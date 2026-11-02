import java.io.*;
import java.util.*;

public class Main {
    static final int[] KN = {33, 31, 18, 14, -33, -31, -18, -14};
    static final int[] KG = {1, -1, 16, -16, 17, 15, -17, -15};
    static final int[] BD = {17, 15, -17, -15};
    static final int[] RD = {1, -1, 16, -16};
    static final int MATE = 30000, INF = 32000, MAXP = 100;

    static int[] board = new int[128];
    static int side, castle, ep, half, hp;
    static int[] kingSq = new int[2];
    static long hash;
    static int[] uCap = new int[4096], uCastle = new int[4096], uEp = new int[4096], uHalf = new int[4096];
    static long[] hashes = new long[4096];
    static long[][] zp = new long[16][128];
    static long[] zCastle = new long[16], zEp = new long[8];
    static long zSide;
    static int[] cm = new int[128];

    static {
        Random r = new Random(12345);
        for (long[] a : zp) for (int i = 0; i < 128; i++) a[i] = r.nextLong();
        for (int i = 0; i < 16; i++) zCastle[i] = r.nextLong();
        for (int i = 0; i < 8; i++) zEp[i] = r.nextLong();
        zSide = r.nextLong();
        Arrays.fill(cm, 15);
        cm[0x04] = 12; cm[0x00] = 13; cm[0x07] = 14;
        cm[0x74] = 3; cm[0x70] = 7; cm[0x77] = 11;
    }

    // ---------- position setup ----------
    static void setFen(String fen) {
        Arrays.fill(board, 0);
        String[] t = fen.trim().split("\\s+");
        int r = 7, f = 0;
        for (char c : t[0].toCharArray()) {
            if (c == '/') { r--; f = 0; }
            else if (Character.isDigit(c)) f += c - '0';
            else {
                int p = "PNBRQK".indexOf(Character.toUpperCase(c)) + 1;
                if (Character.isLowerCase(c)) p |= 8;
                board[r * 16 + f] = p;
                if ((p & 7) == 6) kingSq[p >> 3] = r * 16 + f;
                f++;
            }
        }
        side = t.length > 1 && t[1].equals("b") ? 1 : 0;
        castle = 0;
        String cs = t.length > 2 ? t[2] : "-";
        for (char c : cs.toCharArray()) {
            if (c == 'K') castle |= 1; if (c == 'Q') castle |= 2;
            if (c == 'k') castle |= 4; if (c == 'q') castle |= 8;
        }
        ep = -1;
        if (t.length > 3 && t[3].length() == 2) ep = (t[3].charAt(1) - '1') * 16 + (t[3].charAt(0) - 'a');
        half = t.length > 4 ? Integer.parseInt(t[4]) : 0;
        hp = 0;
        computeHash();
    }

    static void computeHash() {
        long h = 0;
        for (int r = 0; r < 8; r++) for (int f = 0; f < 8; f++) {
            int p = board[r * 16 + f];
            if (p != 0) h ^= zp[p][r * 16 + f];
        }
        if (side == 1) h ^= zSide;
        h ^= zCastle[castle];
        if (ep >= 0) h ^= zEp[ep & 7];
        hash = h;
    }

    // ---------- attacks ----------
    static boolean attacked(int sq, int by) {
        int s;
        if (by == 0) {
            s = sq - 15; if ((s & 0x88) == 0 && board[s] == 1) return true;
            s = sq - 17; if ((s & 0x88) == 0 && board[s] == 1) return true;
        } else {
            s = sq + 15; if ((s & 0x88) == 0 && board[s] == 9) return true;
            s = sq + 17; if ((s & 0x88) == 0 && board[s] == 9) return true;
        }
        int hi = by << 3;
        for (int d : KN) { s = sq + d; if ((s & 0x88) == 0 && board[s] == (2 | hi)) return true; }
        for (int d : KG) { s = sq + d; if ((s & 0x88) == 0 && board[s] == (6 | hi)) return true; }
        for (int d : BD) {
            s = sq + d;
            while ((s & 0x88) == 0) {
                int p = board[s];
                if (p != 0) { if (p == (3 | hi) || p == (5 | hi)) return true; break; }
                s += d;
            }
        }
        for (int d : RD) {
            s = sq + d;
            while ((s & 0x88) == 0) {
                int p = board[s];
                if (p != 0) { if (p == (4 | hi) || p == (5 | hi)) return true; break; }
                s += d;
            }
        }
        return false;
    }

