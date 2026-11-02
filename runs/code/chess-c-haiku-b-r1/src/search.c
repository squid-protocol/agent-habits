/* Search: iterative deepening, PVS alpha-beta, quiescence, TT, null-move and LMR. */
#define _POSIX_C_SOURCE 200809L

#include "search.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define MAXPLY 256
#define INF 32000
#define MATE 30000
#define MATE_BOUND 29000
#define MAX_DEPTH 99
#define TT_BITS 20

enum { TT_EXACT = 1, TT_LOWER = 2, TT_UPPER = 3 };

typedef struct {
  U64 key;
  int32_t score;
  Move move;
  int8_t depth;
  uint8_t flag; /* 0 = empty */
} TTEntry;

static TTEntry *tt;
static U64 tt_mask;
static atomic_bool g_stop;

static const int VAL[6] = {100, 320, 330, 500, 900, 0};
static const int PH[6] = {0, 1, 1, 2, 4, 0};

/* Piece-square tables, written rank 8 first (index 0 = a8). White uses sq ^ 56, black uses sq. */
static const int PST[6][64] = {
    {0, 0, 0, 0, 0, 0, 0, 0,          50, 50, 50, 50, 50, 50, 50, 50,   10, 10, 20, 30, 30, 20, 10, 10,
     5, 5, 10, 25, 25, 10, 5, 5,      0, 0, 0, 20, 20, 0, 0, 0,         5, -5, -10, 0, 0, -10, -5, 5,
     5, 10, 10, -20, -20, 10, 10, 5,  0, 0, 0, 0, 0, 0, 0, 0},
    {-50, -40, -30, -30, -30, -30, -40, -50, -40, -20, 0, 0, 0, 0, -20, -40, -30, 0, 10, 15, 15, 10, 0, -30,
     -30, 5, 15, 20, 20, 15, 5, -30,       -30, 0, 15, 20, 20, 15, 0, -30,   -30, 5, 10, 15, 15, 10, 5, -30,
     -40, -20, 0, 5, 5, 0, -20, -40,       -50, -40, -30, -30, -30, -30, -40, -50},
    {-20, -10, -10, -10, -10, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 10, 10, 5, 0, -10,
     -10, 5, 5, 10, 10, 5, 5, -10,           -10, 0, 10, 10, 10, 10, 0, -10, -10, 10, 10, 10, 10, 10, 10, -10,
     -10, 5, 0, 0, 0, 0, 5, -10,             -20, -10, -10, -10, -10, -10, -10, -20},
    {0, 0, 0, 0, 0, 0, 0, 0,          5, 10, 10, 10, 10, 10, 10, 5,    -5, 0, 0, 0, 0, 0, 0, -5,
     -5, 0, 0, 0, 0, 0, 0, -5,        -5, 0, 0, 0, 0, 0, 0, -5,        -5, 0, 0, 0, 0, 0, 0, -5,
     -5, 0, 0, 0, 0, 0, 0, -5,        0, 0, 0, 5, 5, 0, 0, 0},
    {-20, -10, -10, -5, -5, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 5, 5, 5, 0, -10,
     -5, 0, 5, 5, 5, 5, 0, -5,              0, 0, 5, 5, 5, 5, 0, -5,   -10, 5, 5, 5, 5, 5, 0, -10,
     -10, 0, 5, 0, 0, 0, 0, -10,            -20, -10, -10, -5, -5, -10, -10, -20},
    {-30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30,
     -30, -40, -40, -50, -50, -40, -40, -30, -20, -30, -30, -40, -40, -30, -30, -20, -10, -20, -20, -20, -20, -20, -20, -10,
     20, 20, 0, 0, 0, 0, 20, 20,           20, 30, 10, 0, 0, 10, 30, 20},
};
static const int KING_EG[64] = {
    -50, -40, -30, -20, -20, -30, -40, -50, -30, -20, -10, 0, 0, -10, -20, -30, -30, -10, 20, 30, 30, 20, -10, -30,
    -30, -10, 30, 40, 40, 30, -10, -30,     -30, -10, 30, 40, 40, 30, -10, -30, -30, -10, 20, 30, 30, 20, -10, -30,
    -30, -30, 0, 0, 0, 0, -30, -30,         -50, -30, -30, -30, -30, -30, -30, -50};

