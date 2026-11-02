/* Board representation, attack tables, move generation, make/unmake, FEN, perft. */
#include "chess.h"

#include <stdio.h>
#include <string.h>

static U64 knight_tab[64], king_tab[64], pawn_tab[2][64];

/* ray_tab[d][sq]: all squares from sq in direction d (exclusive of sq), to the board edge.
 * Directions 0 N, 1 S, 2 E, 3 W, 4 NE, 5 NW, 6 SE, 7 SW.
 * For d with DIR_POS the square index grows along the ray, otherwise it shrinks. */
static U64 ray_tab[8][64];
static const int DR[8] = {1, -1, 0, 0, 1, 1, -1, -1};
static const int DF[8] = {0, 0, 1, -1, 1, -1, 1, -1};
static const bool DIR_POS[8] = {true, false, true, false, true, true, false, false};

static U64 zkey_piece[12][64], zkey_castle[16], zkey_ep[8], zkey_side;
static uint8_t castle_mask[64];
static bool inited = false;

static const char PIECE_CHARS[] = "PNBRQKpnbrqk";

static inline int ctz64(U64 b) { return __builtin_ctzll(b); }
static inline int msb64(U64 b) { return 63 - __builtin_clzll(b); }
static inline int popc64(U64 b) { return __builtin_popcountll(b); }

static U64 splitmix64(uint64_t *x) {
  uint64_t z = (*x += 0x9E3779B97F4A7C15ULL);
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
  return z ^ (z >> 31);
}

static inline U64 ray_attacks(int d, int sq, U64 occ) {
  U64 a = ray_tab[d][sq];
  U64 blockers = a & occ;
  if (!blockers) return a;
  int blk = DIR_POS[d] ? ctz64(blockers) : msb64(blockers);
  return a ^ ray_tab[d][blk];
}

static inline U64 bishop_att(int sq, U64 occ) {
  return ray_attacks(4, sq, occ) | ray_attacks(5, sq, occ) | ray_attacks(6, sq, occ) | ray_attacks(7, sq, occ);
}

static inline U64 rook_att(int sq, U64 occ) {
  return ray_attacks(0, sq, occ) | ray_attacks(1, sq, occ) | ray_attacks(2, sq, occ) | ray_attacks(3, sq, occ);
}

static inline U64 piece_att(int type, int sq, U64 occ) {
  switch (type) {
  case KNIGHT: return knight_tab[sq];
  case BISHOP: return bishop_att(sq, occ);
  case ROOK: return rook_att(sq, occ);
  case QUEEN: return bishop_att(sq, occ) | rook_att(sq, occ);
  case KING: return king_tab[sq];
  default: return 0;
  }
}

static inline void put(Position *p, int sq, int pc) {
  U64 b = 1ULL << sq;
  p->mailbox[sq] = (uint8_t)pc;
  p->pieces[pc / 6][pc % 6] |= b;
  p->occ[pc / 6] |= b;
  p->hash ^= zkey_piece[pc][sq];
}

static inline void rem(Position *p, int sq) {
  int pc = p->mailbox[sq];
  U64 nb = ~(1ULL << sq);
  p->pieces[pc / 6][pc % 6] &= nb;
  p->occ[pc / 6] &= nb;
  p->mailbox[sq] = NO_PIECE;
  p->hash ^= zkey_piece[pc][sq];
}

