#define _POSIX_C_SOURCE 200809L
#include <ctype.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "chess.h"

#define MAX_TOKENS 512
#define UNDO_SAFETY_MARGIN 256

static Position *pos;
static SearchLimits limits;
static pthread_t search_thread;
static bool searching = false;

static void reply(const char *s) {
    fputs(s, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void *search_main(void *arg) {
    (void)arg;
    search_think(pos, &limits);
    return NULL;
}

static void stop_search(void) {
    if (searching) {
        search_request_stop();
        pthread_join(search_thread, NULL);
        searching = false;
    }
}

static void start_search(void) {
    stop_search();
    search_clear_stop();
    if (pthread_create(&search_thread, NULL, search_main, NULL) == 0)
        searching = true;
    else
        search_think(pos, &limits);  /* no thread available: search synchronously */
}

static int tokenize(char *line, char **tok, int max) {
    int n = 0;
    char *s = line;
    while (n < max) {
        while (*s && isspace((unsigned char)*s)) s++;
        if (!*s) break;
        tok[n++] = s;
        while (*s && !isspace((unsigned char)*s)) s++;
        if (*s) *s++ = '\0';
    }
    return n;
}

static void cmd_position(char **tok, int n) {
    int i = 1;
    if (i < n && strcmp(tok[i], "startpos") == 0) {
        pos_startpos(pos);
        i++;
    } else if (i < n && strcmp(tok[i], "fen") == 0) {
        char fen[512] = "";
        i++;
        while (i < n && strcmp(tok[i], "moves") != 0) {
            if (strlen(fen) + strlen(tok[i]) + 2 >= sizeof fen) break;
            strcat(fen, tok[i]);
            strcat(fen, " ");
            i++;
        }
        if (!pos_from_fen(pos, fen)) pos_startpos(pos);
    } else {
        return;
    }

    if (i < n && strcmp(tok[i], "moves") == 0) {
        for (i++; i < n; i++) {
            if (pos->nundo >= MAX_UNDO - UNDO_SAFETY_MARGIN) break;
            Move m = parse_move(pos, tok[i]);
            if (m == MOVE_NONE) break;
            pos_make(pos, m);
        }
    }
}

static void run_perft(int depth) {
    uint64_t total = 0;
    if (depth < 1) {
        printf("Nodes searched: 1\n");
        fflush(stdout);
        return;
    }
    MoveList list;
    gen_moves(pos, &list, false);
    char buf[6];
    for (int i = 0; i < list.count; i++) {
        Move m = list.moves[i];
        if (!make_if_legal(pos, m)) continue;
        uint64_t n = perft(pos, depth - 1);
        pos_unmake(pos);
        total += n;
        move_to_str(m, buf);
        printf("%s: %llu\n", buf, (unsigned long long)n);
    }
    printf("Nodes searched: %llu\n", (unsigned long long)total);
    fflush(stdout);
}

static void cmd_go(char **tok, int n) {
    stop_search();
    if (n > 1 && strcmp(tok[1], "perft") == 0) {
        run_perft(n > 2 ? atoi(tok[2]) : 1);
        return;
    }

    int depth = 0;
    long movetime = 0, wtime = -1, btime = -1, winc = 0, binc = 0, movestogo = 0;
    for (int i = 1; i < n; i++) {
        const char *t = tok[i];
        if (i + 1 >= n) break;
        if (strcmp(t, "depth") == 0) depth = atoi(tok[++i]);
        else if (strcmp(t, "movetime") == 0) movetime = atol(tok[++i]);
        else if (strcmp(t, "wtime") == 0) wtime = atol(tok[++i]);
        else if (strcmp(t, "btime") == 0) btime = atol(tok[++i]);
        else if (strcmp(t, "winc") == 0) winc = atol(tok[++i]);
        else if (strcmp(t, "binc") == 0) binc = atol(tok[++i]);
        else if (strcmp(t, "movestogo") == 0) movestogo = atol(tok[++i]);
    }

    limits.max_depth = 0;
    limits.soft_ms = 0;
    limits.hard_ms = 0;
    if (depth > 0) limits.max_depth = depth;

    const bool white = pos->side == WHITE;
    const long mytime = white ? wtime : btime;
    const long myinc = white ? winc : binc;
    if (movetime > 0) {
        double ms = movetime - 20.0;
        if (ms < 5.0) ms = 5.0;
        limits.soft_ms = ms;
        limits.hard_ms = ms;
    } else if (mytime >= 0) {
        const double t = (double)mytime, inc = (double)myinc;
        const double mtg = movestogo > 0 ? (double)movestogo : 30.0;
        double soft = t / mtg + inc * 0.7 - 10.0;
        double hard = soft * 2.0;
        if (hard > t * 0.4) hard = t * 0.4;
        if (soft > hard) soft = hard;
        if (soft < 1.0) soft = 1.0;
        if (hard < 2.0) hard = 2.0;
        limits.soft_ms = soft;
        limits.hard_ms = hard;
    }

    start_search();
}

int main(void) {
    board_init();
    search_init();
    pos = malloc(sizeof *pos);
    if (!pos) return 1;
    pos_startpos(pos);

    static char line[8192];
    while (fgets(line, sizeof line, stdin)) {
        char *tok[MAX_TOKENS];
        const int n = tokenize(line, tok, MAX_TOKENS);
        if (n == 0) continue;
        const char *cmd = tok[0];

        if (strcmp(cmd, "uci") == 0) {
            reply("id name ChessC");
            reply("id author Claude");
            reply("uciok");
        } else if (strcmp(cmd, "isready") == 0) {
            reply("readyok");
        } else if (strcmp(cmd, "ucinewgame") == 0) {
            stop_search();
            search_clear();
            pos_startpos(pos);
        } else if (strcmp(cmd, "position") == 0) {
            stop_search();
            cmd_position(tok, n);
        } else if (strcmp(cmd, "go") == 0) {
            cmd_go(tok, n);
        } else if (strcmp(cmd, "stop") == 0) {
            stop_search();
        } else if (strcmp(cmd, "quit") == 0) {
            break;
        }
        /* setoption, debug, register, ponderhit and unknown commands are ignored. */
    }

    stop_search();
    free(pos);
    return 0;
}
