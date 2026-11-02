#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#include "chess.h"

static uint64_t z_piece[128][16];
static uint64_t z_side;
static uint64_t z_castle[16];
static uint64_t z_ep[8];
static int castle_mask[128];
static bool z_ready = false;

static uint64_t splitmix64(uint64_t *state) {
    uint64_t z = (*state += 0x9E3779B97F4A7C15ull);
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ull;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBull;
    return z ^ (z >> 31);
}

void board_init(void) {
    if (z_ready) return;
    uint64_t s = 0x9D2C5680A5F1B3C7ull;
    for (int sq = 0; sq < 128; sq++)
        for (int pc = 0; pc < 16; pc++) z_piece[sq][pc] = splitmix64(&s);
    z_side = splitmix64(&s);
    for (int i = 0; i < 16; i++) z_castle[i] = splitmix64(&s);
    for (int i = 0; i < 8; i++) z_ep[i] = splitmix64(&s);

    for (int i = 0; i < 128; i++) castle_mask[i] = 15;
    castle_mask[SQ(0, 0)] &= ~CASTLE_WQ;
    castle_mask[SQ(7, 0)] &= ~CASTLE_WK;
    castle_mask[SQ(4, 0)] &= ~(CASTLE_WK | CASTLE_WQ);
    castle_mask[SQ(0, 7)] &= ~CASTLE_BQ;
    castle_mask[SQ(7, 7)] &= ~CASTLE_BK;
    castle_mask[SQ(4, 7)] &= ~(CASTLE_BK | CASTLE_BQ);
    z_ready = true;
}

uint64_t pos_compute_key(const Position *p) {
    uint64_t k = 0;
    for (int r = 0; r < 8; r++)
        for (int f = 0; f < 8; f++) {
            int sq = SQ(f, r);
            if (p->board[sq]) k ^= z_piece[sq][p->board[sq]];
        }
    if (p->side == BLACK) k ^= z_side;
    k ^= z_castle[p->castle];
    if (p->ep >= 0) k ^= z_ep[FILE_OF(p->ep)];
    return k;
}

bool pos_from_fen(Position *p, const char *fen) {
    board_init();
    memset(p->board, 0, sizeof p->board);
    p->nundo = 0;
    p->king[WHITE] = p->king[BLACK] = 0;

    const char *c = fen;
    int rank = 7, file = 0;
    for (; *c && *c != ' '; c++) {
        char ch = *c;
        if (ch == '/') {
            if (file != 8 || rank == 0) return false;
            rank--;
            file = 0;
        } else if (ch >= '1' && ch <= '8') {
            file += ch - '0';
            if (file > 8) return false;
        } else {
            int color = isupper((unsigned char)ch) ? WHITE : BLACK;
            int type;
            switch (tolower((unsigned char)ch)) {
                case 'p': type = PAWN; break;
                case 'n': type = KNIGHT; break;
                case 'b': type = BISHOP; break;
                case 'r': type = ROOK; break;
                case 'q': type = QUEEN; break;
                case 'k': type = KING; break;
                default: return false;
            }
            if (file > 7) return false;
            int sq = SQ(file, rank);
            p->board[sq] = PIECE_OF(color, type);
            if (type == KING) p->king[color] = sq;
            file++;
        }
    }
    while (*c == ' ') c++;

    p->side = (*c == 'b') ? BLACK : WHITE;
    if (*c) c++;
    while (*c == ' ') c++;

    p->castle = 0;
    while (*c && *c != ' ') {
        switch (*c) {
            case 'K': p->castle |= CASTLE_WK; break;
            case 'Q': p->castle |= CASTLE_WQ; break;
            case 'k': p->castle |= CASTLE_BK; break;
            case 'q': p->castle |= CASTLE_BQ; break;
            default: break;
        }
        c++;
    }
    while (*c == ' ') c++;

    p->ep = -1;
    if (*c == '-') {
        c++;
    } else if (c[0] >= 'a' && c[0] <= 'h' && c[1] >= '1' && c[1] <= '8') {
        p->ep = SQ(c[0] - 'a', c[1] - '1');
        c += 2;
    }
    while (*c == ' ') c++;

    p->half = 0;
    p->full = 1;
    if (*c) {
        char *end;
        long h = strtol(c, &end, 10);
        if (end != c) p->half = (int)h;
        c = end;
    }
    while (*c == ' ') c++;
    if (*c) {
        char *end;
        long f = strtol(c, &end, 10);
        if (end != c && f >= 1) p->full = (int)f;
    }
    p->key = pos_compute_key(p);
    return true;
}

