//! Board state, FEN parsing, make-move and Zobrist hashing.

use std::sync::OnceLock;

use crate::attacks::{bishop_attacks, rook_attacks, tables};

pub const WHITE: usize = 0;
pub const BLACK: usize = 1;

pub const PAWN: usize = 0;
pub const KNIGHT: usize = 1;
pub const BISHOP: usize = 2;
pub const ROOK: usize = 3;
pub const QUEEN: usize = 4;
pub const KING: usize = 5;

pub const NO_SQ: u8 = 64;
pub const CASTLE_WK: u8 = 1;
pub const CASTLE_WQ: u8 = 2;
pub const CASTLE_BK: u8 = 4;
pub const CASTLE_BQ: u8 = 8;
pub const START_FEN: &str = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

/// A move. `promo` is the promotion piece type (KNIGHT..=QUEEN), or 0 when there is none.
#[derive(Clone, Copy, PartialEq, Eq, Debug, Default)]
pub struct Move {
    pub from: u8,
    pub to: u8,
    pub promo: u8,
}

impl Move {
    /// A placeholder that never equals a legal move (a1-a1).
    pub const NONE: Move = Move { from: 0, to: 0, promo: 0 };

    pub fn new(from: usize, to: usize, promo: usize) -> Move {
        Move { from: from as u8, to: to as u8, promo: promo as u8 }
    }

    /// Long algebraic notation, e.g. `e2e4` or `e7e8q`.
    pub fn uci(&self) -> String {
        let mut s = String::with_capacity(5);
        s.push((b'a' + self.from % 8) as char);
        s.push((b'1' + self.from / 8) as char);
        s.push((b'a' + self.to % 8) as char);
        s.push((b'1' + self.to / 8) as char);
        if self.promo != 0 {
            s.push(b"-nbrqk"[self.promo as usize] as char);
        }
        s
    }
}

#[inline]
pub fn bit(sq: usize) -> u64 {
    1u64 << sq
}

/// Removes and returns the lowest set square of `bb`.
#[inline]
pub fn pop_lsb(bb: &mut u64) -> usize {
    let sq = bb.trailing_zeros() as usize;
    *bb &= *bb - 1;
    sq
}

/// Mailbox code for a piece: 0 is empty, otherwise `1 + color * 6 + piece type`.
#[inline]
pub fn piece_code(color: usize, pt: usize) -> u8 {
    (color * 6 + pt + 1) as u8
}

/// Piece type of a non-empty mailbox code.
#[inline]
pub fn pt_of(code: u8) -> usize {
    ((code - 1) % 6) as usize
}

/// Castling rights that survive a move touching the given square.
const CASTLE_MASK: [u8; 64] = {
    let mut m = [0xFFu8; 64];
    m[0] = !CASTLE_WQ;
    m[4] = !(CASTLE_WK | CASTLE_WQ);
    m[7] = !CASTLE_WK;
    m[56] = !CASTLE_BQ;
    m[60] = !(CASTLE_BK | CASTLE_BQ);
    m[63] = !CASTLE_BK;
    m
};

struct Zobrist {
    piece: [[u64; 64]; 12],
    castle: [u64; 16],
    ep: [u64; 8],
    side: u64,
}

fn zobrist() -> &'static Zobrist {
    static Z: OnceLock<Zobrist> = OnceLock::new();
    Z.get_or_init(|| {
        let mut state: u64 = 0x2545_F491_4F6C_DD1D;
        let mut next = move || {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            state
        };
        let mut z = Zobrist { piece: [[0; 64]; 12], castle: [0; 16], ep: [0; 8], side: 0 };
        for row in z.piece.iter_mut() {
            for v in row.iter_mut() {
                *v = next();
            }
        }
        for v in z.castle.iter_mut() {
            *v = next();
        }
        for v in z.ep.iter_mut() {
            *v = next();
        }
        z.side = next();
        z
    })
}

