use std::io::{self, BufRead, Write};
use std::sync::mpsc::{self, Receiver};
use std::time::Instant;

const MATE: i32 = 30000;

const fn rng(s: u64) -> u64 {
    let mut x = s;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    x
}
const fn gen_table<const N: usize>(seed: u64) -> [u64; N] {
    let mut t = [0u64; N];
    let mut s = seed;
    let mut i = 0;
    while i < N {
        s = rng(s);
        t[i] = s.wrapping_mul(0x2545F4914F6CDD1D);
        i += 1;
    }
    t
}
static ZP: [u64; 1024] = gen_table::<1024>(0x9E3779B97F4A7C15); // [piece*64+sq]
static ZC: [u64; 16] = gen_table::<16>(0x1234567887654321);
static ZE: [u64; 8] = gen_table::<8>(0xABCDEF0123456789);
const ZS: u64 = 0xF1357AEA2E62A9C5;

const DIRS: [(i8, i8); 8] = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)];
const KN: [(i8, i8); 8] = [(1, 2), (2, 1), (-1, 2), (-2, 1), (1, -2), (2, -1), (-1, -2), (-2, -1)];

fn cmask(sq: usize) -> u8 {
    match sq {
        0 => 13,
        4 => 12,
        7 => 14,
        56 => 7,
        60 => 3,
        63 => 11,
        _ => 15,
    }
}

struct MoveList {
    m: [u16; 256],
    n: usize,
}
impl MoveList {
    fn new() -> Self {
        MoveList { m: [0; 256], n: 0 }
    }
    #[inline]
    fn push(&mut self, from: usize, to: usize, promo: u8) {
        self.m[self.n] = from as u16 | (to as u16) << 6 | (promo as u16) << 12;
        self.n += 1;
    }
}

#[derive(Clone)]
struct Board {
    sq: [u8; 64],
    side: usize,
    castle: u8,
    ep: i8,
    half: u16,
    hash: u64,
    ksq: [usize; 2],
}

fn mv_str(m: u16) -> String {
    let f = (m & 63) as u8;
    let t = ((m >> 6) & 63) as u8;
    let mut s = String::new();
    s.push((b'a' + (f & 7)) as char);
    s.push((b'1' + (f >> 3)) as char);
    s.push((b'a' + (t & 7)) as char);
    s.push((b'1' + (t >> 3)) as char);
    match m >> 12 {
        2 => s.push('n'),
        3 => s.push('b'),
        4 => s.push('r'),
        5 => s.push('q'),
        _ => {}
    }
    s
}

impl Board {
    fn from_fen(fen: &str) -> Option<Board> {
        let mut it = fen.split_whitespace();
        let place = it.next()?;
        let side = it.next().unwrap_or("w");
        let cs = it.next().unwrap_or("-");
        let ep = it.next().unwrap_or("-");
        let half = it.next().unwrap_or("0");
        let mut b = Board { sq: [0; 64], side: 0, castle: 0, ep: -1, half: 0, hash: 0, ksq: [0; 2] };
        let (mut f, mut r) = (0usize, 7i32);
        for c in place.chars() {
            match c {
                '/' => {
                    r -= 1;
                    f = 0;
                }
                '1'..='8' => f += c as usize - '0' as usize,
                _ => {
                    if r < 0 || f > 7 {
                        return None;
                    }
                    let t = match c.to_ascii_lowercase() {
                        'p' => 1,
                        'n' => 2,
                        'b' => 3,
                        'r' => 4,
                        'q' => 5,
                        'k' => 6,
                        _ => return None,
                    };
                    let col = if c.is_ascii_uppercase() { 0 } else { 8 };
                    let s = r as usize * 8 + f;
                    b.sq[s] = t | col;
                    if t == 6 {
                        b.ksq[col as usize >> 3] = s;
                    }
                    f += 1;
                }
            }
        }
        b.side = if side == "b" { 1 } else { 0 };
        for c in cs.chars() {
            b.castle |= match c {
                'K' => 1,
                'Q' => 2,
                'k' => 4,
                'q' => 8,
                _ => 0,
            };
        }
        let e = ep.as_bytes();
        if e.len() == 2 && e[0] >= b'a' && e[0] <= b'h' && e[1] >= b'1' && e[1] <= b'8' {
            b.ep = ((e[1] - b'1') * 8 + (e[0] - b'a')) as i8;
        }
        b.half = half.parse().unwrap_or(0);
        // validate kings
        let wk = b.sq.iter().filter(|&&p| p == 6).count();
        let bk = b.sq.iter().filter(|&&p| p == 14).count();
        if wk != 1 || bk != 1 {
            return None;
        }
        b.hash = b.compute_hash();
        Some(b)
    }

