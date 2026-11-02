use std::io::{self, BufRead, Write};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc;
use std::sync::OnceLock;
use std::time::{Duration, Instant};

static STOP: AtomicBool = AtomicBool::new(false);

const P: u8 = 1;
const N: u8 = 2;
const B: u8 = 3;
const R: u8 = 4;
const Q: u8 = 5;
const K: u8 = 6;
const MATE: i32 = 30000;
const MAXPLY: usize = 100;
const VAL: [i32; 7] = [0, 100, 320, 330, 500, 900, 0];

struct Tables {
    zp: [[u64; 64]; 16],
    zc: [u64; 16],
    ze: [u64; 8],
    zs: u64,
    knight: Vec<Vec<usize>>,
    king: Vec<Vec<usize>>,
}

fn tb() -> &'static Tables {
    static T: OnceLock<Tables> = OnceLock::new();
    T.get_or_init(|| {
        let mut s: u64 = 0x9E3779B97F4A7C15;
        let mut rnd = || {
            s ^= s << 13;
            s ^= s >> 7;
            s ^= s << 17;
            s
        };
        let mut zp = [[0u64; 64]; 16];
        for a in zp.iter_mut() {
            for x in a.iter_mut() {
                *x = rnd();
            }
        }
        let mut zc = [0u64; 16];
        for x in zc.iter_mut() {
            *x = rnd();
        }
        let mut ze = [0u64; 8];
        for x in ze.iter_mut() {
            *x = rnd();
        }
        let zs = rnd();
        let gen = |d: &[(i32, i32)]| {
            let mut v = vec![];
            for sq in 0..64i32 {
                let mut l = vec![];
                for &(df, dr) in d {
                    let f = sq % 8 + df;
                    let r = sq / 8 + dr;
                    if (0..8).contains(&f) && (0..8).contains(&r) {
                        l.push((r * 8 + f) as usize);
                    }
                }
                v.push(l);
            }
            v
        };
        let knight = gen(&[(1, 2), (2, 1), (-1, 2), (-2, 1), (1, -2), (2, -1), (-1, -2), (-2, -1)]);
        let king = gen(&[(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]);
        Tables { zp, zc, ze, zs, knight, king }
    })
}

const DIRS: [(i32, i32); 8] = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)];

fn mv(f: usize, t: usize, p: u8) -> u16 {
    (f as u16) | ((t as u16) << 6) | ((p as u16) << 12)
}
fn mstr(m: u16) -> String {
    let f = (m & 63) as u8;
    let t = ((m >> 6) & 63) as u8;
    let mut s = String::new();
    s.push((b'a' + f % 8) as char);
    s.push((b'1' + f / 8) as char);
    s.push((b'a' + t % 8) as char);
    s.push((b'1' + t / 8) as char);
    match m >> 12 {
        2 => s.push('n'),
        3 => s.push('b'),
        4 => s.push('r'),
        5 => s.push('q'),
        _ => {}
    }
    s
}

#[derive(Clone)]
struct Pos {
    b: [u8; 64],
    side: usize,
    castle: u8,
    ep: i8,
    half: u32,
    hash: u64,
    ksq: [usize; 2],
}

const CMASK: [(usize, u8); 6] = [(0, 2), (4, 3), (7, 1), (56, 8), (60, 12), (63, 4)];

impl Pos {
    fn from_fen(fen: &str) -> Option<Pos> {
        let mut it = fen.split_whitespace();
        let board = it.next()?;
        let mut p = Pos { b: [0; 64], side: 0, castle: 0, ep: -1, half: 0, hash: 0, ksq: [0; 2] };
        let mut r = 7i32;
        let mut f = 0i32;
        for c in board.chars() {
            match c {
                '/' => {
                    r -= 1;
                    f = 0;
                }
                '1'..='8' => f += c as i32 - '0' as i32,
                _ => {
                    let col = if c.is_ascii_uppercase() { 0 } else { 8 };
                    let t = match c.to_ascii_lowercase() {
                        'p' => P,
                        'n' => N,
                        'b' => B,
                        'r' => R,
                        'q' => Q,
                        'k' => K,
                        _ => return None,
                    };
                    if !(0..8).contains(&r) || !(0..8).contains(&f) {
                        return None;
                    }
                    p.b[(r * 8 + f) as usize] = t | col;
                    f += 1;
                }
            }
        }
        p.side = if it.next().unwrap_or("w") == "b" { 1 } else { 0 };
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
        p.half = it.next().and_then(|x| x.parse().ok()).unwrap_or(0);
        let mut kc = [0; 2];
        for sq in 0..64 {
            if p.b[sq] & 7 == K {
                p.ksq[(p.b[sq] >> 3) as usize] = sq;
                kc[(p.b[sq] >> 3) as usize] += 1;
            }
        }
        if kc != [1, 1] {
            return None;
        }
        p.hash = p.compute_hash();
        Some(p)
    }

