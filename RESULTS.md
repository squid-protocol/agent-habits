# Results

Arms: **S** = Claude Code + Sonnet 5.5 (round 1), **S2** = Sonnet round 2, **K** = Claude Code + Haiku 5.5,
**K2** = Haiku round 2, **X** = Codex CLI + gpt-6-luna. One run per arm per cell in the tests (the first run in
the two repeat cells). Ten cells = {chess, SAT} × {C, Java, Python, Rust, COBOL}. Registered tests are sign tests
over cells, Holm-corrected within each family; the registration is [here](preregistration/PREREGISTRATION.md).

The **primary** version is D16's: the four Codex programs that GitGalaxy's aperture blocked are measured per the
pre-stated rule. The **instrument default** (those cells missing) is in `results/data/families.json`.

## 1. The runs

| arm | runs | passed the hidden check | median active time | nudged | hit the 60-min cap |
|---|---|---|---|---|---|
| Sonnet r1 | 12 | 12 | 2 m 37 s | 1 | 0 |
| Sonnet r2 | 12 | 12 | 2 m 33 s | 0 | 0 |
| Haiku r1 | 12 | 12 | 25 m 26 s | 0 | 0 |
| Haiku r2 | 12 | 11 | 19 m 43 s | 0 | 1 |
| Codex | 12 | 10 | 6 m 48 s | 5 | 1 |

The two capped runs' final code passes the check when checked afterwards (supplementary), so 59 of 60 programs
work. The one real failure is `sat-c-codex-r1`: too slow on the hard formulas. Two pilot runs under an easier first
checker were excluded before their measures were looked at (D7).

## 2. Registered primary families (D16 version)

Measures: **1** comment lines per code line · **2** share of functions with a comment directly above ·
**3** early exits per 1,000 keyword tokens (COBOL `EXIT PARAGRAPH/PERFORM`; elsewhere `return`) ·
**4** Python helper code in a non-Python project · **5** `while` per 1,000 keyword tokens (non-COBOL).

### Family A: Sonnet vs Codex (the original registration, H1-H5): nothing confirmed, nothing refuted

| id | prediction | cells for / against (ties) | p | Holm | verdict |
|---|---|---|---|---|---|
| A1 | Sonnet comments more | 8 / 2 | 0.055 | 0.22 | ⚠ inconclusive |
| A2 | Sonnet documents functions more | 4 / 2 (4) | 0.34 | 0.69 | ⚠ inconclusive |
| A3 | Codex exits early more | **9 / 1** | 0.011 | **0.054** | ⚠ inconclusive (just short) |
| A4 | Codex adds Python helpers | 0 / 0 (8) | — | — | ⚠ not testable: no run of any arm wrote one |
| A5 | Sonnet uses `while` more | 6 / 2 | 0.14 | 0.43 | ⚠ inconclusive |

### Family B: Haiku vs Codex (D10): two confirmed

| id | prediction | for / against | Holm | verdict |
|---|---|---|---|---|
| B1 | Haiku comments more | 9 / 1 | 0.043 | ✓ primary only (not robust, see §3) |
| **B2** | **Haiku documents functions more** | **10 / 0** | **0.005** | **✓ confirmed** |
| B3 | Codex exits early more | 8 / 2 | 0.16 | ⚠ |
| B4 | Codex Python helpers | 0 / 0 | — | ⚠ not testable |
| B5 | Haiku `while` more | 4 / 4 | 1.0 | ⚠ |

### Family C: Haiku vs Sonnet (two-sided)

| id | measure | Haiku higher / Sonnet higher | Holm | |
|---|---|---|---|---|
| **C1** | comment lines per code line | **10 / 0** | **0.010** | ✓ Haiku higher |
| **C2** | functions documented | **10 / 0** | **0.010** | ✓ Haiku higher |
| C3 | early exits | 6 / 3 | 1.0 | — |
| C4 | Python helpers | 0 / 0 | — | — |
| **C5** | `while` | **0 / 8** | **0.023** | ✓ Sonnet higher |

### Families D and E: the noise floor (Sonnet vs Sonnet, Haiku vs Haiku): null, as predicted

Every measure: no difference (all Holm p = 1.0). Each model reproduces its own habits across two independent
rounds.

**Reading (fixed in D10 before the data):** A not confirmed, B partly confirmed, C significant on comments. The
commenting habit is strongest in **Haiku**, not a property of "Claude Code" as a whole, and it is stable within
each model (D, E).

## 3. Robustness

