import java.io.IOException;
import java.io.PrintStream;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Arrays;

/**
 * SAT solver for DIMACS CNF formulas.
 *
 * The search is the DPLL procedure: unit propagation (with two watched literals per clause),
 * decisions, and backtracking. It is extended with conflict-driven clause learning (first-UIP
 * analysis with non-chronological backtracking), VSIDS variable ordering, phase saving,
 * Luby restarts and LBD-based deletion of learnt clauses.
 *
 * Literal encoding: variable v (0-based) has positive literal 2v and negative literal 2v+1,
 * so the negation of literal l is l ^ 1.
 */
public final class Solver {
    static final byte UNDEF = 0, TRUE = 1, FALSE = -1;
    static final int EXIT_SAT = 10, EXIT_UNSAT = 20, EXIT_ERROR = 1;

    static final class Clause {
        final int[] lits;
        final boolean learnt;
        int lbd;
        double act;
        boolean deleted;

        Clause(int[] lits, boolean learnt) {
            this.lits = lits;
            this.learnt = learnt;
        }
    }

    private final int nVars;
    private final byte[] val;        // value per literal
    private final int[] level;       // decision level per variable
    private final Clause[] reason;   // antecedent clause per variable (null for decisions and units)
    private final boolean[] phase;   // saved polarity per variable (true = positive)
    private final byte[] target;     // polarity of the largest partial assignment seen (0 = none)
    private int targetSize;          // size of that assignment since the last restart
    private final int[] trail;       // assigned literals in assignment order
    private int trailSize;
    private int qhead;               // next trail position to propagate
    private int decisionLevel;
    private final int[] trailLim;    // trail index where each decision level starts

    // Watch lists: wc[l] holds the clauses watching literal l, wb[l] a blocker literal for each.
    // A clause is visited when its watched literal becomes false.
    private Clause[][] wc;
    private int[][] wb;
    private int[] wn;

    // VSIDS
    private final double[] activity;
    private double varInc = 1.0;
    private final int[] heap;
    private final int[] heapPos;
    private int heapSize;
    private double clauseInc = 1.0;

    // Conflict analysis scratch space
    private final boolean[] seen;
    private final int[] toClear;
    private int clearCount;
    private final int[] learntBuf;
    private final int[] lvlStamp;
    private int stampCounter;
    private int lastLbd;
    private int btLevel;

    private final ArrayList<Clause> learnts = new ArrayList<>();
    private boolean ok = true;
    private long conflicts;

    Solver(int nVars) {
        this.nVars = nVars;
        int nLits = 2 * nVars;
        val = new byte[nLits];
        level = new int[nVars];
        reason = new Clause[nVars];
        phase = new boolean[nVars];
        target = new byte[nVars];
        trail = new int[nVars];
        trailLim = new int[nVars + 1];
        wc = new Clause[nLits][];
        wb = new int[nLits][];
        wn = new int[nLits];
        for (int l = 0; l < nLits; l++) {
            wc[l] = new Clause[4];
            wb[l] = new int[4];
        }
        activity = new double[nVars];
        heap = new int[nVars];
        heapPos = new int[nVars];
        seen = new boolean[nVars];
        toClear = new int[nVars];
        learntBuf = new int[nVars + 1];
        lvlStamp = new int[nVars + 2];
        // Every variable starts unassigned and in the decision heap.
        for (int v = 0; v < nVars; v++) {
            heapPos[v] = -1;
            heapInsert(v);
        }
    }

    // ---------------------------------------------------------------- clauses

    /** Adds an input clause (literals in internal encoding). Propagation happens in solve(). */
    void addClause(int[] lits) {
        if (!ok) return;
        Arrays.sort(lits);
        int j = 0;
        for (int i = 0; i < lits.length; i++) {
            if (j > 0 && lits[j - 1] == lits[i]) continue;          // duplicate literal
            if (j > 0 && (lits[j - 1] ^ 1) == lits[i]) return;      // tautology: always satisfied
            lits[j++] = lits[i];
        }
        if (j == 0) {                                               // empty clause
            ok = false;
            return;
        }
        if (j == 1) {
            int l = lits[0];
            if (val[l] == FALSE) ok = false;
            else if (val[l] == UNDEF) enqueue(l, null);
            return;
        }
        attach(new Clause(Arrays.copyOf(lits, j), false));
    }

