import java.io.*;
import java.nio.file.*;
import java.util.*;

public class Main {
    static final class Clause { int[] lits; boolean learnt, deleted; float act; }
    int nv;
    byte[] assign; int[] level; Clause[] reason; boolean[] seen; boolean[] phase;
    double[] activity; double varInc = 1, varDecay = 0.95;
    float claInc = 1;
    int[] trail; int trailSz = 0, qhead = 0; int[] trailLim; int nLevels = 0;
    Clause[][] watch; int[] wsize;
    int[] heap, heapPos; int heapSz = 0;
    ArrayList<Clause> learnts = new ArrayList<>(), originals = new ArrayList<>();
    boolean ok = true;

    int val(int l) { int a = assign[l >> 1]; return (l & 1) == 0 ? a : -a; }

    void init(int n) {
        nv = n; assign = new byte[n]; level = new int[n]; reason = new Clause[n]; seen = new boolean[n];
        phase = new boolean[n]; activity = new double[n]; trail = new int[n + 1]; trailLim = new int[n + 1];
        watch = new Clause[2 * n][]; wsize = new int[2 * n];
        for (int i = 0; i < 2 * n; i++) watch[i] = new Clause[4];
        heap = new int[n]; heapPos = new int[n];
        for (int i = 0; i < n; i++) { heap[i] = i; heapPos[i] = i; } heapSz = n;
    }
    // heap
    void up(int i) { int x = heap[i]; while (i > 0) { int p = (i - 1) >> 1; if (activity[heap[p]] >= activity[x]) break; heap[i] = heap[p]; heapPos[heap[i]] = i; i = p; } heap[i] = x; heapPos[x] = i; }
    void down(int i) { int x = heap[i]; while (true) { int c = 2 * i + 1; if (c >= heapSz) break; if (c + 1 < heapSz && activity[heap[c + 1]] > activity[heap[c]]) c++; if (activity[heap[c]] <= activity[x]) break; heap[i] = heap[c]; heapPos[heap[i]] = i; i = c; } heap[i] = x; heapPos[x] = i; }
    void heapInsert(int v) { if (heapPos[v] >= 0) return; heap[heapSz] = v; heapPos[v] = heapSz; heapSz++; up(heapSz - 1); }
    int heapPop() { int x = heap[0]; heapSz--; heapPos[x] = -1; if (heapSz > 0) { heap[0] = heap[heapSz]; heapPos[heap[0]] = 0; down(0); } return x; }
    void bumpVar(int v) {
        if ((activity[v] += varInc) > 1e100) { for (int i = 0; i < nv; i++) activity[i] *= 1e-100; varInc *= 1e-100; }
        if (heapPos[v] >= 0) up(heapPos[v]);
    }
    void bumpClause(Clause c) {
        if ((c.act += claInc) > 1e20f) { for (Clause d : learnts) d.act *= 1e-20f; claInc *= 1e-20f; }
    }
    void addWatch(int lit, Clause c) {
        if (wsize[lit] == watch[lit].length) watch[lit] = Arrays.copyOf(watch[lit], wsize[lit] * 2);
        watch[lit][wsize[lit]++] = c;
    }
    void attach(Clause c) { addWatch(c.lits[0], c); addWatch(c.lits[1], c); }
    void enqueue(int l, Clause r) {
        int v = l >> 1; assign[v] = (byte) ((l & 1) == 0 ? 1 : -1); level[v] = nLevels; reason[v] = r; trail[trailSz++] = l;
    }
    boolean addClause(int[] ls) {
        Arrays.sort(ls);
        int[] out = new int[ls.length]; int n = 0; int prev = -1;
        for (int l : ls) {
            if (l == prev) continue;
            if (prev >= 0 && l == (prev ^ 1)) return true;
            prev = l;
            int v = val(l);
            if (v == 1) return true;
            if (v == -1) continue;
            out[n++] = l;
        }
        // tautology check after dedupe: sorted so x and x^1 adjacent (2v,2v+1) handled
        if (n == 0) return false;
        if (n == 1) { enqueue(out[0], null); return true; }
        Clause c = new Clause(); c.lits = Arrays.copyOf(out, n); originals.add(c); attach(c);
        return true;
    }
    Clause propagate() {
        while (qhead < trailSz) {
            int p = trail[qhead++]; int np = p ^ 1;
            Clause[] ws = watch[np]; int n = wsize[np]; int i = 0, j = 0;
            Clause confl = null;
            while (i < n) {
                Clause c = ws[i++];
                if (c.deleted) continue;
                int[] L = c.lits;
                if (L[0] == np) { L[0] = L[1]; L[1] = np; }
                int f = L[0];
                if (val(f) == 1) { ws[j++] = c; continue; }
                boolean found = false;
                for (int k = 2; k < L.length; k++) {
                    if (val(L[k]) != -1) { L[1] = L[k]; L[k] = np; addWatch(L[1], c); found = true; break; }
                }
                if (found) continue;
                ws[j++] = c;
                if (val(f) == -1) {
                    confl = c; qhead = trailSz;
                    while (i < n) ws[j++] = ws[i++];
                } else enqueue(f, c);
            }
            wsize[np] = j;
            if (confl != null) return confl;
        }
        return null;
    }
    void cancelUntil(int lvl) {
        if (nLevels <= lvl) return;
        for (int i = trailSz - 1; i >= trailLim[lvl]; i--) {
            int v = trail[i] >> 1; assign[v] = 0; phase[v] = (trail[i] & 1) == 0; reason[v] = null; heapInsert(v);
        }
        trailSz = trailLim[lvl]; qhead = trailSz; nLevels = lvl;
    }
    int[] learntBuf = new int[16]; int learntN; int btLevel;
    void analyze(Clause confl) {
        learntN = 1; int pathC = 0; int p = -1; int idx = trailSz - 1;
        ensure(1);
        do {
            if (confl.learnt) bumpClause(confl);
            int[] L = confl.lits;
            for (int j = (p == -1 ? 0 : 1); j < L.length; j++) {
                int q = L[j]; int v = q >> 1;
                if (!seen[v] && level[v] > 0) {
                    bumpVar(v); seen[v] = true;
                    if (level[v] >= nLevels) pathC++;
                    else { ensure(learntN + 1); learntBuf[learntN++] = q; }
                }
            }
            while (!seen[trail[idx--] >> 1]) ;
            p = trail[idx + 1]; confl = reason[p >> 1]; seen[p >> 1] = false; pathC--;
        } while (pathC > 0);
        learntBuf[0] = p ^ 1;
        int[] toClear = Arrays.copyOf(learntBuf, learntN);
        int j = 1;
        for (int i = 1; i < learntN; i++) {
            int l = learntBuf[i]; Clause r = reason[l >> 1]; boolean keep = true;
            if (r != null) {
                keep = false;
                for (int k = 1; k < r.lits.length; k++) { int u = r.lits[k] >> 1; if (!seen[u] && level[u] > 0) { keep = true; break; } }
            }
            if (keep) learntBuf[j++] = l;
        }
        learntN = j;
        for (int l : toClear) seen[l >> 1] = false;
        if (learntN == 1) btLevel = 0;
        else {
            int mi = 1;
            for (int i = 2; i < learntN; i++) if (level[learntBuf[i] >> 1] > level[learntBuf[mi] >> 1]) mi = i;
            int t = learntBuf[1]; learntBuf[1] = learntBuf[mi]; learntBuf[mi] = t;
            btLevel = level[learntBuf[1] >> 1];
        }
    }
    void ensure(int n) { if (n > learntBuf.length) learntBuf = Arrays.copyOf(learntBuf, Math.max(n, learntBuf.length * 2)); }

