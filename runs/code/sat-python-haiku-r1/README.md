# SAT solver

`./solver FILE` reads a DIMACS CNF formula and prints a SAT-competition style answer:

- `s SATISFIABLE`, `v ...` model lines ending in `0`, exit code 10; or
- `s UNSATISFIABLE`, exit code 20.

Pure Python 3, standard library only. `./build.sh` checks the interpreter and source and marks `solver` executable.

## How it works

- **DPLL core** (`cdcl`): unit propagation with two watched literals, branching, and backtracking.
  Conflicts are analysed to the first unique implication point and the learned clause is added, so the
  search backjumps non-chronologically. This is conflict-driven clause learning, a DPLL extension.
- **Branching and restarts:** VSIDS activities in a heap (decay 0.99), phase saving, Luby restarts.
- **Clause database:** learned clauses are periodically reduced; glue clauses (LBD <= 2) and reasons are kept.
- **Local search** (`ProbSAT`): a probSAT-style random walk. It can only find models, which are verified
  before printing. The schedule is: CDCL alone for 0.2 s, local search alone for 1 s, then alternating slices (local search gets about a tenth of the CDCL time).

UNSAT answers come only from the CDCL search. A model is printed only after it has been checked against every
original clause.

## Tests

- `python3 tests/test_solver.py` compares against brute force on small random formulas.
