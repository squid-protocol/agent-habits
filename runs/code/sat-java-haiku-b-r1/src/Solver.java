import java.io.IOException;
import java.io.PrintStream;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.List;

/**
 * A DPLL-based SAT solver in the conflict-driven style (CDCL): unit propagation with two watched literals,
 * backtracking search with 1UIP clause learning, VSIDS branching with phase saving, LBD-based restarts and
 * LBD-based deletion of learned clauses. A short WalkSAT-style local search runs first; its models are
 * re-verified before being reported.
 *
 * Usage: solver FILE   (DIMACS CNF)
 * Output: "s SATISFIABLE" + "v ..." lines, exit 10; "s UNSATISFIABLE", exit 20.
 *
 * Literal encoding: variable v (0-based) has positive literal 2v and negative literal 2v+1; negation is lit ^ 1.
 */
public final class Solver {

    static final int EXIT_SAT = 10;
    static final int EXIT_UNSAT = 20;

    private final int nVars;

    // Clause storage. Index = clause id. Deleted learned clauses have deleted[c] = true and clauses[c] = null.
    private int[][] clauses;
    private boolean[] learnt;
    private int[] lbdOf;
    private boolean[] deleted;
    private int nClauses;

    // Assignment state.
    private final byte[] litVal;   // 1 true, -1 false, 0 unassigned (indexed by literal)
    private final int[] level;     // decision level of each variable
    private final int[] reason;    // clause id that implied the variable, -1 for decisions and units
    private final int[] trail;
    private int trailSize;
    private int qhead;
    private final int[] trailLim;  // trail index where each decision level starts
    private int decisionLevel;
    private final boolean[] phase; // last assigned value of each variable (phase saving)

    // Watch lists, indexed by literal: clauses in which the literal is one of the two watched literals.
    private int[][] watches;
    private int[] watchSize;

    // VSIDS activity and a max-heap of unassigned candidate variables.
    private final double[] activity;
    private double varInc = 1.0;
    private static final double VAR_DECAY = 0.95;
    private static final long LOCAL_SEARCH_FLIPS = 5_000_000L;
    private final int[] heap;
    private final int[] heapPos;
    private int heapSize;

    // Conflict analysis scratch space.
    private final boolean[] seen;
    private final int[] toClear;
    private int nToClear;
    private final int[] learntBuf;
    private int learntSize;
    private final int[] levelStamp;
    private int stamp;

    private boolean unsatAtRoot;
    private final List<int[]> allClauses = new ArrayList<>(); // deduplicated input clauses, units included
    private boolean[] model;                                  // set when local search finds a model

    private long conflicts;
    private double emaFast = 0, emaSlow = 0; // moving averages of learned-clause LBD (Glucose-style restarts)

    Solver(int nVars, List<int[]> inputClauses) {
        this.nVars = nVars;
        int nLits = 2 * nVars;
        clauses = new int[1024][];
        learnt = new boolean[1024];
        lbdOf = new int[1024];
        deleted = new boolean[1024];
        litVal = new byte[nLits];
        level = new int[nVars];
        reason = new int[nVars];
        Arrays.fill(reason, -1);
        trail = new int[nVars];
        trailLim = new int[nVars + 1];
        phase = new boolean[nVars];
        watches = new int[nLits][];
        watchSize = new int[nLits];
        for (int l = 0; l < nLits; l++) watches[l] = new int[4];
        activity = new double[nVars];
        heap = new int[nVars];
        heapPos = new int[nVars];
        seen = new boolean[nVars];
        toClear = new int[nVars];
        learntBuf = new int[nVars + 1];
        levelStamp = new int[nVars + 2];
        for (int v = 0; v < nVars; v++) {
            heap[v] = v;
            heapPos[v] = v;
        }
        heapSize = nVars;

        boolean[] mark = new boolean[nLits];
        List<Integer> units = new ArrayList<>();
        for (int[] raw : inputClauses) {
            // Remove duplicate literals; drop tautologies.
            int[] lits = new int[raw.length];
            int len = 0;
            boolean taut = false;
            for (int l : raw) {
                if (mark[l ^ 1]) { taut = true; break; }
                if (!mark[l]) { mark[l] = true; lits[len++] = l; }
            }
            for (int i = 0; i < len; i++) mark[lits[i]] = false; // marks are only ever set on lits[0..len)
            if (taut) continue;
            if (len == 0) {
                unsatAtRoot = true;
                continue;
            }
            allClauses.add(Arrays.copyOf(lits, len));
            if (len == 1) {
                units.add(lits[0]);
            } else {
                addClause(Arrays.copyOf(lits, len), false, 0);
            }
        }
        // Watches are installed before any assignment exists, so every clause starts with valid watches.
        for (int l : units) {
            if (litVal[l] == 1) continue;
            if (litVal[l] == -1) { unsatAtRoot = true; break; }
            enqueue(l, -1);
        }
    }

