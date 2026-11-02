/* Shared types and board-level API of the chess engine. */
#ifndef CHESS_H
#define CHESS_H

#define _POSIX_C_SOURCE 200809L

#include <stdbool.h>
#include <stdint.h>

typedef uint64_t U64;

/* A move is packed into 32 bits:
 *   bits 0-5   from square (a1 = 0, h8 = 63)
 *   bits 6-11  to square
 *   bits 12-14 promotion piece type (0 = none, else KNIGHT..QUEEN)
 *   bits 16-23 flags (F_*)
 */
typedef uint32_t Move;

enum { WHITE = 0, BLACK = 1 };
enum { PAWN, KNIGHT, BISHOP, ROOK, QUEEN, KING };

#define NO_PIECE 12 /* mailbox value of an empty square; otherwise color * 6 + type */
#define START_FEN "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

#define CR_WK 1
#define CR_WQ 2
#define CR_BK 4
#define CR_BQ 8

#define F_CAP 1u
#define F_EP 2u
#define F_CASTLE 4u
#define F_DOUBLE 8u
#define F_PROMO 16u

#define MOVE_MAKE(f, t, pr, fl) ((Move)((f) | ((t) << 6) | ((pr) << 12) | ((fl) << 16)))
#define MFROM(m) ((int)((m) & 63u))
#define MTO(m) ((int)(((m) >> 6) & 63u))
#define MPROMO(m) ((int)(((m) >> 12) & 7u))
#define MFLAGS(m) ((unsigned)(((m) >> 16) & 0xffu))
#define MOVE_NONE ((Move)0)

typedef struct {
  U64 pieces[2][6];
  U64 occ[2];
  uint8_t mailbox[64];
  uint8_t side;
  uint8_t castle;
  int8_t ep; /* en-passant target square, -1 if none */
  uint16_t halfmove;
  uint16_t fullmove;
  U64 hash;
} Position;

/* board.c */
void board_init(void); /* must be called once before anything else */
bool pos_from_fen(Position *p, const char *fen);
int gen_moves(const Position *p, Move *list, bool captures_only); /* pseudo-legal */
void make_move(const Position *src, Position *dst, Move m);
void make_null(const Position *src, Position *dst);
bool in_check(const Position *p, int side);
bool is_attacked(const Position *p, int sq, int by);
U64 hash_full(const Position *p);
void move_to_str(Move m, char buf[6]);
Move parse_move(const Position *p, const char *s); /* legal move matching s, or MOVE_NONE */
U64 perft(const Position *p, int depth);

/* uci.c: serialised output shared by the main and the search thread. */
void out_printf(const char *fmt, ...) __attribute__((format(printf, 1, 2)));

#endif
