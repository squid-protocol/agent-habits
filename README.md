# Agent habits

> **Abstract.** We asked whether AI coding agents leave measurable, model-specific habits in the programs they
> write, and whether a training-free, AST-free structural scanner can see them. Three agent/model combinations
> (Claude Code with Sonnet 5.5 and with Haiku 5.5, two independent rounds each; Codex CLI with gpt-6-luna) each
> built a UCI chess engine and a DPLL SAT solver in C, Java, Python, Rust and COBOL without human steering: 60
> programs, 59 of them working. The hypotheses came from an exploratory analysis of Mathieu Acher's human-steered
> Claude Code / Codex pairs and were pre-registered with a public timestamp before any run. The predicted
> Claude-vs-Codex habits were **not confirmed** after correction. Codex's tendency to exit early came closest (9 of
> 10 cells, Holm p = 0.054); its Python helper scripts disappeared; and the fan-out prediction reversed. Instead,
> habits proved **model-specific**: Haiku comments and documents more than Sonnet in all 10 cells, and documents
> more functions than Codex in all 10. Each model's habits replicate across independent rounds. Structure alone is
> distinctive. With no training step, a program's nearest structural neighbour on the same task and language came
> from the same model **83 % of the time (chance 27 %, p < 0.001)**. That result was exploratory and is
> pre-registered for replication on fresh runs and a new task (round 3). We also found that AI-written code can
> defeat static-analysis safeguards. Codex's ultra-dense programs (whole chess engines in 35–56 lines) were
> skipped by the scanner's anti-minification guard. The gap was caught by a tree-sitter/ctags cross-check, handled
> by a pre-stated rule and fixed upstream.

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

## Related work, and what this study corroborates

That LLMs leave identifiable fingerprints in code is an active research topic. This study is small next to those
benchmarks, and it is not the first to show attribution. Its contribution is the setting (whole programs from
autonomous CLI agents, five languages including COBOL, two independent rounds per model), the method (training-free
structural matching, no AST, no LLM, no comment text) and the pre-registration, negatives included. The summaries
below are drawn from the papers' abstracts and published summaries.

| work | what it reports | what this study corroborates, or adds |
|---|---|---|
| Bisztray et al., [*I Know Which LLM Wrote Your Code Last Summer*](https://arxiv.org/abs/2506.17323) (ACM AISec 2025) | A trained classifier on 32,000 compilable C programs from eight LLMs attributes code to its model (about 95 % across five models; about 97.6 % between closely related ones). Comment phrasing and style are a dominant feature. | **Corroborates** that the generating model is identifiable from its code, here **without training** and **without comment text** (83 %, chance 27 %, nearest structural neighbour). **Consistent with** comments as a strong model marker: comment amount and placement separate Haiku from Sonnet and Codex in every cell. |
| [*The Hidden DNA of LLM-Generated JavaScript*](https://arxiv.org/pdf/2510.10493) (2025) | Structural patterns allow high-accuracy attribution of LLM-written Node.js programs, robust even to minification (about 91 %). | **Corroborates** structure, not surface text, as the carrier of a model's identity, in five other languages. **Adds the converse risk:** dense AI-written code can be *mistaken for minified code* by a scanner's own safeguards, silently dropping one author's programs. |
| [*Code Fingerprints: Disentangled Attribution of LLM-Generated Code*](https://arxiv.org/pdf/2603.04212) (DCAN, 2026) | Separates semantic from stylistic signal; in its case study, Claude-generated code puts more weight on explicit control-flow constructs. | **Partly consistent:** Sonnet uses more `if`/`while` than Haiku in all 8 non-COBOL cells; against Codex, Sonnet's `while` lead is only directional (6 of 2, not significant), and Codex uses more early `return`. The control-flow habit looks model-specific here, not vendor-wide. |
| [*Style, Not Self: Surface Cues Explain Zero-Shot Code Attribution by LLMs*](https://arxiv.org/html/2609.30048v1) (2026) | Argues that surface style cues explain how LLMs attribute code. | **Consistent with** our reading that a fingerprint is a stable *habit of form* (distances 0.32 within a model vs 0.62 between models, replicated across independent rounds), not a trace of what the program does: every program here solves the same task. |
| Acher, [*agentic-cobol-study*](https://github.com/acherm/agentic-cobol-study) and *agentic-chessengine-\** | Same tasks built by Claude Code and Codex, human-steered, with code, history and session logs preserved. | The source of our exploratory hypotheses. Of its habits, **early exits held their direction** under autonomous runs and newer models. **Commenting held for Haiku but weakened for Sonnet; Python helpers vanished; fan-out reversed.** Steering and model version matter. |

Practitioner comparisons of Claude Code and Codex are mostly anecdotal (blog posts and single-user tests). We found
no controlled, same-task comparison of their code's structure before this one, though our search was not
exhaustive.

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
