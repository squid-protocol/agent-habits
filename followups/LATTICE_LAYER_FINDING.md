# Function-Lattice Distribution Layer After Seed-and-Extend (`agent-habits`)

Adding the **14-archetype function lattice** (`portable` reference) as a second layer *after* FGW Seed-and-Extend (`lattice_layer_study.py`, `lattice_layer_pairs.csv`) sharply separates **same-model repeats**, **cross-model pairs**, and **Anthropic vs. Codex** — even on the exact same task and language.

---

## 1. Per-Model 14-Archetype Lattice Signature

Four of the 14 `portable` archetypes carry 100% of the mass across the 56 runs and cleanly order the three model families:

| Archetype | `codex` | `sonnet` | `haiku` |
|---|---:|---:|---:|
| **Compute Cores** | **41.6%** | 24.9% | 8.3% |
| **I/O & Config Routines** | 43.7% | 53.9% | **59.9%** |
| **Many-Argument Workhorses** | 13.8% | 18.3% | **25.4%** |
| **State Mutators** | 1.0% | 2.9% | **6.3%** |

---

## 2. Post-Seed-and-Extend Differentiation (Medians)

| Category | Pairs | `FGW_cost` | `arch_JSD` | `matched_arch_agree` | `post_delta_res` | `matched_loc_diff` |
|---|---:|---:|---:|---:|---:|---:|
| **Same task, same lang, same model** | 41 | **0.548** | **0.139** | **77.3%** | **0.535** | **21.6%** |
| **Same task, same lang, diff model** | 104 | 0.696 | 0.213 | 54.2% | 1.041 | 42.0% |
| **Same task, diff lang, same model** | 236 | 0.751 | 0.329 | 45.5% | 1.263 | 44.7% |
| **Same task, diff lang, diff model** | 376 | 0.768 | 0.426 | 42.9% | 1.379 | 48.8% |
| **Cross-task control (`chess` ↔ `sat`)** | 60 | 0.744 | 0.205 | 54.8% | 1.270 | 46.2% |

---

## 3. Model-Pair Separation Within Same Task & Language

| Pair | Pairs | `FGW_cost` | `arch_JSD` | `matched_arch_agree` | `post_delta_res` |
|---|---:|---:|---:|---:|---:|
| `sonnet` ↔ `sonnet` | 20 | **0.489** | 0.163 | **83.3%** | **0.431** |
| `haiku` ↔ `haiku` | 20 | 0.599 | **0.128** | 71.0% | 0.777 |
| `sonnet` ↔ `haiku` | 64 | 0.678 | 0.196 | 62.0% | 0.883 |
| `sonnet` ↔ `codex` | 20 | 0.693 | 0.213 | 50.0% | 1.492 |
| `haiku` ↔ `codex` | 20 | 0.714 | 0.308 | 40.0% | 1.264 |

**Takeaway:** Even after Seed-and-Extend aligns the call graph, the **post-SE function lattice** (`matched_arch_agree`, `arch_JSD`, and `post_delta_res`) nearly **doubles** the separation between same-model repeats (`77.3%` agree, `0.535` residual) and cross-model pairs (`54.2%` agree, `1.041` residual), and recovers the family hierarchy (`sonnet↔haiku` > `sonnet↔codex` > `haiku↔codex`).