    private void attach(Clause c) {
        addWatch(c.lits[0], c, c.lits[1]);
        addWatch(c.lits[1], c, c.lits[0]);
    }

    private void addWatch(int lit, Clause c, int blocker) {
        int n = wn[lit];
        if (n == wc[lit].length) {
            int cap = Math.max(4, n * 2);
            wc[lit] = Arrays.copyOf(wc[lit], cap);
            wb[lit] = Arrays.copyOf(wb[lit], cap);
        }
        wc[lit][n] = c;
        wb[lit][n] = blocker;
        wn[lit] = n + 1;
    }

    // ---------------------------------------------------------------- assignment

    private void enqueue(int lit, Clause from) {
        val[lit] = TRUE;
        val[lit ^ 1] = FALSE;
        int v = lit >> 1;
        level[v] = decisionLevel;
        reason[v] = from;
        trail[trailSize++] = lit;
    }

    private void newDecisionLevel() {
        trailLim[decisionLevel++] = trailSize;
    }

    private void cancelUntil(int lvl) {
        if (decisionLevel <= lvl) return;
        for (int i = trailSize - 1; i >= trailLim[lvl]; i--) {
            int lit = trail[i];
            int v = lit >> 1;
            val[lit] = UNDEF;
            val[lit ^ 1] = UNDEF;
            phase[v] = (lit & 1) == 0;
            reason[v] = null;
            if (heapPos[v] < 0) heapInsert(v);
        }
        trailSize = trailLim[lvl];
        qhead = trailSize;
        decisionLevel = lvl;
    }

    /** Unit propagation with two watched literals. Returns the conflicting clause, or null. */
    private Clause propagate() {
        Clause confl = null;
        while (qhead < trailSize) {
            int p = trail[qhead++];
            int fl = p ^ 1;                       // literal that just became false
            Clause[] ws = wc[fl];
            int[] bs = wb[fl];
            int n = wn[fl];
            int i = 0, j = 0;
            while (i < n) {
                Clause c = ws[i];
                int b = bs[i];
                i++;
                if (val[b] == TRUE) {             // blocker satisfies the clause: keep watch
                    ws[j] = c;
                    bs[j] = b;
                    j++;
                    continue;
                }
                int[] lits = c.lits;
                if (lits[0] == fl) {
                    lits[0] = lits[1];
                    lits[1] = fl;
                }
                int first = lits[0];
                if (first != b && val[first] == TRUE) {
                    ws[j] = c;
                    bs[j] = first;
                    j++;
                    continue;
                }
                boolean moved = false;
                for (int k = 2; k < lits.length; k++) {
                    int lk = lits[k];
                    if (val[lk] != FALSE) {       // found a new watch
                        lits[1] = lk;
                        lits[k] = fl;
                        addWatch(lk, c, first);
                        moved = true;
                        break;
                    }
                }
                if (moved) continue;
                ws[j] = c;
                bs[j] = first;
                j++;
                if (val[first] == FALSE) {        // conflict: keep the remaining watches
                    confl = c;
                    qhead = trailSize;
                    while (i < n) {
                        ws[j] = ws[i];
                        bs[j] = bs[i];
                        j++;
                        i++;
                    }
                } else {
                    enqueue(first, c);
                }
            }
            wn[fl] = j;
            if (confl != null) break;
        }
        return confl;
    }

    // ---------------------------------------------------------------- conflict analysis

