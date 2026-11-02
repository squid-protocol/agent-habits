"""Registered sensitivity analysis (section 4): every family re-run WITHOUT the runs whose harness check ended FAIL
(the primary analysis keeps them). Uses the D16 primary values (families_d16.json's H1 fills).
Failed runs (runs.csv final_check): chess-cobol-codex-r1 (cap), sat-c-codex-r1 (too slow), chess-c-haiku-b-r1 (cap).
A cell whose r1 run of an arm failed drops out of that arm's comparisons.
"""

import csv
import json

import adapter as A

FAILED = {r["run_id"] for r in csv.DictReader(open(A.CONFIRM / "runs.csv")) if r["final_check"] != "PASS"}


def main() -> None:
    d16 = json.loads((A.HERE / "families_d16.json").read_text())["d16_notes"]
    rows = []
    for r in csv.DictReader(open(A.HERE / "runs_measures.csv")):
        if r["run_id"] in FAILED:
            continue
        t = dict(r)
        if r["run_id"] in d16:
            t["doc_per_code_line"] = d16[r["run_id"]]["doc_per_code_line"]
        for k in ("doc_per_code_line", "funcs_commented_share", "early_exit_per_1k", "while_per_1k", "python_helper"):
            t[k] = None if t[k] in ("", None) else float(t[k])
        t["rep"] = int(t["rep"])
        rows.append(t)
    r1 = {(t["cell"], t["arm"]): t for t in rows if t["rep"] == 1}
    fams = {"A": ("S", "X", True), "B": ("K", "X", True), "C": ("K", "S", False), "D": ("S", "S2", False), "E": ("K", "K2", False)}
    out = {"excluded_failed_runs": sorted(FAILED),
           "families": {n: {"arms": [a, b], "directional": d, "tests": A.family(r1, a, b, d)} for n, (a, b, d) in fams.items()}}
    (A.HERE / "families_sensitivity.json").write_text(json.dumps(out, indent=1) + "\n")
    print("excluded:", sorted(FAILED))
    for name, f in out["families"].items():
        a, b = f["arms"]
        for mid, t in f["tests"].items():
            print(f"  {name}{mid} {t['measure']:24} cells {t['cells']:2}  {a}>{t[f'{a}_higher']:2}  {b}>{t[f'{b}_higher']:2}  "
                  f"p {t['p']:.4f}  holm {t['p_holm']:.4f}")


if __name__ == "__main__":
    main()
