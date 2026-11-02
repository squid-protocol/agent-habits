//! Evaluation and alpha-beta search (iterative deepening, quiescence, transposition table).

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Instant;

use crate::board::*;
use crate::movegen::legal_moves;

pub const MATE: i32 = 30_000;
const MATE_BOUND: i32 = MATE - 1_000;
const INF: i32 = 32_000;
pub const MAX_PLY: usize = 128;
pub const MAX_DEPTH: i32 = 64;

const VALUE: [i32; 7] = [0, 100, 320, 330, 500, 900, 0];
const PHASE: [i32; 7] = [0, 0, 1, 1, 2, 4, 0];

// Piece-square tables, written with rank 8 on the first row (as displayed); white indexes with sq ^ 56.
#[rustfmt::skip]
const PAWN_PST: [i32; 64] = [
     0,  0,  0,  0,  0,  0,  0,  0,
    50, 50, 50, 50, 50, 50, 50, 50,
    10, 10, 20, 30, 30, 20, 10, 10,
     5,  5, 10, 25, 25, 10,  5,  5,
     0,  0,  0, 20, 20,  0,  0,  0,
     5, -5,-10,  0,  0,-10, -5,  5,
     5, 10, 10,-20,-20, 10, 10,  5,
     0,  0,  0,  0,  0,  0,  0,  0,
];
#[rustfmt::skip]
const KNIGHT_PST: [i32; 64] = [
    -50,-40,-30,-30,-30,-30,-40,-50,
    -40,-20,  0,  0,  0,  0,-20,-40,
    -30,  0, 10, 15, 15, 10,  0,-30,
    -30,  5, 15, 20, 20, 15,  5,-30,
    -30,  0, 15, 20, 20, 15,  0,-30,
    -30,  5, 10, 15, 15, 10,  5,-30,
    -40,-20,  0,  5,  5,  0,-20,-40,
    -50,-40,-30,-30,-30,-30,-40,-50,
];
#[rustfmt::skip]
const BISHOP_PST: [i32; 64] = [
    -20,-10,-10,-10,-10,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5, 10, 10,  5,  0,-10,
    -10,  5,  5, 10, 10,  5,  5,-10,
    -10,  0, 10, 10, 10, 10,  0,-10,
    -10, 10, 10, 10, 10, 10, 10,-10,
    -10,  5,  0,  0,  0,  0,  5,-10,
    -20,-10,-10,-10,-10,-10,-10,-20,
];
#[rustfmt::skip]
const ROOK_PST: [i32; 64] = [
     0,  0,  0,  0,  0,  0,  0,  0,
     5, 10, 10, 10, 10, 10, 10,  5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
    -5,  0,  0,  0,  0,  0,  0, -5,
     0,  0,  0,  5,  5,  0,  0,  0,
];
#[rustfmt::skip]
const QUEEN_PST: [i32; 64] = [
    -20,-10,-10, -5, -5,-10,-10,-20,
    -10,  0,  0,  0,  0,  0,  0,-10,
    -10,  0,  5,  5,  5,  5,  0,-10,
     -5,  0,  5,  5,  5,  5,  0, -5,
      0,  0,  5,  5,  5,  5,  0, -5,
    -10,  5,  5,  5,  5,  5,  0,-10,
    -10,  0,  5,  0,  0,  0,  0,-10,
    -20,-10,-10, -5, -5,-10,-10,-20,
];
#[rustfmt::skip]
const KING_MG_PST: [i32; 64] = [
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -30,-40,-40,-50,-50,-40,-40,-30,
    -20,-30,-30,-40,-40,-30,-30,-20,
    -10,-20,-20,-20,-20,-20,-20,-10,
     20, 20,  0,  0,  0,  0, 20, 20,
     20, 30, 10,  0,  0, 10, 30, 20,
];
#[rustfmt::skip]
const KING_EG_PST: [i32; 64] = [
    -50,-40,-30,-20,-20,-30,-40,-50,
    -30,-20,-10,  0,  0,-10,-20,-30,
    -30,-10, 20, 30, 30, 20,-10,-30,
    -30,-10, 30, 40, 40, 30,-10,-30,
    -30,-10, 30, 40, 40, 30,-10,-30,
    -30,-10, 20, 30, 30, 20,-10,-30,
    -30,-30,  0,  0,  0,  0,-30,-30,
    -50,-30,-30,-30,-30,-30,-30,-50,
];

/// Indexed by piece kind (row 0 unused).
const PST: [&[i32; 64]; 7] = [&[0; 64], &PAWN_PST, &KNIGHT_PST, &BISHOP_PST, &ROOK_PST, &QUEEN_PST, &KING_MG_PST];