    fn compute_hash(&self) -> u64 {
        let t = tb();
        let mut h = 0;
        for sq in 0..64 {
            if self.b[sq] != 0 {
                h ^= t.zp[self.b[sq] as usize][sq];
            }
        }
        h ^= t.zc[self.castle as usize];
        if self.ep >= 0 {
            h ^= t.ze[(self.ep & 7) as usize];
        }
        if self.side == 1 {
            h ^= t.zs;
        }
        h
    }

    fn attacked(&self, sq: usize, by: usize) -> bool {
        let t = tb();
        let f = (sq & 7) as i32;
        let r = (sq >> 3) as i32;
        let c = (by as u8) << 3;
        let pr = if by == 0 { r - 1 } else { r + 1 };
        if (0..8).contains(&pr) {
            for df in [-1, 1] {
                let pf = f + df;
                if (0..8).contains(&pf) && self.b[(pr * 8 + pf) as usize] == P | c {
                    return true;
                }
            }
        }
        for &s in &t.knight[sq] {
            if self.b[s] == N | c {
                return true;
            }
        }
        for &s in &t.king[sq] {
            if self.b[s] == K | c {
                return true;
            }
        }
        for (i, &(df, dr)) in DIRS.iter().enumerate() {
            let (mut cf, mut cr) = (f + df, r + dr);
            while (0..8).contains(&cf) && (0..8).contains(&cr) {
                let p = self.b[(cr * 8 + cf) as usize];
                if p != 0 {
                    if p >> 3 == by as u8 {
                        let ty = p & 7;
                        if ty == Q || (i < 4 && ty == R) || (i >= 4 && ty == B) {
                            return true;
                        }
                    }
                    break;
                }
                cf += df;
                cr += dr;
            }
        }
        false
    }

    fn in_check(&self) -> bool {
        self.attacked(self.ksq[self.side], self.side ^ 1)
    }

