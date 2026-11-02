//! Move generation: pseudo-legal moves filtered to legal ones, plus perft.

use crate::attacks::*;
use crate::board::*;

pub struct MoveList {
    pub moves: [Move; 256],
    pub len: usize,
}

impl MoveList {
    pub fn new() -> Self {
        MoveList { moves: [Move::NONE; 256], len: 0 }
    }
    #[inline(always)]
    fn push(&mut self, m: Move) {
        self.moves[self.len] = m;
        self.len += 1;
    }
    #[inline(always)]
    pub fn as_slice(&self) -> &[Move] {
        &self.moves[..self.len]
    }
}

impl Default for MoveList {
    fn default() -> Self {
        Self::new()
    }
}

/// Pseudo-legal moves. With `caps_only`, only captures and promotions are produced.
fn gen_pseudo(b: &Board, caps_only: bool, list: &mut MoveList) {
    let us = b.side;
    let them = us ^ 1;
    let occ = b.occ[0] | b.occ[1];
    let enemy = b.occ[them];
    let own = b.occ[us];

    let (fwd, start_rank, promo_rank): (i32, usize, usize) = if us == WHITE { (8, 1, 7) } else { (-8, 6, 0) };
    let mut pawns = b.pieces[us][PAWN];
    while pawns != 0 {
        let from = pawns.trailing_zeros() as usize;
        pawns &= pawns - 1;
        let to = (from as i32 + fwd) as usize;
        if occ & (1u64 << to) == 0 {
            if to / 8 == promo_rank {
                for i in 0..4u16 {
                    list.push(Move::new(from, to, F_PROMO_N + i));
                }
            } else if !caps_only {
                list.push(Move::new(from, to, F_QUIET));
                if from / 8 == start_rank {
                    let to2 = (to as i32 + fwd) as usize;
                    if occ & (1u64 << to2) == 0 {
                        list.push(Move::new(from, to2, F_DOUBLE));
                    }
                }
            }
        }
        let mut caps = PAWN_ATT[us][from] & enemy;
        while caps != 0 {
            let t = caps.trailing_zeros() as usize;
            caps &= caps - 1;
            if t / 8 == promo_rank {
                for i in 0..4u16 {
                    list.push(Move::new(from, t, F_CAP_PROMO_N + i));
                }
            } else {
                list.push(Move::new(from, t, F_CAP));
            }
        }
        if b.ep != NO_SQ && PAWN_ATT[us][from] & (1u64 << b.ep) != 0 {
            list.push(Move::new(from, b.ep as usize, F_EP));
        }
    }

    for pt in [KNIGHT, BISHOP, ROOK, QUEEN, KING] {
        let mut bb = b.pieces[us][pt];
        while bb != 0 {
            let from = bb.trailing_zeros() as usize;
            bb &= bb - 1;
            let att = match pt {
                KNIGHT => KNIGHT_ATT[from],
                BISHOP => bishop_attacks(occ, from),
                ROOK => rook_attacks(occ, from),
                QUEEN => rook_attacks(occ, from) | bishop_attacks(occ, from),
                _ => KING_ATT[from],
            } & !own;
            let mut targets = if caps_only { att & enemy } else { att };
            while targets != 0 {
                let t = targets.trailing_zeros() as usize;
                targets &= targets - 1;
                let flag = if enemy & (1u64 << t) != 0 { F_CAP } else { F_QUIET };
                list.push(Move::new(from, t, flag));
            }
        }
    }

    if !caps_only {
        gen_castles(b, list);
    }
}

fn gen_castles(b: &Board, list: &mut MoveList) {
    let us = b.side;
    let them = us ^ 1;
    let occ = b.occ[0] | b.occ[1];
    let (king, rook_k, rook_q, k_right, q_right) = if us == WHITE {
        (4usize, 7usize, 0usize, CASTLE_WK, CASTLE_WQ)
    } else {
        (60usize, 63usize, 56usize, CASTLE_BK, CASTLE_BQ)
    };
    if b.pieces[us][KING] & (1u64 << king) == 0 || b.is_attacked(king, them) {
        return;
    }
    let rooks = b.pieces[us][ROOK];
    let empty = |sqs: &[usize]| sqs.iter().all(|&s| occ & (1u64 << s) == 0);
    let safe = |sqs: &[usize]| sqs.iter().all(|&s| !b.is_attacked(s, them));
    if b.castle & k_right != 0
        && rooks & (1u64 << rook_k) != 0
        && empty(&[king + 1, king + 2])
        && safe(&[king + 1, king + 2])
    {
        list.push(Move::new(king, king + 2, F_OO));
    }
    if b.castle & q_right != 0
        && rooks & (1u64 << rook_q) != 0
        && empty(&[king - 1, king - 2, king - 3])
        && safe(&[king - 1, king - 2])
    {
        list.push(Move::new(king, king - 2, F_OOO));
    }
}

/// All legal moves (or only legal captures/promotions when `caps_only`).
pub fn legal_moves(b: &Board, caps_only: bool) -> MoveList {
    let mut pseudo = MoveList::new();
    gen_pseudo(b, caps_only, &mut pseudo);
    let mut out = MoveList::new();
    let us = b.side;
    for &m in pseudo.as_slice() {
        let nb = b.make(m);
        if !nb.is_attacked(nb.king_sq(us), us ^ 1) {
            out.push(m);
        }
    }
    out
}

/// Number of leaf nodes at `depth` plies.
pub fn perft(b: &Board, depth: u32) -> u64 {
    if depth == 0 {
        return 1;
    }
    let list = legal_moves(b, false);
    if depth == 1 {
        return list.len as u64;
    }
    list.as_slice().iter().map(|&m| perft(&b.make(m), depth - 1)).sum()
}
