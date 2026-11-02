use std::io::{self, BufRead, Write};
use std::sync::mpsc::{self, Receiver};
use std::time::Instant;

// ---------- zobrist ----------
const fn next(s: u64) -> (u64, u64) {
    let s = s.wrapping_add(0x9E3779B97F4A7C15);
    let mut z = s;
    z = (z ^ (z >> 30)).wrapping_mul(0xBF58476D1CE4E5B9);
    z = (z ^ (z >> 27)).wrapping_mul(0x94D049BB133111EB);
    (s, z ^ (z >> 31))
}
struct Zob {
    pk: [[u64; 64]; 16],
    ck: [u64; 16],
    ek: [u64; 8],
    sk: u64,
}
const fn gen_zob() -> Zob {
    let mut z = Zob { pk: [[0; 64]; 16], ck: [0; 16], ek: [0; 8], sk: 0 };
    let mut s = 12345u64;
    let mut i = 0;
    while i < 16 {
        let mut j = 0;
        while j < 64 {
            let (ns, v) = next(s);
            s = ns;
            z.pk[i][j] = v;
            j += 1;
        }
        i += 1;
    }
    i = 0;
    while i < 16 {
        let (ns, v) = next(s);
        s = ns;
        z.ck[i] = v;
        i += 1;
    }
    i = 0;
    while i < 8 {
        let (ns, v) = next(s);
        s = ns;
        z.ek[i] = v;
        i += 1;
    }
    let (_, v) = next(s);
    z.sk = v;
    z
}
static Z: Zob = gen_zob();

// ---------- position ----------
const CM: [u8; 64] = {
    let mut m = [15u8; 64];
    m[0] = 13;
    m[4] = 12;
    m[7] = 14;
    m[56] = 7;
    m[60] = 3;
    m[63] = 11;
    m
};
const KN: [(i32, i32); 8] = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)];
const KI: [(i32, i32); 8] = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)];
const DIAG: [(i32, i32); 4] = [(1, 1), (-1, 1), (-1, -1), (1, -1)];
const ORTH: [(i32, i32); 4] = [(1, 0), (-1, 0), (0, 1), (0, -1)];

#[derive(Clone, Copy)]
struct Pos {
    b: [u8; 64],
    side: u8,
    castle: u8,
    ep: i8,
    half: u16,
    hash: u64,
    ksq: [u8; 2],
}

struct MoveList {
    m: [u16; 256],
    n: usize,
}
impl MoveList {
    fn new() -> Self {
        MoveList { m: [0; 256], n: 0 }
    }
    fn add(&mut self, f: usize, t: usize, p: u8) {
        self.m[self.n] = f as u16 | (t as u16) << 6 | (p as u16) << 12;
        self.n += 1;
    }
}

fn mstr(m: u16) -> String {
    let f = (m & 63) as u8;
    let t = ((m >> 6) & 63) as u8;
    let p = (m >> 12) as usize;
    let mut s = String::new();
    s.push((b'a' + f % 8) as char);
    s.push((b'1' + f / 8) as char);
    s.push((b'a' + t % 8) as char);
    s.push((b'1' + t / 8) as char);
    if p != 0 {
        s.push(b"  nbrq"[p] as char);
    }
    s
}