    /** Stores a clause and installs watches on its first two literals. Returns the clause id. */
    private int addClause(int[] lits, boolean isLearnt, int lbd) {
        if (nClauses == clauses.length) {
            int cap = nClauses * 2;
            clauses = Arrays.copyOf(clauses, cap);
            learnt = Arrays.copyOf(learnt, cap);
            lbdOf = Arrays.copyOf(lbdOf, cap);
            deleted = Arrays.copyOf(deleted, cap);
        }
        int c = nClauses++;
        clauses[c] = lits;
        learnt[c] = isLearnt;
        lbdOf[c] = lbd;
        deleted[c] = false;
        addWatch(lits[0], c);
        addWatch(lits[1], c);
        return c;
    }

    private void addWatch(int lit, int c) {
        int[] ws = watches[lit];
        int s = watchSize[lit];
        if (s == ws.length) {
            ws = Arrays.copyOf(ws, s * 2);
            watches[lit] = ws;
        }
        ws[s] = c;
        watchSize[lit] = s + 1;
    }

    private void enqueue(int lit, int r) {
        int v = lit >> 1;
        litVal[lit] = 1;
        litVal[lit ^ 1] = -1;
        level[v] = decisionLevel;
        reason[v] = r;
        trail[trailSize++] = lit;
    }

    /** Unit propagation with two watched literals. Returns a conflicting clause id, or -1. */
    private int propagate() {
        while (qhead < trailSize) {
            int p = trail[qhead++];
            int falseLit = p ^ 1;
            int[] ws = watches[falseLit];
            int n = watchSize[falseLit];
            int i = 0, j = 0;
            while (i < n) {
                int c = ws[i++];
                if (deleted[c]) continue; // lazily drop watches of deleted clauses
                int[] C = clauses[c];
                if (C[0] == falseLit) {
                    C[0] = C[1];
                    C[1] = falseLit;
                }
                int first = C[0];
                if (litVal[first] == 1) {
                    ws[j++] = c;
                    continue;
                }
                boolean moved = false;
                for (int k = 2; k < C.length; k++) {
                    int l = C[k];
                    if (litVal[l] != -1) {
                        C[1] = l;
                        C[k] = falseLit;
                        addWatch(l, c); // l != falseLit, so ws is not affected
                        moved = true;
                        break;
                    }
                }
                if (moved) continue;
                ws[j++] = c;
                if (litVal[first] == -1) {
                    while (i < n) ws[j++] = ws[i++];
                    watchSize[falseLit] = j;
                    qhead = trailSize;
                    return c;
                }
                enqueue(first, c);
            }
            watchSize[falseLit] = j;
        }
        return -1;
    }

    /** 1UIP conflict analysis. Fills learntBuf[0..learntSize) with the asserting clause; returns backtrack level. */
    private int analyze(int confl) {
        int pathC = 0;
        int p = -1;
        int idx = trailSize - 1;
        learntSize = 1; // slot 0 reserved for the asserting literal
        nToClear = 0;
        int c = confl;
        do {
            int[] C = clauses[c];
            int start = (p == -1) ? 0 : 1; // for a reason clause, C[0] is the implied literal p itself
            for (int k = start; k < C.length; k++) {
                int q = C[k];
                int v = q >> 1;
                if (!seen[v] && level[v] > 0) {
                    seen[v] = true;
                    toClear[nToClear++] = v;
                    bumpVar(v);
                    if (level[v] >= decisionLevel) pathC++;
                    else learntBuf[learntSize++] = q;
                }
            }
            while (!seen[trail[idx] >> 1]) idx--;
            p = trail[idx];
            idx--;
            c = reason[p >> 1];
            seen[p >> 1] = false;
            pathC--;
        } while (pathC > 0);
        learntBuf[0] = p ^ 1;

        // Local minimization: drop literals whose reason is subsumed by the learned clause.
        int j = 1;
        for (int i = 1; i < learntSize; i++) {
            int q = learntBuf[i];
            int r = reason[q >> 1];
            boolean redundant = false;
            if (r != -1) {
                redundant = true;
                int[] R = clauses[r];
                for (int k = 1; k < R.length; k++) {
                    int v = R[k] >> 1;
                    if (!seen[v] && level[v] > 0) {
                        redundant = false;
                        break;
                    }
                }
            }
            if (!redundant) learntBuf[j++] = q;
        }
        learntSize = j;

        for (int i = 0; i < nToClear; i++) seen[toClear[i]] = false;

        int btLevel = 0;
        if (learntSize > 1) {
            int maxI = 1;
            for (int i = 2; i < learntSize; i++) {
                if (level[learntBuf[i] >> 1] > level[learntBuf[maxI] >> 1]) maxI = i;
            }
            int tmp = learntBuf[1];
            learntBuf[1] = learntBuf[maxI];
            learntBuf[maxI] = tmp;
            btLevel = level[learntBuf[1] >> 1];
        }
        return btLevel;
    }