    fn gen(&self, out: &mut Vec<u16>, caps: bool) {
        let t = tb();
        let us = self.side;
        let them = (us ^ 1) as u8;
        for sq in 0..64usize {
            let pc = self.b[sq];
            if pc == 0 || (pc >> 3) as usize != us {
                continue;
            }
            let ty = pc & 7;
            let f = (sq & 7) as i32;
            let r = (sq >> 3) as i32;
            match ty {
                P => {
                    let dir: i32 = if us == 0 { 8 } else { -8 };
                    let start = if us == 0 { 1 } else { 6 };
                    let prom = if us == 0 { 6 } else { 1 };
                    let one = (sq as i32 + dir) as usize;
                    if self.b[one] == 0 {
                        if r == prom {
                            for p in (2..=5).rev() {
                                if !caps || p == 5 {
                                    out.push(mv(sq, one, p));
                                }
                            }
                        } else if !caps {
                            out.push(mv(sq, one, 0));
                            if r == start {
                                let two = (sq as i32 + 2 * dir) as usize;
                                if self.b[two] == 0 {
                                    out.push(mv(sq, two, 0));
                                }
                            }
                        }
                    }
                    for df in [-1i32, 1] {
                        if !(0..8).contains(&(f + df)) {
                            continue;
                        }
                        let to = (sq as i32 + dir + df) as usize;
                        let tp = self.b[to];
                        if (tp != 0 && tp >> 3 == them) || (tp == 0 && to as i8 == self.ep) {
                            if r == prom {
                                for p in (2..=5).rev() {
                                    out.push(mv(sq, to, p));
                                }
                            } else {
                                out.push(mv(sq, to, 0));
                            }
                        }
                    }
                }
                N | K => {
                    let l = if ty == N { &t.knight[sq] } else { &t.king[sq] };
                    for &to in l {
                        let tp = self.b[to];
                        if tp == 0 {
                            if !caps {
                                out.push(mv(sq, to, 0));
                            }
                        } else if tp >> 3 == them {
                            out.push(mv(sq, to, 0));
                        }
                    }
                    if ty == K && !caps {
                        let base = if us == 0 { 0 } else { 56 };
                        if sq == base + 4 && !self.attacked(sq, them as usize) {
                            let rk = R | (us as u8) << 3;
                            let (ks, qs) = if us == 0 { (1, 2) } else { (4, 8) };
                            if self.castle & ks != 0
                                && self.b[base + 5] == 0
                                && self.b[base + 6] == 0
                                && self.b[base + 7] == rk
                                && !self.attacked(base + 5, them as usize)
                                && !self.attacked(base + 6, them as usize)
                            {
                                out.push(mv(sq, base + 6, 0));
                            }
                            if self.castle & qs != 0
                                && self.b[base + 1] == 0
                                && self.b[base + 2] == 0
                                && self.b[base + 3] == 0
                                && self.b[base] == rk
                                && !self.attacked(base + 3, them as usize)
                                && !self.attacked(base + 2, them as usize)
                            {
                                out.push(mv(sq, base + 2, 0));
                            }
                        }
                    }
                }
                _ => {
                    let (s, e) = match ty {
                        B => (4, 8),
                        R => (0, 4),
                        _ => (0, 8),
                    };
                    for &(df, dr) in &DIRS[s..e] {
                        let (mut cf, mut cr) = (f + df, r + dr);
                        while (0..8).contains(&cf) && (0..8).contains(&cr) {
                            let to = (cr * 8 + cf) as usize;
                            let tp = self.b[to];
                            if tp == 0 {
                                if !caps {
                                    out.push(mv(sq, to, 0));
                                }
                            } else {
                                if tp >> 3 == them {
                                    out.push(mv(sq, to, 0));
                                }
                                break;
                            }
                            cf += df;
                            cr += dr;
                        }
                    }
                }
            }
        }
    }

    fn make(&self, m: u16) -> Pos {
        let t = tb();
        let mut p = self.clone();
        let from = (m & 63) as usize;
        let to = ((m >> 6) & 63) as usize;
        let promo = (m >> 12) as u8;
        let pc = p.b[from];
        let us = p.side;
        let ty = pc & 7;
        let cap = p.b[to];
        p.hash ^= t.zp[pc as usize][from];
        if cap != 0 {
            p.hash ^= t.zp[cap as usize][to];
        }
        p.b[from] = 0;
        let oldep = p.ep;
        if oldep >= 0 {
            p.hash ^= t.ze[(oldep & 7) as usize];
        }
        p.ep = -1;
        let mut placed = pc;
        if ty == P {
            if to as i8 == oldep && cap == 0 && (from & 7) != (to & 7) {
                let csq = if us == 0 { to - 8 } else { to + 8 };
                let cp = p.b[csq];
                p.hash ^= t.zp[cp as usize][csq];
                p.b[csq] = 0;
            }
            if (to as i32 - from as i32).abs() == 16 {
                p.ep = ((from + to) / 2) as i8;
                p.hash ^= t.ze[to & 7];
            }
            if promo != 0 {
                placed = promo | (us as u8) << 3;
            }
        }
        if ty == K {
            p.ksq[us] = to;
            if (to as i32 - from as i32).abs() == 2 {
                let (rf, rt) = if to > from { (to + 1, to - 1) } else { (to - 2, to + 1) };
                let rk = p.b[rf];
                p.hash ^= t.zp[rk as usize][rf] ^ t.zp[rk as usize][rt];
                p.b[rf] = 0;
                p.b[rt] = rk;
            }
        }
        p.b[to] = placed;
        p.hash ^= t.zp[placed as usize][to];
        let old = p.castle;
        for &(sq, mask) in &CMASK {
            if sq == from || sq == to {
                p.castle &= !mask;
            }
        }
        p.hash ^= t.zc[old as usize] ^ t.zc[p.castle as usize];
        p.half = if ty == P || cap != 0 { 0 } else { p.half + 1 };
        p.side ^= 1;
        p.hash ^= t.zs;
        p
    }

