//! Precomputed attack tables and sliding-piece attacks.
//!
//! Squares are numbered a1 = 0, b1 = 1, ..., h8 = 63 (square = rank * 8 + file).
//! Sliding attacks use precomputed rays: the nearest blocker on a ray cuts it off.

/// Ray directions as (file delta, rank delta). Index: 0 N, 1 S, 2 E, 3 W, 4 NE, 5 NW, 6 SE, 7 SW.
const DELTAS: [(i32, i32); 8] = [(0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (-1, 1), (1, -1), (-1, -1)];
/// Rays whose squares have larger indices than their origin (their nearest blocker is the lowest bit).
const POSITIVE: [bool; 8] = [true, false, true, false, true, true, false, false];

const KNIGHT_D: [(i32, i32); 8] = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)];
const KING_D: [(i32, i32); 8] = [(0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (-1, 1), (1, -1), (-1, -1)];

const fn build_rays() -> [[u64; 64]; 8] {
    let mut t = [[0u64; 64]; 8];
    let mut d = 0;
    while d < 8 {
        let mut sq = 0;
        while sq < 64 {
            let df = DELTAS[d].0;
            let dr = DELTAS[d].1;
            let mut f = (sq % 8) as i32 + df;
            let mut r = (sq / 8) as i32 + dr;
            while f >= 0 && f < 8 && r >= 0 && r < 8 {
                t[d][sq] |= 1u64 << (r * 8 + f);
                f += df;
                r += dr;
            }
            sq += 1;
        }
        d += 1;
    }
    t
}

const fn build_step(deltas: &[(i32, i32); 8]) -> [u64; 64] {
    let mut t = [0u64; 64];
    let mut sq = 0;
    while sq < 64 {
        let mut i = 0;
        while i < 8 {
            let f = (sq % 8) as i32 + deltas[i].0;
            let r = (sq / 8) as i32 + deltas[i].1;
            if f >= 0 && f < 8 && r >= 0 && r < 8 {
                t[sq] |= 1u64 << (r * 8 + f);
            }
            i += 1;
        }
        sq += 1;
    }
    t
}

const fn build_pawn(white: bool) -> [u64; 64] {
    let mut t = [0u64; 64];
    let dr = if white { 1 } else { -1 };
    let mut sq = 0;
    while sq < 64 {
        let r = (sq / 8) as i32 + dr;
        let mut k = 0;
        while k < 2 {
            let f = (sq % 8) as i32 + if k == 0 { -1 } else { 1 };
            if f >= 0 && f < 8 && r >= 0 && r < 8 {
                t[sq] |= 1u64 << (r * 8 + f);
            }
            k += 1;
        }
        sq += 1;
    }
    t
}

pub static RAYS: [[u64; 64]; 8] = build_rays();
pub static KNIGHT_ATT: [u64; 64] = build_step(&KNIGHT_D);
pub static KING_ATT: [u64; 64] = build_step(&KING_D);
/// PAWN_ATT[colour][square]: squares attacked by a pawn of `colour` standing on `square`.
pub static PAWN_ATT: [[u64; 64]; 2] = [build_pawn(true), build_pawn(false)];

/// Attacks along one ray direction `d` from `sq`, stopping at (and including) the first blocker.
#[inline(always)]
pub fn ray_attack(occ: u64, sq: usize, d: usize) -> u64 {
    let ray = RAYS[d][sq];
    let blockers = ray & occ;
    if blockers == 0 {
        return ray;
    }
    let b = (if POSITIVE[d] { blockers.trailing_zeros() } else { 63 - blockers.leading_zeros() }) as usize;
    ray ^ RAYS[d][b]
}

#[inline(always)]
pub fn rook_attacks(occ: u64, sq: usize) -> u64 {
    ray_attack(occ, sq, 0) | ray_attack(occ, sq, 1) | ray_attack(occ, sq, 2) | ray_attack(occ, sq, 3)
}

#[inline(always)]
pub fn bishop_attacks(occ: u64, sq: usize) -> u64 {
    ray_attack(occ, sq, 4) | ray_attack(occ, sq, 5) | ray_attack(occ, sq, 6) | ray_attack(occ, sq, 7)
}
