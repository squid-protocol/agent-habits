# Orthogonal Procrustes vs. Translation & Held-Out `explore/` Attribution

Tested ([`procrustes_and_explore_study.py`](procrustes_and_explore_study.py)) on all 56 `confirm` runs + 16 held-out `confirm/scans/explore/` scans (`agentic-chessengine-*` and `agentic-cobol-*`).

## 1. Orthogonal Procrustes vs. Pure Translation (`confirm`, Leave-One-Task-Out)

| Method | Held-out `sat` AUC (fit `chess`) | Held-out `chess` AUC (fit `sat`) |
|---|---:|---:|
| Raw `kw_JSD` | 0.520 | 0.660 |
| **Pure Translation (`delta_lang`) `kw_JSD`** | 0.602 | **0.698** |
| **Orthogonal Procrustes (`W_lang`) L2** | **0.606** | 0.645 |

Pure translation (`delta_lang`, 32 parameters) matches or outperforms a 32×32 Orthogonal Procrustes rotation (which overfits with ~5 paired runs per language).

## 2. Zero-Shot Held-Out `explore/` Attribution (`Claude Code` vs. `Codex CLI`)

Using only the language-centered difference vector `w_clf = mean(claude_res) - mean(codex_res)` fit on `confirm`:
- **Overall held-out ROC AUC (`n=16`):** **`0.730`** (`62.5%` accuracy at uncalibrated `0.0` threshold).
- **Pairwise within-`(task, lang)` ordering (`cc > codex`):** **6 / 7 pairs** (`100%` of `chess` across C, COBOL, Java, Python, Rust, **plus** `agentic-cobol-doom-cc > agentic-cobol-doom-codex`: `+0.0152` vs `-0.0395`). Only `agentic-cobol-sat` inverted (`-0.0710` vs `-0.0591`).
