# RustChess

A UCI chess engine written in Rust with no external crates.

## Build and run

    ./build.sh      # cargo build --release, then copies the binary to ./engine
    ./engine        # speaks UCI on stdin/stdout

## Layout

- `src/board.rs`   – piece encoding, FEN parsing, make/unmake, Zobrist hashing, repetition check
- `src/movegen.rs` – attack detection, pseudo-legal and legal move generation (castling, en passant,
                     promotion), perft
- `src/search.rs`  – tapered piece-square evaluation; alpha-beta with iterative deepening, quiescence
                     search, check extensions, transposition table, killer/history move ordering,
                     mate scoring, time budget checks
- `src/main.rs`    – UCI loop; each search runs on a worker thread so `stop`/`quit` interrupt it

## Supported UCI

`uci`, `isready`, `ucinewgame`, `position startpos|fen ... [moves ...]`,
`go depth N | movetime MS | wtime/btime/winc/binc [movestogo N] | infinite | perft N`, `stop`, `quit`.
`go perft N` prints `<move>: <count>` for each root move, then `Nodes searched: <total>`.
