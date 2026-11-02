package engine;

import java.util.concurrent.atomic.AtomicBoolean;
import java.util.function.Consumer;

/**
 * Iterative-deepening alpha-beta search with a transposition table, null-move pruning, late-move reductions,
 * killer and history move ordering, check extensions and a capture-only quiescence search.
 */
final class Search {
    static final int INF = 32000;
    static final int MATE = 30000;
    static final int MATE_BOUND = 29000;
    static final int MAXPLY = 128;

    private final Board b;
    private final TT tt;
    private final AtomicBoolean stop;
    /** System.nanoTime() deadline; 0 means none. */
    private final long deadline;
    private final Consumer<String> info;

    private final int[][] moves = new int[MAXPLY][256];
    private final int[][] scores = new int[MAXPLY][256];
    private final int[] killer1 = new int[MAXPLY];
    private final int[] killer2 = new int[MAXPLY];
    private final int[][] history = new int[16][128];

    private long nodes;
    private boolean aborted;
    private int iter;
    private int rootBest;
    private long startNanos;

    Search(Board b, TT tt, AtomicBoolean stop, long deadline, Consumer<String> info) {
        this.b = b;
        this.tt = tt;
        this.stop = stop;
        this.deadline = deadline;
        this.info = info;
    }

    /** Searches up to maxDepth and returns the best move found (0 if the side to move has no legal move). */
    int run(int maxDepth) {
        startNanos = System.nanoTime();
        int[] rootList = new int[256];
        int nRoot = MoveGen.genLegal(b, rootList);
        if (nRoot == 0) {
            return 0;
        }
        int bestMove = rootList[0];
        for (int d = 1; d <= maxDepth; d++) {
            iter = d;
            int s = search(d, -INF, INF, 0);
            if (aborted) {
                break;
            }
            bestMove = rootBest;
            report(d, s);
            if (Math.abs(s) >= MATE_BOUND && MATE - Math.abs(s) <= d) {
                break; // a forced mate inside the horizon cannot be beaten by searching deeper
            }
        }
        return bestMove;
    }

    private void report(int depth, int s) {
        long ms = Math.max(1, (System.nanoTime() - startNanos) / 1_000_000L);
        String score;
        if (Math.abs(s) >= MATE_BOUND) {
            int plies = MATE - Math.abs(s);
            int moves = (plies + 1) / 2;
            score = "mate " + (s > 0 ? moves : -moves);
        } else {
            score = "cp " + s;
        }
        info.accept("info depth " + depth + " score " + score + " nodes " + nodes + " time " + ms
                + " nps " + (nodes * 1000L / ms) + " pv " + Move.toUci(rootBest));
    }

    private void checkTime() {
        if (stop.get() || (deadline != 0 && iter > 1 && System.nanoTime() >= deadline)) {
            aborted = true;
        }
    }

    private static int toTT(int s, int ply) {
        return s >= MATE_BOUND ? s + ply : s <= -MATE_BOUND ? s - ply : s;
    }

    private static int fromTT(int s, int ply) {
        return s >= MATE_BOUND ? s - ply : s <= -MATE_BOUND ? s + ply : s;
    }

    /** True if the position (or a repetition of it) occurred earlier on the current line, or since the last capture or pawn move. */
    private boolean isRepetition() {
        int lim = Math.min(b.halfmove, b.ply);
        for (int i = b.ply - 2; i >= b.ply - lim; i -= 2) {
            if (b.stHash[i] == b.hash) {
                return true;
            }
        }
        return false;
    }