| check | effect |
|---|---|
| Failed runs excluded (registered sensitivity) | B2, C1, C2, C5 stay significant; **B1 loses it** (Holm 0.14); A3 7 / 1 (Holm 0.18) |
| Instrument default (D16 cells missing) | B1 Holm 0.22; everything else as above |
| Exploratory set re-scanned with this engine | reproduces its original directions (10 / 0, 10 / 0, 9 / 1, 4 / 0, 5 / 0) |

## 4. Registered secondary and variance tests (Sonnet vs Codex, uncorrected)

| id | prediction | result | verdict |
|---|---|---|---|
| S1 | Sonnet higher fan-out | **0 of 7 cells: Codex higher in all 7** | ✗ refuted (reversed) |
| S2 | Codex higher median complexity | 5 of 7, p = 0.23 | ⚠ |
| S3 | COBOL reverses S1/S2 | 0 of 2 COBOL cells | ✗ not supported |
| S4 | Sonnet's comments name more of the techniques it implements | 1 of 1 (4 cells tie at zero) | ⚠ not evaluable: Sonnet names almost none |
| S5 | Sonnet more bitwise operations | 6 of 7, p = 0.06 | ⚠ direction holds |
| V1 | comment volume a stable trait (two repeat cells) | passes chess/Rust, fails SAT/Python | ✗ not supported |
| V2 | overall structure *not* a stable trait (within/between sfs ratio ≥ 0.85) | **ratio 0.44** (both cells) | ✗ not supported: **structure is stable within a model** |

## 5. Structural fingerprints (sfs, structure lens; D16)

| relationship | median profile distance |
|---|---|
| same model, same task + language, another run | **0.32** |
| different model, same task + language | **0.62** |
| same model + language, other task | 0.64 |
| same model + task, other language | 1.01 |
| different model, other task or language | 1.07 |

Same cell, model pairs: Haiku–Codex 0.55, Haiku–Sonnet 0.64, Sonnet–Codex 0.66. **Exploratory model
identification:** the nearest same-cell neighbour is the same model in **43 of 52** runs (83 %; chance 27 %;
permutation p < 0.001). The portable lens gives 82 %. Language moves a program most; task and model about
equally.

## 6. Keywords (exploratory except S6)

- **S6 (registered secondary):** Codex `CALL` more than Sonnet: not testable (neither used it in COBOL); Sonnet
  `EVALUATE` more: 1 of 1 cell.
- **Exploratory leans that replicated:** Codex `return` more than Sonnet in **8 of 8** cells; Codex Java `throw`
  (2 of 2, against both Claude models).
- **Exploratory leans that vanished:** Codex COBOL subprograms (now Haiku writes them), Claude COBOL
  `FILLER`/`REDEFINES`, Rust `#[inline]`/`unsafe`, Python `@dataclass`; Claude `for` reversed.
- **New (hypotheses for a next registration):** Codex Python uses `yield`/`raise`/`finally`/`nonlocal`, which no
  Claude run uses. Haiku writes C `bool`, Java `private` (112 uses; none in the other arms) and Rust `pub`/`mod`.
  Sonnet writes more `if`/`while` than Haiku (8 of 8 cells) and COBOL `GO TO`/`THRU`. About 450 keyword × pair
  comparisons were made, so single findings are hypotheses.

## 7. The instrument

- **Agreement:** where GitGalaxy read a file, its functions match tree-sitter and ctags almost one for one in every
  arm (e.g. 363 / 363 / 363 for Haiku), and parameter counts agree on all 1,204 comparable pairs.
- **The gap:** four Codex programs were skipped whole by the anti-minification and packed-payload guards
  (lines up to 2,303 chars). Rescanning with the guard lifted (one file), and with formatter-wrapped copies (three
  files), recovers them: GitGalaxy = ctags at 23, 20 and 30 functions. Upstream fix:
  [gitgalaxy#7501](https://github.com/squid-protocol/gitgalaxy/issues/7501).
- **The comment classifier**, hand-checked blind on 100 fresh blocks: **54 %**, down from 91 %. It misses most
  rationale (0 of 11) and invariant comments (4 of 26). No registered test uses its classes.

## 8. Order of events, stated plainly

The registered tests were computed before the scan-validity appraisal (D16). A missing-value pattern exposed the
gap, the handling rule was fixed before the appraisal reported, and both versions are shown. The confirmation cell
table was written after the scans but before any measure (D14). Twelve Python programs had no file extension; the
rule for them was fixed before any measure value was read (D15).
