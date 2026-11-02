use std::collections::VecDeque;
use std::io::{self, BufRead, Write};
use std::sync::mpsc::{channel, Receiver};
use std::time::Instant;

#[derive(Clone, Copy, PartialEq, Eq, Default)]
struct Move {
    from: u8,
    to: u8,
    promo: u8,
}
impl Move {
    fn is_null(&self) -> bool {
        self.from == 0 && self.to == 0
    }
    fn to_str(&self) -> String {
        let mut s = String::new();
        s.push((b'a' + (self.from & 7)) as char);
        s.push((b'1' + (self.from >> 3)) as char);
        s.push((b'a' + (self.to & 7)) as char);
        s.push((b'1' + (self.to >> 3)) as char);
        if self.promo != 0 {
            s.push(b"  nbrq"[self.promo as usize] as char);
        }
        s
    }
}

const KN: [(i32, i32); 8] = [(1, 2), (2, 1), (-1, 2), (-2, 1), (1, -2), (2, -1), (-1, -2), (-2, -1)];
const KI: [(i32, i32); 8] = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)];
const DIAG: [(i32, i32); 4] = [(1, 1), (1, -1), (-1, 1), (-1, -1)];
const ORTH: [(i32, i32); 4] = [(1, 0), (-1, 0), (0, 1), (0, -1)];

struct Zob {
    piece: [[u64; 64]; 16],
    castle: [u64; 16],
    ep: [u64; 8],
    side: u64,
}
fn make_zob() -> Zob {
    let mut s: u64 = 0x9E3779B97F4A7C15;
    let mut next = || {
        s ^= s << 13;
        s ^= s >> 7;
        s ^= s << 17;
        s.wrapping_mul(0x2545F4914F6CDD1D)
    };
    let mut z = Zob { piece: [[0; 64]; 16], castle: [0; 16], ep: [0; 8], side: 0 };
    for p in 0..16 {
        for q in 0..64 {
            z.piece[p][q] = next();
        }
    }
    for i in 0..16 {
        z.castle[i] = next();
    }
    for i in 0..8 {
        z.ep[i] = next();
    }
    z.side = next();
    z
}

#[derive(Clone, Copy)]
struct Pos {
    b: [u8; 64],
    stm: u8,
    castle: u8,
    ep: i8,
    half: u32,
    hash: u64,
    ksq: [u8; 2],
}

const CASTLE_MASK: [(usize, u8); 6] = [(0, 2), (4, 3), (7, 1), (56, 8), (60, 12), (63, 4)];

