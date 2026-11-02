//! Move generation. Pseudo-legal moves are generated first; `is_legal` filters them.

use crate::attacks::{bishop_attacks, rook_attacks, tables};
use crate::board::*;

pub struct MoveList {
    pub moves: [Move; 256],
    pub len: usize,
}

impl Default for MoveList {
    fn default() -> Self {
        Self::new()
    }
}

impl MoveList {
    pub fn new() -> Self {
        MoveList { moves: [Move::NONE; 256], len: 0 }
    }

    #[inline]
    pub fn push(&mut self, m: Move) {
        self.moves[self.len] = m;
        self.len += 1;
    }

    pub fn as_slice(&self) -> &[Move] {
        &self.moves[..self.len]
    }
}

/// True when the side `mover` has not left its own king attacked.
#[inline]
pub fn is_legal(child: &Position, mover: usize) -> bool {
    !child.attacked_by(child.king_sq(mover), 1 - mover)
}

/// Generates pseudo-legal moves for the side to move. With `captures_only`, only captures and
/// promotions are produced (used by quiescence search outside check).
pub fn gen_pseudo(pos: &Position, list: &mut MoveList, captures_only: bool) {
    let t = tables();
    let us = pos.side;
    let them = 1 - us;
    let own = pos.occ[us];
    let theirs = pos.occ[them];
    let occ = own | theirs;
    let empty = !occ;

    // Pawns.
    let (step, start_rank, promo_rank): (isize, usize, usize) = if us == WHITE { (8, 1, 7) } else { (-8, 6, 0) };
    let mut pawns = pos.bb[us * 6 + PAWN];
    while pawns != 0 {
        let from = pop_lsb(&mut pawns);
        let to = (from as isize + step) as usize;
        if empty & bit(to) != 0 {
            if to / 8 == promo_rank {
                push_promotions(list, from, to);
            } else if !captures_only {
                list.push(Move::new(from, to, 0));
                if from / 8 == start_rank {
                    let to2 = (to as isize + step) as usize;
                    if empty & bit(to2) != 0 {
                        list.push(Move::new(from, to2, 0));
                    }
                }
            }
        }
        let mut caps = t.pawn[us][from] & theirs;
        while caps != 0 {
            let to = pop_lsb(&mut caps);
            if to / 8 == promo_rank {
                push_promotions(list, from, to);
            } else {
                list.push(Move::new(from, to, 0));
            }
        }
        if pos.ep != NO_SQ && t.pawn[us][from] & bit(pos.ep as usize) != 0 {
            list.push(Move::new(from, pos.ep as usize, 0));
        }
    }

    // Knights, bishops, rooks, queens and kings.
    for pt in [KNIGHT, BISHOP, ROOK, QUEEN, KING] {
        let mut pieces = pos.bb[us * 6 + pt];
        while pieces != 0 {
            let from = pop_lsb(&mut pieces);
            let attacks = match pt {
                KNIGHT => t.knight[from],
                BISHOP => bishop_attacks(from, occ),
                ROOK => rook_attacks(from, occ),
                QUEEN => bishop_attacks(from, occ) | rook_attacks(from, occ),
                _ => t.king[from],
            };
            let mut targets = attacks & if captures_only { theirs } else { !own };
            while targets != 0 {
                let to = pop_lsb(&mut targets);
                list.push(Move::new(from, to, 0));
            }
        }
    }

    // Castling: the king and rook must be home, the path empty, and no square the king crosses attacked.
    if !captures_only && !pos.in_check() {
        if us == WHITE {
            if pos.castle & CASTLE_WK != 0
                && occ & 0x60 == 0
                && pos.board[7] == piece_code(WHITE, ROOK)
                && pos.board[4] == piece_code(WHITE, KING)
                && !pos.attacked_by(5, them)
                && !pos.attacked_by(6, them)
            {
                list.push(Move::new(4, 6, 0));
            }
            if pos.castle & CASTLE_WQ != 0
                && occ & 0x0E == 0
                && pos.board[0] == piece_code(WHITE, ROOK)
                && pos.board[4] == piece_code(WHITE, KING)
                && !pos.attacked_by(3, them)
                && !pos.attacked_by(2, them)
            {
                list.push(Move::new(4, 2, 0));
            }
        } else {
            if pos.castle & CASTLE_BK != 0
                && occ & (0x60u64 << 56) == 0
                && pos.board[63] == piece_code(BLACK, ROOK)
                && pos.board[60] == piece_code(BLACK, KING)
                && !pos.attacked_by(61, them)
                && !pos.attacked_by(62, them)
            {
                list.push(Move::new(60, 62, 0));
            }
            if pos.castle & CASTLE_BQ != 0
                && occ & (0x0Eu64 << 56) == 0
                && pos.board[56] == piece_code(BLACK, ROOK)
                && pos.board[60] == piece_code(BLACK, KING)
                && !pos.attacked_by(59, them)
                && !pos.attacked_by(58, them)
            {
                list.push(Move::new(60, 58, 0));
            }
        }
    }
}

fn push_promotions(list: &mut MoveList, from: usize, to: usize) {
    for pt in [QUEEN, ROOK, BISHOP, KNIGHT] {
        list.push(Move::new(from, to, pt));
    }
}

/// All legal moves in the position.
pub fn legal_moves(pos: &Position) -> Vec<Move> {
    let mut list = MoveList::new();
    gen_pseudo(pos, &mut list, false);
    list.as_slice().iter().copied().filter(|&m| is_legal(&pos.make(m), pos.side)).collect()
}

/// Number of leaf nodes `depth` plies from `pos`.
pub fn perft(pos: &Position, depth: u32) -> u64 {
    if depth == 0 {
        return 1;
    }
    let mut list = MoveList::new();
    gen_pseudo(pos, &mut list, false);
    let mut nodes = 0;
    for &m in list.as_slice() {
        let child = pos.make(m);
        if !is_legal(&child, pos.side) {
            continue;
        }
        nodes += if depth == 1 { 1 } else { perft(&child, depth - 1) };
    }
    nodes
}
