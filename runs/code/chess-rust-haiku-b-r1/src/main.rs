//! RustChess: a UCI chess engine with no external dependencies.

mod board;
mod eval;
mod movegen;
mod search;

use std::io::{self, BufRead};
use std::sync::atomic::Ordering;
use std::sync::mpsc;
use std::thread;

use board::Position;
use movegen::{divide, Move, MoveList};
use search::{Limits, STOP, TT};

/// Transposition table size: 2^20 entries.
const TT_LOG2: u32 = 20;

struct State {
    pos: Position,
    /// Hashes of the positions before `pos` in the game.
    hashes: Vec<u64>,
    tt: TT,
}

fn main() {
    let (tx, rx) = mpsc::channel::<String>();

    // Input thread: `stop` and `quit` must take effect while a search is running,
    // so they are handled here; everything else goes to the main loop in order.
    thread::spawn(move || {
        for line in io::stdin().lock().lines() {
            let Ok(line) = line else { break };
            let line = line.trim().to_string();
            let cmd = line.split_whitespace().next().unwrap_or("");
            match cmd {
                "stop" => STOP.store(true, Ordering::SeqCst),
                "quit" => {
                    // Stop any running search, then let the main loop reach `quit` in order.
                    STOP.store(true, Ordering::SeqCst);
                    let _ = tx.send(line);
                    break;
                }
                _ => {
                    if cmd == "go" {
                        STOP.store(false, Ordering::SeqCst);
                    }
                    if tx.send(line).is_err() {
                        break;
                    }
                }
            }
        }
        // End of input: finish any running search and shut down.
        STOP.store(true, Ordering::SeqCst);
    });

    let mut st = State { pos: Position::startpos(), hashes: Vec::new(), tt: TT::new(TT_LOG2) };
    for line in rx {
        let tokens: Vec<&str> = line.split_whitespace().collect();
        let Some(&cmd) = tokens.first() else { continue };
        match cmd {
            "uci" => {
                println!("id name RustChess 1.0");
                println!("id author RustChess contributors");
                println!("uciok");
            }
            "isready" => println!("readyok"),
            "quit" => break,
            "ucinewgame" => {
                st.tt.clear();
                st.pos = Position::startpos();
                st.hashes.clear();
            }
            "position" => cmd_position(&mut st, &tokens[1..]),
            "go" => cmd_go(&mut st, &tokens[1..]),
            _ => {} // setoption, debug, register and unknown commands are ignored
        }
    }
}

fn cmd_position(st: &mut State, args: &[&str]) {
    let (mut pos, mut i) = match args.first() {
        Some(&"startpos") => (Position::startpos(), 1),
        Some(&"fen") => {
            let end = args.iter().position(|&t| t == "moves").unwrap_or(args.len());
            let fen = args[1..end].join(" ");
            match Position::from_fen(&fen) {
                Ok(p) => (p, end),
                Err(_) => return,
            }
        }
        _ => return,
    };
    let mut hashes = Vec::new();
    if args.get(i) == Some(&"moves") {
        i += 1;
        for tok in &args[i..] {
            let Some(m) = parse_move(&pos, tok) else { break };
            hashes.push(pos.hash);
            pos = pos.make(m);
        }
    }
    st.pos = pos;
    st.hashes = hashes;
}

/// Finds the legal move whose long algebraic notation is `s`.
fn parse_move(pos: &Position, s: &str) -> Option<Move> {
    let mut list = MoveList::new();
    pos.gen_moves(&mut list, false);
    (0..list.len)
        .map(|i| list.moves[i])
        .find(|&m| m.to_uci() == s && pos.make(m).legal_after_move(pos.stm))
}

fn cmd_go(st: &mut State, args: &[&str]) {
    if args.first() == Some(&"perft") {
        let depth = args.get(1).and_then(|s| s.parse::<u32>().ok()).unwrap_or(1);
        perft_divide(&st.pos, depth);
        return;
    }
    let mut limits = Limits::default();
    let mut i = 0;
    while i < args.len() {
        let val = args.get(i + 1).and_then(|s| s.parse::<u64>().ok());
        match args[i] {
            "depth" => {
                limits.depth = val.map(|v| v as u32);
                i += 2;
            }
            "movetime" => {
                limits.movetime = val;
                i += 2;
            }
            "wtime" => {
                limits.time[0] = val;
                i += 2;
            }
            "btime" => {
                limits.time[1] = val;
                i += 2;
            }
            "winc" => {
                limits.inc[0] = val.unwrap_or(0);
                i += 2;
            }
            "binc" => {
                limits.inc[1] = val.unwrap_or(0);
                i += 2;
            }
            "movestogo" | "nodes" | "mate" => i += 2,
            _ => i += 1,
        }
    }
    let best = search::think(&st.pos, st.hashes.clone(), &mut st.tt, &limits);
    println!("bestmove {}", best.to_uci());
}

fn perft_divide(pos: &Position, depth: u32) {
    if depth == 0 {
        println!("Nodes searched: 1");
        return;
    }
    let mut total = 0u64;
    for (m, n) in divide(pos, depth) {
        println!("{}: {}", m.to_uci(), n);
        total += n;
    }
    println!("Nodes searched: {total}");
}
