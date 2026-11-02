//! Iterative-deepening alpha-beta search with a transposition table, quiescence search,
//! null-move and late-move reductions, killer and history heuristics, and time management.

use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use crate::board::*;
use crate::eval::evaluate;
use crate::movegen::{Move, MoveList};

/// Set by the input thread on `stop`; polled by the search.
pub static STOP: AtomicBool = AtomicBool::new(false);

pub const INF: i32 = 32_000;
pub const MATE: i32 = 31_000;
pub const MATE_BOUND: i32 = 30_000;
const MAX_PLY: usize = 128;

const BOUND_NONE: u8 = 0;
const BOUND_EXACT: u8 = 1;
const BOUND_LOWER: u8 = 2;
const BOUND_UPPER: u8 = 3;

#[derive(Default, Clone)]
pub struct Limits {
    pub depth: Option<u32>,
    pub movetime: Option<u64>,
    /// Remaining time for white and black, in milliseconds.
    pub time: [Option<u64>; 2],
    /// Increment for white and black, in milliseconds.
    pub inc: [u64; 2],
}

#[derive(Clone, Copy)]
struct TTEntry {
    key: u64,
    mv: Move,
    score: i32,
    depth: i32,
    bound: u8,
}

const EMPTY_ENTRY: TTEntry = TTEntry { key: 0, mv: Move::NONE, score: 0, depth: 0, bound: BOUND_NONE };

pub struct TT {
    entries: Vec<TTEntry>,
    mask: usize,
}

impl TT {
    pub fn new(log2_size: u32) -> TT {
        let n = 1usize << log2_size;
        TT { entries: vec![EMPTY_ENTRY; n], mask: n - 1 }
    }

    pub fn clear(&mut self) {
        for e in &mut self.entries {
            *e = EMPTY_ENTRY;
        }
    }

    fn probe(&self, key: u64) -> Option<TTEntry> {
        let e = self.entries[key as usize & self.mask];
        if e.bound != BOUND_NONE && e.key == key {
            Some(e)
        } else {
            None
        }
    }

    fn store(&mut self, key: u64, mv: Move, score: i32, depth: i32, bound: u8) {
        let idx = key as usize & self.mask;
        let old = self.entries[idx];
        // Keep the previous best move for this position when the new search has none.
        let mv = if mv == Move::NONE && old.key == key { old.mv } else { mv };
        self.entries[idx] = TTEntry { key, mv, score, depth, bound };
    }
}

fn score_to_tt(s: i32, ply: usize) -> i32 {
    if s >= MATE_BOUND {
        s + ply as i32
    } else if s <= -MATE_BOUND {
        s - ply as i32
    } else {
        s
    }
}

fn score_from_tt(s: i32, ply: usize) -> i32 {
    if s >= MATE_BOUND {
        s - ply as i32
    } else if s <= -MATE_BOUND {
        s + ply as i32
    } else {
        s
    }
}

/// Ordering value of a piece kind (for MVV-LVA).
const ORDER_VALUE: [i32; 6] = [100, 320, 330, 500, 900, 2000];

struct Searcher<'a> {
    tt: &'a mut TT,
    /// Hashes of ancestor positions (game history and the current search path).
    hist: Vec<u64>,
    nodes: u64,
    killers: [[Move; 2]; MAX_PLY],
    /// History heuristic, indexed by (side, from, to).
    hh: Vec<i32>,
    pv: [[Move; MAX_PLY]; MAX_PLY],
    pv_len: [usize; MAX_PLY],
    hard_deadline: Option<Instant>,
    aborted: bool,
}

impl<'a> Searcher<'a> {
    #[inline]
    fn stop_now(&self) -> bool {
        STOP.load(Ordering::Relaxed) || self.hard_deadline.is_some_and(|d| Instant::now() >= d)
    }

    fn is_repetition(&self, pos: &Position) -> bool {
        let n = self.hist.len();
        let max_back = (pos.halfmove as usize).min(n);
        let mut back = 2;
        while back <= max_back {
            if self.hist[n - back] == pos.hash {
                return true;
            }
            back += 2;
        }
        false
    }

    fn update_pv(&mut self, ply: usize, m: Move) {
        self.pv[ply][0] = m;
        let n = self.pv_len[ply + 1];
        for i in 0..n {
            self.pv[ply][i + 1] = self.pv[ply + 1][i];
        }
        self.pv_len[ply] = n + 1;
    }

    fn update_killer(&mut self, ply: usize, m: Move) {
        if self.killers[ply][0] != m {
            self.killers[ply][1] = self.killers[ply][0];
            self.killers[ply][0] = m;
        }
    }

    fn update_history(&mut self, side: usize, m: Move, depth: i32) {
        let idx = (side * 64 + m.from()) * 64 + m.to();
        self.hh[idx] = (self.hh[idx] + depth * depth).min(400_000);
    }

