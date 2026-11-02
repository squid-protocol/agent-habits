import java.io.*;
import java.util.*;

public class Engine {
    static final int CAP = 1 << 17, EP = 1 << 18, CASTLE = 1 << 19, DBL = 1 << 20;
    static final int MATE = 30000, MAXP = 120;
    static final int[] KN = {33, 31, 18, 14, -33, -31, -18, -14};
    static final int[] DG = {17, 15, -17, -15};
    static final int[] OR = {1, -1, 16, -16};
    static final int[] AL = {1, -1, 16, -16, 17, 15, -17, -15};
    static final int[] VAL = {0, 100, 320, 330, 500, 900, 0};
    static final int[] CMASK = new int[128];
    static long[][] Z = new long[16][128];
    static long[] ZC = new long[16], ZEP = new long[128];
    static long ZS;

    static {
        Random r = new Random(12345);
        for (long[] a : Z) for (int i = 0; i < 128; i++) a[i] = r.nextLong();
        for (int i = 0; i < 16; i++) ZC[i] = r.nextLong();
        for (int i = 0; i < 128; i++) ZEP[i] = r.nextLong();
        ZS = r.nextLong();
        Arrays.fill(CMASK, 15);
        CMASK[4] = 12; CMASK[0] = 13; CMASK[7] = 14;
        CMASK[0x74] = 3; CMASK[0x70] = 7; CMASK[0x77] = 11;
    }

    int[] b = new int[128];
    int side, castle, ep = -1, half, hply;
    int[] ks = new int[2];
    long hash;
    int[] stCap = new int[4200], stCastle = new int[4200], stEp = new int[4200], stHalf = new int[4200];
    long[] stHash = new long[4200];

    // ---------- setup ----------
    void setFen(String fen) {
        Arrays.fill(b, 0);
        String[] t = fen.trim().split("\\s+");
        int r = 7, f = 0;
        String pc = "?PNBRQK";
        for (char c : t[0].toCharArray()) {
            if (c == '/') { r--; f = 0; }
            else if (Character.isDigit(c)) f += c - '0';
            else {
                int col = Character.isUpperCase(c) ? 0 : 8;
                int ty = pc.indexOf(Character.toUpperCase(c));
                b[r * 16 + f] = ty | col;
                if (ty == 6) ks[col >> 3] = r * 16 + f;
                f++;
            }
        }
        side = t.length > 1 && t[1].equals("b") ? 1 : 0;
        castle = 0;
        String cs = t.length > 2 ? t[2] : "-";
        if (cs.contains("K")) castle |= 1;
        if (cs.contains("Q")) castle |= 2;
        if (cs.contains("k")) castle |= 4;
        if (cs.contains("q")) castle |= 8;
        ep = -1;
        if (t.length > 3 && !t[3].equals("-")) ep = (t[3].charAt(1) - '1') * 16 + (t[3].charAt(0) - 'a');
        half = t.length > 4 ? Integer.parseInt(t[4]) : 0;
        hply = 0;
        hash = 0;
        for (int s = 0; s < 128; s++) if ((s & 0x88) == 0 && b[s] != 0) hash ^= Z[b[s]][s];
        hash ^= ZC[castle];
        if (ep >= 0) hash ^= ZEP[ep];
        if (side == 1) hash ^= ZS;
    }

    boolean attacked(int sq, int by) {
        int pawn = 1 | (by << 3);
        if (by == 0) {
            int s = sq - 15; if ((s & 0x88) == 0 && b[s] == pawn) return true;
            s = sq - 17; if ((s & 0x88) == 0 && b[s] == pawn) return true;
        } else {
            int s = sq + 15; if ((s & 0x88) == 0 && b[s] == pawn) return true;
            s = sq + 17; if ((s & 0x88) == 0 && b[s] == pawn) return true;
        }
        int n = 2 | (by << 3);
        for (int d : KN) { int s = sq + d; if ((s & 0x88) == 0 && b[s] == n) return true; }
        int k = 6 | (by << 3);
        for (int d : AL) { int s = sq + d; if ((s & 0x88) == 0 && b[s] == k) return true; }
        int bi = 3 | (by << 3), ro = 4 | (by << 3), q = 5 | (by << 3);
        for (int d : DG) {
            int s = sq + d;
            while ((s & 0x88) == 0) {
                int p = b[s];
                if (p != 0) { if (p == bi || p == q) return true; break; }
                s += d;
            }
        }
        for (int d : OR) {
            int s = sq + d;
            while ((s & 0x88) == 0) {
                int p = b[s];
                if (p != 0) { if (p == ro || p == q) return true; break; }
                s += d;
            }
        }
        return false;
    }

