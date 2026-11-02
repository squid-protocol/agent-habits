//! Board representation: piece encoding, FEN parsing, make/unmake and Zobrist hashing.

use std::sync::OnceLock;

pub const WHITE: u8 = 0;
pub const BLACK: u8 = 1;

pub const EMPTY: u8 = 0;
pub const PAWN: u8 = 1;
pub const KNIGHT: u8 = 2;
pub const BISHOP: u8 = 3;
pub const ROOK: u8 = 4;
pub const QUEEN: u8 = 5;
pub const KING: u8 = 6;

/// Marker for "no en-passant square".
pub const NO_SQ: u8 = 64;

pub const CASTLE_WK: u8 = 1;
pub const CASTLE_WQ: u8 = 2;
pub const CASTLE_BK: u8 = 4;
pub const CASTLE_BQ: u8 = 8;

pub const FLAG_DOUBLE: u8 = 1;
pub const FLAG_EP: u8 = 2;
pub const FLAG_CASTLE: u8 = 4;

pub const START_FEN: &str = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

/// A piece is `kind | (color << 3)`; an empty square is 0.
#[inline]
pub fn make_piece(color: u8, kind: u8) -> u8 {
    kind | (color << 3)
}

#[inline]
pub fn kind_of(p: u8) -> u8 {
    p & 7
}

#[inline]
pub fn color_of(p: u8) -> u8 {
    p >> 3
}

/// A move. Squares are indexed a1 = 0 .. h8 = 63. `promo` is the promotion piece kind (0 if none).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Move {
    pub from: u8,
    pub to: u8,
    pub promo: u8,
    pub flags: u8,
}

impl Move {
    pub fn new(from: u8, to: u8) -> Move {
        Move { from, to, promo: 0, flags: 0 }
    }

    /// Same from/to/promotion, ignoring flags.
    #[inline]
    pub fn same_as(&self, o: &Move) -> bool {
        self.from == o.from && self.to == o.to && self.promo == o.promo
    }

    /// Long algebraic (UCI) notation, e.g. `e2e4`, `e7e8q`.
    pub fn uci(&self) -> String {
        let mut s = sq_name(self.from) + &sq_name(self.to);
        match self.promo {
            KNIGHT => s.push('n'),
            BISHOP => s.push('b'),
            ROOK => s.push('r'),
            QUEEN => s.push('q'),
            _ => {}
        }
        s
    }
}

pub fn sq_name(sq: u8) -> String {
    format!("{}{}", (b'a' + (sq & 7)) as char, (b'1' + (sq >> 3)) as char)
}

pub fn parse_square(s: &str) -> Option<u8> {
    let b = s.as_bytes();
    if b.len() != 2 || !(b'a'..=b'h').contains(&b[0]) || !(b'1'..=b'8').contains(&b[1]) {
        return None;
    }
    Some((b[1] - b'1') * 8 + (b[0] - b'a'))
}

struct Zobrist {
    piece: [[u64; 64]; 16],
    side: u64,
    castle: [u64; 16],
    ep: [u64; 8],
}

fn zobrist() -> &'static Zobrist {
    static Z: OnceLock<Zobrist> = OnceLock::new();
    Z.get_or_init(|| {
        let mut state: u64 = 0x1234_5678_9abc_def0;
        let mut next = move || {
            state = state.wrapping_add(0x9E37_79B9_7F4A_7C15);
            let mut z = state;
            z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
            z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
            z ^ (z >> 31)
        };
        let mut piece = [[0u64; 64]; 16];
        for row in piece.iter_mut() {
            for k in row.iter_mut() {
                *k = next();
            }
        }
        let side = next();
        let mut castle = [0u64; 16];
        for c in castle.iter_mut() {
            *c = next();
        }
        let mut ep = [0u64; 8];
        for e in ep.iter_mut() {
            *e = next();
        }
        Zobrist { piece, side, castle, ep }
    })
}

