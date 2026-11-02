//! Position representation: bitboards, a mailbox copy, FEN parsing, make-move and Zobrist hashing.

use std::sync::OnceLock;

use crate::movegen::Move;

pub const WHITE: usize = 0;
pub const BLACK: usize = 1;

pub const PAWN: usize = 0;
pub const KNIGHT: usize = 1;
pub const BISHOP: usize = 2;
pub const ROOK: usize = 3;
pub const QUEEN: usize = 4;
pub const KING: usize = 5;

/// Mailbox value for an empty square.
pub const EMPTY: u8 = 12;
/// En-passant value meaning "no en-passant square".
pub const NO_EP: u8 = 64;

pub const CASTLE_WK: u8 = 1;
pub const CASTLE_WQ: u8 = 2;
pub const CASTLE_BK: u8 = 4;
pub const CASTLE_BQ: u8 = 8;

pub const START_FEN: &str = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

/// Ray directions as (file delta, rank delta): N, NE, E, SE, S, SW, W, NW.
const DIRS: [(i32, i32); 8] = [(0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1)];
/// Directions along which the square index increases (the nearest blocker is the lowest bit).
const POSITIVE: [bool; 8] = [true, true, true, false, false, false, false, true];
const ROOK_DIRS: [usize; 4] = [0, 2, 4, 6];
const BISHOP_DIRS: [usize; 4] = [1, 3, 5, 7];

pub struct Tables {
    pub knight: [u64; 64],
    pub king: [u64; 64],
    /// pawn[color][sq]: squares attacked by a pawn of `color` standing on `sq`.
    pub pawn: [[u64; 64]; 2],
    /// rays[dir][sq]: all squares strictly beyond `sq` in direction `dir`.
    pub rays: [[u64; 64]; 8],
    pub castle_mask: [u8; 64],
    pub zobrist_piece: [[u64; 64]; 12],
    pub zobrist_castle: [u64; 16],
    pub zobrist_ep: [u64; 8],
    pub zobrist_side: u64,
}

pub fn tables() -> &'static Tables {
    static T: OnceLock<Tables> = OnceLock::new();
    T.get_or_init(build_tables)
}

fn splitmix(state: &mut u64) -> u64 {
    *state = state.wrapping_add(0x9E37_79B9_7F4A_7C15);
    let mut z = *state;
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

fn build_tables() -> Tables {
    let mut t = Tables {
        knight: [0; 64],
        king: [0; 64],
        pawn: [[0; 64]; 2],
        rays: [[0; 64]; 8],
        castle_mask: [0b1111; 64],
        zobrist_piece: [[0; 64]; 12],
        zobrist_castle: [0; 16],
        zobrist_ep: [0; 8],
        zobrist_side: 0,
    };
    let on = |x: i32, y: i32| (0..8).contains(&x) && (0..8).contains(&y);
    for sq in 0..64usize {
        let f = (sq % 8) as i32;
        let r = (sq / 8) as i32;
        for (df, dr) in [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)] {
            if on(f + df, r + dr) {
                t.knight[sq] |= 1u64 << ((r + dr) * 8 + f + df);
            }
        }
        for (df, dr) in DIRS {
            if on(f + df, r + dr) {
                t.king[sq] |= 1u64 << ((r + dr) * 8 + f + df);
            }
        }
        for df in [-1, 1] {
            if on(f + df, r + 1) {
                t.pawn[WHITE][sq] |= 1u64 << ((r + 1) * 8 + f + df);
            }
            if on(f + df, r - 1) {
                t.pawn[BLACK][sq] |= 1u64 << ((r - 1) * 8 + f + df);
            }
        }
        for (d, (df, dr)) in DIRS.iter().enumerate() {
            let (mut x, mut y) = (f + df, r + dr);
            while on(x, y) {
                t.rays[d][sq] |= 1u64 << (y * 8 + x);
                x += df;
                y += dr;
            }
        }
    }
    t.castle_mask[0] &= !CASTLE_WQ; // a1
    t.castle_mask[7] &= !CASTLE_WK; // h1
    t.castle_mask[4] &= !(CASTLE_WK | CASTLE_WQ); // e1
    t.castle_mask[56] &= !CASTLE_BQ; // a8
    t.castle_mask[63] &= !CASTLE_BK; // h8
    t.castle_mask[60] &= !(CASTLE_BK | CASTLE_BQ); // e8

    let mut seed = 0x1234_5678_9abc_def0u64;
    for p in 0..12 {
        for s in 0..64 {
            t.zobrist_piece[p][s] = splitmix(&mut seed);
        }
    }
    for c in 0..16 {
        t.zobrist_castle[c] = splitmix(&mut seed);
    }
    for f in 0..8 {
        t.zobrist_ep[f] = splitmix(&mut seed);
    }
    t.zobrist_side = splitmix(&mut seed);
    t
}

