# Cross-Task COBOL Model Attribution Check (`doom-dna` ↔ `agent-habits`)

Tested whether the 32-keyword-family lattice (`kw_JSD`, which achieved `0.944` ROC AUC within `chess`/`sat` same-task pairs) can attribute the generating model **across completely different tasks** by comparing 4 `doom-dna` COBOL targets (`agentic-cobol-doom-cc`, `agentic-cobol-doom-codex`, `fps-cob`, `carddemo-cobol-ctrl`) against the 10 `agent-habits` COBOL runs (`chess` and `sat`) using `structural_fingerprint.lattice.seed_and_extend_with_lattice`.

Script: [`cross_task_attribution.py`](cross_task_attribution.py) · Data: [`cross_task_attribution.csv`](cross_task_attribution.csv)

## Results (Means Across `agent-habits` COBOL Runs)

| Target (`doom-dna`) | Funcs | vs `sonnet` (`n=4`) | vs `haiku` (`n=4`) | vs `codex` (`n=2`) |
|---|---:|---|---|---|
| **`agentic-cobol-doom-cc`** *(Claude Code)* | 54 | **`kw_JSD=0.200`** (`0.165` min), `FGW=0.670` | `kw_JSD=0.213`, **`FGW=0.646`** | `kw_JSD=0.212`, `FGW=0.723` |
| **`agentic-cobol-doom-codex`** *(Codex CLI)* | 167 | `kw_JSD=0.371`, `FGW=0.714` | `kw_JSD=0.361`, `FGW=0.697` | `kw_JSD=0.379`, `FGW=0.744` |
| **`fps-cob`** *(human)* | 54 | `kw_JSD=0.203`, `FGW=0.666` | `kw_JSD=0.205`, `FGW=0.637` | `kw_JSD=0.156`, `FGW=0.690` |
| **`carddemo-cobol-ctrl`** *(human CICS)* | 55 | `kw_JSD=0.379`, `FGW=0.762` | `kw_JSD=0.385`, `FGW=0.724` | `kw_JSD=0.420`, `FGW=0.772` |

## Verdict: Boundary Found (Cross-Task Attribution Does Not Transfer Out-of-the-Box)

- `agentic-cobol-doom-cc` is slightly closest to `sonnet` on `kw_JSD` (`0.200`, min `0.165`) and to Claude models on `FGW` (`0.646–0.670` vs `0.723` for `codex`).
- However, **`agentic-cobol-doom-codex` does NOT match `chess/sat-cobol-codex`** (`kw_JSD=0.379`, `FGW=0.744`), sitting as far away as enterprise `carddemo-cobol-ctrl` (`0.379–0.420`), and human `fps-cob` sits closer to `codex` on `kw_JSD` (`0.156`) than `agentic-cobol-doom-codex` does.
- **Conclusion:** While `kw_JSD` (`0.944` AUC) + FGW (`0.874` AUC) cleanly separate models **within the same task & language**, **cross-task attribution across unrelated domains** (`raycaster` vs `chess`/`sat`) is confounded by task-specific structure and multi-language/FFI wrappers (`167` funcs in `agentic-cobol-doom-codex`).
