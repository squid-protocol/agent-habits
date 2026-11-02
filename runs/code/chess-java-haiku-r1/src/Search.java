import java.util.Arrays;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Consumer;

/** Iterative-deepening alpha-beta search with a transposition table, null-move and late-move pruning. */
final class Search {
    static final int MATE = 100000;
    static final int MATE_BOUND = MATE - 1000;
    static final int INF = 1000000;
    static final int MAXPLY = 128;
    static final int MAX_DEPTH = 64;

    private static final int TT_BITS = 20;
    private static final int TT_MASK = (1 << TT_BITS) - 1;
    private static final int EXACT = 0, LOWER = 1, UPPER = 2;
    private static final long[] tKey = new long[1 << TT_BITS];
    private static final int[] tMove = new int[1 << TT_BITS];
    private static final int[] tScore = new int[1 << TT_BITS];
    private static final int[] tDepth = new int[1 << TT_BITS];
    private static final int[] tFlag = new int[1 << TT_BITS];

    static synchronized void clearTT() {
        Arrays.fill(tKey, 0L);
        Arrays.fill(tMove, 0);
        Arrays.fill(tDepth, 0);
    }

    private final Position pos;
    private final AtomicBoolean stopReq;
    private final long deadline;     // System.nanoTime() value, or Long.MAX_VALUE for no limit
    private final int maxDepth;
    private final Consumer<String> info;
    private final int[][] killers = new int[MAXPLY][2];
    private final int[] history = new int[2 * 128 * 128];
    private final long startNs = System.nanoTime();
    private long nodes;
    private boolean stopped;
    private int rootBest;

    Search(Position pos, AtomicBoolean stopReq, long deadline, int maxDepth, Consumer<String> info) {
        this.pos = pos;
        this.stopReq = stopReq;
        this.deadline = deadline;
        this.maxDepth = Math.max(1, Math.min(maxDepth, MAX_DEPTH));
        this.info = info;
    }

    /** Returns the best move found, or 0 if there is no legal move. */
    int run() {
        int[] root = new int[256];
        int n = pos.legal(root);
        if (n == 0) return 0;
        int best = root[0];
        if (n == 1) return best;
        for (int depth = 1; depth <= maxDepth; depth++) {
            int score = searchRoot(depth, -INF, INF);
            if (stopped) break;
            best = rootBest;
            report(depth, score, best);
        }
        return best;
    }

    private void checkTime() {
        if (stopReq.get() || (deadline != Long.MAX_VALUE && System.nanoTime() >= deadline)) stopped = true;
    }

    private void report(int depth, int score, int move) {
        long ms = (System.nanoTime() - startNs) / 1_000_000L;
        String sc;
        if (Math.abs(score) >= MATE_BOUND) {
            int mate = score > 0 ? (MATE - score + 1) / 2 : -(MATE + score) / 2;
            sc = "mate " + mate;
        } else {
            sc = "cp " + score;
        }
        long nps = ms > 0 ? nodes * 1000L / ms : nodes;
        info.accept("info depth " + depth + " score " + sc + " nodes " + nodes + " nps " + nps
                + " time " + ms + " pv " + Position.uci(move));
    }

    // ---------------------------------------------------------------- move ordering

    private void scoreMoves(int[] mv, int[] sc, int n, int ttMove, int ply) {
        int me = pos.side;
        for (int i = 0; i < n; i++) {
            int m = mv[i];
            int from = Position.from(m), to = Position.to(m), promo = Position.promo(m);
            int p = pos.b[from];
            int victim = pos.b[to];
            boolean ep = (m & Position.F_EP) != 0;
            if (m == ttMove) {
                sc[i] = 3_000_000;
            } else if (victim != Position.EMPTY || ep) {
                int vt = ep ? Position.PAWN : Position.type(victim);
                sc[i] = 2_000_000 + vt * 10 - Position.type(p);
            } else if (promo != 0) {
                sc[i] = 1_900_000 + promo;
            } else if (ply < MAXPLY && killers[ply][0] == m) {
                sc[i] = 1_500_000;
            } else if (ply < MAXPLY && killers[ply][1] == m) {
                sc[i] = 1_400_000;
            } else {
                sc[i] = history[me * 16384 + from * 128 + to];
            }
        }
    }

    private static int pick(int[] mv, int[] sc, int n, int i) {
        int best = i;
        for (int j = i + 1; j < n; j++) if (sc[j] > sc[best]) best = j;
        if (best != i) {
            int t = mv[i]; mv[i] = mv[best]; mv[best] = t;
            int s = sc[i]; sc[i] = sc[best]; sc[best] = s;
        }
        return mv[i];
    }

    private int ttProbeMove(long key) {
        int idx = (int) (key & TT_MASK);
        return tKey[idx] == key ? tMove[idx] : 0;
    }

    private static int toTT(int s, int ply) {
        if (s >= MATE_BOUND) return s + ply;
        if (s <= -MATE_BOUND) return s - ply;
        return s;
    }

    private static int fromTT(int s, int ply) {
        if (s >= MATE_BOUND) return s - ply;
        if (s <= -MATE_BOUND) return s + ply;
        return s;
    }

    // ---------------------------------------------------------------- search

