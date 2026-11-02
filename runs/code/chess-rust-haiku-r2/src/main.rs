//! RustChess: a UCI chess engine written without external crates.

mod attacks;
mod board;
mod eval;
mod movegen;
mod search;
mod uci;

fn main() {
    uci::run();
}
