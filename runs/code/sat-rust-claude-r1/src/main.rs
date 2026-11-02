use std::io::Write;

struct Clause {
    lits: Vec<u32>,
    lbd: u32,
    learnt: bool,
    deleted: bool,
}

struct Solver {
    n: usize,
    clauses: Vec<Clause>,
    watches: Vec<Vec<(u32, u32)>>,
    vals: Vec<i8>, // by lit
    level: Vec<u32>,
    reason: Vec<u32>,
    trail: Vec<u32>,
    lim: Vec<usize>,
    qhead: usize,
    act: Vec<f64>,
    inc: f64,
    heap: Vec<u32>,
    pos: Vec<i32>,
    phase: Vec<bool>,
    seen: Vec<bool>,
    stamp: Vec<u32>,
    stamp_n: u32,
}
const NONE: u32 = u32::MAX;

impl Solver {
    fn new(n: usize) -> Self {
        let mut s = Solver {
            n,
            clauses: vec![],
            watches: vec![vec![]; 2 * n],
            vals: vec![0; 2 * n],
            level: vec![0; n],
            reason: vec![NONE; n],
            trail: vec![],
            lim: vec![],
            qhead: 0,
            act: vec![0.0; n],
            inc: 1.0,
            heap: vec![],
            pos: vec![-1; n],
            phase: vec![false; n],
            seen: vec![false; n],
            stamp: vec![0; n + 1],
            stamp_n: 0,
        };
        for v in 0..n {
            s.heap_insert(v as u32);
        }
        s
    }
    fn heap_up(&mut self, mut i: usize) {
        let v = self.heap[i];
        while i > 0 {
            let p = (i - 1) / 2;
            let pv = self.heap[p];
            if self.act[v as usize] > self.act[pv as usize] {
                self.heap[i] = pv;
                self.pos[pv as usize] = i as i32;
                i = p;
            } else {
                break;
            }
        }
        self.heap[i] = v;
        self.pos[v as usize] = i as i32;
    }
    fn heap_down(&mut self, mut i: usize) {
        let v = self.heap[i];
        let len = self.heap.len();
        loop {
            let mut c = 2 * i + 1;
            if c >= len {
                break;
            }
            if c + 1 < len && self.act[self.heap[c + 1] as usize] > self.act[self.heap[c] as usize] {
                c += 1;
            }
            let cv = self.heap[c];
            if self.act[cv as usize] > self.act[v as usize] {
                self.heap[i] = cv;
                self.pos[cv as usize] = i as i32;
                i = c;
            } else {
                break;
            }
        }
        self.heap[i] = v;
        self.pos[v as usize] = i as i32;
    }
    fn heap_insert(&mut self, v: u32) {
        if self.pos[v as usize] >= 0 {
            return;
        }
        self.heap.push(v);
        let i = self.heap.len() - 1;
        self.pos[v as usize] = i as i32;
        self.heap_up(i);
    }
    fn heap_pop(&mut self) -> Option<u32> {
        if self.heap.is_empty() {
            return None;
        }
        let top = self.heap[0];
        let last = self.heap.pop().unwrap();
        self.pos[top as usize] = -1;
        if !self.heap.is_empty() {
            self.heap[0] = last;
            self.pos[last as usize] = 0;
            self.heap_down(0);
        }
        Some(top)
    }
    fn bump(&mut self, v: usize) {
        self.act[v] += self.inc;
        if self.act[v] > 1e100 {
            for a in self.act.iter_mut() {
                *a *= 1e-100;
            }
            self.inc *= 1e-100;
        }
        if self.pos[v] >= 0 {
            self.heap_up(self.pos[v] as usize);
        }
    }
    fn enqueue(&mut self, l: u32, r: u32) {
        let v = (l >> 1) as usize;
        self.vals[l as usize] = 1;
        self.vals[(l ^ 1) as usize] = -1;
        self.level[v] = self.lim.len() as u32;
        self.reason[v] = r;
        self.trail.push(l);
    }
    fn add_clause(&mut self, lits: Vec<u32>, learnt: bool, lbd: u32) -> u32 {
        let cr = self.clauses.len() as u32;
        self.watches[lits[0] as usize].push((cr, lits[1]));
        self.watches[lits[1] as usize].push((cr, lits[0]));
        self.clauses.push(Clause { lits, lbd, learnt, deleted: false });
        cr
    }
    fn propagate(&mut self) -> u32 {
        while self.qhead < self.trail.len() {
            let p = self.trail[self.qhead];
            self.qhead += 1;
            let fl = p ^ 1;
            let mut ws = std::mem::take(&mut self.watches[fl as usize]);
            let mut i = 0;
            let mut j = 0;
            let mut confl = NONE;
            while i < ws.len() {
                let (cr, blk) = ws[i];
                i += 1;
                if self.vals[blk as usize] == 1 {
                    ws[j] = (cr, blk);
                    j += 1;
                    continue;
                }
                let c = &mut self.clauses[cr as usize];
                if c.deleted {
                    continue;
                }
                if c.lits[0] == fl {
                    c.lits.swap(0, 1);
                }
                let first = c.lits[0];
                if first != blk && self.vals[first as usize] == 1 {
                    ws[j] = (cr, first);
                    j += 1;
                    continue;
                }
                let mut found = false;
                for k in 2..c.lits.len() {
                    let lk = c.lits[k];
                    if self.vals[lk as usize] != -1 {
                        c.lits.swap(1, k);
                        self.watches[lk as usize].push((cr, first));
                        found = true;
                        break;
                    }
                }
                if found {
                    continue;
                }
                ws[j] = (cr, first);
                j += 1;
                if self.vals[first as usize] == -1 {
                    confl = cr;
                    self.qhead = self.trail.len();
                    while i < ws.len() {
                        ws[j] = ws[i];
                        j += 1;
                        i += 1;
                    }
                    break;
                } else {
                    self.enqueue(first, cr);
                }
            }
            ws.truncate(j);
            self.watches[fl as usize] = ws;
            if confl != NONE {
                return confl;
            }
        }
        NONE
    }
    fn backtrack(&mut self, lvl: usize) {
        if self.lim.len() <= lvl {
            return;
        }
        let start = self.lim[lvl];
        for k in (start..self.trail.len()).rev() {
            let l = self.trail[k];
            let v = (l >> 1) as usize;
            self.vals[l as usize] = 0;
            self.vals[(l ^ 1) as usize] = 0;
            self.phase[v] = l & 1 == 0;
            self.heap_insert(v as u32);
        }
        self.trail.truncate(start);
        self.qhead = start;
        self.lim.truncate(lvl);
    }
    fn analyze(&mut self, mut confl: u32) -> (Vec<u32>, usize, u32) {
        let cur = self.lim.len() as u32;
        let mut learnt: Vec<u32> = vec![0];
        let mut path = 0;
        let mut idx = self.trail.len();
        let mut first = true;
        let mut p;
        loop {
            let lits = self.clauses[confl as usize].lits.clone();
            for &q in lits.iter().skip(if first { 0 } else { 1 }) {
                let v = (q >> 1) as usize;
                if !self.seen[v] && self.level[v] > 0 {
                    self.bump(v);
                    self.seen[v] = true;
                    if self.level[v] >= cur {
                        path += 1;
                    } else {
                        learnt.push(q);
                    }
                }
            }
            first = false;
            loop {
                idx -= 1;
                if self.seen[(self.trail[idx] >> 1) as usize] {
                    break;
                }
            }
            p = self.trail[idx];
            self.seen[(p >> 1) as usize] = false;
            path -= 1;
            if path == 0 {
                break;
            }
            confl = self.reason[(p >> 1) as usize];
        }
        learnt[0] = p ^ 1;
        let to_clear: Vec<u32> = learnt.clone();
        // minimize
        let mut k = 1;
        let mut out = vec![learnt[0]];
        while k < learnt.len() {
            let l = learnt[k];
            k += 1;
            let r = self.reason[(l >> 1) as usize];
            let mut keep = true;
            if r != NONE {
                keep = false;
                for &q in self.clauses[r as usize].lits.iter().skip(1) {
                    let v = (q >> 1) as usize;
                    if !self.seen[v] && self.level[v] > 0 {
                        keep = true;
                        break;
                    }
                }
            }
            if keep {
                out.push(l);
            }
        }
        for &l in &to_clear {
            self.seen[(l >> 1) as usize] = false;
        }
        let mut learnt = out;
        let mut bt = 0;
        if learnt.len() > 1 {
            let mut mi = 1;
            for i in 1..learnt.len() {
                if self.level[(learnt[i] >> 1) as usize] > self.level[(learnt[mi] >> 1) as usize] {
                    mi = i;
                }
            }
            learnt.swap(1, mi);
            bt = self.level[(learnt[1] >> 1) as usize] as usize;
        }
        self.stamp_n += 1;
        let mut lbd = 0;
        for &l in &learnt {
            let lv = self.level[(l >> 1) as usize] as usize;
            if self.stamp[lv] != self.stamp_n {
                self.stamp[lv] = self.stamp_n;
                lbd += 1;
            }
        }
        (learnt, bt, lbd)
    }
    fn reduce_db(&mut self) {
        let mut cand: Vec<u32> = vec![];
        for (i, c) in self.clauses.iter().enumerate() {
            if c.learnt && !c.deleted && c.lbd > 2 && c.lits.len() > 2 {
                let l0 = c.lits[0];
                let locked = self.vals[l0 as usize] == 1 && self.reason[(l0 >> 1) as usize] == i as u32;
                if !locked {
                    cand.push(i as u32);
                }
            }
        }
        cand.sort_by(|&a, &b| {
            let ca = &self.clauses[a as usize];
            let cb = &self.clauses[b as usize];
            cb.lbd.cmp(&ca.lbd).then(cb.lits.len().cmp(&ca.lits.len()))
        });
        for &cr in cand.iter().take(cand.len() / 2) {
            let c = &mut self.clauses[cr as usize];
            c.deleted = true;
            c.lits = vec![];
        }
        let clauses = &self.clauses;
        for w in self.watches.iter_mut() {
            w.retain(|&(cr, _)| !clauses[cr as usize].deleted);
        }
    }
    fn luby(mut x: u64) -> u64 {
        let mut size = 1u64;
        let mut seq = 0;
        while size < x + 1 {
            seq += 1;
            size = 2 * size + 1;
        }
        while size - 1 != x {
            size = (size - 1) >> 1;
            seq -= 1;
            x %= size;
        }
        1u64 << seq
    }
    fn solve(&mut self) -> bool {
        let mut conflicts: u64 = 0;
        let mut restart_n = 0u64;
        let mut budget = 100 * Self::luby(0);
        let mut max_learnts = (self.clauses.len() as f64 / 3.0).max(5000.0);
        let mut nlearnt = 0usize;
        loop {
            let confl = self.propagate();
            if confl != NONE {
                conflicts += 1;
                if self.lim.is_empty() {
                    return false;
                }
                let (learnt, bt, lbd) = self.analyze(confl);
                self.backtrack(bt);
                if learnt.len() == 1 {
                    self.enqueue(learnt[0], NONE);
                } else {
                    let l0 = learnt[0];
                    let cr = self.add_clause(learnt, true, lbd);
                    nlearnt += 1;
                    self.enqueue(l0, cr);
                }
                self.inc /= 0.95;
                budget = budget.saturating_sub(1);
            } else {
                if budget == 0 {
                    restart_n += 1;
                    budget = 100 * Self::luby(restart_n);
                    self.backtrack(0);
                    if nlearnt as f64 > max_learnts {
                        self.reduce_db();
                        nlearnt /= 2;
                        max_learnts *= 1.1;
                    }
                    continue;
                }
                let mut next = NONE;
                while let Some(v) = self.heap_pop() {
                    if self.vals[(2 * v) as usize] == 0 {
                        next = v;
                        break;
                    }
                }
                if next == NONE {
                    return true;
                }
                self.lim.push(self.trail.len());
                let l = 2 * next + if self.phase[next as usize] { 0 } else { 1 };
                self.enqueue(l, NONE);
            }
        }
    }
}

