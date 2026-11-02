//! Iterative-deepening principal-variation search with quiescence, a transposition table,
//! killer and history heuristics, null-move and late-move reductions, and draw detection.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Instant;

use crate::board::*;
use crate::eval::{evaluate, MG_VAL};
use crate::movegen::{gen_pseudo, is_legal, legal_moves, MoveList};

pub const MAX_DEPTH: i32 = 64;
const INF: i32 = 32_000;
const MATE: i32 = 31_000;
const MATE_BOUND: i32 = 30_000;
const MAX_PLY: usize = 128;
const TT_LOG2: u32 = 20;

#[derive(Clone, Copy, PartialEq, Eq, Default)]
enum Bound {
    #[default]
    Exact,
    Lower,
    Upper,
}

#[derive(Clone, Copy, Default)]
struct TTEntry {
    key: u64,
    mv: Move,
    score: i32,
    depth: i32,
    bound: Bound,
}

pub struct Searcher {
    tt: Vec<TTEntry>,
    stop: Arc<AtomicBool>,
    killers: [[Move; 2]; MAX_PLY],
    history: Box<[[[i32; 64]; 64]; 2]>,
    /// Hashes of the positions on the current line, the root included; used for repetition checks.
    hist: Vec<u64>,
    nodes: u64,
    deadline: Option<Instant>,
    stopped: bool,
    start: Instant,
}

impl Searcher {
    pub fn new(stop: Arc<AtomicBool>) -> Self {
        Searcher {
            tt: vec![TTEntry::default(); 1 << TT_LOG2],
            stop,
            killers: [[Move::NONE; 2]; MAX_PLY],
            history: Box::new([[[0; 64]; 64]; 2]),
            hist: Vec::new(),
            nodes: 0,
            deadline: None,
            stopped: false,
            start: Instant::now(),
        }
    }

    /// Forgets everything learned from earlier searches.
    pub fn clear(&mut self) {
        self.tt.iter_mut().for_each(|e| *e = TTEntry::default());
        self.killers = [[Move::NONE; 2]; MAX_PLY];
        *self.history = [[[0; 64]; 64]; 2];
    }

    /// Searches `root` up to `max_depth` plies or until `deadline`, and returns the best move
    /// (`Move::NONE` when there are no legal moves). `game_history` holds the hashes of the
    /// positions that came before `root`.
    pub fn search(&mut self, root: &Position, game_history: &[u64], max_depth: i32, deadline: Option<Instant>) -> Move {
        self.nodes = 0;
        self.stopped = false;
        self.start = Instant::now();
        self.deadline = deadline;
        self.hist.clear();
        self.hist.extend_from_slice(game_history);
        self.hist.push(root.hash);

        let mut root_moves: Vec<(Move, i32)> = legal_moves(root).into_iter().map(|m| (m, -INF)).collect();
        if root_moves.is_empty() {
            return Move::NONE;
        }
        let mut best = root_moves[0].0;
        if root_moves.len() == 1 {
            return best;
        }
        for depth in 1..=max_depth.clamp(1, MAX_DEPTH) {
            if !self.root_search(root, depth, &mut root_moves) {
                break;
            }
            root_moves.sort_by_key(|&(_, score)| std::cmp::Reverse(score));
            best = root_moves[0].0;
            let score = root_moves[0].1;
            self.report(depth, score, best);
            // A mate inside the searched depth is proven; further iterations cannot change the move.
            if score.abs() >= MATE_BOUND && MATE - score.abs() <= depth {
                break;
            }
        }
        best
    }

    /// One full-width iteration at the root. Returns false when the search was stopped.
    fn root_search(&mut self, root: &Position, depth: i32, moves: &mut [(Move, i32)]) -> bool {
        let mut alpha = -INF;
        let beta = INF;
        for i in 0..moves.len() {
            let child = root.make(moves[i].0);
            let score = if i == 0 {
                -self.negamax(&child, -beta, -alpha, depth - 1, 1)
            } else {
                let mut s = -self.negamax(&child, -alpha - 1, -alpha, depth - 1, 1);
                if s > alpha {
                    s = -self.negamax(&child, -beta, -alpha, depth - 1, 1);
                }
                s
            };
            if self.stopped {
                return false;
            }
            moves[i].1 = score;
            if score > alpha {
                alpha = score;
            }
        }
        true
    }

    fn report(&self, depth: i32, score: i32, best: Move) {
        let ms = self.start.elapsed().as_millis().max(1) as u64;
        let nps = self.nodes * 1000 / ms;
        let score_text = if score.abs() >= MATE_BOUND {
            let moves = (MATE - score.abs() + 1) / 2;
            format!("mate {}", if score > 0 { moves } else { -moves })
        } else {
            format!("cp {score}")
        };
        println!("info depth {depth} score {score_text} nodes {} nps {nps} time {ms} pv {}", self.nodes, best.uci());
    }

