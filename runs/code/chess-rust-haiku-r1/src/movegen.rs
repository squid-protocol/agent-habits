//! Pseudo-legal and legal move generation, attack detection and perft.

use crate::board::*;

const KNIGHT_D: [(i32, i32); 8] = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)];
const KING_D: [(i32, i32); 8] = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)];
const BISHOP_D: [(i32, i32); 4] = [(1, 1), (1, -1), (-1, 1), (-1, -1)];
const ROOK_D: [(i32, i32); 4] = [(1, 0), (-1, 0), (0, 1), (0, -1)];

#[inline]
fn on_board(f: i32, r: i32) -> bool {
    (0..8).contains(&f) && (0..8).contains(&r)
}

impl Position {
    /// Is square `sq` attacked by any piece of colour `by`?
    pub fn is_attacked(&self, sq: usize, by: u8) -> bool {
        let b = &self.b;
        let f = (sq & 7) as i32;
        let r = (sq >> 3) as i32;

        // Pawns: a pawn of `by` attacks diagonally forward, so look one rank "behind" sq.
        let pr = if by == WHITE { r - 1 } else { r + 1 };
        if (0..8).contains(&pr) {
            for df in [-1, 1] {
                let pf = f + df;
                if (0..8).contains(&pf) && b[(pr * 8 + pf) as usize] == make_piece(by, PAWN) {
                    return true;
                }
            }
        }
        for (df, dr) in KNIGHT_D {
            let (nf, nr) = (f + df, r + dr);
            if on_board(nf, nr) && b[(nr * 8 + nf) as usize] == make_piece(by, KNIGHT) {
                return true;
            }
        }
        for (df, dr) in KING_D {
            let (nf, nr) = (f + df, r + dr);
            if on_board(nf, nr) && b[(nr * 8 + nf) as usize] == make_piece(by, KING) {
                return true;
            }
        }
        let bishop = make_piece(by, BISHOP);
        let queen = make_piece(by, QUEEN);
        for (df, dr) in BISHOP_D {
            let (mut nf, mut nr) = (f + df, r + dr);
            while on_board(nf, nr) {
                let p = b[(nr * 8 + nf) as usize];
                if p != EMPTY {
                    if p == bishop || p == queen {
                        return true;
                    }
                    break;
                }
                nf += df;
                nr += dr;
            }
        }
        let rook = make_piece(by, ROOK);
        for (df, dr) in ROOK_D {
            let (mut nf, mut nr) = (f + df, r + dr);
            while on_board(nf, nr) {
                let p = b[(nr * 8 + nf) as usize];
                if p != EMPTY {
                    if p == rook || p == queen {
                        return true;
                    }
                    break;
                }
                nf += df;
                nr += dr;
            }
        }
        false
    }

    #[inline]
    pub fn in_check(&self) -> bool {
        self.is_attacked(self.king[self.stm as usize] as usize, self.stm ^ 1)
    }
}

fn push_promotions(out: &mut Vec<Move>, from: u8, to: u8, flags: u8) {
    for promo in [QUEEN, ROOK, BISHOP, KNIGHT] {
        out.push(Move { from, to, promo, flags });
    }
}

fn gen_pawn(pos: &Position, sq: u8, us: u8, out: &mut Vec<Move>, caps_only: bool) {
    let b = &pos.b;
    let f = (sq & 7) as i32;
    let r = sq >> 3;
    let (dir, start_rank, promo_rank): (i32, u8, u8) = if us == WHITE { (8, 1, 7) } else { (-8, 6, 0) };

    let to1 = (sq as i32 + dir) as usize;
    if b[to1] == EMPTY {
        if (to1 >> 3) as u8 == promo_rank {
            push_promotions(out, sq, to1 as u8, 0);
        } else if !caps_only {
            out.push(Move::new(sq, to1 as u8));
            if r == start_rank {
                let to2 = (sq as i32 + 2 * dir) as usize;
                if b[to2] == EMPTY {
                    out.push(Move { from: sq, to: to2 as u8, promo: 0, flags: FLAG_DOUBLE });
                }
            }
        }
    }

    for df in [-1, 1] {
        let nf = f + df;
        if !(0..8).contains(&nf) {
            continue;
        }
        let to = (sq as i32 + dir + df) as usize;
        let t = b[to];
        if t != EMPTY && color_of(t) != us {
            if (to >> 3) as u8 == promo_rank {
                push_promotions(out, sq, to as u8, 0);
            } else {
                out.push(Move::new(sq, to as u8));
            }
        } else if t == EMPTY && pos.ep != NO_SQ && pos.ep as usize == to {
            out.push(Move { from: sq, to: to as u8, promo: 0, flags: FLAG_EP });
        }
    }
}

fn gen_steps(pos: &Position, sq: u8, us: u8, dirs: &[(i32, i32)], out: &mut Vec<Move>, caps_only: bool) {
    let f = (sq & 7) as i32;
    let r = (sq >> 3) as i32;
    for &(df, dr) in dirs {
        let (nf, nr) = (f + df, r + dr);
        if !on_board(nf, nr) {
            continue;
        }
        let to = (nr * 8 + nf) as u8;
        let t = pos.b[to as usize];
        if t == EMPTY {
            if !caps_only {
                out.push(Move::new(sq, to));
            }
        } else if color_of(t) != us {
            out.push(Move::new(sq, to));
        }
    }
}