    fn null(&self) -> Pos {
        let t = tb();
        let mut p = self.clone();
        if p.ep >= 0 {
            p.hash ^= t.ze[(p.ep & 7) as usize];
        }
        p.ep = -1;
        p.side ^= 1;
        p.half = 0;
        p.hash ^= t.zs;
        p
    }

    fn legal(&self) -> Vec<(u16, Pos)> {
        let mut v = vec![];
        self.gen(&mut v, false);
        let us = self.side;
        v.into_iter()
            .filter_map(|m| {
                let p = self.make(m);
                if p.attacked(p.ksq[us], us ^ 1) {
                    None
                } else {
                    Some((m, p))
                }
            })
            .collect()
    }

    fn is_cap(&self, m: u16) -> bool {
        let from = (m & 63) as usize;
        let to = ((m >> 6) & 63) as usize;
        self.b[to] != 0 || (self.b[from] & 7 == P && (from & 7) != (to & 7))
    }

    fn eval(&self) -> i32 {
        let mut sc = [0i32; 2];
        let mut phase = 0;
        let mut bish = [0; 2];
        const PB: [i32; 8] = [0, 0, 5, 10, 20, 35, 60, 0];
        let cdist = |sq: usize| -> i32 {
            let f = (sq & 7) as i32;
            let r = (sq >> 3) as i32;
            f.min(7 - f) + r.min(7 - r)
        };
        for sq in 0..64 {
            let pc = self.b[sq];
            if pc == 0 {
                continue;
            }
            let c = (pc >> 3) as usize;
            let ty = pc & 7;
            let f = (sq & 7) as i32;
            let r = (sq >> 3) as i32;
            let rr = if c == 0 { r } else { 7 - r } as usize;
            let cd = cdist(sq);
            match ty {
                P => {
                    sc[c] += 100 + PB[rr] + if f == 3 || f == 4 { 5 } else { 0 };
                }
                N => {
                    sc[c] += 320 + cd * 6;
                    phase += 1;
                }
                B => {
                    sc[c] += 330 + cd * 3;
                    phase += 1;
                    bish[c] += 1;
                }
                R => {
                    sc[c] += 500 + if rr == 6 { 15 } else { 0 };
                    phase += 2;
                }
                Q => {
                    sc[c] += 900 + cd;
                    phase += 4;
                }
                _ => {}
            }
        }
        let phase = phase.min(24);
        for c in 0..2 {
            if bish[c] >= 2 {
                sc[c] += 30;
            }
            let ks = self.ksq[c];
            let rr = if c == 0 { ks >> 3 } else { 7 - (ks >> 3) } as i32;
            let f = (ks & 7) as i32;
            let mg = -rr * 12 + if rr == 0 && (f <= 2 || f >= 6) { 15 } else { 0 };
            let eg = cdist(ks) * 8;
            sc[c] += (mg * phase + eg * (24 - phase)) / 24;
        }
        let md = sc[0] - sc[1];
        if phase <= 8 && md.abs() >= 300 {
            let (w, l) = if md > 0 { (0, 1) } else { (1, 0) };
            let lk = self.ksq[l];
            let wk = self.ksq[w];
            let man = ((lk & 7) as i32 - (wk & 7) as i32).abs() + ((lk >> 3) as i32 - (wk >> 3) as i32).abs();
            sc[w] += (6 - cdist(lk)) * 10 + (14 - man) * 4;
        }
        let s = sc[0] - sc[1];
        (if self.side == 0 { s } else { -s }) + 10
    }

    fn has_pieces(&self, c: usize) -> bool {
        self.b.iter().any(|&p| p != 0 && (p >> 3) as usize == c && matches!(p & 7, N | B | R | Q))
    }
}

#[derive(Clone, Copy)]
struct TTE {
    key: u64,
    mv: u16,
    score: i32,
    depth: i8,
    flag: u8,
}

struct Search {
    tt: Vec<TTE>,
    killers: [[u16; 2]; MAXPLY + 2],
    history: Vec<i32>,
    nodes: u64,
    start: Instant,
    limit: Option<Duration>,
    stopped: bool,
    hist: Vec<u64>,
    root_best: u16,
}

const TTSIZE: usize = 1 << 21;

