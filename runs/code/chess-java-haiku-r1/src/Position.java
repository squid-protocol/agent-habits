import java.util.Arrays;
import java.util.Random;

/**
 * Board state on a 0x88 mailbox, with make/unmake, Zobrist hashing and pseudo-legal move generation.
 *
 * Squares: index = rank * 16 + file, a1 = 0, h1 = 7, a8 = 112. Off-board test: (s & 0x88) != 0.
 * Pieces: white type t is stored as t, black type t as 8 + t, empty as 0.
 * Moves: from | to << 7 | promotionType << 14 | flags << 17.
 */
final class Position {
    static final int EMPTY = 0, PAWN = 1, KNIGHT = 2, BISHOP = 3, ROOK = 4, QUEEN = 5, KING = 6;
    static final int WHITE = 0, BLACK = 1;
    static final int CWK = 1, CWQ = 2, CBK = 4, CBQ = 8;
    static final int F_EP = 1 << 17, F_CASTLE = 1 << 18, F_DOUBLE = 1 << 19;
    static final int F_MASK = 7 << 17;
    static final String START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

    static final long[][] Z = new long[16][128];
    static final long[] ZCASTLE = new long[16];
    static final long[] ZEP = new long[8];
    static final long ZSIDE;
    private static final int[] CMASK = new int[128];
    static final int[] ROOK_DIRS = {1, -1, 16, -16};
    static final int[] BISHOP_DIRS = {15, -15, 17, -17};
    static final int[] KING_DIRS = {1, -1, 16, -16, 15, -15, 17, -17};
    static final int[] KNIGHT_DIRS = {33, 31, 18, 14, -33, -31, -18, -14};
    private static final int[] WHITE_PAWN_CAPS = {15, 17};
    private static final int[] BLACK_PAWN_CAPS = {-15, -17};

    static {
        Random r = new Random(0x5EED1234L);
        for (int p = 0; p < 16; p++) for (int s = 0; s < 128; s++) Z[p][s] = r.nextLong();
        for (int i = 0; i < 16; i++) ZCASTLE[i] = r.nextLong();
        for (int i = 0; i < 8; i++) ZEP[i] = r.nextLong();
        ZSIDE = r.nextLong();
        Arrays.fill(CMASK, 15);
        CMASK[0] = 15 & ~CWQ;
        CMASK[4] = 15 & ~(CWK | CWQ);
        CMASK[7] = 15 & ~CWK;
        CMASK[112] = 15 & ~CBQ;
        CMASK[116] = 15 & ~(CBK | CBQ);
        CMASK[119] = 15 & ~CBK;
    }

    final int[] b = new int[128];
    int side, castle, ep = -1, half, full = 1;
    final int[] kingSq = new int[2];
    long key;

    /** Number of entries in the undo stack; the key/move history used for repetition detection. */
    int plies;
    int[] uMove = new int[512], uCap = new int[512], uCastle = new int[512], uEp = new int[512], uHalf = new int[512];
    long[] uKey = new long[512];

    static int pc(int color, int type) { return color == WHITE ? type : 8 + type; }
    static int color(int p) { return p >> 3; }
    static int type(int p) { return p & 7; }
    static int enc(int from, int to, int promo, int flags) { return from | (to << 7) | (promo << 14) | flags; }
    static int from(int m) { return m & 127; }
    static int to(int m) { return (m >> 7) & 127; }
    static int promo(int m) { return (m >> 14) & 7; }

    static String sqName(int s) { return "" + (char) ('a' + (s & 7)) + (char) ('1' + (s >> 4)); }

    static String uci(int m) {
        String s = sqName(from(m)) + sqName(to(m));
        if (promo(m) != 0) s += "xxnbrq".charAt(promo(m));
        return s;
    }

    static Position startpos() {
        Position p = new Position();
        p.setFen(START_FEN);
        return p;
    }

    int at(int s) { return (s & 0x88) != 0 ? -1 : b[s]; }

    Position copy() {
        Position p = new Position();
        System.arraycopy(b, 0, p.b, 0, 128);
        p.side = side;
        p.castle = castle;
        p.ep = ep;
        p.half = half;
        p.full = full;
        p.kingSq[0] = kingSq[0];
        p.kingSq[1] = kingSq[1];
        p.key = key;
        p.plies = plies;
        p.uMove = uMove.clone();
        p.uCap = uCap.clone();
        p.uCastle = uCastle.clone();
        p.uEp = uEp.clone();
        p.uHalf = uHalf.clone();
        p.uKey = uKey.clone();
        return p;
    }