impl Pos {
    fn from_fen(fen: &str, z: &Zob) -> Option<Pos> {
        let mut it = fen.split_whitespace();
        let board = it.next()?;
        let mut p = Pos { b: [0; 64], stm: 0, castle: 0, ep: -1, half: 0, hash: 0, ksq: [4, 60] };
        let mut r = 7i32;
        let mut f = 0i32;
        for c in board.chars() {
            if c == '/' {
                r -= 1;
                f = 0;
            } else if let Some(d) = c.to_digit(10) {
                f += d as i32;
            } else {
                let t = match c.to_ascii_lowercase() {
                    'p' => 1,
                    'n' => 2,
                    'b' => 3,
                    'r' => 4,
                    'q' => 5,
                    'k' => 6,
                    _ => return None,
                };
                if !(0..8).contains(&r) || !(0..8).contains(&f) {
                    return None;
                }
                let col = if c.is_ascii_uppercase() { 0 } else { 8 };
                let sq = (r * 8 + f) as usize;
                p.b[sq] = t | col;
                if t == 6 {
                    p.ksq[(col >> 3) as usize] = sq as u8;
                }
                f += 1;
            }
        }
        p.stm = if it.next().unwrap_or("w") == "b" { 1 } else { 0 };
        for c in it.next().unwrap_or("-").chars() {
            p.castle |= match c {
                'K' => 1,
                'Q' => 2,
                'k' => 4,
                'q' => 8,
                _ => 0,
            };
        }
        let e = it.next().unwrap_or("-").as_bytes();
        if e.len() == 2 && e[0] >= b'a' && e[0] <= b'h' && e[1] >= b'1' && e[1] <= b'8' {
            p.ep = ((e[1] - b'1') * 8 + (e[0] - b'a')) as i8;
        }
        p.half = it.next().and_then(|s| s.parse().ok()).unwrap_or(0);
        p.hash = p.compute_hash(z);
        Some(p)
    }
    fn compute_hash(&self, z: &Zob) -> u64 {
        let mut h = 0;
        for s in 0..64 {
            if self.b[s] != 0 {
                h ^= z.piece[self.b[s] as usize][s];
            }
        }
        h ^= z.castle[self.castle as usize];
        if self.ep >= 0 {
            h ^= z.ep[(self.ep & 7) as usize];
        }
        if self.stm == 1 {
            h ^= z.side;
        }
        h
    }
    fn attacked(&self, sq: usize, by: u8) -> bool {
        let f = (sq & 7) as i32;
        let r = (sq >> 3) as i32;
        let col = by << 3;
        let at = |df: i32, dr: i32| -> u8 {
            let nf = f + df;
            let nr = r + dr;
            if (0..8).contains(&nf) && (0..8).contains(&nr) {
                self.b[(nr * 8 + nf) as usize]
            } else {
                255
            }
        };
        let pr = if by == 0 { -1 } else { 1 };
        for df in [-1, 1] {
            if at(df, pr) == (1 | col) {
                return true;
            }
        }
        for (df, dr) in KN {
            if at(df, dr) == (2 | col) {
                return true;
            }
        }
        for (df, dr) in KI {
            if at(df, dr) == (6 | col) {
                return true;
            }
        }
        for (dirs, a, b2) in [(&DIAG, 3u8, 5u8), (&ORTH, 4u8, 5u8)] {
            for &(df, dr) in dirs.iter() {
                let mut k = 1;
                loop {
                    let p = at(df * k, dr * k);
                    if p == 255 {
                        break;
                    }
                    if p != 0 {
                        if p == (a | col) || p == (b2 | col) {
                            return true;
                        }
                        break;
                    }
                    k += 1;
                }
            }
        }
        false
    }
    fn in_check(&self) -> bool {
        self.attacked(self.ksq[self.stm as usize] as usize, 1 - self.stm)
    }
    fn gen(&self, out: &mut Vec<Move>, caps_only: bool) {
        let us = self.stm;
        for sq in 0..64usize {
            let p = self.b[sq];
            if p == 0 || (p >> 3) != us {
                continue;
            }
            let t = p & 7;
            let f = (sq & 7) as i32;
            let r = (sq >> 3) as i32;
            match t {
                1 => {
                    let dr = if us == 0 { 1 } else { -1 };
                    let start = if us == 0 { 1 } else { 6 };
                    let promo_from = if us == 0 { 6 } else { 1 };
                    let r1 = r + dr;
                    let to = (r1 * 8 + f) as usize;
                    let mut add = |to: usize, out: &mut Vec<Move>| {
                        if r == promo_from {
                            for pr in (2..=5).rev() {
                                out.push(Move { from: sq as u8, to: to as u8, promo: pr });
                            }
                        } else {
                            out.push(Move { from: sq as u8, to: to as u8, promo: 0 });
                        }
                    };
                    if self.b[to] == 0 {
                        if r == promo_from || !caps_only {
                            add(to, out);
                        }
                        if r == start && !caps_only {
                            let to2 = ((r + 2 * dr) * 8 + f) as usize;
                            if self.b[to2] == 0 {
                                out.push(Move { from: sq as u8, to: to2 as u8, promo: 0 });
                            }
                        }
                    }
                    for df in [-1, 1] {
                        let nf = f + df;
                        if !(0..8).contains(&nf) {
                            continue;
                        }
                        let to = (r1 * 8 + nf) as usize;
                        if self.b[to] != 0 && (self.b[to] >> 3) != us {
                            add(to, out);
                        } else if self.b[to] == 0 && to as i8 == self.ep {
                            out.push(Move { from: sq as u8, to: to as u8, promo: 0 });
                        }
                    }
                }
                2 | 6 => {
                    let d = if t == 2 { &KN } else { &KI };
                    for &(df, dr) in d.iter() {
                        let nf = f + df;
                        let nr = r + dr;
                        if !(0..8).contains(&nf) || !(0..8).contains(&nr) {
                            continue;
                        }
                        let to = (nr * 8 + nf) as usize;
                        let q = self.b[to];
                        if q == 0 {
                            if !caps_only {
                                out.push(Move { from: sq as u8, to: to as u8, promo: 0 });
                            }
                        } else if (q >> 3) != us {
                            out.push(Move { from: sq as u8, to: to as u8, promo: 0 });
                        }
                    }
                }
                _ => {
                    let both = [&DIAG[..], &ORTH[..]];
                    for (i, dirs) in both.iter().enumerate() {
                        if (i == 0 && t == 4) || (i == 1 && t == 3) {
                            continue;
                        }
                        for &(df, dr) in dirs.iter() {
                            let mut nf = f + df;
                            let mut nr = r + dr;
                            while (0..8).contains(&nf) && (0..8).contains(&nr) {
                                let to = (nr * 8 + nf) as usize;
                                let q = self.b[to];
                                if q == 0 {
                                    if !caps_only {
                                        out.push(Move { from: sq as u8, to: to as u8, promo: 0 });
                                    }
                                } else {
                                    if (q >> 3) != us {
                                        out.push(Move { from: sq as u8, to: to as u8, promo: 0 });
                                    }
                                    break;
                                }
                                nf += df;
                                nr += dr;
                            }
                        }
                    }
                }
            }
        }
        if !caps_only {
            let o = if us == 0 { 0usize } else { 56 };
            let them = 1 - us;
            let king = 6 | (us << 3);
            let rook = 4 | (us << 3);
            if self.b[o + 4] == king && !self.attacked(o + 4, them) {
                let (ks, qs) = if us == 0 { (1, 2) } else { (4, 8) };
                if self.castle & ks != 0
                    && self.b[o + 7] == rook
                    && self.b[o + 5] == 0
                    && self.b[o + 6] == 0
                    && !self.attacked(o + 5, them)
                    && !self.attacked(o + 6, them)
                {
                    out.push(Move { from: (o + 4) as u8, to: (o + 6) as u8, promo: 0 });
                }
                if self.castle & qs != 0
                    && self.b[o] == rook
                    && self.b[o + 1] == 0
                    && self.b[o + 2] == 0
                    && self.b[o + 3] == 0
                    && !self.attacked(o + 3, them)
                    && !self.attacked(o + 2, them)
                {
                    out.push(Move { from: (o + 4) as u8, to: (o + 2) as u8, promo: 0 });
                }
            }
        }
    }
    fn is_capture(&self, m: Move) -> bool {
        self.b[m.to as usize] != 0 || ((self.b[m.from as usize] & 7) == 1 && m.to as i8 == self.ep && (m.from & 7) != (m.to & 7))
    }
    fn make(&self, m: Move, z: &Zob) -> Pos {
        let mut n = *self;
        let from = m.from as usize;
        let to = m.to as usize;
        let p = n.b[from];
        let t = p & 7;
        let us = n.stm;
        let cap = n.b[to];
        n.hash ^= z.side;
        if n.ep >= 0 {
            n.hash ^= z.ep[(n.ep & 7) as usize];
        }
        let old_ep = n.ep;
        n.ep = -1;
        n.hash ^= z.piece[p as usize][from];
        n.b[from] = 0;
        if cap != 0 {
            n.hash ^= z.piece[cap as usize][to];
        }
        if t == 1 && to as i8 == old_ep && cap == 0 && (from & 7) != (to & 7) {
            let cs = if us == 0 { to - 8 } else { to + 8 };
            n.hash ^= z.piece[n.b[cs] as usize][cs];
            n.b[cs] = 0;
        }
        let placed = if m.promo != 0 { m.promo | (us << 3) } else { p };
        n.b[to] = placed;
        n.hash ^= z.piece[placed as usize][to];
        if t == 1 && (to as i32 - from as i32).abs() == 16 {
            n.ep = ((from + to) / 2) as i8;
            n.hash ^= z.ep[(n.ep & 7) as usize];
        }
        if t == 6 {
            n.ksq[us as usize] = to as u8;
            if (to as i32 - from as i32).abs() == 2 {
                let (rf, rt) = if to > from { (from + 3, from + 1) } else { (from - 4, from - 1) };
                let rk = n.b[rf];
                n.hash ^= z.piece[rk as usize][rf] ^ z.piece[rk as usize][rt];
                n.b[rf] = 0;
                n.b[rt] = rk;
            }
        }
        let oc = n.castle;
        for (s, mask) in CASTLE_MASK {
            if s == from || s == to {
                n.castle &= !mask;
            }
        }
        n.hash ^= z.castle[oc as usize] ^ z.castle[n.castle as usize];
        n.half = if t == 1 || cap != 0 { 0 } else { n.half + 1 };
        n.stm = 1 - us;
        n
    }
    fn null(&self, z: &Zob) -> Pos {
        let mut n = *self;
        n.hash ^= z.side;
        if n.ep >= 0 {
            n.hash ^= z.ep[(n.ep & 7) as usize];
        }
        n.ep = -1;
        n.stm = 1 - n.stm;
        n.half += 1;
        n
    }
    fn legal(&self, z: &Zob) -> Vec<(Move, Pos)> {
        let mut v = Vec::with_capacity(48);
        self.gen(&mut v, false);
        let us = self.stm as usize;
        v.into_iter()
            .filter_map(|m| {
                let n = self.make(m, z);
                if n.attacked(n.ksq[us] as usize, 1 - us as u8) {
                    None
                } else {
                    Some((m, n))
                }
            })
            .collect()
    }
    fn has_nonpawn(&self, c: u8) -> bool {
        self.b.iter().any(|&p| p != 0 && (p >> 3) == c && (p & 7) >= 2 && (p & 7) <= 5)
    }
    fn insufficient(&self) -> bool {
        let mut minors = 0;
        for &p in self.b.iter() {
            match p & 7 {
                1 | 4 | 5 => return false,
                2 | 3 => minors += 1,
                _ => {}
            }
        }
        minors <= 1
    }
}