impl Search {
    fn new() -> Search {
        Search {
            tt: vec![TTE { key: 0, mv: 0, score: 0, depth: -1, flag: 0 }; TTSIZE],
            killers: [[0; 2]; MAXPLY + 2],
            history: vec![0; 2 * 64 * 64],
            nodes: 0,
            start: Instant::now(),
            limit: None,
            stopped: false,
            hist: vec![],
            root_best: 0,
        }
    }

    fn check_time(&mut self) {
        if STOP.load(Ordering::Relaxed) {
            self.stopped = true;
        } else if let Some(l) = self.limit {
            if self.start.elapsed() >= l {
                self.stopped = true;
            }
        }
    }

    fn order(&self, pos: &Pos, moves: &[u16], ttm: u16, ply: usize) -> Vec<i32> {
        moves
            .iter()
            .map(|&m| {
                if m == ttm {
                    return 1_000_000;
                }
                let from = (m & 63) as usize;
                let to = ((m >> 6) & 63) as usize;
                let promo = (m >> 12) as usize;
                let mut s = 0;
                if pos.is_cap(m) {
                    let v = VAL[(pos.b[to] & 7) as usize].max(100);
                    s = 100_000 + v * 10 - VAL[(pos.b[from] & 7) as usize] / 10;
                } else if self.killers[ply][0] == m {
                    s = 90_000;
                } else if self.killers[ply][1] == m {
                    s = 89_000;
                } else {
                    s += self.history[(pos.side * 64 + from) * 64 + to].min(80_000);
                }
                if promo != 0 {
                    s += VAL[promo] * 10;
                }
                s
            })
            .collect()
    }

