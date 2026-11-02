# Exploratory follow-ups

Measured **after** the registered tests, on the same scans (GitGalaxy `7d2e1f627`). None of these was predicted in
advance; each reports its own comparison or control, and each should be confirmed on fresh runs before anyone builds on
it. Every folder has a re-runnable `measure.py` (`/path/to/venv/bin/python -I measure.py`), its per-program table and a
one-page `FINDING.md` with caveats.

| Folder | Question | One-line finding |
|---|---|---|
| [`size-shape/`](size-shape/FINDING.md) | Do the models differ in program size and function shape? | Codex packs its code tight (smaller than Sonnet in 9 of 10 jobs, denser in 10 of 10); Haiku writes the most code but keeps its worst function simpler than Sonnet's (10 of 10). |
| [`wiring/`](wiring/FINDING.md) | Does Codex route its calls through a few hub functions? | Not outside COBOL: top-3 share 37% vs Sonnet's 36%. Haiku's call chains run deeper than Codex's (7 of 7). `per_run_edges/` holds every program's call graph (names only). |
| [`time-vs-code/`](time-vs-code/FINDING.md) | Does more working time make different code? | No: within a model, the slower run was the bigger one in 13 of 22 pairs. Haiku is slow because it works in many small steps. |
| [`steered-vs-autonomous/`](steered-vs-autonomous/FINDING.md) | Which hunches from Acher's human-steered pairs survived autonomous runs and newer models? | Early exits, Codex's complexity and Claude's bitwise operations kept their direction; commenting survived only in Haiku; fan-out reversed. Directions only, uncorrected. |
