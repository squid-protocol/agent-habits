//! Static evaluation: material plus piece-square tables, tapered between middlegame and endgame.

use crate::board::*;

const VAL: [i32; 6] = [100, 320, 330, 500, 900, 0];
/// Game-phase weight per piece type; the full set of pieces sums to 24.
const PHASE: [i32; 6] = [0, 1, 1, 2, 4, 0];
const TEMPO: i32 = 10;

// Tables are written from White's point of view with a8 first (top-left), as usual.
const PAWN_MG: [i32; 64] = [
    0, 0, 0, 0, 0, 0, 0, 0, 50, 50, 50, 50, 50, 50, 50, 50, 10, 10, 20, 30, 30, 20, 10, 10, 5, 5, 10, 25, 25, 10, 5, 5,
    0, 0, 0, 20, 20, 0, 0, 0, 5, -5, -10, 0, 0, -10, -5, 5, 5, 10, 10, -20, -20, 10, 10, 5, 0, 0, 0, 0, 0, 0, 0, 0,
];
const PAWN_EG: [i32; 64] = [
    0, 0, 0, 0, 0, 0, 0, 0, 80, 80, 80, 80, 80, 80, 80, 80, 50, 50, 50, 50, 50, 50, 50, 50, 30, 30, 30, 30, 30, 30, 30,
    30, 20, 20, 20, 20, 20, 20, 20, 20, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 0, 0, 0, 0, 0,
    0, 0, 0,
];
const KNIGHT_MG: [i32; 64] = [
    -50, -40, -30, -30, -30, -30, -40, -50, -40, -20, 0, 0, 0, 0, -20, -40, -30, 0, 10, 15, 15, 10, 0, -30, -30, 5, 15,
    20, 20, 15, 5, -30, -30, 0, 15, 20, 20, 15, 0, -30, -30, 5, 10, 15, 15, 10, 5, -30, -40, -20, 0, 5, 5, 0, -20, -40,
    -50, -40, -30, -30, -30, -30, -40, -50,
];
const BISHOP_MG: [i32; 64] = [
    -20, -10, -10, -10, -10, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 10, 10, 5, 0, -10, -10, 5, 5, 10, 10,
    5, 5, -10, -10, 0, 10, 10, 10, 10, 0, -10, -10, 10, 10, 10, 10, 10, 10, -10, -10, 5, 0, 0, 0, 0, 5, -10, -20, -10,
    -10, -10, -10, -10, -10, -20,
];
const ROOK_MG: [i32; 64] = [
    0, 0, 0, 0, 0, 0, 0, 0, 5, 10, 10, 10, 10, 10, 10, 5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0,
    0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, -5, 0, 0, 0, 0, 0, 0, -5, 0, 0, 0, 5, 5, 0, 0, 0,
];
const QUEEN_MG: [i32; 64] = [
    -20, -10, -10, -5, -5, -10, -10, -20, -10, 0, 0, 0, 0, 0, 0, -10, -10, 0, 5, 5, 5, 5, 0, -10, -5, 0, 5, 5, 5, 5, 0,
    -5, 0, 0, 5, 5, 5, 5, 0, -5, -10, 5, 5, 5, 5, 5, 0, -10, -10, 0, 5, 0, 0, 0, 0, -10, -20, -10, -10, -5, -5, -10,
    -10, -20,
];
const KING_MG: [i32; 64] = [
    -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40, -30, -30, -40, -40, -50, -50, -40, -40,
    -30, -30, -40, -40, -50, -50, -40, -40, -30, -20, -30, -30, -40, -40, -30, -30, -20, -10, -20, -20, -20, -20, -20,
    -20, -10, 20, 20, 0, 0, 0, 0, 20, 20, 20, 30, 10, 0, 0, 10, 30, 20,
];
const KING_EG: [i32; 64] = [
    -50, -40, -30, -20, -20, -30, -40, -50, -30, -20, -10, 0, 0, -10, -20, -30, -30, -10, 20, 30, 30, 20, -10, -30, -30,
    -10, 30, 40, 40, 30, -10, -30, -30, -10, 30, 40, 40, 30, -10, -30, -30, -10, 20, 30, 30, 20, -10, -30, -30, -30, 0,
    0, 0, 0, -30, -30, -50, -30, -30, -30, -30, -30, -30, -50,
];

const PST_MG: [&[i32; 64]; 6] = [&PAWN_MG, &KNIGHT_MG, &BISHOP_MG, &ROOK_MG, &QUEEN_MG, &KING_MG];
const PST_EG: [&[i32; 64]; 6] = [&PAWN_EG, &KNIGHT_MG, &BISHOP_MG, &ROOK_MG, &QUEEN_MG, &KING_EG];

/// Score in centipawns from the point of view of the side to move.
pub fn evaluate(b: &Board) -> i32 {
    let mut mg = [0i32; 2];
    let mut eg = [0i32; 2];
    let mut phase = 0;
    for c in 0..2 {
        for pt in 0..6 {
            let mut bb = b.pieces[c][pt];
            phase += PHASE[pt] * bb.count_ones() as i32;
            while bb != 0 {
                let sq = bb.trailing_zeros() as usize;
                bb &= bb - 1;
                // White reads the tables with the rank flipped; Black reads them directly.
                let idx = if c == WHITE { sq ^ 56 } else { sq };
                mg[c] += VAL[pt] + PST_MG[pt][idx];
                eg[c] += VAL[pt] + PST_EG[pt][idx];
            }
        }
        if b.pieces[c][BISHOP].count_ones() >= 2 {
            mg[c] += 30;
            eg[c] += 40;
        }
    }
    let phase = phase.min(24);
    let s = ((mg[WHITE] - mg[BLACK]) * phase + (eg[WHITE] - eg[BLACK]) * (24 - phase)) / 24;
    let s = s + TEMPO;
    if b.side == WHITE {
        s
    } else {
        -s
    }
}

/// True if side `c` has a knight, bishop, rook or queen (used to avoid null-move pruning in pawn endings).
pub fn has_non_pawn(b: &Board, c: usize) -> bool {
    (b.pieces[c][KNIGHT] | b.pieces[c][BISHOP] | b.pieces[c][ROOK] | b.pieces[c][QUEEN]) != 0
}
