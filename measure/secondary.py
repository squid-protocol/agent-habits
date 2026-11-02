"""Registered secondary tests S1-S5 (uncorrected one-sided sign tests, S vs X, r1 runs) and V1, on the frozen code.

S1 non-COBOL: S fan_out_mean > X      (landscape.profile; D16: blocked Codex runs from the wrapped scans)
S2 non-COBOL: X complexity_median > S (same)
S3 COBOL: S1 and S2 do NOT hold (reversed or tied in at least half the COBOL cells)
S4 S's comments name more of the techniques its code implements: per run, named / implemented, where
   "implemented" = identifier hits in comment-stripped code (techcheck's automatic signal; the exploratory set's
   hand confirmation is not repeated for 60 runs: labelled automatic)
S5 non-COBOL: S bitwise_ops per 100 function LOC > X (cell language functions, as signal_diff_lang)
V1 comment volume a stable trait: per repeat cell, (mean S - mean X) / pooled within-agent SD > 1 in both cells;
   D11 all-cell version: |S - X| > |S - S2| per cell, counted.
"""

import csv
import contextlib
import importlib
import io
import json
import math
import sqlite3
import statistics
from pathlib import Path

import adapter as A

WRAPPED = A.CONFIRM / "scans" / "confirm-wrapped"
D16 = A.CONFIRM / "scans" / "confirm-d16"
STILL_BLOCKED = {"chess-c-codex-r1", "chess-rust-codex-r1", "chess-rust-codex-r2"}


def scan_root(rid):
    if rid in STILL_BLOCKED:
        return WRAPPED
    if rid == "sat-c-codex-r1":
        return D16
    return A.SCANS


def profile(rid):
    A.L.SCANS = scan_root(rid)
    try:
        return A.L.profile(rid)
    finally:
        A.L.SCANS = A.SCANS


def bitwise(rid, lang):
    db = next((scan_root(rid) / rid).glob("*_galaxy_master.db"))
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    r = con.execute("SELECT sum(f.loc), sum(coalesce(f.bitwise_ops, 0)) FROM function_data f JOIN file_data d ON d.id = f.file_id "
                    "WHERE lower(d.language) = ? AND f.loc >= 3", (lang,)).fetchone()
    con.close()
    return 100.0 * (r[1] or 0) / r[0] if r[0] else None


def technique_share(rs):
    """S4: the frozen pipeline (extract -> classify -> techcheck) on the S and X r1 runs only, in its own output dir,
    with the agent field set to the names techcheck's summary hard-codes ("claude" = S, "codex" = X)."""
    out_dir = A.HERE / "comments_s4"
    out_dir.mkdir(parents=True, exist_ok=True)
    code_dir = Path("/tmp/gitgalaxy-scratch/claude/agent-habits-confirm/code_only_s4")
    code_dir.mkdir(parents=True, exist_ok=True)
    mods = {n: importlib.import_module(n) for n in ("extract", "classify", "techcheck")}
    for m in mods.values():
        m.OUT = str(out_dir)
        if hasattr(m, "CODE_DIR"):
            m.CODE_DIR = str(code_dir)
        if hasattr(m, "TEXT_CACHE"):
            m.TEXT_CACHE = str(code_dir.parent / "comment_blocks_text_s4.jsonl")
    name = {"S": "claude", "X": "codex"}
    mods["extract"].REPOS = [(r["cell"], r["lang"], name[r["arm"]], str(A.MSRC / r["run_id"]), "pair")
                             for r in rs if r["rep"] == 1 and r["arm"] in name]
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        for n in ("extract", "classify", "techcheck"):
            mods[n].main()
    per = {}
    inv = {"claude": "S", "codex": "X"}
    for r in csv.DictReader(open(out_dir / "technique_presence.csv")):
        key = (r["pair"], inv[r["agent"]])
        d = per.setdefault(key, {"named": 0, "impl": 0})
        implemented = int(r.get("code_identifier_hits") or 0) > 0
        if implemented:
            d["impl"] += 1
            if int(r.get("named_in_comments") or 0) > 0:
                d["named"] += 1
    return {k: (v["named"] / v["impl"] if v["impl"] else None) for k, v in per.items()}


def one_sided(k, n):
    return 1.0 if n == 0 else sum(math.comb(n, i) for i in range(k, n + 1)) / 2 ** n


def sign(per, a_higher):
    k = sum((x > y) if a_higher else (y > x) for _, x, y in per)
    n = sum(x != y for _, x, y in per)
    return {"agree": k, "of": n, "p_one_sided": round(one_sided(k, n), 4), "per_cell": [(c, round(x, 3), round(y, 3)) for c, x, y in per]}