    // ---------- move generation ----------
    static int mv(int from, int to, int promo, int fl) { return from | (to << 7) | (promo << 14) | (fl << 17); }

    static int gen(int[] m, boolean caps) {
        int n = 0;
        int us = side, hi = us << 3;
        for (int r = 0; r < 8; r++) for (int f = 0; f < 8; f++) {
            int from = r * 16 + f, p = board[from];
            if (p == 0 || (p >> 3) != us) continue;
            int t = p & 7;
            if (t == 1) {
                int dir = us == 0 ? 16 : -16;
                int promoRank = us == 0 ? 6 : 1, startRank = us == 0 ? 1 : 6;
                int to = from + dir;
                if (board[to] == 0) {
                    if (r == promoRank) { for (int pr = 5; pr >= 2; pr--) m[n++] = mv(from, to, pr, 0); }
                    else if (!caps) {
                        m[n++] = mv(from, to, 0, 0);
                        if (r == startRank && board[to + dir] == 0) m[n++] = mv(from, to + dir, 0, 8);
                    }
                }
                for (int dc = -1; dc <= 1; dc += 2) {
                    to = from + dir + dc;
                    if ((to & 0x88) != 0) continue;
                    int q = board[to];
                    if (q != 0 && (q >> 3) != us) {
                        if (r == promoRank) { for (int pr = 5; pr >= 2; pr--) m[n++] = mv(from, to, pr, 1); }
                        else m[n++] = mv(from, to, 0, 1);
                    } else if (q == 0 && to == ep) m[n++] = mv(from, to, 0, 3);
                }
            } else if (t == 2 || t == 6) {
                int[] ds = t == 2 ? KN : KG;
                for (int d : ds) {
                    int to = from + d;
                    if ((to & 0x88) != 0) continue;
                    int q = board[to];
                    if (q == 0) { if (!caps) m[n++] = mv(from, to, 0, 0); }
                    else if ((q >> 3) != us) m[n++] = mv(from, to, 0, 1);
                }
                if (t == 6 && !caps) {
                    int e = us == 0 ? 0x04 : 0x74;
                    if (from == e && !attacked(e, us ^ 1)) {
                        if ((castle & (us == 0 ? 1 : 4)) != 0 && board[e + 1] == 0 && board[e + 2] == 0
                                && board[e + 3] == (4 | hi) && !attacked(e + 1, us ^ 1) && !attacked(e + 2, us ^ 1))
                            m[n++] = mv(e, e + 2, 0, 4);
                        if ((castle & (us == 0 ? 2 : 8)) != 0 && board[e - 1] == 0 && board[e - 2] == 0 && board[e - 3] == 0
                                && board[e - 4] == (4 | hi) && !attacked(e - 1, us ^ 1) && !attacked(e - 2, us ^ 1))
                            m[n++] = mv(e, e - 2, 0, 4);
                    }
                }
            } else {
                for (int k = 0; k < 8; k++) {
                    int d = KG[k];
                    boolean diag = k >= 4;
                    if (t == 3 && !diag) continue;
                    if (t == 4 && diag) continue;
                    int to = from + d;
                    while ((to & 0x88) == 0) {
                        int q = board[to];
                        if (q == 0) { if (!caps) m[n++] = mv(from, to, 0, 0); }
                        else { if ((q >> 3) != us) m[n++] = mv(from, to, 0, 1); break; }
                        to += d;
                    }
                }
            }
        }
        return n;
    }