    void setFen(String fen) {
        Arrays.fill(b, EMPTY);
        String[] f = fen.trim().split("\\s+");
        int row = 7, col = 0;
        for (char c : f[0].toCharArray()) {
            if (c == '/') {
                row--;
                col = 0;
            } else if (c >= '1' && c <= '8') {
                col += c - '0';
            } else {
                int color = Character.isUpperCase(c) ? WHITE : BLACK;
                int t;
                switch (Character.toLowerCase(c)) {
                    case 'p': t = PAWN; break;
                    case 'n': t = KNIGHT; break;
                    case 'b': t = BISHOP; break;
                    case 'r': t = ROOK; break;
                    case 'q': t = QUEEN; break;
                    default: t = KING; break;
                }
                int s = row * 16 + col;
                b[s] = pc(color, t);
                if (t == KING) kingSq[color] = s;
                col++;
            }
        }
        side = f.length > 1 && f[1].equals("b") ? BLACK : WHITE;
        castle = 0;
        if (f.length > 2) {
            if (f[2].indexOf('K') >= 0) castle |= CWK;
            if (f[2].indexOf('Q') >= 0) castle |= CWQ;
            if (f[2].indexOf('k') >= 0) castle |= CBK;
            if (f[2].indexOf('q') >= 0) castle |= CBQ;
        }
        ep = -1;
        if (f.length > 3 && f[3].length() >= 2 && f[3].charAt(0) >= 'a' && f[3].charAt(0) <= 'h') {
            ep = (f[3].charAt(1) - '1') * 16 + (f[3].charAt(0) - 'a');
        }
        half = f.length > 4 ? parseIntOr(f[4], 0) : 0;
        full = f.length > 5 ? Math.max(1, parseIntOr(f[5], 1)) : 1;
        plies = 0;
        key = computeKey();
    }

    private static int parseIntOr(String s, int dflt) {
        try {
            return Integer.parseInt(s);
        } catch (NumberFormatException e) {
            return dflt;
        }
    }

    long computeKey() {
        long k = 0;
        for (int s = 0; s < 128; s++) {
            if ((s & 0x88) == 0 && b[s] != EMPTY) k ^= Z[b[s]][s];
        }
        k ^= ZCASTLE[castle];
        if (ep >= 0) k ^= ZEP[ep & 7];
        if (side == BLACK) k ^= ZSIDE;
        return k;
    }

    private void ensure() {
        if (plies + 1 >= uMove.length) {
            int n = uMove.length * 2;
            uMove = Arrays.copyOf(uMove, n);
            uCap = Arrays.copyOf(uCap, n);
            uCastle = Arrays.copyOf(uCastle, n);
            uEp = Arrays.copyOf(uEp, n);
            uHalf = Arrays.copyOf(uHalf, n);
            uKey = Arrays.copyOf(uKey, n);
        }
    }

    // ---------------------------------------------------------------- attacks

    /** True if square sq is attacked by any piece of colour by. */
    boolean attacked(int sq, int by) {
        if (by == WHITE) {
            if (at(sq - 15) == PAWN || at(sq - 17) == PAWN) return true;
        } else {
            if (at(sq + 15) == 8 + PAWN || at(sq + 17) == 8 + PAWN) return true;
        }
        int nk = pc(by, KNIGHT);
        for (int d : KNIGHT_DIRS) if (at(sq + d) == nk) return true;
        int kg = pc(by, KING);
        for (int d : KING_DIRS) if (at(sq + d) == kg) return true;
        int rk = pc(by, ROOK), qn = pc(by, QUEEN), bp = pc(by, BISHOP);
        for (int d : ROOK_DIRS) {
            int s = sq + d, q;
            while ((q = at(s)) == EMPTY) s += d;
            if (q == rk || q == qn) return true;
        }
        for (int d : BISHOP_DIRS) {
            int s = sq + d, q;
            while ((q = at(s)) == EMPTY) s += d;
            if (q == bp || q == qn) return true;
        }
        return false;
    }

    boolean inCheck() { return attacked(kingSq[side], side ^ 1); }

    /** After make(): true if the side that just moved left its king safe. */
    boolean legalAfterMake() { return !attacked(kingSq[side ^ 1], side); }

    int nonPawnCount(int c) {
        int n = 0;
        for (int s = 0; s < 128; s++) {
            if ((s & 0x88) != 0) continue;
            int p = b[s];
            if (p != EMPTY && color(p) == c && type(p) >= KNIGHT && type(p) <= QUEEN) n++;
        }
        return n;
    }