def main():
    rs = A.runs()
    r1 = {(r["cell"], r["arm"]): r for r in rs if r["rep"] == 1}
    cells = sorted({r["cell"] for r in rs})
    prof = {r["run_id"]: profile(r["run_id"]) for r in rs if r["arm"] in ("S", "X")}
    out = {}
    for sid, field, s_higher, keep in (("S1", "fan_out_mean", True, lambda c: not c.endswith("cobol")),
                                       ("S2", "complexity_median", False, lambda c: not c.endswith("cobol"))):
        per = [(c, prof[r1[(c, "S")]["run_id"]].get(field), prof[r1[(c, "X")]["run_id"]].get(field)) for c in cells if keep(c)]
        out[sid] = {"measure": field, **sign([p for p in per if None not in p], s_higher)}
    cob = []
    for c in cells:
        if not c.endswith("cobol"):
            continue
        s, x = prof[r1[(c, "S")]["run_id"]], prof[r1[(c, "X")]["run_id"]]
        holds1 = (s.get("fan_out_mean") or 0) > (x.get("fan_out_mean") or 0)
        holds2 = (x.get("complexity_median") or 0) > (s.get("complexity_median") or 0)
        cob.append({"cell": c, "S1_holds": holds1, "S2_holds": holds2})
    n_not = sum((not d["S1_holds"]) and (not d["S2_holds"]) for d in cob)
    out["S3"] = {"cells": cob, "cells_where_neither_holds": n_not, "of": len(cob), "supported": n_not >= len(cob) / 2}
    tech = technique_share(rs)
    per = [(c, tech.get((c, "S")), tech.get((c, "X"))) for c in cells]
    out["S4"] = {"measure": "named / implemented (automatic)", **sign([p for p in per if None not in p], True)}
    per = [(c, bitwise(r1[(c, "S")]["run_id"], c.split("-")[1]), bitwise(r1[(c, "X")]["run_id"], c.split("-")[1])) for c in cells if not c.endswith("cobol")]
    out["S5"] = {"measure": "bitwise_ops per 100 function LOC", **sign([p for p in per if None not in p], True)}
    # V1 on H1 (D16 values)
    d16 = json.loads((A.HERE / "families_d16.json").read_text())["d16_notes"]
    h1 = {}
    for row in csv.DictReader(open(A.HERE / "runs_measures.csv")):
        v = d16[row["run_id"]]["doc_per_code_line"] if row["run_id"] in d16 else (float(row["doc_per_code_line"]) if row["doc_per_code_line"] else None)
        h1[row["run_id"]] = v
    v1 = []
    for c in ("chess-rust", "sat-python"):
        s = [h1[r["run_id"]] for r in rs if r["cell"] == c and r["arm"] == "S"]
        x = [h1[r["run_id"]] for r in rs if r["cell"] == c and r["arm"] == "X"]
        if len(s) >= 2 and len(x) >= 2 and None not in s + x:
            sd = math.sqrt((statistics.variance(s) + statistics.variance(x)) / 2)
            gap = statistics.mean(s) - statistics.mean(x)
            v1.append({"cell": c, "S": s, "X": x, "gap": round(gap, 4), "pooled_sd": round(sd, 4),
                       "ratio": round(gap / sd, 2) if sd else None, "passes": (sd == 0 and gap > 0) or (bool(sd) and gap / sd > 1)})
    out["V1_registered"] = {"cells": v1, "passes_both": all(d["passes"] for d in v1) if v1 else None, "note": "underpowered (two cells)"}
    allc = []
    for c in cells:
        s, s2, x = (h1.get(r1[(c, a)]["run_id"]) if (c, a) in r1 else None for a in ("S", "S2", "X"))
        if None not in (s, s2, x):
            allc.append({"cell": c, "S-X": round(abs(s - x), 4), "S-S2": round(abs(s - s2), 4), "gap_exceeds_noise": abs(s - x) > abs(s - s2)})
    out["V1_allcell_D11"] = {"cells": allc, "count": sum(d["gap_exceeds_noise"] for d in allc), "of": len(allc)}
    (A.HERE / "secondary.json").write_text(json.dumps(out, indent=1, default=str) + "\n")
    for k in ("S1", "S2", "S4", "S5"):
        print(f"{k} {out[k]['measure']}: {out[k]['agree']} of {out[k]['of']} cells, p = {out[k]['p_one_sided']}")
    print("S3:", out["S3"]["cells_where_neither_holds"], "of", out["S3"]["of"], "COBOL cells where neither holds; supported =", out["S3"]["supported"], out["S3"]["cells"])
    print("V1 registered:", json.dumps(out["V1_registered"]))
    print("V1 all-cell:", out["V1_allcell_D11"]["count"], "of", out["V1_allcell_D11"]["of"])


if __name__ == "__main__":
    main()
