//! UCI chess engine. Reads commands on stdin; searches run on a worker thread so `stop` and `quit` work mid-search.

mod board;
mod movegen;
mod search;

use std::io::{self, BufRead, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::thread::{self, JoinHandle};
use std::time::{Duration, Instant};

use board::{from_fen, Position};
use movegen::{legal_moves, perft};
use search::{new_table, Entry, Searcher, MAX_DEPTH};

struct State {
    pos: Position,
    tt: Arc<Mutex<Vec<Entry>>>,
    stop: Option<Arc<AtomicBool>>,
    worker: Option<JoinHandle<()>>,
}

enum Job {
    Perft(u32),
    Search { max_depth: i32, deadline: Option<Instant> },
}

fn parse_position(args: &[&str]) -> Option<Position> {
    let (mut pos, rest) = match args.first()? {
        &"startpos" => (Position::startpos(), &args[1..]),
        &"fen" => {
            let end = args.iter().position(|&t| t == "moves").unwrap_or(args.len());
            let fen = args[1..end].join(" ");
            (from_fen(&fen).ok()?, &args[end..])
        }
        _ => return None,
    };
    if rest.first() == Some(&"moves") {
        for mv in &rest[1..] {
            let m = legal_moves(&mut pos, false).into_iter().find(|m| m.uci() == *mv)?;
            pos.make_move(m);
        }
    }
    Some(pos)
}

fn parse_go(args: &[&str], pos: &Position) -> Job {
    let mut depth: Option<i32> = None;
    let mut movetime: Option<u64> = None;
    let mut time = [None::<u64>; 2];
    let mut inc = [0u64; 2];
    let mut movestogo: Option<u64> = None;
    let mut perft_depth: Option<u32> = None;

    let mut i = 0;
    while i < args.len() {
        let val = args.get(i + 1).and_then(|v| v.parse::<i64>().ok());
        match args[i] {
            "perft" => perft_depth = val.map(|v| v.max(0) as u32),
            "depth" => depth = val.map(|v| v as i32),
            "movetime" => movetime = val.map(|v| v.max(0) as u64),
            "wtime" => time[0] = val.map(|v| v.max(0) as u64),
            "btime" => time[1] = val.map(|v| v.max(0) as u64),
            "winc" => inc[0] = val.map(|v| v.max(0) as u64).unwrap_or(0),
            "binc" => inc[1] = val.map(|v| v.max(0) as u64).unwrap_or(0),
            "movestogo" => movestogo = val.map(|v| v.max(1) as u64),
            _ => {}
        }
        // Every keyword except "infinite" and "ponder" takes one value.
        i += if matches!(args[i], "infinite" | "ponder") { 1 } else { 2 };
    }

    if let Some(d) = perft_depth {
        return Job::Perft(d);
    }

    let now = Instant::now();
    let mut deadline = None;
    if let Some(ms) = movetime {
        // Leave a small margin for output and scheduling.
        let budget = ms.saturating_sub(ms / 10 + 5);
        deadline = Some(now + Duration::from_millis(budget));
    } else if let Some(left) = time[pos.stm as usize] {
        let mtg = movestogo.unwrap_or(30).max(1);
        let mut budget = left / mtg + inc[pos.stm as usize] * 3 / 4;
        budget = budget.min(left.saturating_sub(50)).max(5);
        deadline = Some(now + Duration::from_millis(budget));
    }

    Job::Search {
        max_depth: depth.unwrap_or(MAX_DEPTH).clamp(1, MAX_DEPTH),
        deadline,
    }
}

fn stop_search(st: &mut State) {
    if let Some(stop) = st.stop.take() {
        stop.store(true, Ordering::Relaxed);
    }
    if let Some(h) = st.worker.take() {
        let _ = h.join();
    }
}

fn start_search(st: &mut State, max_depth: i32, deadline: Option<Instant>) {
    let stop = Arc::new(AtomicBool::new(false));
    st.stop = Some(stop.clone());
    let pos = st.pos.clone();
    let tt = st.tt.clone();
    st.worker = Some(thread::spawn(move || {
        let mut table = tt.lock().unwrap_or_else(|e| e.into_inner());
        let mut s = Searcher::new(pos, &mut table[..], stop, deadline);
        let best = s.search_root(max_depth);
        println!("bestmove {}", best.map(|m| m.uci()).unwrap_or_else(|| "0000".into()));
        let _ = io::stdout().flush();
    }));
}

fn run_perft(pos: &Position, depth: u32) {
    let mut p = pos.clone();
    let mut total = 0u64;
    for m in legal_moves(&mut p, false) {
        p.make_move(m);
        let n = if depth <= 1 { 1 } else { perft(&mut p, depth - 1) };
        p.unmake_move(m);
        println!("{}: {}", m.uci(), n);
        total += n;
    }
    println!("Nodes searched: {total}");
}

fn main() {
    let mut st = State {
        pos: Position::startpos(),
        tt: Arc::new(Mutex::new(new_table())),
        stop: None,
        worker: None,
    };

    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let Ok(line) = line else { break };
        let toks: Vec<&str> = line.split_whitespace().collect();
        let Some(&cmd) = toks.first() else { continue };
        let args = &toks[1..];
        match cmd {
            "uci" => {
                println!("id name RustChess 1.0");
                println!("id author RustChess authors");
                println!("uciok");
            }
            "isready" => println!("readyok"),
            "ucinewgame" => {
                stop_search(&mut st);
                if let Ok(mut t) = st.tt.lock() {
                    t.iter_mut().for_each(|e| *e = Entry::default());
                }
                st.pos = Position::startpos();
            }
            "position" => {
                stop_search(&mut st);
                if let Some(p) = parse_position(args) {
                    st.pos = p;
                }
            }
            "go" => {
                stop_search(&mut st);
                match parse_go(args, &st.pos) {
                    Job::Perft(d) => run_perft(&st.pos, d),
                    Job::Search { max_depth, deadline } => start_search(&mut st, max_depth, deadline),
                }
            }
            "stop" => stop_search(&mut st),
            "quit" => {
                stop_search(&mut st);
                break;
            }
            _ => {}
        }
        let _ = io::stdout().flush();
    }
    stop_search(&mut st);
}