fn perft(p: &Pos, d: u32, z: &Zob) -> u64 {
    let l = p.legal(z);
    if d <= 1 {
        return l.len() as u64;
    }
    l.iter().map(|(_, n)| perft(n, d - 1, z)).sum()
}

// ---------- eval ----------
const VAL: [i32; 7] = [0, 100, 320, 330, 500, 900, 0];
const PST: [[i32; 64]; 7] = [
    [0; 64],
    [
        0, 0, 0, 0, 0, 0, 0, 0, 50, 50, 50, 50, 50, 50, 50, 50, 10, 10, 20, 30, 30, 20, 10, 10, 5, 5, 10, 25, 25, 10, 5, 5, 0, 0, 0, 20, 20, 0, 0, 0, 5,
        -5, -10, 0, 0, -10, -5, 5, 5, 10, 10, -20, -20, 10, 10, 5, 0, 0, 0, 0, 0, 0, 0, 0,
    ],
    [
        -50, -40, -30, -30, -30, -30, -40, -50, -40, -20, 0, 0, 0, 0, -20, -40, -30, 0, 10, 15, 15, 10, 0, -30, -30, 5, 15, 20, 20, 15, 5, -30, -30, 0,
        15, 20, 20, 15, 0, -30, -30, 5, 10, 15, 15, 10, 5, -30, -40, -20, 0, 5, 5, 0, -20, -40, -50, -40, -30, -30, -30, -30, -40, -50,
    ],
    [
        -20, -10, -10, -10, -10, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 10, 10, 5, 0, -10, -10, 5, 5, 10, 10, 5, 5, -10, -10, 0, 10, 10,
        10, 10, 0, -10, -10, 10, 10, 10, 10, 10, 10, -10, -10, 5, 0, 0, 0, 0, 5, -10, -20, -10, -10, -10, -10, -10, -10, -20,
    ],
    [
        0, 0, 0, 0, 0, 0, 0, 0, 5, 10, 10, 10, 10, 10, 10, 5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0,
        0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, 0, 0, 0, 5, 5, 0, 0, 0,
    ],
    [
        -20, -10, -10, -5, -5, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 5, 5, 5, 0, -10, -5, 0, 5, 5, 5, 5, 0, -5, 0, 0, 5, 5, 5, 5, 0, -5,
        -10, 5, 5, 5, 5, 5, 0, -10, -10, 0, 5, 0, 0, 0, 0, -10, -20, -10, -10, -5, -5, -10, -10, -20,
    ],
    [
        -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50,
        -40, -40, -30, -20, -30, -30, -40, -40, -30, -30, -20, -10, -20, -20, -20, -20, -20, -20, -10, 20, 20, 0, 0, 0, 0, 20, 20, 20, 30, 10, 0, 0, 10,
        30, 20,
    ],
];
const KING_EG: [i32; 64] = [
    -50, -40, -30, -20, -20, -30, -40, -50, -30, -20, -10, 0, 0, -10, -20, -30, -30, -10, 20, 30, 30, 20, -10, -30, -30, -10, 30, 40, 40, 30, -10, -30,
    -30, -10, 30, 40, 40, 30, -10, -30, -30, -10, 20, 30, 30, 20, -10, -30, -30, -30, 0, 0, 0, 0, -30, -30, -50, -30, -30, -30, -30, -30, -30, -50,
];