#[inline]
pub fn rook_attacks(sq: usize, occ: u64) -> u64 {
    let t = tables();
    ROOK_DIRS.iter().fold(0, |acc, &d| acc | ray_attacks(t, d, sq, occ))
}

#[inline]
pub fn bishop_attacks(sq: usize, occ: u64) -> u64 {
    let t = tables();
    BISHOP_DIRS.iter().fold(0, |acc, &d| acc | ray_attacks(t, d, sq, occ))
}

#[inline]
fn ray_attacks(t: &Tables, d: usize, sq: usize, occ: u64) -> u64 {
    let ray = t.rays[d][sq];
    let blockers = ray & occ;
    if blockers == 0 {
        return ray;
    }
    let b = if POSITIVE[d] {
        blockers.trailing_zeros() as usize
    } else {
        63 - blockers.leading_zeros() as usize
    };
    // Keep everything up to and including the blocker.
    ray ^ t.rays[d][b]
}

pub fn parse_square(s: &str) -> Option<usize> {
    let b = s.as_bytes();
    if b.len() != 2 {
        return None;
    }
    let f = b[0].wrapping_sub(b'a');
    let r = b[1].wrapping_sub(b'1');
    if f < 8 && r < 8 {
        Some(r as usize * 8 + f as usize)
    } else {
        None
    }
}

pub fn square_name(sq: usize) -> String {
    let mut s = String::with_capacity(2);
    s.push((b'a' + (sq % 8) as u8) as char);
    s.push((b'1' + (sq / 8) as u8) as char);
    s
}

fn piece_from_char(c: char) -> Option<usize> {
    let color = if c.is_ascii_uppercase() { WHITE } else { BLACK };
    let kind = match c.to_ascii_lowercase() {
        'p' => PAWN,
        'n' => KNIGHT,
        'b' => BISHOP,
        'r' => ROOK,
        'q' => QUEEN,
        'k' => KING,
        _ => return None,
    };
    Some(color * 6 + kind)
}

#[derive(Clone, Copy)]
pub struct Position {
    /// Piece bitboards, index = color * 6 + kind.
    pub pieces: [u64; 12],
    /// Occupancy per colour.
    pub occ: [u64; 2],
    /// Mailbox: piece index (0..12) or EMPTY.
    pub board: [u8; 64],
    pub stm: usize,
    pub castle: u8,
    /// En-passant target square (only set when an en-passant capture is actually possible), or NO_EP.
    pub ep: u8,
    pub halfmove: u32,
    pub fullmove: u32,
    pub hash: u64,
}

impl Position {
    pub fn empty() -> Position {
        Position {
            pieces: [0; 12],
            occ: [0; 2],
            board: [EMPTY; 64],
            stm: WHITE,
            castle: 0,
            ep: NO_EP,
            halfmove: 0,
            fullmove: 1,
            hash: 0,
        }
    }

    pub fn startpos() -> Position {
        Position::from_fen(START_FEN).expect("start FEN is valid")
    }

