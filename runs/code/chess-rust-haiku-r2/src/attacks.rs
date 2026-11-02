//! Precomputed attack tables and sliding-piece attack generation.
//!
//! Squares use index `rank * 8 + file`, so a1 = 0 and h8 = 63.

use std::sync::OnceLock;

/// Ray directions as (file step, rank step).
const DIRS: [(i32, i32); 8] = [(0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (-1, 1), (1, -1), (-1, -1)];
/// Directions whose steps increase the square index; the first blocker is the lowest set bit.
const POSITIVE: [bool; 8] = [true, false, true, false, true, true, false, false];
const KNIGHT_STEPS: [(i32, i32); 8] = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)];

pub struct Tables {
    pub knight: [u64; 64],
    pub king: [u64; 64],
    /// `pawn[c][sq]`: squares attacked by a pawn of colour `c` standing on `sq`.
    pub pawn: [[u64; 64]; 2],
    /// `ray[d][sq]`: every square reachable from `sq` in direction `d`, excluding `sq`.
    pub ray: [[u64; 64]; 8],
}

pub fn tables() -> &'static Tables {
    static T: OnceLock<Tables> = OnceLock::new();
    T.get_or_init(build_tables)
}

fn step(sq: usize, df: i32, dr: i32) -> Option<usize> {
    let f = (sq % 8) as i32 + df;
    let r = (sq / 8) as i32 + dr;
    if (0..8).contains(&f) && (0..8).contains(&r) {
        Some((r * 8 + f) as usize)
    } else {
        None
    }
}

fn build_tables() -> Tables {
    let mut t = Tables { knight: [0; 64], king: [0; 64], pawn: [[0; 64]; 2], ray: [[0; 64]; 8] };
    for sq in 0..64 {
        for &(df, dr) in &KNIGHT_STEPS {
            if let Some(to) = step(sq, df, dr) {
                t.knight[sq] |= 1u64 << to;
            }
        }
        for &(df, dr) in &DIRS {
            if let Some(to) = step(sq, df, dr) {
                t.king[sq] |= 1u64 << to;
            }
        }
        for &(df, dr) in &[(1, 1), (-1, 1)] {
            if let Some(to) = step(sq, df, dr) {
                t.pawn[0][sq] |= 1u64 << to;
            }
        }
        for &(df, dr) in &[(1, -1), (-1, -1)] {
            if let Some(to) = step(sq, df, dr) {
                t.pawn[1][sq] |= 1u64 << to;
            }
        }
        for (d, &(df, dr)) in DIRS.iter().enumerate() {
            let mut cur = step(sq, df, dr);
            while let Some(to) = cur {
                t.ray[d][sq] |= 1u64 << to;
                cur = step(to, df, dr);
            }
        }
    }
    t
}

#[inline]
fn ray_attacks(t: &Tables, sq: usize, d: usize, occ: u64) -> u64 {
    let ray = t.ray[d][sq];
    let blockers = ray & occ;
    if blockers == 0 {
        return ray;
    }
    let blocker = if POSITIVE[d] {
        blockers.trailing_zeros() as usize
    } else {
        63 - blockers.leading_zeros() as usize
    };
    ray ^ t.ray[d][blocker]
}

#[inline]
pub fn rook_attacks(sq: usize, occ: u64) -> u64 {
    let t = tables();
    ray_attacks(t, sq, 0, occ) | ray_attacks(t, sq, 1, occ) | ray_attacks(t, sq, 2, occ) | ray_attacks(t, sq, 3, occ)
}

#[inline]
pub fn bishop_attacks(sq: usize, occ: u64) -> u64 {
    let t = tables();
    ray_attacks(t, sq, 4, occ) | ray_attacks(t, sq, 5, occ) | ray_attacks(t, sq, 6, occ) | ray_attacks(t, sq, 7, occ)
}
