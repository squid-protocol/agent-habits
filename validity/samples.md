# samples.md: concrete GG / tree-sitter (TS) / ctags (CT) disagreements, confirmation runs

Names and line numbers only. Each cause was checked against the source line (shape only; no source text here).
Full slot totals: `definition_causes.csv` (by cell language) and `definition_causes_by_arm.csv`. Raw sample dump
(up to 6 per class): `samples_raw.txt`. Ranked by number of definitions affected.

## 1. Saturation exclusion: GG never read the program (81 definitions, 4 runs, all Codex)
Aperture Gate 4.1 blocks a file when any of its first 100 lines is over 500 chars, unless `_has_definitions` finds
one C-style definition (`) {` on a line of at most 200 chars). The four Codex files have no such line, so the
whole program is invisible to GG (0 functions, 0 lines).

| run | file | first long line (GG reason) | lines >500 in first 100 | TS = CT functions lost |
|---|---|---|---|---|
| chess-c-codex-r1 | engine.c | 38 | 5 | 23 |
| sat-c-codex-r1 | solver.c | 15 | 1 | 8 |
| chess-rust-codex-r1 | src/main.rs | 14 | 6 | 20 |
| chess-rust-codex-r2 | src/main.rs | 16 | 7 | 30 |

Examples (TS and CT agree, GG has nothing): chess-c-codex-r1 `engine.c:16` sqfile, sqrank (two on one line), `:17`
valid, `:18` color, `:19` typ, `:20` init; chess-rust-codex-r1 `src/main.rs:8` text, `:10` sq, `:11` parse_sq,
`:13` start, `:14` fen (a 786-char line), `:15` king.

Two other Codex files have a >500-char line in their first 100 lines and WERE read, because the rescue found a
short definition: chess-java-codex-r1 `Main.java` (line 47, 533 chars) and sat-rust-codex-r1 `src/main.rs`
(line 91, 687 chars). So inclusion is not "dense = excluded": it depends on whether one short `) {` line exists.

## 2. Methods inside a class body written on one line (4 definitions; GG miss; TS+CT agree)
GG does record one-line methods (sat-java-sonnet-b-r1 `less`@15, `up`@16, `down`@17 all match), but not methods
whose enclosing class body opens and closes on the same line.
- sat-java-sonnet-b-r1 `src/Main.java:5` Clause (constructor inside a one-line nested class `Clause`)
- sat-java-sonnet-b-r1 `src/Main.java:250` add, toArray (two methods inside a one-line nested class `IntList`)
- chess-java-codex-r1 `Debug.java:1` main (the whole file is one 176-char line; GG has 0 functions in the file)

## 3. COBOL: ctags-only tags are all ctags phantoms (256 ctags tags; GG misses none)
With ctags' free-format parser (`CobolFree`), every GG paragraph pairs with a ctags paragraph/section
(352 of 352, all arms). The 256 ctags-only tags (checked case-insensitively) are:
- 200 scope terminators ending in `.` tagged as paragraphs (`END-IF`, `END-PERFORM`, `END-EVALUATE`; Codex writes
  them lower case: chess-cobol-codex-r1 `engine.cob:282` end-if, `:468` end-perform, `:249` end-perform);
  e.g. chess-cobol-haiku-b-r1 `src/core.cob:158` END-EVALUATE, `:181` END-IF, `:164` END-PERFORM.
- 56 environment/data-division headers tagged as sections (chess-cobol-haiku-b-r1 `src/core.cob:4`
  WORKING-STORAGE, `:10` LINKAGE; chess-cobol-codex-r1 `engine.cob:5` configuration).
By arm: claude 35+8, codex 20+7, haiku 55+10, haiku-b 58+23, sonnet-b 32+8 (terminators+headers).

**Parser choice matters.** compare.py's default `Cobol` (fixed-format) parser misreads these programs (all built
with `cobc -free`): it strips columns 1-7 and tags `ART` for MAIN-START at chess-cobol-claude-r1 `chess.cob:259`,
`-STR` at `:455`, `-EVALUATE` at `:292`, `-ID` at `:2`. Under it GG matches 0 of 352 except haiku-b (82 of 82),
the only arm that indents every line to column 8. That would have read as an arm effect; it is a ctags setting.

## 4. Rust attribute line included in the unit (span +1, 70 functions; names and counts agree)
GG starts a Rust function at its `#[...]` attribute line; TS starts at `fn`. Names, counts and parameters agree;
only the unit span is one line longer. chess-rust-haiku-b-r1 `src/movegen.rs:18` new (GG 18, TS 19, 4 vs 3
lines), `:22` from, `:26` to, `:31` promo, `:280` startpos_perft (a `#[test]`); chess-rust-claude-r2
`src/main.rs:53` push. By arm: haiku-b 45, haiku 24, claude 1, sonnet-b 0, codex 0 (`spans.csv`).

## 5. Java record header (1 definition; TS node-map gap, not a GG error)
chess-java-codex-r1 `Main.java:40` Move: a one-line `record` declaration. GG records a function and ctags a
method (the canonical constructor); the TS node map counts no `record_declaration`.

## Classes not seen
Outside classes 1-5 there is no disagreement in any file GG read: no nested-function, macro or dense-one-line
miss surfaced in the pairing (their presence in the code was not separately counted), (parameter counts agree on all 1,204 comparable GG/TS
pairs and all 1,204 comparable GG/ctags pairs).