static struct {
  U64 hist[SEARCH_HIST_CAP];
  int histn;
  Move killers[MAXPLY][2];
  int history[2][4096];
  U64 nodes;
  bool aborted;
  bool use_time;
  long long start_ms, deadline;
  Move root_best;
} S;

static long long now_ms(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

void search_init(void) {
  tt = calloc((size_t)1 << TT_BITS, sizeof *tt);
  tt_mask = ((U64)1 << TT_BITS) - 1;
}

void search_clear(void) {
  if (tt) memset(tt, 0, ((size_t)1 << TT_BITS) * sizeof *tt);
}

void search_stop(void) { atomic_store(&g_stop, true); }
void search_reset_stop(void) { atomic_store(&g_stop, false); }

static void check_time(void) {
  if (atomic_load(&g_stop)) S.aborted = true;
  else if (S.use_time && now_ms() >= S.deadline) S.aborted = true;
}

static int evaluate(const Position *p) {
  int mg = 0, eg = 0, ph = 0;
  for (int sq = 0; sq < 64; sq++) {
    int pc = p->mailbox[sq];
    if (pc == NO_PIECE) continue;
    int c = pc / 6, t = pc % 6;
    int idx = c == WHITE ? (sq ^ 56) : sq;
    int sign = c == WHITE ? 1 : -1;
    mg += sign * (VAL[t] + PST[t][idx]);
    eg += sign * (VAL[t] + (t == KING ? KING_EG[idx] : PST[t][idx]));
    ph += PH[t];
  }
  if (ph > 24) ph = 24;
  int score = (mg * ph + eg * (24 - ph)) / 24;
  return p->side == WHITE ? score : -score;
}

static bool has_nonpawn(const Position *p, int side) {
  return (p->pieces[side][KNIGHT] | p->pieces[side][BISHOP] | p->pieces[side][ROOK] | p->pieces[side][QUEEN]) != 0;
}

static bool is_insufficient(const Position *p) {
  U64 heavy = p->pieces[WHITE][PAWN] | p->pieces[BLACK][PAWN] | p->pieces[WHITE][ROOK] | p->pieces[BLACK][ROOK] |
              p->pieces[WHITE][QUEEN] | p->pieces[BLACK][QUEEN];
  if (heavy) return false;
  int minors = __builtin_popcountll(p->pieces[WHITE][KNIGHT] | p->pieces[WHITE][BISHOP] |
                                    p->pieces[BLACK][KNIGHT] | p->pieces[BLACK][BISHOP]);
  return minors <= 1;
}

/* Is the current position (S.hist[histn-1]) a repetition of an earlier one within the reversible window? */
static bool is_repeat(const Position *p) {
  int lo = S.histn - 1 - p->halfmove;
  if (lo < 0) lo = 0;
  for (int i = S.histn - 3; i >= lo; i -= 2)
    if (S.hist[i] == p->hash) return true;
  return false;
}

static inline int score_to_tt(int s, int ply) {
  if (s >= MATE_BOUND) return s + ply;
  if (s <= -MATE_BOUND) return s - ply;
  return s;
}

static inline int score_from_tt(int s, int ply) {
  if (s >= MATE_BOUND) return s - ply;
  if (s <= -MATE_BOUND) return s + ply;
  return s;
}

static void score_moves(const Position *p, const Move *list, int n, Move ttm, int ply, int *sc) {
  int us = p->side;
  for (int i = 0; i < n; i++) {
    Move m = list[i];
    int from = MFROM(m), to = MTO(m), pr = MPROMO(m);
    unsigned fl = MFLAGS(m);
    if (m == ttm) {
      sc[i] = 2000000;
    } else if (fl & (F_CAP | F_EP)) {
      int vt = (fl & F_EP) ? PAWN : p->mailbox[to] % 6;
      int at = p->mailbox[from] % 6;
      sc[i] = 1000000 + VAL[vt] * 10 - VAL[at] / 10;
    } else if (pr) {
      sc[i] = 950000 + VAL[pr];
    } else if (ply >= 0 && m == S.killers[ply][0]) {
      sc[i] = 900000;
    } else if (ply >= 0 && m == S.killers[ply][1]) {
      sc[i] = 890000;
    } else {
      sc[i] = S.history[us][from * 64 + to];
    }
  }
}

static void pick(Move *list, int *sc, int n, int i) {
  int best = i;
  for (int j = i + 1; j < n; j++)
    if (sc[j] > sc[best]) best = j;
  if (best != i) {
    Move tm = list[i];
    list[i] = list[best];
    list[best] = tm;
    int ts = sc[i];
    sc[i] = sc[best];
    sc[best] = ts;
  }
}

static int qsearch(const Position *pos, int alpha, int beta, int ply) {
  S.nodes++;
  if ((S.nodes & 2047) == 0) check_time();
  if (S.aborted) return 0;
  if (ply >= MAXPLY - 2) return evaluate(pos);

  int us = pos->side;
  bool incheck = in_check(pos, us);
  int best;
  if (!incheck) {
    best = evaluate(pos);
    if (best >= beta) return best;
    if (best > alpha) alpha = best;
  } else {
    best = -MATE + ply;
  }

  Move list[256];
  int sc[256];
  int n = gen_moves(pos, list, !incheck); /* in check, all evasions are needed */
  score_moves(pos, list, n, MOVE_NONE, -1, sc);
  int legal = 0;
  for (int i = 0; i < n; i++) {
    pick(list, sc, n, i);
    Position child;
    make_move(pos, &child, list[i]);
    if (in_check(&child, us)) continue;
    legal++;
    int s = -qsearch(&child, -beta, -alpha, ply + 1);
    if (S.aborted) return 0;
    if (s > best) {
      best = s;
      if (s > alpha) {
        alpha = s;
        if (alpha >= beta) break;
      }
    }
  }
  if (incheck && legal == 0) return -MATE + ply;
  return best;
}

static int nega(const Position *pos, int alpha, int beta, int depth, int ply, bool allow_null) {
  S.nodes++;
  if ((S.nodes & 2047) == 0) check_time();
  if (S.aborted) return 0;
  if (ply >= MAXPLY - 2) return evaluate(pos);

  bool root = ply == 0;
  if (!root) {
    if (pos->halfmove >= 100 || is_insufficient(pos) || is_repeat(pos)) return 0;
  }
  if (depth <= 0) return qsearch(pos, alpha, beta, ply);

  int us = pos->side;
  bool incheck = in_check(pos, us);

  TTEntry *e = &tt[pos->hash & tt_mask];
  Move ttm = MOVE_NONE;
  if (e->flag && e->key == pos->hash) {
    ttm = e->move;
    if (!root && e->depth >= depth) {
      int s = score_from_tt(e->score, ply);
      if (e->flag == TT_EXACT || (e->flag == TT_LOWER && s >= beta) || (e->flag == TT_UPPER && s <= alpha))
        return s;
    }
  }

  if (!root && !incheck && allow_null && depth >= 3 && beta < MATE_BOUND && has_nonpawn(pos, us) &&
      evaluate(pos) >= beta) {
    Position nul;
    make_null(pos, &nul);
    int R = depth >= 6 ? 3 : 2;
    S.hist[S.histn++] = nul.hash;
    int s = -nega(&nul, -beta, -beta + 1, depth - 1 - R, ply + 1, false);
    S.histn--;
    if (S.aborted) return 0;
    if (s >= beta) return beta;
  }

  Move list[256];
  int sc[256];
  int n = gen_moves(pos, list, false);
  score_moves(pos, list, n, ttm, ply, sc);

  int alpha0 = alpha, best = -INF, legal = 0;
  Move bestm = MOVE_NONE;
  for (int i = 0; i < n; i++) {
    pick(list, sc, n, i);
    Move m = list[i];
    Position child;
    make_move(pos, &child, m);
    if (in_check(&child, us)) continue;
    legal++;

    unsigned fl = MFLAGS(m);
    bool quiet = !(fl & (F_CAP | F_EP)) && !MPROMO(m);
    bool gives = in_check(&child, us ^ 1);
    int nd = depth - 1 + ((gives && ply < MAXPLY / 2) ? 1 : 0);
    int red = 0;
    if (quiet && !incheck && !gives && depth >= 3 && legal > 3) red = legal > 8 ? 2 : 1;

    S.hist[S.histn++] = child.hash;
    int s;
    if (legal == 1) {
      s = -nega(&child, -beta, -alpha, nd, ply + 1, true);
    } else {
      s = -nega(&child, -alpha - 1, -alpha, nd - red, ply + 1, true);
      if (s > alpha && red) s = -nega(&child, -alpha - 1, -alpha, nd, ply + 1, true);
      if (s > alpha && s < beta) s = -nega(&child, -beta, -alpha, nd, ply + 1, true);
    }
    S.histn--;
    if (S.aborted) return 0;

    if (s > best) {
      best = s;
      bestm = m;
      if (s > alpha) {
        alpha = s;
        if (root) S.root_best = m;
        if (alpha >= beta) {
          if (quiet) {
            if (S.killers[ply][0] != m) {
              S.killers[ply][1] = S.killers[ply][0];
              S.killers[ply][0] = m;
            }
            int *h = &S.history[us][MFROM(m) * 64 + MTO(m)];
            *h += depth * depth;
            if (*h > 800000) {
              for (int c = 0; c < 2; c++)
                for (int k = 0; k < 4096; k++) S.history[c][k] /= 2;
            }
          }
          break;
        }
      }
    }
  }

  if (legal == 0) return incheck ? -MATE + ply : 0;

  e->key = pos->hash;
  e->score = score_to_tt(best, ply);
  e->move = bestm;
  e->depth = (int8_t)depth;
  e->flag = best >= beta ? TT_LOWER : best <= alpha0 ? TT_UPPER : TT_EXACT;
  return best;
}

static Move first_legal(const Position *root) {
  Move list[256];
  int n = gen_moves(root, list, false);
  for (int i = 0; i < n; i++) {
    Position c;
    make_move(root, &c, list[i]);
    if (!in_check(&c, root->side)) return list[i];
  }
  return MOVE_NONE;
}

static void report(int depth, int score, Move best) {
  long long elapsed = now_ms() - S.start_ms;
  if (elapsed < 1) elapsed = 1;
  char mv[6];
  move_to_str(best, mv);
  if (score > MATE_BOUND)
    out_printf("info depth %d score mate %d nodes %llu nps %llu time %lld pv %s\n", depth, (MATE - score + 1) / 2,
               (unsigned long long)S.nodes, (unsigned long long)(S.nodes * 1000 / (U64)elapsed), elapsed, mv);
  else if (score < -MATE_BOUND)
    out_printf("info depth %d score mate %d nodes %llu nps %llu time %lld pv %s\n", depth, -(MATE + score) / 2,
               (unsigned long long)S.nodes, (unsigned long long)(S.nodes * 1000 / (U64)elapsed), elapsed, mv);
  else
    out_printf("info depth %d score cp %d nodes %llu nps %llu time %lld pv %s\n", depth, score,
               (unsigned long long)S.nodes, (unsigned long long)(S.nodes * 1000 / (U64)elapsed), elapsed, mv);
}

Move search_think(const Position *root, const U64 *hist, int histn, const Limits *lim) {
  memset(S.killers, 0, sizeof S.killers);
  memset(S.history, 0, sizeof S.history);
  S.nodes = 0;
  S.aborted = false;
  S.root_best = MOVE_NONE;

  S.histn = 0;
  int keep = histn < SEARCH_HIST_CAP - MAXPLY - 8 ? histn : SEARCH_HIST_CAP - MAXPLY - 8;
  for (int i = 0; i < keep; i++) S.hist[S.histn++] = hist[i];
  if (S.histn == 0 || S.hist[S.histn - 1] != root->hash) S.hist[S.histn++] = root->hash;

  S.start_ms = now_ms();
  S.use_time = false;
  if (lim->movetime > 0) {
    long long budget = lim->movetime - lim->movetime / 20 - 5;
    if (budget < 1) budget = 1;
    S.use_time = true;
    S.deadline = S.start_ms + budget;
  } else if (lim->has_clock && !lim->infinite) {
    long long my = root->side == WHITE ? lim->wtime : lim->btime;
    long long inc = root->side == WHITE ? lim->winc : lim->binc;
    long long budget = my / 30 + inc * 3 / 4;
    if (budget > my - 50) budget = my - 50;
    if (budget < 5) budget = 5;
    S.use_time = true;
    S.deadline = S.start_ms + budget;
  }

  Move best = first_legal(root);
  if (!best) return MOVE_NONE;

  int maxd = lim->depth > 0 ? lim->depth : MAX_DEPTH;
  if (maxd > MAX_DEPTH) maxd = MAX_DEPTH;
  for (int d = 1; d <= maxd; d++) {
    S.root_best = MOVE_NONE;
    int score = nega(root, -INF, INF, d, 0, true);
    if (S.aborted) break;
    if (S.root_best) best = S.root_best;
    report(d, score, best);
  }
  return best;
}