    fn compute_hash(&self) -> u64 {
        let mut h = 0;
        for s in 0..64 {
            if self.sq[s] != 0 {
                h ^= ZP[self.sq[s] as usize * 64 + s];
            }
        }
        h ^= ZC[self.castle as usize];
        if self.ep >= 0 {
            h ^= ZE[(self.ep & 7) as usize];
        }
        if self.side == 1 {
            h ^= ZS;
        }
        h
    }

    fn attacked(&self, sq: usize, by: usize) -> bool {
        let f = (sq & 7) as i8;
        let r = (sq >> 3) as i8;
        let off = (by * 8) as u8;
        let pr = if by == 0 { r - 1 } else { r + 1 };
        if (0..8).contains(&pr) {
            for df in [-1i8, 1] {
                let pf = f + df;
                if (0..8).contains(&pf) && self.sq[(pr * 8 + pf) as usize] == off + 1 {
                    return true;
                }
            }
        }
        for &(df, dr) in &KN {
            let (nf, nr) = (f + df, r + dr);
            if (0..8).contains(&nf) && (0..8).contains(&nr) && self.sq[(nr * 8 + nf) as usize] == off + 2 {
                return true;
            }
        }
        for &(df, dr) in &DIRS {
            let (nf, nr) = (f + df, r + dr);
            if (0..8).contains(&nf) && (0..8).contains(&nr) && self.sq[(nr * 8 + nf) as usize] == off + 6 {
                return true;
            }
        }
        for (i, &(df, dr)) in DIRS.iter().enumerate() {
            let (mut nf, mut nr) = (f + df, r + dr);
            while (0..8).contains(&nf) && (0..8).contains(&nr) {
                let p = self.sq[(nr * 8 + nf) as usize];
                if p != 0 {
                    if p & 8 == off {
                        let t = p & 7;
                        if t == 5 || (i < 4 && t == 4) || (i >= 4 && t == 3) {
                            return true;
                        }
                    }
                    break;
                }
                nf += df;
                nr += dr;
            }
        }
        false
    }

    fn in_check(&self) -> bool {
        self.attacked(self.ksq[self.side], self.side ^ 1)
    }