fn eval(p: &Pos) -> i32 {
    let mut mg = 0;
    let mut eg = 0;
    let mut phase = 0;
    let mut bishops = [0; 2];
    for sq in 0..64 {
        let pc = p.b[sq];
        if pc == 0 {
            continue;
        }
        let t = (pc & 7) as usize;
        let c = pc >> 3;
        let idx = if c == 0 { sq ^ 56 } else { sq };
        let s = if c == 0 { 1 } else { -1 };
        let v = VAL[t] + PST[t][idx];
        if t == 6 {
            mg += s * PST[6][idx];
            eg += s * KING_EG[idx];
        } else {
            mg += s * v;
            eg += s * v;
        }
        match t {
            2 | 3 => phase += 1,
            4 => phase += 2,
            5 => phase += 4,
            _ => {}
        }
        if t == 3 {
            bishops[c as usize] += 1;
        }
    }
    let ph = phase.min(24);
    let mut sc = (mg * ph + eg * (24 - ph)) / 24;
    if bishops[0] >= 2 {
        sc += 30;
    }
    if bishops[1] >= 2 {
        sc -= 30;
    }
    if p.stm == 0 {
        sc + 10
    } else {
        -sc + 10
    }
}

// ---------- search ----------
const MATE: i32 = 30000;
const MAXPLY: usize = 100;

