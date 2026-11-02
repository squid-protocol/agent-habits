//! A DPLL-style SAT solver with conflict-driven clause learning (CDCL).
//!
//! The search is classic DPLL: decide a literal, propagate units with two watched literals, and
//! backtrack on conflicts. On top of it:
//! - first-UIP conflict analysis with recursive clause minimisation, so each conflict yields a
//!   learnt clause that prunes the search space (this is what makes DPLL practical here);
//! - VSIDS variable activities kept in a binary heap, with phase saving;
//! - Luby restarts;
//! - periodic deletion of learnt clauses ranked by literal block distance (LBD).
//!
//! Literal encoding: variable `v` (0-based) has the positive literal `2v` and the negative
//! literal `2v + 1`, so negation is `lit ^ 1`.

pub type Lit = u32;

const NO_REASON: u32 = u32::MAX;
const RESTART_BASE: u64 = 100;
const FIRST_REDUCE: u64 = 2000;
const REDUCE_INC: u64 = 300;

#[derive(Clone, Copy)]
struct Watcher {
    cref: u32,
    /// A literal of the clause; if it is true the clause is satisfied and need not be visited.
    blocker: Lit,
}

struct Clause {
    lits: Vec<Lit>,
    learnt: bool,
    lbd: u32,
    deleted: bool,
}

/// Max-heap of variables ordered by activity, supporting increase-key.
struct VarHeap {
    heap: Vec<u32>,
    /// Position of each variable in `heap`, or -1 if absent.
    pos: Vec<i32>,
}

impl VarHeap {
    fn new(n: usize) -> Self {
        VarHeap { heap: Vec::with_capacity(n), pos: vec![-1; n] }
    }

    fn contains(&self, v: usize) -> bool {
        self.pos[v] >= 0
    }

    fn insert(&mut self, v: usize, act: &[f64]) {
        if self.contains(v) {
            return;
        }
        self.pos[v] = self.heap.len() as i32;
        self.heap.push(v as u32);
        self.sift_up(self.heap.len() - 1, act);
    }

    fn sift_up(&mut self, mut i: usize, act: &[f64]) {
        let v = self.heap[i];
        while i > 0 {
            let parent = (i - 1) / 2;
            let pv = self.heap[parent];
            if act[pv as usize] >= act[v as usize] {
                break;
            }
            self.heap[i] = pv;
            self.pos[pv as usize] = i as i32;
            i = parent;
        }
        self.heap[i] = v;
        self.pos[v as usize] = i as i32;
    }

    fn sift_down(&mut self, mut i: usize, act: &[f64]) {
        let v = self.heap[i];
        let n = self.heap.len();
        loop {
            let l = 2 * i + 1;
            if l >= n {
                break;
            }
            let r = l + 1;
            let c = if r < n && act[self.heap[r] as usize] > act[self.heap[l] as usize] { r } else { l };
            let cv = self.heap[c];
            if act[cv as usize] <= act[v as usize] {
                break;
            }
            self.heap[i] = cv;
            self.pos[cv as usize] = i as i32;
            i = c;
        }
        self.heap[i] = v;
        self.pos[v as usize] = i as i32;
    }

    fn pop(&mut self, act: &[f64]) -> Option<usize> {
        if self.heap.is_empty() {
            return None;
        }
        let top = self.heap[0];
        let last = self.heap.pop().expect("heap is non-empty");
        self.pos[top as usize] = -1;
        if !self.heap.is_empty() {
            self.heap[0] = last;
            self.pos[last as usize] = 0;
            self.sift_down(0, act);
        }
        Some(top as usize)
    }
}

