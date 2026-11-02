#!/usr/bin/env python3
"""Differential test: compare ./solver against brute force on random small CNF formulas.

usage: python3 tests/fuzz.py [iterations] [seed]
Checks: SAT answers come with a valid model (all variables listed, exit 10);
UNSAT answers agree with exhaustive search (exit 20).
"""
import itertools
import os
import random
import subprocess
import sys
import tempfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SOLVER = os.environ.get("SOLVER", os.path.join(ROOT, "solver"))


def brute_sat(n, clauses):
    for bits in range(1 << n):
        if all(any(((bits >> (abs(l) - 1)) & 1) == (l > 0) for l in c) for c in clauses):
            return True
    return False


def random_formula(rng):
    n = rng.randint(1, 14)
    m = rng.randint(0, 6 * n)
    k_max = min(4, n)
    clauses = []
    for _ in range(m):
        k = rng.randint(1, k_max)
        vs = rng.sample(range(1, n + 1), k)
        clauses.append([v if rng.random() < 0.5 else -v for v in vs])
    return n, clauses


def main():
    iters = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    rng = random.Random(seed)
    sat = unsat = 0
    with tempfile.TemporaryDirectory() as td:
        path = os.path.join(td, "f.cnf")
        for it in range(iters):
            n, clauses = random_formula(rng)
            with open(path, "w") as f:
                f.write(f"c fuzz {it}\np cnf {n} {len(clauses)}\n")
                for c in clauses:
                    f.write(" ".join(map(str, c)) + " 0\n")
            want = brute_sat(n, clauses)
            p = subprocess.run([SOLVER, path], capture_output=True, text=True, timeout=20)
            lines = [ln.strip() for ln in p.stdout.splitlines()]
            if want:
                lits = [int(t) for ln in lines if ln.startswith("v") for t in ln[1:].split()]
                ok = (p.returncode == 10 and "s SATISFIABLE" in lines and lits and lits[-1] == 0)
                model = {abs(x): x > 0 for x in lits if x}
                ok = ok and all(v in model for v in range(1, n + 1))
                ok = ok and all(any(model.get(abs(l)) == (l > 0) for l in c) for c in clauses)
                sat += 1
            else:
                ok = p.returncode == 20 and "s UNSATISFIABLE" in lines
                unsat += 1
            if not ok:
                print(f"MISMATCH at iteration {it}: want {'SAT' if want else 'UNSAT'}, "
                      f"exit {p.returncode}, output:\n{p.stdout}\n{p.stderr}")
                print(f"formula kept at {path}")
                os.system(f"cp {path} /tmp/fuzz_fail.cnf")
                return 1
    print(f"ok: {iters} formulas ({sat} SAT, {unsat} UNSAT) agree with brute force")
    return 0


if __name__ == "__main__":
    sys.exit(main())
