//! Alpha-beta search: iterative deepening, PVS, transposition table, quiescence search,
//! null-move and late-move reductions, killer and history heuristics, repetition detection.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Instant;

use crate::board::*;
use crate::eval::{evaluate, has_non_pawn};
use crate::movegen::{legal_moves, MoveList};

pub const MATE: i32 = 30_000;
pub const INF: i32 = 32_000;
const MATE_BOUND: i32 = MATE - 1000;
const MAX_PLY: usize = 128;
const TT_BITS: usize = 20;

const EXACT: u8 = 0;
const LOWER: u8 = 1;
const UPPER: u8 = 2;

#[derive(Clone, Copy, Default)]
struct TTEntry {
    key: u64,
    mv: Move,
    depth: i32,
    score: i32,
    bound: u8,
}

pub struct Searcher {
    tt: Vec<TTEntry>,
    nodes: u64,
    killers: [[Move; 2]; MAX_PLY],
    history: Vec<i32>,
    /// Hashes of all positions from the game start to the current node (for repetition checks).
    path: Vec<u64>,
    stop: Arc<AtomicBool>,
    deadline: Option<Instant>,
    stopped: bool,
    start: Instant,
}

fn to_tt(score: i32, ply: usize) -> i32 {
    if score >= MATE_BOUND {
        score + ply as i32
    } else if score <= -MATE_BOUND {
        score - ply as i32
    } else {
        score
    }
}

fn from_tt(score: i32, ply: usize) -> i32 {
    if score >= MATE_BOUND {
        score - ply as i32
    } else if score <= -MATE_BOUND {
        score + ply as i32
    } else {
        score
    }
}

impl Searcher {
    pub fn new(stop: Arc<AtomicBool>) -> Self {
        Searcher {
            tt: vec![TTEntry::default(); 1 << TT_BITS],
            nodes: 0,
            killers: [[Move::NONE; 2]; MAX_PLY],
            history: vec![0; 2 * 64 * 64],
            path: Vec::new(),
            stop,
            deadline: None,
            stopped: false,
            start: Instant::now(),
        }
    }

    pub fn clear(&mut self) {
        self.tt.iter_mut().for_each(|e| *e = TTEntry::default());
        self.killers = [[Move::NONE; 2]; MAX_PLY];
        self.history.iter_mut().for_each(|h| *h = 0);
    }

    #[inline]
    fn check_stop(&mut self) -> bool {
        if !self.stopped && self.nodes & 2047 == 0 {
            if self.stop.load(Ordering::Relaxed) || self.deadline.is_some_and(|d| Instant::now() >= d) {
                self.stopped = true;
            }
        }
        self.stopped
    }

    /// Draw by fifty-move rule, insufficient material, or repetition of a position in the search path.
    fn is_draw(&self, b: &Board) -> bool {
        if b.halfmove >= 100 {
            return true;
        }
        let heavy = b.pieces[WHITE][PAWN] | b.pieces[BLACK][PAWN] | b.pieces[WHITE][ROOK] | b.pieces[BLACK][ROOK]
            | b.pieces[WHITE][QUEEN] | b.pieces[BLACK][QUEEN];
        if heavy == 0 && (b.pieces[WHITE][KNIGHT] | b.pieces[WHITE][BISHOP] | b.pieces[BLACK][KNIGHT] | b.pieces[BLACK][BISHOP]).count_ones() <= 1 {
            return true;
        }
        let n = self.path.len();
        let mut back = 2;
        while back <= b.halfmove as usize && back < n {
            if self.path[n - 1 - back] == b.hash {
                return true;
            }
            back += 2;
        }
        false
    }

    /// Orders moves: TT move, captures (MVV-LVA), promotions, killers, then history.
    fn score_moves(&self, b: &Board, moves: &MoveList, tt_move: Move, ply: usize, scores: &mut [i32; 256]) {
        let us = b.side;
        let them = us ^ 1;
        for (i, &m) in moves.as_slice().iter().enumerate() {
            scores[i] = if m == tt_move {
                10_000_000
            } else if m.is_capture() {
                let victim = if m.flag() == F_EP {
                    PAWN
                } else {
                    b.piece_type_at(them, m.to()).unwrap_or(PAWN)
                };
                let attacker = b.piece_type_at(us, m.from()).unwrap_or(PAWN);
                1_000_000 + VICTIM_VALUE[victim] * 16 - attacker as i32
            } else if m.is_promo() {
                900_000 + m.promo_piece() as i32
            } else if m == self.killers[ply][0] {
                800_000
            } else if m == self.killers[ply][1] {
                700_000
            } else {
                self.history[(us * 64 + m.from()) * 64 + m.to()].min(500_000)
            };
        }
    }