pub struct Solver {
    clauses: Vec<Clause>,
    /// `watches[l]` holds the clauses in which literal `l` is one of the two watched literals.
    watches: Vec<Vec<Watcher>>,
    /// Truth value of each literal: 1 true, -1 false, 0 unassigned.
    lit_val: Vec<i8>,
    level: Vec<u32>,
    reason: Vec<u32>,
    trail: Vec<Lit>,
    trail_lim: Vec<usize>,
    qhead: usize,
    activity: Vec<f64>,
    var_inc: f64,
    /// Saved phase: `true` means the last value assigned to the variable was positive.
    phase: Vec<bool>,
    heap: VarHeap,
    seen: Vec<bool>,
    level_stamp: Vec<u64>,
    stamp: u64,
    conflicts: u64,
    next_reduce: u64,
    reduce_count: u64,
}

/// Luby sequence (1, 1, 2, 1, 1, 2, 4, ...), 1-based.
fn luby(i: u64) -> u64 {
    let mut k = 1u32;
    while (1u64 << k) - 1 < i {
        k += 1;
    }
    if (1u64 << k) - 1 == i {
        1u64 << (k - 1)
    } else {
        luby(i - (1u64 << (k - 1)) + 1)
    }
}

/// Convert a DIMACS literal (non-zero) into the internal encoding.
fn to_lit(x: i32) -> Lit {
    let v = x.unsigned_abs() - 1;
    2 * v + u32::from(x < 0)
}

impl Solver {
    pub fn new(nvars: usize) -> Self {
        let mut heap = VarHeap::new(nvars);
        let activity = vec![0.0; nvars];
        for v in 0..nvars {
            heap.insert(v, &activity);
        }
        Solver {
            clauses: Vec::new(),
            watches: vec![Vec::new(); 2 * nvars],
            lit_val: vec![0; 2 * nvars],
            level: vec![0; nvars],
            reason: vec![NO_REASON; nvars],
            trail: Vec::with_capacity(nvars),
            trail_lim: Vec::new(),
            qhead: 0,
            activity,
            var_inc: 1.0,
            phase: vec![false; nvars],
            heap,
            seen: vec![false; nvars],
            level_stamp: vec![0; nvars + 2],
            stamp: 0,
            conflicts: 0,
            next_reduce: FIRST_REDUCE,
            reduce_count: 0,
        }
    }

    #[inline]
    fn decision_level(&self) -> u32 {
        self.trail_lim.len() as u32
    }

    /// Assign `l` true at the current level. The caller guarantees `l` is unassigned.
    #[inline]
    fn enqueue(&mut self, l: Lit, reason: u32) {
        let v = (l >> 1) as usize;
        self.lit_val[l as usize] = 1;
        self.lit_val[(l ^ 1) as usize] = -1;
        self.level[v] = self.decision_level();
        self.reason[v] = reason;
        self.trail.push(l);
    }

    /// Add an input clause at decision level 0. Returns `false` if the formula is now trivially
    /// unsatisfiable. Units are enqueued but not propagated; `solve` propagates them.
    fn add_input(&mut self, dimacs: &[i32]) -> bool {
        let mut lits: Vec<Lit> = dimacs.iter().map(|&x| to_lit(x)).collect();
        lits.sort_unstable();
        lits.dedup();
        // Tautology: sorted literals of one variable are adjacent (2v, 2v+1).
        if lits.windows(2).any(|w| w[0] ^ 1 == w[1]) {
            return true;
        }
        // Drop literals already false at level 0; a literal already true satisfies the clause.
        let mut kept = Vec::with_capacity(lits.len());
        for l in lits {
            match self.lit_val[l as usize] {
                1 => return true,
                -1 => {}
                _ => kept.push(l),
            }
        }
        match kept.len() {
            0 => false,
            1 => {
                self.enqueue(kept[0], NO_REASON);
                true
            }
            _ => {
                self.add_clause(kept, false, 0);
                true
            }
        }
    }

    fn add_clause(&mut self, lits: Vec<Lit>, learnt: bool, lbd: u32) -> u32 {
        let cref = self.clauses.len() as u32;
        self.watches[lits[0] as usize].push(Watcher { cref, blocker: lits[1] });
        self.watches[lits[1] as usize].push(Watcher { cref, blocker: lits[0] });
        self.clauses.push(Clause { lits, learnt, lbd, deleted: false });
        cref
    }