    fn qsearch(&mut self, pos: &Pos, mut alpha: i32, beta: i32, ply: usize) -> i32 {
        self.nodes += 1;
        if self.nodes & 2047 == 0 {
            self.check_time();
        }
        if self.stopped {
            return 0;
        }
        let stand = pos.eval();
        if ply >= MAXPLY || stand >= beta {
            return stand;
        }
        if stand > alpha {
            alpha = stand;
        }
        let mut moves = vec![];
        pos.gen(&mut moves, true);
        let mut sc = self.order(pos, &moves, 0, ply);
        for i in 0..moves.len() {
            let mut bi = i;
            for j in i + 1..moves.len() {
                if sc[j] > sc[bi] {
                    bi = j;
                }
            }
            moves.swap(i, bi);
            sc.swap(i, bi);
            let np = pos.make(moves[i]);
            if np.attacked(np.ksq[pos.side], pos.side ^ 1) {
                continue;
            }
            let s = -self.qsearch(&np, -beta, -alpha, ply + 1);
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

    fn negamax(&mut self, pos: &Pos, mut depth: i32, mut alpha: i32, beta: i32, ply: usize, nullok: bool) -> i32 {
        self.nodes += 1;
        if self.nodes & 2047 == 0 {
            self.check_time();
        }
        if self.stopped {
            return 0;
        }
        if ply > 0 {
            if pos.half >= 100 {
                return 0;
            }
            let n = self.hist.len();
            let mut i = 2;
            while i <= pos.half as usize && i < n {
                if self.hist[n - 1 - i] == pos.hash {
                    return 0;
                }
                i += 2;
            }
        }
        if ply >= MAXPLY {
            return pos.eval();
        }
        let in_check = pos.in_check();
        if in_check {
            depth += 1;
        }
        if depth <= 0 {
            return self.qsearch(pos, alpha, beta, ply);
        }
        let idx = (pos.hash as usize) & (TTSIZE - 1);
        let e = self.tt[idx];
        let mut ttm = 0;
        if e.key == pos.hash && e.depth >= 0 {
            ttm = e.mv;
            if ply > 0 && e.depth as i32 >= depth {
                let mut s = e.score;
                if s > MATE - 1000 {
                    s -= ply as i32;
                } else if s < -MATE + 1000 {
                    s += ply as i32;
                }
                match e.flag {
                    0 => return s,
                    1 if s >= beta => return s,
                    2 if s <= alpha => return s,
                    _ => {}
                }
            }
        }
        if nullok && !in_check && depth >= 3 && ply > 0 && beta < MATE - 1000 && pos.has_pieces(pos.side) && pos.eval() >= beta {
            let np = pos.null();
            self.hist.push(np.hash);
            let s = -self.negamax(&np, depth - 3, -beta, -beta + 1, ply + 1, false);
            self.hist.pop();
            if self.stopped {
                return 0;
            }
            if s >= beta {
                return beta;
            }
        }
        let mut moves = vec![];
        pos.gen(&mut moves, false);
        let mut sc = self.order(pos, &moves, ttm, ply);
        let orig = alpha;
        let mut best = -MATE - 1;
        let mut bestm = 0;
        let mut legal = 0;
        for i in 0..moves.len() {
            let mut bi = i;
            for j in i + 1..moves.len() {
                if sc[j] > sc[bi] {
                    bi = j;
                }
            }
            moves.swap(i, bi);
            sc.swap(i, bi);
            let m = moves[i];
            let np = pos.make(m);
            if np.attacked(np.ksq[pos.side], pos.side ^ 1) {
                continue;
            }
            legal += 1;
            let quiet = !pos.is_cap(m) && (m >> 12) == 0;
            self.hist.push(np.hash);
            let s;
            if legal == 1 {
                s = -self.negamax(&np, depth - 1, -beta, -alpha, ply + 1, true);
            } else {
                let mut red = 0;
                if legal > 4 && depth >= 3 && !in_check && quiet && sc[i] < 89_000 {
                    red = if legal > 10 { 2 } else { 1 };
                }
                let mut x = -self.negamax(&np, depth - 1 - red, -alpha - 1, -alpha, ply + 1, true);
                if x > alpha && (red > 0 || x < beta) {
                    x = -self.negamax(&np, depth - 1, -beta, -alpha, ply + 1, true);
                }
                s = x;
            }
            self.hist.pop();
            if self.stopped {
                return 0;
            }
            if s > best {
                best = s;
                bestm = m;
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
                            let h = &mut self.history[(pos.side * 64 + (m & 63) as usize) * 64 + ((m >> 6) & 63) as usize];
                            *h += depth * depth;
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
            1
        } else if best > orig {
            0
        } else {
            2
        };
        let mut ss = best;
        if ss > MATE - 1000 {
            ss += ply as i32;
        } else if ss < -MATE + 1000 {
            ss -= ply as i32;
        }
        self.tt[idx] = TTE { key: pos.hash, mv: bestm, score: ss, depth: depth as i8, flag };
        best
    }

    fn think(&mut self, pos: &Pos, maxdepth: i32, limit: Option<Duration>) -> u16 {
        self.start = Instant::now();
        self.limit = limit;
        self.stopped = false;
        self.nodes = 0;
        self.killers = [[0; 2]; MAXPLY + 2];
        let legal = pos.legal();
        if legal.is_empty() {
            return 0;
        }
        let mut best = legal[0].0;
        for d in 1..=maxdepth.min(MAXPLY as i32 - 2) {
            self.root_best = 0;
            let s = self.negamax(pos, d, -MATE - 1, MATE + 1, 0, true);
            if self.stopped && d > 1 {
                break;
            }
            if self.root_best != 0 {
                best = self.root_best;
            }
            if self.stopped {
                break;
            }
            let el = self.start.elapsed().as_millis();
            let sstr = if s.abs() > MATE - 1000 {
                let n = (MATE - s.abs() + 1) / 2;
                format!("mate {}", if s > 0 { n } else { -n })
            } else {
                format!("cp {}", s)
            };
            println!("info depth {} score {} nodes {} time {} pv {}", d, sstr, self.nodes, el, mstr(best));
            let _ = io::stdout().flush();
            if let Some(l) = limit {
                if self.start.elapsed() * 10 >= l * 5 {
                    break;
                }
            }
            if s.abs() > MATE - 200 && limit.is_some() {
                break;
            }
        }
        best
    }
}

fn perft(pos: &Pos, d: u32) -> u64 {
    if d == 0 {
        return 1;
    }
    let l = pos.legal();
    if d == 1 {
        return l.len() as u64;
    }
    l.iter().map(|(_, p)| perft(p, d - 1)).sum()
}

const START: &str = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

fn main() {
    let h = std::thread::Builder::new().stack_size(64 << 20).spawn(run).unwrap();
    let _ = h.join();
}

fn run() {
    let (tx, rx) = mpsc::channel::<String>();
    std::thread::spawn(move || {
        let stdin = io::stdin();
        for line in stdin.lock().lines() {
            let Ok(line) = line else { break };
            let t = line.trim().to_string();
            if t == "stop" || t == "quit" {
                STOP.store(true, Ordering::Relaxed);
            }
            if tx.send(t).is_err() {
                break;
            }
        }
        STOP.store(true, Ordering::Relaxed);
        let _ = tx.send("quit".into());
    });
    let mut pos = Pos::from_fen(START).unwrap();
    let mut game: Vec<u64> = vec![pos.hash];
    let mut srch = Search::new();
    let out = io::stdout();
    while let Ok(line) = rx.recv() {
        let tok: Vec<&str> = line.split_whitespace().collect();
        if tok.is_empty() {
            continue;
        }
        match tok[0] {
            "uci" => {
                println!("id name RustFish 1.0\nid author Claude\nuciok");
            }
            "isready" => println!("readyok"),
            "ucinewgame" => {
                for e in srch.tt.iter_mut() {
                    e.depth = -1;
                    e.key = 0;
                }
                srch.history.iter_mut().for_each(|x| *x = 0);
            }
            "position" => {
                let mut i = 1;
                let mut np = None;
                if tok.get(1) == Some(&"startpos") {
                    np = Pos::from_fen(START);
                    i = 2;
                } else if tok.get(1) == Some(&"fen") {
                    let mut j = 2;
                    let mut f = vec![];
                    while j < tok.len() && tok[j] != "moves" {
                        f.push(tok[j]);
                        j += 1;
                    }
                    np = Pos::from_fen(&f.join(" "));
                    i = j;
                }
                if let Some(mut p) = np {
                    let mut g = vec![p.hash];
                    if tok.get(i) == Some(&"moves") {
                        for ms in &tok[i + 1..] {
                            let l = p.legal();
                            if let Some((_, q)) = l.into_iter().find(|(m, _)| mstr(*m) == *ms) {
                                p = q;
                                g.push(p.hash);
                            } else {
                                break;
                            }
                        }
                    }
                    pos = p;
                    game = g;
                }
            }
            "go" => {
                let mut depth = 64;
                let mut movetime: Option<u64> = None;
                let mut t = [None::<u64>; 2];
                let mut inc = [0u64; 2];
                let mut perft_d = None;
                let mut infinite = false;
                let mut i = 1;
                while i < tok.len() {
                    let v = tok.get(i + 1).and_then(|x| x.parse::<i64>().ok()).unwrap_or(0).max(0) as u64;
                    match tok[i] {
                        "depth" => depth = v as i32,
                        "movetime" => movetime = Some(v),
                        "wtime" => t[0] = Some(v),
                        "btime" => t[1] = Some(v),
                        "winc" => inc[0] = v,
                        "binc" => inc[1] = v,
                        "perft" => perft_d = Some(v as u32),
                        "infinite" => infinite = true,
                        _ => {
                            i += 1;
                            continue;
                        }
                    }
                    i += 2;
                }
                if let Some(d) = perft_d {
                    let mut total = 0;
                    for (m, p) in pos.legal() {
                        let c = if d <= 1 { 1 } else { perft(&p, d - 1) };
                        total += c;
                        println!("{}: {}", mstr(m), c);
                    }
                    println!("Nodes searched: {}", total);
                    let _ = out.lock().flush();
                    continue;
                }
                let mut limit = None;
                if let Some(mt) = movetime {
                    limit = Some(Duration::from_millis(mt.saturating_sub(15).max(1)));
                } else if let Some(tl) = t[pos.side] {
                    let a = (tl / 25 + inc[pos.side] * 3 / 4).min(tl / 3).max(5);
                    limit = Some(Duration::from_millis(a));
                }
                if infinite {
                    limit = None;
                }
                STOP.store(false, Ordering::Relaxed);
                // a stop/quit that arrived before we reset the flag is still queued
                srch.hist = game.clone();
                let best = srch.think(&pos, depth, limit);
                if best == 0 {
                    println!("bestmove 0000");
                } else {
                    println!("bestmove {}", mstr(best));
                }
                let _ = out.lock().flush();
            }
            "quit" => break,
            _ => {}
        }
        let _ = out.lock().flush();
    }
}