/// Castling-right mask applied to a square a move starts from or lands on.
const CASTLE_MASK: [u8; 64] = {
    let mut m = [0x0Fu8; 64];
    m[0] = !CASTLE_WQ & 0x0F;
    m[7] = !CASTLE_WK & 0x0F;
    m[4] = !(CASTLE_WK | CASTLE_WQ) & 0x0F;
    m[56] = !CASTLE_BQ & 0x0F;
    m[63] = !CASTLE_BK & 0x0F;
    m[60] = !(CASTLE_BK | CASTLE_BQ) & 0x0F;
    m
};

#[derive(Clone, Copy)]
struct Undo {
    moved: u8,
    captured: u8,
    castle: u8,
    ep: u8,
    half: u32,
    full: u32,
    hash: u64,
}

#[derive(Clone)]
pub struct Position {
    pub b: [u8; 64],
    pub stm: u8,
    pub castle: u8,
    pub ep: u8,
    pub half: u32,
    pub full: u32,
    pub hash: u64,
    pub king: [u8; 2],
    undo: Vec<Undo>,
}

impl Position {
    fn empty() -> Position {
        Position {
            b: [EMPTY; 64],
            stm: WHITE,
            castle: 0,
            ep: NO_SQ,
            half: 0,
            full: 1,
            hash: 0,
            king: [0, 0],
            undo: Vec::with_capacity(256),
        }
    }

    pub fn startpos() -> Position {
        from_fen(START_FEN).expect("start position is valid")
    }

    /// Replace the piece on `sq` and keep the hash in sync.
    #[inline]
    fn put(&mut self, sq: usize, p: u8) {
        let z = zobrist();
        let old = self.b[sq];
        if old != EMPTY {
            self.hash ^= z.piece[old as usize][sq];
        }
        if p != EMPTY {
            self.hash ^= z.piece[p as usize][sq];
        }
        self.b[sq] = p;
    }

    pub fn compute_hash(&self) -> u64 {
        let z = zobrist();
        let mut h = 0u64;
        for sq in 0..64 {
            let p = self.b[sq];
            if p != EMPTY {
                h ^= z.piece[p as usize][sq];
            }
        }
        if self.stm == BLACK {
            h ^= z.side;
        }
        h ^= z.castle[self.castle as usize];
        if self.ep != NO_SQ {
            h ^= z.ep[(self.ep & 7) as usize];
        }
        h
    }

    pub fn make_move(&mut self, m: Move) {
        let z = zobrist();
        let us = self.stm;
        let them = us ^ 1;
        let from = m.from as usize;
        let to = m.to as usize;
        let moved = self.b[from];
        let kind = kind_of(moved);
        // The square whose occupant is removed: `to` normally, the passed pawn for en passant.
        let cap_sq = if m.flags & FLAG_EP != 0 {
            if us == WHITE { to - 8 } else { to + 8 }
        } else {
            to
        };
        let captured = self.b[cap_sq];

        self.undo.push(Undo {
            moved,
            captured,
            castle: self.castle,
            ep: self.ep,
            half: self.half,
            full: self.full,
            hash: self.hash,
        });

        if self.ep != NO_SQ {
            self.hash ^= z.ep[(self.ep & 7) as usize];
            self.ep = NO_SQ;
        }

        if m.flags & FLAG_EP != 0 {
            self.put(cap_sq, EMPTY);
        }

        self.put(from, EMPTY);
        let placed = if m.promo != 0 { make_piece(us, m.promo) } else { moved };
        self.put(to, placed);

        if kind == KING {
            self.king[us as usize] = m.to;
            if m.flags & FLAG_CASTLE != 0 {
                let (rf, rt) = if to > from { (from + 3, from + 1) } else { (from - 4, from - 1) };
                let rook = self.b[rf];
                self.put(rf, EMPTY);
                self.put(rt, rook);
            }
        }

        let newc = self.castle & CASTLE_MASK[from] & CASTLE_MASK[to];
        if newc != self.castle {
            self.hash ^= z.castle[self.castle as usize] ^ z.castle[newc as usize];
            self.castle = newc;
        }

        if m.flags & FLAG_DOUBLE != 0 {
            let ep = ((from + to) / 2) as u8;
            self.ep = ep;
            self.hash ^= z.ep[(ep & 7) as usize];
        }

        self.half = if kind == PAWN || captured != EMPTY { 0 } else { self.half + 1 };
        if us == BLACK {
            self.full += 1;
        }
        self.stm = them;
        self.hash ^= z.side;
    }

