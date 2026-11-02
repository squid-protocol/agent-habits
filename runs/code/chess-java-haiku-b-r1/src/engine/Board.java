package engine;

import java.util.Arrays;
import java.util.SplittableRandom;

/** A chess position on a 0x88 board with make/unmake, attack detection, FEN parsing and a Zobrist hash. */
final class Board {
    static final int WHITE = 0, BLACK = 1;
    static final int PAWN = 1, KNIGHT = 2, BISHOP = 3, ROOK = 4, QUEEN = 5, KING = 6;
    static final int WK = 1, WQ = 2, BK = 4, BQ = 8;
    static final String START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1";

    static final int[] KNIGHT_D = {-33, -31, -18, -14, 14, 18, 31, 33};
    static final int[] KING_D = {-17, -16, -15, -1, 1, 15, 16, 17};
    static final int[] BISHOP_D = {-17, -15, 15, 17};
    static final int[] ROOK_D = {-16, -1, 1, 16};
    static final int[] QUEEN_D = {-17, -16, -15, -1, 1, 15, 16, 17};

    private static final long[][] Z_PIECE = new long[16][128];
    private static final long[] Z_CASTLE = new long[16];
    private static final long[] Z_EP = new long[8];
    private static final long Z_SIDE;
    private static final int[] CASTLE_MASK = new int[128];

    static {
        SplittableRandom rnd = new SplittableRandom(0x2545F4914F6CDD1DL);
        for (int p = 0; p < 16; p++) {
            for (int s = 0; s < 128; s++) {
                Z_PIECE[p][s] = rnd.nextLong();
            }
        }
        for (int i = 0; i < 16; i++) {
            Z_CASTLE[i] = rnd.nextLong();
        }
        for (int i = 0; i < 8; i++) {
            Z_EP[i] = rnd.nextLong();
        }
        Z_SIDE = rnd.nextLong();
        Arrays.fill(CASTLE_MASK, 15);
        CASTLE_MASK[0] &= ~WQ;
        CASTLE_MASK[4] &= ~(WK | WQ);
        CASTLE_MASK[7] &= ~WK;
        CASTLE_MASK[112] &= ~BQ;
        CASTLE_MASK[116] &= ~(BK | BQ);
        CASTLE_MASK[119] &= ~BK;
    }

    final int[] sq = new int[128];
    int side = WHITE;
    int castle;
    int ep = -1;
    int halfmove;
    int fullmove = 1;
    final int[] kingSq = new int[2];
    long hash;

    /** Number of entries on the undo stack, i.e. plies made since this board was created. */
    int ply;
    int[] stMove = new int[512];
    int[] stCap = new int[512];
    int[] stCastle = new int[512];
    int[] stEp = new int[512];
    int[] stHalf = new int[512];
    long[] stHash = new long[512];

    private Board() {
    }

    static Board fromFen(String fen) {
        String[] f = fen.trim().split("\\s+");
        Board b = new Board();
        int rank = 7, file = 0;
        for (char ch : f[0].toCharArray()) {
            if (ch == '/') {
                rank--;
                file = 0;
            } else if (ch >= '1' && ch <= '8') {
                file += ch - '0';
            } else {
                int color = Character.isUpperCase(ch) ? WHITE : BLACK;
                int type = pieceType(Character.toLowerCase(ch));
                int s = (rank << 4) | file;
                b.sq[s] = (color << 3) | type;
                if (type == KING) {
                    b.kingSq[color] = s;
                }
                file++;
            }
        }
        b.side = f.length > 1 && f[1].equals("b") ? BLACK : WHITE;
        if (f.length > 2) {
            for (char ch : f[2].toCharArray()) {
                switch (ch) {
                    case 'K': b.castle |= WK; break;
                    case 'Q': b.castle |= WQ; break;
                    case 'k': b.castle |= BK; break;
                    case 'q': b.castle |= BQ; break;
                    default: break;
                }
            }
        }
        if (f.length > 3 && !f[3].equals("-")) {
            b.ep = ((f[3].charAt(1) - '1') << 4) | (f[3].charAt(0) - 'a');
        }
        if (f.length > 4) {
            b.halfmove = Integer.parseInt(f[4]);
        }
        if (f.length > 5) {
            b.fullmove = Integer.parseInt(f[5]);
        }
        b.hash = b.computeHash();
        return b;
    }

