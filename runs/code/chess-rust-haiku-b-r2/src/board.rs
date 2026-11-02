//! Board representation, moves, Zobrist hashing, FEN parsing and making moves.

use std::sync::OnceLock;

use crate::attacks::*;

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

// Move flags (stored in bits 12..15 of a move).
pub const F_QUIET: u16 = 0;
pub const F_DOUBLE: u16 = 1;
pub const F_OO: u16 = 2;
pub const F_OOO: u16 = 3;
pub const F_EP: u16 = 4;
pub const F_CAP: u16 = 5;
/// Non-capture promotions: 8 + piece (0 N, 1 B, 2 R, 3 Q).
pub const F_PROMO_N: u16 = 8;
/// Capture promotions: 12 + piece.
pub const F_CAP_PROMO_N: u16 = 12;

/// A move packed into 16 bits: from (0..6), to (6..12), flag (12..16).
#[derive(Clone, Copy, PartialEq, Eq, Default, Debug)]
pub struct Move(pub u16);

impl Move {
    pub const NONE: Move = Move(0);

    #[inline(always)]
    pub fn new(from: usize, to: usize, flag: u16) -> Move {
        Move(from as u16 | ((to as u16) << 6) | (flag << 12))
    }
    #[inline(always)]
    pub fn from(self) -> usize {
        (self.0 & 63) as usize
    }
    #[inline(always)]
    pub fn to(self) -> usize {
        ((self.0 >> 6) & 63) as usize
    }
    #[inline(always)]
    pub fn flag(self) -> u16 {
        self.0 >> 12
    }
    #[inline(always)]
    pub fn is_capture(self) -> bool {
        let f = self.flag();
        f == F_EP || f == F_CAP || f >= F_CAP_PROMO_N
    }
    #[inline(always)]
    pub fn is_promo(self) -> bool {
        self.flag() >= F_PROMO_N
    }
    #[inline(always)]
    pub fn promo_piece(self) -> usize {
        [KNIGHT, BISHOP, ROOK, QUEEN][(self.flag() & 3) as usize]
    }
    pub fn to_uci(self) -> String {
        if self == Move::NONE {
            return "0000".to_string();
        }
        let name = |s: usize| format!("{}{}", (b'a' + (s % 8) as u8) as char, (b'1' + (s / 8) as u8) as char);
        let mut s = format!("{}{}", name(self.from()), name(self.to()));
        if self.is_promo() {
            s.push(['n', 'b', 'r', 'q'][(self.flag() & 3) as usize]);
        }
        s
    }
}

/// Zobrist keys, generated deterministically at first use.
pub struct Zobrist {
    pub piece: [[[u64; 64]; 6]; 2],
    pub side: u64,
    pub castle: [u64; 16],
    pub ep: [u64; 8],
}

fn splitmix(state: &mut u64) -> u64 {
    *state = state.wrapping_add(0x9E37_79B9_7F4A_7C15);
    let mut z = *state;
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

static ZOBRIST: OnceLock<Zobrist> = OnceLock::new();

pub fn zobrist() -> &'static Zobrist {
    ZOBRIST.get_or_init(|| {
        let mut s = 0x1234_5678_9ABC_DEF0u64;
        let mut z = Zobrist { piece: [[[0; 64]; 6]; 2], side: 0, castle: [0; 16], ep: [0; 8] };
        for c in 0..2 {
            for p in 0..6 {
                for sq in 0..64 {
                    z.piece[c][p][sq] = splitmix(&mut s);
                }
            }
        }
        z.side = splitmix(&mut s);
        for i in 0..16 {
            z.castle[i] = splitmix(&mut s);
        }
        for i in 0..8 {
            z.ep[i] = splitmix(&mut s);
        }
        z
    })
}

/// Castling rights that survive a move touching `sq`.
#[inline]
fn castle_mask(sq: usize) -> u8 {
    match sq {
        0 => !CASTLE_WQ,
        7 => !CASTLE_WK,
        4 => !(CASTLE_WK | CASTLE_WQ),
        56 => !CASTLE_BQ,
        63 => !CASTLE_BK,
        60 => !(CASTLE_BK | CASTLE_BQ),
        _ => 0xF,
    }
}