fn gen_slides(pos: &Position, sq: u8, us: u8, dirs: &[(i32, i32)], out: &mut Vec<Move>, caps_only: bool) {
    let f0 = (sq & 7) as i32;
    let r0 = (sq >> 3) as i32;
    for &(df, dr) in dirs {
        let (mut nf, mut nr) = (f0 + df, r0 + dr);
        while on_board(nf, nr) {
            let to = (nr * 8 + nf) as u8;
            let t = pos.b[to as usize];
            if t == EMPTY {
                if !caps_only {
                    out.push(Move::new(sq, to));
                }
            } else {
                if color_of(t) != us {
                    out.push(Move::new(sq, to));
                }
                break;
            }
            nf += df;
            nr += dr;
        }
    }
}

fn gen_castles(pos: &Position, us: u8, out: &mut Vec<Move>) {
    let them = us ^ 1;
    let b = &pos.b;
    if pos.in_check() {
        return;
    }
    let att = |s: usize| pos.is_attacked(s, them);
    if us == WHITE {
        if pos.castle & CASTLE_WK != 0
            && b[4] == make_piece(WHITE, KING)
            && b[7] == make_piece(WHITE, ROOK)
            && b[5] == EMPTY
            && b[6] == EMPTY
            && !att(5)
            && !att(6)
        {
            out.push(Move { from: 4, to: 6, promo: 0, flags: FLAG_CASTLE });
        }
        if pos.castle & CASTLE_WQ != 0
            && b[4] == make_piece(WHITE, KING)
            && b[0] == make_piece(WHITE, ROOK)
            && b[1] == EMPTY
            && b[2] == EMPTY
            && b[3] == EMPTY
            && !att(3)
            && !att(2)
        {
            out.push(Move { from: 4, to: 2, promo: 0, flags: FLAG_CASTLE });
        }
    } else {
        if pos.castle & CASTLE_BK != 0
            && b[60] == make_piece(BLACK, KING)
            && b[63] == make_piece(BLACK, ROOK)
            && b[61] == EMPTY
            && b[62] == EMPTY
            && !att(61)
            && !att(62)
        {
            out.push(Move { from: 60, to: 62, promo: 0, flags: FLAG_CASTLE });
        }
        if pos.castle & CASTLE_BQ != 0
            && b[60] == make_piece(BLACK, KING)
            && b[56] == make_piece(BLACK, ROOK)
            && b[57] == EMPTY
            && b[58] == EMPTY
            && b[59] == EMPTY
            && !att(59)
            && !att(58)
        {
            out.push(Move { from: 60, to: 58, promo: 0, flags: FLAG_CASTLE });
        }
    }
}

/// Pseudo-legal moves for the side to move (may leave own king in check).
/// With `caps_only`, only captures and promotions are produced.
pub fn pseudo_moves(pos: &Position, out: &mut Vec<Move>, caps_only: bool) {
    let us = pos.stm;
    for sq in 0..64u8 {
        let p = pos.b[sq as usize];
        if p == EMPTY || color_of(p) != us {
            continue;
        }
        match kind_of(p) {
            PAWN => gen_pawn(pos, sq, us, out, caps_only),
            KNIGHT => gen_steps(pos, sq, us, &KNIGHT_D, out, caps_only),
            KING => gen_steps(pos, sq, us, &KING_D, out, caps_only),
            BISHOP => gen_slides(pos, sq, us, &BISHOP_D, out, caps_only),
            ROOK => gen_slides(pos, sq, us, &ROOK_D, out, caps_only),
            QUEEN => {
                gen_slides(pos, sq, us, &BISHOP_D, out, caps_only);
                gen_slides(pos, sq, us, &ROOK_D, out, caps_only);
            }
            _ => {}
        }
    }
    if !caps_only {
        gen_castles(pos, us, out);
    }
}

/// Exactly the legal moves of the side to move.
pub fn legal_moves(pos: &mut Position, caps_only: bool) -> Vec<Move> {
    let mut pseudo = Vec::with_capacity(64);
    pseudo_moves(pos, &mut pseudo, caps_only);
    let us = pos.stm;
    let mut out = Vec::with_capacity(pseudo.len());
    for m in pseudo {
        pos.make_move(m);
        if !pos.is_attacked(pos.king[us as usize] as usize, us ^ 1) {
            out.push(m);
        }
        pos.unmake_move(m);
    }
    out
}

/// Number of leaf nodes at `depth` plies (depth 0 counts the position itself).
pub fn perft(pos: &mut Position, depth: u32) -> u64 {
    if depth == 0 {
        return 1;
    }
    let moves = legal_moves(pos, false);
    if depth == 1 {
        return moves.len() as u64;
    }
    let mut n = 0;
    for m in moves {
        pos.make_move(m);
        n += perft(pos, depth - 1);
        pos.unmake_move(m);
    }
    n
}
