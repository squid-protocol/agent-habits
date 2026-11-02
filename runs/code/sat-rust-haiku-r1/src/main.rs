//! A DPLL-based SAT solver for DIMACS CNF formulas.
//!
//! The search is DPLL: unit propagation (two watched literals), decisions and
//! chronological backtracking. On top of that it uses conflict-driven clause
//! learning (first-UIP learning with recursive minimisation), VSIDS variable
//! ordering, phase saving, Luby restarts and LBD-based clause deletion.
//!
//! Output follows the SAT competition convention: `s SATISFIABLE` with `v`
//! lines and exit code 10, `s UNSATISFIABLE` with exit code 20.

use std::env;
use std::fs;
use std::io::{self, Write};
use std::process;

const NONE: u32 = u32::MAX;

#[derive(Clone, Copy)]
struct Watcher {
    cref: u32,
    /// If this literal is true the clause is satisfied and need not be visited.
    blocker: u32,
}

struct Clause {
    /// Literals; `lits[0]` and `lits[1]` are the watched ones.
    lits: Vec<u32>,
    learnt: bool,
    lbd: u32,
    deleted: bool,
}

/// Literal encoding: variable `v` (0-based) gives literals `2v` (positive) and `2v+1` (negative).
struct Solver {
    clauses: Vec<Clause>,
    /// `watches[l]`: clauses in which literal `l` is watched.
    watches: Vec<Vec<Watcher>>,
    /// Value per literal: 1 true, -1 false, 0 unassigned.
    val: Vec<i8>,
    level: Vec<u32>,
    reason: Vec<u32>,
    trail: Vec<u32>,
    trail_lim: Vec<usize>,
    qhead: usize,
    activity: Vec<f64>,
    var_inc: f64,
    /// Binary max-heap of unassigned candidate variables ordered by activity.
    heap: Vec<u32>,
    heap_pos: Vec<i32>,
    phase: Vec<bool>,
    seen: Vec<bool>,
    num_learnts: usize,
    max_learnts: f64,
    conflicts: u64,
}

