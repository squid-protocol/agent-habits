#define _POSIX_C_SOURCE 200809L
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "chess.h"

#define MAX_PLY 128
#define MAX_DEPTH 64
#define INF 32000
#define MATE_SCORE 30000
#define MATE_BOUND (MATE_SCORE - MAX_PLY)
#define TT_SIZE (1u << 20)

enum { TT_NONE = 0, TT_EXACT, TT_LOWER, TT_UPPER };

typedef struct {
    uint64_t key;
    int score;
    int depth;
    int flag;
    Move move;
} TTEntry;

static TTEntry *tt = NULL;
static uint64_t tt_mask = 0;
static Move killers[MAX_PLY][2];
static int history[2][128][128];
static atomic_bool stop_flag = false;
static uint64_t nodes = 0;
static double start_ms = 0, hard_ms = 0, soft_ms = 0;

static double now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

void search_init(void) {
    if (!tt) tt = calloc(TT_SIZE, sizeof *tt);
    tt_mask = TT_SIZE - 1;
}

void search_clear(void) {
    if (tt) memset(tt, 0, TT_SIZE * sizeof *tt);
}

void search_clear_stop(void) { atomic_store(&stop_flag, false); }
void search_request_stop(void) { atomic_store(&stop_flag, true); }

static inline bool stopped(void) {
    if ((nodes & 2047) == 0 && hard_ms > 0 && now_ms() - start_ms >= hard_ms)
        atomic_store(&stop_flag, true);
    return atomic_load(&stop_flag);
}

static int score_to_tt(int s, int ply) {
    if (s >= MATE_BOUND) return s + ply;
    if (s <= -MATE_BOUND) return s - ply;
    return s;
}

static int score_from_tt(int s, int ply) {
    if (s >= MATE_BOUND) return s - ply;
    if (s <= -MATE_BOUND) return s + ply;
    return s;
}

/* Ordering: TT move, captures (MVV-LVA), promotions, killers, then history. */
static void score_moves(const Position *p, MoveList *l, Move tt_move, int ply) {
    for (int i = 0; i < l->count; i++) {
        const Move m = l->moves[i];
        const int from = MOVE_FROM(m), to = MOVE_TO(m), promo = MOVE_PROMO(m);
        const int pc = p->board[from], victim = p->board[to];
        int s;
        if (m == tt_move) {
            s = 2000000;
        } else if (victim || (TYPE_OF(pc) == PAWN && to == p->ep)) {
            const int vt = victim ? TYPE_OF(victim) : PAWN;
            s = 1000000 + PIECE_VALUE[vt] * 16 - TYPE_OF(pc);
        } else if (promo) {
            s = 900000 + promo;
        } else if (m == killers[ply][0]) {
            s = 800000;
        } else if (m == killers[ply][1]) {
            s = 790000;
        } else {
            s = history[p->side][from][to];
        }
        l->scores[i] = s;
    }
}

static void pick_best(MoveList *l, int i) {
    int best = i;
    for (int j = i + 1; j < l->count; j++)
        if (l->scores[j] > l->scores[best]) best = j;
    if (best != i) {
        Move tm = l->moves[i]; l->moves[i] = l->moves[best]; l->moves[best] = tm;
        int ts = l->scores[i]; l->scores[i] = l->scores[best]; l->scores[best] = ts;
    }
}

static void update_quiet(const Position *p, Move m, int depth, int ply) {
    if (killers[ply][0] != m) {
        killers[ply][1] = killers[ply][0];
        killers[ply][0] = m;
    }
    int *h = &history[p->side][MOVE_FROM(m)][MOVE_TO(m)];
    *h += depth * depth;
    if (*h > 600000) {
        for (int s = 0; s < 2; s++)
            for (int f = 0; f < 128; f++)
                for (int t = 0; t < 128; t++) history[s][f][t] /= 2;
    }
}

