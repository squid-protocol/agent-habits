//! Move encoding, pseudo-legal move generation with legality filtering, and perft.

use crate::board::*;

pub const FLAG_CAPTURE: u32 = 1 << 16;
pub const FLAG_EP: u32 = 1 << 17;
pub const FLAG_DOUBLE: u32 = 1 << 18;
pub const FLAG_CASTLE: u32 = 1 << 19;

/// A move packed into 32 bits: from (0-5), to (6-11), promotion kind (12-14), flags (16-19).
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub struct Move(pub u32);

impl Move {
    /// Sentinel "no move" (a1a1 is never a legal move).
    pub const NONE: Move = Move(0);

    #[inline]
    pub fn new(from: usize, to: usize, promo: usize, flags: u32) -> Move {
        Move((from as u32) | ((to as u32) << 6) | ((promo as u32) << 12) | flags)
    }
    #[inline]
    pub fn from(self) -> usize {
        (self.0 & 63) as usize
    }
    #[inline]
    pub fn to(self) -> usize {
        ((self.0 >> 6) & 63) as usize
    }
    /// Promotion piece kind (KNIGHT..QUEEN) or 0.
    #[inline]
    pub fn promo(self) -> usize {
        ((self.0 >> 12) & 7) as usize
    }
    #[inline]
    pub fn is_capture(self) -> bool {
        self.0 & FLAG_CAPTURE != 0
    }
    #[inline]
    pub fn is_ep(self) -> bool {
        self.0 & FLAG_EP != 0
    }
    #[inline]
    pub fn is_double(self) -> bool {
        self.0 & FLAG_DOUBLE != 0
    }
    #[inline]
    pub fn is_castle(self) -> bool {
        self.0 & FLAG_CASTLE != 0
    }
    /// Neither a capture nor a promotion.
    #[inline]
    pub fn is_quiet(self) -> bool {
        !self.is_capture() && self.promo() == 0
    }

    pub fn to_uci(self) -> String {
        if self == Move::NONE {
            return "0000".into();
        }
        let mut s = square_name(self.from()) + &square_name(self.to());
        match self.promo() {
            KNIGHT => s.push('n'),
            BISHOP => s.push('b'),
            ROOK => s.push('r'),
            QUEEN => s.push('q'),
            _ => {}
        }
        s
    }
}

pub struct MoveList {
    pub moves: [Move; 256],
    pub len: usize,
}

impl MoveList {
    #[inline]
    pub fn new() -> MoveList {
        MoveList { moves: [Move::NONE; 256], len: 0 }
    }
    #[inline]
    pub fn push(&mut self, m: Move) {
        self.moves[self.len] = m;
        self.len += 1;
    }
}

fn push_promotions(list: &mut MoveList, from: usize, to: usize, capture: bool) {
    let base = if capture { FLAG_CAPTURE } else { 0 };
    for promo in [QUEEN, ROOK, BISHOP, KNIGHT] {
        list.push(Move::new(from, to, promo, base));
    }
}

impl Position {
    /// Generates pseudo-legal moves. With `captures_only`, only captures and promotions are produced.
    /// Moves that leave the mover's king attacked must be filtered with `legal_after_move`.
    pub fn gen_moves(&self, list: &mut MoveList, captures_only: bool) {
        let t = tables();
        let us = self.stm;
        let them = us ^ 1;
        let own = self.occ[us];
        let enemy = self.occ[them];
        let occ = own | enemy;

        let (fwd, start_rank, promo_rank): (i32, usize, usize) = if us == WHITE { (8, 1, 7) } else { (-8, 6, 0) };
        let mut pawns = self.pieces[us * 6 + PAWN];
        while pawns != 0 {
            let from = pawns.trailing_zeros() as usize;
            pawns &= pawns - 1;
            let file = (from % 8) as i32;
            let rank = from / 8;
            let to = (from as i32 + fwd) as usize;
            if occ & (1u64 << to) == 0 {
                if to / 8 == promo_rank {
                    push_promotions(list, from, to, false);
                } else if !captures_only {
                    list.push(Move::new(from, to, 0, 0));
                    if rank == start_rank {
                        let to2 = (to as i32 + fwd) as usize;
                        if occ & (1u64 << to2) == 0 {
                            list.push(Move::new(from, to2, 0, FLAG_DOUBLE));
                        }
                    }
                }
            }
            for df in [-1i32, 1] {
                if !(0..8).contains(&(file + df)) {
                    continue;
                }
                let to = (from as i32 + fwd + df) as usize;
                if enemy & (1u64 << to) != 0 {
                    if to / 8 == promo_rank {
                        push_promotions(list, from, to, true);
                    } else {
                        list.push(Move::new(from, to, 0, FLAG_CAPTURE));
                    }
                } else if self.ep as usize == to {
                    list.push(Move::new(from, to, 0, FLAG_CAPTURE | FLAG_EP));
                }
            }
        }

        for kind in [KNIGHT, BISHOP, ROOK, QUEEN, KING] {
            let mut bb = self.pieces[us * 6 + kind];
            while bb != 0 {
                let from = bb.trailing_zeros() as usize;
                bb &= bb - 1;
                let attacks = match kind {
                    KNIGHT => t.knight[from],
                    BISHOP => bishop_attacks(from, occ),
                    ROOK => rook_attacks(from, occ),
                    QUEEN => bishop_attacks(from, occ) | rook_attacks(from, occ),
                    _ => t.king[from],
                };
                let mut targets = attacks & !own;
                if captures_only {
                    targets &= enemy;
                }
                while targets != 0 {
                    let to = targets.trailing_zeros() as usize;
                    targets &= targets - 1;
                    let flags = if enemy & (1u64 << to) != 0 { FLAG_CAPTURE } else { 0 };
                    list.push(Move::new(from, to, 0, flags));
                }
            }
        }

        if !captures_only {
            self.gen_castling(list);
        }
    }