    /** Literal block distance of learntBuf[0..learntSize): number of distinct decision levels. */
    private int computeLbd() {
        stamp++;
        int lbd = 0;
        for (int i = 0; i < learntSize; i++) {
            int lv = level[learntBuf[i] >> 1];
            if (levelStamp[lv] != stamp) {
                levelStamp[lv] = stamp;
                lbd++;
            }
        }
        return lbd;
    }

    private void cancelUntil(int lvl) {
        if (decisionLevel <= lvl) return;
        for (int i = trailSize - 1; i >= trailLim[lvl]; i--) {
            int lit = trail[i];
            int v = lit >> 1;
            phase[v] = (lit & 1) == 0;
            litVal[lit] = 0;
            litVal[lit ^ 1] = 0;
            if (heapPos[v] < 0) heapInsert(v);
        }
        trailSize = trailLim[lvl];
        qhead = trailSize;
        decisionLevel = lvl;
    }

    private void bumpVar(int v) {
        activity[v] += varInc;
        if (activity[v] > 1e100) {
            for (int u = 0; u < nVars; u++) activity[u] *= 1e-100;
            varInc *= 1e-100;
        }
        if (heapPos[v] >= 0) heapUp(heapPos[v]);
    }

    private void heapUp(int i) {
        int v = heap[i];
        while (i > 0) {
            int p = (i - 1) >> 1;
            if (activity[heap[p]] >= activity[v]) break;
            heap[i] = heap[p];
            heapPos[heap[i]] = i;
            i = p;
        }
        heap[i] = v;
        heapPos[v] = i;
    }

    private void heapDown(int i) {
        int v = heap[i];
        while (true) {
            int l = 2 * i + 1;
            if (l >= heapSize) break;
            int r = l + 1;
            int ch = (r < heapSize && activity[heap[r]] > activity[heap[l]]) ? r : l;
            if (activity[heap[ch]] <= activity[v]) break;
            heap[i] = heap[ch];
            heapPos[heap[i]] = i;
            i = ch;
        }
        heap[i] = v;
        heapPos[v] = i;
    }

    private void heapInsert(int v) {
        heap[heapSize] = v;
        heapPos[v] = heapSize;
        heapSize++;
        heapUp(heapSize - 1);
    }

    private int heapRemoveMax() {
        int top = heap[0];
        heapPos[top] = -1;
        heapSize--;
        if (heapSize > 0) {
            heap[0] = heap[heapSize];
            heapPos[heap[0]] = 0;
            heapDown(0);
        }
        return top;
    }

    /** Next decision literal, or -1 when every variable is assigned. */
    private int pickBranchLit() {
        while (heapSize > 0) {
            int v = heapRemoveMax();
            if (litVal[2 * v] == 0) return phase[v] ? 2 * v : 2 * v + 1;
        }
        return -1;
    }

    /** True if clause c is the reason for a current assignment (it must not be deleted). */
    private boolean locked(int c) {
        int first = clauses[c][0];
        return litVal[first] == 1 && reason[first >> 1] == c;
    }

    /** Deletes roughly half of the learned clauses with LBD > 2 that are not reasons. */
    private void reduceDB() {
        List<Integer> cand = new ArrayList<>();
        for (int c = 0; c < nClauses; c++) {
            if (learnt[c] && !deleted[c] && lbdOf[c] > 2 && clauses[c].length > 2 && !locked(c)) cand.add(c);
        }
        cand.sort(Comparator
                .comparingInt((Integer c) -> lbdOf[c]).reversed()
                .thenComparing(c -> clauses[c].length, Comparator.reverseOrder()));
        int toDelete = cand.size() / 2;
        for (int i = 0; i < toDelete; i++) {
            int c = cand.get(i);
            deleted[c] = true;
            clauses[c] = null;
        }
    }