    private static int pieceType(char c) {
        switch (c) {
            case 'p': return PAWN;
            case 'n': return KNIGHT;
            case 'b': return BISHOP;
            case 'r': return ROOK;
            case 'q': return QUEEN;
            case 'k': return KING;
            default: throw new IllegalArgumentException("bad piece letter: " + c);
        }
    }

    long computeHash() {
        long h = 0;
        for (int s = 0; s < 128; s++) {
            if ((s & 0x88) == 0 && sq[s] != 0) {
                h ^= Z_PIECE[sq[s]][s];
            }
        }
        h ^= Z_CASTLE[castle];
        if (ep >= 0) {
            h ^= Z_EP[ep & 7];
        }
        if (side == BLACK) {
            h ^= Z_SIDE;
        }
        return h;
    }

    Board copy() {
        Board c = new Board();
        System.arraycopy(sq, 0, c.sq, 0, 128);
        c.side = side;
        c.castle = castle;
        c.ep = ep;
        c.halfmove = halfmove;
        c.fullmove = fullmove;
        c.kingSq[0] = kingSq[0];
        c.kingSq[1] = kingSq[1];
        c.hash = hash;
        c.ply = ply;
        c.stMove = stMove.clone();
        c.stCap = stCap.clone();
        c.stCastle = stCastle.clone();
        c.stEp = stEp.clone();
        c.stHalf = stHalf.clone();
        c.stHash = stHash.clone();
        return c;
    }

    private void push(int m, int captured) {
        if (ply >= stMove.length) {
            int n = stMove.length * 2;
            stMove = Arrays.copyOf(stMove, n);
            stCap = Arrays.copyOf(stCap, n);
            stCastle = Arrays.copyOf(stCastle, n);
            stEp = Arrays.copyOf(stEp, n);
            stHalf = Arrays.copyOf(stHalf, n);
            stHash = Arrays.copyOf(stHash, n);
        }
        stMove[ply] = m;
        stCap[ply] = captured;
        stCastle[ply] = castle;
        stEp[ply] = ep;
        stHalf[ply] = halfmove;
        stHash[ply] = hash;
        ply++;
    }

    /** Plays a pseudo-legal or legal move. The caller must check that the mover's king is not left in check. */
    void make(int m) {
        int from = Move.from(m), to = Move.to(m), promo = Move.promo(m), fl = Move.flags(m);
        int us = side, them = us ^ 1;
        int pc = sq[from];
        int captured = sq[to];
        push(m, captured);

        hash ^= Z_CASTLE[castle];
        if (ep >= 0) {
            hash ^= Z_EP[ep & 7];
        }
        ep = -1;

        sq[from] = 0;
        hash ^= Z_PIECE[pc][from];
        if ((fl & Move.EP) != 0) {
            int cs = to + (us == WHITE ? -16 : 16);
            int cp = sq[cs];
            sq[cs] = 0;
            hash ^= Z_PIECE[cp][cs];
        } else if (captured != 0) {
            hash ^= Z_PIECE[captured][to];
        }
        int np = promo != 0 ? (us << 3) | promo : pc;
        sq[to] = np;
        hash ^= Z_PIECE[np][to];
        if ((pc & 7) == KING) {
            kingSq[us] = to;
        }
        if ((fl & Move.CASTLE) != 0) {
            int rf, rt;
            if ((to & 7) == 6) {
                rf = to + 1;
                rt = to - 1;
            } else {
                rf = to - 2;
                rt = to + 1;
            }
            int rp = (us << 3) | ROOK;
            sq[rf] = 0;
            hash ^= Z_PIECE[rp][rf];
            sq[rt] = rp;
            hash ^= Z_PIECE[rp][rt];
        }
        castle &= CASTLE_MASK[from] & CASTLE_MASK[to];
        if ((fl & Move.DOUBLE) != 0) {
            ep = (from + to) >> 1;
        }
        hash ^= Z_CASTLE[castle];
        if (ep >= 0) {
            hash ^= Z_EP[ep & 7];
        }
        halfmove = ((pc & 7) == PAWN || captured != 0 || (fl & Move.EP) != 0) ? 0 : halfmove + 1;
        if (us == BLACK) {
            fullmove++;
        }
        side = them;
        hash ^= Z_SIDE;
    }