void pos_startpos(Position *p) {
    pos_from_fen(p, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
}

void pos_make(Position *p, Move m) {
    Undo *u = &p->undo[p->nundo++];
    const int from = MOVE_FROM(m), to = MOVE_TO(m), promo = MOVE_PROMO(m);
    const int side = p->side;
    const int pc = p->board[from];

    u->move = m;
    u->castle = p->castle;
    u->ep = p->ep;
    u->half = p->half;
    u->full = p->full;
    u->key = p->key;

    int cap = p->board[to];
    int cap_sq = to;
    if (TYPE_OF(pc) == PAWN && to == p->ep && !cap) {
        cap_sq = side == WHITE ? to - 16 : to + 16;
        cap = p->board[cap_sq];
    }
    u->captured = cap;
    u->cap_sq = cap_sq;
    if (cap) {
        p->board[cap_sq] = 0;
        p->key ^= z_piece[cap_sq][cap];
    }

    p->board[from] = 0;
    p->key ^= z_piece[from][pc];
    const int placed = promo ? PIECE_OF(side, promo) : pc;
    p->board[to] = placed;
    p->key ^= z_piece[to][placed];

    if (TYPE_OF(pc) == KING) {
        p->king[side] = to;
        if (to - from == 2 || from - to == 2) {  /* castling: move the rook too */
            int rf, rt;
            if (to > from) { rf = from + 3; rt = from + 1; }
            else           { rf = from - 4; rt = from - 1; }
            int rook = p->board[rf];
            p->board[rf] = 0;
            p->key ^= z_piece[rf][rook];
            p->board[rt] = rook;
            p->key ^= z_piece[rt][rook];
        }
    }

    if (p->ep >= 0) p->key ^= z_ep[FILE_OF(p->ep)];
    p->ep = -1;
    if (TYPE_OF(pc) == PAWN && (to - from == 32 || from - to == 32)) {
        p->ep = (from + to) / 2;
        p->key ^= z_ep[FILE_OF(p->ep)];
    }

    p->key ^= z_castle[p->castle];
    p->castle &= castle_mask[from] & castle_mask[to];
    p->key ^= z_castle[p->castle];

    if (TYPE_OF(pc) == PAWN || cap) p->half = 0;
    else p->half++;
    if (side == BLACK) p->full++;

    p->side ^= 1;
    p->key ^= z_side;
}

void pos_unmake(Position *p) {
    const Undo *u = &p->undo[--p->nundo];
    const Move m = u->move;
    const int from = MOVE_FROM(m), to = MOVE_TO(m);

    p->side ^= 1;
    const int side = p->side;
    const int pc = MOVE_PROMO(m) ? PIECE_OF(side, PAWN) : p->board[to];

    p->board[from] = pc;
    p->board[to] = 0;
    if (u->captured) p->board[u->cap_sq] = u->captured;

    if (TYPE_OF(pc) == KING) {
        p->king[side] = from;
        if (to - from == 2 || from - to == 2) {
            int rf, rt;
            if (to > from) { rf = from + 3; rt = from + 1; }
            else           { rf = from - 4; rt = from - 1; }
            p->board[rf] = p->board[rt];
            p->board[rt] = 0;
        }
    }

    p->castle = u->castle;
    p->ep = u->ep;
    p->half = u->half;
    p->full = u->full;
    p->key = u->key;
}

void pos_make_null(Position *p) {
    Undo *u = &p->undo[p->nundo++];
    u->move = MOVE_NONE;
    u->captured = 0;
    u->cap_sq = 0;
    u->castle = p->castle;
    u->ep = p->ep;
    u->half = p->half;
    u->full = p->full;
    u->key = p->key;

    if (p->ep >= 0) p->key ^= z_ep[FILE_OF(p->ep)];
    p->ep = -1;
    p->half++;
    if (p->side == BLACK) p->full++;
    p->side ^= 1;
    p->key ^= z_side;
}

void pos_unmake_null(Position *p) {
    const Undo *u = &p->undo[--p->nundo];
    p->side ^= 1;
    p->castle = u->castle;
    p->ep = u->ep;
    p->half = u->half;
    p->full = u->full;
    p->key = u->key;
}

static const int KNIGHT_OFF[8] = {33, 31, 18, 14, -33, -31, -18, -14};
static const int KING_OFF[8] = {1, -1, 16, -16, 15, 17, -15, -17};

bool pos_attacked(const Position *p, int sq, int by) {
    const int *b = p->board;
    int s;

    /* A white pawn attacks sq from sq-15 / sq-17; a black pawn from sq+15 / sq+17. */
    const int pawn = PIECE_OF(by, PAWN);
    if (by == WHITE) {
        s = sq - 15; if (ON_BOARD(s) && b[s] == pawn) return true;
        s = sq - 17; if (ON_BOARD(s) && b[s] == pawn) return true;
    } else {
        s = sq + 15; if (ON_BOARD(s) && b[s] == pawn) return true;
        s = sq + 17; if (ON_BOARD(s) && b[s] == pawn) return true;
    }

    const int knight = PIECE_OF(by, KNIGHT);
    for (int i = 0; i < 8; i++) {
        s = sq + KNIGHT_OFF[i];
        if (ON_BOARD(s) && b[s] == knight) return true;
    }

    const int king = PIECE_OF(by, KING);
    for (int i = 0; i < 8; i++) {
        s = sq + KING_OFF[i];
        if (ON_BOARD(s) && b[s] == king) return true;
    }

    /* Sliders: rook-like directions 0..3, bishop-like 4..7 (KING_OFF order). */
    const int rook = PIECE_OF(by, ROOK), bishop = PIECE_OF(by, BISHOP), queen = PIECE_OF(by, QUEEN);
    for (int i = 0; i < 8; i++) {
        const int d = KING_OFF[i];
        const bool diag = i >= 4;
        for (s = sq + d; ON_BOARD(s); s += d) {
            int pc = b[s];
            if (!pc) continue;
            if (pc == queen || (diag ? pc == bishop : pc == rook)) return true;
            break;
        }
    }
    return false;
}

bool pos_in_check(const Position *p) {
    return pos_attacked(p, p->king[p->side], p->side ^ 1);
}

bool pos_is_repetition(const Position *p) {
    /* Only positions with the same side to move, reachable since the last irreversible move. */
    int limit = p->half;
    for (int i = p->nundo - 2; i >= 0 && i >= p->nundo - limit; i -= 2)
        if (p->undo[i].key == p->key) return true;
    return false;
}

bool pos_has_non_pawn(const Position *p, int side) {
    for (int r = 0; r < 8; r++)
        for (int f = 0; f < 8; f++) {
            int pc = p->board[SQ(f, r)];
            if (pc && COLOR_OF(pc) == side) {
                int t = TYPE_OF(pc);
                if (t != PAWN && t != KING) return true;
            }
        }
    return false;
}

void move_to_str(Move m, char buf[6]) {
    static const char promo_chars[7] = {0, 0, 'n', 'b', 'r', 'q', 0};
    const int from = MOVE_FROM(m), to = MOVE_TO(m), promo = MOVE_PROMO(m);
    buf[0] = (char)('a' + FILE_OF(from));
    buf[1] = (char)('1' + RANK_OF(from));
    buf[2] = (char)('a' + FILE_OF(to));
    buf[3] = (char)('1' + RANK_OF(to));
    int n = 4;
    if (promo) buf[n++] = promo_chars[promo];
    buf[n] = '\0';
}