    fn score_moves(&self, pos: &Position, list: &MoveList, tt_move: Move, ply: usize, scores: &mut [i32; 256]) {
        for i in 0..list.len {
            let m = list.moves[i];
            scores[i] = if m == tt_move {
                3_000_000
            } else if m.is_capture() {
                let victim = if m.is_ep() { PAWN } else { pos.board[m.to()] as usize % 6 };
                let attacker = pos.board[m.from()] as usize % 6;
                1_000_000 + ORDER_VALUE[victim] * 10 - ORDER_VALUE[attacker] / 10
            } else if m.promo() != 0 {
                900_000 + ORDER_VALUE[m.promo()]
            } else if m == self.killers[ply][0] {
                800_000
            } else if m == self.killers[ply][1] {
                790_000
            } else {
                self.hh[(pos.stm * 64 + m.from()) * 64 + m.to()]
            };
        }
    }

    /// Selection step: moves the best-scored move among `i..len` to position `i`.
    #[inline]
    fn pick(list: &mut MoveList, scores: &mut [i32; 256], i: usize) -> Move {
        let mut best = i;
        for j in i + 1..list.len {
            if scores[j] > scores[best] {
                best = j;
            }
        }
        list.moves.swap(i, best);
        scores.swap(i, best);
        list.moves[i]
    }

    fn negamax(&mut self, pos: &Position, depth: i32, ply: usize, mut alpha: i32, beta: i32, allow_null: bool) -> i32 {
        self.pv_len[ply] = 0;
        self.nodes += 1;
        if self.nodes & 2047 == 0 && self.stop_now() {
            self.aborted = true;
        }
        if self.aborted {
            return 0;
        }
        if ply > 0 {
            if pos.halfmove >= 100 || self.is_repetition(pos) {
                return 0;
            }
            if ply >= MAX_PLY - 1 {
                return evaluate(pos);
            }
        }

        let pv_node = beta - alpha > 1;
        let in_check = pos.in_check();
        // Check extension.
        let depth = if in_check { depth + 1 } else { depth };
        if depth <= 0 {
            return self.qsearch(pos, alpha, beta, ply);
        }

        let mut tt_move = Move::NONE;
        if let Some(e) = self.tt.probe(pos.hash) {
            tt_move = e.mv;
            if ply > 0 && !pv_node && e.depth >= depth {
                let s = score_from_tt(e.score, ply);
                let cut = match e.bound {
                    BOUND_EXACT => true,
                    BOUND_LOWER => s >= beta,
                    BOUND_UPPER => s <= alpha,
                    _ => false,
                };
                if cut {
                    return s;
                }
            }
        }

        // Null-move pruning.
        if !pv_node && !in_check && allow_null && depth >= 3 && pos.has_non_pawn(pos.stm) && evaluate(pos) >= beta {
            let r = 3 + depth / 6;
            self.hist.push(pos.hash);
            let np = pos.make_null();
            let s = -self.negamax(&np, depth - 1 - r, ply + 1, -beta, -beta + 1, false);
            self.hist.pop();
            if self.aborted {
                return 0;
            }
            if s >= beta {
                return if s >= MATE_BOUND { beta } else { s };
            }
        }

        let mut list = MoveList::new();
        pos.gen_moves(&mut list, false);
        let mut scores = [0i32; 256];
        self.score_moves(pos, &list, tt_move, ply, &mut scores);

        let orig_alpha = alpha;
        let mut best = -INF;
        let mut best_move = Move::NONE;
        let mut legal = 0;
        for i in 0..list.len {
            let m = Self::pick(&mut list, &mut scores, i);
            let child = pos.make(m);
            if !child.legal_after_move(pos.stm) {
                continue;
            }
            legal += 1;
            let quiet = m.is_quiet();
            let gives_check = child.in_check();
            let reduce = if depth >= 3 && legal > 3 && quiet && !in_check && !gives_check && !pv_node {
                if legal > 8 {
                    2
                } else {
                    1
                }
            } else {
                0
            };

            self.hist.push(pos.hash);
            let new_depth = depth - 1;
            let mut s;
            if legal == 1 {
                s = -self.negamax(&child, new_depth, ply + 1, -beta, -alpha, true);
            } else {
                s = -self.negamax(&child, new_depth - reduce, ply + 1, -alpha - 1, -alpha, true);
                if s > alpha && reduce > 0 {
                    s = -self.negamax(&child, new_depth, ply + 1, -alpha - 1, -alpha, true);
                }
                if s > alpha && s < beta {
                    s = -self.negamax(&child, new_depth, ply + 1, -beta, -alpha, true);
                }
            }
            self.hist.pop();
            if self.aborted {
                return 0;
            }

            if s > best {
                best = s;
                best_move = m;
                if s > alpha {
                    alpha = s;
                    self.update_pv(ply, m);
                    if s >= beta {
                        if quiet {
                            self.update_killer(ply, m);
                            self.update_history(pos.stm, m, depth);
                        }
                        break;
                    }
                }
            }
        }

        if legal == 0 {
            return if in_check { -MATE + ply as i32 } else { 0 };
        }
        let bound = if best >= beta {
            BOUND_LOWER
        } else if best > orig_alpha {
            BOUND_EXACT
        } else {
            BOUND_UPPER
        };
        self.tt.store(pos.hash, best_move, score_to_tt(best, ply), depth, bound);
        best
    }