fn luby(mut x: u64) -> u64 {
    let (mut size, mut seq) = (1u64, 0u32);
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

impl Solver {
    fn new(nvars: usize, nclauses: usize) -> Solver {
        Solver {
            clauses: Vec::with_capacity(nclauses),
            watches: (0..2 * nvars).map(|_| Vec::new()).collect(),
            val: vec![0; 2 * nvars],
            level: vec![0; nvars],
            reason: vec![NONE; nvars],
            trail: Vec::with_capacity(nvars),
            trail_lim: Vec::new(),
            qhead: 0,
            activity: vec![0.0; nvars],
            var_inc: 1.0,
            heap: (0..nvars as u32).collect(),
            heap_pos: (0..nvars as i32).collect(),
            phase: vec![false; nvars],
            seen: vec![false; nvars],
            num_learnts: 0,
            max_learnts: (nclauses as f64 / 3.0).max(2000.0),
            conflicts: 0,
        }
    }

    fn decision_level(&self) -> u32 {
        self.trail_lim.len() as u32
    }

    // ---- VSIDS heap -------------------------------------------------------

    fn heap_up(&mut self, mut i: usize) {
        let v = self.heap[i];
        while i > 0 {
            let parent = (i - 1) / 2;
            let pv = self.heap[parent];
            if self.activity[v as usize] <= self.activity[pv as usize] {
                break;
            }
            self.heap[i] = pv;
            self.heap_pos[pv as usize] = i as i32;
            i = parent;
        }
        self.heap[i] = v;
        self.heap_pos[v as usize] = i as i32;
    }

    fn heap_down(&mut self, mut i: usize) {
        let v = self.heap[i];
        let n = self.heap.len();
        loop {
            let l = 2 * i + 1;
            if l >= n {
                break;
            }
            let r = l + 1;
            let mut c = l;
            if r < n && self.activity[self.heap[r] as usize] > self.activity[self.heap[l] as usize] {
                c = r;
            }
            if self.activity[self.heap[c] as usize] <= self.activity[v as usize] {
                break;
            }
            let cv = self.heap[c];
            self.heap[i] = cv;
            self.heap_pos[cv as usize] = i as i32;
            i = c;
        }
        self.heap[i] = v;
        self.heap_pos[v as usize] = i as i32;
    }

    fn heap_insert(&mut self, v: u32) {
        if self.heap_pos[v as usize] >= 0 {
            return;
        }
        self.heap.push(v);
        let i = self.heap.len() - 1;
        self.heap_pos[v as usize] = i as i32;
        self.heap_up(i);
    }

    fn heap_pop(&mut self) -> Option<u32> {
        if self.heap.is_empty() {
            return None;
        }
        let top = self.heap[0];
        let last = self.heap.pop().unwrap();
        self.heap_pos[top as usize] = -1;
        if !self.heap.is_empty() {
            self.heap[0] = last;
            self.heap_pos[last as usize] = 0;
            self.heap_down(0);
        }
        Some(top)
    }

    fn bump_var(&mut self, v: usize) {
        self.activity[v] += self.var_inc;
        if self.activity[v] > 1e100 {
            for a in self.activity.iter_mut() {
                *a *= 1e-100;
            }
            self.var_inc *= 1e-100;
        }
        let p = self.heap_pos[v];
        if p >= 0 {
            self.heap_up(p as usize);
        }
    }

    // ---- trail and clauses ------------------------------------------------

    fn enqueue(&mut self, lit: u32, reason: u32) {
        let v = (lit >> 1) as usize;
        self.val[lit as usize] = 1;
        self.val[(lit ^ 1) as usize] = -1;
        self.level[v] = self.decision_level();
        self.reason[v] = reason;
        self.trail.push(lit);
    }

    fn backtrack(&mut self, lvl: u32) {
        if self.decision_level() <= lvl {
            return;
        }
        let lim = self.trail_lim[lvl as usize];
        for k in (lim..self.trail.len()).rev() {
            let lit = self.trail[k];
            let v = (lit >> 1) as usize;
            self.val[lit as usize] = 0;
            self.val[(lit ^ 1) as usize] = 0;
            self.phase[v] = lit & 1 == 0;
            self.reason[v] = NONE;
            self.heap_insert(v as u32);
        }
        self.trail.truncate(lim);
        self.trail_lim.truncate(lvl as usize);
        self.qhead = lim;
    }

    /// Stores a clause (length >= 2) and watches its first two literals.
    fn add_clause(&mut self, lits: Vec<u32>, learnt: bool, lbd: u32) -> u32 {
        let cr = self.clauses.len() as u32;
        let (a, b) = (lits[0], lits[1]);
        self.clauses.push(Clause { lits, learnt, lbd, deleted: false });
        self.watches[a as usize].push(Watcher { cref: cr, blocker: b });
        self.watches[b as usize].push(Watcher { cref: cr, blocker: a });
        cr
    }

    /// Unit propagation. Returns the conflicting clause, if any.
    fn propagate(&mut self) -> Option<u32> {
        let mut confl = None;
        while self.qhead < self.trail.len() {
            let p = self.trail[self.qhead];
            self.qhead += 1;
            // `fl` has just become false; visit the clauses watching it.
            let fl = p ^ 1;
            let mut ws = std::mem::take(&mut self.watches[fl as usize]);
            let n = ws.len();
            let (mut i, mut j) = (0usize, 0usize);
            while i < n {
                let w = ws[i];
                i += 1;
                if self.val[w.blocker as usize] == 1 {
                    ws[j] = w;
                    j += 1;
                    continue;
                }
                let cr = w.cref;
                let lits = &mut self.clauses[cr as usize].lits;
                if lits[0] == fl {
                    lits.swap(0, 1);
                }
                let first = lits[0];
                if first != w.blocker && self.val[first as usize] == 1 {
                    ws[j] = Watcher { cref: cr, blocker: first };
                    j += 1;
                    continue;
                }
                // Look for a replacement watch that is not false.
                let mut moved = false;
                for k in 2..lits.len() {
                    let l = lits[k];
                    if self.val[l as usize] != -1 {
                        lits.swap(1, k);
                        self.watches[l as usize].push(Watcher { cref: cr, blocker: first });
                        moved = true;
                        break;
                    }
                }
                if moved {
                    continue;
                }
                // No replacement: the clause is unit or conflicting.
                ws[j] = Watcher { cref: cr, blocker: first };
                j += 1;
                if self.val[first as usize] == -1 {
                    confl = Some(cr);
                    self.qhead = self.trail.len();
                    while i < n {
                        ws[j] = ws[i];
                        j += 1;
                        i += 1;
                    }
                    break;
                }
                self.enqueue(first, cr);
            }
            ws.truncate(j);
            self.watches[fl as usize] = ws;
            if confl.is_some() {
                break;
            }
        }
        confl
    }

    // ---- conflict analysis ------------------------------------------------

    fn abstract_level(&self, v: usize) -> u32 {
        1u32 << (self.level[v] & 31)
    }

    /// Checks whether literal `q` (false, in the learnt clause) is implied by
    /// other literals already in the clause; used for clause minimisation.
    fn lit_redundant(&mut self, q: u32, abs: u32, extra: &mut Vec<usize>) -> bool {
        let mut stack = vec![q];
        let top = extra.len();
        while let Some(x) = stack.pop() {
            let xv = (x >> 1) as usize;
            let cr = self.reason[xv] as usize;
            let nl = self.clauses[cr].lits.len();
            for k in 0..nl {
                let r = self.clauses[cr].lits[k];
                let rv = (r >> 1) as usize;
                if rv == xv || self.seen[rv] || self.level[rv] == 0 {
                    continue;
                }
                if self.reason[rv] != NONE && (self.abstract_level(rv) & abs) != 0 {
                    self.seen[rv] = true;
                    stack.push(r);
                    extra.push(rv);
                } else {
                    for &v in &extra[top..] {
                        self.seen[v] = false;
                    }
                    extra.truncate(top);
                    return false;
                }
            }
        }
        true
    }

    /// First-UIP conflict analysis. Returns the learnt clause (asserting literal
    /// first), the backjump level and the clause's LBD.
    fn analyze(&mut self, mut confl: u32) -> (Vec<u32>, u32, u32) {
        let cur = self.decision_level();
        let mut learnt: Vec<u32> = vec![NONE];
        let mut path = 0usize;
        let mut p = NONE;
        let mut idx = self.trail.len();
        loop {
            let nl = self.clauses[confl as usize].lits.len();
            for k in 0..nl {
                let q = self.clauses[confl as usize].lits[k];
                if q == p {
                    continue;
                }
                let v = (q >> 1) as usize;
                if !self.seen[v] && self.level[v] > 0 {
                    self.seen[v] = true;
                    self.bump_var(v);
                    if self.level[v] >= cur {
                        path += 1;
                    } else {
                        learnt.push(q);
                    }
                }
            }
            // Next seen literal on the trail, walking backwards.
            loop {
                idx -= 1;
                if self.seen[(self.trail[idx] >> 1) as usize] {
                    break;
                }
            }
            p = self.trail[idx];
            let pv = (p >> 1) as usize;
            confl = self.reason[pv];
            self.seen[pv] = false;
            path -= 1;
            if path == 0 {
                break;
            }
        }
        learnt[0] = p ^ 1;

        // Recursive minimisation.
        let original = learnt.clone();
        let mut abs = 0u32;
        for &q in &learnt[1..] {
            abs |= self.abstract_level((q >> 1) as usize);
        }
        let mut extra: Vec<usize> = Vec::new();
        let mut j = 1;
        for i in 1..learnt.len() {
            let q = learnt[i];
            let v = (q >> 1) as usize;
            if self.reason[v] == NONE || !self.lit_redundant(q, abs, &mut extra) {
                learnt[j] = q;
                j += 1;
            }
        }
        learnt.truncate(j);

        // Backjump level: the highest level among the other literals, moved to position 1.
        let bt = if learnt.len() == 1 {
            0
        } else {
            let mut mi = 1;
            for i in 2..learnt.len() {
                if self.level[(learnt[i] >> 1) as usize] > self.level[(learnt[mi] >> 1) as usize] {
                    mi = i;
                }
            }
            learnt.swap(1, mi);
            self.level[(learnt[1] >> 1) as usize]
        };

        // LBD: number of distinct decision levels in the clause.
        let mut levels: Vec<u32> = learnt.iter().map(|&q| self.level[(q >> 1) as usize]).collect();
        levels.sort_unstable();
        levels.dedup();
        let lbd = levels.len() as u32;

        for &q in &original {
            self.seen[(q >> 1) as usize] = false;
        }
        for &v in &extra {
            self.seen[v] = false;
        }
        (learnt, bt, lbd)
    }

    // ---- clause database --------------------------------------------------

    /// Deletes roughly half of the learnt clauses (those with high LBD) and
    /// satisfied learnt clauses. Must be called at decision level 0 after a
    /// complete propagation.
    fn reduce_db(&mut self) {
        for k in 0..self.trail.len() {
            let v = (self.trail[k] >> 1) as usize;
            self.reason[v] = NONE;
        }
        let mut cand: Vec<(u32, usize, usize)> = Vec::new();
        for i in 0..self.clauses.len() {
            if !self.clauses[i].learnt {
                continue;
            }
            if self.clauses[i].lits.iter().any(|&l| self.val[l as usize] == 1) {
                self.clauses[i].deleted = true;
                continue;
            }
            if self.clauses[i].lbd > 2 {
                cand.push((self.clauses[i].lbd, self.clauses[i].lits.len(), i));
            }
        }
        cand.sort_unstable_by(|a, b| b.cmp(a));
        for &(_, _, i) in cand.iter().take(cand.len() / 2) {
            self.clauses[i].deleted = true;
        }
        self.clauses.retain(|c| !c.deleted);
        self.num_learnts = self.clauses.iter().filter(|c| c.learnt).count();

        // Rebuild watch lists; the watched positions are unchanged.
        for w in self.watches.iter_mut() {
            w.clear();
        }
        for (i, c) in self.clauses.iter().enumerate() {
            let cr = i as u32;
            let (a, b) = (c.lits[0], c.lits[1]);
            self.watches[a as usize].push(Watcher { cref: cr, blocker: b });
            self.watches[b as usize].push(Watcher { cref: cr, blocker: a });
        }
    }

    // ---- search -----------------------------------------------------------

    /// Returns true if satisfiable (the model is then in `val`), false otherwise.
    fn solve(&mut self) -> bool {
        let mut restarts = 0u64;
        let mut conflicts_at_restart = 0u64;
        loop {
            if let Some(confl) = self.propagate() {
                self.conflicts += 1;
                if self.decision_level() == 0 {
                    return false;
                }
                let (learnt, bt, lbd) = self.analyze(confl);
                self.backtrack(bt);
                if learnt.len() == 1 {
                    self.enqueue(learnt[0], NONE);
                } else {
                    let cr = self.add_clause(learnt, true, lbd);
                    self.num_learnts += 1;
                    let l0 = self.clauses[cr as usize].lits[0];
                    self.enqueue(l0, cr);
                }
                self.var_inc /= 0.95;
            } else {
                let limit = luby(restarts) * 100;
                if self.conflicts - conflicts_at_restart >= limit {
                    restarts += 1;
                    conflicts_at_restart = self.conflicts;
                    self.backtrack(0);
                    if self.num_learnts as f64 >= self.max_learnts {
                        self.reduce_db();
                        self.max_learnts *= 1.1;
                    }
                    continue;
                }
                // Decide on the most active unassigned variable.
                let mut next = None;
                while let Some(v) = self.heap_pop() {
                    if self.val[2 * v as usize] == 0 {
                        next = Some(v);
                        break;
                    }
                }
                match next {
                    None => return true,
                    Some(v) => {
                        let lit = 2 * v + if self.phase[v as usize] { 0 } else { 1 };
                        self.trail_lim.push(self.trail.len());
                        self.enqueue(lit, NONE);
                    }
                }
            }
        }
    }
}

/// Builds the solver from the formula. Returns None if the formula is trivially unsatisfiable.
fn load(nvars: usize, formula: &[Vec<i64>]) -> Option<Solver> {
    let mut s = Solver::new(nvars, formula.len());
    let mut units: Vec<u32> = Vec::new();
    for clause in formula {
        let mut lits: Vec<u32> = clause
            .iter()
            .map(|&x| {
                let v = (x.unsigned_abs() - 1) as u32;
                2 * v + if x < 0 { 1 } else { 0 }
            })
            .collect();
        lits.sort_unstable();
        lits.dedup();
        // Tautology: both `2v` and `2v+1` present (they are adjacent after sorting).
        if lits.windows(2).any(|w| w[0] ^ 1 == w[1]) {
            continue;
        }
        match lits.len() {
            0 => return None,
            1 => units.push(lits[0]),
            _ => {
                s.add_clause(lits, false, 0);
            }
        }
    }
    for lit in units {
        match s.val[lit as usize] {
            -1 => return None,
            0 => s.enqueue(lit, NONE),
            _ => {}
        }
    }
    Some(s)
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: {} FILE", args[0]);
        process::exit(2);
    }
    let bytes = match fs::read(&args[1]) {
        Ok(b) => b,
        Err(e) => {
            eprintln!("c cannot read {}: {}", args[1], e);
            process::exit(1);
        }
    };
    let text = String::from_utf8_lossy(&bytes);

    let mut header_vars = 0usize;
    let mut max_var = 0usize;
    let mut formula: Vec<Vec<i64>> = Vec::new();
    let mut cur: Vec<i64> = Vec::new();
    for line in text.lines() {
        let t = line.trim();
        match t.as_bytes().first() {
            None => continue,
            Some(b'c') => continue,
            Some(b'%') => break, // end-of-file marker used by some benchmark archives
            Some(b'p') => {
                let parts: Vec<&str> = t.split_whitespace().collect();
                if parts.len() >= 3 {
                    header_vars = parts[2].parse().unwrap_or(0);
                }
                continue;
            }
            _ => {}
        }
        for tok in t.split_whitespace() {
            let x: i64 = match tok.parse() {
                Ok(x) => x,
                Err(_) => {
                    eprintln!("c bad token in input: {}", tok);
                    process::exit(1);
                }
            };
            if x == 0 {
                formula.push(std::mem::take(&mut cur));
            } else {
                max_var = max_var.max(x.unsigned_abs() as usize);
                cur.push(x);
            }
        }
    }
    if !cur.is_empty() {
        formula.push(cur);
    }
    let nvars = header_vars.max(max_var);

    let mut out = String::new();
    let result = match load(nvars, &formula) {
        None => None,
        Some(mut s) => {
            if s.solve() {
                Some(s)
            } else {
                None
            }
        }
    };
    match result {
        None => {
            out.push_str("s UNSATISFIABLE\n");
            io::stdout().write_all(out.as_bytes()).ok();
            io::stdout().flush().ok();
            process::exit(20);
        }
        Some(s) => {
            let model: Vec<bool> = (0..nvars).map(|v| s.val[2 * v] == 1).collect();
            // Independent check of the model against the input formula.
            let ok = formula.iter().all(|c| {
                c.iter().any(|&x| {
                    let v = x.unsigned_abs() as usize - 1;
                    model[v] == (x > 0)
                })
            });
            if !ok {
                eprintln!("c internal error: model does not satisfy the formula");
                println!("s UNKNOWN");
                process::exit(1);
            }
            out.push_str("s SATISFIABLE\n");
            let mut line = String::from("v");
            for v in 0..nvars {
                let lit = if model[v] { (v + 1) as i64 } else { -((v + 1) as i64) };
                let tok = lit.to_string();
                if line.len() + tok.len() + 1 > 78 {
                    out.push_str(&line);
                    out.push('\n');
                    line = String::from("v");
                }
                line.push(' ');
                line.push_str(&tok);
            }
            if line.len() + 3 > 78 {
                out.push_str(&line);
                out.push('\n');
                line = String::from("v");
            }
            line.push_str(" 0\n");
            out.push_str(&line);
            io::stdout().write_all(out.as_bytes()).ok();
            io::stdout().flush().ok();
            process::exit(10);
        }
    }
}