fn main() {
    let path = std::env::args().nth(1).expect("usage: solver FILE");
    let text = std::fs::read_to_string(&path).expect("cannot read file");
    let mut nvars = 0usize;
    let mut cls: Vec<Vec<i64>> = vec![];
    let mut cur: Vec<i64> = vec![];
    'outer: for line in text.lines() {
        let t = line.trim();
        if t.is_empty() || t.starts_with('c') {
            continue;
        }
        if t.starts_with('%') {
            break;
        }
        if t.starts_with('p') {
            let parts: Vec<&str> = t.split_whitespace().collect();
            if parts.len() >= 3 {
                nvars = parts[2].parse().unwrap_or(0);
            }
            continue;
        }
        for tok in t.split_whitespace() {
            if tok == "%" {
                break 'outer;
            }
            let x: i64 = match tok.parse() {
                Ok(x) => x,
                Err(_) => continue,
            };
            if x == 0 {
                cls.push(std::mem::take(&mut cur));
            } else {
                nvars = nvars.max(x.unsigned_abs() as usize);
                cur.push(x);
            }
        }
    }
    if !cur.is_empty() {
        cls.push(cur);
    }
    let mut s = Solver::new(nvars);
    let mut ok = true;
    for c in cls {
        let mut lits: Vec<u32> = c
            .iter()
            .map(|&x| (((x.unsigned_abs() - 1) as u32) << 1) | if x < 0 { 1 } else { 0 })
            .collect();
        lits.sort();
        lits.dedup();
        if lits.windows(2).any(|w| w[0] >> 1 == w[1] >> 1) {
            continue;
        }
        match lits.len() {
            0 => {
                ok = false;
                break;
            }
            1 => {
                let l = lits[0];
                if s.vals[l as usize] == -1 {
                    ok = false;
                    break;
                }
                if s.vals[l as usize] == 0 {
                    s.enqueue(l, NONE);
                }
            }
            _ => {
                s.add_clause(lits, false, 0);
            }
        }
    }
    let out = std::io::stdout();
    let mut o = out.lock();
    if ok && s.solve() {
        let mut line = String::from("v");
        writeln!(o, "s SATISFIABLE").unwrap();
        for v in 0..s.n {
            let x = if s.vals[2 * v] == 1 { (v + 1) as i64 } else { -((v + 1) as i64) };
            let t = format!(" {}", x);
            if line.len() + t.len() > 70 {
                writeln!(o, "{}", line).unwrap();
                line = String::from("v");
            }
            line.push_str(&t);
        }
        line.push_str(" 0");
        writeln!(o, "{}", line).unwrap();
        o.flush().unwrap();
        std::process::exit(10);
    } else {
        writeln!(o, "s UNSATISFIABLE").unwrap();
        o.flush().unwrap();
        std::process::exit(20);
    }
}