    fn negamax(&mut self, b: &Board, mut alpha: i32, mut beta: i32, mut depth: i32, ply: usize) -> i32 {
        self.nodes += 1;
        if self.check_stop() {
            return 0;
        }
        if ply > 0 {
            if self.is_draw(b) {
                return 0;
            }
            alpha = alpha.max(-MATE + ply as i32);
            beta = beta.min(MATE - ply as i32 - 1);
            if alpha >= beta {
                return alpha;
            }
        }
        if ply >= MAX_PLY - 1 {
            return evaluate(b);
        }

        let in_check = b.in_check();
        if in_check {
            depth += 1;
        }
        if depth <= 0 {
            return self.qsearch(b, alpha, beta, ply);
        }

        let pv_node = beta - alpha > 1;
        let key = b.hash;
        let slot = (key as usize) & ((1 << TT_BITS) - 1);
        let entry = self.tt[slot];
        let mut tt_move = Move::NONE;
        if entry.key == key {
            tt_move = entry.mv;
            if ply > 0 && entry.depth >= depth {
                let s = from_tt(entry.score, ply);
                let cut = match entry.bound {
                    EXACT => true,
                    LOWER => s >= beta,
                    _ => s <= alpha,
                };
                if cut {
                    return s;
                }
            }
        }

        // Null-move pruning.
        if !pv_node && !in_check && depth >= 3 && beta.abs() < MATE_BOUND && has_non_pawn(b, b.side) {
            if evaluate(b) >= beta {
                let r = if depth >= 6 { 3 } else { 2 };
                let nb = b.make_null();
                self.path.push(nb.hash);
                let score = -self.negamax(&nb, -beta, -beta + 1, depth - 1 - r, ply + 1);
                self.path.pop();
                if self.stopped {
                    return 0;
                }
                if score >= beta {
                    return if score >= MATE_BOUND { beta } else { score };
                }
            }
        }

        let mut moves = legal_moves(b, false);
        let n = moves.len;
        if n == 0 {
            return if in_check { -MATE + ply as i32 } else { 0 };
        }
        let mut scores = [0i32; 256];
        self.score_moves(b, &moves, tt_move, ply, &mut scores);

        let us = b.side;
        let orig_alpha = alpha;
        let mut best = -INF;
        let mut best_move = Move::NONE;
        for i in 0..n {
            let mut bi = i;
            for j in (i + 1)..n {
                if scores[j] > scores[bi] {
                    bi = j;
                }
            }
            moves.moves.swap(i, bi);
            scores.swap(i, bi);
            let m = moves.moves[i];
            let quiet = !m.is_capture() && !m.is_promo();

            let nb = b.make(m);
            self.path.push(nb.hash);
            let reduction = if i >= 3 && depth >= 3 && quiet && !in_check { if i >= 6 { 2 } else { 1 } } else { 0 };
            let score = if i == 0 {
                -self.negamax(&nb, -beta, -alpha, depth - 1, ply + 1)
            } else {
                let mut s = -self.negamax(&nb, -alpha - 1, -alpha, depth - 1 - reduction, ply + 1);
                if s > alpha && reduction > 0 {
                    s = -self.negamax(&nb, -alpha - 1, -alpha, depth - 1, ply + 1);
                }
                if s > alpha && s < beta {
                    s = -self.negamax(&nb, -beta, -alpha, depth - 1, ply + 1);
                }
                s
            };
            self.path.pop();
            if self.stopped {
                return 0;
            }

            if score > best {
                best = score;
                best_move = m;
                if score > alpha {
                    alpha = score;
                    if score >= beta {
                        if quiet {
                            if self.killers[ply][0] != m {
                                self.killers[ply][1] = self.killers[ply][0];
                                self.killers[ply][0] = m;
                            }
                            let h = &mut self.history[(us * 64 + m.from()) * 64 + m.to()];
                            *h = (*h + depth * depth).min(400_000);
                        }
                        break;
                    }
                }
            }
        }

        let bound = if best >= beta {
            LOWER
        } else if best > orig_alpha {
            EXACT
        } else {
            UPPER
        };
        self.tt[slot] = TTEntry { key, mv: best_move, depth, score: to_tt(best, ply), bound };
        best
    }