void board_init(void) {
  if (inited) return;
  inited = true;

  static const int KN[8][2] = {{1, 2}, {2, 1}, {2, -1}, {1, -2}, {-1, -2}, {-2, -1}, {-2, 1}, {-1, 2}};
  for (int sq = 0; sq < 64; sq++) {
    int r = sq / 8, f = sq % 8;
    knight_tab[sq] = king_tab[sq] = pawn_tab[WHITE][sq] = pawn_tab[BLACK][sq] = 0;
    for (int k = 0; k < 8; k++) {
      int nr = r + KN[k][0], nf = f + KN[k][1];
      if (nr >= 0 && nr < 8 && nf >= 0 && nf < 8) knight_tab[sq] |= 1ULL << (nr * 8 + nf);
    }
    for (int d = 0; d < 8; d++) {
      int nr = r + DR[d], nf = f + DF[d];
      if (nr >= 0 && nr < 8 && nf >= 0 && nf < 8) king_tab[sq] |= 1ULL << (nr * 8 + nf);
      ray_tab[d][sq] = 0;
      int rr = r + DR[d], ff = f + DF[d];
      while (rr >= 0 && rr < 8 && ff >= 0 && ff < 8) {
        ray_tab[d][sq] |= 1ULL << (rr * 8 + ff);
        rr += DR[d];
        ff += DF[d];
      }
    }
    for (int df = -1; df <= 1; df += 2) {
      int nf = f + df;
      if (nf < 0 || nf > 7) continue;
      if (r + 1 < 8) pawn_tab[WHITE][sq] |= 1ULL << ((r + 1) * 8 + nf);
      if (r - 1 >= 0) pawn_tab[BLACK][sq] |= 1ULL << ((r - 1) * 8 + nf);
    }
  }

  uint64_t seed = 0x2545F4914F6CDD1DULL;
  for (int pc = 0; pc < 12; pc++)
    for (int sq = 0; sq < 64; sq++) zkey_piece[pc][sq] = splitmix64(&seed);
  for (int i = 0; i < 16; i++) zkey_castle[i] = splitmix64(&seed);
  for (int i = 0; i < 8; i++) zkey_ep[i] = splitmix64(&seed);
  zkey_side = splitmix64(&seed);

  for (int sq = 0; sq < 64; sq++) castle_mask[sq] = 15;
  castle_mask[0] &= (uint8_t)~CR_WQ;
  castle_mask[7] &= (uint8_t)~CR_WK;
  castle_mask[4] &= (uint8_t)~(CR_WK | CR_WQ);
  castle_mask[56] &= (uint8_t)~CR_BQ;
  castle_mask[63] &= (uint8_t)~CR_BK;
  castle_mask[60] &= (uint8_t)~(CR_BK | CR_BQ);
}

U64 hash_full(const Position *p) {
  U64 h = 0;
  for (int sq = 0; sq < 64; sq++)
    if (p->mailbox[sq] != NO_PIECE) h ^= zkey_piece[p->mailbox[sq]][sq];
  h ^= zkey_castle[p->castle];
  if (p->ep >= 0) h ^= zkey_ep[p->ep & 7];
  if (p->side == BLACK) h ^= zkey_side;
  return h;
}

bool pos_from_fen(Position *p, const char *fen) {
  memset(p, 0, sizeof *p);
  for (int sq = 0; sq < 64; sq++) p->mailbox[sq] = NO_PIECE;
  p->ep = -1;
  p->fullmove = 1;

  char bstr[128] = "", sstr[8] = "w", cstr[8] = "-", estr[8] = "-";
  int hm = 0, fm = 1;
  int got = sscanf(fen, "%127s %7s %7s %7s %d %d", bstr, sstr, cstr, estr, &hm, &fm);
  if (got < 1) return false;

  int r = 7, f = 0;
  for (const char *c = bstr; *c; c++) {
    if (*c == '/') {
      r--;
      f = 0;
      if (r < 0) return false;
    } else if (*c >= '1' && *c <= '8') {
      f += *c - '0';
    } else {
      const char *k = strchr(PIECE_CHARS, *c);
      if (!k || f > 7) return false;
      int idx = (int)(k - PIECE_CHARS);
      put(p, r * 8 + f, (idx >= 6 ? BLACK : WHITE) * 6 + idx % 6);
      f++;
    }
  }

  p->side = (sstr[0] == 'b') ? BLACK : WHITE;
  for (const char *c = cstr; *c; c++) {
    if (*c == 'K') p->castle |= CR_WK;
    else if (*c == 'Q') p->castle |= CR_WQ;
    else if (*c == 'k') p->castle |= CR_BK;
    else if (*c == 'q') p->castle |= CR_BQ;
  }
  if (estr[0] >= 'a' && estr[0] <= 'h' && estr[1] >= '1' && estr[1] <= '8')
    p->ep = (int8_t)((estr[1] - '1') * 8 + (estr[0] - 'a'));
  p->halfmove = (uint16_t)(hm < 0 ? 0 : hm);
  p->fullmove = (uint16_t)(fm < 1 ? 1 : fm);
  p->hash = hash_full(p);
  return true;
}