    /**
     * First-UIP conflict analysis. Returns the learnt clause with the asserting literal first,
     * the second literal at the backtrack level; sets btLevel and lastLbd.
     */
    private int[] analyze(Clause confl) {
        int pathC = 0;
        int p = -1;
        int idx = trailSize - 1;
        int outSize = 1;
        int clearN = 0;
        Clause c = confl;
        do {
            if (c.learnt) bumpClause(c);
            int[] lits = c.lits;
            for (int k = (p == -1) ? 0 : 1; k < lits.length; k++) {
                int q = lits[k];
                int v = q >> 1;
                if (!seen[v] && level[v] > 0) {
                    seen[v] = true;
                    toClear[clearN++] = v;
                    bumpVar(v);
                    if (level[v] >= decisionLevel) pathC++;
                    else learntBuf[outSize++] = q;
                }
            }
            while (!seen[trail[idx] >> 1]) idx--;
            p = trail[idx];
            idx--;
            c = reason[p >> 1];
            pathC--;
        } while (pathC > 0);
        learntBuf[0] = p ^ 1;

        // Local minimisation: drop a literal whose reason only has literals already in the clause.
        int j = 1;
        for (int i = 1; i < outSize; i++) {
            int q = learntBuf[i];
            Clause r = reason[q >> 1];
            if (r == null || !isRedundant(r)) learntBuf[j++] = q;
        }
        outSize = j;

        int bt = 0;
        if (outSize > 1) {
            int maxI = 1;
            for (int i = 2; i < outSize; i++) {
                if (level[learntBuf[i] >> 1] > level[learntBuf[maxI] >> 1]) maxI = i;
            }
            int tmp = learntBuf[1];
            learntBuf[1] = learntBuf[maxI];
            learntBuf[maxI] = tmp;
            bt = level[learntBuf[1] >> 1];
        }

        stampCounter++;
        int lbd = 0;
        for (int i = 0; i < outSize; i++) {
            int lv = level[learntBuf[i] >> 1];
            if (lvlStamp[lv] != stampCounter) {
                lvlStamp[lv] = stampCounter;
                lbd++;
            }
        }

        for (int i = 0; i < clearN; i++) seen[toClear[i]] = false;
        btLevel = bt;
        lastLbd = lbd;
        return Arrays.copyOf(learntBuf, outSize);
    }

    private boolean isRedundant(Clause r) {
        int[] lits = r.lits;
        for (int k = 1; k < lits.length; k++) {
            int v = lits[k] >> 1;
            if (!seen[v] && level[v] > 0) return false;
        }
        return true;
    }

    // ---------------------------------------------------------------- heuristics

    private void bumpVar(int v) {
        activity[v] += varInc;
        if (activity[v] > 1e100) {
            for (int i = 0; i < nVars; i++) activity[i] *= 1e-100;
            varInc *= 1e-100;
        }
        if (heapPos[v] >= 0) percolateUp(heapPos[v]);
    }

    private void bumpClause(Clause c) {
        c.act += clauseInc;
        if (c.act > 1e20) {
            for (Clause l : learnts) l.act *= 1e-20;
            clauseInc *= 1e-20;
        }
    }

    private void heapInsert(int v) {
        heap[heapSize] = v;
        heapPos[v] = heapSize;
        heapSize++;
        percolateUp(heapPos[v]);
    }

    private void percolateUp(int i) {
        int v = heap[i];
        while (i > 0) {
            int parent = (i - 1) >> 1;
            if (activity[heap[parent]] >= activity[v]) break;
            heap[i] = heap[parent];
            heapPos[heap[i]] = i;
            i = parent;
        }
        heap[i] = v;
        heapPos[v] = i;
    }

    private void percolateDown(int i) {
        int v = heap[i];
        while (true) {
            int child = 2 * i + 1;
            if (child >= heapSize) break;
            if (child + 1 < heapSize && activity[heap[child + 1]] > activity[heap[child]]) child++;
            if (activity[heap[child]] <= activity[v]) break;
            heap[i] = heap[child];
            heapPos[heap[i]] = i;
            i = child;
        }
        heap[i] = v;
        heapPos[v] = i;
    }

    private int heapRemoveMax() {
        int v = heap[0];
        heapPos[v] = -1;
        heapSize--;
        if (heapSize > 0) {
            heap[0] = heap[heapSize];
            heapPos[heap[0]] = 0;
            percolateDown(0);
        }
        return v;
    }

    /** Next decision literal (highest activity unassigned variable, saved phase), or -1 if all assigned. */
    private int pickBranchLit() {
        while (heapSize > 0) {
            int v = heapRemoveMax();
            if (val[2 * v] == UNDEF) {
                boolean pos = target[v] != 0 ? target[v] > 0 : phase[v];
                return pos ? 2 * v : 2 * v + 1;
            }
        }
        return -1;
    }