    /**
     * WalkSAT-style stochastic local search over allClauses, limited to maxFlips flips.
     * Returns a satisfying assignment or null. The caller re-verifies the result.
     */
    private boolean[] localSearch(long maxFlips, long seed) {
        int m = allClauses.size();
        int[][] cls = allClauses.toArray(new int[0][]);
        int nLits = 2 * nVars;
        int[] occCnt = new int[nLits];
        for (int[] C : cls) for (int l : C) occCnt[l]++;
        int[][] occ = new int[nLits][];
        for (int l = 0; l < nLits; l++) occ[l] = new int[occCnt[l]];
        int[] fill = new int[nLits];
        for (int c = 0; c < m; c++) for (int l : cls[c]) occ[l][fill[l]++] = c;

        java.util.Random rnd = new java.util.Random(seed);
        boolean[] a = new boolean[nVars];
        for (int v = 0; v < nVars; v++) a[v] = rnd.nextBoolean();
        int[] numTrue = new int[m];
        int[] unsat = new int[m];
        int[] pos = new int[m];
        int nUnsat = 0;
        for (int c = 0; c < m; c++) {
            for (int l : cls[c]) if (a[l >> 1] == ((l & 1) == 0)) numTrue[c]++;
            pos[c] = -1;
            if (numTrue[c] == 0) {
                pos[c] = nUnsat;
                unsat[nUnsat++] = c;
            }
        }

        for (long flip = 0; ; flip++) {
            if (nUnsat == 0) return a;
            if (flip >= maxFlips) return null;
            int c = unsat[rnd.nextInt(nUnsat)];
            int[] C = cls[c];
            int pick = -1;
            int bestBreak = Integer.MAX_VALUE;
            int ties = 0;
            for (int l : C) {
                int v = l >> 1;
                int trueLit = a[v] ? 2 * v : 2 * v + 1;
                int brk = 0;
                for (int d : occ[trueLit]) if (numTrue[d] == 1) brk++;
                if (brk < bestBreak) {
                    bestBreak = brk;
                    pick = v;
                    ties = 1;
                } else if (brk == bestBreak && rnd.nextInt(++ties) == 0) {
                    pick = v;
                }
                if (brk == 0) break;
            }
            if (bestBreak > 0 && rnd.nextDouble() < 0.5) pick = C[rnd.nextInt(C.length)] >> 1;

            // flip(pick)
            a[pick] = !a[pick];
            int newTrue = a[pick] ? 2 * pick : 2 * pick + 1;
            for (int d : occ[newTrue]) {
                if (numTrue[d]++ == 0) {
                    int idx = pos[d];
                    int last = unsat[--nUnsat];
                    unsat[idx] = last;
                    pos[last] = idx;
                    pos[d] = -1;
                }
            }
            for (int d : occ[newTrue ^ 1]) {
                if (--numTrue[d] == 0) {
                    pos[d] = nUnsat;
                    unsat[nUnsat++] = d;
                }
            }
        }
    }

    private boolean satisfiesAll(boolean[] a) {
        for (int[] C : allClauses) {
            boolean sat = false;
            for (int l : C) {
                if (a[l >> 1] == ((l & 1) == 0)) { sat = true; break; }
            }
            if (!sat) return false;
        }
        return true;
    }

    /** Returns EXIT_SAT or EXIT_UNSAT. */
    int solve() {
        if (unsatAtRoot) return EXIT_UNSAT;
        boolean[] found = localSearch(LOCAL_SEARCH_FLIPS, 12345);
        if (found != null && satisfiesAll(found)) {
            model = found;
            return EXIT_SAT;
        }
        if (propagate() != -1) return EXIT_UNSAT;

        long conflictsAtRestart = 0;
        long nextReduce = 2000;
        int reduces = 0;

        while (true) {
            int confl = propagate();
            if (confl != -1) {
                conflicts++;
                if (decisionLevel == 0) return EXIT_UNSAT;
                int bt = analyze(confl);
                int lbd = computeLbd();
                emaFast += 0.03 * (lbd - emaFast);
                emaSlow += 0.0001 * (lbd - emaSlow);
                cancelUntil(bt);
                if (learntSize == 1) {
                    enqueue(learntBuf[0], -1);
                } else {
                    int[] lits = Arrays.copyOf(learntBuf, learntSize);
                    int c = addClause(lits, true, lbd);
                    enqueue(lits[0], c);
                }
                varInc /= VAR_DECAY;
            } else {
                if (conflicts - conflictsAtRestart >= 50 && emaFast * 0.8 > emaSlow) {
                    cancelUntil(0);
                    conflictsAtRestart = conflicts;
                }
                if (conflicts >= nextReduce) {
                    reduces++;
                    reduceDB();
                    nextReduce = conflicts + 2000 + 300L * reduces;
                }
                int lit = pickBranchLit();
                if (lit == -1) return EXIT_SAT;
                trailLim[decisionLevel++] = trailSize;
                enqueue(lit, -1);
            }
        }
    }

