# ChessCOBOL

A UCI chess engine written in GnuCOBOL 3.1 (`cobc`), with no third-party code.

## Build and run

    ./build.sh      # runs: cobc -x -free -O2 -o engine engine.cob
    ./engine        # speaks UCI on stdin/stdout

## Design

`engine.cob` holds three programs:

- **ENGINE** (main): the UCI loop. Parses `uci`, `isready`, `ucinewgame`, `position`
  (startpos or FEN, plus moves), `go` (`depth`, `movetime`, `wtime`/`btime`/`winc`/`binc`,
  `perft N`), `stop`, `quit`. Works out the time budget and prints `bestmove`.
- **INPUTIO**: a buffered reader over raw `read(2)`. During a search it calls `poll(2)`
  so that `stop` and `quit` interrupt the search without blocking.
- **CHESS** (recursive): a 10x12 mailbox board, pseudo-legal move generation (castling,
  en passant, promotions), make/unmake with an undo stack, legality by testing the king
  after each move, alpha-beta search with MVV-LVA ordering, quiescence search (all
  evasions when in check), material evaluation, and perft. Every search node is one
  `CALL` into CHESS, with per-node state in `LOCAL-STORAGE`.

Iterative deepening runs until the time budget is used, the depth limit is reached, or a
forced mate is found. The result of the last completed iteration is the move played.

## Verification

- Perft matches the published counts for the start position (depth 4) and for the
  kiwipete, position 3, 4 and 5 test positions.
- Randomized tests against python-chess: perft on random positions, and perft after
  UCI `moves` sequences that include castling, en passant and promotions.
- All 22 practice mate-in-2/3 puzzles are solved within 2 s.
- The engine wins 4 of 4 games against a greedy material-grabbing opponent at 0.5 s per move.