    fn gen(&self, out: &mut MoveList, caps_only: bool) {
        let us = self.side;
        let col = (us * 8) as u8;
        for s in 0..64usize {
            let p = self.sq[s];
            if p == 0 || p & 8 != col {
                continue;
            }
            let t = p & 7;
            let f = (s & 7) as i8;
            let r = (s >> 3) as i8;
            match t {
                1 => {
                    let dir: i8 = if us == 0 { 1 } else { -1 };
                    let promo_r = if us == 0 { 6 } else { 1 };
                    let start_r = if us == 0 { 1 } else { 6 };
                    let to = (s as i8 + dir * 8) as usize;
                    if self.sq[to] == 0 {
                        if r == promo_r {
                            for pr in (2..=5).rev() {
                                if !caps_only || pr == 5 {
                                    out.push(s, to, pr);
                                }
                            }
                        } else if !caps_only {
                            out.push(s, to, 0);
                            if r == start_r {
                                let to2 = (s as i8 + dir * 16) as usize;
                                if self.sq[to2] == 0 {
                                    out.push(s, to2, 0);
                                }
                            }
                        }
                    }
                    for df in [-1i8, 1] {
                        if !(0..8).contains(&(f + df)) {
                            continue;
                        }
                        let to = (s as i8 + dir * 8 + df) as usize;
                        let c = self.sq[to];
                        if c != 0 && c & 8 != col {
                            if r == promo_r {
                                for pr in (2..=5).rev() {
                                    out.push(s, to, pr);
                                }
                            } else {
                                out.push(s, to, 0);
                            }
                        } else if c == 0 && self.ep == to as i8 {
                            out.push(s, to, 0);
                        }
                    }
                }
                2 | 6 => {
                    if t == 2 {
                        for &(df, dr) in &KN {
                            let (nf, nr) = (f + df, r + dr);
                            if (0..8).contains(&nf) && (0..8).contains(&nr) {
                                let to = (nr * 8 + nf) as usize;
                                let c = self.sq[to];
                                if c == 0 {
                                    if !caps_only {
                                        out.push(s, to, 0)
                                    }
                                } else if c & 8 != col {
                                    out.push(s, to, 0)
                                }
                            }
                        }
                    } else {
                        for &(df, dr) in &DIRS {
                            let (nf, nr) = (f + df, r + dr);
                            if (0..8).contains(&nf) && (0..8).contains(&nr) {
                                let to = (nr * 8 + nf) as usize;
                                let c = self.sq[to];
                                if c == 0 {
                                    if !caps_only {
                                        out.push(s, to, 0)
                                    }
                                } else if c & 8 != col {
                                    out.push(s, to, 0)
                                }
                            }
                        }
                        if !caps_only {
                            let base = if us == 0 { 0 } else { 56 };
                            if s == base + 4 {
                                let (ks, qs) = if us == 0 { (1, 2) } else { (4, 8) };
                                let en = us ^ 1;
                                let rk = col | 4;
                                if self.castle & ks != 0
                                    && self.sq[base + 7] == rk
                                    && self.sq[base + 5] == 0
                                    && self.sq[base + 6] == 0
                                    && !self.attacked(base + 4, en)
                                    && !self.attacked(base + 5, en)
                                    && !self.attacked(base + 6, en)
                                {
                                    out.push(s, base + 6, 0);
                                }
                                if self.castle & qs != 0
                                    && self.sq[base] == rk
                                    && self.sq[base + 1] == 0
                                    && self.sq[base + 2] == 0
                                    && self.sq[base + 3] == 0
                                    && !self.attacked(base + 4, en)
                                    && !self.attacked(base + 3, en)
                                    && !self.attacked(base + 2, en)
                                {
                                    out.push(s, base + 2, 0);
                                }
                            }
                        }
                    }
                }
                _ => {
                    let (a, b) = match t {
                        3 => (4, 8),
                        4 => (0, 4),
                        _ => (0, 8),
                    };
                    for &(df, dr) in &DIRS[a..b] {
                        let (mut nf, mut nr) = (f + df, r + dr);
                        while (0..8).contains(&nf) && (0..8).contains(&nr) {
                            let to = (nr * 8 + nf) as usize;
                            let c = self.sq[to];
                            if c == 0 {
                                if !caps_only {
                                    out.push(s, to, 0)
                                }
                            } else {
                                if c & 8 != col {
                                    out.push(s, to, 0)
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

    fn is_capture(&self, m: u16) -> bool {
        let from = (m & 63) as usize;
        let to = ((m >> 6) & 63) as usize;
        self.sq[to] != 0 || (self.sq[from] & 7 == 1 && (from & 7) != (to & 7))
    }

    fn make(&self, m: u16) -> Board {
        let mut b = self.clone();
        let from = (m & 63) as usize;
        let to = ((m >> 6) & 63) as usize;
        let promo = (m >> 12) as u8;
        let us = b.side;
        let col = (us * 8) as u8;
        let p = b.sq[from];
        let cap = b.sq[to];
        let t = p & 7;
        b.hash ^= ZP[p as usize * 64 + from];
        if cap != 0 {
            b.hash ^= ZP[cap as usize * 64 + to];
        }
        b.sq[from] = 0;
        let mut placed = p;
        if promo != 0 {
            placed = col | promo;
        }
        if t == 1 && cap == 0 && b.ep == to as i8 && (from & 7) != (to & 7) {
            let cs = if us == 0 { to - 8 } else { to + 8 };
            let cp = b.sq[cs];
            b.hash ^= ZP[cp as usize * 64 + cs];
            b.sq[cs] = 0;
        }
        b.sq[to] = placed;
        b.hash ^= ZP[placed as usize * 64 + to];
        if t == 6 {
            b.ksq[us] = to;
            let rk = col | 4;
            let mv_rook = |b: &mut Board, rf: usize, rt: usize| {
                b.sq[rf] = 0;
                b.sq[rt] = rk;
                b.hash ^= ZP[rk as usize * 64 + rf] ^ ZP[rk as usize * 64 + rt];
            };
            if to == from + 2 {
                mv_rook(&mut b, from + 3, from + 1);
            } else if to + 2 == from {
                mv_rook(&mut b, from - 4, from - 1);
            }
        }
        b.hash ^= ZC[b.castle as usize];
        b.castle &= cmask(from) & cmask(to);
        b.hash ^= ZC[b.castle as usize];
        if b.ep >= 0 {
            b.hash ^= ZE[(b.ep & 7) as usize];
        }
        b.ep = -1;
        if t == 1 && (to as i32 - from as i32).abs() == 16 {
            b.ep = ((from + to) / 2) as i8;
            b.hash ^= ZE[(b.ep & 7) as usize];
        }
        b.half = if t == 1 || cap != 0 { 0 } else { b.half + 1 };
        b.side ^= 1;
        b.hash ^= ZS;
        b
    }

    fn null_move(&self) -> Board {
        let mut b = self.clone();
        if b.ep >= 0 {
            b.hash ^= ZE[(b.ep & 7) as usize];
        }
        b.ep = -1;
        b.side ^= 1;
        b.hash ^= ZS;
        b
    }

    fn legal_moves(&self) -> Vec<u16> {
        let mut l = MoveList::new();
        self.gen(&mut l, false);
        let mut v = Vec::new();
        for i in 0..l.n {
            let nb = self.make(l.m[i]);
            if !nb.attacked(nb.ksq[self.side], self.side ^ 1) {
                v.push(l.m[i]);
            }
        }
        v
    }

    fn perft(&self, depth: u32) -> u64 {
        if depth == 0 {
            return 1;
        }
        let mut l = MoveList::new();
        self.gen(&mut l, false);
        let mut n = 0;
        for i in 0..l.n {
            let nb = self.make(l.m[i]);
            if nb.attacked(nb.ksq[self.side], self.side ^ 1) {
                continue;
            }
            n += if depth == 1 { 1 } else { nb.perft(depth - 1) };
        }
        n
    }

    fn eval(&self) -> i32 {
        let mut mg = [0i32; 2];
        let mut eg = [0i32; 2];
        let mut phase = 0;
        let mut cnt = [[0u8; 7]; 2];
        for s in 0..64usize {
            let p = self.sq[s];
            if p == 0 {
                continue;
            }
            let t = (p & 7) as usize;
            let c = (p >> 3) as usize;
            cnt[c][t] += 1;
            let idx = if c == 0 { s ^ 56 } else { s };
            let v = [0, 100, 320, 330, 500, 900, 0][t];
            if t == 6 {
                mg[c] += PST[5 * 64 + idx] as i32;
                eg[c] += PST[6 * 64 + idx] as i32;
            } else {
                let x = v + PST[(t - 1) * 64 + idx] as i32;
                mg[c] += x;
                eg[c] += x;
            }
            phase += [0, 0, 1, 1, 2, 4, 0][t];
        }
        // insufficient material
        if cnt[0][1] + cnt[1][1] + cnt[0][4] + cnt[1][4] + cnt[0][5] + cnt[1][5] == 0 {
            let minors = cnt[0][2] + cnt[0][3] + cnt[1][2] + cnt[1][3];
            if minors <= 1 {
                return 0;
            }
        }
        for c in 0..2 {
            if cnt[c][3] >= 2 {
                mg[c] += 30;
                eg[c] += 40;
            }
        }
        let ph = phase.min(24);
        let w = (mg[0] * ph + eg[0] * (24 - ph)) / 24;
        let bl = (mg[1] * ph + eg[1] * (24 - ph)) / 24;
        let sc = w - bl + 10;
        if self.side == 0 {
            sc
        } else {
            -sc + 20 - 0
        }
        .min(MATE - 1000)
    }

    fn has_pieces(&self) -> bool {
        let col = (self.side * 8) as u8;
        self.sq.iter().any(|&p| p != 0 && p & 8 == col && (p & 7) >= 2 && (p & 7) <= 5)
    }
}

#[rustfmt::skip]
static PST: [i16; 448] = [
// pawn
0,0,0,0,0,0,0,0, 50,50,50,50,50,50,50,50, 10,10,20,30,30,20,10,10, 5,5,10,25,25,10,5,5,
0,0,0,20,20,0,0,0, 5,-5,-10,0,0,-10,-5,5, 5,10,10,-20,-20,10,10,5, 0,0,0,0,0,0,0,0,
// knight
-50,-40,-30,-30,-30,-30,-40,-50, -40,-20,0,0,0,0,-20,-40, -30,0,10,15,15,10,0,-30, -30,5,15,20,20,15,5,-30,
-30,0,15,20,20,15,0,-30, -30,5,10,15,15,10,5,-30, -40,-20,0,5,5,0,-20,-40, -50,-40,-30,-30,-30,-30,-40,-50,
// bishop
-20,-10,-10,-10,-10,-10,-10,-20, -10,0,0,0,0,0,0,-10, -10,0,5,10,10,5,0,-10, -10,5,5,10,10,5,5,-10,
-10,0,10,10,10,10,0,-10, -10,10,10,10,10,10,10,-10, -10,5,0,0,0,0,5,-10, -20,-10,-10,-10,-10,-10,-10,-20,
// rook
0,0,0,0,0,0,0,0, 5,10,10,10,10,10,10,5, -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5,
-5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5, 0,0,0,5,5,0,0,0,
// queen
-20,-10,-10,-5,-5,-10,-10,-20, -10,0,0,0,0,0,0,-10, -10,0,5,5,5,5,0,-10, -5,0,5,5,5,5,0,-5,
0,0,5,5,5,5,0,-5, -10,5,5,5,5,5,0,-10, -10,0,5,0,0,0,0,-10, -20,-10,-10,-5,-5,-10,-10,-20,
// king mid
-30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30,
-20,-30,-30,-40,-40,-30,-30,-20, -10,-20,-20,-20,-20,-20,-20,-10, 20,20,0,0,0,0,20,20, 20,30,10,0,0,10,30,20,
// king end
-50,-40,-30,-20,-20,-30,-40,-50, -30,-20,-10,0,0,-10,-20,-30, -30,-10,20,30,30,20,-10,-30, -30,-10,30,40,40,30,-10,-30,
-30,-10,30,40,40,30,-10,-30, -30,-10,20,30,30,20,-10,-30, -30,-30,0,0,0,0,-30,-30, -50,-30,-30,-30,-30,-30,-30,-50,
];

#[derive(Clone, Copy, Default)]
struct TTE {
    key: u64,
    mv: u16,
    score: i32,
    depth: i8,
    flag: u8, // 1 exact, 2 lower, 3 upper
}

const TT_SIZE: usize = 1 << 21;

struct Engine {
    board: Board,
    hist: Vec<u64>,
    tt: Vec<TTE>,
    killers: [[u16; 2]; 128],
    history: Vec<i32>,
    nodes: u64,
    start: Instant,
    hard_ms: Option<u128>,
    stop: bool,
    quit: bool,
    rx: Receiver<String>,
    pending: Vec<String>,
    root_best: u16,
}

impl Engine {
    fn poll(&mut self) {
        if let Some(h) = self.hard_ms {
            if self.start.elapsed().as_millis() >= h {
                self.stop = true;
            }
        }
        while let Ok(l) = self.rx.try_recv() {
            let t = l.trim();
            if t == "stop" {
                self.stop = true;
            } else if t == "quit" {
                self.stop = true;
                self.quit = true;
            } else if t == "isready" {
                println!("readyok");
                let _ = io::stdout().flush();
            } else {
                self.pending.push(l);
            }
        }
    }

    fn qsearch(&mut self, b: &Board, mut alpha: i32, beta: i32, ply: usize) -> i32 {
        self.nodes += 1;
        if self.nodes & 2047 == 0 {
            self.poll();
        }
        if self.stop {
            return 0;
        }
        let stand = b.eval();
        if ply >= 100 {
            return stand;
        }
        if stand >= beta {
            return stand;
        }
        if stand > alpha {
            alpha = stand;
        }
        let mut l = MoveList::new();
        b.gen(&mut l, true);
        let mut sc = [0i32; 256];
        for i in 0..l.n {
            let m = l.m[i];
            let victim = b.sq[((m >> 6) & 63) as usize] & 7;
            let vv = if victim == 0 { 1 } else { victim as i32 };
            sc[i] = vv * 10 - (b.sq[(m & 63) as usize] & 7) as i32 + if m >> 12 != 0 { 50 } else { 0 };
        }
        let mut best = stand;
        for i in 0..l.n {
            let mut bi = i;
            for j in i + 1..l.n {
                if sc[j] > sc[bi] {
                    bi = j;
                }
            }
            l.m.swap(i, bi);
            sc.swap(i, bi);
            let m = l.m[i];
            // delta pruning
            let victim = b.sq[((m >> 6) & 63) as usize] & 7;
            let vval = [100, 100, 320, 330, 500, 900, 0][victim as usize];
            if stand + vval + 200 < alpha && m >> 12 == 0 {
                continue;
            }
            let nb = b.make(m);
            if nb.attacked(nb.ksq[b.side], b.side ^ 1) {
                continue;
            }
            let s = -self.qsearch(&nb, -beta, -alpha, ply + 1);
            if self.stop {
                return 0;
            }
            if s > best {
                best = s;
                if s > alpha {
                    alpha = s;
                    if s >= beta {
                        break;
                    }
                }
            }
        }
        best
    }

    fn negamax(&mut self, b: &Board, mut depth: i32, ply: usize, mut alpha: i32, beta: i32, can_null: bool) -> i32 {
        if self.stop {
            return 0;
        }
        self.nodes += 1;
        if self.nodes & 2047 == 0 {
            self.poll();
            if self.stop {
                return 0;
            }
        }
        if ply > 0 {
            if b.half >= 100 {
                return 0;
            }
            let n = self.hist.len();
            let lim = (b.half as usize).min(n);
            let mut k = 2;
            while k <= lim {
                if self.hist[n - k] == b.hash {
                    return 0;
                }
                k += 2;
            }
        }
        if ply >= 120 {
            return b.eval();
        }
        let in_check = b.in_check();
        if in_check {
            depth += 1;
        }
        if depth <= 0 {
            return self.qsearch(b, alpha, beta, ply);
        }
        let pv_node = beta - alpha > 1;
        let idx = (b.hash as usize) & (TT_SIZE - 1);
        let e = self.tt[idx];
        let mut tt_move = 0u16;
        if e.key == b.hash && e.flag != 0 {
            tt_move = e.mv;
            if ply > 0 && e.depth as i32 >= depth && !pv_node {
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
        let static_eval = if in_check { -MATE } else { b.eval() };
        if !pv_node && !in_check && ply > 0 {
            if depth <= 3 && static_eval - 120 * depth >= beta && beta.abs() < MATE - 200 {
                return static_eval;
            }
            if can_null && depth >= 3 && static_eval >= beta && b.has_pieces() {
                let nb = b.null_move();
                let r = 2 + depth / 4;
                self.hist.push(b.hash);
                let s = -self.negamax(&nb, depth - 1 - r, ply + 1, -beta, -beta + 1, false);
                self.hist.pop();
                if self.stop {
                    return 0;
                }
                if s >= beta {
                    return if s > MATE - 200 { beta } else { s };
                }
            }
        }
        let mut l = MoveList::new();
        b.gen(&mut l, false);
        let mut sc = [0i32; 256];
        for i in 0..l.n {
            let m = l.m[i];
            sc[i] = if m == tt_move {
                10_000_000
            } else if b.is_capture(m) {
                let v = b.sq[((m >> 6) & 63) as usize] & 7;
                let v = if v == 0 { 1 } else { v as i32 };
                1_000_000 + v * 10 - (b.sq[(m & 63) as usize] & 7) as i32 + if m >> 12 == 5 { 500 } else { 0 }
            } else if m >> 12 != 0 {
                if m >> 12 == 5 { 900_000 } else { -1000 }
            } else if m == self.killers[ply][0] {
                800_000
            } else if m == self.killers[ply][1] {
                700_000
            } else {
                self.history[(m & 4095) as usize]
            };
        }
        let orig_alpha = alpha;
        let mut best = -MATE - 1;
        let mut best_move = 0u16;
        let mut legal = 0;
        for i in 0..l.n {
            let mut bi = i;
            for j in i + 1..l.n {
                if sc[j] > sc[bi] {
                    bi = j;
                }
            }
            l.m.swap(i, bi);
            sc.swap(i, bi);
            let m = l.m[i];
            let nb = b.make(m);
            if nb.attacked(nb.ksq[b.side], b.side ^ 1) {
                continue;
            }
            legal += 1;
            let quiet = !b.is_capture(m) && m >> 12 == 0;
            self.hist.push(b.hash);
            let gives_check = nb.in_check();
            let mut s;
            if legal == 1 {
                s = -self.negamax(&nb, depth - 1, ply + 1, -beta, -alpha, true);
            } else {
                let mut r = 0;
                if depth >= 3 && legal > 3 && quiet && !in_check && !gives_check {
                    r = 1 + (legal > 8) as i32 + (depth > 6) as i32;
                }
                s = -self.negamax(&nb, depth - 1 - r, ply + 1, -alpha - 1, -alpha, true);
                if s > alpha && r > 0 {
                    s = -self.negamax(&nb, depth - 1, ply + 1, -alpha - 1, -alpha, true);
                }
                if s > alpha && s < beta {
                    s = -self.negamax(&nb, depth - 1, ply + 1, -beta, -alpha, true);
                }
            }
            self.hist.pop();
            if self.stop {
                return 0;
            }
            if s > best {
                best = s;
                best_move = m;
                if s > alpha {
                    alpha = s;
                    if ply == 0 {
                        self.root_best = m;
                    }
                    if s >= beta {
                        if quiet {
                            if self.killers[ply][0] != m {
                                self.killers[ply][1] = self.killers[ply][0];
                                self.killers[ply][0] = m;
                            }
                            let h = &mut self.history[(m & 4095) as usize];
                            *h = (*h + depth * depth).min(500_000);
                        }
                        break;
                    }
                }
            }
        }
        if legal == 0 {
            return if in_check { -MATE + ply as i32 } else { 0 };
        }
        let flag = if best >= beta {
            2
        } else if best > orig_alpha {
            1
        } else {
            3
        };
        let mut ss = best;
        if ss > MATE - 200 {
            ss += ply as i32;
        } else if ss < -MATE + 200 {
            ss -= ply as i32;
        }
        self.tt[idx] = TTE { key: b.hash, mv: best_move, score: ss, depth: depth as i8, flag };
        best
    }

    fn go(&mut self, args: &[&str]) {
        let mut depth = 64;
        let mut movetime: Option<u128> = None;
        let mut wtime: Option<i64> = None;
        let mut btime: Option<i64> = None;
        let (mut winc, mut binc) = (0i64, 0i64);
        let mut infinite = false;
        let mut movestogo = 30i64;
        let mut i = 0;
        while i < args.len() {
            let v = args.get(i + 1).and_then(|x| x.parse::<i64>().ok());
            match args[i] {
                "perft" => {
                    let d = v.unwrap_or(1) as u32;
                    let b = self.board.clone();
                    let mut total = 0;
                    for m in b.legal_moves() {
                        let n = if d <= 1 { 1 } else { b.make(m).perft(d - 1) };
                        println!("{}: {}", mv_str(m), n);
                        total += n;
                    }
                    println!("Nodes searched: {}", total);
                    let _ = io::stdout().flush();
                    return;
                }
                "depth" => depth = v.unwrap_or(64) as i32,
                "movetime" => movetime = v.map(|x| x.max(1) as u128),
                "wtime" => wtime = v,
                "btime" => btime = v,
                "winc" => winc = v.unwrap_or(0),
                "binc" => binc = v.unwrap_or(0),
                "movestogo" => movestogo = v.unwrap_or(30).max(1),
                "infinite" => infinite = true,
                _ => {}
            }
            i += 1;
        }
        let b = self.board.clone();
        let (mut soft, mut hard): (Option<u128>, Option<u128>) = (None, None);
        if let Some(mt) = movetime {
            let h = mt.saturating_sub(20).max(1);
            hard = Some(h);
            soft = Some(h);
        } else if !infinite && (wtime.is_some() || btime.is_some()) {
            let (t, inc) = if b.side == 0 { (wtime.unwrap_or(0), winc) } else { (btime.unwrap_or(0), binc) };
            let t = t.max(1);
            let alloc = (t / movestogo.min(30) + inc * 3 / 4).min(t * 2 / 5).max(1);
            let h = (alloc * 3).min(t / 2).max(1).min((t - 30).max(1));
            soft = Some(alloc as u128);
            hard = Some(h as u128);
        }
        self.hard_ms = hard;
        self.start = Instant::now();
        self.stop = false;
        self.nodes = 0;
        self.killers = [[0; 2]; 128];
        for h in self.history.iter_mut() {
            *h /= 2;
        }
        let legal = b.legal_moves();
        let mut best = legal.first().copied().unwrap_or(0);
        if legal.len() > 1 || infinite {
            for d in 1..=depth {
                self.root_best = 0;
                let s = self.negamax(&b, d, 0, -MATE - 10, MATE + 10, true);
                if self.stop {
                    // keep partial result only if it found something at root and it's a legitimately improved move
                    if self.root_best != 0 && d > 1 {
                        best = self.root_best;
                    }
                    break;
                }
                if self.root_best != 0 {
                    best = self.root_best;
                }
                let el = self.start.elapsed().as_millis();
                let sstr = if s.abs() > MATE - 200 {
                    let n = (MATE - s.abs() + 1) / 2;
                    format!("mate {}", if s > 0 { n } else { -n })
                } else {
                    format!("cp {}", s)
                };
                println!("info depth {} score {} nodes {} time {} pv {}", d, sstr, self.nodes, el, mv_str(best));
                let _ = io::stdout().flush();
                if s > MATE - 200 && !infinite && d >= MATE - s {
                    break;
                }
                if let Some(sf) = soft {
                    if el * 10 >= sf * 5 {
                        break;
                    }
                }
            }
        }
        if infinite && !self.stop {
            // wait for stop
            while !self.stop {
                match self.rx.recv() {
                    Ok(l) => {
                        let t = l.trim();
                        if t == "stop" {
                            self.stop = true;
                        } else if t == "quit" {
                            self.stop = true;
                            self.quit = true;
                        } else {
                            self.pending.push(l);
                        }
                    }
                    Err(_) => break,
                }
            }
        }
        self.hard_ms = None;
        if best == 0 {
            println!("bestmove 0000");
        } else {
            println!("bestmove {}", mv_str(best));
        }
        let _ = io::stdout().flush();
    }

    fn set_position(&mut self, toks: &[&str]) {
        let mut i = 1;
        let mut b = if toks.get(1) == Some(&"fen") {
            let mut fen = Vec::new();
            i = 2;
            while i < toks.len() && toks[i] != "moves" {
                fen.push(toks[i]);
                i += 1;
            }
            match Board::from_fen(&fen.join(" ")) {
                Some(b) => b,
                None => return,
            }
        } else {
            i = 2;
            Board::from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1").unwrap()
        };
        let mut hist = Vec::new();
        if toks.get(i) == Some(&"moves") {
            for ms in &toks[i + 1..] {
                let found = b.legal_moves().into_iter().find(|&m| mv_str(m) == *ms);
                match found {
                    Some(m) => {
                        hist.push(b.hash);
                        b = b.make(m);
                    }
                    None => break,
                }
            }
        }
        self.board = b;
        self.hist = hist;
    }
}

fn main() {
    let (tx, rx) = mpsc::channel::<String>();
    std::thread::spawn(move || {
        let stdin = io::stdin();
        for line in stdin.lock().lines() {
            match line {
                Ok(l) => {
                    if tx.send(l).is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
    });
    let mut e = Engine {
        board: Board::from_fen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1").unwrap(),
        hist: Vec::new(),
        tt: vec![TTE::default(); TT_SIZE],
        killers: [[0; 2]; 128],
        history: vec![0; 4096],
        nodes: 0,
        start: Instant::now(),
        hard_ms: None,
        stop: false,
        quit: false,
        rx,
        pending: Vec::new(),
        root_best: 0,
    };
    loop {
        let line = if !e.pending.is_empty() {
            e.pending.remove(0)
        } else {
            match e.rx.recv() {
                Ok(l) => l,
                Err(_) => break,
            }
        };
        let toks: Vec<&str> = line.split_whitespace().collect();
        if toks.is_empty() {
            continue;
        }
        match toks[0] {
            "uci" => {
                println!("id name RustyUCI 1.0");
                println!("id author Claude");
                println!("uciok");
            }
            "isready" => println!("readyok"),
            "ucinewgame" => {
                for t in e.tt.iter_mut() {
                    *t = TTE::default();
                }
                e.history.iter_mut().for_each(|h| *h = 0);
            }
            "position" => e.set_position(&toks),
            "go" => {
                e.go(&toks[1..]);
                if e.quit {
                    break;
                }
            }
            "quit" => break,
            _ => {}
        }
        let _ = io::stdout().flush();
    }
}
