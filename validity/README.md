# confirm/validity: scan-validity appraisal of GG extraction on the 60 confirmation runs

Purpose: before any study result is used, check how much of each run's code GitGalaxy (GG) read and how well its
function definitions agree with tree-sitter (TS) and universal-ctags (CT), by arm. No study measure was computed
or read (nothing under `../measure/` was opened). No tool is ground truth; the numbers count agreement.

## Inputs, versions
- Runs: `../scan_src/confirm/<run>/` (60). GG scans: `../scans/confirm/<run>/*_galaxy_master.db`, engine main
  7d2e1f627 (`../engine`), `GITGALAXY_DISABLE_GIT_HISTORY=1` (`../scan_all.sh`). Nothing was rescanned.
- Adapter: `/home/joe/gitgalaxy/chess-study/compare/compare.py`, imported read-only (`gather_file`, `slots_for`,
  `guess_cause`, `available`); its engine tool modules (`ctags_reader`, `tri_comparison_gatherer`,
  `tri_comparison_reconcile`, `tree_sitter_accuracy_audit`) are byte-identical between engine 433228fe1 and 7d2e1f627.
- Venv `/home/joe/gitgalaxy/venvs/doom-ci` (py3.12.3): tree-sitter 0.26.0, tree-sitter-language-pack 1.22.1.
  Universal Ctags 5.9.0.
- Rerun (about 5 s, one core): `PYTHONPATH=/home/joe/gitgalaxy/chess-study/engine /home/joe/gitgalaxy/venvs/doom-ci/bin/python validity.py`

## Method
- Cell language = the run id's language. A file belongs to it by extension (`.c/.h`, `.java`, `.py`, `.rs`,
  `.cob/.cpy`) or, when extension-less, by its `#!` line (the Python `./engine` / `./solver` executables);
  TS and ctags are forced to that language's parser (ctags `--language-force`).
- Definitions: functions only (compare.py's NODE_MAPS kinds for TS, `ctags_reader` function kinds for CT; GG
  `function_data` minus synthetic units, of which there were none). Pairing is `tri_comparison_reconcile`'s
  (name + line proximity). Each occurrence lands in one column: matched_all, GG-only, TS-only, CT-only, or a
  two-tool column.
- **COBOL deviation from compare.py:** TS has no COBOL node map, so COBOL is GG vs ctags only. All programs are
  built with `cobc -free`, so ctags' `CobolFree` parser is used (in memory, `ctags_reader.LANG_MAP['cobol']`;
  `GG_VALIDITY_COBOL_CTAGS=Cobol` reproduces compare.py's fixed-format setting, which misreads these files; see
  samples.md section 3).
- Files GG excluded: TS and ctags still run; GG is 0 by construction; rows say `excluded`.
- Extra: `spans.csv` compares each GG unit's `loc` with the TS node's line span (start line within 1).

## Outputs
- `exclusions.csv`: every file GG excluded or did not record (reason, size, lines, max line length, source/main flags).
- `coverage.csv`: per run, cell-language files/bytes/lines on disk vs read by GG, max line length, lines >200/>400.
- `definitions.csv`: per run (`level=run`), per arm x language, per arm (c+java+python+rust vs cobol), split
  read/excluded, plus `arm (all files)`; parameter-count agreement columns. `definitions_by_file.csv`: per file.
- `definition_causes.csv`, `definition_causes_by_arm.csv`: disagreement slots by cause class. `samples.md`,
  `samples_raw.txt`: examples. `spans.csv`: unit spans.

## Summary
**Coverage (share of cell-language source GG read).** claude, sonnet-b, haiku, haiku-b: 100% of bytes and lines in
all 12 runs each. **codex: 74.3% of bytes, 94.8% of lines pooled; 4 of 12 runs at 0%** (mean per-run share 0.667).
The only main-source exclusions in the 60 runs are Codex's (aperture saturation gate, a line >500 chars in the
first 100 lines and no short `) {` definition line to rescue it):
chess-c-codex-r1 `engine.c` (56 lines), sat-c-codex-r1 `solver.c` (15), chess-rust-codex-r1 and -r2 `src/main.rs`
(35, 37). These are the Codex C cell (both runs) and the Codex chess-Rust cell (both reps): those cells have no GG
data at all. Everything else excluded is build output, binaries, lockfiles, `Cargo.toml`, `.gitignore`, a plaintext file, or a
gitignored shell wrapper. Codex is also the only arm with >500-char lines anywhere (6 runs; 30 lines >400 chars vs
0 in other arms); two of its dense files were read only because the rescue found one short definition.

**Agreement where GG read the file.** c/java/python/rust functions, GG / TS / CT / matched-all-3:
claude 179/179/179/179; sonnet-b 172/175/175/172 (3 TS+CT-only); haiku 363/363/363/363;
haiku-b 385/385/385/385; codex 106/106/107/105 (1 TS+CT-only, 1 GG+CT-only). Parameter counts agree on all
1,204 comparable pairs with each tool. COBOL (GG vs ctags CobolFree): GG's 352 paragraphs all match
(claude 78, codex 37, haiku 84, haiku-b 82, sonnet-b 71); ctags' 256 extra tags are all ctags phantoms
(scope terminators, data-division headers).

**Disagreement classes, ranked:** (1) saturation exclusion, 81 functions, Codex only; (2) Rust attribute line
counted in the unit span (+1 line, 70 functions; haiku-b 45, haiku 24, claude 1); (3) methods inside a one-line
class body missed by GG, 4 (sonnet-b 3 in sat-java-sonnet-b-r1, codex 1); (4) Java record header, 1 (TS gap).

**Arm-specific bias.** The exclusion gap falls entirely on Codex (C and chess-Rust cells blank, 26% of Codex bytes),
so any between-arm comparison that includes those cells, or pools Codex across languages, compares Codex's
Java/Python/COBOL/sat-Rust code against everyone else's full set. A missing-file rate correlated with code density
is also correlated with Codex's style, so dropping the cells is not neutral either. The span +1 for `#[...]`
attributes is concentrated in the Haiku arms (Rust per-function line counts slightly higher than TS's). The
one-line-class miss is small (4 functions). Not appraised here: anything below the definition level on dense lines
(per-line signals, comment/code splitting on >200-char lines), which falls mostly on Codex.