    /// Quiescence search: captures and promotions only; all evasions when in check.
    fn qsearch(&mut self, b: &Board, mut alpha: i32, beta: i32, ply: usize) -> i32 {
        self.nodes += 1;
        if self.check_stop() {
            return 0;
        }
        if ply >= MAX_PLY - 1 {
            return evaluate(b);
        }
        let in_check = b.in_check();
        let mut best;
        if in_check {
            best = -INF;
        } else {
            let stand = evaluate(b);
            if stand >= beta {
                return stand;
            }
            if stand > alpha {
                alpha = stand;
            }
            best = stand;
        }
        let mut moves = legal_moves(b, !in_check);
        let n = moves.len;
        if n == 0 {
            return if in_check { -MATE + ply as i32 } else { best };
        }
        let mut scores = [0i32; 256];
        self.score_moves(b, &moves, Move::NONE, ply, &mut scores);
        for i in 0..n {
            let mut bi = i;
            for j in (i + 1)..n {
                if scores[j] > scores[bi] {
                    bi = j;
                }
            }
            moves.moves.swap(i, bi);
            scores.swap(i, bi);
            let nb = b.make(moves.moves[i]);
            let score = -self.qsearch(&nb, -beta, -alpha, ply + 1);
            if self.stopped {
                return 0;
            }
            if score > best {
                best = score;
                if score > alpha {
                    alpha = score;
                    if score >= beta {
                        break;
                    }
                }
            }
        }
        best
    }

    /// Finds the best move for `root` within the depth and time limits.
    /// `history` holds the hashes of all earlier positions of the game, ending with `root`'s hash.
    pub fn think(&mut self, root: &Board, history: &[u64], max_depth: u32, deadline: Option<Instant>) -> Move {
        self.nodes = 0;
        self.stopped = false;
        self.start = Instant::now();
        self.deadline = deadline;
        self.path.clear();
        self.path.extend_from_slice(history);
        if self.path.last() != Some(&root.hash) {
            self.path.push(root.hash);
        }

        let legal = legal_moves(root, false);
        if legal.len == 0 {
            return Move::NONE;
        }
        if legal.len == 1 {
            return legal.moves[0];
        }
        let mut order: Vec<(Move, i32)> = legal.as_slice().iter().map(|&m| (m, 0)).collect();
        let mut best = order[0].0;

        for depth in 1..=max_depth as i32 {
            let mut alpha = -INF;
            let beta = INF;
            let mut iter_best = order[0].0;
            let mut iter_score = -INF;
            for idx in 0..order.len() {
                let m = order[idx].0;
                let nb = root.make(m);
                self.path.push(nb.hash);
                let score = if idx == 0 {
                    -self.negamax(&nb, -beta, -alpha, depth - 1, 1)
                } else {
                    let mut s = -self.negamax(&nb, -alpha - 1, -alpha, depth - 1, 1);
                    if s > alpha && s < beta {
                        s = -self.negamax(&nb, -beta, -alpha, depth - 1, 1);
                    }
                    s
                };
                self.path.pop();
                if self.stopped {
                    break;
                }
                order[idx].1 = score;
                if score > iter_score {
                    iter_score = score;
                    iter_best = m;
                }
                if score > alpha {
                    alpha = score;
                }
            }
            if self.stopped {
                break;
            }
            order.sort_by(|a, b| b.1.cmp(&a.1));
            best = iter_best;
            self.report(depth, iter_score, best);
            // A mate that is fully within the searched depth cannot be improved by searching deeper.
            if iter_score.abs() >= MATE_BOUND && MATE - iter_score.abs() <= depth {
                break;
            }
            if self.deadline.is_some_and(|d| Instant::now() >= d) {
                break;
            }
        }
        best
    }

    fn report(&self, depth: i32, score: i32, mv: Move) {
        let elapsed = self.start.elapsed().as_millis().max(1) as u64;
        let score_str = if score.abs() >= MATE_BOUND {
            let moves = (MATE - score.abs() + 1) / 2;
            format!("mate {}", if score > 0 { moves } else { -moves })
        } else {
            format!("cp {}", score)
        };
        println!(
            "info depth {} score {} nodes {} nps {} time {} pv {}",
            depth,
            score_str,
            self.nodes,
            self.nodes * 1000 / elapsed,
            elapsed,
            mv.to_uci()
        );
    }
}

const VICTIM_VALUE: [i32; 6] = [1, 3, 3, 5, 9, 0];