    private boolean hasNonPawnMaterial(int color) {
        for (int r = 0; r < 8; r++) {
            for (int f = 0; f < 8; f++) {
                int pc = b.sq[(r << 4) | f];
                if (pc != 0 && (pc >> 3) == color) {
                    int t = pc & 7;
                    if (t >= Board.KNIGHT && t <= Board.QUEEN) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    private boolean isQuiet(int m) {
        return b.sq[Move.to(m)] == 0 && (Move.flags(m) & Move.EP) == 0 && Move.promo(m) == 0;
    }

    private int scoreMove(int m, int ttMove, int ply) {
        if (m == ttMove) {
            return 3_000_000;
        }
        int from = Move.from(m), to = Move.to(m), promo = Move.promo(m);
        if (promo != 0) {
            return 1_500_000 + Eval.VAL[promo];
        }
        int mover = b.sq[from];
        int victim = b.sq[to];
        if (victim != 0 || (Move.flags(m) & Move.EP) != 0) {
            int vt = (Move.flags(m) & Move.EP) != 0 ? Board.PAWN : (victim & 7);
            return 2_000_000 + Eval.VAL[vt] * 8 - (mover & 7);
        }
        if (m == killer1[ply]) {
            return 1_000_000;
        }
        if (m == killer2[ply]) {
            return 999_000;
        }
        return Math.min(history[mover][to], 900_000);
    }

    private static void swap(int[] a, int i, int j) {
        int t = a[i];
        a[i] = a[j];
        a[j] = t;
    }

    private int search(int depth, int alpha, int beta, int ply) {
        if (aborted) {
            return 0;
        }
        if ((++nodes & 1023) == 0) {
            checkTime();
            if (aborted) {
                return 0;
            }
        }
        if (ply > 0) {
            if (b.halfmove >= 100 || isRepetition()) {
                return 0;
            }
        }
        if (ply >= MAXPLY - 1) {
            return Eval.eval(b);
        }
        int us = b.side;
        boolean inCheck = b.inCheck();
        if (inCheck) {
            depth++;
        }
        if (depth <= 0) {
            return qsearch(alpha, beta, ply);
        }

        boolean pv = beta - alpha > 1;
        long key = b.hash;
        int ttIdx = tt.index(key);
        int ttMove = 0;
        if (tt.meta[ttIdx] != 0 && tt.keys[ttIdx] == key) {
            ttMove = tt.moves[ttIdx];
            if (!pv && ply > 0 && (tt.meta[ttIdx] >> 2) >= depth) {
                int s = fromTT(tt.scores[ttIdx], ply);
                int bound = tt.meta[ttIdx] & 3;
                if (bound == TT.EXACT || (bound == TT.LOWER && s >= beta) || (bound == TT.UPPER && s <= alpha)) {
                    return s;
                }
            }
        }

        if (!pv && !inCheck && depth >= 3 && Eval.eval(b) >= beta && hasNonPawnMaterial(us)) {
            int r = depth >= 6 ? 3 : 2;
            b.makeNull();
            int s = -search(depth - 1 - r, -beta, -beta + 1, ply + 1);
            b.unmake();
            if (aborted) {
                return 0;
            }
            if (s >= beta) {
                return s >= MATE_BOUND ? beta : s;
            }
        }

        int[] list = moves[ply];
        int[] sc = scores[ply];
        int n = MoveGen.gen(b, list, false);
        for (int i = 0; i < n; i++) {
            sc[i] = scoreMove(list[i], ttMove, ply);
        }
        int origAlpha = alpha;
        int best = -INF, bestMove = 0, legal = 0;
        for (int i = 0; i < n; i++) {
            int bi = i;
            for (int j = i + 1; j < n; j++) {
                if (sc[j] > sc[bi]) {
                    bi = j;
                }
            }
            if (bi != i) {
                swap(sc, i, bi);
                swap(list, i, bi);
            }
            int m = list[i];
            boolean quiet = isQuiet(m);
            int mover = b.sq[Move.from(m)];
            b.make(m);
            if (b.attacked(b.kingSq[us], us ^ 1)) {
                b.unmake();
                continue;
            }
            legal++;
            int s;
            if (legal == 1) {
                s = -search(depth - 1, -beta, -alpha, ply + 1);
            } else {
                int r = 0;
                if (depth >= 3 && legal >= 4 && quiet && !inCheck && !b.inCheck()) {
                    r = 1;
                }
                s = -search(depth - 1 - r, -alpha - 1, -alpha, ply + 1);
                if (s > alpha && r > 0) {
                    s = -search(depth - 1, -alpha - 1, -alpha, ply + 1);
                }
                if (s > alpha && s < beta) {
                    s = -search(depth - 1, -beta, -alpha, ply + 1);
                }
            }
            b.unmake();
            if (aborted) {
                return 0;
            }
            if (s > best) {
                best = s;
                bestMove = m;
                if (s > alpha) {
                    alpha = s;
                    if (alpha >= beta) {
                        if (quiet) {
                            if (m != killer1[ply]) {
                                killer2[ply] = killer1[ply];
                                killer1[ply] = m;
                            }
                            history[mover][Move.to(m)] += depth * depth;
                        }
                        break;
                    }
                }
            }
        }
        if (legal == 0) {
            return inCheck ? -MATE + ply : 0;
        }
        if (ply == 0) {
            rootBest = bestMove;
        }
        int bound = best <= origAlpha ? TT.UPPER : best >= beta ? TT.LOWER : TT.EXACT;
        tt.store(key, bestMove, toTT(best, ply), depth, bound);
        return best;
    }

    private int qsearch(int alpha, int beta, int ply) {
        if (aborted) {
            return 0;
        }
        if ((++nodes & 1023) == 0) {
            checkTime();
            if (aborted) {
                return 0;
            }
        }
        if (ply >= MAXPLY - 1) {
            return Eval.eval(b);
        }
        int us = b.side;
        boolean inCheck = b.inCheck();
        int best;
        if (inCheck) {
            best = -INF;
        } else {
            best = Eval.eval(b);
            if (best >= beta) {
                return best;
            }
            if (best > alpha) {
                alpha = best;
            }
        }
        int[] list = moves[ply];
        int[] sc = scores[ply];
        int n = MoveGen.gen(b, list, !inCheck);
        for (int i = 0; i < n; i++) {
            sc[i] = scoreMove(list[i], 0, ply);
        }
        int legal = 0;
        for (int i = 0; i < n; i++) {
            int bi = i;
            for (int j = i + 1; j < n; j++) {
                if (sc[j] > sc[bi]) {
                    bi = j;
                }
            }
            if (bi != i) {
                swap(sc, i, bi);
                swap(list, i, bi);
            }
            int m = list[i];
            b.make(m);
            if (b.attacked(b.kingSq[us], us ^ 1)) {
                b.unmake();
                continue;
            }
            legal++;
            int s = -qsearch(-beta, -alpha, ply + 1);
            b.unmake();
            if (aborted) {
                return 0;
            }
            if (s > best) {
                best = s;
                if (s > alpha) {
                    alpha = s;
                    if (alpha >= beta) {
                        return best;
                    }
                }
            }
        }
        if (inCheck && legal == 0) {
            return -MATE + ply;
        }
        return best;
    }
}