    private int searchRoot(int depth, int alpha, int beta) {
        int[] mv = new int[256];
        int n = pos.gen(mv, false);
        int[] sc = new int[n];
        scoreMoves(mv, sc, n, ttProbeMove(pos.key), 0);
        int bestScore = -INF, bestMv = 0, legal = 0;
        int me = pos.side;
        for (int i = 0; i < n; i++) {
            int m = pick(mv, sc, n, i);
            pos.make(m);
            if (!pos.legalAfterMake()) {
                pos.unmake();
                continue;
            }
            legal++;
            int score;
            if (legal == 1) {
                score = -negamax(depth - 1, -beta, -alpha, 1, true);
            } else {
                score = -negamax(depth - 1, -alpha - 1, -alpha, 1, true);
                if (score > alpha && score < beta) score = -negamax(depth - 1, -beta, -alpha, 1, true);
            }
            pos.unmake();
            if (stopped) return 0;
            if (score > bestScore) {
                bestScore = score;
                bestMv = m;
                if (score > alpha) alpha = score;
            }
        }
        if (bestMv != 0) {
            rootBest = bestMv;
            store(pos.key, depth, bestScore, EXACT, bestMv, 0);
        }
        return bestScore;
    }

    private void store(long key, int depth, int score, int flag, int move, int ply) {
        int idx = (int) (key & TT_MASK);
        tKey[idx] = key;
        tMove[idx] = move;
        tScore[idx] = toTT(score, ply);
        tDepth[idx] = depth;
        tFlag[idx] = flag;
    }

    private int negamax(int depth, int alpha, int beta, int ply, boolean allowNull) {
        if ((++nodes & 2047) == 0) checkTime();
        if (stopped) return 0;
        if (ply > 0 && (pos.half >= 100 || pos.repetition())) return 0;
        if (ply >= MAXPLY - 1) return Eval.eval(pos);

        boolean inCheck = pos.inCheck();
        if (inCheck) depth++;
        if (depth <= 0) return qsearch(alpha, beta, ply);

        int alphaOrig = alpha;
        long key = pos.key;
        int idx = (int) (key & TT_MASK);
        int ttMove = 0;
        if (tKey[idx] == key) {
            ttMove = tMove[idx];
            if (tDepth[idx] >= depth && ply > 0) {
                int s = fromTT(tScore[idx], ply);
                int f = tFlag[idx];
                if (f == EXACT || (f == LOWER && s >= beta) || (f == UPPER && s <= alpha)) return s;
            }
        }

        if (allowNull && !inCheck && depth >= 3 && ply > 0 && pos.nonPawnCount(pos.side) > 0
                && Eval.eval(pos) >= beta) {
            int r = 2 + depth / 4;
            pos.makeNull();
            int s = -negamax(depth - 1 - r, -beta, -beta + 1, ply + 1, false);
            pos.unmakeNull();
            if (stopped) return 0;
            if (s >= beta) return s >= MATE_BOUND ? beta : s;
        }

        int[] mv = new int[256];
        int n = pos.gen(mv, false);
        int[] sc = new int[n];
        scoreMoves(mv, sc, n, ttMove, ply);
        int me = pos.side;
        int best = -INF, bestMv = 0, legal = 0;
        for (int i = 0; i < n; i++) {
            int m = pick(mv, sc, n, i);
            int to = Position.to(m);
            boolean quiet = pos.b[to] == Position.EMPTY && (m & Position.F_MASK) == 0 && Position.promo(m) == 0;
            pos.make(m);
            if (!pos.legalAfterMake()) {
                pos.unmake();
                continue;
            }
            legal++;
            int nd = depth - 1;
            int score;
            if (legal == 1) {
                score = -negamax(nd, -beta, -alpha, ply + 1, true);
            } else {
                int r = 0;
                if (depth >= 3 && legal > 3 && quiet && !inCheck) r = legal > 6 ? 2 : 1;
                score = -negamax(nd - r, -alpha - 1, -alpha, ply + 1, true);
                if (score > alpha && r > 0) score = -negamax(nd, -alpha - 1, -alpha, ply + 1, true);
                if (score > alpha && score < beta) score = -negamax(nd, -beta, -alpha, ply + 1, true);
            }
            pos.unmake();
            if (stopped) return 0;
            if (score > best) {
                best = score;
                bestMv = m;
                if (score > alpha) {
                    alpha = score;
                    if (score >= beta) {
                        if (quiet) {
                            if (killers[ply][0] != m) {
                                killers[ply][1] = killers[ply][0];
                                killers[ply][0] = m;
                            }
                            int hi = me * 16384 + Position.from(m) * 128 + to;
                            history[hi] = Math.min(history[hi] + depth * depth, 400_000);
                        }
                        break;
                    }
                }
            }
        }
        if (legal == 0) return inCheck ? -MATE + ply : 0;

        int flag = best <= alphaOrig ? UPPER : best >= beta ? LOWER : EXACT;
        store(key, depth, best, flag, bestMv, ply);
        return best;
    }

    private int qsearch(int alpha, int beta, int ply) {
        if ((++nodes & 2047) == 0) checkTime();
        if (stopped) return 0;
        if (ply >= MAXPLY - 1) return Eval.eval(pos);

        boolean inCheck = pos.inCheck();
        int best;
        if (inCheck) {
            best = -INF;
        } else {
            int stand = Eval.eval(pos);
            if (stand >= beta) return stand;
            if (stand > alpha) alpha = stand;
            best = stand;
        }
        int[] mv = new int[256];
        int n = pos.gen(mv, !inCheck);
        int[] sc = new int[n];
        scoreMoves(mv, sc, n, 0, ply);
        int legal = 0;
        for (int i = 0; i < n; i++) {
            int m = pick(mv, sc, n, i);
            pos.make(m);
            if (!pos.legalAfterMake()) {
                pos.unmake();
                continue;
            }
            legal++;
            int score = -qsearch(-beta, -alpha, ply + 1);
            pos.unmake();
            if (stopped) return 0;
            if (score > best) {
                best = score;
                if (score > alpha) {
                    alpha = score;
                    if (score >= beta) return best;
                }
            }
        }
        if (inCheck && legal == 0) return -MATE + ply;
        return best;
    }
}