    // ---------------------------------------------------------------- learnt clause management

    private boolean isLocked(Clause c) {
        int l = c.lits[0];
        return val[l] == TRUE && reason[l >> 1] == c;
    }

    /** Deletes roughly half of the learnt clauses: the ones with high LBD and low activity. */
    private void reduceDB() {
        learnts.sort((a, b) -> a.lbd != b.lbd ? Integer.compare(a.lbd, b.lbd) : Double.compare(b.act, a.act));
        int limit = learnts.size() / 2;
        ArrayList<Clause> kept = new ArrayList<>(learnts.size());
        boolean removed = false;
        for (int i = 0; i < learnts.size(); i++) {
            Clause c = learnts.get(i);
            if (i >= limit && c.lbd > 2 && !isLocked(c)) {
                c.deleted = true;
                removed = true;
            } else {
                kept.add(c);
            }
        }
        learnts.clear();
        learnts.addAll(kept);
        if (!removed) return;
        for (int l = 0; l < wc.length; l++) {
            Clause[] ws = wc[l];
            int[] bs = wb[l];
            int n = wn[l], j = 0;
            for (int i = 0; i < n; i++) {
                if (!ws[i].deleted) {
                    ws[j] = ws[i];
                    bs[j] = bs[i];
                    j++;
                }
            }
            for (int i = j; i < n; i++) ws[i] = null;
            wn[l] = j;
        }
    }

    // ---------------------------------------------------------------- main search

    /** Returns EXIT_SAT or EXIT_UNSAT. On SAT the assignment is left in val[]. */
    int solve() {
        if (!ok) return EXIT_UNSAT;
        if (propagate() != null) return EXIT_UNSAT;

        // Restarts are driven by the recent LBD of learnt clauses (fast moving average) against
        // the long-run average (slow); a restart is due when the recent clauses are much worse.
        double emaFast = 0, emaSlow = 0;
        long sinceRestart = 0;
        long nextReduce = 2000;
        long reduces = 0;

        while (true) {
            Clause confl = propagate();
            if (confl != null) {
                conflicts++;
                sinceRestart++;
                if (decisionLevel == 0) return EXIT_UNSAT;
                emaFast += (lastLbd - emaFast) / 32.0;
                emaSlow += (lastLbd - emaSlow) / 4096.0;
                if (trailSize > targetSize) {          // remember the best partial assignment
                    targetSize = trailSize;
                    for (int i = 0; i < trailSize; i++) {
                        int lit = trail[i];
                        target[lit >> 1] = (byte) ((lit & 1) == 0 ? 1 : -1);
                    }
                }
                int[] learnt = analyze(confl);
                cancelUntil(btLevel);
                if (learnt.length == 1) {
                    enqueue(learnt[0], null);
                } else {
                    Clause c = new Clause(learnt, true);
                    c.lbd = lastLbd;
                    attach(c);
                    learnts.add(c);
                    bumpClause(c);
                    enqueue(learnt[0], c);
                }
                varInc /= 0.95;
                clauseInc /= 0.999;
            } else {
                if (sinceRestart >= 50 && emaFast > 1.25 * emaSlow) {
                    sinceRestart = 0;
                    targetSize = 0;
                    cancelUntil(0);
                    continue;
                }
                if (conflicts >= nextReduce) {
                    reduces++;
                    reduceDB();
                    nextReduce = conflicts + 2000 + 300 * reduces;
                }
                int lit = pickBranchLit();
                if (lit < 0) return EXIT_SAT;
                newDecisionLevel();
                enqueue(lit, null);
            }
        }
    }

    boolean modelSatisfies(int[][] clauses) {
        for (int[] c : clauses) {
            boolean sat = false;
            for (int l : c) {
                if (val[l] == TRUE) {
                    sat = true;
                    break;
                }
            }
            if (!sat) return false;
        }
        return true;
    }

    int valueOfVar(int v) {
        return val[2 * v] == TRUE ? 1 : -1;
    }

    // ---------------------------------------------------------------- DIMACS input / output

    static final class Cnf {
        int nVars;
        final ArrayList<int[]> clauses = new ArrayList<>();
    }

