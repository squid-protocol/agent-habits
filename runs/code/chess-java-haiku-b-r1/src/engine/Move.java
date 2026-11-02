package engine;

/**
 * A move packed into an int: bits 0-6 from square, 7-13 to square, 14-16 promotion piece type (0 = none),
 * 17+ flags. Square numbering is 0x88: index = rank * 16 + file, a1 = 0, h8 = 119.
 */
final class Move {
    static final int EP = 1, CASTLE = 2, DOUBLE = 4;

    private Move() {}

    static int pack(int from, int to, int promo, int flags) {
        return from | (to << 7) | (promo << 14) | (flags << 17);
    }

    static int from(int m) {
        return m & 127;
    }

    static int to(int m) {
        return (m >> 7) & 127;
    }

    static int promo(int m) {
        return (m >> 14) & 7;
    }

    static int flags(int m) {
        return m >>> 17;
    }

    static String sqName(int s) {
        return "" + (char) ('a' + (s & 7)) + (char) ('1' + (s >> 4));
    }

    static String toUci(int m) {
        if (m == 0) {
            return "0000";
        }
        StringBuilder sb = new StringBuilder(5);
        sb.append(sqName(from(m))).append(sqName(to(m)));
        switch (promo(m)) {
            case Board.KNIGHT: sb.append('n'); break;
            case Board.BISHOP: sb.append('b'); break;
            case Board.ROOK: sb.append('r'); break;
            case Board.QUEEN: sb.append('q'); break;
            default: break;
        }
        return sb.toString();
    }
}