    static int mk(int f, int t, int promo, int flags) { return f | (t << 7) | (promo << 14) | flags; }

    int gen(int[] m, boolean caps) {
        int n = 0;
        int us = side, them = side ^ 1;
        for (int from = 0; from < 128; from++) {
            if ((from & 0x88) != 0) { from += 7; continue; }
            int p = b[from];
            if (p == 0 || (p >> 3) != us) continue;
            int ty = p & 7;
            if (ty == 1) {
                int dir = us == 0 ? 16 : -16, st = us == 0 ? 1 : 6, pr = us == 0 ? 6 : 1;
                int rk = from >> 4;
                int to = from + dir;
                if (b[to] == 0) {
                    if (rk == pr) { for (int pp = 5; pp >= 2; pp--) m[n++] = mk(from, to, pp, 0); }
                    else {
                        if (!caps) m[n++] = mk(from, to, 0, 0);
                        if (!caps && rk == st && b[to + dir] == 0) m[n++] = mk(from, to + dir, 0, DBL);
                    }
                }
                for (int dd = -1; dd <= 1; dd += 2) {
                    int t = to + dd;
                    if ((t & 0x88) != 0) continue;
                    if (b[t] != 0 && (b[t] >> 3) == them) {
                        if (rk == pr) { for (int pp = 5; pp >= 2; pp--) m[n++] = mk(from, t, pp, CAP); }
                        else m[n++] = mk(from, t, 0, CAP);
                    } else if (t == ep && b[t] == 0) m[n++] = mk(from, t, 0, CAP | EP);
                }
            } else if (ty == 2 || ty == 6) {
                int[] ds = ty == 2 ? KN : AL;
                for (int d : ds) {
                    int t = from + d;
                    if ((t & 0x88) != 0) continue;
                    if (b[t] == 0) { if (!caps) m[n++] = mk(from, t, 0, 0); }
                    else if ((b[t] >> 3) == them) m[n++] = mk(from, t, 0, CAP);
                }
                if (ty == 6 && !caps) {
                    int base = us == 0 ? 0 : 0x70;
                    if (from == base + 4 && !attacked(from, them)) {
                        if ((castle & (us == 0 ? 1 : 4)) != 0 && b[base + 5] == 0 && b[base + 6] == 0
                            && !attacked(base + 5, them) && !attacked(base + 6, them))
                            m[n++] = mk(from, base + 6, 0, CASTLE);
                        if ((castle & (us == 0 ? 2 : 8)) != 0 && b[base + 3] == 0 && b[base + 2] == 0 && b[base + 1] == 0
                            && !attacked(base + 3, them) && !attacked(base + 2, them))
                            m[n++] = mk(from, base + 2, 0, CASTLE);
                    }
                }
            } else {
                int[] ds = ty == 3 ? DG : ty == 4 ? OR : AL;
                for (int d : ds) {
                    int t = from + d;
                    while ((t & 0x88) == 0) {
                        if (b[t] == 0) { if (!caps) m[n++] = mk(from, t, 0, 0); }
                        else { if ((b[t] >> 3) == them) m[n++] = mk(from, t, 0, CAP); break; }
                        t += d;
                    }
                }
            }
        }
        return n;
    }

    void make(int m) {
        int from = m & 127, to = (m >> 7) & 127, promo = (m >> 14) & 7;
        stHash[hply] = hash; stCastle[hply] = castle; stEp[hply] = ep; stHalf[hply] = half;
        int p = b[from];
        int cap = b[to];
        if ((m & EP) != 0) {
            int cs = to + (side == 0 ? -16 : 16);
            cap = b[cs]; b[cs] = 0; hash ^= Z[cap][cs];
        } else if (cap != 0) hash ^= Z[cap][to];
        stCap[hply] = cap;
        hply++;
        hash ^= Z[p][from];
        b[from] = 0;
        if (promo != 0) p = promo | (side << 3);
        b[to] = p;
        hash ^= Z[p][to];
        if ((m & CASTLE) != 0) {
            int rf, rt;
            if (to > from) { rf = from + 3; rt = from + 1; } else { rf = from - 4; rt = from - 1; }
            int rk = b[rf]; b[rf] = 0; b[rt] = rk;
            hash ^= Z[rk][rf] ^ Z[rk][rt];
        }
        if ((p & 7) == 6) ks[side] = to;
        hash ^= ZC[castle];
        castle &= CMASK[from] & CMASK[to];
        hash ^= ZC[castle];
        if (ep >= 0) hash ^= ZEP[ep];
        ep = -1;
        if ((m & DBL) != 0) { ep = (from + to) / 2; hash ^= ZEP[ep]; }
        half = ((p & 7) == 1 || cap != 0) ? 0 : half + 1;
        side ^= 1;
        hash ^= ZS;
    }

