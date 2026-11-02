/** Static evaluation: material and piece-square tables, tapered between middlegame and endgame. */
final class Eval {
    static final int[] VAL_MG = {0, 100, 320, 330, 500, 900, 0};
    static final int[] VAL_EG = {0, 120, 320, 330, 520, 920, 0};
    static final int[] PHASE = {0, 0, 1, 1, 2, 4, 0};

    // Tables are written rank 8 first (index 0 = a8), as in the usual simplified evaluation tables.
    private static final int[] ZERO = new int[64];
    private static final int[] PAWN_T = {
             0,   0,   0,   0,   0,   0,   0,   0,
            50,  50,  50,  50,  50,  50,  50,  50,
            10,  10,  20,  30,  30,  20,  10,  10,
             5,   5,  10,  25,  25,  10,   5,   5,
             0,   0,   0,  20,  20,   0,   0,   0,
             5,  -5, -10,   0,   0, -10,  -5,   5,
             5,  10,  10, -20, -20,  10,  10,   5,
             0,   0,   0,   0,   0,   0,   0,   0};
    private static final int[] KNIGHT_T = {
            -50, -40, -30, -30, -30, -30, -40, -50,
            -40, -20,   0,   0,   0,   0, -20, -40,
            -30,   0,  10,  15,  15,  10,   0, -30,
            -30,   5,  15,  20,  20,  15,   5, -30,
            -30,   0,  15,  20,  20,  15,   0, -30,
            -30,   5,  10,  15,  15,  10,   5, -30,
            -40, -20,   0,   5,   5,   0, -20, -40,
            -50, -40, -30, -30, -30, -30, -40, -50};
    private static final int[] BISHOP_T = {
            -20, -10, -10, -10, -10, -10, -10, -20,
            -10,   0,   0,   0,   0,   0,   0, -10,
            -10,   0,   5,  10,  10,   5,   0, -10,
            -10,   5,   5,  10,  10,   5,   5, -10,
            -10,   0,  10,  10,  10,  10,   0, -10,
            -10,  10,  10,  10,  10,  10,  10, -10,
            -10,   5,   0,   0,   0,   0,   5, -10,
            -20, -10, -10, -10, -10, -10, -10, -20};
    private static final int[] ROOK_T = {
              0,   0,   0,   0,   0,   0,   0,   0,
              5,  10,  10,  10,  10,  10,  10,   5,
             -5,   0,   0,   0,   0,   0,   0,  -5,
             -5,   0,   0,   0,   0,   0,   0,  -5,
             -5,   0,   0,   0,   0,   0,   0,  -5,
             -5,   0,   0,   0,   0,   0,   0,  -5,
             -5,   0,   0,   0,   0,   0,   0,  -5,
              0,   0,   0,   5,   5,   0,   0,   0};
    private static final int[] QUEEN_T = {
            -20, -10, -10,  -5,  -5, -10, -10, -20,
            -10,   0,   0,   0,   0,   0,   0, -10,
            -10,   0,   5,   5,   5,   5,   0, -10,
             -5,   0,   5,   5,   5,   5,   0,  -5,
              0,   0,   5,   5,   5,   5,   0,  -5,
            -10,   5,   5,   5,   5,   5,   0, -10,
            -10,   0,   5,   0,   0,   0,   0, -10,
            -20, -10, -10,  -5,  -5, -10, -10, -20};
    private static final int[] KING_MG_T = {
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -30, -40, -40, -50, -50, -40, -40, -30,
            -20, -30, -30, -40, -40, -30, -30, -20,
            -10, -20, -20, -20, -20, -20, -20, -10,
             20,  20,   0,   0,   0,   0,  20,  20,
             20,  30,  10,   0,   0,  10,  30,  20};
    private static final int[] KING_EG_T = {
            -50, -40, -30, -20, -20, -30, -40, -50,
            -30, -20, -10,   0,   0, -10, -20, -30,
            -30, -10,  20,  30,  30,  20, -10, -30,
            -30, -10,  30,  40,  40,  30, -10, -30,
            -30, -10,  30,  40,  40,  30, -10, -30,
            -30, -10,  20,  30,  30,  20, -10, -30,
            -30, -30,   0,   0,   0,   0, -30, -30,
            -50, -30, -30, -30, -30, -30, -30, -50};

    private static final int[][] MG = {ZERO, PAWN_T, KNIGHT_T, BISHOP_T, ROOK_T, QUEEN_T, KING_MG_T};
    private static final int[][] EG = {ZERO, PAWN_T, KNIGHT_T, BISHOP_T, ROOK_T, QUEEN_T, KING_EG_T};

    private Eval() {}

    /** Score from the point of view of the side to move. */
    static int eval(Position p) {
        int mg = 0, eg = 0, ph = 0;
        for (int sq = 0; sq < 128; sq++) {
            if ((sq & 0x88) != 0) continue;
            int pc = p.b[sq];
            if (pc == Position.EMPTY) continue;
            int c = Position.color(pc), t = Position.type(pc);
            int r = sq >> 4, f = sq & 7;
            int idx = c == Position.WHITE ? (7 - r) * 8 + f : r * 8 + f;
            int sign = c == Position.WHITE ? 1 : -1;
            mg += sign * (VAL_MG[t] + MG[t][idx]);
            eg += sign * (VAL_EG[t] + EG[t][idx]);
            ph += PHASE[t];
        }
        if (ph > 24) ph = 24;
        int s = (mg * ph + eg * (24 - ph)) / 24;
        return p.side == Position.WHITE ? s : -s;
    }
}