    /** Parses DIMACS CNF. Clauses are returned in internal literal encoding. */
    static Cnf parse(byte[] data) {
        Cnf cnf = new Cnf();
        int declared = 0, maxVar = 0;
        int pos = 0, n = data.length;
        int[] cur = new int[16];
        int curLen = 0;
        while (pos < n) {
            byte ch = data[pos];
            if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') {
                pos++;
            } else if (ch == 'c') {
                while (pos < n && data[pos] != '\n') pos++;
            } else if (ch == 'p') {
                int end = pos;
                while (end < n && data[end] != '\n') end++;
                String[] tok = new String(data, pos, end - pos, java.nio.charset.StandardCharsets.US_ASCII)
                        .trim().split("\\s+");
                if (tok.length < 4 || !tok[1].equals("cnf")) {
                    throw new IllegalArgumentException("bad problem line");
                }
                declared = Integer.parseInt(tok[2]);
                pos = end;
            } else if (ch == '%') {
                break;                                     // SATLIB end-of-file marker
            } else {
                boolean neg = false;
                if (ch == '-' || ch == '+') {
                    neg = ch == '-';
                    pos++;
                }
                if (pos >= n || data[pos] < '0' || data[pos] > '9') {
                    throw new IllegalArgumentException("unexpected character at byte " + pos);
                }
                long x = 0;
                while (pos < n && data[pos] >= '0' && data[pos] <= '9') {
                    x = x * 10 + (data[pos] - '0');
                    if (x > Integer.MAX_VALUE) throw new IllegalArgumentException("literal too large");
                    pos++;
                }
                if (x == 0) {
                    cnf.clauses.add(Arrays.copyOf(cur, curLen));
                    curLen = 0;
                } else {
                    if (x > maxVar) maxVar = (int) x;
                    if (curLen == cur.length) cur = Arrays.copyOf(cur, curLen * 2);
                    cur[curLen++] = 2 * ((int) x - 1) + (neg ? 1 : 0);
                }
            }
        }
        if (curLen > 0) cnf.clauses.add(Arrays.copyOf(cur, curLen));   // last clause missing its 0
        cnf.nVars = Math.max(declared, maxVar);
        return cnf;
    }

    static void printModel(Solver s, PrintStream out) {
        StringBuilder sb = new StringBuilder();
        sb.append("s SATISFIABLE\n");
        sb.append('v');
        int col = 1;
        for (int v = 0; v < s.nVars; v++) {
            String tok = Integer.toString(s.valueOfVar(v) * (v + 1));
            if (col + 1 + tok.length() > 78) {
                sb.append("\nv");
                col = 1;
            }
            sb.append(' ').append(tok);
            col += 1 + tok.length();
        }
        if (col + 2 > 78) sb.append("\nv");
        sb.append(" 0\n");
        out.print(sb);
    }

    public static void main(String[] args) throws IOException {
        if (args.length != 1) {
            System.err.println("usage: solver FILE");
            System.exit(EXIT_ERROR);
        }
        byte[] data;
        try {
            data = Files.readAllBytes(Paths.get(args[0]));
        } catch (IOException e) {
            System.err.println("c cannot read " + args[0] + ": " + e.getMessage());
            System.exit(EXIT_ERROR);
            return;
        }
        Cnf cnf;
        try {
            cnf = parse(data);
        } catch (IllegalArgumentException e) {
            System.err.println("c parse error: " + e.getMessage());
            System.exit(EXIT_ERROR);
            return;
        }

        int[][] clauses = cnf.clauses.toArray(new int[0][]);
        Solver s = new Solver(cnf.nVars);
        for (int[] c : clauses) s.addClause(Arrays.copyOf(c, c.length));
        int result = s.solve();

        PrintStream out = System.out;
        if (result == EXIT_SAT) {
            if (!s.modelSatisfies(clauses)) {
                // Never report an assignment that does not satisfy the formula.
                System.err.println("c internal error: model check failed");
                System.exit(EXIT_ERROR);
            }
            printModel(s, out);
            out.flush();
            System.exit(EXIT_SAT);
        } else {
            out.print("s UNSATISFIABLE\n");
            out.flush();
            System.exit(EXIT_UNSAT);
        }
    }
}