    void unmake(int m) {
        int from = m & 127, to = (m >> 7) & 127, promo = (m >> 14) & 7;
        hply--;
        side ^= 1;
        int p = b[to];
        int cap = stCap[hply];
        if (promo != 0) p = 1 | (side << 3);
        b[from] = p;
        if ((m & EP) != 0) {
            b[to] = 0;
            b[to + (side == 0 ? -16 : 16)] = cap;
        } else b[to] = cap;
        if ((m & CASTLE) != 0) {
            int rf, rt;
            if (to > from) { rf = from + 3; rt = from + 1; } else { rf = from - 4; rt = from - 1; }
            b[rf] = b[rt]; b[rt] = 0;
        }
        if ((p & 7) == 6) ks[side] = from;
        castle = stCastle[hply]; ep = stEp[hply]; half = stHalf[hply]; hash = stHash[hply];
    }

    void makeNull() {
        stHash[hply] = hash; stCastle[hply] = castle; stEp[hply] = ep; stHalf[hply] = half;
        hply++;
        if (ep >= 0) hash ^= ZEP[ep];
        ep = -1; half++; side ^= 1; hash ^= ZS;
    }

    void unmakeNull() {
        hply--; side ^= 1;
        castle = stCastle[hply]; ep = stEp[hply]; half = stHalf[hply]; hash = stHash[hply];
    }

    boolean legalMake(int m) {
        make(m);
        if (attacked(ks[side ^ 1], side)) { unmake(m); return false; }
        return true;
    }

    static String str(int m) {
        int f = m & 127, t = (m >> 7) & 127, p = (m >> 14) & 7;
        String s = "" + (char) ('a' + (f & 7)) + (char) ('1' + (f >> 4)) + (char) ('a' + (t & 7)) + (char) ('1' + (t >> 4));
        if (p != 0) s += "??nbrq".charAt(p);
        return s;
    }

    long perft(int d, boolean root) {
        int[] m = new int[256];
        int n = gen(m, false);
        long tot = 0;
        for (int i = 0; i < n; i++) {
            if (!legalMake(m[i])) continue;
            long c = d <= 1 ? 1 : perft(d - 1, false);
            unmake(m[i]);
            tot += c;
            if (root) System.out.println(str(m[i]) + ": " + c);
        }
        return tot;
    }

    // ---------- eval ----------
    static int[][] PST = new int[7][128];
    static int[] KMG = new int[128], KEG = new int[128];
    static {
        for (int s = 0; s < 128; s++) {
            if ((s & 0x88) != 0) continue;
            int f = s & 7, r = s >> 4;
            int dist = (Math.abs(2 * f - 7) + Math.abs(2 * r - 7)) / 2; // 1..7
            int cf = Math.min(f, 7 - f);
            PST[1][s] = (r - 1) * 8 + (r >= 1 && r <= 6 ? (cf >= 2 ? 6 : 0) * Math.min(r, 4) / 2 : 0);
            PST[2][s] = -9 * dist;
            PST[3][s] = -4 * dist;
            PST[4][s] = (r == 6 ? 15 : 0) + (cf >= 2 ? 3 : 0);
            PST[5][s] = -2 * dist;
            KMG[s] = -12 * r + (r == 0 && (f == 6 || f == 1) ? 25 : 0) - (cf >= 2 ? 10 : 0);
            KEG[s] = -10 * dist;
        }
    }