    /// Unit propagation with two watched literals. Returns a conflicting clause, if any.
    fn propagate(&mut self) -> Option<u32> {
        let mut confl = None;
        while self.qhead < self.trail.len() {
            let p = self.trail[self.qhead];
            self.qhead += 1;
            let false_lit = p ^ 1;
            // Visit the clauses watching `false_lit`, which has just become false.
            let mut ws = std::mem::take(&mut self.watches[false_lit as usize]);
            let len = ws.len();
            let mut i = 0;
            let mut j = 0;
            while i < len {
                let w = ws[i];
                i += 1;
                if self.lit_val[w.blocker as usize] == 1 {
                    ws[j] = w;
                    j += 1;
                    continue;
                }
                let lits = &mut self.clauses[w.cref as usize].lits;
                if lits[0] == false_lit {
                    lits.swap(0, 1);
                }
                let first = lits[0];
                if first != w.blocker && self.lit_val[first as usize] == 1 {
                    ws[j] = Watcher { cref: w.cref, blocker: first };
                    j += 1;
                    continue;
                }
                // Look for a replacement watch that is not false.
                let mut moved = false;
                for k in 2..lits.len() {
                    let lk = lits[k];
                    if self.lit_val[lk as usize] != -1 {
                        lits.swap(1, k);
                        self.watches[lk as usize].push(Watcher { cref: w.cref, blocker: first });
                        moved = true;
                        break;
                    }
                }
                if moved {
                    continue;
                }
                // No replacement: the clause is unit on `first`, or conflicting.
                ws[j] = Watcher { cref: w.cref, blocker: first };
                j += 1;
                if self.lit_val[first as usize] == -1 {
                    confl = Some(w.cref);
                    while i < len {
                        ws[j] = ws[i];
                        j += 1;
                        i += 1;
                    }
                    break;
                }
                self.enqueue(first, w.cref);
            }
            ws.truncate(j);
            self.watches[false_lit as usize] = ws;
            if confl.is_some() {
                self.qhead = self.trail.len();
                break;
            }
        }
        confl
    }

    fn bump_var(&mut self, v: usize) {
        self.activity[v] += self.var_inc;
        if self.activity[v] > 1e100 {
            for a in self.activity.iter_mut() {
                *a *= 1e-100;
            }
            self.var_inc *= 1e-100;
        }
        if self.heap.contains(v) {
            self.heap.sift_up(self.heap.pos[v] as usize, &self.activity);
        }
    }

