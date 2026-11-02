# Agent habits

**Do AI coding agents have habits you can measure from their code?** We gave the same two tasks (a UCI chess
engine and a DPLL SAT solver) in the same five languages (C, Java, Python, Rust, COBOL) to three agent/model
combinations, with no human in the loop, and measured what they wrote with
[GitGalaxy](https://github.com/squid-protocol/gitgalaxy): an AST-free, LLM-free structural scanner.

- **Claude Code on Sonnet 5.5**: two independent rounds
- **Claude Code on Haiku 5.5**: two independent rounds
- **OpenAI Codex CLI on gpt-6-luna** (ChatGPT Free): one round

That makes 60 runs, 57 of which passed the task's hidden test on the first try. Every hypothesis was
pre-registered, with a public timestamp, before any of this data existed.

## The answer, in one paragraph

Each model writes code with a **stable, recognisable structure**. Given only GitGalaxy's structural fingerprint of
a program, its nearest neighbour among programs for the same task and language comes from **the same model 83 % of
the time** (43 of 52; chance 27 %, permutation p < 0.001). Two runs of one model sit about half as far apart
as two different models (sfs profile distance 0.32 vs 0.62). The *habits* that separate the models are not the
ones the earlier exploratory study suggested:

- **Haiku comments and documents the most**: more than Sonnet in all 10 cells, and documents more functions than
  Codex in all 10.
- **Sonnet vs Codex**, the pre-registered headline comparison, confirmed nothing after correction. Every testable
  direction matched the exploratory study, and the closest was **Codex exits early more** (9 of 10 cells,
  Holm p = 0.054).
- **Codex writes extraordinarily dense code** (whole chess engines in 35-56 lines). Dense enough that the scanner's
  anti-minification guard skipped four Codex programs; that was found, handled by a pre-stated rule, and fixed
  upstream ([gitgalaxy#7501](https://github.com/squid-protocol/gitgalaxy/issues/7501)).

Full results, with every registered verdict, are in [RESULTS.md](RESULTS.md).

## Built on Mathieu Acher's paired-agent studies

This work exists because **[Mathieu Acher](https://mathieuacher.com/)** (Professor of Computer Science, University
of Rennes / IRISA) published something rare: the *same* tasks built by Claude Code and by Codex, side by side, with
the code, git history and session logs preserved:

- **[agentic-cobol-study](https://github.com/acherm/agentic-cobol-study)**: "Coding Agents Develop COBOL Systems",
  16 systems (chess engine, compressor, DOOM-like game, pygame-style framework, SAT solver) with an analysis pipeline,
  session logs and replay packs (MIT).
- **agentic-chessengine-\***: chess engines built by Claude Code and Codex in 15+ languages, with a meta-analysis
  ([agentic-chessengine-metaanalysis](https://github.com/acherm/agentic-chessengine-metaanalysis)).

Our **exploratory** analysis used ten of his MIT-licensed same-task pairs (C, C++, Java, Python, Rust and COBOL
chess engines, plus four COBOL systems). The habits it suggested became the predictions we registered, and this
repository tests them on **fresh code** that no hypothesis had seen. His study is human-steered (one of his COBOL
engines records "47 substantive prompts, 15.5 active hours"); ours is autonomous. That difference, and the newer
models, are part of the result. Any error here is ours, not his.

## How it was done (and how you can check it)

1. **Exploratory**: GitGalaxy and [sfs](https://github.com/squid-protocol/gitgalaxy-population-analyses/tree/main/structural-fingerprint-scanner)
   scans of the ten Acher pairs. Comments, keywords, structure.
2. **Pre-registration**: hypotheses, tests, α, and the sha256 of every analysis script, committed before any
   confirmation run ([gitgalaxy-population-analyses `agent-habits-prereg/`](https://github.com/squid-protocol/gitgalaxy-population-analyses/tree/main/agent-habits-prereg),
   commit `5700b9e`, 2026-11-01T12:41Z). Every later change is a dated deviation, committed before it was used:
   [preregistration/PREREGISTRATION.md](preregistration/PREREGISTRATION.md), D1-D16.
3. **Runs**: each agent got one fixed prompt per task, in a fresh container, with a 60-minute cap. A hidden
   checker decided "done": perft, mate puzzles and a match against a weak opponent for chess; hard SAT/UNSAT
   formulas for SAT. The agents practised on a separate set.
   [kit/](kit/) (prompts, checker with the held-out set, harness, Dockerfile) · [runs/](runs/) (all 60 programs as
   written, the run log, each run's prompt and check).
4. **Validity**: GitGalaxy's function extraction compared with tree-sitter and ctags on all 60 runs
   ([validity/](validity/)). Where GitGalaxy read a file, the three agree almost one for one. The one gap was
   Codex's dense code (above).
5. **Measurement**: the frozen scripts, applied through [measure/adapter.py](measure/adapter.py). Results are in
   [results/data/](results/data/), with both the instrument-default and the D16 versions.

Engine for every number: GitGalaxy main `7d2e1f627`. To re-derive the tables: `python measure/adapter.py`, then
`families_d16.py`, `sensitivity.py`, `secondary.py`, `keywords_confirm.py`, and `measure/run_sfs.sh` plus
`relations_d16.py`. The scripts read the local scans by absolute path; the scans are regenerated by
`measure/scan_all.sh`.

## What it does not show

- **Which agent is better.** No quality ranking is attempted here; the tasks were only pass/fail.
- **Habits in human-steered work.** These runs are autonomous; Acher's are steered.
- **Anything about other models, tasks or languages.** Ten cells is small, and several results rest on one or two
  cells. The keyword and content findings beyond the registered tests are exploratory, and we say so where they
  appear.
- **Comment content.** The comment classifier's accuracy fell to 54 % on this new code (91 % on the exploratory
  sample), so we report comment *amounts* and *placement*, not what the comments say.

## Repository map

| path | what |
|---|---|
| `RESULTS.md` | every registered verdict, the sensitivity analyses, the sfs and keyword findings |
| `preregistration/` | the registration with deviations D1-D16, the frozen exploratory scripts, the found-pair search |
| `kit/` | prompts, checker (held-out and practice sets), harness, Dockerfile, run order |
| `runs/` | the 60 programs (`code/`), the run log (`runs.csv`), per-run prompt and checks (`meta/`), pilot log |
| `measure/` | the adapter and the analysis scripts |
| `results/data/` | every table as JSON or CSV |
| `validity/` | the GitGalaxy vs tree-sitter vs ctags appraisal |

Measurements, counts and names describe the measured code. The 60 programs in `runs/code/` were written by the
agents for this study. No third-party source is reproduced.