    pub fn unmake_move(&mut self, m: Move) {
        let u = self.undo.pop().expect("unmake without make");
        let us = self.stm ^ 1;
        let from = m.from as usize;
        let to = m.to as usize;

        self.b[from] = u.moved;
        if m.flags & FLAG_EP != 0 {
            self.b[to] = EMPTY;
            let cap = if us == WHITE { to - 8 } else { to + 8 };
            self.b[cap] = u.captured;
        } else {
            self.b[to] = u.captured;
        }

        if kind_of(u.moved) == KING {
            self.king[us as usize] = m.from;
            if m.flags & FLAG_CASTLE != 0 {
                let (rf, rt) = if to > from { (from + 3, from + 1) } else { (from - 4, from - 1) };
                self.b[rf] = self.b[rt];
                self.b[rt] = EMPTY;
            }
        }

        self.stm = us;
        self.castle = u.castle;
        self.ep = u.ep;
        self.half = u.half;
        self.full = u.full;
        self.hash = u.hash;
    }

    /// True if the current position occurred earlier in the game/search path (twofold is enough inside a search).
    pub fn repetition(&self) -> bool {
        let n = self.undo.len();
        let lim = (self.half as usize).min(n);
        let mut k = 2;
        while k <= lim {
            if self.undo[n - k].hash == self.hash {
                return true;
            }
            k += 2;
        }
        false
    }
}

pub fn from_fen(fen: &str) -> Result<Position, String> {
    let f: Vec<&str> = fen.split_whitespace().collect();
    if f.is_empty() {
        return Err("empty FEN".into());
    }
    let mut pos = Position::empty();
    let rows: Vec<&str> = f[0].split('/').collect();
    if rows.len() != 8 {
        return Err("board must have 8 ranks".into());
    }
    for (i, row) in rows.iter().enumerate() {
        let rank = 7 - i;
        let mut file = 0usize;
        for ch in row.chars() {
            if let Some(d) = ch.to_digit(10) {
                file += d as usize;
                continue;
            }
            let color = if ch.is_ascii_uppercase() { WHITE } else { BLACK };
            let kind = match ch.to_ascii_lowercase() {
                'p' => PAWN,
                'n' => KNIGHT,
                'b' => BISHOP,
                'r' => ROOK,
                'q' => QUEEN,
                'k' => KING,
                _ => return Err(format!("bad piece '{ch}'")),
            };
            if file >= 8 || (kind == PAWN && (rank == 0 || rank == 7)) {
                return Err("bad piece placement".into());
            }
            pos.b[rank * 8 + file] = make_piece(color, kind);
            file += 1;
        }
        if file != 8 {
            return Err("rank does not have 8 files".into());
        }
    }
    pos.stm = match f.get(1).copied().unwrap_or("w") {
        "w" => WHITE,
        "b" => BLACK,
        _ => return Err("bad side to move".into()),
    };
    for c in f.get(2).copied().unwrap_or("-").chars() {
        pos.castle |= match c {
            'K' => CASTLE_WK,
            'Q' => CASTLE_WQ,
            'k' => CASTLE_BK,
            'q' => CASTLE_BQ,
            '-' => 0,
            _ => return Err("bad castling field".into()),
        };
    }
    pos.ep = match f.get(3).copied() {
        None | Some("-") => NO_SQ,
        Some(s) => parse_square(s).ok_or("bad en-passant square")?,
    };
    pos.half = f.get(4).and_then(|s| s.parse().ok()).unwrap_or(0);
    pos.full = f.get(5).and_then(|s| s.parse().ok()).unwrap_or(1);

    let mut found = [false; 2];
    for sq in 0..64 {
        let p = pos.b[sq];
        if p != EMPTY && kind_of(p) == KING {
            let c = color_of(p) as usize;
            found[c] = true;
            pos.king[c] = sq as u8;
        }
    }
    if !found[0] || !found[1] {
        return Err("each side needs exactly one king".into());
    }
    pos.hash = pos.compute_hash();
    Ok(pos)
}