    /** Passes the turn without moving (used for null-move pruning). */
    void makeNull() {
        push(0, 0);
        if (ep >= 0) {
            hash ^= Z_EP[ep & 7];
        }
        ep = -1;
        halfmove++;
        side ^= 1;
        hash ^= Z_SIDE;
    }

    void unmake() {
        ply--;
        int m = stMove[ply];
        side ^= 1;
        castle = stCastle[ply];
        ep = stEp[ply];
        halfmove = stHalf[ply];
        hash = stHash[ply];
        if (m == 0) {
            return;
        }
        int us = side, them = us ^ 1;
        int from = Move.from(m), to = Move.to(m), promo = Move.promo(m), fl = Move.flags(m);
        int pc = promo != 0 ? (us << 3) | PAWN : sq[to];
        sq[from] = pc;
        if ((pc & 7) == KING) {
            kingSq[us] = from;
        }
        if ((fl & Move.EP) != 0) {
            sq[to] = 0;
            sq[to + (us == WHITE ? -16 : 16)] = (them << 3) | PAWN;
        } else {
            sq[to] = stCap[ply];
        }
        if ((fl & Move.CASTLE) != 0) {
            int rf, rt;
            if ((to & 7) == 6) {
                rf = to + 1;
                rt = to - 1;
            } else {
                rf = to - 2;
                rt = to + 1;
            }
            sq[rt] = 0;
            sq[rf] = (us << 3) | ROOK;
        }
        if (us == BLACK) {
            fullmove--;
        }
    }

    /** True if square s is attacked by any piece of colour by. */
    boolean attacked(int s, int by) {
        int base = by << 3;
        int t;
        if (by == WHITE) {
            t = s - 17;
            if ((t & 0x88) == 0 && sq[t] == base + PAWN) {
                return true;
            }
            t = s - 15;
            if ((t & 0x88) == 0 && sq[t] == base + PAWN) {
                return true;
            }
        } else {
            t = s + 15;
            if ((t & 0x88) == 0 && sq[t] == base + PAWN) {
                return true;
            }
            t = s + 17;
            if ((t & 0x88) == 0 && sq[t] == base + PAWN) {
                return true;
            }
        }
        for (int d : KNIGHT_D) {
            t = s + d;
            if ((t & 0x88) == 0 && sq[t] == base + KNIGHT) {
                return true;
            }
        }
        for (int d : KING_D) {
            t = s + d;
            if ((t & 0x88) == 0 && sq[t] == base + KING) {
                return true;
            }
        }
        for (int d : BISHOP_D) {
            t = s + d;
            while ((t & 0x88) == 0) {
                int p = sq[t];
                if (p != 0) {
                    if (p == base + BISHOP || p == base + QUEEN) {
                        return true;
                    }
                    break;
                }
                t += d;
            }
        }
        for (int d : ROOK_D) {
            t = s + d;
            while ((t & 0x88) == 0) {
                int p = sq[t];
                if (p != 0) {
                    if (p == base + ROOK || p == base + QUEEN) {
                        return true;
                    }
                    break;
                }
                t += d;
            }
        }
        return false;
    }

    boolean inCheck() {
        return attacked(kingSq[side], side ^ 1);
    }
}
