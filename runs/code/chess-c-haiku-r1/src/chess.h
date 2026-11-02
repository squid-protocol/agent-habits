#ifndef CHESS_H
#define CHESS_H

#include <stdbool.h>
#include <stdint.h>

enum { EMPTY = 0, PAWN = 1, KNIGHT = 2, BISHOP = 3, ROOK = 4, QUEEN = 5, KING = 6 };
enum { WHITE = 0, BLACK = 1 };
enum { CASTLE_WK = 1, CASTLE_WQ = 2, CASTLE_BK = 4, CASTLE_BQ = 8 };

/* Pieces are stored as color*8 + type (white 1..6, black 9..14, 0 = empty). */
#define PIECE_OF(color, type) ((color) * 8 + (type))
#define COLOR_OF(pc) ((pc) >> 3)
#define TYPE_OF(pc) ((pc) & 7)

/* 0x88 board: square = rank*16 + file, a1 = 0, h8 = 119. */
#define SQ(file, rank) ((rank) * 16 + (file))
#define FILE_OF(sq) ((sq) & 7)
#define RANK_OF(sq) ((sq) >> 4)
#define ON_BOARD(sq) (((sq) & 0x88) == 0)

/* A move packs from (7 bits), to (7 bits) and promotion piece type (3 bits). */
typedef uint32_t Move;
#define MOVE_NONE ((Move)0)
#define MAKE_MOVE(from, to, promo) ((Move)((from) | ((to) << 7) | ((promo) << 14)))
#define MOVE_FROM(m) ((m) & 127u)
#define MOVE_TO(m) (((m) >> 7) & 127u)
#define MOVE_PROMO(m) (((m) >> 14) & 7u)

#define MAX_MOVES 256
typedef struct {
    Move moves[MAX_MOVES];
    int scores[MAX_MOVES];
    int count;
} MoveList;

#define MAX_UNDO 8192
typedef struct {
    Move move;      /* MOVE_NONE for a null move */
    int captured;   /* piece code removed by the move, 0 if none */
    int cap_sq;     /* square the captured piece stood on (differs from `to` for en passant) */
    int castle;
    int ep;
    int half;
    int full;
    uint64_t key;   /* hash before the move */
} Undo;

typedef struct {
    int board[128];
    int side;
    int castle;     /* CASTLE_* bits */
    int ep;         /* en-passant target square (0x88) or -1 */
    int half;       /* halfmove clock */
    int full;       /* fullmove number */
    int king[2];
    uint64_t key;   /* Zobrist hash */
    int nundo;
    Undo undo[MAX_UNDO];
} Position;

typedef struct {
    int max_depth;  /* 0 = no depth limit */
    double soft_ms; /* do not start a new iteration after this many ms (0 = none) */
    double hard_ms; /* abort the search after this many ms (0 = none) */
} SearchLimits;

/* board.c */
void board_init(void);
void pos_startpos(Position *p);
bool pos_from_fen(Position *p, const char *fen);
uint64_t pos_compute_key(const Position *p);
void pos_make(Position *p, Move m);
void pos_unmake(Position *p);
void pos_make_null(Position *p);
void pos_unmake_null(Position *p);
bool pos_attacked(const Position *p, int sq, int by);
bool pos_in_check(const Position *p);
bool pos_is_repetition(const Position *p);
bool pos_has_non_pawn(const Position *p, int side);
void move_to_str(Move m, char buf[6]);

/* movegen.c */
void gen_moves(const Position *p, MoveList *list, bool captures_only);
bool make_if_legal(Position *p, Move m);
Move parse_move(Position *p, const char *s);
uint64_t perft(Position *p, int depth);

/* eval.c */
extern const int PIECE_VALUE[7];
int evaluate(const Position *p);

/* search.c */
void search_init(void);
void search_clear(void);
void search_clear_stop(void);
void search_request_stop(void);
void search_think(Position *p, const SearchLimits *lim);

#endif
