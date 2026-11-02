//! A UCI chess engine.

mod attacks;
mod board;
mod eval;
mod movegen;
mod search;

use std::io::{self, BufRead, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use board::*;
use movegen::{legal_moves, perft};
use search::Searcher;

const DEFAULT_MAX_DEPTH: u32 = 64;

struct Engine {
    board: Board,
    /// Hashes of every position since the game started (for repetition detection).
    history: Vec<u64>,
    stop: Arc<AtomicBool>,
    searcher: Option<Box<Searcher>>,
    handle: Option<JoinHandle<Box<Searcher>>>,
}

fn parse_move(b: &Board, s: &str) -> Option<Move> {
    legal_moves(b, false).as_slice().iter().copied().find(|m| m.to_uci() == s)
}

impl Engine {
    fn new() -> Engine {
        let stop = Arc::new(AtomicBool::new(false));
        Engine {
            board: Board::startpos(),
            history: vec![Board::startpos().hash],
            searcher: Some(Box::new(Searcher::new(stop.clone()))),
            stop,
            handle: None,
        }
    }

    /// Stops a running search (it prints its `bestmove`) and reclaims the searcher.
    fn halt(&mut self) {
        self.stop.store(true, Ordering::Relaxed);
        if let Some(h) = self.handle.take() {
            self.searcher = Some(h.join().expect("search thread"));
        }
    }

    fn reset_game(&mut self) {
        self.halt();
        self.board = Board::startpos();
        self.history = vec![self.board.hash];
        if let Some(s) = self.searcher.as_mut() {
            s.clear();
        }
    }

    fn cmd_position(&mut self, args: &[&str]) {
        self.halt();
        let (mut board, mut i) = match args.first().copied() {
            Some("startpos") => (Board::startpos(), 1),
            Some("fen") => {
                let end = args.iter().position(|&t| t == "moves").unwrap_or(args.len());
                let fen = args[1..end].join(" ");
                match Board::from_fen(&fen) {
                    Some(b) => (b, end),
                    None => return,
                }
            }
            _ => return,
        };
        let mut history = vec![board.hash];
        if args.get(i) == Some(&"moves") {
            i += 1;
            while i < args.len() {
                match parse_move(&board, args[i]) {
                    Some(m) => {
                        board = board.make(m);
                        history.push(board.hash);
                    }
                    None => break,
                }
                i += 1;
            }
        }
        self.board = board;
        self.history = history;
    }

    fn cmd_go(&mut self, args: &[&str]) {
        self.halt();
        let mut depth: Option<u32> = None;
        let mut perft_depth: Option<u32> = None;
        let mut movetime: Option<u64> = None;
        let mut clock: [Option<u64>; 2] = [None, None];
        let mut inc = [0u64; 2];
        let mut i = 0;
        while i < args.len() {
            let val = args.get(i + 1).and_then(|s| s.parse::<u64>().ok());
            match args[i] {
                "perft" => {
                    perft_depth = val.map(|v| v as u32);
                    i += 2;
                }
                "depth" => {
                    depth = val.map(|v| v as u32);
                    i += 2;
                }
                "movetime" => {
                    movetime = val;
                    i += 2;
                }
                "wtime" => {
                    clock[WHITE] = val;
                    i += 2;
                }
                "btime" => {
                    clock[BLACK] = val;
                    i += 2;
                }
                "winc" => {
                    inc[WHITE] = val.unwrap_or(0);
                    i += 2;
                }
                "binc" => {
                    inc[BLACK] = val.unwrap_or(0);
                    i += 2;
                }
                _ => i += 1,
            }
        }

        if let Some(d) = perft_depth {
            self.run_perft(d);
            return;
        }

        // Time budget for this move.
        let budget_ms: Option<u64> = if let Some(mt) = movetime {
            Some(mt.saturating_sub((mt / 10).max(5)))
        } else if let Some(t) = clock[self.board.side] {
            let my_inc = inc[self.board.side];
            Some((t / 25 + my_inc * 3 / 4).min(t.saturating_sub(50)).max(1))
        } else {
            None
        };
        let deadline = budget_ms.map(|ms| Instant::now() + Duration::from_millis(ms));
        let max_depth = depth.unwrap_or(DEFAULT_MAX_DEPTH);

        self.stop.store(false, Ordering::Relaxed);
        let mut searcher = self.searcher.take().expect("searcher available after halt");
        let board = self.board;
        let history = self.history.clone();
        self.handle = Some(
            thread::Builder::new()
                .stack_size(64 << 20)
                .spawn(move || {
                    let mv = searcher.think(&board, &history, max_depth, deadline);
                    println!("bestmove {}", mv.to_uci());
                    io::stdout().flush().ok();
                    searcher
                })
                .expect("spawn search thread"),
        );
    }

    fn run_perft(&mut self, depth: u32) {
        let mut total = 0u64;
        for m in legal_moves(&self.board, false).as_slice().to_vec() {
            let n = if depth == 0 { 1 } else { perft(&self.board.make(m), depth - 1) };
            println!("{}: {}", m.to_uci(), n);
            total += n;
        }
        println!("Nodes searched: {}", total);
    }
}

fn main() {
    let mut eng = Engine::new();
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let line = match line {
            Ok(l) => l,
            Err(_) => break,
        };
        let tokens: Vec<&str> = line.split_whitespace().collect();
        let Some(&cmd) = tokens.first() else { continue };
        let args = &tokens[1..];
        match cmd {
            "uci" => {
                println!("id name RustChess 1.0");
                println!("id author RustChess authors");
                println!("uciok");
            }
            "isready" => println!("readyok"),
            "ucinewgame" => eng.reset_game(),
            "position" => eng.cmd_position(args),
            "go" => eng.cmd_go(args),
            "stop" => eng.halt(),
            "quit" => {
                eng.halt();
                break;
            }
            _ => {}
        }
        io::stdout().flush().ok();
    }
    eng.halt();
}
