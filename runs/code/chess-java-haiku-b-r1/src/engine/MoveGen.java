package engine;

/** Pseudo-legal move generation plus the legality filter. */
final class MoveGen {
    private MoveGen() {}

    /**
     * Appends pseudo-legal moves to list. With capsOnly, only captures and promotions are produced
     * (quiet promotions included). Castling is never produced when capsOnly is set.
     */
    static int gen(Board b, int[] list, boolean capsOnly) {
        final int us = b.side, them = us ^ 1;
        final int[] sq = b.sq;
        final int ownRook = (us << 3) | Board.ROOK;
        final int pawnDir = us == Board.WHITE ? 16 : -16;
        final int promoRank = us == Board.WHITE ? 7 : 0;
        final int startRank = us == Board.WHITE ? 1 : 6;
        int n = 0;
        for (int r = 0; r < 8; r++) {
            for (int f = 0; f < 8; f++) {
                int s = (r << 4) | f;
                int pc = sq[s];
                if (pc == 0 || (pc >> 3) != us) {
                    continue;
                }
                int type = pc & 7;
                if (type == Board.PAWN) {
                    int t = s + pawnDir;
                    if ((t & 0x88) == 0 && sq[t] == 0) {
                        if ((t >> 4) == promoRank) {
                            n = addPromos(list, n, s, t);
                        } else if (!capsOnly) {
                            list[n++] = Move.pack(s, t, 0, 0);
                            if (r == startRank && sq[t + pawnDir] == 0) {
                                list[n++] = Move.pack(s, t + pawnDir, 0, Move.DOUBLE);
                            }
                        }
                    }
                    for (int k = 0; k < 2; k++) {
                        int d = us == Board.WHITE ? (k == 0 ? 15 : 17) : (k == 0 ? -17 : -15);
                        t = s + d;
                        if ((t & 0x88) != 0) {
                            continue;
                        }
                        int tp = sq[t];
                        if (tp != 0 && (tp >> 3) == them) {
                            if ((t >> 4) == promoRank) {
                                n = addPromos(list, n, s, t);
                            } else {
                                list[n++] = Move.pack(s, t, 0, 0);
                            }
                        } else if (t == b.ep) {
                            list[n++] = Move.pack(s, t, 0, Move.EP);
                        }
                    }
                } else if (type == Board.KNIGHT || type == Board.KING) {
                    int[] offs = type == Board.KNIGHT ? Board.KNIGHT_D : Board.KING_D;
                    for (int d : offs) {
                        int t = s + d;
                        if ((t & 0x88) != 0) {
                            continue;
                        }
                        int tp = sq[t];
                        if (tp == 0 ? !capsOnly : (tp >> 3) == them) {
                            list[n++] = Move.pack(s, t, 0, 0);
                        }
                    }
                    if (type == Board.KING && !capsOnly) {
                        n = genCastles(b, list, n, s, us, them, ownRook);
                    }
                } else {
                    int[] dirs = type == Board.BISHOP ? Board.BISHOP_D
                            : type == Board.ROOK ? Board.ROOK_D : Board.QUEEN_D;
                    for (int d : dirs) {
                        int t = s + d;
                        while ((t & 0x88) == 0) {
                            int tp = sq[t];
                            if (tp == 0) {
                                if (!capsOnly) {
                                    list[n++] = Move.pack(s, t, 0, 0);
                                }
                            } else {
                                if ((tp >> 3) == them) {
                                    list[n++] = Move.pack(s, t, 0, 0);
                                }
                                break;
                            }
                            t += d;
                        }
                    }
                }
            }
        }
        return n;
    }

    private static int addPromos(int[] list, int n, int from, int to) {
        list[n++] = Move.pack(from, to, Board.QUEEN, 0);
        list[n++] = Move.pack(from, to, Board.ROOK, 0);
        list[n++] = Move.pack(from, to, Board.BISHOP, 0);
        list[n++] = Move.pack(from, to, Board.KNIGHT, 0);
        return n;
    }

    private static int genCastles(Board b, int[] list, int n, int e, int us, int them, int ownRook) {
        if (b.attacked(e, them)) {
            return n;
        }
        int[] sq = b.sq;
        boolean white = us == Board.WHITE;
        int ks = white ? Board.WK : Board.BK;
        int qs = white ? Board.WQ : Board.BQ;
        if ((b.castle & ks) != 0 && sq[e + 1] == 0 && sq[e + 2] == 0 && sq[e + 3] == ownRook
                && !b.attacked(e + 1, them) && !b.attacked(e + 2, them)) {
            list[n++] = Move.pack(e, e + 2, 0, Move.CASTLE);
        }
        if ((b.castle & qs) != 0 && sq[e - 1] == 0 && sq[e - 2] == 0 && sq[e - 3] == 0 && sq[e - 4] == ownRook
                && !b.attacked(e - 1, them) && !b.attacked(e - 2, them)) {
            list[n++] = Move.pack(e, e - 2, 0, Move.CASTLE);
        }
        return n;
    }

    /** Writes the legal moves of b into list (which needs room for 256 entries) and returns their count. */
    static int genLegal(Board b, int[] list) {
        int n = gen(b, list, false);
        int us = b.side;
        int k = 0;
        for (int i = 0; i < n; i++) {
            int m = list[i];
            b.make(m);
            if (!b.attacked(b.kingSq[us], us ^ 1)) {
                list[k++] = m;
            }
            b.unmake();
        }
        return k;
    }
}