#[derive(Clone, Copy)]
pub struct Position {
    /// Piece bitboards, indexed by `color * 6 + piece type`.
    pub bb: [u64; 12],
    /// Occupancy per colour.
    pub occ: [u64; 2],
    /// Mailbox: piece code per square (see `piece_code`).
    pub board: [u8; 64],
    pub side: usize,
    pub castle: u8,
    /// En-passant target square, or `NO_SQ`.
    pub ep: u8,
    pub halfmove: u32,
    pub fullmove: u32,
    pub hash: u64,
}

impl Position {
    pub fn empty() -> Position {
        Position {
            bb: [0; 12],
            occ: [0; 2],
            board: [0; 64],
            side: WHITE,
            castle: 0,
            ep: NO_SQ,
            halfmove: 0,
            fullmove: 1,
            hash: zobrist().castle[0],
        }
    }

    pub fn startpos() -> Position {
        Position::from_fen(START_FEN).expect("start position is valid")
    }

    pub fn from_fen(fen: &str) -> Result<Position, String> {
        let bad = || format!("bad FEN: {fen}");
        let f: Vec<&str> = fen.split_whitespace().collect();
        if f.len() < 4 {
            return Err(bad());
        }
        let rows: Vec<&str> = f[0].split('/').collect();
        if rows.len() != 8 {
            return Err(bad());
        }
        let mut pos = Position::empty();
        for (i, row) in rows.iter().enumerate() {
            let rank = 7 - i;
            let mut file = 0usize;
            for c in row.chars() {
                if let Some(d) = c.to_digit(10) {
                    file += d as usize;
                    continue;
                }
                let color = if c.is_ascii_uppercase() { WHITE } else { BLACK };
                let pt = match c.to_ascii_lowercase() {
                    'p' => PAWN,
                    'n' => KNIGHT,
                    'b' => BISHOP,
                    'r' => ROOK,
                    'q' => QUEEN,
                    'k' => KING,
                    _ => return Err(bad()),
                };
                if file >= 8 {
                    return Err(bad());
                }
                pos.put(rank * 8 + file, color, pt);
                file += 1;
            }
            if file != 8 {
                return Err(bad());
            }
        }
        pos.side = match f[1] {
            "w" => WHITE,
            "b" => BLACK,
            _ => return Err(bad()),
        };
        if pos.side == BLACK {
            pos.hash ^= zobrist().side;
        }
        let mut castle = 0u8;
        if f[2] != "-" {
            for c in f[2].chars() {
                castle |= match c {
                    'K' => CASTLE_WK,
                    'Q' => CASTLE_WQ,
                    'k' => CASTLE_BK,
                    'q' => CASTLE_BQ,
                    _ => return Err(bad()),
                };
            }
        }
        pos.set_castle(castle);
        if f[3] != "-" {
            let b = f[3].as_bytes();
            if b.len() != 2 {
                return Err(bad());
            }
            let file = b[0].wrapping_sub(b'a');
            let rank = b[1].wrapping_sub(b'1');
            if file >= 8 || rank >= 8 {
                return Err(bad());
            }
            pos.set_ep((rank as usize * 8 + file as usize) as u8);
        }
        pos.halfmove = f.get(4).and_then(|s| s.parse().ok()).unwrap_or(0);
        pos.fullmove = f.get(5).and_then(|s| s.parse().ok()).unwrap_or(1);
        if pos.bb[KING].count_ones() != 1 || pos.bb[BLACK * 6 + KING].count_ones() != 1 {
            return Err(bad());
        }
        Ok(pos)
    }

    #[inline]
    pub fn king_sq(&self, color: usize) -> usize {
        self.bb[color * 6 + KING].trailing_zeros() as usize
    }

    #[inline]
    pub fn has_non_pawn(&self, color: usize) -> bool {
        let base = color * 6;
        (self.bb[base + KNIGHT] | self.bb[base + BISHOP] | self.bb[base + ROOK] | self.bb[base + QUEEN]) != 0
    }