    int eval() {
        int sc = 0, phase = 0;
        int[] bishops = new int[2];
        int kmg = 0, keg = 0;
        for (int s = 0; s < 128; s++) {
            if ((s & 0x88) != 0) { s += 7; continue; }
            int p = b[s];
            if (p == 0) continue;
            int col = p >> 3, ty = p & 7;
            int sq = col == 0 ? s : (s ^ 0x70);
            int v;
            if (ty == 6) {
                int a = KMG[sq], e = KEG[sq];
                if (col == 0) { kmg += a; keg += e; } else { kmg -= a; keg -= e; }
                continue;
            }
            v = VAL[ty] + PST[ty][sq];
            if (ty == 1) {
                // passed pawn
                boolean passed = true;
                int dir = col == 0 ? 16 : -16;
                int f = s & 7;
                for (int t = s + dir; (t & 0x88) == 0 && passed; t += dir)
                    for (int dd = -1; dd <= 1; dd++) {
                        int u = t + dd;
                        if ((u & 0x88) == 0 && b[u] == (1 | ((col ^ 1) << 3))) { passed = false; break; }
                    }
                if (passed) { int rr = col == 0 ? s >> 4 : 7 - (s >> 4); v += rr * rr * 3; }
            } else {
                if (ty == 3) bishops[col]++;
                phase += ty == 5 ? 4 : ty == 4 ? 2 : 1;
            }
            sc += col == 0 ? v : -v;
        }
        if (bishops[0] >= 2) sc += 30;
        if (bishops[1] >= 2) sc -= 30;
        if (phase > 24) phase = 24;
        sc += (kmg * phase + keg * (24 - phase)) / 24;
        return side == 0 ? sc : -sc;
    }

    // ---------- search ----------
    static final int TTS = 1 << 21;
    long[] ttKey = new long[TTS];
    int[] ttMove = new int[TTS], ttScore = new int[TTS];
    byte[] ttDepth = new byte[TTS], ttFlag = new byte[TTS];
    int[][] mv = new int[MAXP + 4][256], sc = new int[MAXP + 4][256];
    int[][] killers = new int[MAXP + 4][2];
    int[][][] hist = new int[2][128][128];
    volatile boolean stop;
    long nodes, startTime, limitMs;
    boolean timed;
    int rootBest;

    boolean hasNonPawn(int s) {
        for (int i = 0; i < 128; i++) {
            if ((i & 0x88) != 0) { i += 7; continue; }
            int p = b[i];
            if (p != 0 && (p >> 3) == s && (p & 7) >= 2 && (p & 7) <= 5) return true;
        }
        return false;
    }

    boolean repeated() {
        if (half >= 100) return true;
        for (int i = hply - 2; i >= 0 && i >= hply - half; i -= 2)
            if (stHash[i] == hash) return true;
        return false;
    }

    int qsearch(int alpha, int beta, int ply) {
        nodes++;
        if ((nodes & 2047) == 0 && timed && System.currentTimeMillis() - startTime >= limitMs) stop = true;
        if (stop) return 0;
        int stand = eval();
        if (ply >= MAXP || stand >= beta) return stand;
        if (stand > alpha) alpha = stand;
        int[] m = mv[ply], s = sc[ply];
        int n = gen(m, true);
        for (int i = 0; i < n; i++) {
            int x = m[i];
            int vic = (x & EP) != 0 ? 1 : b[(x >> 7) & 127] & 7;
            s[i] = vic * 16 - (b[x & 127] & 7) + (((x >> 14) & 7) != 0 ? 100 : 0);
        }
        for (int i = 0; i < n; i++) {
            int bi = i;
            for (int j = i + 1; j < n; j++) if (s[j] > s[bi]) bi = j;
            int t = m[i]; m[i] = m[bi]; m[bi] = t; t = s[i]; s[i] = s[bi]; s[bi] = t;
            if (!legalMake(m[i])) continue;
            int v = -qsearch(-beta, -alpha, ply + 1);
            unmake(m[i]);
            if (stop) return 0;
            if (v >= beta) return v;
            if (v > alpha) alpha = v;
        }
        return alpha;
    }