    /// First-UIP conflict analysis. Returns the learnt clause (asserting literal first, a literal
    /// of the backjump level second), the backjump level and the clause LBD.
    fn analyze(&mut self, mut confl: u32) -> (Vec<Lit>, u32, u32) {
        let cur = self.decision_level();
        let mut learnt: Vec<Lit> = vec![0];
        let mut path_c = 0usize;
        let mut index = self.trail.len();
        let mut p: Lit;
        let mut first = true;
        loop {
            // For a reason clause, lits[0] is the implied literal `p` itself, which we skip.
            let start = if first { 0 } else { 1 };
            first = false;
            let n = self.clauses[confl as usize].lits.len();
            for k in start..n {
                let q = self.clauses[confl as usize].lits[k];
                let v = (q >> 1) as usize;
                if !self.seen[v] && self.level[v] > 0 {
                    self.seen[v] = true;
                    self.bump_var(v);
                    if self.level[v] >= cur {
                        path_c += 1;
                    } else {
                        learnt.push(q);
                    }
                }
            }
            // Next seen literal on the trail (walking backwards).
            loop {
                index -= 1;
                if self.seen[(self.trail[index] >> 1) as usize] {
                    break;
                }
            }
            p = self.trail[index];
            let pv = (p >> 1) as usize;
            confl = self.reason[pv];
            self.seen[pv] = false;
            path_c -= 1;
            if path_c == 0 {
                break;
            }
        }
        learnt[0] = p ^ 1;

        // Recursive minimisation: drop literals implied by the rest of the clause.
        let mut toclear: Vec<Lit> = learnt.clone();
        let mut abs_levels = 0u32;
        for &l in &learnt[1..] {
            abs_levels |= 1u32 << (self.level[(l >> 1) as usize] & 31);
        }
        let mut stack = Vec::new();
        let mut j = 1;
        for i in 1..learnt.len() {
            let l = learnt[i];
            let v = (l >> 1) as usize;
            if self.reason[v] == NO_REASON || !self.lit_redundant(l, abs_levels, &mut stack, &mut toclear) {
                learnt[j] = l;
                j += 1;
            }
        }
        learnt.truncate(j);
        for &l in &toclear {
            self.seen[(l >> 1) as usize] = false;
        }

        // LBD: number of distinct decision levels in the clause.
        self.stamp += 1;
        let mut lbd = 0u32;
        for &l in &learnt {
            let lv = self.level[(l >> 1) as usize] as usize;
            if self.level_stamp[lv] != self.stamp {
                self.level_stamp[lv] = self.stamp;
                lbd += 1;
            }
        }

        // Backjump level: the highest level among the non-asserting literals, moved to position 1.
        let bt = if learnt.len() == 1 {
            0
        } else {
            let mut max_i = 1;
            for i in 2..learnt.len() {
                if self.level[(learnt[i] >> 1) as usize] > self.level[(learnt[max_i] >> 1) as usize] {
                    max_i = i;
                }
            }
            learnt.swap(1, max_i);
            self.level[(learnt[1] >> 1) as usize]
        };
        (learnt, bt, lbd)
    }

    /// Is literal `p` (false, in the learnt clause) implied by other literals already in the clause
    /// (marked `seen`) or by level-0 facts? Literals proven redundant are marked and recorded in
    /// `toclear`; on failure, the marks added by this call are undone.
    fn lit_redundant(&mut self, p: Lit, abs_levels: u32, stack: &mut Vec<Lit>, toclear: &mut Vec<Lit>) -> bool {
        stack.clear();
        stack.push(p);
        let top = toclear.len();
        while let Some(q) = stack.pop() {
            let cr = self.reason[(q >> 1) as usize] as usize;
            let n = self.clauses[cr].lits.len();
            for k in 1..n {
                let l = self.clauses[cr].lits[k];
                let v = (l >> 1) as usize;
                if self.seen[v] || self.level[v] == 0 {
                    continue;
                }
                if self.reason[v] != NO_REASON && (1u32 << (self.level[v] & 31)) & abs_levels != 0 {
                    self.seen[v] = true;
                    stack.push(l);
                    toclear.push(l);
                } else {
                    for t in top..toclear.len() {
                        self.seen[(toclear[t] >> 1) as usize] = false;
                    }
                    toclear.truncate(top);
                    return false;
                }
            }
        }
        true
    }

    fn backtrack(&mut self, lvl: u32) {
        if self.decision_level() <= lvl {
            return;
        }
        let lim = self.trail_lim[lvl as usize];
        for i in (lim..self.trail.len()).rev() {
            let l = self.trail[i];
            let v = (l >> 1) as usize;
            self.lit_val[l as usize] = 0;
            self.lit_val[(l ^ 1) as usize] = 0;
            self.reason[v] = NO_REASON;
            self.phase[v] = l & 1 == 0;
            self.heap.insert(v, &self.activity);
        }
        self.trail.truncate(lim);
        self.trail_lim.truncate(lvl as usize);
        self.qhead = self.trail.len();
    }