impl Pos {
    fn put(&mut self, sq: usize, p: u8) {
        self.b[sq] = p;
        self.hash ^= Z.pk[p as usize][sq];
    }
    fn del(&mut self, sq: usize) {
        let p = self.b[sq];
        self.hash ^= Z.pk[p as usize][sq];
        self.b[sq] = 0;
    }
    fn compute_hash(&self) -> u64 {
        let mut h = 0;
        for s in 0..64 {
            if self.b[s] != 0 {
                h ^= Z.pk[self.b[s] as usize][s];
            }
        }
        h ^= Z.ck[self.castle as usize];
        if self.ep >= 0 {
            h ^= Z.ek[(self.ep & 7) as usize];
        }
        if self.side == 1 {
            h ^= Z.sk;
        }
        h
    }
    fn from_fen(fen: &str) -> Option<Pos> {
        let mut it = fen.split_whitespace();
        let board = it.next()?;
        let mut p = Pos { b: [0; 64], side: 0, castle: 0, ep: -1, half: 0, hash: 0, ksq: [0; 2] };
        let (mut f, mut r) = (0usize, 7i32);
        for c in board.chars() {
            match c {
                '/' => {
                    r -= 1;
                    f = 0;
                }
                '1'..='8' => f += c as usize - '0' as usize,
                _ => {
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
                    if r < 0 || f > 7 {
                        return None;
                    }
                    let sq = r as usize * 8 + f;
                    p.b[sq] = t | col;
                    if t == 6 {
                        p.ksq[(col >> 3) as usize] = sq as u8;
                    }
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
        let ep = it.next().unwrap_or("-").as_bytes();
        if ep.len() == 2 {
            p.ep = ((ep[1] - b'1') * 8 + (ep[0] - b'a')) as i8;
        }
        p.half = it.next().and_then(|x| x.parse().ok()).unwrap_or(0);
        p.hash = p.compute_hash();
        Some(p)
    }

    fn attacked(&self, sq: usize, by: u8) -> bool {
        let f = (sq & 7) as i32;
        let r = (sq >> 3) as i32;
        let cb = by << 3;
        let dr = if by == 0 { -1 } else { 1 };
        for df in [-1, 1] {
            let (nf, nr) = (f + df, r + dr);
            if (0..8).contains(&nf) && (0..8).contains(&nr) && self.b[(nr * 8 + nf) as usize] == (1 | cb) {
                return true;
            }
        }
        for (df, dr) in KN {
            let (nf, nr) = (f + df, r + dr);
            if (0..8).contains(&nf) && (0..8).contains(&nr) && self.b[(nr * 8 + nf) as usize] == (2 | cb) {
                return true;
            }
        }
        for (df, dr) in KI {
            let (nf, nr) = (f + df, r + dr);
            if (0..8).contains(&nf) && (0..8).contains(&nr) && self.b[(nr * 8 + nf) as usize] == (6 | cb) {
                return true;
            }
        }
        for (dirs, a) in [(&DIAG, 3u8), (&ORTH, 4u8)] {
            for &(df, dr) in dirs.iter() {
                let (mut nf, mut nr) = (f + df, r + dr);
                while (0..8).contains(&nf) && (0..8).contains(&nr) {
                    let p = self.b[(nr * 8 + nf) as usize];
                    if p != 0 {
                        if p == (a | cb) || p == (5 | cb) {
                            return true;
                        }
                        break;
                    }
                    nf += df;
                    nr += dr;
                }
            }
        }
        false
    }
    fn in_check(&self) -> bool {
        self.attacked(self.ksq[self.side as usize] as usize, self.side ^ 1)
    }

    fn make(&mut self, m: u16) -> bool {
        let from = (m & 63) as usize;
        let to = ((m >> 6) & 63) as usize;
        let promo = (m >> 12) as u8;
        let pc = self.b[from];
        let us = self.side;
        let t = pc & 7;
        self.hash ^= Z.ck[self.castle as usize];
        if self.ep >= 0 {
            self.hash ^= Z.ek[(self.ep & 7) as usize];
        }
        let cap = self.b[to];
        if cap != 0 {
            self.del(to);
        }
        if t == 1 || cap != 0 {
            self.half = 0
        } else {
            self.half += 1
        }
        let mut newep = -1i8;
        if t == 1 {
            if self.ep >= 0 && to as i8 == self.ep && cap == 0 && (from & 7) != (to & 7) {
                let csq = if us == 0 { to - 8 } else { to + 8 };
                self.del(csq);
            }
            if (to as i32 - from as i32).abs() == 16 {
                newep = ((from + to) / 2) as i8;
            }
        }
        self.del(from);
        let np = if promo != 0 { promo | (us << 3) } else { pc };
        self.put(to, np);
        if t == 6 {
            self.ksq[us as usize] = to as u8;
            if (to as i32 - from as i32).abs() == 2 {
                let (rf, rt) = if to > from { (from + 3, from + 1) } else { (from - 4, from - 1) };
                let r = self.b[rf];
                self.del(rf);
                self.put(rt, r);
            }
        }
        self.castle &= CM[from] & CM[to];
        self.hash ^= Z.ck[self.castle as usize];
        self.ep = newep;
        if newep >= 0 {
            self.hash ^= Z.ek[(newep & 7) as usize];
        }
        self.side ^= 1;
        self.hash ^= Z.sk;
        !self.attacked(self.ksq[us as usize] as usize, us ^ 1)
    }

    fn make_null(&mut self) {
        if self.ep >= 0 {
            self.hash ^= Z.ek[(self.ep & 7) as usize];
        }
        self.ep = -1;
        self.side ^= 1;
        self.hash ^= Z.sk;
        self.half += 1;
    }

    fn gen(&self, l: &mut MoveList, caps: bool) {
        let us = self.side;
        let cb = us << 3;
        for sq in 0..64usize {
            let p = self.b[sq];
            if p == 0 || (p & 8) != cb {
                continue;
            }
            let t = p & 7;
            let f = (sq & 7) as i32;
            let r = (sq >> 3) as i32;
            match t {
                1 => {
                    let dr = if us == 0 { 1 } else { -1 };
                    let start = if us == 0 { 1 } else { 6 };
                    let last = if us == 0 { 7 } else { 0 };
                    let nr = r + dr;
                    if nr < 0 || nr > 7 {
                        continue;
                    }
                    let to = (nr * 8 + f) as usize;
                    if self.b[to] == 0 {
                        if nr == last {
                            for pr in (2..=5).rev() {
                                l.add(sq, to, pr);
                            }
                        } else if !caps {
                            l.add(sq, to, 0);
                            if r == start {
                                let to2 = ((r + 2 * dr) * 8 + f) as usize;
                                if self.b[to2] == 0 {
                                    l.add(sq, to2, 0);
                                }
                            }
                        }
                    }
                    for df in [-1, 1] {
                        let nf = f + df;
                        if !(0..8).contains(&nf) {
                            continue;
                        }
                        let to = (nr * 8 + nf) as usize;
                        let q = self.b[to];
                        if q != 0 && (q & 8) != cb {
                            if nr == last {
                                for pr in (2..=5).rev() {
                                    l.add(sq, to, pr);
                                }
                            } else {
                                l.add(sq, to, 0);
                            }
                        } else if q == 0 && self.ep >= 0 && to as i8 == self.ep {
                            l.add(sq, to, 0);
                        }
                    }
                }
                2 | 6 => {
                    let d = if t == 2 { &KN } else { &KI };
                    for &(df, dr) in d.iter() {
                        let (nf, nr) = (f + df, r + dr);
                        if !(0..8).contains(&nf) || !(0..8).contains(&nr) {
                            continue;
                        }
                        let to = (nr * 8 + nf) as usize;
                        let q = self.b[to];
                        if q == 0 {
                            if !caps {
                                l.add(sq, to, 0);
                            }
                        } else if (q & 8) != cb {
                            l.add(sq, to, 0);
                        }
                    }
                    if t == 6 && !caps {
                        let base = if us == 0 { 0 } else { 56 };
                        if sq == base + 4 {
                            let (ks, qs) = if us == 0 { (1, 2) } else { (4, 8) };
                            let e = us ^ 1;
                            if self.castle & ks != 0
                                && self.b[base + 5] == 0
                                && self.b[base + 6] == 0
                                && !self.attacked(base + 4, e)
                                && !self.attacked(base + 5, e)
                            {
                                l.add(sq, base + 6, 0);
                            }
                            if self.castle & qs != 0
                                && self.b[base + 1] == 0
                                && self.b[base + 2] == 0
                                && self.b[base + 3] == 0
                                && !self.attacked(base + 4, e)
                                && !self.attacked(base + 3, e)
                            {
                                l.add(sq, base + 2, 0);
                            }
                        }
                    }
                }
                _ => {
                    for (dirs, ok) in [(&DIAG, t == 3 || t == 5), (&ORTH, t == 4 || t == 5)] {
                        if !ok {
                            continue;
                        }
                        for &(df, dr) in dirs.iter() {
                            let (mut nf, mut nr) = (f + df, r + dr);
                            while (0..8).contains(&nf) && (0..8).contains(&nr) {
                                let to = (nr * 8 + nf) as usize;
                                let q = self.b[to];
                                if q == 0 {
                                    if !caps {
                                        l.add(sq, to, 0);
                                    }
                                } else {
                                    if (q & 8) != cb {
                                        l.add(sq, to, 0);
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
    }

    fn is_capture(&self, m: u16) -> bool {
        let to = ((m >> 6) & 63) as usize;
        if self.b[to] != 0 {
            return true;
        }
        let from = (m & 63) as usize;
        (self.b[from] & 7) == 1 && (from & 7) != (to & 7)
    }

    fn has_nonpawn(&self, side: u8) -> bool {
        let cb = side << 3;
        self.b.iter().any(|&p| p != 0 && (p & 8) == cb && (p & 7) >= 2 && (p & 7) <= 5)
    }

    fn parse_move(&self, s: &str) -> Option<u16> {
        let mut l = MoveList::new();
        self.gen(&mut l, false);
        for i in 0..l.n {
            if mstr(l.m[i]) == s {
                let mut c = *self;
                if c.make(l.m[i]) {
                    return Some(l.m[i]);
                }
            }
        }
        None
    }
}

fn perft(p: &Pos, d: u32) -> u64 {
    if d == 0 {
        return 1;
    }
    let mut l = MoveList::new();
    p.gen(&mut l, false);
    let mut n = 0;
    for i in 0..l.n {
        let mut c = *p;
        if c.make(l.m[i]) {
            n += if d == 1 { 1 } else { perft(&c, d - 1) };
        }
    }
    n
}

// ---------- eval ----------
const VAL: [i32; 7] = [0, 100, 320, 330, 500, 900, 0];
#[rustfmt::skip]
const PST: [[i32; 64]; 7] = [
 [0;64],
 [0,0,0,0,0,0,0,0, 50,50,50,50,50,50,50,50, 10,10,20,30,30,20,10,10, 5,5,10,25,25,10,5,5, 0,0,0,20,20,0,0,0, 5,-5,-10,0,0,-10,-5,5, 5,10,10,-20,-20,10,10,5, 0,0,0,0,0,0,0,0],
 [-50,-40,-30,-30,-30,-30,-40,-50, -40,-20,0,0,0,0,-20,-40, -30,0,10,15,15,10,0,-30, -30,5,15,20,20,15,5,-30, -30,0,15,20,20,15,0,-30, -30,5,10,15,15,10,5,-30, -40,-20,0,5,5,0,-20,-40, -50,-40,-30,-30,-30,-30,-40,-50],
 [-20,-10,-10,-10,-10,-10,-10,-20, -10,0,0,0,0,0,0,-10, -10,0,5,10,10,5,0,-10, -10,5,5,10,10,5,5,-10, -10,0,10,10,10,10,0,-10, -10,10,10,10,10,10,10,-10, -10,5,0,0,0,0,5,-10, -20,-10,-10,-10,-10,-10,-10,-20],
 [0,0,0,0,0,0,0,0, 5,10,10,10,10,10,10,5, -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5, 0,0,0,5,5,0,0,0],
 [-20,-10,-10,-5,-5,-10,-10,-20, -10,0,0,0,0,0,0,-10, -10,0,5,5,5,5,0,-10, -5,0,5,5,5,5,0,-5, 0,0,5,5,5,5,0,-5, -10,5,5,5,5,5,0,-10, -10,0,5,0,0,0,0,-10, -20,-10,-10,-5,-5,-10,-10,-20],
 [-30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30, -20,-30,-30,-40,-40,-30,-30,-20, -10,-20,-20,-20,-20,-20,-20,-10, 20,20,0,0,0,0,20,20, 20,30,10,0,0,10,30,20],
];
#[rustfmt::skip]
const KEND: [i32; 64] = [-50,-40,-30,-20,-20,-30,-40,-50, -30,-20,-10,0,0,-10,-20,-30, -30,-10,20,30,30,20,-10,-30, -30,-10,30,40,40,30,-10,-30, -30,-10,30,40,40,30,-10,-30, -30,-10,20,30,30,20,-10,-30, -30,-30,0,0,0,0,-30,-30, -50,-30,-30,-30,-30,-30,-30,-50];

fn eval(p: &Pos) -> i32 {
    let mut s = [0i32; 2];
    let mut mg_k = [0i32; 2];
    let mut eg_k = [0i32; 2];
    let mut phase = 0;
    let mut bishops = [0; 2];
    for sq in 0..64 {
        let pc = p.b[sq];
        if pc == 0 {
            continue;
        }
        let t = (pc & 7) as usize;
        let c = (pc >> 3) as usize;
        let idx = if c == 0 { sq ^ 56 } else { sq };
        if t == 6 {
            mg_k[c] = PST[6][idx];
            eg_k[c] = KEND[idx];
        } else {
            s[c] += VAL[t] + PST[t][idx];
            match t {
                2 | 3 => phase += 1,
                4 => phase += 2,
                5 => phase += 4,
                _ => {}
            }
            if t == 3 {
                bishops[c] += 1;
            }
        }
    }
    let ph = phase.min(24);
    for c in 0..2 {
        s[c] += (mg_k[c] * ph + eg_k[c] * (24 - ph)) / 24;
        if bishops[c] >= 2 {
            s[c] += 30;
        }
    }
    let v = s[0] - s[1];
    if p.side == 0 {
        v
    } else {
        -v
    }
}

// ---------- search ----------
const MATE: i32 = 30000;
const INF: i32 = 32000;

#[derive(Clone, Copy, Default)]
struct Tte {
    key: u64,
    mv: u16,
    score: i16,
    depth: i8,
    flag: u8,
}
const TTN: usize = 1 << 21;

struct Searcher<'a> {
    tt: Vec<Tte>,
    rx: &'a Receiver<String>,
    nodes: u64,
    start: Instant,
    limit_ms: u64,
    stop: bool,
    quit: bool,
    cur_depth: i32,
    hist: Vec<u64>,
    killers: [[u16; 2]; 128],
    history: Vec<i32>,
    root_best: u16,
}

impl<'a> Searcher<'a> {
    fn check_time(&mut self) {
        if self.cur_depth <= 1 {
            return;
        }
        while let Ok(s) = self.rx.try_recv() {
            match s.trim() {
                "stop" => self.stop = true,
                "quit" => {
                    self.stop = true;
                    self.quit = true
                }
                "isready" => println!("readyok"),
                _ => {}
            }
        }
        if self.limit_ms > 0 && self.start.elapsed().as_millis() as u64 >= self.limit_ms {
            self.stop = true;
        }
    }

    fn is_draw(&self, p: &Pos) -> bool {
        if p.half >= 100 {
            return true;
        }
        let n = self.hist.len();
        let mut k = 2;
        while k <= p.half as usize && k < n {
            if self.hist[n - 1 - k] == p.hash {
                return true;
            }
            k += 2;
        }
        false
    }

    fn qsearch(&mut self, p: &Pos, mut alpha: i32, beta: i32, ply: usize) -> i32 {
        self.nodes += 1;
        if self.nodes & 2047 == 0 {
            self.check_time();
        }
        if self.stop {
            return 0;
        }
        let stand = eval(p);
        if ply >= 100 || stand >= beta {
            return stand;
        }
        if stand > alpha {
            alpha = stand;
        }
        let mut l = MoveList::new();
        p.gen(&mut l, true);
        let mut sc = [0i32; 256];
        for i in 0..l.n {
            sc[i] = self.order_score(p, l.m[i]);
        }
        for i in 0..l.n {
            let mut b = i;
            for j in i + 1..l.n {
                if sc[j] > sc[b] {
                    b = j;
                }
            }
            l.m.swap(i, b);
            sc.swap(i, b);
            let mut c = *p;
            if !c.make(l.m[i]) {
                continue;
            }
            let s = -self.qsearch(&c, -beta, -alpha, ply + 1);
            if self.stop {
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

    fn order_score(&self, p: &Pos, m: u16) -> i32 {
        let from = (m & 63) as usize;
        let to = ((m >> 6) & 63) as usize;
        let promo = (m >> 12) as i32;
        let mut s = 0;
        if p.is_capture(m) {
            let v = if p.b[to] != 0 { (p.b[to] & 7) as i32 } else { 1 };
            s = 100000 + v * 10 - (p.b[from] & 7) as i32;
        }
        if promo != 0 {
            s += 90000 + promo * 100;
        }
        s
    }

    fn negamax(&mut self, p: &Pos, mut depth: i32, ply: usize, mut alpha: i32, beta: i32, null_ok: bool) -> i32 {
        if self.stop {
            return 0;
        }
        if ply > 0 && self.is_draw(p) {
            return 0;
        }
        let in_check = p.in_check();
        if in_check {
            depth += 1;
        }
        if depth <= 0 || ply >= 100 {
            return self.qsearch(p, alpha, beta, ply);
        }
        self.nodes += 1;
        if self.nodes & 2047 == 0 {
            self.check_time();
            if self.stop {
                return 0;
            }
        }
        // mate distance pruning
        let a0 = alpha.max(-MATE + ply as i32);
        let b0 = beta.min(MATE - ply as i32 - 1);
        if a0 >= b0 {
            return a0;
        }
        let orig_alpha = alpha;
        let idx = (p.hash as usize) & (TTN - 1);
        let e = self.tt[idx];
        let mut tt_move = 0u16;
        if e.key == p.hash {
            tt_move = e.mv;
            if ply > 0 && e.depth as i32 >= depth {
                let mut s = e.score as i32;
                if s > MATE - 200 {
                    s -= ply as i32;
                } else if s < -MATE + 200 {
                    s += ply as i32;
                }
                if e.flag == 0 || (e.flag == 1 && s >= beta) || (e.flag == 2 && s <= alpha) {
                    return s;
                }
            }
        }
        if null_ok && !in_check && depth >= 3 && beta < MATE - 200 && p.has_nonpawn(p.side) && eval(p) >= beta {
            let mut c = *p;
            c.make_null();
            self.hist.push(c.hash);
            let r = if depth >= 6 { 3 } else { 2 };
            let s = -self.negamax(&c, depth - 1 - r, ply + 1, -beta, -beta + 1, false);
            self.hist.pop();
            if self.stop {
                return 0;
            }
            if s >= beta {
                return if s > MATE - 200 { beta } else { s };
            }
        }
        let mut l = MoveList::new();
        p.gen(&mut l, false);
        let mut sc = [0i32; 256];
        for i in 0..l.n {
            let m = l.m[i];
            sc[i] = if m == tt_move && m != 0 {
                1_000_000
            } else {
                let mut s = self.order_score(p, m);
                if s == 0 {
                    if m == self.killers[ply][0] {
                        s = 90000;
                    } else if m == self.killers[ply][1] {
                        s = 80000;
                    } else {
                        let from = (m & 63) as usize;
                        let to = ((m >> 6) & 63) as usize;
                        s = self.history[(p.b[from] as usize) * 64 + to].min(70000);
                    }
                }
                s
            };
        }
        let mut best = -INF;
        let mut best_move = 0u16;
        let mut legal = 0;
        for i in 0..l.n {
            let mut b = i;
            for j in i + 1..l.n {
                if sc[j] > sc[b] {
                    b = j;
                }
            }
            l.m.swap(i, b);
            sc.swap(i, b);
            let m = l.m[i];
            let mut c = *p;
            if !c.make(m) {
                continue;
            }
            legal += 1;
            let cap = p.is_capture(m);
            let quiet = !cap && (m >> 12) == 0;
            self.hist.push(c.hash);
            let mut s;
            if legal == 1 {
                s = -self.negamax(&c, depth - 1, ply + 1, -beta, -alpha, true);
            } else {
                let mut red = 0;
                if depth >= 3 && legal > 3 && quiet && !in_check {
                    red = if legal > 8 { 2 } else { 1 };
                }
                s = -self.negamax(&c, depth - 1 - red, ply + 1, -alpha - 1, -alpha, true);
                if s > alpha && !self.stop && (red > 0 || s < beta) {
                    s = -self.negamax(&c, depth - 1, ply + 1, -beta, -alpha, true);
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
                            let from = (m & 63) as usize;
                            let to = ((m >> 6) & 63) as usize;
                            let h = &mut self.history[(p.b[from] as usize) * 64 + to];
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
        } else if best > orig_alpha {
            0
        } else {
            2
        };
        let mut s = best;
        if s > MATE - 200 {
            s += ply as i32;
        } else if s < -MATE + 200 {
            s -= ply as i32;
        }
        self.tt[idx] = Tte { key: p.hash, mv: best_move, score: s as i16, depth: depth as i8, flag };
        best
    }

    fn think(&mut self, p: &Pos, max_depth: i32, timed: bool) -> u16 {
        let mut best = 0u16;
        // fallback: first legal move
        let mut l = MoveList::new();
        p.gen(&mut l, false);
        for i in 0..l.n {
            let mut c = *p;
            if c.make(l.m[i]) {
                best = l.m[i];
                break;
            }
        }
        if best == 0 {
            return 0;
        }
        self.root_best = best;
        for d in 1..=max_depth {
            self.cur_depth = d;
            self.history.iter_mut().for_each(|h| *h /= 2);
            let s = self.negamax(p, d, 0, -INF, INF, false);
            if self.stop {
                break;
            }
            best = self.root_best;
            let el = self.start.elapsed().as_millis();
            let sc = if s.abs() > MATE - 200 {
                let n = (MATE - s.abs() + 1) / 2;
                format!("mate {}", if s > 0 { n } else { -n })
            } else {
                format!("cp {}", s)
            };
            println!("info depth {} score {} nodes {} time {} pv {}", d, sc, self.nodes, el, mstr(best));
            if timed && self.limit_ms > 0 {
                if el as u64 * 10 > self.limit_ms * 5 {
                    break;
                }
                if s.abs() > MATE - 200 && d as i32 >= (MATE - s.abs()) {
                    break;
                }
            }
        }
        best
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
                        return;
                    }
                }
                Err(_) => break,
            }
        }
        let _ = tx.send("quit".to_string());
    });
    let startfen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";
    let mut pos = Pos::from_fen(startfen).unwrap();
    let mut hist: Vec<u64> = vec![pos.hash];
    let mut tt = vec![Tte::default(); TTN];
    let out = io::stdout();
    while let Ok(line) = rx.recv() {
        let toks: Vec<&str> = line.split_whitespace().collect();
        if toks.is_empty() {
            continue;
        }
        match toks[0] {
            "uci" => {
                println!("id name RustFish 1.0");
                println!("id author agent");
                println!("uciok");
            }
            "isready" => println!("readyok"),
            "ucinewgame" => {
                tt.iter_mut().for_each(|e| *e = Tte::default());
            }
            "position" => {
                let mut i = 1;
                let mut np = None;
                if i < toks.len() && toks[i] == "startpos" {
                    np = Pos::from_fen(startfen);
                    i += 1;
                } else if i < toks.len() && toks[i] == "fen" {
                    i += 1;
                    let mut f = Vec::new();
                    while i < toks.len() && toks[i] != "moves" {
                        f.push(toks[i]);
                        i += 1;
                    }
                    np = Pos::from_fen(&f.join(" "));
                }
                if let Some(mut p) = np {
                    let mut h = vec![p.hash];
                    if i < toks.len() && toks[i] == "moves" {
                        for t in &toks[i + 1..] {
                            match p.parse_move(t) {
                                Some(m) => {
                                    p.make(m);
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
                let mut movetime = 0u64;
                let (mut wt, mut bt, mut wi, mut bi) = (0u64, 0u64, 0u64, 0u64);
                let mut has_clock = false;
                let mut perft_d = 0;
                let mut i = 1;
                let mut fixed_depth = false;
                while i < toks.len() {
                    let v = toks.get(i + 1).and_then(|x| x.parse::<i64>().ok()).unwrap_or(0);
                    match toks[i] {
                        "depth" => {
                            depth = v.clamp(1, 64) as i32;
                            fixed_depth = true;
                            i += 1
                        }
                        "movetime" => {
                            movetime = v.max(1) as u64;
                            i += 1
                        }
                        "wtime" => {
                            wt = v.max(0) as u64;
                            has_clock = true;
                            i += 1
                        }
                        "btime" => {
                            bt = v.max(0) as u64;
                            has_clock = true;
                            i += 1
                        }
                        "winc" => {
                            wi = v.max(0) as u64;
                            i += 1
                        }
                        "binc" => {
                            bi = v.max(0) as u64;
                            i += 1
                        }
                        "perft" => {
                            perft_d = v.max(0) as u32;
                            i += 1
                        }
                        _ => {}
                    }
                    i += 1;
                }
                if perft_d > 0 {
                    let mut l = MoveList::new();
                    pos.gen(&mut l, false);
                    let mut tot = 0;
                    for k in 0..l.n {
                        let mut c = pos;
                        if c.make(l.m[k]) {
                            let n = perft(&c, perft_d - 1);
                            tot += n;
                            println!("{}: {}", mstr(l.m[k]), n);
                        }
                    }
                    println!("Nodes searched: {}", tot);
                    out.lock().flush().ok();
                    continue;
                }
                let mut limit = 0u64;
                if movetime > 0 {
                    limit = movetime.saturating_sub(15).max(1);
                } else if has_clock {
                    let (t, inc) = if pos.side == 0 { (wt, wi) } else { (bt, bi) };
                    limit = (t / 25 + inc * 3 / 4).min(t.saturating_sub(50) * 4 / 5).max(5);
                }
                let _ = fixed_depth;
                let timed = limit > 0;
                let mut s = Searcher {
                    tt: std::mem::take(&mut tt),
                    rx: &rx,
                    nodes: 0,
                    start: Instant::now(),
                    limit_ms: limit,
                    stop: false,
                    quit: false,
                    cur_depth: 0,
                    hist: hist.clone(),
                    killers: [[0; 2]; 128],
                    history: vec![0; 16 * 64],
                    root_best: 0,
                };
                let best = s.think(&pos, depth, timed);
                let quit = s.quit;
                tt = std::mem::take(&mut s.tt);
                if best == 0 {
                    println!("bestmove 0000");
                } else {
                    println!("bestmove {}", mstr(best));
                }
                out.lock().flush().ok();
                if quit {
                    return;
                }
            }
            "quit" => return,
            _ => {}
        }
        out.lock().flush().ok();
    }
}
