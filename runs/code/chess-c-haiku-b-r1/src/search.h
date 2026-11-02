/* Search API: iterative-deepening alpha-beta with a transposition table. */
#ifndef SEARCH_H
#define SEARCH_H

#include "chess.h"

#define SEARCH_HIST_CAP 2048

typedef struct {
  int depth;          /* fixed depth limit, 0 = none */
  long long movetime; /* milliseconds, 0 = none */
  long long wtime, btime, winc, binc;
  bool has_clock;     /* wtime/btime were given */
  bool infinite;      /* search until stopped */
} Limits;

void search_init(void);
void search_clear(void); /* forget the transposition table and move-ordering state */
void search_stop(void);  /* ask a running search to stop (asynchronous) */
void search_reset_stop(void);
/* Blocking search. hist holds the hashes of all earlier positions of the game, root last. */
Move search_think(const Position *root, const U64 *hist, int histn, const Limits *lim);

#endif
