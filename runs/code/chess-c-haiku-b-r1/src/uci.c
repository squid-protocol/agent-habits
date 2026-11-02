/* UCI front end: reads commands on stdin, runs searches on a worker thread so that
 * `stop` and `quit` are obeyed while thinking. */
#define _POSIX_C_SOURCE 200809L

#include "chess.h"
#include "search.h"

#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MAX_TOKENS 512

static pthread_mutex_t out_mtx = PTHREAD_MUTEX_INITIALIZER;

void out_printf(const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  pthread_mutex_lock(&out_mtx);
  vprintf(fmt, ap);
  fflush(stdout);
  pthread_mutex_unlock(&out_mtx);
  va_end(ap);
}

/* Game state as set by `position`. */
static Position game_pos;
static U64 game_hist[SEARCH_HIST_CAP];
static int game_histn;

/* Job handed to the search thread. The main thread never touches it while the thread runs. */
typedef struct {
  Position pos;
  U64 hist[SEARCH_HIST_CAP];
  int histn;
  Limits lim;
} Job;
static Job job;
static pthread_t search_thr;
static bool search_active = false;

static void join_search(void) {
  if (search_active) {
    pthread_join(search_thr, NULL);
    search_active = false;
  }
}

static void stop_search(void) {
  search_stop();
  join_search();
}

static void *search_main(void *arg) {
  Job *j = arg;
  Move m = search_think(&j->pos, j->hist, j->histn, &j->lim);
  char buf[6] = "0000";
  if (m) move_to_str(m, buf);
  out_printf("bestmove %s\n", buf);
  return NULL;
}

static void set_startpos(void) {
  pos_from_fen(&game_pos, START_FEN);
  game_histn = 0;
  game_hist[game_histn++] = game_pos.hash;
}

static void parse_position(int argc, char **argv) {
  int i = 1;
  if (i < argc && strcmp(argv[i], "startpos") == 0) {
    set_startpos();
    i++;
  } else if (i < argc && strcmp(argv[i], "fen") == 0) {
    char fen[512] = "";
    int j = i + 1;
    while (j < argc && strcmp(argv[j], "moves") != 0) {
      if (strlen(fen) + strlen(argv[j]) + 2 < sizeof fen) {
        if (fen[0]) strcat(fen, " ");
        strcat(fen, argv[j]);
      }
      j++;
    }
    if (!pos_from_fen(&game_pos, fen)) {
      set_startpos();
      return;
    }
    game_histn = 0;
    game_hist[game_histn++] = game_pos.hash;
    i = j;
  } else {
    return;
  }

  if (i < argc && strcmp(argv[i], "moves") == 0) {
    for (int k = i + 1; k < argc; k++) {
      Move m = parse_move(&game_pos, argv[k]);
      if (!m) break;
      Position next;
      make_move(&game_pos, &next, m);
      game_pos = next;
      if (game_histn < SEARCH_HIST_CAP - 300) game_hist[game_histn++] = game_pos.hash;
    }
  }
}

static void run_perft(int depth) {
  if (depth <= 0) {
    out_printf("Nodes searched: 1\n");
    return;
  }
  Move list[256];
  int n = gen_moves(&game_pos, list, false);
  U64 total = 0;
  for (int i = 0; i < n; i++) {
    Position child;
    make_move(&game_pos, &child, list[i]);
    if (in_check(&child, game_pos.side)) continue;
    U64 cnt = perft(&child, depth - 1);
    char buf[6];
    move_to_str(list[i], buf);
    out_printf("%s: %llu\n", buf, (unsigned long long)cnt);
    total += cnt;
  }
  out_printf("Nodes searched: %llu\n", (unsigned long long)total);
}

static void parse_go(int argc, char **argv, Limits *lim, bool *perft, int *perft_depth) {
  memset(lim, 0, sizeof *lim);
  *perft = false;
  bool any = false;
  for (int i = 1; i < argc; i++) {
    const char *t = argv[i];
    bool has_next = i + 1 < argc;
    if (strcmp(t, "perft") == 0 && has_next) {
      *perft = true;
      *perft_depth = atoi(argv[++i]);
      any = true;
    } else if (strcmp(t, "depth") == 0 && has_next) {
      lim->depth = atoi(argv[++i]);
      any = true;
    } else if (strcmp(t, "movetime") == 0 && has_next) {
      lim->movetime = atoll(argv[++i]);
      any = true;
    } else if (strcmp(t, "wtime") == 0 && has_next) {
      lim->wtime = atoll(argv[++i]);
      lim->has_clock = true;
      any = true;
    } else if (strcmp(t, "btime") == 0 && has_next) {
      lim->btime = atoll(argv[++i]);
      lim->has_clock = true;
      any = true;
    } else if (strcmp(t, "winc") == 0 && has_next) {
      lim->winc = atoll(argv[++i]);
    } else if (strcmp(t, "binc") == 0 && has_next) {
      lim->binc = atoll(argv[++i]);
    } else if (strcmp(t, "movestogo") == 0 && has_next) {
      i++;
    } else if (strcmp(t, "infinite") == 0 || strcmp(t, "ponder") == 0) {
      lim->infinite = true;
      any = true;
    }
  }
  if (!any) lim->infinite = true;
}

static void cmd_go(int argc, char **argv) {
  stop_search();
  Limits lim;
  bool perft_mode = false;
  int perft_depth = 0;
  parse_go(argc, argv, &lim, &perft_mode, &perft_depth);

  if (perft_mode) {
    run_perft(perft_depth);
    return;
  }

  job.pos = game_pos;
  memcpy(job.hist, game_hist, sizeof(U64) * (size_t)game_histn);
  job.histn = game_histn;
  job.lim = lim;
  search_reset_stop();
  if (pthread_create(&search_thr, NULL, search_main, &job) == 0) {
    search_active = true;
  } else {
    /* Could not start a thread: search synchronously. */
    search_main(&job);
  }
}

int main(void) {
  board_init();
  search_init();
  set_startpos();

  char *line = NULL;
  size_t cap = 0;
  ssize_t len;
  while ((len = getline(&line, &cap, stdin)) != -1) {
    (void)len;
    char *argv[MAX_TOKENS];
    int argc = 0;
    for (char *tok = strtok(line, " \t\r\n"); tok && argc < MAX_TOKENS; tok = strtok(NULL, " \t\r\n"))
      argv[argc++] = tok;
    if (argc == 0) continue;

    const char *cmd = argv[0];
    if (strcmp(cmd, "uci") == 0) {
      out_printf("id name CChess 1.0\n");
      out_printf("id author Claude agent\n");
      out_printf("uciok\n");
    } else if (strcmp(cmd, "isready") == 0) {
      out_printf("readyok\n");
    } else if (strcmp(cmd, "ucinewgame") == 0) {
      stop_search();
      search_clear();
      set_startpos();
    } else if (strcmp(cmd, "position") == 0) {
      stop_search();
      parse_position(argc, argv);
    } else if (strcmp(cmd, "go") == 0) {
      cmd_go(argc, argv);
    } else if (strcmp(cmd, "stop") == 0) {
      stop_search();
    } else if (strcmp(cmd, "quit") == 0) {
      break;
    }
    /* setoption, debug, register and unknown commands are ignored. */
  }

  stop_search();
  free(line);
  return 0;
}