static int qsearch(Position *p, int alpha, int beta, int ply) {
    nodes++;
    if (stopped()) return 0;
    if (ply >= MAX_PLY - 1) return evaluate(p);

    const bool in_check = pos_in_check(p);
    int best;
    if (in_check) {
        best = -INF;
    } else {
        best = evaluate(p);
        if (best >= beta) return best;
        if (best > alpha) alpha = best;
    }

    MoveList list;
    gen_moves(p, &list, !in_check);  /* in check: every evasion; otherwise captures and promotions */
    score_moves(p, &list, MOVE_NONE, ply);

    int legal = 0;
    for (int i = 0; i < list.count; i++) {
        pick_best(&list, i);
        const Move m = list.moves[i];
        if (!make_if_legal(p, m)) continue;
        legal++;
        const int s = -qsearch(p, -beta, -alpha, ply + 1);
        pos_unmake(p);
        if (stopped()) return 0;
        if (s > best) {
            best = s;
            if (s > alpha) {
                alpha = s;
                if (alpha >= beta) break;
            }
        }
    }
    if (in_check && legal == 0) return -MATE_SCORE + ply;
    return best;
}

static int negamax(Position *p, int depth, int alpha, int beta, int ply, bool allow_null) {
    nodes++;
    if (stopped()) return 0;
    if (ply > 0 && (p->half >= 100 || pos_is_repetition(p))) return 0;
    if (ply >= MAX_PLY - 1) return evaluate(p);

    const bool in_check = pos_in_check(p);
    if (in_check) depth++;
    if (depth <= 0) return qsearch(p, alpha, beta, ply);

    const int alpha0 = alpha;
    const bool pv = beta - alpha > 1;

    TTEntry *e = &tt[p->key & tt_mask];
    Move tt_move = MOVE_NONE;
    if (e->flag != TT_NONE && e->key == p->key) {
        tt_move = e->move;
        if (!pv && ply > 0 && e->depth >= depth) {
            const int s = score_from_tt(e->score, ply);
            if (e->flag == TT_EXACT || (e->flag == TT_LOWER && s >= beta) ||
                (e->flag == TT_UPPER && s <= alpha))
                return s;
        }
    }

    /* Null-move pruning. */
    if (!pv && !in_check && allow_null && depth >= 3 && pos_has_non_pawn(p, p->side) &&
        evaluate(p) >= beta) {
        const int r = depth >= 6 ? 3 : 2;
        pos_make_null(p);
        const int s = -negamax(p, depth - 1 - r, -beta, -beta + 1, ply + 1, false);
        pos_unmake_null(p);
        if (stopped()) return 0;
        if (s >= beta) return beta;
    }

    MoveList list;
    gen_moves(p, &list, false);
    score_moves(p, &list, tt_move, ply);

    int best = -INF;
    Move best_move = MOVE_NONE;
    int legal = 0;
    for (int i = 0; i < list.count; i++) {
        pick_best(&list, i);
        const Move m = list.moves[i];
        const int from = MOVE_FROM(m), to = MOVE_TO(m);
        const int pc = p->board[from];
        const bool capture = p->board[to] != 0 || (TYPE_OF(pc) == PAWN && to == p->ep);
        const bool promo = MOVE_PROMO(m) != 0;

        if (!make_if_legal(p, m)) continue;
        legal++;
        const bool gives_check = pos_in_check(p);

        int s;
        if (legal == 1) {
            s = -negamax(p, depth - 1, -beta, -alpha, ply + 1, true);
        } else {
            int red = 0;
            if (depth >= 3 && legal > 3 && !capture && !promo && !in_check && !gives_check)
                red = (legal > 6 && depth >= 5) ? 2 : 1;
            s = -negamax(p, depth - 1 - red, -alpha - 1, -alpha, ply + 1, true);
            if (red && s > alpha)
                s = -negamax(p, depth - 1, -alpha - 1, -alpha, ply + 1, true);
            if (s > alpha && s < beta)
                s = -negamax(p, depth - 1, -beta, -alpha, ply + 1, true);
        }
        pos_unmake(p);
        if (stopped()) return 0;

        if (s > best) {
            best = s;
            best_move = m;
            if (s > alpha) {
                alpha = s;
                if (alpha >= beta) {
                    if (!capture && !promo) update_quiet(p, m, depth, ply);
                    break;
                }
            }
        }
    }

    if (legal == 0) return in_check ? -MATE_SCORE + ply : 0;

    const int flag = best >= beta ? TT_LOWER : (best > alpha0 ? TT_EXACT : TT_UPPER);
    if (e->key != p->key || e->depth <= depth || e->flag == TT_NONE) {
        e->key = p->key;
        e->score = score_to_tt(best, ply);
        e->depth = depth;
        e->flag = flag;
        e->move = best_move;
    }
    return best;
}