    #[inline]
    fn put(&mut self, sq: usize, color: usize, pt: usize) {
        let code = color * 6 + pt;
        self.bb[code] |= bit(sq);
        self.occ[color] |= bit(sq);
        self.board[sq] = code as u8 + 1;
        self.hash ^= zobrist().piece[code][sq];
    }

    #[inline]
    fn remove(&mut self, sq: usize) {
        let code = (self.board[sq] - 1) as usize;
        self.bb[code] &= !bit(sq);
        self.occ[code / 6] &= !bit(sq);
        self.board[sq] = 0;
        self.hash ^= zobrist().piece[code][sq];
    }

    fn set_castle(&mut self, rights: u8) {
        let z = zobrist();
        self.hash ^= z.castle[self.castle as usize] ^ z.castle[rights as usize];
        self.castle = rights;
    }

    fn set_ep(&mut self, sq: u8) {
        let z = zobrist();
        if self.ep != NO_SQ {
            self.hash ^= z.ep[(self.ep % 8) as usize];
        }
        self.ep = sq;
        if sq != NO_SQ {
            self.hash ^= z.ep[(sq % 8) as usize];
        }
    }

    /// Is `sq` attacked by any piece of colour `by`?
    #[inline]
    pub fn attacked_by(&self, sq: usize, by: usize) -> bool {
        let t = tables();
        let occ = self.occ[0] | self.occ[1];
        let base = by * 6;
        let queens = self.bb[base + QUEEN];
        (t.pawn[1 - by][sq] & self.bb[base + PAWN]) != 0
            || (t.knight[sq] & self.bb[base + KNIGHT]) != 0
            || (t.king[sq] & self.bb[base + KING]) != 0
            || (bishop_attacks(sq, occ) & (self.bb[base + BISHOP] | queens)) != 0
            || (rook_attacks(sq, occ) & (self.bb[base + ROOK] | queens)) != 0
    }

    #[inline]
    pub fn in_check(&self) -> bool {
        self.attacked_by(self.king_sq(self.side), 1 - self.side)
    }

    /// Applies a pseudo-legal move and returns the resulting position.
    pub fn make(&self, m: Move) -> Position {
        let mut p = *self;
        let from = m.from as usize;
        let to = m.to as usize;
        let us = p.side;
        let code = p.board[from];
        let pt = pt_of(code);
        let captured = p.board[to];
        let is_ep = pt == PAWN && captured == 0 && from % 8 != to % 8;

        p.set_ep(NO_SQ);
        p.set_castle(p.castle & CASTLE_MASK[from] & CASTLE_MASK[to]);
        p.halfmove += 1;
        if pt == PAWN || captured != 0 {
            p.halfmove = 0;
        }
        if captured != 0 {
            p.remove(to);
        }
        if is_ep {
            let cap_sq = if us == WHITE { to - 8 } else { to + 8 };
            p.remove(cap_sq);
        }
        p.remove(from);
        let new_pt = if m.promo != 0 { m.promo as usize } else { pt };
        p.put(to, us, new_pt);

        if pt == KING {
            if to == from + 2 {
                p.remove(from + 3);
                p.put(from + 1, us, ROOK);
            } else if from == to + 2 {
                p.remove(from - 4);
                p.put(from - 1, us, ROOK);
            }
        }
        if pt == PAWN && from.abs_diff(to) == 16 {
            p.set_ep(((from + to) / 2) as u8);
        }
        if us == BLACK {
            p.fullmove += 1;
        }
        p.side = 1 - us;
        p.hash ^= zobrist().side;
        p
    }

    /// The position after passing the move (used for null-move pruning).
    pub fn make_null(&self) -> Position {
        let mut p = *self;
        p.set_ep(NO_SQ);
        p.side = 1 - p.side;
        p.hash ^= zobrist().side;
        p.halfmove += 1;
        p
    }
}