    void reduceDB() {
        learnts.sort((a, b) -> Float.compare(a.act, b.act));
        int half = learnts.size() / 2; ArrayList<Clause> keep = new ArrayList<>();
        for (int i = 0; i < learnts.size(); i++) {
            Clause c = learnts.get(i);
            boolean locked = reason[c.lits[0] >> 1] == c && val(c.lits[0]) == 1;
            if (i < half && c.lits.length > 2 && !locked) c.deleted = true; else keep.add(c);
        }
        learnts = keep;
        for (int l = 0; l < 2 * nv; l++) {
            int j = 0; Clause[] ws = watch[l];
            for (int i = 0; i < wsize[l]; i++) if (!ws[i].deleted) ws[j++] = ws[i];
            for (int i = j; i < wsize[l]; i++) ws[i] = null;
            wsize[l] = j;
        }
    }
    static double luby(double y, int x) {
        int size = 1, seq = 0;
        while (size < x + 1) { seq++; size = 2 * size + 1; }
        while (size - 1 != x) { size = (size - 1) >> 1; seq--; x = x % size; }
        return Math.pow(y, seq);
    }
    // returns 1 sat, -1 unsat, 0 restart
    int search(long budget) {
        long conflicts = 0;
        while (true) {
            Clause confl = propagate();
            if (confl != null) {
                conflicts++;
                if (nLevels == 0) return -1;
                analyze(confl);
                cancelUntil(btLevel);
                if (learntN == 1) enqueue(learntBuf[0], null);
                else {
                    Clause c = new Clause(); c.lits = Arrays.copyOf(learntBuf, learntN); c.learnt = true; bumpClause(c);
                    learnts.add(c); attach(c); enqueue(c.lits[0], c);
                }
                varInc /= varDecay; claInc /= 0.999f;
            } else {
                if (conflicts >= budget) { cancelUntil(0); return 0; }
                if (learnts.size() - trailSz >= maxLearnts) { reduceDB(); maxLearnts *= 1.1; }
                int next = -1;
                while (heapSz > 0) { int v = heapPop(); if (assign[v] == 0) { next = v; break; } }
                if (next < 0) return 1;
                trailLim[nLevels++] = trailSz;
                enqueue(2 * next + (phase[next] ? 0 : 1), null);
            }
        }
    }
    double maxLearnts;
    boolean solve() {
        if (!ok) return false;
        maxLearnts = Math.max(originals.size() / 3.0, 4000);
        for (int i = 0; ; i++) {
            int r = search((long) (luby(2, i) * 100));
            if (r != 0) return r == 1;
        }
    }