    pub fn from_fen(fen: &str) -> Result<Position, String> {
        let parts: Vec<&str> = fen.split_whitespace().collect();
        if parts.len() < 4 {
            return Err("FEN needs at least four fields".into());
        }
        let mut p = Position::empty();
        let ranks: Vec<&str> = parts[0].split('/').collect();
        if ranks.len() != 8 {
            return Err("FEN board needs eight ranks".into());
        }
        for (i, row) in ranks.iter().enumerate() {
            let rank = 7 - i;
            let mut file = 0usize;
            for c in row.chars() {
                if let Some(d) = c.to_digit(10) {
                    file += d as usize;
                    continue;
                }
                let piece = piece_from_char(c).ok_or_else(|| format!("bad piece '{c}'"))?;
                if file >= 8 {
                    return Err("rank too long".into());
                }
                p.put(rank * 8 + file, piece);
                file += 1;
            }
            if file != 8 {
                return Err("rank does not have eight files".into());
            }
        }
        p.stm = match parts[1] {
            "w" => WHITE,
            "b" => BLACK,
            _ => return Err("bad side to move".into()),
        };
        for c in parts[2].chars() {
            p.castle |= match c {
                'K' => CASTLE_WK,
                'Q' => CASTLE_WQ,
                'k' => CASTLE_BK,
                'q' => CASTLE_BQ,
                '-' => 0,
                _ => return Err("bad castling field".into()),
            };
        }
        if parts[3] != "-" {
            let sq = parse_square(parts[3]).ok_or("bad en-passant square")?;
            p.ep = sq as u8;
        }
        p.halfmove = parts.get(4).and_then(|s| s.parse().ok()).unwrap_or(0);
        p.fullmove = parts.get(5).and_then(|s| s.parse().ok()).unwrap_or(1).max(1);
        // Keep the en-passant square only if it can be used, so that equal positions hash equally.
        if p.ep != NO_EP && !p.ep_capturable() {
            p.ep = NO_EP;
        }
        p.hash = p.compute_hash();
        Ok(p)
    }

    /// True if the side to move has a pawn that can capture on the en-passant square.
    fn ep_capturable(&self) -> bool {
        let e = self.ep as usize;
        // A pawn of the side to move on X attacks e iff X is in pawn[opponent][e].
        tables().pawn[self.stm ^ 1][e] & self.pieces[self.stm * 6 + PAWN] != 0
    }

    #[inline]
    pub fn put(&mut self, sq: usize, piece: usize) {
        let bit = 1u64 << sq;
        self.pieces[piece] |= bit;
        self.occ[piece / 6] |= bit;
        self.board[sq] = piece as u8;
        self.hash ^= tables().zobrist_piece[piece][sq];
    }

    #[inline]
    pub fn remove(&mut self, sq: usize) {
        let piece = self.board[sq] as usize;
        let bit = 1u64 << sq;
        self.pieces[piece] &= !bit;
        self.occ[piece / 6] &= !bit;
        self.board[sq] = EMPTY;
        self.hash ^= tables().zobrist_piece[piece][sq];
    }

    #[inline]
    pub fn has(&self, color: usize, kind: usize, sq: usize) -> bool {
        self.pieces[color * 6 + kind] & (1u64 << sq) != 0
    }

    /// Square of the king of `color`, or 64 if there is none.
    #[inline]
    pub fn king_sq(&self, color: usize) -> usize {
        let b = self.pieces[color * 6 + KING];
        if b == 0 {
            64
        } else {
            b.trailing_zeros() as usize
        }
    }

    /// True if square `sq` is attacked by any piece of colour `by`.
    pub fn is_attacked(&self, sq: usize, by: usize) -> bool {
        if sq >= 64 {
            return false;
        }
        let t = tables();
        let occ = self.occ[0] | self.occ[1];
        let base = by * 6;
        if t.pawn[by ^ 1][sq] & self.pieces[base + PAWN] != 0 {
            return true;
        }
        if t.knight[sq] & self.pieces[base + KNIGHT] != 0 {
            return true;
        }
        if t.king[sq] & self.pieces[base + KING] != 0 {
            return true;
        }
        let diag = self.pieces[base + BISHOP] | self.pieces[base + QUEEN];
        if bishop_attacks(sq, occ) & diag != 0 {
            return true;
        }
        let straight = self.pieces[base + ROOK] | self.pieces[base + QUEEN];
        rook_attacks(sq, occ) & straight != 0
    }