    static void make(int m) {
        int from = m & 127, to = (m >> 7) & 127, promo = (m >> 14) & 7, fl = m >> 17;
        int p = board[from], us = side;
        int cap = board[to];
        uCastle[hp] = castle; uEp[hp] = ep; uHalf[hp] = half; hashes[hp] = hash;
        hash ^= zCastle[castle];
        if (ep >= 0) hash ^= zEp[ep & 7];
        board[from] = 0; hash ^= zp[p][from];
        if ((fl & 2) != 0) {
            int cs = to + (us == 0 ? -16 : 16);
            cap = board[cs]; board[cs] = 0; hash ^= zp[cap][cs];
        } else if (cap != 0) hash ^= zp[cap][to];
        uCap[hp] = cap; hp++;
        int np = promo != 0 ? (promo | (us << 3)) : p;
        board[to] = np; hash ^= zp[np][to];
        if ((fl & 4) != 0) {
            int rf, rt;
            if (to > from) { rf = to + 1; rt = to - 1; } else { rf = to - 2; rt = to + 1; }
            int r = board[rf]; board[rf] = 0; board[rt] = r;
            hash ^= zp[r][rf] ^ zp[r][rt];
        }
        if ((p & 7) == 6) kingSq[us] = to;
        castle &= cm[from] & cm[to];
        ep = (fl & 8) != 0 ? (from + to) / 2 : -1;
        if (ep >= 0) hash ^= zEp[ep & 7];
        hash ^= zCastle[castle] ^ zSide;
        half = ((p & 7) == 1 || cap != 0) ? 0 : half + 1;
        side ^= 1;
    }

    static void unmake(int m) {
        int from = m & 127, to = (m >> 7) & 127, promo = (m >> 14) & 7, fl = m >> 17;
        hp--; side ^= 1;
        int us = side;
        castle = uCastle[hp]; ep = uEp[hp]; half = uHalf[hp]; hash = hashes[hp];
        int cap = uCap[hp];
        int np = board[to];
        int p = promo != 0 ? (1 | (us << 3)) : np;
        board[from] = p; board[to] = 0;
        if ((fl & 2) != 0) board[to + (us == 0 ? -16 : 16)] = cap; else board[to] = cap;
        if ((fl & 4) != 0) {
            int rf, rt;
            if (to > from) { rf = to + 1; rt = to - 1; } else { rf = to - 2; rt = to + 1; }
            board[rf] = board[rt]; board[rt] = 0;
        }
        if ((p & 7) == 6) kingSq[us] = from;
    }

    static void makeNull() {
        hashes[hp] = hash; uEp[hp] = ep; uHalf[hp] = half; hp++;
        if (ep >= 0) hash ^= zEp[ep & 7];
        ep = -1; hash ^= zSide; side ^= 1; half++;
    }
    static void unmakeNull() {
        hp--; side ^= 1; ep = uEp[hp]; half = uHalf[hp]; hash = hashes[hp];
    }

    static boolean legalMake(int m) {
        int us = side;
        make(m);
        if (attacked(kingSq[us], us ^ 1)) { unmake(m); return false; }
        return true;
    }

    static String moveStr(int m) {
        int from = m & 127, to = (m >> 7) & 127, promo = (m >> 14) & 7;
        String s = "" + (char) ('a' + (from & 7)) + (char) ('1' + (from >> 4)) + (char) ('a' + (to & 7)) + (char) ('1' + (to >> 4));
        if (promo != 0) s += "  nbrq".charAt(promo) == ' ' ? "" : "nbrq".charAt(promo - 2);
        return s;
    }

    static long perft(int d) {
        if (d == 0) return 1;
        int[] ms = new int[256];
        int n = gen(ms, false);
        long tot = 0;
        for (int i = 0; i < n; i++) {
            if (!legalMake(ms[i])) continue;
            tot += d == 1 ? 1 : perft(d - 1);
            unmake(ms[i]);
        }
        return tot;
    }

