# Seed-and-Extend Structural DNA Across `agent-habits` (56 Runs)

Parallel study to [`squid-protocol/doom-dna`](https://github.com/squid-protocol/doom-dna): running unsupervised **Seed-and-Extend** (`composition` mode + Fused Gromov–Wasserstein `alpha=0.5, eps=0.05, outer=40` + `delta` offset + 3-hop call-graph extension, zero identifiers read) across 56 valid scans in `confirm/scans/confirm` (`chess` and `sat`, 5 languages, 5 arms) plus `linuxdoom` as a negative control.

Script: [`seed_and_extend_study.py`](seed_and_extend_study.py) · Pairwise output: [`seed_and_extend_pairs.csv`](seed_and_extend_pairs.csv)

---

## 1. Category Summary (825 Pairs)

| Category | Pairs | Median `FGW_cost` (Min) | Mean Tier-1 Name Prec. | Mean 3-Hop SE Name Prec. |
|---|---:|---:|---:|---:|
| **Same task, same language, same model** | 41 | **0.548** (`0.154`) | **66.7%** | **50.9%** |
| **Same task, same language, different model** | 104 | 0.696 (`0.505`) | 44.6% | 26.5% |
| **Same task, different language, same model** | 236 | 0.751 (`0.574`) | 28.9% | 15.2% |
| **Same task, different language, different model** | 376 | 0.768 (`0.620`) | 23.4% | 13.3% |
| **Cross-task control (`chess` ↔ `sat`, same lang & model)** | 60 | 0.744 (`0.599`) | 16.1% | 8.7% |
| **Cross-domain negative control (`chess`/`sat` ↔ `linuxdoom`)** | 8 | 0.771 (`0.750`) | **0.0%** | **0.7%** |

---

## 2. Model Self-Similarity (`same_task_same_lang_same_model`)

Independent runs of **Sonnet** (`claude` / `sonnet-b`) on the same task and language converge on nearly identical call-graph DNA — tighter than **Haiku** (`haiku` / `haiku-b`):

| Model Family | Pairs | Median `FGW_cost` | Mean Tier-1 Name Prec. | Mean 3-Hop SE Name Prec. |
|---|---:|---:|---:|---:|
| **Sonnet** (`claude` ↔ `sonnet-b`) | 20 | **0.489** | **78.7%** | **68.1%** |
| **Haiku** (`haiku` ↔ `haiku-b`) | 20 | 0.599 | 53.1% | 32.6% |
| **Codex** (`codex`, 1 repeat cell) | 1 | 0.472 | 100.0% | 72.7% |

### Tightest Independent Run Pairs

| Pair | `FGW_cost` | Tier-1 Name Prec. | 3-Hop SE Name Prec. |
|---|---:|---:|---:|
| `sat-python-claude-r1` ↔ `sat-python-sonnet-b-r1` | **0.1544** | **100.0%** | **100.0%** |
| `sat-python-claude-r1` ↔ `sat-python-claude-r2` | **0.1907** | **100.0%** | **100.0%** |
| `sat-python-claude-r2` ↔ `sat-python-sonnet-b-r1` | **0.2096** | **100.0%** | **100.0%** |
| `sat-rust-claude-r1` ↔ `sat-rust-sonnet-b-r1` | 0.3316 | 100.0% | 66.7% |
| `chess-java-claude-r1` ↔ `chess-java-sonnet-b-r1` | 0.3658 | 66.7% | 84.2% |
| `sat-c-claude-r1` ↔ `sat-c-sonnet-b-r1` | 0.4093 | 100.0% | 75.0% |

---

## 3. Similarities & Differences vs. `doom-dna`

1. **Same-model AI repeats look like DOOM source forks:** Independent Sonnet runs (`FGW = 0.154–0.489`, `78.7%` T1 / `68.1%` SE) match or exceed the structural similarity of true C DOOM ports (`doomgeneric` ↔ `linuxdoom` `0.567`, `cydoomgeneric` ↔ `doomgeneric` `0.313`) — even with **zero shared codebase ancestry**, because the model's learned architectural template acts as a common ancestor.
2. **Model identity is an architectural fingerprint:** Switching models on the exact same prompt and language (`same_task_same_lang_diff_model`) jumps median `FGW_cost` from `0.548` to `0.696` and halves 3-hop SE precision (`50.9% → 26.5%`), mirroring how switching paradigms/rewriting from scratch in `doom-dna` erases call-graph similarity.
3. **Zero cross-domain bleed:** `chess` / `sat` C runs against `linuxdoom` sit at `FGW = 0.771`, `0.0%` Tier-1, `0.7%` SE — confirming the `doom-dna` noise floor.