bool is_attacked(const Position *p, int sq, int by) {
  const U64 *P = p->pieces[by];
  U64 occ = p->occ[0] | p->occ[1];
  if (pawn_tab[by ^ 1][sq] & P[PAWN]) return true;
  if (knight_tab[sq] & P[KNIGHT]) return true;
  if (king_tab[sq] & P[KING]) return true;
  if (bishop_att(sq, occ) & (P[BISHOP] | P[QUEEN])) return true;
  if (rook_att(sq, occ) & (P[ROOK] | P[QUEEN])) return true;
  return false;
}

bool in_check(const Position *p, int side) {
  U64 k = p->pieces[side][KING];
  if (!k) return false;
  return is_attacked(p, ctz64(k), side ^ 1);
}

static void gen_castles(const Position *p, Move *list, int *n) {
  U64 occ = p->occ[0] | p->occ[1];
  if (p->side == WHITE) {
    if (!(p->pieces[WHITE][KING] & (1ULL << 4))) return;
    if ((p->castle & CR_WK) && (p->pieces[WHITE][ROOK] & (1ULL << 7)) &&
        !(occ & ((1ULL << 5) | (1ULL << 6))) && !is_attacked(p, 4, BLACK) && !is_attacked(p, 5, BLACK))
      list[(*n)++] = MOVE_MAKE(4, 6, 0, F_CASTLE);
    if ((p->castle & CR_WQ) && (p->pieces[WHITE][ROOK] & (1ULL << 0)) &&
        !(occ & ((1ULL << 1) | (1ULL << 2) | (1ULL << 3))) && !is_attacked(p, 4, BLACK) &&
        !is_attacked(p, 3, BLACK))
      list[(*n)++] = MOVE_MAKE(4, 2, 0, F_CASTLE);
  } else {
    if (!(p->pieces[BLACK][KING] & (1ULL << 60))) return;
    if ((p->castle & CR_BK) && (p->pieces[BLACK][ROOK] & (1ULL << 63)) &&
        !(occ & ((1ULL << 61) | (1ULL << 62))) && !is_attacked(p, 60, WHITE) && !is_attacked(p, 61, WHITE))
      list[(*n)++] = MOVE_MAKE(60, 62, 0, F_CASTLE);
    if ((p->castle & CR_BQ) && (p->pieces[BLACK][ROOK] & (1ULL << 56)) &&
        !(occ & ((1ULL << 57) | (1ULL << 58) | (1ULL << 59))) && !is_attacked(p, 60, WHITE) &&
        !is_attacked(p, 59, WHITE))
      list[(*n)++] = MOVE_MAKE(60, 58, 0, F_CASTLE);
  }
}

int gen_moves(const Position *p, Move *list, bool captures_only) {
  int n = 0;
  int us = p->side;
  U64 own = p->occ[us], enemy = p->occ[us ^ 1];
  U64 occ = own | enemy;
  U64 targets = captures_only ? enemy : ~own;

  U64 pawns = p->pieces[us][PAWN];
  int dir = us == WHITE ? 8 : -8;
  int start_rank = us == WHITE ? 1 : 6;
  int promo_rank = us == WHITE ? 6 : 1;
  while (pawns) {
    int from = ctz64(pawns);
    pawns &= pawns - 1;
    int to = from + dir;
    bool promo = (from / 8) == promo_rank;
    if (!(occ & (1ULL << to))) {
      if (promo) {
        for (int pr = KNIGHT; pr <= QUEEN; pr++) list[n++] = MOVE_MAKE(from, to, pr, F_PROMO);
      } else if (!captures_only) {
        list[n++] = MOVE_MAKE(from, to, 0, 0);
        if ((from / 8) == start_rank && !(occ & (1ULL << (to + dir))))
          list[n++] = MOVE_MAKE(from, to + dir, 0, F_DOUBLE);
      }
    }
    U64 caps = pawn_tab[us][from] & enemy;
    while (caps) {
      int t = ctz64(caps);
      caps &= caps - 1;
      if (promo) {
        for (int pr = KNIGHT; pr <= QUEEN; pr++) list[n++] = MOVE_MAKE(from, t, pr, F_CAP | F_PROMO);
      } else {
        list[n++] = MOVE_MAKE(from, t, 0, F_CAP);
      }
    }
    if (p->ep >= 0 && (pawn_tab[us][from] & (1ULL << p->ep)))
      list[n++] = MOVE_MAKE(from, p->ep, 0, F_EP | F_CAP);
  }

  for (int type = KNIGHT; type <= KING; type++) {
    U64 bb = p->pieces[us][type];
    while (bb) {
      int from = ctz64(bb);
      bb &= bb - 1;
      U64 att = piece_att(type, from, occ) & targets;
      while (att) {
        int to = ctz64(att);
        att &= att - 1;
        unsigned fl = ((enemy >> to) & 1ULL) ? F_CAP : 0u;
        list[n++] = MOVE_MAKE(from, to, 0, fl);
      }
    }
  }

  if (!captures_only) gen_castles(p, list, &n);
  return n;
}