    // ---------- evaluation ----------
    static int[][] pst = new int[7][];
    static int[] kEnd;
    static final int[] VAL = {0, 100, 320, 330, 500, 900, 0};
    static {
        pst[1] = new int[]{0,0,0,0,0,0,0,0, 50,50,50,50,50,50,50,50, 10,10,20,30,30,20,10,10, 5,5,10,25,25,10,5,5,
            0,0,0,20,20,0,0,0, 5,-5,-10,0,0,-10,-5,5, 5,10,10,-20,-20,10,10,5, 0,0,0,0,0,0,0,0};
        pst[2] = new int[]{-50,-40,-30,-30,-30,-30,-40,-50, -40,-20,0,0,0,0,-20,-40, -30,0,10,15,15,10,0,-30, -30,5,15,20,20,15,5,-30,
            -30,0,15,20,20,15,0,-30, -30,5,10,15,15,10,5,-30, -40,-20,0,5,5,0,-20,-40, -50,-40,-30,-30,-30,-30,-40,-50};
        pst[3] = new int[]{-20,-10,-10,-10,-10,-10,-10,-20, -10,0,0,0,0,0,0,-10, -10,0,5,10,10,5,0,-10, -10,5,5,10,10,5,5,-10,
            -10,0,10,10,10,10,0,-10, -10,10,10,10,10,10,10,-10, -10,5,0,0,0,0,5,-10, -20,-10,-10,-10,-10,-10,-10,-20};
        pst[4] = new int[]{0,0,0,0,0,0,0,0, 5,10,10,10,10,10,10,5, -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5,
            -5,0,0,0,0,0,0,-5, -5,0,0,0,0,0,0,-5, 0,0,0,5,5,0,0,0};
        pst[5] = new int[]{-20,-10,-10,-5,-5,-10,-10,-20, -10,0,0,0,0,0,0,-10, -10,0,5,5,5,5,0,-10, -5,0,5,5,5,5,0,-5,
            0,0,5,5,5,5,0,-5, -10,5,5,5,5,5,0,-10, -10,0,5,0,0,0,0,-10, -20,-10,-10,-5,-5,-10,-10,-20};
        pst[6] = new int[]{-30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30, -30,-40,-40,-50,-50,-40,-40,-30,
            -30,-40,-40,-50,-50,-40,-40,-30, -20,-30,-30,-40,-40,-30,-30,-20, -10,-20,-20,-20,-20,-20,-20,-10,
            20,20,0,0,0,0,20,20, 20,30,10,0,0,10,30,20};
        kEnd = new int[]{-50,-40,-30,-20,-20,-30,-40,-50, -30,-20,-10,0,0,-10,-20,-30, -30,-10,20,30,30,20,-10,-30,
            -30,-10,30,40,40,30,-10,-30, -30,-10,30,40,40,30,-10,-30, -30,-10,20,30,30,20,-10,-30,
            -30,-30,0,0,0,0,-30,-30, -50,-30,-30,-30,-30,-30,-30,-50};
    }

    static int eval() {
        int score = 0, phase = 0;
        int[] bishops = new int[2];
        for (int r = 0; r < 8; r++) for (int f = 0; f < 8; f++) {
            int p = board[r * 16 + f];
            if (p == 0) continue;
            int t = p & 7, c = p >> 3;
            int v;
            if (t == 6) v = 0;
            else {
                v = VAL[t] + pst[t][c == 0 ? (7 - r) * 8 + f : r * 8 + f];
                phase += t == 2 || t == 3 ? 1 : t == 4 ? 2 : t == 5 ? 4 : 0;
                if (t == 3) bishops[c]++;
            }
            score += c == 0 ? v : -v;
        }
        if (bishops[0] >= 2) score += 30;
        if (bishops[1] >= 2) score -= 30;
        if (phase > 24) phase = 24;
        int wk = kingSq[0], bk = kingSq[1];
        int wm = pst[6][(7 - (wk >> 4)) * 8 + (wk & 7)], we = kEnd[(7 - (wk >> 4)) * 8 + (wk & 7)];
        int bm = pst[6][(bk >> 4) * 8 + (bk & 7)], be = kEnd[(bk >> 4) * 8 + (bk & 7)];
        score += ((wm - bm) * phase + (we - be) * (24 - phase)) / 24;
        if (phase <= 8 && Math.abs(score) > 200) {
            int loser = score > 0 ? bk : wk, winner = score > 0 ? wk : bk;
            int lf = loser & 7, lr = loser >> 4;
            int cd = Math.max(3 - lf, lf - 4) + Math.max(3 - lr, lr - 4);
            int dist = Math.abs((loser & 7) - (winner & 7)) + Math.abs((loser >> 4) - (winner >> 4));
            int bonus = (cd * 10 + (14 - dist) * 4) * (8 - phase) / 8;
            score += score > 0 ? bonus : -bonus;
        }
        return side == 0 ? score : -score;
    }