    int search(int depth, int alpha, int beta, int ply, boolean nullOk) {
        nodes++;
        if ((nodes & 2047) == 0 && timed && System.currentTimeMillis() - startTime >= limitMs) stop = true;
        if (stop) return 0;
        if (ply > 0 && repeated()) return 0;
        if (ply >= MAXP) return eval();
        boolean inCheck = attacked(ks[side], side ^ 1);
        if (inCheck) depth++;
        if (depth <= 0) return qsearch(alpha, beta, ply);
        int idx = (int) (hash & (TTS - 1));
        int ttm = 0;
        if (ttKey[idx] == hash) {
            ttm = ttMove[idx];
            if (ply > 0 && ttDepth[idx] >= depth) {
                int v = ttScore[idx];
                if (v > MATE - 200) v -= ply; else if (v < -MATE + 200) v += ply;
                int fl = ttFlag[idx];
                if (fl == 0) return v;
                if (fl == 1 && v >= beta) return v;
                if (fl == 2 && v <= alpha) return v;
            }
        }
        if (ply == 0 && rootBest != 0) ttm = rootBest;
        if (nullOk && !inCheck && depth >= 3 && ply > 0 && beta < MATE - 200 && hasNonPawn(side) && eval() >= beta) {
            makeNull();
            int v = -search(depth - 3, -beta, -beta + 1, ply + 1, false);
            unmakeNull();
            if (stop) return 0;
            if (v >= beta) return beta;
        }
        int[] m = mv[ply], s = sc[ply];
        int n = gen(m, false);
        for (int i = 0; i < n; i++) {
            int x = m[i];
            if (x == ttm) s[i] = 2000000;
            else if ((x & CAP) != 0) {
                int vic = (x & EP) != 0 ? 1 : b[(x >> 7) & 127] & 7;
                s[i] = 1000000 + vic * 16 - (b[x & 127] & 7);
            } else if (((x >> 14) & 7) != 0) s[i] = 1000000 + 500;
            else if (x == killers[ply][0]) s[i] = 900000;
            else if (x == killers[ply][1]) s[i] = 800000;
            else s[i] = hist[side][x & 127][(x >> 7) & 127];
        }
        int legal = 0, bestM = 0, best = -MATE - 1, origAlpha = alpha;
        for (int i = 0; i < n; i++) {
            int bi = i;
            for (int j = i + 1; j < n; j++) if (s[j] > s[bi]) bi = j;
            int t = m[i]; m[i] = m[bi]; m[bi] = t; t = s[i]; s[i] = s[bi]; s[bi] = t;
            int x = m[i];
            if (!legalMake(x)) continue;
            legal++;
            boolean quiet = (x & CAP) == 0 && ((x >> 14) & 7) == 0;
            int v;
            if (legal == 1) v = -search(depth - 1, -beta, -alpha, ply + 1, true);
            else {
                int red = (legal > 4 && depth >= 3 && quiet && !inCheck) ? 1 : 0;
                v = -search(depth - 1 - red, -alpha - 1, -alpha, ply + 1, true);
                if (v > alpha && !stop && (red > 0 || v < beta)) v = -search(depth - 1, -beta, -alpha, ply + 1, true);
            }
            unmake(x);
            if (stop) return 0;
            if (v > best) {
                best = v; bestM = x;
                if (v > alpha) {
                    alpha = v;
                    if (ply == 0) rootBest = x;
                    if (v >= beta) {
                        if (quiet) {
                            if (killers[ply][0] != x) { killers[ply][1] = killers[ply][0]; killers[ply][0] = x; }
                            hist[side][x & 127][(x >> 7) & 127] += depth * depth;
                        }
                        break;
                    }
                }
            }
        }
        if (legal == 0) return inCheck ? -MATE + ply : 0;
        int fl = best >= beta ? 1 : best > origAlpha ? 0 : 2;
        int sv = best;
        if (sv > MATE - 200) sv += ply; else if (sv < -MATE + 200) sv -= ply;
        ttKey[idx] = hash; ttMove[idx] = bestM; ttScore[idx] = sv; ttDepth[idx] = (byte) Math.min(depth, 100); ttFlag[idx] = (byte) fl;
        return best;
    }

    void think(int maxDepth, boolean timedSearch, long soft, long hard) {
        stop = false; timed = timedSearch; limitMs = hard; nodes = 0;
        startTime = System.currentTimeMillis();
        rootBest = 0;
        for (int[] k : killers) { k[0] = 0; k[1] = 0; }
        int[] m = new int[256];
        int n = gen(m, false), first = 0, cnt = 0;
        for (int i = 0; i < n; i++) if (legalMake(m[i])) { unmake(m[i]); if (cnt++ == 0) first = m[i]; }
        if (cnt == 0) { System.out.println("bestmove 0000"); return; }
        int best = first;
        for (int d = 1; d <= maxDepth; d++) {
            int v = search(d, -MATE - 1, MATE + 1, 0, false);
            if (stop && d > 1) break;
            if (rootBest != 0) best = rootBest;
            long el = System.currentTimeMillis() - startTime;
            System.out.println("info depth " + d + " score " + (Math.abs(v) > MATE - 200 ? "mate " + ((v > 0 ? MATE - v + 1 : -(MATE + v)) / (v > 0 ? 2 : 2)) : "cp " + v)
                + " nodes " + nodes + " time " + el + " pv " + str(best));
            if (stop) break;
            if (timedSearch && el >= soft) break;
            if (v > MATE - 200 && timedSearch && d >= 2) break;
            if (cnt == 1 && timedSearch && d >= 4) break;
        }
        System.out.println("bestmove " + str(best));
        System.out.flush();
    }