    /** True if the current position already occurred earlier in the game/search (a draw by repetition). */
    boolean repetition() {
        int lim = Math.max(0, plies - half);
        for (int i = plies - 2; i >= lim; i -= 2) if (uKey[i] == key) return true;
        return false;
    }

    // ---------------------------------------------------------------- move generation

    /**
     * Pseudo-legal moves into mv (length >= 256). caps = true gives only captures and promotions.
     * Returns the number of moves. Callers must test legality with make() + legalAfterMake().
     */
    int gen(int[] mv, boolean caps) {
        int n = 0;
        int me = side, opp = me ^ 1;
        for (int sq = 0; sq < 128; sq++) {
            if ((sq & 0x88) != 0) continue;
            int p = b[sq];
            if (p == EMPTY || color(p) != me) continue;
            int t = type(p);
            if (t == PAWN) {
                n = genPawn(mv, n, sq, me, caps);
            } else if (t == KNIGHT || t == KING) {
                int[] dirs = t == KNIGHT ? KNIGHT_DIRS : KING_DIRS;
                for (int d : dirs) {
                    int to = sq + d;
                    if ((to & 0x88) != 0) continue;
                    int q = b[to];
                    if (q == EMPTY) {
                        if (!caps) mv[n++] = enc(sq, to, 0, 0);
                    } else if (color(q) == opp) {
                        mv[n++] = enc(sq, to, 0, 0);
                    }
                }
                if (t == KING && !caps) n = genCastle(mv, n, me);
            } else {
                int[] dirs = t == ROOK ? ROOK_DIRS : t == BISHOP ? BISHOP_DIRS : KING_DIRS;
                for (int d : dirs) {
                    int to = sq + d;
                    while ((to & 0x88) == 0) {
                        int q = b[to];
                        if (q == EMPTY) {
                            if (!caps) mv[n++] = enc(sq, to, 0, 0);
                        } else {
                            if (color(q) == opp) mv[n++] = enc(sq, to, 0, 0);
                            break;
                        }
                        to += d;
                    }
                }
            }
        }
        return n;
    }

    private int genCastle(int[] mv, int n, int me) {
        int opp = me ^ 1;
        int base = me == WHITE ? 0 : 112;
        int kingP = pc(me, KING), rookP = pc(me, ROOK);
        if (b[base + 4] != kingP) return n;
        int rk = me == WHITE ? CWK : CBK, rq = me == WHITE ? CWQ : CBQ;
        if ((castle & rk) != 0 && b[base + 5] == EMPTY && b[base + 6] == EMPTY && b[base + 7] == rookP
                && !attacked(base + 4, opp) && !attacked(base + 5, opp)) {
            mv[n++] = enc(base + 4, base + 6, 0, F_CASTLE);
        }
        if ((castle & rq) != 0 && b[base + 1] == EMPTY && b[base + 2] == EMPTY && b[base + 3] == EMPTY
                && b[base] == rookP && !attacked(base + 4, opp) && !attacked(base + 3, opp)) {
            mv[n++] = enc(base + 4, base + 2, 0, F_CASTLE);
        }
        return n;
    }

    private int genPawn(int[] mv, int n, int sq, int me, boolean caps) {
        int opp = me ^ 1;
        int dir = me == WHITE ? 16 : -16;
        int promoRank = me == WHITE ? 7 : 0;
        int startRank = me == WHITE ? 1 : 6;
        int one = sq + dir;
        if ((one & 0x88) == 0 && b[one] == EMPTY) {
            if ((one >> 4) == promoRank) {
                n = addPromos(mv, n, sq, one, 0);
            } else if (!caps) {
                mv[n++] = enc(sq, one, 0, 0);
                int two = one + dir;
                if ((sq >> 4) == startRank && b[two] == EMPTY) mv[n++] = enc(sq, two, 0, F_DOUBLE);
            }
        }
        for (int d : me == WHITE ? WHITE_PAWN_CAPS : BLACK_PAWN_CAPS) {
            int to = sq + d;
            if ((to & 0x88) != 0) continue;
            int q = b[to];
            boolean enemy = q != EMPTY && color(q) == opp;
            boolean epCap = to == ep && q == EMPTY;
            if (!enemy && !epCap) continue;
            if ((to >> 4) == promoRank) n = addPromos(mv, n, sq, to, 0);
            else mv[n++] = enc(sq, to, 0, epCap ? F_EP : 0);
        }
        return n;
    }

