#include <string.h>

#include "chess.h"

/* Directions: 0..3 rook-like, 4..7 bishop-like; the king and queen use all eight. */
static const int DIRS[8] = {1, -1, 16, -16, 15, 17, -15, -17};
static const int KNIGHT_OFF[8] = {33, 31, 18, 14, -33, -31, -18, -14};

static void add_move(MoveList *l, int from, int to, int promo) {
    l->moves[l->count++] = MAKE_MOVE(from, to, promo);
}

static void add_promotions(MoveList *l, int from, int to) {
    add_move(l, from, to, QUEEN);
    add_move(l, from, to, ROOK);
    add_move(l, from, to, BISHOP);
    add_move(l, from, to, KNIGHT);
}

/* Pseudo-legal generation; the king-safety test happens in make_if_legal. */
void gen_moves(const Position *p, MoveList *list, bool captures_only) {
    list->count = 0;
    const int side = p->side, enemy = side ^ 1;
    const int fwd = side == WHITE ? 16 : -16;
    const int start_rank = side == WHITE ? 1 : 6;
    const int last_rank = side == WHITE ? 7 : 0;

    for (int rank = 0; rank < 8; rank++)
        for (int file = 0; file < 8; file++) {
            const int from = SQ(file, rank);
            const int pc = p->board[from];
            if (!pc || COLOR_OF(pc) != side) continue;
            const int type = TYPE_OF(pc);

            if (type == PAWN) {
                int to = from + fwd;
                if (ON_BOARD(to) && !p->board[to]) {
                    if (RANK_OF(to) == last_rank) {
                        add_promotions(list, from, to);
                    } else if (!captures_only) {
                        add_move(list, from, to, 0);
                        if (rank == start_rank && !p->board[to + fwd])
                            add_move(list, from, to + fwd, 0);
                    }
                }
                for (int i = 0; i < 2; i++) {
                    const int t = from + fwd + (i == 0 ? -1 : 1);
                    if (!ON_BOARD(t)) continue;
                    const int victim = p->board[t];
                    if (victim && COLOR_OF(victim) == enemy) {
                        if (RANK_OF(t) == last_rank) add_promotions(list, from, t);
                        else add_move(list, from, t, 0);
                    } else if (!victim && t == p->ep) {
                        add_move(list, from, t, 0);
                    }
                }
            } else if (type == KNIGHT || type == KING) {
                const int n = 8;
                for (int i = 0; i < n; i++) {
                    const int to = from + (type == KNIGHT ? KNIGHT_OFF[i] : DIRS[i]);
                    if (!ON_BOARD(to)) continue;
                    const int t = p->board[to];
                    if (!t ? !captures_only : COLOR_OF(t) == enemy) add_move(list, from, to, 0);
                }
                if (type == KING && !captures_only) {
                    const int home = side == WHITE ? SQ(4, 0) : SQ(4, 7);
                    if (from == home && !pos_attacked(p, from, enemy)) {
                        const int rook = PIECE_OF(side, ROOK);
                        const int ks = side == WHITE ? CASTLE_WK : CASTLE_BK;
                        const int qs = side == WHITE ? CASTLE_WQ : CASTLE_BQ;
                        if ((p->castle & ks) && !p->board[from + 1] && !p->board[from + 2] &&
                            p->board[from + 3] == rook && !pos_attacked(p, from + 1, enemy) &&
                            !pos_attacked(p, from + 2, enemy))
                            add_move(list, from, from + 2, 0);
                        if ((p->castle & qs) && !p->board[from - 1] && !p->board[from - 2] &&
                            !p->board[from - 3] && p->board[from - 4] == rook &&
                            !pos_attacked(p, from - 1, enemy) && !pos_attacked(p, from - 2, enemy))
                            add_move(list, from, from - 2, 0);
                    }
                }
            } else {
                const int start = type == BISHOP ? 4 : 0;
                const int end = type == ROOK ? 4 : 8;
                for (int d = start; d < end; d++) {
                    const int step = DIRS[d];
                    for (int to = from + step; ON_BOARD(to); to += step) {
                        const int t = p->board[to];
                        if (!t) {
                            if (!captures_only) add_move(list, from, to, 0);
                            continue;
                        }
                        if (COLOR_OF(t) == enemy) add_move(list, from, to, 0);
                        break;
                    }
                }
            }
        }
}

bool make_if_legal(Position *p, Move m) {
    pos_make(p, m);
    const int mover = p->side ^ 1;
    if (pos_attacked(p, p->king[mover], p->side)) {
        pos_unmake(p);
        return false;
    }
    return true;
}

Move parse_move(Position *p, const char *s) {
    MoveList list;
    gen_moves(p, &list, false);
    char buf[6];
    for (int i = 0; i < list.count; i++) {
        move_to_str(list.moves[i], buf);
        if (strcmp(buf, s) == 0) {
            if (make_if_legal(p, list.moves[i])) {
                pos_unmake(p);
                return list.moves[i];
            }
            return MOVE_NONE;
        }
    }
    return MOVE_NONE;
}

uint64_t perft(Position *p, int depth) {
    if (depth == 0) return 1;
    MoveList list;
    gen_moves(p, &list, false);
    uint64_t nodes = 0;
    if (depth == 1) {
        for (int i = 0; i < list.count; i++)
            if (make_if_legal(p, list.moves[i])) {
                nodes++;
                pos_unmake(p);
            }
        return nodes;
    }
    for (int i = 0; i < list.count; i++)
        if (make_if_legal(p, list.moves[i])) {
            nodes += perft(p, depth - 1);
            pos_unmake(p);
        }
    return nodes;
}