    #[inline]
    pub fn in_check(&self) -> bool {
        self.is_attacked(self.king_sq(self.stm), self.stm ^ 1)
    }

    /// For a position reached by a move of `mover`: true if `mover`'s king is not attacked.
    #[inline]
    pub fn legal_after_move(&self, mover: usize) -> bool {
        !self.is_attacked(self.king_sq(mover), self.stm)
    }

    pub fn has_non_pawn(&self, color: usize) -> bool {
        let b = color * 6;
        self.pieces[b + KNIGHT] | self.pieces[b + BISHOP] | self.pieces[b + ROOK] | self.pieces[b + QUEEN] != 0
    }

    /// Applies a pseudo-legal move. The result may leave the mover in check; callers must test that.
    pub fn make(&self, m: Move) -> Position {
        let t = tables();
        let mut p = *self;
        let us = self.stm;
        let them = us ^ 1;
        let from = m.from();
        let to = m.to();
        let moving = self.board[from] as usize;
        let kind = moving % 6;

        p.hash ^= t.zobrist_side;
        if p.ep != NO_EP {
            p.hash ^= t.zobrist_ep[(p.ep % 8) as usize];
        }
        p.ep = NO_EP;

        let old_castle = p.castle;
        p.castle &= t.castle_mask[from] & t.castle_mask[to];
        p.hash ^= t.zobrist_castle[old_castle as usize] ^ t.zobrist_castle[p.castle as usize];

        let mut capture = false;
        if m.is_ep() {
            let cap = if us == WHITE { to - 8 } else { to + 8 };
            p.remove(cap);
            capture = true;
        } else if self.board[to] != EMPTY {
            p.remove(to);
            capture = true;
        }
        p.remove(from);
        let placed = if m.promo() != 0 { us * 6 + m.promo() } else { moving };
        p.put(to, placed);

        if m.is_castle() {
            let (rf, rt) = match to {
                6 => (7, 5),
                2 => (0, 3),
                62 => (63, 61),
                _ => (56, 59),
            };
            let rook = p.board[rf] as usize;
            p.remove(rf);
            p.put(rt, rook);
        }

        if kind == PAWN || capture {
            p.halfmove = 0;
        } else {
            p.halfmove += 1;
        }
        if kind == PAWN && m.is_double() {
            let e = (from + to) / 2;
            if t.pawn[us][e] & p.pieces[them * 6 + PAWN] != 0 {
                p.ep = e as u8;
                p.hash ^= t.zobrist_ep[e % 8];
            }
        }
        if us == BLACK {
            p.fullmove += 1;
        }
        p.stm = them;
        p
    }

    /// Passes the move (used for null-move pruning).
    pub fn make_null(&self) -> Position {
        let t = tables();
        let mut p = *self;
        if p.ep != NO_EP {
            p.hash ^= t.zobrist_ep[(p.ep % 8) as usize];
            p.ep = NO_EP;
        }
        p.stm ^= 1;
        p.hash ^= t.zobrist_side;
        p.halfmove += 1;
        p
    }

    pub fn compute_hash(&self) -> u64 {
        let t = tables();
        let mut h = 0u64;
        for sq in 0..64 {
            let pc = self.board[sq];
            if pc != EMPTY {
                h ^= t.zobrist_piece[pc as usize][sq];
            }
        }
        h ^= t.zobrist_castle[self.castle as usize];
        if self.ep != NO_EP {
            h ^= t.zobrist_ep[(self.ep % 8) as usize];
        }
        if self.stm == BLACK {
            h ^= t.zobrist_side;
        }
        h
    }
}
