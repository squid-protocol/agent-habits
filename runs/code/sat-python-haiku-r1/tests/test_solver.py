#!/usr/bin/env python3
"""Self-test for ./solver: brute-force comparison on small random formulas, and model checks.

Run from the project directory:  python3 tests/test_solver.py [count]
"""

import itertools
import os
import random
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOLVER = os.path.join(ROOT, "solver")


def brute_force(n, clauses):
    for bits in itertools.product([False, True], repeat=n):
        if all(any(bits[abs(l) - 1] == (l > 0) for l in c) for c in clauses):
            return True
    return False


def run(clauses, n):
    with tempfile.TemporaryDirectory() as td:
        path = os.path.join(td, "f.cnf")
        with open(path, "w") as f:
            f.write(f"p cnf {n} {len(clauses)}\n")
            for c in clauses:
                f.write(" ".join(map(str, c)) + " 0\n")
        p = subprocess.run([SOLVER, path], capture_output=True, text=True, timeout=60)
    return p


def main() -> int:
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    rng = random.Random(1)
    failures = 0
    for it in range(count):
        n = rng.randint(1, 10)
        clauses = []
        for _ in range(rng.randint(0, 45)):
            k = rng.randint(1, 4)
            clauses.append([rng.choice([1, -1]) * rng.randint(1, n) for _ in range(k)])
        want = brute_force(n, clauses)
        p = run(clauses, n)
        lines = p.stdout.splitlines()
        if want:
            lits = [int(t) for ln in lines if ln.startswith("v") for t in ln[1:].split()]
            model = {abs(x): x > 0 for x in lits if x}
            ok = (p.returncode == 10 and lines and lines[0] == "s SATISFIABLE" and len(model) == n
                  and all(any(model[abs(l)] == (l > 0) for l in c) for c in clauses))
        else:
            ok = p.returncode == 20 and lines == ["s UNSATISFIABLE"]
        if not ok:
            failures += 1
            print("FAIL", n, clauses, "want", want, "got", p.stdout, p.stderr)
    print(f"{count - failures} of {count} random formulas answered correctly")
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