    /// Quiescence search: captures and promotions; all evasions when in check.
    fn qsearch(&mut self, pos: &Position, mut alpha: i32, beta: i32, ply: usize) -> i32 {
        self.nodes += 1;
        if self.nodes & 2047 == 0 && self.stop_now() {
            self.aborted = true;
        }
        if self.aborted {
            return 0;
        }
        if ply >= MAX_PLY - 1 {
            return evaluate(pos);
        }
        let in_check = pos.in_check();
        let mut best;
        if in_check {
            best = -INF;
        } else {
            let stand = evaluate(pos);
            if stand >= beta {
                return stand;
            }
            if stand > alpha {
                alpha = stand;
            }
            best = stand;
        }

        let mut list = MoveList::new();
        pos.gen_moves(&mut list, !in_check);
        let mut scores = [0i32; 256];
        for i in 0..list.len {
            let m = list.moves[i];
            scores[i] = if m.is_capture() {
                let victim = if m.is_ep() { PAWN } else { pos.board[m.to()] as usize % 6 };
                let attacker = pos.board[m.from()] as usize % 6;
                1_000_000 + ORDER_VALUE[victim] * 10 - ORDER_VALUE[attacker] / 10
            } else if m.promo() != 0 {
                900_000 + ORDER_VALUE[m.promo()]
            } else {
                0
            };
        }

        let mut legal = 0;
        for i in 0..list.len {
            let m = Self::pick(&mut list, &mut scores, i);
            let child = pos.make(m);
            if !child.legal_after_move(pos.stm) {
                continue;
            }
            legal += 1;
            let s = -self.qsearch(&child, -beta, -alpha, ply + 1);
            if self.aborted {
                return 0;
            }
            if s > best {
                best = s;
                if s > alpha {
                    alpha = s;
                    if s >= beta {
                        return s;
                    }
                }
            }
        }
        if in_check && legal == 0 {
            return -MATE + ply as i32;
        }
        best
    }
}

fn time_limits(l: &Limits, stm: usize) -> (Option<Duration>, Option<Duration>) {
    if let Some(mt) = l.movetime {
        let d = Duration::from_millis(mt.saturating_sub(10).max(1));
        return (Some(d), Some(d));
    }
    if let Some(t) = l.time[stm] {
        let inc = l.inc[stm];
        let soft = (t / 30 + inc * 3 / 4).min(t.saturating_sub(10)).max(1);
        let hard = (soft * 3).min(t / 2).max(1);
        return (Some(Duration::from_millis(soft)), Some(Duration::from_millis(hard)));
    }
    (None, None)
}

/// Searches `root` and returns the best move (`Move::NONE` if there are no legal moves).
/// `history` holds the hashes of the positions before `root` in the game.
/// Prints `info` lines as iterations complete; the caller prints `bestmove`.
pub fn think(root: &Position, history: Vec<u64>, tt: &mut TT, limits: &Limits) -> Move {
    let start = Instant::now();
    let (soft, hard) = time_limits(limits, root.stm);
    let mut s = Searcher {
        tt,
        hist: history,
        nodes: 0,
        killers: [[Move::NONE; 2]; MAX_PLY],
        hh: vec![0; 2 * 64 * 64],
        pv: [[Move::NONE; MAX_PLY]; MAX_PLY],
        pv_len: [0; MAX_PLY],
        hard_deadline: hard.map(|h| start + h),
        aborted: false,
    };
    let max_depth = limits.depth.unwrap_or(MAX_PLY as u32 - 2).clamp(1, MAX_PLY as u32 - 2);

    // Fallback if the first iteration is cut short: any legal move.
    let mut best = root.legal_moves().first().copied().unwrap_or(Move::NONE);
    for depth in 1..=max_depth {
        let score = s.negamax(root, depth as i32, 0, -INF, INF, true);
        if s.aborted {
            break;
        }
        best = s.pv[0][0];
        let elapsed = start.elapsed();
        let ms = elapsed.as_millis().max(1);
        let score_str = if score.abs() >= MATE_BOUND {
            let plies = MATE - score.abs();
            let moves = (plies + 1) / 2;
            format!("mate {}", if score > 0 { moves } else { -moves })
        } else {
            format!("cp {score}")
        };
        let pv: Vec<String> = (0..s.pv_len[0]).map(|i| s.pv[0][i].to_uci()).collect();
        println!(
            "info depth {} score {} nodes {} nps {} time {} pv {}",
            depth,
            score_str,
            s.nodes,
            s.nodes as u128 * 1000 / ms,
            ms,
            pv.join(" ")
        );
        // A mate for us within the searched horizon cannot be improved on by a later iteration.
        if score > MATE_BOUND && MATE - score <= depth as i32 {
            break;
        }
        if soft.is_some_and(|d| elapsed >= d) {
            break;
        }
    }
    best
}