static void print_info(int depth, int score, Move m) {
    char buf[6];
    move_to_str(m, buf);
    if (score > MATE_BOUND)
        printf("info depth %d score mate %d", depth, (MATE_SCORE - score + 1) / 2);
    else if (score < -MATE_BOUND)
        printf("info depth %d score mate %d", depth, -(MATE_SCORE + score + 1) / 2);
    else
        printf("info depth %d score cp %d", depth, score);
    printf(" nodes %llu time %.0f pv %s\n", (unsigned long long)nodes, now_ms() - start_ms, buf);
    fflush(stdout);
}

void search_think(Position *p, const SearchLimits *lim) {
    nodes = 0;
    memset(killers, 0, sizeof killers);
    memset(history, 0, sizeof history);
    start_ms = now_ms();
    hard_ms = lim->hard_ms;
    soft_ms = lim->soft_ms;
    const int max_depth = lim->max_depth > 0 && lim->max_depth <= MAX_DEPTH ? lim->max_depth : MAX_DEPTH;

    MoveList root;
    gen_moves(p, &root, false);
    Move legal_moves[MAX_MOVES];
    int nlegal = 0;
    for (int i = 0; i < root.count; i++)
        if (make_if_legal(p, root.moves[i])) {
            pos_unmake(p);
            legal_moves[nlegal++] = root.moves[i];
        }

    if (nlegal == 0) {
        printf("bestmove 0000\n");
        fflush(stdout);
        return;
    }

    char buf[6];
    Move best = legal_moves[0];
    if (nlegal == 1) {
        move_to_str(best, buf);
        printf("bestmove %s\n", buf);
        fflush(stdout);
        return;
    }

    for (int depth = 1; depth <= max_depth; depth++) {
        MoveList list;
        gen_moves(p, &list, false);
        score_moves(p, &list, best, 0);

        int alpha = -INF, iter_score = -INF;
        Move iter_best = MOVE_NONE;
        int legal = 0;
        bool aborted = false;
        for (int i = 0; i < list.count; i++) {
            pick_best(&list, i);
            const Move m = list.moves[i];
            if (!make_if_legal(p, m)) continue;
            legal++;
            int s;
            if (legal == 1) {
                s = -negamax(p, depth - 1, -INF, INF, 1, true);
            } else {
                s = -negamax(p, depth - 1, -alpha - 1, -alpha, 1, true);
                if (s > alpha) s = -negamax(p, depth - 1, -INF, INF, 1, true);
            }
            pos_unmake(p);
            if (stopped()) {
                aborted = true;
                break;
            }
            if (s > iter_score) {
                iter_score = s;
                iter_best = m;
                if (s > alpha) alpha = s;
            }
        }
        if (aborted) break;

        best = iter_best;
        print_info(depth, iter_score, best);
        if ((iter_score > MATE_BOUND || iter_score < -MATE_BOUND) &&
            MATE_SCORE - (iter_score > 0 ? iter_score : -iter_score) <= depth)
            break;  /* the mate is proven at the depth searched: nothing shorter can exist */
        if (soft_ms > 0 && now_ms() - start_ms >= soft_ms) break;
    }

    move_to_str(best, buf);
    printf("bestmove %s\n", buf);
    fflush(stdout);
}