    fn gen_castling(&self, list: &mut MoveList) {
        let us = self.stm;
        let them = us ^ 1;
        let occ = self.occ[WHITE] | self.occ[BLACK];
        if us == WHITE {
            if !self.has(WHITE, KING, 4) {
                return;
            }
            if self.castle & CASTLE_WK != 0
                && occ & ((1 << 5) | (1 << 6)) == 0
                && self.has(WHITE, ROOK, 7)
                && !self.is_attacked(4, them)
                && !self.is_attacked(5, them)
                && !self.is_attacked(6, them)
            {
                list.push(Move::new(4, 6, 0, FLAG_CASTLE));
            }
            if self.castle & CASTLE_WQ != 0
                && occ & ((1 << 1) | (1 << 2) | (1 << 3)) == 0
                && self.has(WHITE, ROOK, 0)
                && !self.is_attacked(4, them)
                && !self.is_attacked(3, them)
                && !self.is_attacked(2, them)
            {
                list.push(Move::new(4, 2, 0, FLAG_CASTLE));
            }
        } else {
            if !self.has(BLACK, KING, 60) {
                return;
            }
            if self.castle & CASTLE_BK != 0
                && occ & ((1 << 61) | (1 << 62)) == 0
                && self.has(BLACK, ROOK, 63)
                && !self.is_attacked(60, them)
                && !self.is_attacked(61, them)
                && !self.is_attacked(62, them)
            {
                list.push(Move::new(60, 62, 0, FLAG_CASTLE));
            }
            if self.castle & CASTLE_BQ != 0
                && occ & ((1 << 57) | (1 << 58) | (1 << 59)) == 0
                && self.has(BLACK, ROOK, 56)
                && !self.is_attacked(60, them)
                && !self.is_attacked(59, them)
                && !self.is_attacked(58, them)
            {
                list.push(Move::new(60, 58, 0, FLAG_CASTLE));
            }
        }
    }

    /// All legal moves in the position.
    pub fn legal_moves(&self) -> Vec<Move> {
        let mut list = MoveList::new();
        self.gen_moves(&mut list, false);
        (0..list.len)
            .map(|i| list.moves[i])
            .filter(|&m| self.make(m).legal_after_move(self.stm))
            .collect()
    }
}

/// Number of leaf nodes at `depth` (bulk-counted at the last ply).
pub fn perft(pos: &Position, depth: u32) -> u64 {
    if depth == 0 {
        return 1;
    }
    let mut list = MoveList::new();
    pos.gen_moves(&mut list, false);
    let mut nodes = 0;
    for i in 0..list.len {
        let child = pos.make(list.moves[i]);
        if !child.legal_after_move(pos.stm) {
            continue;
        }
        nodes += if depth == 1 { 1 } else { perft(&child, depth - 1) };
    }
    nodes
}

/// Per-root-move node counts for `perft depth`.
pub fn divide(pos: &Position, depth: u32) -> Vec<(Move, u64)> {
    let mut out = Vec::new();
    let mut list = MoveList::new();
    pos.gen_moves(&mut list, false);
    for i in 0..list.len {
        let m = list.moves[i];
        let child = pos.make(m);
        if !child.legal_after_move(pos.stm) {
            continue;
        }
        out.push((m, perft(&child, depth.saturating_sub(1))));
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn perft_fen(fen: &str, depth: u32) -> u64 {
        perft(&Position::from_fen(fen).unwrap(), depth)
    }

    #[test]
    fn startpos_perft() {
        let p = Position::startpos();
        assert_eq!(perft(&p, 1), 20);
        assert_eq!(perft(&p, 2), 400);
        assert_eq!(perft(&p, 3), 8902);
    }

    #[test]
    fn kiwipete_perft() {
        let fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1";
        assert_eq!(perft_fen(fen, 1), 48);
        assert_eq!(perft_fen(fen, 2), 2039);
        assert_eq!(perft_fen(fen, 3), 97862);
    }

    #[test]
    fn endgame_perft() {
        assert_eq!(perft_fen("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 4), 43238);
        assert_eq!(perft_fen("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", 3), 9467);
        assert_eq!(perft_fen("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", 3), 62379);
    }

    #[test]
    fn incremental_hash_matches_recomputed() {
        fn walk(p: &Position, depth: u32) {
            assert_eq!(p.hash, p.compute_hash());
            if depth == 0 {
                return;
            }
            let mut list = MoveList::new();
            p.gen_moves(&mut list, false);
            for i in 0..list.len {
                let c = p.make(list.moves[i]);
                if c.legal_after_move(p.stm) {
                    walk(&c, depth - 1);
                }
            }
        }
        let fen = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1";
        walk(&Position::from_fen(fen).unwrap(), 2);
        walk(&Position::startpos(), 3);
    }
}