    private static int addPromos(int[] mv, int n, int from, int to, int flags) {
        mv[n++] = enc(from, to, QUEEN, flags);
        mv[n++] = enc(from, to, ROOK, flags);
        mv[n++] = enc(from, to, BISHOP, flags);
        mv[n++] = enc(from, to, KNIGHT, flags);
        return n;
    }

    /** All strictly legal moves into out (length >= 256). */
    int legal(int[] out) {
        int[] tmp = new int[256];
        int n = gen(tmp, false);
        int k = 0;
        for (int i = 0; i < n; i++) {
            make(tmp[i]);
            if (legalAfterMake()) out[k++] = tmp[i];
            unmake();
        }
        return k;
    }

    /** Finds the legal move with this UCI text, or 0. */
    int parseMove(String s) {
        int[] mv = new int[256];
        int n = legal(mv);
        for (int i = 0; i < n; i++) if (uci(mv[i]).equals(s)) return mv[i];
        return 0;
    }

    // ---------------------------------------------------------------- make / unmake

    void make(int m) {
        ensure();
        int from = from(m), to = to(m), promo = promo(m), fl = m & F_MASK;
        int me = side;
        int piece = b[from];
        int type = type(piece);
        uMove[plies] = m;
        uCastle[plies] = castle;
        uEp[plies] = ep;
        uHalf[plies] = half;
        uKey[plies] = key;
        plies++;

        key ^= ZCASTLE[castle];
        if (ep >= 0) key ^= ZEP[ep & 7];

        int cap;
        if ((fl & F_EP) != 0) {
            int capSq = to + (me == WHITE ? -16 : 16);
            cap = b[capSq];
            b[capSq] = EMPTY;
            key ^= Z[cap][capSq];
        } else {
            cap = b[to];
            if (cap != EMPTY) key ^= Z[cap][to];
        }
        uCap[plies - 1] = cap;

        b[from] = EMPTY;
        key ^= Z[piece][from];
        int placed = promo != 0 ? pc(me, promo) : piece;
        b[to] = placed;
        key ^= Z[placed][to];
        if (type == KING) kingSq[me] = to;

        if ((fl & F_CASTLE) != 0) {
            int rf, rt;
            if (to > from) {
                rf = to + 1;
                rt = to - 1;
            } else {
                rf = to - 2;
                rt = to + 1;
            }
            int rook = b[rf];
            b[rf] = EMPTY;
            b[rt] = rook;
            key ^= Z[rook][rf] ^ Z[rook][rt];
        }

        castle &= CMASK[from] & CMASK[to];
        key ^= ZCASTLE[castle];

        ep = (type == PAWN && Math.abs(to - from) == 32) ? (from + to) >> 1 : -1;
        if (ep >= 0) key ^= ZEP[ep & 7];

        half = (type == PAWN || cap != EMPTY) ? 0 : half + 1;
        if (me == BLACK) full++;
        side ^= 1;
        key ^= ZSIDE;
    }

    void unmake() {
        plies--;
        int m = uMove[plies];
        int from = from(m), to = to(m), fl = m & F_MASK;
        side ^= 1;
        int me = side;
        int placed = b[to];
        int moved = promo(m) != 0 ? pc(me, PAWN) : placed;
        b[from] = moved;
        b[to] = EMPTY;
        if ((fl & F_EP) != 0) b[to + (me == WHITE ? -16 : 16)] = uCap[plies];
        else b[to] = uCap[plies];
        if (type(moved) == KING) kingSq[me] = from;
        if ((fl & F_CASTLE) != 0) {
            int rf, rt;
            if (to > from) {
                rf = to + 1;
                rt = to - 1;
            } else {
                rf = to - 2;
                rt = to + 1;
            }
            b[rf] = b[rt];
            b[rt] = EMPTY;
        }
        castle = uCastle[plies];
        ep = uEp[plies];
        half = uHalf[plies];
        key = uKey[plies];
        if (me == BLACK) full--;
    }

    /** Passes the turn (used for null-move pruning only). */
    void makeNull() {
        ensure();
        uMove[plies] = 0;
        uCap[plies] = EMPTY;
        uCastle[plies] = castle;
        uEp[plies] = ep;
        uHalf[plies] = half;
        uKey[plies] = key;
        plies++;
        if (ep >= 0) key ^= ZEP[ep & 7];
        ep = -1;
        half++;
        side ^= 1;
        key ^= ZSIDE;
    }

    void unmakeNull() {
        plies--;
        side ^= 1;
        castle = uCastle[plies];
        ep = uEp[plies];
        half = uHalf[plies];
        key = uKey[plies];
    }
}