#[derive(Clone, Copy)]
pub struct Board {
    /// pieces[colour][piece type] bitboards.
    pub pieces: [[u64; 6]; 2],
    pub occ: [u64; 2],
    pub side: usize,
    pub castle: u8,
    /// En-passant target square, or NO_SQ.
    pub ep: u8,
    pub halfmove: u32,
    pub fullmove: u32,
    pub hash: u64,
}

impl Board {
    pub fn empty() -> Board {
        Board {
            pieces: [[0; 6]; 2],
            occ: [0; 2],
            side: WHITE,
            castle: 0,
            ep: NO_SQ,
            halfmove: 0,
            fullmove: 1,
            hash: 0,
        }
    }

    pub fn startpos() -> Board {
        Board::from_fen(START_FEN).expect("valid start FEN")
    }

    fn put(&mut self, c: usize, pt: usize, sq: usize) {
        let bit = 1u64 << sq;
        self.pieces[c][pt] |= bit;
        self.occ[c] |= bit;
    }

    pub fn from_fen(s: &str) -> Option<Board> {
        let mut it = s.split_whitespace();
        let placement = it.next()?;
        let side = it.next()?;
        let castling = it.next().unwrap_or("-");
        let ep = it.next().unwrap_or("-");
        let halfmove = it.next().unwrap_or("0").parse().unwrap_or(0);
        let fullmove = it.next().unwrap_or("1").parse().unwrap_or(1);

        let mut b = Board::empty();
        let (mut rank, mut file) = (7i32, 0i32);
        for ch in placement.chars() {
            match ch {
                '/' => {
                    rank -= 1;
                    file = 0;
                }
                '1'..='8' => file += ch as i32 - '0' as i32,
                _ => {
                    let color = if ch.is_ascii_uppercase() { WHITE } else { BLACK };
                    let pt = match ch.to_ascii_lowercase() {
                        'p' => PAWN,
                        'n' => KNIGHT,
                        'b' => BISHOP,
                        'r' => ROOK,
                        'q' => QUEEN,
                        'k' => KING,
                        _ => return None,
                    };
                    if !(0..8).contains(&file) || !(0..8).contains(&rank) {
                        return None;
                    }
                    b.put(color, pt, (rank * 8 + file) as usize);
                    file += 1;
                }
            }
        }
        if rank != 0 || file != 8 {
            return None;
        }
        b.side = match side {
            "w" => WHITE,
            "b" => BLACK,
            _ => return None,
        };
        for ch in castling.chars() {
            match ch {
                'K' => b.castle |= CASTLE_WK,
                'Q' => b.castle |= CASTLE_WQ,
                'k' => b.castle |= CASTLE_BK,
                'q' => b.castle |= CASTLE_BQ,
                '-' => {}
                _ => return None,
            }
        }
        if ep != "-" {
            let bytes = ep.as_bytes();
            if bytes.len() != 2 {
                return None;
            }
            let f = bytes[0].wrapping_sub(b'a') as usize;
            let r = bytes[1].wrapping_sub(b'1') as usize;
            if f > 7 || r > 7 {
                return None;
            }
            b.ep = (r * 8 + f) as u8;
        }
        b.halfmove = halfmove;
        b.fullmove = fullmove;
        if b.pieces[WHITE][KING].count_ones() != 1 || b.pieces[BLACK][KING].count_ones() != 1 {
            return None;
        }
        b.hash = b.compute_hash();
        Some(b)
    }

    pub fn compute_hash(&self) -> u64 {
        let z = zobrist();
        let mut h = 0u64;
        for c in 0..2 {
            for pt in 0..6 {
                let mut bb = self.pieces[c][pt];
                while bb != 0 {
                    let sq = bb.trailing_zeros() as usize;
                    bb &= bb - 1;
                    h ^= z.piece[c][pt][sq];
                }
            }
        }
        if self.side == BLACK {
            h ^= z.side;
        }
        h ^= z.castle[self.castle as usize];
        if self.ep != NO_SQ {
            h ^= z.ep[(self.ep % 8) as usize];
        }
        h
    }

    /// Piece type of colour `c` on square `sq`, if any.
    #[inline]
    pub fn piece_type_at(&self, c: usize, sq: usize) -> Option<usize> {
        let bit = 1u64 << sq;
        (0..6).find(|&pt| self.pieces[c][pt] & bit != 0)
    }

