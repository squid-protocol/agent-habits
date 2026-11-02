# ChessC

A UCI chess engine written in C17 (POSIX threads only, no third-party code).

## Build and run

    ./build.sh      # builds ./engine
    ./engine        # speaks UCI on stdin/stdout

## Layout

- `src/chess.h`   shared types: 0x88 board, packed moves, positions, search limits
- `src/board.c`   FEN, Zobrist hashing, make/unmake, attack detection, repetition
- `src/movegen.c` move generation (castling, en passant, promotion), legality, perft
- `src/eval.c`    tapered material + piece-square evaluation
- `src/search.c`  iterative-deepening alpha-beta (PVS), quiescence, transposition table,
                  null-move and late-move reductions, killer/history ordering, time control
- `src/uci.c`     UCI command loop; the search runs on its own thread so `stop` works

## Supported UCI

`uci`, `isready`, `ucinewgame`, `position startpos|fen ... [moves ...]`,
`go depth N | movetime MS | wtime/btime/winc/binc/movestogo | infinite | perft N`,
`stop`, `quit`. `go perft N` prints `<move>: <count>` per root move and `Nodes searched: <total>`.