    /// Counts a node and checks the stop flag and deadline every 1024 nodes. Returns true when stopped.
    #[inline]
    fn tick(&mut self) -> bool {
        self.nodes += 1;
        if self.nodes & 1023 == 0 && !self.stopped {
            if self.stop.load(Ordering::Relaxed) {
                self.stopped = true;
            } else if let Some(d) = self.deadline {
                if Instant::now() >= d {
                    self.stopped = true;
                }
            }
        }
        self.stopped
    }

    /// True when the current position (top of `hist`) is a draw by the fifty-move rule or repetition.
    fn is_draw(&self, pos: &Position) -> bool {
        if pos.halfmove >= 100 {
            return true;
        }
        let n = self.hist.len();
        let limit = (pos.halfmove as usize).min(n - 1);
        let mut back = 2;
        while back <= limit {
            if self.hist[n - 1 - back] == pos.hash {
                return true;
            }
            back += 2;
        }
        false
    }

    fn negamax(&mut self, pos: &Position, alpha: i32, beta: i32, depth: i32, ply: usize) -> i32 {
        self.hist.push(pos.hash);
        let score = self.node(pos, alpha, beta, depth, ply);
        self.hist.pop();
        score
    }

    fn node(&mut self, pos: &Position, mut alpha: i32, beta: i32, mut depth: i32, ply: usize) -> i32 {
        if self.tick() {
            return 0;
        }
        if ply > 0 && self.is_draw(pos) {
            return 0;
        }
        if ply >= MAX_PLY - 1 {
            return evaluate(pos);
        }
        let us = pos.side;
        let in_check = pos.in_check();
        if in_check {
            depth += 1;
        }
        if depth <= 0 {
            return self.qsearch(pos, alpha, beta, ply);
        }
        let is_pv = beta - alpha > 1;

        let idx = (pos.hash as usize) & (self.tt.len() - 1);
        let entry = self.tt[idx];
        let mut tt_move = Move::NONE;
        if entry.key == pos.hash {
            tt_move = entry.mv;
            if ply > 0 && !is_pv && entry.depth >= depth {
                let s = score_from_tt(entry.score, ply);
                let cut = match entry.bound {
                    Bound::Exact => true,
                    Bound::Lower => s >= beta,
                    Bound::Upper => s <= alpha,
                };
                if cut {
                    return s;
                }
            }
        }

        // Null-move pruning: if passing still beats beta, the position is good enough to cut.
        if !is_pv && !in_check && depth >= 3 && beta.abs() < MATE_BOUND && pos.has_non_pawn(us) && evaluate(pos) >= beta {
            let r = 2 + depth / 4;
            let child = pos.make_null();
            let s = -self.negamax(&child, -beta, -beta + 1, depth - 1 - r, ply + 1);
            if self.stopped {
                return 0;
            }
            if s >= beta {
                return beta;
            }
        }

        let mut list = MoveList::new();
        gen_pseudo(pos, &mut list, false);
        let n = list.len;
        let mut scores = self.score_moves(pos, &list, tt_move, ply);
        let orig_alpha = alpha;
        let mut best = -INF;
        let mut best_move = Move::NONE;
        let mut legal = 0;
        for i in 0..n {
            pick_best(&mut list.moves, &mut scores, i, n);
            let m = list.moves[i];
            let child = pos.make(m);
            if !is_legal(&child, us) {
                continue;
            }
            legal += 1;
            let quiet = is_quiet(pos, m);
            let new_depth = depth - 1;
            let score = if legal == 1 {
                -self.negamax(&child, -beta, -alpha, new_depth, ply + 1)
            } else {
                // Late quiet moves are searched shallower first; a surprise re-searches at full depth.
                let mut red = 0;
                if quiet && !in_check && new_depth >= 2 && legal > 3 {
                    red = if legal > 8 { 2 } else { 1 };
                }
                let mut s = -self.negamax(&child, -alpha - 1, -alpha, new_depth - red, ply + 1);
                if red > 0 && s > alpha {
                    s = -self.negamax(&child, -alpha - 1, -alpha, new_depth, ply + 1);
                }
                if s > alpha && s < beta {
                    s = -self.negamax(&child, -beta, -alpha, new_depth, ply + 1);
                }
                s
            };
            if self.stopped {
                return 0;
            }
            if score > best {
                best = score;
                best_move = m;
                if score > alpha {
                    alpha = score;
                    if alpha >= beta {
                        if quiet {
                            self.note_quiet_cutoff(us, ply, m, depth);
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
            Bound::Lower
        } else if best > orig_alpha {
            Bound::Exact
        } else {
            Bound::Upper
        };
        self.tt[idx] = TTEntry { key: pos.hash, mv: best_move, score: score_to_tt(best, ply), depth, bound };
        best
    }

    /// Quiescence search: resolves captures (and all evasions when in check) to avoid the horizon effect.
    fn qsearch(&mut self, pos: &Position, mut alpha: i32, beta: i32, ply: usize) -> i32 {
        if self.tick() {
            return 0;
        }
        if ply >= MAX_PLY - 1 {
            return evaluate(pos);
        }
        let us = pos.side;
        let in_check = pos.in_check();
        let mut best;
        if in_check {
            best = -INF;
        } else {
            let stand_pat = evaluate(pos);
            if stand_pat >= beta {
                return stand_pat;
            }
            if stand_pat > alpha {
                alpha = stand_pat;
            }
            best = stand_pat;
        }
        let mut list = MoveList::new();
        gen_pseudo(pos, &mut list, !in_check);
        let n = list.len;
        let mut scores = self.score_moves(pos, &list, Move::NONE, ply);
        let mut legal = 0;
        for i in 0..n {
            pick_best(&mut list.moves, &mut scores, i, n);
            let child = pos.make(list.moves[i]);
            if !is_legal(&child, us) {
                continue;
            }
            legal += 1;
            let score = -self.qsearch(&child, -beta, -alpha, ply + 1);
            if self.stopped {
                return 0;
            }
            if score > best {
                best = score;
                if score > alpha {
                    alpha = score;
                    if alpha >= beta {
                        break;
                    }
                }
            }
        }
        if in_check && legal == 0 {
            return -MATE + ply as i32;
        }
        best
    }

    /// Move ordering: hash move, then captures (MVV-LVA), promotions, killers, and history.
    fn score_moves(&self, pos: &Position, list: &MoveList, tt_move: Move, ply: usize) -> [i32; 256] {
        let mut scores = [0i32; 256];
        let us = pos.side;
        for (i, &m) in list.as_slice().iter().enumerate() {
            let victim = pos.board[m.to as usize];
            scores[i] = if m == tt_move {
                10_000_000
            } else if victim != 0 || is_ep_capture(pos, m) {
                let v = if victim != 0 { pt_of(victim) } else { PAWN };
                let attacker = pt_of(pos.board[m.from as usize]);
                1_000_000 + MG_VAL[v] * 8 - MG_VAL[attacker] / 10
            } else if m.promo != 0 {
                950_000 + MG_VAL[m.promo as usize]
            } else if m == self.killers[ply][0] {
                900_000
            } else if m == self.killers[ply][1] {
                890_000
            } else {
                self.history[us][m.from as usize][m.to as usize]
            };
        }
        scores
    }

    fn note_quiet_cutoff(&mut self, us: usize, ply: usize, m: Move, depth: i32) {
        if self.killers[ply][0] != m {
            self.killers[ply][1] = self.killers[ply][0];
            self.killers[ply][0] = m;
        }
        let h = &mut self.history[us][m.from as usize][m.to as usize];
        *h = (*h + depth * depth).min(400_000);
    }
}

fn is_ep_capture(pos: &Position, m: Move) -> bool {
    pt_of(pos.board[m.from as usize]) == PAWN && pos.board[m.to as usize] == 0 && m.from % 8 != m.to % 8
}

fn is_quiet(pos: &Position, m: Move) -> bool {
    m.promo == 0 && pos.board[m.to as usize] == 0 && !is_ep_capture(pos, m)
}

/// Brings the best-scored move from `start..n` to index `start`.
#[inline]
fn pick_best(moves: &mut [Move], scores: &mut [i32], start: usize, n: usize) {
    let mut best = start;
    for j in start + 1..n {
        if scores[j] > scores[best] {
            best = j;
        }
    }
    moves.swap(start, best);
    scores.swap(start, best);
}

/// Mate scores are stored relative to the node, not the root, so they stay valid when transposed.
fn score_to_tt(score: i32, ply: usize) -> i32 {
    if score >= MATE_BOUND {
        score + ply as i32
    } else if score <= -MATE_BOUND {
        score - ply as i32
    } else {
        score
    }
}

fn score_from_tt(score: i32, ply: usize) -> i32 {
    if score >= MATE_BOUND {
        score - ply as i32
    } else if score <= -MATE_BOUND {
        score + ply as i32
    } else {
        score
    }
}