    #[inline]
    pub fn king_sq(&self, c: usize) -> usize {
        self.pieces[c][KING].trailing_zeros() as usize
    }

    /// True if square `sq` is attacked by any piece of colour `by`.
    pub fn is_attacked(&self, sq: usize, by: usize) -> bool {
        let occ = self.occ[0] | self.occ[1];
        let p = &self.pieces[by];
        if PAWN_ATT[by ^ 1][sq] & p[PAWN] != 0 {
            return true;
        }
        if KNIGHT_ATT[sq] & p[KNIGHT] != 0 {
            return true;
        }
        if KING_ATT[sq] & p[KING] != 0 {
            return true;
        }
        if bishop_attacks(occ, sq) & (p[BISHOP] | p[QUEEN]) != 0 {
            return true;
        }
        rook_attacks(occ, sq) & (p[ROOK] | p[QUEEN]) != 0
    }

    #[inline]
    pub fn in_check(&self) -> bool {
        self.is_attacked(self.king_sq(self.side), self.side ^ 1)
    }

    /// Applies a pseudo-legal move and returns the resulting position.
    pub fn make(&self, m: Move) -> Board {
        let z = zobrist();
        let mut b = *self;
        let us = self.side;
        let them = us ^ 1;
        let from = m.from();
        let to = m.to();
        let flag = m.flag();
        let pt = self.piece_type_at(us, from).expect("moving piece present");
        let from_bit = 1u64 << from;
        let to_bit = 1u64 << to;

        if b.ep != NO_SQ {
            b.hash ^= z.ep[(b.ep % 8) as usize];
        }
        b.ep = NO_SQ;

        // Lift the moving piece.
        b.pieces[us][pt] ^= from_bit;
        b.occ[us] ^= from_bit;
        b.hash ^= z.piece[us][pt][from];

        // Remove a captured piece.
        if flag == F_EP {
            let cap = if us == WHITE { to - 8 } else { to + 8 };
            let bit = 1u64 << cap;
            b.pieces[them][PAWN] ^= bit;
            b.occ[them] ^= bit;
            b.hash ^= z.piece[them][PAWN][cap];
        } else if m.is_capture() {
            let cpt = self.piece_type_at(them, to).expect("captured piece present");
            b.pieces[them][cpt] ^= to_bit;
            b.occ[them] ^= to_bit;
            b.hash ^= z.piece[them][cpt][to];
        }

        // Place the moving piece (or its promotion).
        let placed = if m.is_promo() { m.promo_piece() } else { pt };
        b.pieces[us][placed] |= to_bit;
        b.occ[us] |= to_bit;
        b.hash ^= z.piece[us][placed][to];

        // Castling also moves the rook.
        let rook_hop = match flag {
            F_OO => Some(if us == WHITE { (7, 5) } else { (63, 61) }),
            F_OOO => Some(if us == WHITE { (0, 3) } else { (56, 59) }),
            _ => None,
        };
        if let Some((rf, rt)) = rook_hop {
            let bits = (1u64 << rf) | (1u64 << rt);
            b.pieces[us][ROOK] ^= bits;
            b.occ[us] ^= bits;
            b.hash ^= z.piece[us][ROOK][rf] ^ z.piece[us][ROOK][rt];
        }

        let old_castle = b.castle;
        b.castle &= castle_mask(from) & castle_mask(to);
        if b.castle != old_castle {
            b.hash ^= z.castle[old_castle as usize] ^ z.castle[b.castle as usize];
        }

        if flag == F_DOUBLE {
            let e = (from + to) / 2;
            b.ep = e as u8;
            b.hash ^= z.ep[e % 8];
        }

        if pt == PAWN || m.is_capture() {
            b.halfmove = 0;
        } else {
            b.halfmove += 1;
        }
        if us == BLACK {
            b.fullmove += 1;
        }
        b.side = them;
        b.hash ^= z.side;
        b
    }

    /// Passes the move to the opponent (used for null-move pruning).
    pub fn make_null(&self) -> Board {
        let z = zobrist();
        let mut b = *self;
        if b.ep != NO_SQ {
            b.hash ^= z.ep[(b.ep % 8) as usize];
            b.ep = NO_SQ;
        }
        b.side ^= 1;
        b.hash ^= z.side;
        b.halfmove += 1;
        b
    }
}