    // ---------- UCI ----------
    void applyMoves(String[] t, int i) {
        for (; i < t.length; i++) {
            int[] m = new int[256];
            int n = gen(m, false);
            for (int j = 0; j < n; j++) {
                if (str(m[j]).equals(t[i])) { make(m[j]); break; }
            }
        }
    }

    Thread th;

    void join() {
        stop = true;
        try { if (th != null) th.join(); } catch (InterruptedException e) { }
        th = null;
    }

    public static void main(String[] a) throws IOException {
        Engine e = new Engine();
        e.setFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
        BufferedReader in = new BufferedReader(new InputStreamReader(System.in));
        String line;
        while ((line = in.readLine()) != null) {
            String[] t = line.trim().split("\\s+");
            if (t[0].isEmpty()) continue;
            switch (t[0]) {
                case "uci":
                    System.out.println("id name JChess\nid author agent\nuciok"); break;
                case "isready": System.out.println("readyok"); break;
                case "ucinewgame":
                    e.join();
                    Arrays.fill(e.ttKey, 0);
                    for (int[][] x : e.hist) for (int[] y : x) Arrays.fill(y, 0);
                    break;
                case "position": {
                    e.join();
                    int i = 1;
                    if (t[1].equals("startpos")) { e.setFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"); i = 2; }
                    else {
                        StringBuilder sb = new StringBuilder();
                        i = 2;
                        while (i < t.length && !t[i].equals("moves")) sb.append(t[i++]).append(' ');
                        e.setFen(sb.toString());
                    }
                    if (i < t.length && t[i].equals("moves")) e.applyMoves(t, i + 1);
                    break;
                }
                case "go": {
                    e.join();
                    int depth = 64; long mt = -1, wt = -1, bt = -1, wi = 0, bi = 0; boolean perft = false, inf = false;
                    int pd = 0;
                    for (int i = 1; i < t.length; i++) {
                        switch (t[i]) {
                            case "depth": depth = Integer.parseInt(t[++i]); break;
                            case "movetime": mt = Long.parseLong(t[++i]); break;
                            case "wtime": wt = Long.parseLong(t[++i]); break;
                            case "btime": bt = Long.parseLong(t[++i]); break;
                            case "winc": wi = Long.parseLong(t[++i]); break;
                            case "binc": bi = Long.parseLong(t[++i]); break;
                            case "perft": perft = true; pd = Integer.parseInt(t[++i]); break;
                            case "infinite": inf = true; break;
                        }
                    }
                    if (perft) {
                        long n = pd <= 0 ? 1 : e.perft(pd, true);
                        System.out.println("Nodes searched: " + n);
                        System.out.flush();
                        break;
                    }
                    final int fd = depth;
                    boolean timed = false; long soft = 0, hard = 0;
                    if (mt >= 0) { timed = true; hard = Math.max(1, mt - 30); soft = hard * 6 / 10; }
                    else if (!inf && (wt >= 0 || bt >= 0)) {
                        long my = e.side == 0 ? wt : bt, inc = e.side == 0 ? wi : bi;
                        if (my < 0) my = 1000;
                        long alloc = my / 25 + inc * 3 / 4;
                        alloc = Math.min(alloc, my / 3);
                        alloc = Math.max(alloc - 30, 5);
                        timed = true; hard = alloc; soft = alloc * 6 / 10;
                    }
                    final boolean ft = timed; final long fs = soft, fh = hard;
                    e.th = new Thread(null, () -> e.think(fd, ft, fs, fh), "search", 64L << 20);
                    e.th.start();
                    break;
                }
                case "stop": e.join(); break;
                case "quit": e.join(); System.exit(0); break;
            }
            System.out.flush();
        }
        e.join();
    }
}
