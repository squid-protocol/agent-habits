package engine;

/** Leaf-node counting for move generation verification. */
final class Perft {
    private Perft() {}

    /** Counts leaf nodes at the given remaining depth. lists needs one 256-entry row per ply used. */
    static long perft(Board b, int depth, int ply, int[][] lists) {
        if (depth <= 0) {
            return 1;
        }
        int[] list = lists[ply];
        int n = MoveGen.gen(b, list, false);
        int us = b.side;
        long total = 0;
        for (int i = 0; i < n; i++) {
            int m = list[i];
            b.make(m);
            if (!b.attacked(b.kingSq[us], us ^ 1)) {
                total += perft(b, depth - 1, ply + 1, lists);
            }
            b.unmake();
        }
        return total;
    }
}