    // ---------- search ----------
    static final int TTN = 1 << 21;
    static long[] ttKey = new long[TTN];
    static int[] ttMove = new int[TTN], ttScore = new int[TTN];
    static byte[] ttDepth = new byte[TTN], ttFlag = new byte[TTN];
    static int[][] mvs = new int[MAXP + 2][256], scs = new int[MAXP + 2][256];
    static int[][] killers = new int[MAXP + 2][2];
    static int[][] history = new int[16][128];
    static volatile boolean stop;
    static long nodes, startT, softMs, hardMs;
    static int rootBest, doneBest;

    static void checkTime() {
        if (hardMs > 0 && System.currentTimeMillis() - startT >= hardMs) stop = true;
    }

    static boolean repeated() {
        int lim = Math.min(half, hp);
        for (int i = 2; i <= lim; i += 2) if (hashes[hp - i] == hash) return true;
        return false;
    }

    static boolean hasPieces(int s) {
        for (int r = 0; r < 8; r++) for (int f = 0; f < 8; f++) {
            int p = board[r * 16 + f];
            if (p != 0 && (p >> 3) == s) { int t = p & 7; if (t >= 2 && t <= 5) return true; }
        }
        return false;
    }

    static int capScore(int m) {
        int v = board[(m >> 7) & 127] & 7;
        if ((m >> 17 & 2) != 0) v = 1;
        int a = board[m & 127] & 7;
        return v * 16 - a + 100000 + ((m >> 14) & 7) * 20;
    }

    static int qsearch(int alpha, int beta, int ply) {
        if ((nodes++ & 2047) == 0) checkTime();
        if (stop) return 0;
        int stand = eval();
        if (ply >= MAXP) return stand;
        if (stand >= beta) return stand;
        if (stand > alpha) alpha = stand;
        int[] ms = mvs[ply], sc = scs[ply];
        int n = gen(ms, true);
        for (int i = 0; i < n; i++) sc[i] = capScore(ms[i]);
        for (int i = 0; i < n; i++) {
            int b = i;
            for (int j = i + 1; j < n; j++) if (sc[j] > sc[b]) b = j;
            int m = ms[b]; ms[b] = ms[i]; ms[i] = m; int t = sc[b]; sc[b] = sc[i]; sc[i] = t;
            if (!legalMake(m)) continue;
            int s = -qsearch(-beta, -alpha, ply + 1);
            unmake(m);
            if (stop) return 0;
            if (s > stand) {
                stand = s;
                if (s > alpha) { alpha = s; if (s >= beta) break; }
            }
        }
        return stand;
    }