#[derive(Clone, Copy, Default)]
struct Entry {
    key: u64,
    mv: Move,
    score: i32,
    depth: i8,
    flag: u8, // 0 none,1 exact,2 lower,3 upper
}

struct Searcher {
    z: Zob,
    tt: Vec<Entry>,
    path: Vec<u64>,
    nodes: u64,
    start: Instant,
    hard_ms: u64,
    stopped: bool,
    quit: bool,
    rx: Receiver<String>,
    pending: VecDeque<String>,
    killers: [[Move; 2]; MAXPLY + 2],
    history: [[[i32; 64]; 64]; 2],
    root_best: Move,
}

impl Searcher {
    fn check_time(&mut self) {
        if self.nodes & 2047 != 0 {
            return;
        }
        while let Ok(l) = self.rx.try_recv() {
            let t = l.trim();
            if t == "stop" {
                self.stopped = true;
            } else if t == "quit" {
                self.stopped = true;
                self.quit = true;
                self.pending.push_back(l);
            } else {
                self.pending.push_back(l);
            }
        }
        if self.start.elapsed().as_millis() as u64 >= self.hard_ms {
            self.stopped = true;
        }
    }
    fn is_draw(&self, p: &Pos) -> bool {
        if p.half >= 100 || p.insufficient() {
            return true;
        }
        let n = self.path.len();
        let mut k = 2;
        while k <= p.half as usize && k <= n {
            if self.path[n - k] == p.hash {
                return true;
            }
            k += 2;
        }
        false
    }
    fn order(&self, p: &Pos, mut mv: Vec<(Move, Pos)>, ttm: Move, ply: usize) -> Vec<(Move, Pos)> {
        let mut sc: Vec<(i32, usize)> = mv
            .iter()
            .enumerate()
            .map(|(i, (m, _))| {
                let s = if *m == ttm && !ttm.is_null() {
                    1_000_000
                } else if p.is_capture(*m) {
                    let v = p.b[m.to as usize] & 7;
                    let v = if v == 0 { 1 } else { v };
                    100_000 + VAL[v as usize] * 10 - VAL[(p.b[m.from as usize] & 7) as usize] / 10 + if m.promo != 0 { 800 } else { 0 }
                } else if m.promo != 0 {
                    100_000 + VAL[m.promo as usize]
                } else if ply < MAXPLY && self.killers[ply][0] == *m {
                    90_000
                } else if ply < MAXPLY && self.killers[ply][1] == *m {
                    89_000
                } else {
                    self.history[p.stm as usize][m.from as usize][m.to as usize]
                };
                (s, i)
            })
            .collect();
        sc.sort_by(|a, b| b.0.cmp(&a.0));
        let mut out = Vec::with_capacity(mv.len());
        for (_, i) in sc {
            out.push(mv[i]);
        }
        mv.clear();
        out
    }
    fn qsearch(&mut self, p: &Pos, mut alpha: i32, beta: i32, ply: usize) -> i32 {
        self.nodes += 1;
        self.check_time();
        if self.stopped {
            return 0;
        }
        let stand = eval(p);
        if ply >= MAXPLY || stand >= beta {
            return stand;
        }
        if stand > alpha {
            alpha = stand;
        }
        let mut v = Vec::new();
        p.gen(&mut v, true);
        let us = p.stm as usize;
        let mut mv: Vec<(i32, Pos, Move)> = Vec::new();
        for m in v {
            let n = p.make(m, &self.z);
            if n.attacked(n.ksq[us] as usize, 1 - us as u8) {
                continue;
            }
            let vic = (p.b[m.to as usize] & 7) as usize;
            let s = VAL[vic] * 10 - VAL[(p.b[m.from as usize] & 7) as usize] / 10 + VAL[m.promo as usize];
            mv.push((s, n, m));
        }
        mv.sort_by(|a, b| b.0.cmp(&a.0));
        for (_, n, _) in mv {
            let s = -self.qsearch(&n, -beta, -alpha, ply + 1);
            if self.stopped {
                return 0;
            }
            if s >= beta {
                return s;
            }
            if s > alpha {
                alpha = s;
            }
        }
        alpha
    }
    fn negamax(&mut self, p: &Pos, mut depth: i32, ply: usize, mut alpha: i32, beta: i32, allow_null: bool) -> i32 {
        self.nodes += 1;
        self.check_time();
        if self.stopped {
            return 0;
        }
        if ply > 0 && self.is_draw(p) {
            return 0;
        }
        let in_check = p.in_check();
        if in_check {
            depth += 1;
        }
        if depth <= 0 || ply >= MAXPLY {
            return self.qsearch(p, alpha, beta, ply);
        }
        let idx = (p.hash as usize) & (self.tt.len() - 1);
        let e = self.tt[idx];
        let mut ttm = Move::default();
        if e.flag != 0 && e.key == p.hash {
            ttm = e.mv;
            if ply > 0 && e.depth as i32 >= depth {
                let mut s = e.score;
                if s > MATE - 200 {
                    s -= ply as i32;
                } else if s < -MATE + 200 {
                    s += ply as i32;
                }
                match e.flag {
                    1 => return s,
                    2 if s >= beta => return s,
                    3 if s <= alpha => return s,
                    _ => {}
                }
            }
        }
        let pv_node = beta - alpha > 1;
        let st = eval(p);
        if !in_check && !pv_node && depth <= 3 && st - 120 * depth >= beta && beta.abs() < MATE - 200 {
            return st;
        }
        if allow_null && !in_check && !pv_node && depth >= 3 && st >= beta && p.has_nonpawn(p.stm) {
            let n = p.null(&self.z);
            self.path.push(p.hash);
            let r = 2 + depth / 4;
            let s = -self.negamax(&n, depth - 1 - r, ply + 1, -beta, -beta + 1, false);
            self.path.pop();
            if self.stopped {
                return 0;
            }
            if s >= beta {
                return if s > MATE - 200 { beta } else { s };
            }
        }
        let moves = p.legal(&self.z);
        if moves.is_empty() {
            return if in_check { -MATE + ply as i32 } else { 0 };
        }
        let moves = self.order(p, moves, ttm, ply);
        let orig_alpha = alpha;
        let mut best = -MATE - 1;
        let mut best_mv = Move::default();
        self.path.push(p.hash);
        for (i, (m, n)) in moves.iter().enumerate() {
            let cap = p.is_capture(*m);
            let quiet = !cap && m.promo == 0;
            let s;
            if i == 0 {
                s = -self.negamax(n, depth - 1, ply + 1, -beta, -alpha, true);
            } else {
                let mut red = 0;
                if depth >= 3 && i >= 3 && quiet && !in_check {
                    red = 1 + (i >= 8) as i32 + (depth >= 6) as i32;
                }
                let mut t = -self.negamax(n, depth - 1 - red, ply + 1, -alpha - 1, -alpha, true);
                if t > alpha && (red > 0 || t < beta) {
                    t = -self.negamax(n, depth - 1, ply + 1, -beta, -alpha, true);
                }
                s = t;
            }
            if self.stopped {
                self.path.pop();
                return 0;
            }
            if s > best {
                best = s;
                best_mv = *m;
                if ply == 0 {
                    self.root_best = *m;
                }
            }
            if s > alpha {
                alpha = s;
                if alpha >= beta {
                    if quiet {
                        if self.killers[ply][0] != *m {
                            self.killers[ply][1] = self.killers[ply][0];
                            self.killers[ply][0] = *m;
                        }
                        let h = &mut self.history[p.stm as usize][m.from as usize][m.to as usize];
                        *h = (*h + depth * depth).min(80_000);
                    }
                    break;
                }
            }
        }
        self.path.pop();
        let flag = if best >= beta {
            2
        } else if best > orig_alpha {
            1
        } else {
            3
        };
        let mut s = best;
        if s > MATE - 200 {
            s += ply as i32;
        } else if s < -MATE + 200 {
            s -= ply as i32;
        }
        self.tt[idx] = Entry { key: p.hash, mv: best_mv, score: s, depth: depth as i8, flag };
        best
    }