/// Static evaluation in centipawns from the side to move's point of view (tapered middlegame/endgame).
pub fn eval(pos: &Position) -> i32 {
    let mut mg = [0i32; 2];
    let mut eg = [0i32; 2];
    let mut phase = 0;
    for sq in 0..64 {
        let p = pos.b[sq];
        if p == EMPTY {
            continue;
        }
        let c = color_of(p) as usize;
        let k = kind_of(p) as usize;
        let idx = if c == WHITE as usize { sq ^ 56 } else { sq };
        mg[c] += VALUE[k] + PST[k][idx];
        eg[c] += VALUE[k] + if k == KING as usize { KING_EG_PST[idx] } else { PST[k][idx] };
        phase += PHASE[k];
    }
    let ph = phase.min(24);
    let s = ((mg[0] - mg[1]) * ph + (eg[0] - eg[1]) * (24 - ph)) / 24;
    let s = if pos.stm == WHITE { s } else { -s };
    s + 10 // tempo
}

pub const TT_BITS: usize = 20;
const EXACT: u8 = 1;
const LOWER: u8 = 2;
const UPPER: u8 = 3;

#[derive(Clone, Copy, Default)]
pub struct Entry {
    key: u64,
    best: Move,
    score: i32,
    depth: i32,
    bound: u8,
}

pub fn new_table() -> Vec<Entry> {
    vec![Entry::default(); 1 << TT_BITS]
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

pub struct Searcher<'a> {
    pub pos: Position,
    tt: &'a mut [Entry],
    stop: Arc<AtomicBool>,
    deadline: Option<Instant>,
    start: Instant,
    nodes: u64,
    aborted: bool,
    killers: [[Move; 2]; MAX_PLY],
    history: Box<[[i32; 64]; 64]>,
}

impl<'a> Searcher<'a> {
    pub fn new(pos: Position, tt: &'a mut [Entry], stop: Arc<AtomicBool>, deadline: Option<Instant>) -> Self {
        Searcher {
            pos,
            tt,
            stop,
            deadline,
            start: Instant::now(),
            nodes: 0,
            aborted: false,
            killers: [[Move::default(); 2]; MAX_PLY],
            history: Box::new([[0; 64]; 64]),
        }
    }

    fn check_limits(&mut self) {
        if self.stop.load(Ordering::Relaxed) {
            self.aborted = true;
        } else if let Some(d) = self.deadline {
            if Instant::now() >= d {
                self.aborted = true;
            }
        }
    }

    /// Iterative deepening from the root. Returns the best move found by the last completed iteration.
    pub fn search_root(&mut self, max_depth: i32) -> Option<Move> {
        let mut moves = legal_moves(&mut self.pos, false);
        if moves.is_empty() {
            return None;
        }
        if moves.len() == 1 {
            return Some(moves[0]);
        }
        let mut best = moves[0];
        for depth in 1..=max_depth {
            let mut alpha = -INF;
            let beta = INF;
            let mut iter_best: Option<Move> = None;
            let mut iter_score = -INF;
            let mut scores = vec![-INF; moves.len()];
            for i in 0..moves.len() {
                let m = moves[i];
                self.pos.make_move(m);
                let s = -self.negamax(depth - 1, -beta, -alpha, 1);
                self.pos.unmake_move(m);
                if self.aborted {
                    return Some(best);
                }
                scores[i] = s;
                if iter_best.is_none() || s > iter_score {
                    iter_score = s;
                    iter_best = Some(m);
                }
                if s > alpha {
                    alpha = s;
                }
            }
            best = iter_best.unwrap_or(best);
            // Search the best root move first next iteration.
            let mut order: Vec<usize> = (0..moves.len()).collect();
            order.sort_by(|&a, &b| scores[b].cmp(&scores[a]));
            moves = order.iter().map(|&i| moves[i]).collect();

            self.report(depth, iter_score);
            if iter_score >= MATE_BOUND && MATE - iter_score <= depth {
                break; // mate found within the horizon; deeper search cannot change the move
            }
        }
        Some(best)
    }

    fn report(&self, depth: i32, score: i32) {
        let ms = self.start.elapsed().as_millis() as u64;
        let nps = self.nodes * 1000 / ms.max(1);
        let score_str = if score.abs() >= MATE_BOUND {
            let moves = (MATE - score.abs() + 1) / 2;
            format!("mate {}", if score > 0 { moves } else { -moves })
        } else {
            format!("cp {score}")
        };
        println!("info depth {depth} score {score_str} nodes {} time {ms} nps {nps}", self.nodes);
    }