    static int search(int depth, int alpha, int beta, int ply, boolean nullOk) {
        if ((nodes++ & 2047) == 0) checkTime();
        if (stop) return 0;
        if (ply > 0 && (half >= 100 || repeated())) return 0;
        if (ply >= MAXP) return eval();
        boolean inCheck = attacked(kingSq[side], side ^ 1);
        if (inCheck) depth++;
        if (depth <= 0) return qsearch(alpha, beta, ply);
        if (ply > 0) {
            alpha = Math.max(alpha, -MATE + ply); beta = Math.min(beta, MATE - ply - 1);
            if (alpha >= beta) return alpha;
        }
        int alphaOrig = alpha;
        boolean pv = beta - alpha > 1;
        int idx = (int) (hash & (TTN - 1));
        int tm = 0;
        if (ttKey[idx] == hash) {
            tm = ttMove[idx];
            if (ply > 0 && ttDepth[idx] >= depth) {
                int s = ttScore[idx];
                if (s > MATE - 200) s -= ply; else if (s < -MATE + 200) s += ply;
                int fl = ttFlag[idx];
                if (fl == 0 || (fl == 1 && s >= beta) || (fl == 2 && s <= alpha)) return s;
            }
        }
        if (nullOk && !inCheck && !pv && depth >= 3 && ply > 0 && hasPieces(side) && eval() >= beta) {
            makeNull();
            int s = -search(depth - 3 - depth / 6, -beta, -beta + 1, ply + 1, false);
            unmakeNull();
            if (stop) return 0;
            if (s >= beta) return s >= MATE - 200 ? beta : s;
        }
        int[] ms = mvs[ply], sc = scs[ply];
        int n = gen(ms, false);
        for (int i = 0; i < n; i++) {
            int m = ms[i];
            if (m == tm || (ply == 0 && m == doneBest)) sc[i] = 2000000;
            else if ((m >> 17 & 1) != 0 || ((m >> 14) & 7) != 0) sc[i] = capScore(m);
            else if (m == killers[ply][0]) sc[i] = 90000;
            else if (m == killers[ply][1]) sc[i] = 80000;
            else sc[i] = history[board[m & 127]][(m >> 7) & 127];
        }
        int best = -INF, bm = 0, legal = 0;
        for (int i = 0; i < n; i++) {
            int b = i;
            for (int j = i + 1; j < n; j++) if (sc[j] > sc[b]) b = j;
            int m = ms[b]; ms[b] = ms[i]; ms[i] = m; int t = sc[b]; sc[b] = sc[i]; sc[i] = t;
            int us = side;
            int piece = board[m & 127];
            if (!legalMake(m)) continue;
            legal++;
            boolean quiet = (m >> 17 & 1) == 0 && ((m >> 14) & 7) == 0;
            int s;
            if (legal == 1) s = -search(depth - 1, -beta, -alpha, ply + 1, true);
            else {
                int r = 0;
                if (depth >= 3 && legal > 4 && quiet && !inCheck && !attacked(kingSq[side], side ^ 1)) r = legal > 10 ? 2 : 1;
                s = -search(depth - 1 - r, -alpha - 1, -alpha, ply + 1, true);
                if (s > alpha && r > 0) s = -search(depth - 1, -alpha - 1, -alpha, ply + 1, true);
                if (s > alpha && s < beta) s = -search(depth - 1, -beta, -alpha, ply + 1, true);
            }
            unmake(m);
            if (stop) return 0;
            if (s > best) {
                best = s; bm = m;
                if (s > alpha) {
                    alpha = s;
                    if (ply == 0) rootBest = m;
                    if (s >= beta) {
                        if (quiet) {
                            if (killers[ply][0] != m) { killers[ply][1] = killers[ply][0]; killers[ply][0] = m; }
                            history[piece][(m >> 7) & 127] += depth * depth;
                        }
                        break;
                    }
                }
            }
        }
        if (legal == 0) return inCheck ? -MATE + ply : 0;
        int fl = best >= beta ? 1 : best > alphaOrig ? 0 : 2;
        int st = best;
        if (st > MATE - 200) st += ply; else if (st < -MATE + 200) st -= ply;
        ttKey[idx] = hash; ttMove[idx] = bm; ttScore[idx] = st; ttDepth[idx] = (byte) Math.min(depth, 100); ttFlag[idx] = (byte) fl;
        return best;
    }

    static void think(int maxDepth) {
        stop = false; nodes = 0; startT = System.currentTimeMillis();
        for (int[] k : killers) { k[0] = 0; k[1] = 0; }
        for (int[] h : history) Arrays.fill(h, 0);
        doneBest = 0; rootBest = 0;
        int[] ms = new int[256];
        int cnt = gen(ms, false), first = 0;
        for (int i = 0; i < cnt; i++) if (legalMake(ms[i])) { unmake(ms[i]); if (first == 0) first = ms[i]; }
        if (first == 0) { System.out.println("bestmove 0000"); return; }
        doneBest = first;
        for (int d = 1; d <= maxDepth; d++) {
            int s = search(d, -INF, INF, 0, false);
            if (stop) break;
            doneBest = rootBest != 0 ? rootBest : doneBest;
            long el = System.currentTimeMillis() - startT;
            String sc;
            if (s > MATE - 200) sc = "mate " + ((MATE - s + 1) / 2);
            else if (s < -MATE + 200) sc = "mate -" + ((MATE + s + 1) / 2);
            else sc = "cp " + s;
            System.out.println("info depth " + d + " score " + sc + " nodes " + nodes + " time " + el + " pv " + moveStr(doneBest));
            System.out.flush();
            if (Math.abs(s) > MATE - 200 && d >= 2 && (MATE - Math.abs(s)) < d) break;
            if (softMs > 0 && el > softMs * 6 / 10) break;
        }
        System.out.println("bestmove " + moveStr(doneBest));
        System.out.flush();
    }