    boolean modelValue(int v) {
        return model != null ? model[v] : litVal[2 * v] == 1;
    }

    // ----------------------------------------------------------------------------------------------------
    // DIMACS input and output.

    private static final class Cnf {
        int declaredVars;
        int maxVar;
        List<int[]> clauses = new ArrayList<>(); // DIMACS literals
    }

    static Cnf parse(byte[] b) {
        Cnf cnf = new Cnf();
        int pos = 0;
        int n = b.length;
        int[] cur = new int[16];
        int curLen = 0;
        outer:
        while (pos < n) {
            byte ch = b[pos];
            if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') {
                pos++;
                continue;
            }
            if (ch == 'c' || ch == 'p' || ch == '%') {
                int eol = pos;
                while (eol < n && b[eol] != '\n') eol++;
                if (ch == '%') break outer;
                if (ch == 'p') {
                    String[] tok = new String(b, pos, eol - pos, java.nio.charset.StandardCharsets.US_ASCII).trim().split("\\s+");
                    if (tok.length >= 4) cnf.declaredVars = Integer.parseInt(tok[2]);
                }
                pos = eol;
                continue;
            }
            // Integer token; anything else is skipped as a whole token.
            boolean neg = false;
            int start = pos;
            if (ch == '-' || ch == '+') {
                neg = ch == '-';
                pos++;
            }
            if (pos < n && b[pos] >= '0' && b[pos] <= '9') {
                long val = 0;
                while (pos < n && b[pos] >= '0' && b[pos] <= '9') {
                    val = val * 10 + (b[pos] - '0');
                    if (val > Integer.MAX_VALUE) val = Integer.MAX_VALUE;
                    pos++;
                }
                int lit = (int) val;
                if (neg) lit = -lit;
                if (lit == 0) {
                    cnf.clauses.add(Arrays.copyOf(cur, curLen));
                    curLen = 0;
                } else {
                    if (curLen == cur.length) cur = Arrays.copyOf(cur, curLen * 2);
                    cur[curLen++] = lit;
                    cnf.maxVar = Math.max(cnf.maxVar, Math.abs(lit));
                }
            } else {
                pos = start + 1;
                while (pos < n && b[pos] != ' ' && b[pos] != '\t' && b[pos] != '\r' && b[pos] != '\n') pos++;
            }
        }
        if (curLen > 0) cnf.clauses.add(Arrays.copyOf(cur, curLen)); // clause missing its final 0
        return cnf;
    }

    public static void main(String[] args) throws IOException {
        if (args.length != 1) {
            System.err.println("usage: solver FILE");
            System.exit(1);
        }
        Cnf cnf = parse(Files.readAllBytes(Paths.get(args[0])));
        int nVars = Math.max(cnf.declaredVars, cnf.maxVar);

        // Convert DIMACS literals to internal encoding.
        List<int[]> clauses = new ArrayList<>(cnf.clauses.size());
        for (int[] dc : cnf.clauses) {
            int[] lits = new int[dc.length];
            for (int i = 0; i < dc.length; i++) {
                int d = dc[i];
                lits[i] = 2 * (Math.abs(d) - 1) + (d < 0 ? 1 : 0);
            }
            clauses.add(lits);
        }

        Solver s = new Solver(nVars, clauses);
        int result = s.solve();

        PrintStream out = new PrintStream(new java.io.BufferedOutputStream(System.out, 1 << 16), false);
        if (result == EXIT_SAT) {
            out.println("s SATISFIABLE");
            StringBuilder sb = new StringBuilder();
            int onLine = 0;
            for (int v = 0; v < nVars; v++) {
                if (onLine == 0) sb.append('v');
                sb.append(' ').append(s.modelValue(v) ? v + 1 : -(v + 1));
                onLine++;
                if (onLine == 20) {
                    sb.append('\n');
                    out.print(sb);
                    sb.setLength(0);
                    onLine = 0;
                }
            }
            if (onLine == 0) sb.append('v');
            sb.append(" 0\n");
            out.print(sb);
        } else {
            out.println("s UNSATISFIABLE");
        }
        out.flush();
        System.exit(result);
    }
}