    /// Delete the less useful half of the learnt clauses (keeping glue clauses with LBD <= 2 and
    /// binary clauses), then compact the clause store and rebuild the watch lists.
    /// Must be called at decision level 0 after propagation has completed.
    fn reduce_db(&mut self) {
        // Level-0 reasons are never inspected by analysis; clear them so no reason index dangles.
        for &l in &self.trail {
            self.reason[(l >> 1) as usize] = NO_REASON;
        }
        let mut cands: Vec<usize> = (0..self.clauses.len())
            .filter(|&i| {
                let c = &self.clauses[i];
                c.learnt && !c.deleted && c.lbd > 2 && c.lits.len() > 2
            })
            .collect();
        cands.sort_unstable_by(|&a, &b| {
            let (ca, cb) = (&self.clauses[a], &self.clauses[b]);
            (cb.lbd, cb.lits.len()).cmp(&(ca.lbd, ca.lits.len()))
        });
        for &i in &cands[..cands.len() / 2] {
            self.clauses[i].deleted = true;
        }
        self.clauses.retain(|c| !c.deleted);
        for ws in self.watches.iter_mut() {
            ws.clear();
        }
        for cref in 0..self.clauses.len() {
            let (w0, w1) = (self.clauses[cref].lits[0], self.clauses[cref].lits[1]);
            self.watches[w0 as usize].push(Watcher { cref: cref as u32, blocker: w1 });
            self.watches[w1 as usize].push(Watcher { cref: cref as u32, blocker: w0 });
        }
        self.reduce_count += 1;
        self.next_reduce = self.conflicts + FIRST_REDUCE + REDUCE_INC * self.reduce_count;
    }

    fn pick_branch(&mut self) -> Option<Lit> {
        while let Some(v) = self.heap.pop(&self.activity) {
            if self.lit_val[2 * v] == 0 {
                return Some(2 * v as u32 + u32::from(!self.phase[v]));
            }
        }
        None
    }

    /// Run the search. Returns `true` if satisfiable (the assignment is then in `lit_val`).
    fn search(&mut self) -> bool {
        if self.propagate().is_some() {
            return false;
        }
        let mut restarts = 0u64;
        let mut conflicts_since_restart = 0u64;
        let mut restart_limit = RESTART_BASE * luby(1);
        loop {
            if let Some(confl) = self.propagate() {
                self.conflicts += 1;
                conflicts_since_restart += 1;
                if self.decision_level() == 0 {
                    return false;
                }
                let (learnt, bt, lbd) = self.analyze(confl);
                self.backtrack(bt);
                if learnt.len() == 1 {
                    self.enqueue(learnt[0], NO_REASON);
                } else {
                    let first = learnt[0];
                    let cref = self.add_clause(learnt, true, lbd);
                    self.enqueue(first, cref);
                }
                self.var_inc /= 0.95;
            } else {
                if conflicts_since_restart >= restart_limit {
                    restarts += 1;
                    conflicts_since_restart = 0;
                    restart_limit = RESTART_BASE * luby(restarts + 1);
                    self.backtrack(0);
                    continue;
                }
                if self.conflicts >= self.next_reduce {
                    self.backtrack(0);
                    self.reduce_db();
                    continue;
                }
                match self.pick_branch() {
                    None => return true,
                    Some(l) => {
                        self.trail_lim.push(self.trail.len());
                        self.enqueue(l, NO_REASON);
                    }
                }
            }
        }
    }
}

/// Decide the formula. Returns `Some(model)` (indexed by 0-based variable) if satisfiable, or
/// `None` if unsatisfiable. Clauses use DIMACS literals and must only mention variables in
/// `1..=nvars`.
pub fn solve(nvars: usize, clauses: &[Vec<i32>]) -> Option<Vec<bool>> {
    let mut s = Solver::new(nvars);
    for c in clauses {
        if !s.add_input(c) {
            return None;
        }
    }
    if !s.search() {
        return None;
    }
    Some((0..nvars).map(|v| s.lit_val[2 * v] == 1).collect())
}