void make_move(const Position *src, Position *dst, Move m) {
  *dst = *src;
  int from = MFROM(m), to = MTO(m);
  unsigned fl = MFLAGS(m);
  int us = dst->side, them = us ^ 1;
  int pc = dst->mailbox[from];

  if (dst->ep >= 0) dst->hash ^= zkey_ep[dst->ep & 7];
  dst->hash ^= zkey_castle[dst->castle];
  dst->hash ^= zkey_side;
  dst->ep = -1;

  bool capture = (fl & (F_CAP | F_EP)) != 0;
  if (fl & F_EP) {
    rem(dst, us == WHITE ? to - 8 : to + 8);
  } else if (dst->mailbox[to] != NO_PIECE) {
    rem(dst, to);
  }
  rem(dst, from);
  if (MPROMO(m)) put(dst, to, us * 6 + MPROMO(m));
  else put(dst, to, pc);

  if (fl & F_CASTLE) {
    if (to > from) {
      rem(dst, from + 3);
      put(dst, from + 1, us * 6 + ROOK);
    } else {
      rem(dst, from - 4);
      put(dst, from - 1, us * 6 + ROOK);
    }
  }

  dst->castle &= castle_mask[from] & castle_mask[to];
  if (fl & F_DOUBLE) dst->ep = (int8_t)((from + to) / 2);
  dst->halfmove = (pc % 6 == PAWN || capture) ? 0 : (uint16_t)(dst->halfmove + 1);
  if (us == BLACK) dst->fullmove++;
  dst->side = (uint8_t)them;

  dst->hash ^= zkey_castle[dst->castle];
  if (dst->ep >= 0) dst->hash ^= zkey_ep[dst->ep & 7];
}

void make_null(const Position *src, Position *dst) {
  *dst = *src;
  if (dst->ep >= 0) {
    dst->hash ^= zkey_ep[dst->ep & 7];
    dst->ep = -1;
  }
  dst->side ^= 1;
  dst->hash ^= zkey_side;
  dst->halfmove++;
}

void move_to_str(Move m, char buf[6]) {
  buf[0] = (char)('a' + MFROM(m) % 8);
  buf[1] = (char)('1' + MFROM(m) / 8);
  buf[2] = (char)('a' + MTO(m) % 8);
  buf[3] = (char)('1' + MTO(m) / 8);
  int pr = MPROMO(m);
  if (pr) {
    static const char PROMO_CHARS[] = " nbrq";
    buf[4] = PROMO_CHARS[pr];
    buf[5] = '\0';
  } else {
    buf[4] = '\0';
  }
}

Move parse_move(const Position *p, const char *s) {
  Move list[256];
  int n = gen_moves(p, list, false);
  for (int i = 0; i < n; i++) {
    char buf[6];
    move_to_str(list[i], buf);
    if (strcmp(buf, s) != 0) continue;
    Position child;
    make_move(p, &child, list[i]);
    if (!in_check(&child, p->side)) return list[i];
  }
  return MOVE_NONE;
}

U64 perft(const Position *p, int depth) {
  if (depth == 0) return 1;
  Move list[256];
  int n = gen_moves(p, list, false);
  U64 nodes = 0;
  Position child;
  for (int i = 0; i < n; i++) {
    make_move(p, &child, list[i]);
    if (in_check(&child, p->side)) continue;
    nodes += (depth == 1) ? 1 : perft(&child, depth - 1);
  }
  return nodes;
}