    // ---------- UCI ----------
    static Thread worker;

    static void waitSearch() {
        if (worker != null) {
            stop = true;
            try { worker.join(); } catch (InterruptedException e) { }
            worker = null;
        }
    }

    static void applyMoves(String[] t, int from) {
        for (int i = from; i < t.length; i++) {
            int[] ms = new int[256];
            int n = gen(ms, false);
            for (int j = 0; j < n; j++) {
                if (moveStr(ms[j]).equals(t[i]) && legalMake(ms[j])) break;
            }
        }
    }

    public static void main(String[] args) throws IOException {
        BufferedReader in = new BufferedReader(new InputStreamReader(System.in));
        setFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
        String line;
        while ((line = in.readLine()) != null) {
            String[] t = line.trim().split("\\s+");
            if (t.length == 0 || t[0].isEmpty()) continue;
            switch (t[0]) {
                case "uci":
                    System.out.println("id name JChess");
                    System.out.println("id author Claude");
                    System.out.println("uciok");
                    break;
                case "isready": System.out.println("readyok"); break;
                case "ucinewgame":
                    waitSearch();
                    Arrays.fill(ttKey, 0);
                    break;
                case "position": {
                    waitSearch();
                    int i = 1;
                    if (t[1].equals("startpos")) { setFen("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"); i = 2; }
                    else {
                        StringBuilder sb = new StringBuilder();
                        i = 2;
                        while (i < t.length && !t[i].equals("moves")) sb.append(t[i++]).append(' ');
                        setFen(sb.toString());
                    }
                    if (i < t.length && t[i].equals("moves")) applyMoves(t, i + 1);
                    break;
                }
                case "go": {
                    waitSearch();
                    int depth = MAXP - 1; long movetime = -1, wt = -1, bt = -1, wi = 0, bi = 0; int mtg = 0;
                    boolean infinite = false;
                    for (int i = 1; i < t.length; i++) {
                        switch (t[i]) {
                            case "perft": {
                                int d = Integer.parseInt(t[i + 1]);
                                int[] ms = new int[256];
                                int n = gen(ms, false);
                                long tot = 0;
                                for (int k = 0; k < n; k++) {
                                    if (!legalMake(ms[k])) continue;
                                    long c = d <= 1 ? 1 : perft(d - 1);
                                    unmake(ms[k]);
                                    System.out.println(moveStr(ms[k]) + ": " + c);
                                    tot += c;
                                }
                                System.out.println("Nodes searched: " + tot);
                                System.out.flush();
                                depth = -1; i = t.length;
                                break;
                            }
                            case "depth": depth = Integer.parseInt(t[++i]); break;
                            case "movetime": movetime = Long.parseLong(t[++i]); break;
                            case "wtime": wt = Long.parseLong(t[++i]); break;
                            case "btime": bt = Long.parseLong(t[++i]); break;
                            case "winc": wi = Long.parseLong(t[++i]); break;
                            case "binc": bi = Long.parseLong(t[++i]); break;
                            case "movestogo": mtg = Integer.parseInt(t[++i]); break;
                            case "infinite": infinite = true; break;
                        }
                    }
                    if (depth < 0) break;
                    softMs = 0; hardMs = 0;
                    if (movetime >= 0) { softMs = hardMs = Math.max(5, movetime - 40); }
                    else if (!infinite && (wt >= 0 || bt >= 0)) {
                        long tm = side == 0 ? wt : bt, inc = side == 0 ? wi : bi;
                        if (tm < 0) tm = 1000;
                        long alloc = tm / (mtg > 0 ? mtg + 1 : 30) + inc * 3 / 4;
                        alloc = Math.min(alloc, tm * 6 / 10);
                        softMs = Math.max(5, alloc);
                        hardMs = Math.max(10, Math.min(alloc * 3, tm * 7 / 10) - 30);
                        if (hardMs < softMs) hardMs = softMs;
                    }
                    final int fd = depth;
                    worker = new Thread(null, () -> think(fd), "search", 64L << 20);
                    worker.start();
                    break;
                }
                case "stop": waitSearch(); break;
                case "quit": waitSearch(); System.exit(0); break;
            }
            System.out.flush();
        }
        waitSearch();
    }
}
