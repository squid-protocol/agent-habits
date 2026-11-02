use std::io::Write;
const NONE: u32 = u32::MAX;
struct Cl { lits: Vec<u32>, learnt: bool, lbd: u32, del: bool }
#[derive(Clone, Copy)]
struct W { c: u32, b: u32 }
struct S {
    nv: usize, cls: Vec<Cl>, watches: Vec<Vec<W>>, vals: Vec<i8>, level: Vec<u32>, reason: Vec<u32>,
    trail: Vec<u32>, lim: Vec<usize>, qh: usize, act: Vec<f64>, inc: f64, heap: Vec<u32>, pos: Vec<i32>,
    phase: Vec<bool>, seen: Vec<bool>, learnts: Vec<u32>, stamp: Vec<u32>, stamp_n: u32,
}
#[inline] fn var(l: u32) -> usize { (l >> 1) as usize }
impl S {
    fn new(nv: usize) -> S {
        let mut s = S { nv, cls: vec![], watches: vec![vec![]; 2 * nv], vals: vec![0; 2 * nv], level: vec![0; nv], reason: vec![NONE; nv],
            trail: vec![], lim: vec![], qh: 0, act: vec![0.0; nv], inc: 1.0, heap: vec![], pos: vec![-1; nv], phase: vec![false; nv],
            seen: vec![false; nv], learnts: vec![], stamp: vec![0; nv + 1], stamp_n: 0 };
        for v in 0..nv { s.heap_insert(v as u32); }
        s
    }
    fn lt(&self, a: u32, b: u32) -> bool { self.act[a as usize] > self.act[b as usize] }
    fn up(&mut self, mut i: usize) {
        let x = self.heap[i];
        while i > 0 { let p = (i - 1) / 2; if self.lt(x, self.heap[p]) { self.heap[i] = self.heap[p]; self.pos[self.heap[i] as usize] = i as i32; i = p; } else { break; } }
        self.heap[i] = x; self.pos[x as usize] = i as i32;
    }
    fn down(&mut self, mut i: usize) {
        let x = self.heap[i]; let n = self.heap.len();
        loop {
            let mut c = 2 * i + 1; if c >= n { break; }
            if c + 1 < n && self.lt(self.heap[c + 1], self.heap[c]) { c += 1; }
            if self.lt(self.heap[c], x) { self.heap[i] = self.heap[c]; self.pos[self.heap[i] as usize] = i as i32; i = c; } else { break; }
        }
        self.heap[i] = x; self.pos[x as usize] = i as i32;
    }
    fn heap_insert(&mut self, v: u32) {
        if self.pos[v as usize] >= 0 { return; }
        self.heap.push(v); let i = self.heap.len() - 1; self.pos[v as usize] = i as i32; self.up(i);
    }
    fn pop(&mut self) -> Option<u32> {
        if self.heap.is_empty() { return None; }
        let t = self.heap[0]; let l = self.heap.pop().unwrap(); self.pos[t as usize] = -1;
        if !self.heap.is_empty() { self.heap[0] = l; self.pos[l as usize] = 0; self.down(0); }
        Some(t)
    }
    fn bump(&mut self, v: usize) {
        self.act[v] += self.inc;
        if self.act[v] > 1e100 { for a in self.act.iter_mut() { *a *= 1e-100; } self.inc *= 1e-100; }
        if self.pos[v] >= 0 { self.up(self.pos[v] as usize); }
    }
    fn enqueue(&mut self, l: u32, r: u32) {
        self.vals[l as usize] = 1; self.vals[(l ^ 1) as usize] = -1;
        let v = var(l); self.level[v] = self.lim.len() as u32; self.reason[v] = r; self.trail.push(l);
    }
    fn add_clause(&mut self, lits: Vec<u32>, learnt: bool, lbd: u32) -> u32 {
        let c = self.cls.len() as u32;
        self.watches[lits[0] as usize].push(W { c, b: lits[1] });
        self.watches[lits[1] as usize].push(W { c, b: lits[0] });
        self.cls.push(Cl { lits, learnt, lbd, del: false });
        c
    }
    fn propagate(&mut self) -> u32 {
        while self.qh < self.trail.len() {
            let p = self.trail[self.qh]; self.qh += 1;
            let fl = p ^ 1; // literal now false
            let mut ws = std::mem::take(&mut self.watches[fl as usize]);
            let (mut i, mut j) = (0, 0); let n = ws.len();
            let mut confl = NONE;
            while i < n {
                let w = ws[i]; i += 1;
                if self.vals[w.b as usize] == 1 { ws[j] = w; j += 1; continue; }
                let cr = w.c as usize;
                if self.cls[cr].del { continue; }
                let c = &mut self.cls[cr].lits;
                if c[0] == fl { c.swap(0, 1); }
                let first = c[0];
                if first != w.b && self.vals[first as usize] == 1 { ws[j] = W { c: w.c, b: first }; j += 1; continue; }
                let mut found = false;
                for k in 2..c.len() {
                    if self.vals[c[k] as usize] != -1 {
                        c.swap(1, k);
                        let nl = c[1];
                        self.watches[nl as usize].push(W { c: w.c, b: first });
                        found = true; break;
                    }
                }
                if found { continue; }
                ws[j] = W { c: w.c, b: first }; j += 1;
                if self.vals[first as usize] == -1 {
                    confl = w.c; self.qh = self.trail.len();
                    while i < n { ws[j] = ws[i]; j += 1; i += 1; }
                } else { self.enqueue(first, w.c); }
            }
            ws.truncate(j);
            self.watches[fl as usize] = ws;
            if confl != NONE { return confl; }
        }
        NONE
    }
    fn cancel(&mut self, lvl: usize) {
        if self.lim.len() <= lvl { return; }
        let st = self.lim[lvl];
        for i in (st..self.trail.len()).rev() {
            let l = self.trail[i]; let v = var(l);
            self.vals[l as usize] = 0; self.vals[(l ^ 1) as usize] = 0;
            self.phase[v] = l & 1 == 0; self.heap_insert(v as u32);
        }
        self.trail.truncate(st); self.lim.truncate(lvl); self.qh = st;
    }
    fn analyze(&mut self, mut confl: u32) -> (Vec<u32>, usize, u32) {
        let mut learnt = vec![0u32]; let mut path = 0; let mut p = NONE; let mut idx = self.trail.len();
        let cur = self.lim.len() as u32;
        loop {
            let start = if p == NONE { 0 } else { 1 };
            let len = self.cls[confl as usize].lits.len();
            for k in start..len {
                let q = self.cls[confl as usize].lits[k]; let v = var(q);
                if !self.seen[v] && self.level[v] > 0 {
                    self.bump(v); self.seen[v] = true;
                    if self.level[v] >= cur { path += 1 } else { learnt.push(q) }
                }
            }
            loop { idx -= 1; if self.seen[var(self.trail[idx])] { break; } }
            p = self.trail[idx]; confl = self.reason[var(p)];
            self.seen[var(p)] = false; path -= 1;
            if path == 0 { break; }
        }
        learnt[0] = p ^ 1;
        let to_clear: Vec<u32> = learnt.clone();
        let mut out = vec![learnt[0]];
        for &q in &learnt[1..] {
            let r = self.reason[var(q)];
            let mut keep = r == NONE;
            if !keep {
                for &x in &self.cls[r as usize].lits[1..] {
                    if !self.seen[var(x)] && self.level[var(x)] > 0 { keep = true; break; }
                }
            }
            if keep { out.push(q); }
        }
        for &q in &to_clear { self.seen[var(q)] = false; }
        let mut bt = 0;
        if out.len() > 1 {
            let mut mi = 1;
            for k in 1..out.len() { if self.level[var(out[k])] > self.level[var(out[mi])] { mi = k; } }
            out.swap(1, mi); bt = self.level[var(out[1])] as usize;
        }
        self.stamp_n += 1; let mut lbd = 0;
        for &q in &out { let l = self.level[var(q)] as usize; if self.stamp[l] != self.stamp_n { self.stamp[l] = self.stamp_n; lbd += 1; } }
        (out, bt, lbd)
    }
    fn reduce(&mut self) {
        let mut ls = std::mem::take(&mut self.learnts);
        ls.retain(|&c| !self.cls[c as usize].del);
        ls.sort_by_key(|&c| { let k = &self.cls[c as usize]; (std::cmp::Reverse(k.lbd), std::cmp::Reverse(k.lits.len())) });
        let n = ls.len() / 2; let mut kept = vec![];
        for (i, &c) in ls.iter().enumerate() {
            let k = &self.cls[c as usize];
            let l0 = k.lits[0];
            let locked = self.vals[l0 as usize] == 1 && self.reason[var(l0)] == c;
            if i < n && k.lbd > 2 && !locked { let k = &mut self.cls[c as usize]; k.del = true; k.lits = vec![]; } else { kept.push(c); }
        }
        self.learnts = kept;
    }
    fn solve(&mut self) -> bool {
        let mut conflicts = 0u64; let mut next_reduce = 4000u64; let mut rs = 0u32;
        loop {
            let budget = 100 * luby(rs); rs += 1; let mut c_here = 0;
            loop {
                let confl = self.propagate();
                if confl != NONE {
                    conflicts += 1; c_here += 1;
                    if self.lim.is_empty() { return false; }
                    let (l, bt, lbd) = self.analyze(confl);
                    self.cancel(bt);
                    if l.len() == 1 { self.enqueue(l[0], NONE); }
                    else { let f = l[0]; let c = self.add_clause(l, true, lbd); self.learnts.push(c); self.enqueue(f, c); }
                    self.inc /= 0.95;
                } else {
                    if c_here >= budget { self.cancel(0); break; }
                    if conflicts >= next_reduce { self.reduce(); next_reduce = conflicts + 4000 + 300 * (conflicts / 4000); }
                    let mut dec = NONE;
                    while let Some(v) = self.pop() { if self.vals[2 * v as usize] == 0 { dec = v; break; } }
                    if dec == NONE { return true; }
                    self.lim.push(self.trail.len());
                    let l = 2 * dec + if self.phase[dec as usize] { 0 } else { 1 };
                    self.enqueue(l, NONE);
                }
            }
        }
    }
}
fn luby(i: u32) -> u64 {
    let (mut size, mut seq) = (1u64, 0u32);
    while size < i as u64 + 1 { seq += 1; size = 2 * size + 1; }
    let mut x = i as u64;
    while size - 1 != x { size = (size - 1) >> 1; seq -= 1; x %= size; }
    1u64 << seq
}
fn main() {
    let path = std::env::args().nth(1).expect("usage: solver FILE");
    let text = std::fs::read_to_string(path).expect("read");
    let mut nv = 0usize; let mut clauses: Vec<Vec<i64>> = vec![]; let mut cur: Vec<i64> = vec![];
    for line in text.lines() {
        let t = line.trim();
        if t.starts_with('c') || t.starts_with('%') { continue; }
        if t.starts_with('p') { let p: Vec<&str> = t.split_whitespace().collect(); if p.len() >= 3 { nv = p[2].parse().unwrap_or(0); } continue; }
        for tok in t.split_whitespace() {
            if let Ok(x) = tok.parse::<i64>() { if x == 0 { clauses.push(std::mem::take(&mut cur)); } else { cur.push(x); } }
        }
    }
    if !cur.is_empty() { clauses.push(cur); }
    for c in &clauses { for &x in c { nv = nv.max(x.unsigned_abs() as usize); } }
    let mut s = S::new(nv);
    let mut ok = true;
    let mut units = vec![];
    for c in clauses {
        let mut l: Vec<u32> = c.iter().map(|&x| 2 * (x.unsigned_abs() as u32 - 1) + if x < 0 { 1 } else { 0 }).collect();
        l.sort(); l.dedup();
        if l.windows(2).any(|w| w[0] ^ 1 == w[1]) { continue; }
        match l.len() { 0 => ok = false, 1 => units.push(l[0]), _ => { s.add_clause(l, false, 0); } }
    }
    if ok {
        for u in units {
            if s.vals[u as usize] == -1 { ok = false; break; }
            if s.vals[u as usize] == 0 { s.enqueue(u, NONE); }
        }
    }
    let sat = ok && s.solve();
    let mut o = std::io::stdout().lock();
    if sat {
        writeln!(o, "s SATISFIABLE").unwrap();
        let mut line = String::from("v");
        for v in 0..s.nv {
            let t = format!(" {}", if s.vals[2 * v] == 1 { v as i64 + 1 } else { -(v as i64 + 1) });
            if line.len() + t.len() > 75 { writeln!(o, "{}", line).unwrap(); line = String::from("v"); }
            line += &t;
        }
        line += " 0"; writeln!(o, "{}", line).unwrap();
        o.flush().unwrap(); std::process::exit(10);
    } else { writeln!(o, "s UNSATISFIABLE").unwrap(); o.flush().unwrap(); std::process::exit(20); }
}