    fn think(&mut self, p: &Pos, max_depth: i32, soft_ms: u64, hard_ms: u64, infinite: bool) -> Move {
        self.start = Instant::now();
        self.hard_ms = hard_ms;
        self.stopped = false;
        self.nodes = 0;
        self.killers = [[Move::default(); 2]; MAXPLY + 2];
        self.history = [[[0; 64]; 64]; 2];
        let legal = p.legal(&self.z);
        if legal.is_empty() {
            return Move::default();
        }
        let mut best = legal[0].0;
        if legal.len() == 1 && !infinite && max_depth >= 64 {
            return best;
        }
        for d in 1..=max_depth {
            self.root_best = Move::default();
            let s = self.negamax(p, d, 0, -MATE - 1, MATE + 1, false);
            if self.stopped {
                break;
            }
            if !self.root_best.is_null() {
                best = self.root_best;
            }
            let el = self.start.elapsed().as_millis() as u64;
            let sc = if s.abs() > MATE - 200 {
                let mt = (MATE - s.abs() + 1) / 2;
                format!("mate {}", if s > 0 { mt } else { -mt })
            } else {
                format!("cp {}", s)
            };
            println!("info depth {} score {} nodes {} time {} pv {}", d, sc, self.nodes, el, best.to_str());
            let _ = io::stdout().flush();
            if !infinite {
                if s > MATE - 200 && (MATE - s) <= d {
                    break;
                }
                if el * 2 >= soft_ms {
                    break;
                }
            }
        }
        best
    }
}