    fn negamax(&mut self, mut depth: i32, mut alpha: i32, beta: i32, ply: usize) -> i32 {
        self.nodes += 1;
        if self.nodes & 2047 == 0 {
            self.check_limits();
        }
        if self.aborted {
            return 0;
        }
        if ply >= MAX_PLY - 1 {
            return eval(&self.pos);
        }
        if ply > 0 && (self.pos.half >= 100 || self.pos.repetition()) {
            return 0;
        }

        let in_check = self.pos.in_check();
        if in_check {
            depth += 1; // check extension
        }
        if depth <= 0 {
            return self.qsearch(alpha, beta, ply);
        }

        let key = self.pos.hash;
        let idx = (key as usize) & (self.tt.len() - 1);
        let entry = self.tt[idx];
        let mut tt_move = Move::default();
        if entry.bound != 0 && entry.key == key {
            tt_move = entry.best;
            if ply > 0 && entry.depth >= depth {
                let s = score_from_tt(entry.score, ply);
                match entry.bound {
                    EXACT => return s,
                    LOWER if s >= beta => return s,
                    UPPER if s <= alpha => return s,
                    _ => {}
                }
            }
        }

        let mut moves = legal_moves(&mut self.pos, false);
        if moves.is_empty() {
            return if in_check { -MATE + ply as i32 } else { 0 };
        }
        let mut keys: Vec<i32> = moves.iter().map(|&m| self.move_score(m, tt_move, ply)).collect();

        let mut best = -INF;
        let mut best_move = moves[0];
        let mut bound = UPPER;
        for i in 0..moves.len() {
            pick_best(&mut moves, &mut keys, i);
            let m = moves[i];
            let capture = self.pos.b[m.to as usize] != EMPTY || m.flags & FLAG_EP != 0;
            self.pos.make_move(m);
            let score = -self.negamax(depth - 1, -beta, -alpha, ply + 1);
            self.pos.unmake_move(m);
            if self.aborted {
                return 0;
            }
            if score > best {
                best = score;
                best_move = m;
                if score > alpha {
                    alpha = score;
                    bound = EXACT;
                    if score >= beta {
                        bound = LOWER;
                        if !capture {
                            self.record_quiet(m, depth, ply);
                        }
                        break;
                    }
                }
            }
        }

        self.tt[idx] = Entry {
            key,
            best: best_move,
            score: score_to_tt(best, ply),
            depth,
            bound,
        };
        best
    }

    fn qsearch(&mut self, mut alpha: i32, beta: i32, ply: usize) -> i32 {
        self.nodes += 1;
        if self.nodes & 2047 == 0 {
            self.check_limits();
        }
        if self.aborted {
            return 0;
        }
        if ply >= MAX_PLY - 1 {
            return eval(&self.pos);
        }

        let in_check = self.pos.in_check();
        let mut best;
        if in_check {
            best = -INF;
        } else {
            let stand = eval(&self.pos);
            if stand >= beta {
                return stand;
            }
            if stand > alpha {
                alpha = stand;
            }
            best = stand;
        }

        // Out of check: captures and promotions only. In check: every legal evasion.
        let mut moves = legal_moves(&mut self.pos, !in_check);
        if moves.is_empty() {
            return if in_check { -MATE + ply as i32 } else { best };
        }
        let mut keys: Vec<i32> = moves.iter().map(|&m| self.move_score(m, Move::default(), ply)).collect();
        for i in 0..moves.len() {
            pick_best(&mut moves, &mut keys, i);
            let m = moves[i];
            self.pos.make_move(m);
            let score = -self.qsearch(-beta, -alpha, ply + 1);
            self.pos.unmake_move(m);
            if self.aborted {
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

    fn move_score(&self, m: Move, tt_move: Move, ply: usize) -> i32 {
        if tt_move.from != tt_move.to && m.same_as(&tt_move) {
            return 10_000_000;
        }
        let victim = self.pos.b[m.to as usize];
        if victim != EMPTY || m.flags & FLAG_EP != 0 {
            let v = if m.flags & FLAG_EP != 0 { PAWN } else { kind_of(victim) };
            let a = kind_of(self.pos.b[m.from as usize]);
            return 5_000_000 + VALUE[v as usize] * 10 - VALUE[a as usize] / 10;
        }
        if m.promo != 0 {
            return 4_000_000 + VALUE[m.promo as usize];
        }
        if self.killers[ply][0].same_as(&m) {
            return 3_000_000;
        }
        if self.killers[ply][1].same_as(&m) {
            return 2_900_000;
        }
        self.history[m.from as usize][m.to as usize]
    }

    fn record_quiet(&mut self, m: Move, depth: i32, ply: usize) {
        if !self.killers[ply][0].same_as(&m) {
            self.killers[ply][1] = self.killers[ply][0];
            self.killers[ply][0] = m;
        }
        let h = &mut self.history[m.from as usize][m.to as usize];
        *h = (*h + depth * depth).min(900_000);
    }
}

fn pick_best(moves: &mut [Move], keys: &mut [i32], start: usize) {
    let mut bi = start;
    for j in start + 1..moves.len() {
        if keys[j] > keys[bi] {
            bi = j;
        }
    }
    moves.swap(start, bi);
    keys.swap(start, bi);
}