    public static void main(String[] args) throws Exception {
        byte[] data = Files.readAllBytes(Paths.get(args[0]));
        int pos = 0, len = data.length;
        int hdrVars = 0;
        ArrayList<int[]> clauses = new ArrayList<>();
        int[] cur = new int[16]; int cn = 0; int maxVar = 0;
        outer:
        while (pos < len) {
            int c = data[pos];
            if (c == ' ' || c == '\n' || c == '\r' || c == '\t') { pos++; continue; }
            if (c == 'c' || c == 'p' || c == '%') {
                int st = pos;
                while (pos < len && data[pos] != '\n') pos++;
                if (c == '%') break outer;
                if (c == 'p') {
                    String[] t = new String(data, st, pos - st).trim().split("\\s+");
                    if (t.length >= 3) hdrVars = Integer.parseInt(t[2]);
                }
                continue;
            }
            boolean neg = false;
            if (c == '-') { neg = true; pos++; } else if (c == '+') pos++;
            int x = 0;
            while (pos < len && data[pos] >= '0' && data[pos] <= '9') x = x * 10 + (data[pos++] - '0');
            if (x == 0) { clauses.add(Arrays.copyOf(cur, cn)); cn = 0; }
            else {
                if (x > maxVar) maxVar = x;
                if (cn == cur.length) cur = Arrays.copyOf(cur, cn * 2);
                cur[cn++] = 2 * (x - 1) + (neg ? 1 : 0);
            }
        }
        if (cn > 0) clauses.add(Arrays.copyOf(cur, cn));
        int n = Math.max(hdrVars, maxVar);
        Main s = new Main(); s.init(n);
        for (int[] cl : clauses) if (!s.addClause(cl)) { s.ok = false; break; }
        boolean sat = s.solve();
        StringBuilder sb = new StringBuilder();
        if (sat) {
            sb.append("s SATISFIABLE\n");
            StringBuilder line = new StringBuilder("v");
            for (int v = 0; v < n; v++) {
                String t = " " + (s.assign[v] >= 0 ? v + 1 : -(v + 1));
                if (line.length() + t.length() > 78) { sb.append(line).append('\n'); line = new StringBuilder("v"); }
                line.append(t);
            }
            line.append(" 0"); sb.append(line).append('\n');
        } else sb.append("s UNSATISFIABLE\n");
        System.out.print(sb); System.out.flush();
        System.exit(sat ? 10 : 20);
    }
}