fn parse_move(p: &Pos, s: &str, z: &Zob) -> Option<Pos> {
    p.legal(z).into_iter().find(|(m, _)| m.to_str() == s).map(|(_, n)| n)
}

fn main() {
    let (tx, rx) = channel();
    std::thread::spawn(move || {
        let stdin = io::stdin();
        for l in stdin.lock().lines() {
            match l {
                Ok(l) => {
                    if tx.send(l).is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    });
    let z = make_zob();
    let startfen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
    let mut pos = Pos::from_fen(startfen, &z).unwrap();
    let mut hist: Vec<u64> = vec![pos.hash];
    let mut s = Searcher {
        z: make_zob(),
        tt: vec![Entry::default(); 1 << 21],
        path: Vec::new(),
        nodes: 0,
        start: Instant::now(),
        hard_ms: 0,
        stopped: false,
        quit: false,
        rx,
        pending: VecDeque::new(),
        killers: [[Move::default(); 2]; MAXPLY + 2],
        history: [[[0; 64]; 64]; 2],
        root_best: Move::default(),
    };
    loop {
        let line = match s.pending.pop_front() {
            Some(l) => l,
            None => match s.rx.recv() {
                Ok(l) => l,
                Err(_) => break,
            },
        };
        let tk: Vec<&str> = line.split_whitespace().collect();
        if tk.is_empty() {
            continue;
        }
        match tk[0] {
            "uci" => {
                println!("id name RustFish 1.0\nid author Claude\nuciok");
            }
            "isready" => println!("readyok"),
            "ucinewgame" => {
                for e in s.tt.iter_mut() {
                    *e = Entry::default();
                }
            }
            "position" => {
                let mut i = 1;
                let mut np = None;
                if i < tk.len() && tk[i] == "startpos" {
                    np = Pos::from_fen(startfen, &z);
                    i += 1;
                } else if i < tk.len() && tk[i] == "fen" {
                    i += 1;
                    let mut f = Vec::new();
                    while i < tk.len() && tk[i] != "moves" {
                        f.push(tk[i]);
                        i += 1;
                    }
                    np = Pos::from_fen(&f.join(" "), &z);
                }
                if let Some(mut p) = np {
                    let mut h = vec![p.hash];
                    if i < tk.len() && tk[i] == "moves" {
                        for m in &tk[i + 1..] {
                            match parse_move(&p, m, &z) {
                                Some(n) => {
                                    p = n;
                                    h.push(p.hash);
                                }
                                None => break,
                            }
                        }
                    }
                    pos = p;
                    hist = h;
                }
            }
            "go" => {
                let mut depth = 64;
                let (mut wt, mut bt, mut wi, mut bi) = (None, None, 0u64, 0u64);
                let mut movetime = None;
                let mut mtg = None;
                let mut infinite = false;
                let mut i = 1;
                let mut perft_d = None;
                while i < tk.len() {
                    let v = tk.get(i + 1).and_then(|x| x.parse::<i64>().ok());
                    match tk[i] {
                        "perft" => perft_d = v,
                        "depth" => depth = v.unwrap_or(64) as i32,
                        "movetime" => movetime = v.map(|x| x.max(1) as u64),
                        "wtime" => wt = v.map(|x| x.max(1) as u64),
                        "btime" => bt = v.map(|x| x.max(1) as u64),
                        "winc" => wi = v.unwrap_or(0).max(0) as u64,
                        "binc" => bi = v.unwrap_or(0).max(0) as u64,
                        "movestogo" => mtg = v,
                        "infinite" => {
                            infinite = true;
                            i -= 1;
                        }
                        _ => {
                            i -= 1;
                        }
                    }
                    i += 2;
                }
                if let Some(d) = perft_d {
                    let mut total = 0;
                    for (m, n) in pos.legal(&z) {
                        let c = if d <= 1 { 1 } else { perft(&n, d as u32 - 1, &z) };
                        println!("{}: {}", m.to_str(), c);
                        total += c;
                    }
                    println!("\nNodes searched: {}", total);
                    let _ = io::stdout().flush();
                    continue;
                }
                let (mut soft, mut hard) = (u64::MAX / 4, u64::MAX / 4);
                if let Some(mt) = movetime {
                    hard = mt.saturating_sub(20).max(1);
                    soft = hard;
                } else {
                    let (t, inc) = if pos.stm == 0 { (wt, wi) } else { (bt, bi) };
                    if let Some(t) = t {
                        let n = mtg.unwrap_or(30).max(1) as u64;
                        soft = (t / n + inc * 3 / 4).max(5);
                        hard = (soft * 4).min(t / 2).max(5);
                        soft = soft.min(hard);
                    } else if !infinite && depth >= 64 {
                        // no limits given: default
                        soft = 5000;
                        hard = 10000;
                    }
                }
                if infinite {
                    soft = u64::MAX / 4;
                    hard = u64::MAX / 4;
                }
                s.path = hist[..hist.len() - 1].to_vec();
                let mut m = s.think(&pos, depth.min(MAXPLY as i32 - 1), soft, hard, infinite);
                if infinite && !s.stopped && !s.quit {
                    // wait for stop
                    while let Ok(l) = s.rx.recv() {
                        let t = l.trim().to_string();
                        if t == "stop" {
                            break;
                        }
                        if t == "quit" {
                            s.quit = true;
                            break;
                        }
                        s.pending.push_back(l);
                    }
                }
                if m.is_null() {
                    if let Some((x, _)) = pos.legal(&z).first() {
                        m = *x;
                    }
                }
                if m.is_null() {
                    println!("bestmove 0000");
                } else {
                    println!("bestmove {}", m.to_str());
                }
                let _ = io::stdout().flush();
                if s.quit {
                    break;
                }
            }
            "quit" => break,
            _ => {}
        }
        let _ = io::stdout().flush();
    }
}
