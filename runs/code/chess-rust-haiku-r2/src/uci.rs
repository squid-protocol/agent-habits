//! The UCI protocol loop: option handling, position setup, search threads, and `go perft`.

use std::io::{self, BufRead, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use crate::board::*;
use crate::movegen::{gen_pseudo, is_legal, legal_moves, perft, MoveList};
use crate::search::{Searcher, MAX_DEPTH};

/// Time kept back from every `movetime` or clock budget for I/O and thread start-up.
const MOVE_OVERHEAD_MS: u64 = 10;
const SEARCH_STACK_BYTES: usize = 64 << 20;

struct Uci {
    pos: Position,
    /// Hashes of the positions before `pos` in the game, for repetition detection.
    history: Vec<u64>,
    stop: Arc<AtomicBool>,
    /// Owned here while idle; moved into the worker thread while a search runs.
    searcher: Option<Searcher>,
    worker: Option<JoinHandle<Searcher>>,
}

impl Uci {
    fn new() -> Self {
        let stop = Arc::new(AtomicBool::new(false));
        Uci {
            pos: Position::startpos(),
            history: Vec::new(),
            searcher: Some(Searcher::new(stop.clone())),
            stop,
            worker: None,
        }
    }

    /// Blocks until any running search has finished and returns its searcher.
    fn wait(&mut self) {
        if let Some(handle) = self.worker.take() {
            if let Ok(searcher) = handle.join() {
                self.searcher = Some(searcher);
            }
        }
    }

    /// `position startpos|fen <fen> [moves ...]`
    fn set_position(&mut self, args: &[&str]) {
        let (mut pos, mut i) = match args.first().copied() {
            Some("startpos") => (Position::startpos(), 1),
            Some("fen") => {
                let end = args.iter().position(|&t| t == "moves").unwrap_or(args.len());
                match Position::from_fen(&args[1..end].join(" ")) {
                    Ok(p) => (p, end),
                    Err(_) => return,
                }
            }
            _ => return,
        };
        let mut history = Vec::new();
        if args.get(i).copied() == Some("moves") {
            i += 1;
            for token in &args[i..] {
                match find_move(&pos, token) {
                    Some(m) => {
                        history.push(pos.hash);
                        pos = pos.make(m);
                    }
                    None => break,
                }
            }
        }
        self.pos = pos;
        self.history = history;
    }

    /// `go ...`: starts a search on a worker thread, or runs `perft` synchronously.
    fn go(&mut self, args: &[&str]) {
        self.wait();
        if args.first().copied() == Some("perft") {
            let depth = args.get(1).and_then(|s| s.parse::<u32>().ok()).unwrap_or(1);
            self.perft_divide(depth);
            return;
        }

        let mut depth: Option<i32> = None;
        let mut movetime: Option<u64> = None;
        let mut time: [Option<u64>; 2] = [None, None];
        let mut inc: [u64; 2] = [0, 0];
        let mut i = 0;
        while i < args.len() {
            let num = args.get(i + 1).and_then(|s| s.parse::<i64>().ok());
            let key = args[i];
            match key {
                "depth" => depth = num.map(|v| v as i32),
                "movetime" => movetime = num.map(|v| v.max(0) as u64),
                "wtime" => time[WHITE] = num.map(|v| v.max(0) as u64),
                "btime" => time[BLACK] = num.map(|v| v.max(0) as u64),
                "winc" => inc[WHITE] = num.map_or(0, |v| v.max(0) as u64),
                "binc" => inc[BLACK] = num.map_or(0, |v| v.max(0) as u64),
                _ => {
                    i += 1;
                    continue;
                }
            }
            i += 2;
        }

        let side = self.pos.side;
        let limit_ms = match movetime {
            Some(mt) => Some(mt.saturating_sub(MOVE_OVERHEAD_MS).max(1)),
            None => time[side].map(|t| {
                let budget = t / 30 + inc[side] * 3 / 4;
                budget.min(t.saturating_sub(MOVE_OVERHEAD_MS)).max(1)
            }),
        };
        let deadline = limit_ms.map(|ms| Instant::now() + Duration::from_millis(ms));
        let max_depth = depth.unwrap_or(MAX_DEPTH).clamp(1, MAX_DEPTH);

        self.stop.store(false, Ordering::SeqCst);
        let mut searcher = self.searcher.take().unwrap_or_else(|| Searcher::new(self.stop.clone()));
        let pos = self.pos;
        let history = self.history.clone();
        let handle = thread::Builder::new()
            .stack_size(SEARCH_STACK_BYTES)
            .spawn(move || {
                let best = searcher.search(&pos, &history, max_depth, deadline);
                let text = if best == Move::NONE { "0000".to_string() } else { best.uci() };
                println!("bestmove {text}");
                let _ = io::stdout().flush();
                searcher
            })
            .expect("failed to spawn search thread");
        self.worker = Some(handle);
    }

    /// `go perft N`: prints the node count under each root move, then the total.
    fn perft_divide(&self, depth: u32) {
        if depth == 0 {
            println!("Nodes searched: 1");
            return;
        }
        let mut total = 0u64;
        let mut list = MoveList::new();
        gen_pseudo(&self.pos, &mut list, false);
        for &m in list.as_slice() {
            let child = self.pos.make(m);
            if !is_legal(&child, self.pos.side) {
                continue;
            }
            let n = if depth == 1 { 1 } else { perft(&child, depth - 1) };
            println!("{}: {}", m.uci(), n);
            total += n;
        }
        println!("Nodes searched: {total}");
    }
}

/// Resolves a UCI move string against the legal moves of `pos`.
fn find_move(pos: &Position, text: &str) -> Option<Move> {
    legal_moves(pos).into_iter().find(|m| m.uci() == text)
}

/// Runs the UCI loop on standard input until `quit` or end of input.
pub fn run() {
    let mut uci = Uci::new();
    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let Ok(line) = line else { break };
        let tokens: Vec<&str> = line.split_whitespace().collect();
        let Some((&cmd, args)) = tokens.split_first() else { continue };
        match cmd {
            "uci" => {
                println!("id name RustChess 1.0");
                println!("id author RustChess contributors");
                println!("uciok");
            }
            "isready" => println!("readyok"),
            "ucinewgame" => {
                uci.wait();
                if let Some(s) = uci.searcher.as_mut() {
                    s.clear();
                }
                uci.pos = Position::startpos();
                uci.history.clear();
            }
            "position" => uci.set_position(args),
            "go" => uci.go(args),
            "stop" => uci.stop.store(true, Ordering::SeqCst),
            "quit" => {
                uci.stop.store(true, Ordering::SeqCst);
                break;
            }
            _ => {}
        }
        let _ = io::stdout().flush();
    }
    uci.stop.store(true, Ordering::SeqCst);
    uci.wait();
    let _ = io::stdout().flush();
}
