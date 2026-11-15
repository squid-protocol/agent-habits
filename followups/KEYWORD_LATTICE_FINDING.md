# 32-Keyword-Family Lattice vs. Seed-and-Extend vs. 14-Archetype Clusters (`agent-habits`)

Head-to-head comparison ([`keyword_lattice_study.py`](keyword_lattice_study.py), [`keyword_lattice_pairs.csv`](keyword_lattice_pairs.csv)) across all 56 `agent-habits` runs:

1. **Whole-program 32-keyword-family lattice (`-kw_JSD`)**
2. **Call-graph FGW Seed-and-Extend (`-fgw_cost`)**
3. **Post-SE matched keyword-family cosine (`kw_cos`) & dominant-family agreement (`kw_dom_agree`)**
4. **14-archetype cluster distribution (`-arch_JSD`) & post-SE archetype agreement (`arch_agree`)**

---

## 1. ROC AUC: Same-Model vs. Different-Model (Same Task & Language)

| Layer / Metric | ROC AUC |
|---|---:|
| **32-Keyword-Family Lattice (`-kw_JSD`)** | **0.944** |
| **Call-graph FGW Seed-and-Extend (`-fgw_cost`)** | **0.874** |
| **Post-SE Matched Keyword Cosine (`kw_cos`)** | **0.796** |
| **Post-SE 14-Archetype Agreement (`arch_agree`)** | **0.724** |
| **Post-SE Keyword Dominant-Family Agreement (`kw_dom_agree`)** | **0.677** |
| **14-Archetype Cluster Distribution (`-arch_JSD`)** | **0.655** |

---

## 2. Top Discriminating Keyword Families Across Models

| Keyword Family | `codex` | `haiku` | `sonnet` |
|---|---:|---:|---:|
| `struct_branch` | **31.41%** | 20.41% | 24.94% |
| `bitwise_ops` | 0.38% | 3.63% | **6.05%** |
| `state_pointers` | 0.52% | **4.88%** | 3.69% |
| `struct_linear` | **19.95%** | 17.02% | 16.06% |
| `struct_args` | 4.29% | **7.79%** | 4.90% |
| `state_flux` | 26.40% | 24.73% | **27.95%** |
| `struct_func_start` | 5.54% | **8.35%** | 5.64% |
| `state_cast_hits` | 0.80% | 2.34% | **3.48%** |
| `def_encapsulation` | 0.00% | **2.02%** | 0.67% |
| `arch_scientific` | **2.07%** | 0.17% | 0.24% |
| `arch_api` | 2.25% | **2.72%** | 1.12% |
| `state_print_hits` | 1.13% | 0.48% | **1.23%** |

---

## 3. Medians Across Pair Categories

| Category | Pairs | `FGW` | `arch_JSD` | `arch_agree` | `kw_JSD` | `kw_dom` | `kw_cos` |
|---|---:|---:|---:|---:|---:|---:|---:|
| **Same task, same lang, same model** | 41 | **0.548** | **0.139** | **77.3%** | **0.112** | **66.7%** | **0.958** |
| **Same task, same lang, diff model** | 104 | 0.696 | 0.213 | 54.2% | 0.217 | 54.2% | 0.886 |
| **Same task, diff lang, same model** | 236 | 0.751 | 0.329 | 45.5% | 0.330 | 32.1% | 0.751 |
| **Same task, diff lang, diff model** | 376 | 0.768 | 0.426 | 42.9% | 0.351 | 31.2% | 0.757 |
| **Cross-task control (`chess` ↔ `sat`)** | 60 | 0.744 | 0.205 | 54.8% | 0.175 | 41.4% | 0.840 |
