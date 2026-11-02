"""How different is everyone? sfs profile distances (lower = more alike) between the confirmation runs, grouped by
relationship, for the structure and portable lenses. Registered V2 (two repeat cells, S and X) and its D11 all-cell
version are computed first; the rest is descriptive.

Excluded (D16): chess-c-codex-r1, chess-rust-codex-r1, chess-rust-codex-r2 (no program in the scan) and
sat-c-codex-r1 (0 functions of >= 3 lines after its rescan).
"""

import collections
import csv
import json
import re
import statistics
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODEL = {"claude": "sonnet", "sonnet-b": "sonnet", "codex": "codex", "haiku": "haiku", "haiku-b": "haiku"}
ARM = {"claude": "S", "sonnet-b": "S2", "codex": "X", "haiku": "K", "haiku-b": "K2"}
EXCLUDED = {"sat-c-codex-r1"}  # D16
RX = re.compile(r"(chess|sat)-(c|java|python|rust|cobol)-(claude|codex|haiku|haiku-b|sonnet-b)-r(\d)")


def parse(rid):
    m = RX.fullmatch(rid)
    return {"cell": f"{m[1]}-{m[2]}", "task": m[1], "lang": m[2], "arm": ARM[m[3]], "model": MODEL[m[3]], "rep": int(m[4])}


def load(lens):
    d = {}
    for row in csv.DictReader(open(HERE / lens / "pairs.csv")):
        v = float(row["profile_distance"])
        d[(row["a"], row["b"])] = d[(row["b"], row["a"])] = v
    return d


def stats(xs):
    xs = sorted(xs)
    return {"n": len(xs), "median": round(statistics.median(xs), 3), "mean": round(statistics.mean(xs), 3)} if xs else {"n": 0}


def analyse(lens):
    dist = load(lens)
    ids = sorted({a for a, _ in dist} - EXCLUDED)
    info = {r: parse(r) for r in ids}
    groups = collections.defaultdict(list)
    model_pair_same_cell = collections.defaultdict(list)
    for i, a in enumerate(ids):
        for b in ids[i + 1:]:
            x, y = info[a], info[b]
            v = dist[(a, b)]
            same_cell = x["cell"] == y["cell"]
            same_model = x["model"] == y["model"]
            if same_cell and same_model:
                groups["1 same task+language, same model (another run)"].append(v)
            elif same_cell:
                groups["2 same task+language, different model"].append(v)
                model_pair_same_cell[tuple(sorted((x["model"], y["model"])))].append(v)
            elif same_model and x["lang"] == y["lang"]:
                groups["3 same model + language, other task"].append(v)
            elif same_model and x["task"] == y["task"]:
                groups["4 same model + task, other language"].append(v)
            elif same_model:
                groups["5 same model, other task and language"].append(v)
            else:
                groups["6 different model, other task or language"].append(v)
    out = {"groups": {k: stats(v) for k, v in sorted(groups.items())},
           "model_pairs_same_cell": {f"{a} vs {b}": stats(v) for (a, b), v in sorted(model_pair_same_cell.items())}}
    # Registered V2 (two repeat cells, S and X): median over cells of mean within-agent repeat distance / mean S-X distance.
    v2 = []
    for cell in ("chess-rust", "sat-python"):
        def run(arm, rep):
            rid = next((r for r in ids if info[r]["cell"] == cell and info[r]["arm"] == arm and info[r]["rep"] == rep), None)
            return rid
        within = [dist[(run(arm, 1), run(arm, 2))] for arm in ("S", "X") if run(arm, 1) and run(arm, 2)]
        between = [dist[(run("S", r1), run("X", r2))] for r1 in (1, 2) for r2 in (1, 2) if run("S", r1) and run("X", r2)]
        if within and between:
            v2.append({"cell": cell, "within": round(statistics.mean(within), 3), "between": round(statistics.mean(between), 3),
                       "ratio": round(statistics.mean(within) / statistics.mean(between), 3), "within_pairs": len(within)})
        else:
            v2.append({"cell": cell, "note": "not evaluable: Codex runs excluded (D16)"})
    ratios = [c["ratio"] for c in v2 if "ratio" in c]
    out["V2_registered"] = {"cells": v2, "median_ratio": round(statistics.median(ratios), 3) if ratios else None,
                            "passes_(>=0.85)": (statistics.median(ratios) >= 0.85) if ratios else None,
                            "note": "underpowered by registration (two cells)"}
    # D11 all-cell version: per cell, S-S2 distance vs S-X distance (r1 runs).
    allcell = []
    for cell in sorted({info[r]["cell"] for r in ids}):
        def r1(arm):
            return next((r for r in ids if info[r]["cell"] == cell and info[r]["arm"] == arm and info[r]["rep"] == 1), None)
        s, s2, x, k, k2 = r1("S"), r1("S2"), r1("X"), r1("K"), r1("K2")
        row = {"cell": cell}
        if s and s2:
            row["S-S2"] = round(dist[(s, s2)], 3)
        if k and k2:
            row["K-K2"] = round(dist[(k, k2)], 3)
        if s and x:
            row["S-X"] = round(dist[(s, x)], 3)
        if k and x:
            row["K-X"] = round(dist[(k, x)], 3)
        if s and k:
            row["S-K"] = round(dist[(s, k)], 3)
        allcell.append(row)
    out["per_cell_r1"] = allcell
    ev = [c for c in allcell if "S-S2" in c and "S-X" in c]
    out["D11_V2_allcell"] = {"cells_evaluable": len(ev), "cells_S-S2_<_S-X": sum(c["S-S2"] < c["S-X"] for c in ev)}
    return out


def main():
    res = {lens: analyse(lens) for lens in ("structure_d16",)}
    (HERE / "relations_d16.json").write_text(json.dumps(res, indent=1) + "\n")
    for lens, r in res.items():
        print(f"\n===== {lens} lens: profile distance (lower = more alike)")
        for k, s in r["groups"].items():
            print(f"  {k:48} median {s.get('median')}  mean {s.get('mean')}  n {s['n']}")
        print("  -- model pairs, same task+language:")
        for k, s in r["model_pairs_same_cell"].items():
            print(f"     {k:20} median {s['median']}  n {s['n']}")
        print("  -- registered V2:", json.dumps(r["V2_registered"]))
        print("  -- D11 all-cell V2:", r["D11_V2_allcell"])
        print("  -- per cell (r1):")
        for c in r["per_cell_r1"]:
            print("    ", c)


if __name__ == "__main__":
    main()
