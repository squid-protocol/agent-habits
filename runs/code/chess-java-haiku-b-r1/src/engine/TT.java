package engine;

import java.util.Arrays;

/** Fixed-size transposition table; always-replace scheme. An entry is unused while meta == 0. */
final class TT {
    static final int EXACT = 1, LOWER = 2, UPPER = 3;

    final long[] keys;
    final int[] moves;
    final int[] scores;
    /** (depth << 2) | bound. */
    final int[] meta;
    private final int mask;

    TT(int bits) {
        int size = 1 << bits;
        keys = new long[size];
        moves = new int[size];
        scores = new int[size];
        meta = new int[size];
        mask = size - 1;
    }

    int index(long key) {
        return (int) (key & mask);
    }

    void clear() {
        Arrays.fill(meta, 0);
    }

    void store(long key, int move, int score, int depth, int bound) {
        int i = index(key);
        keys[i] = key;
        moves[i] = move;
        scores[i] = score;
        meta[i] = (depth << 2) | bound;
    }
}
