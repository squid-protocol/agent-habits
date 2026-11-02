"""One data.json for the agent-habits article: every number the page shows, from the study's own result files.

Reads only results/data/, runs/runs.csv and followups/*/ (when present); never program source text.
Checks itself against the published totals (43 of 52 nearest neighbours) and stops if they differ.
Usage: python3 -I article/build_data.py   (from the repo root or anywhere)
"""
import csv
import json
import re
import statistics as st
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
D = ROOT / "results" / "data"
OUT = Path(__file__).resolve().parent / "data.json"

RX = re.compile(r"(chess|sat)-(c|java|python|rust|cobol)-(claude|codex|haiku|haiku-b|sonnet-b)-r(\d)")
ARM = {"claude": "S", "sonnet-b": "S2", "haiku": "K", "haiku-b": "K2", "codex": "X"}
MODEL = {"S": "sonnet", "S2": "sonnet", "K": "haiku", "K2": "haiku", "X": "codex"}
LANG = {"c": "C", "java": "Java", "python": "Python", "rust": "Rust", "cobol": "COBOL"}


def num(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return None


def read_csv(p):
    with open(p) as f:
        return list(csv.DictReader(f))


# ---------------------------------------------------------------- runs
ledger = {r["run_id"]: r for r in read_csv(ROOT / "runs" / "runs.csv")}
measures = {r["run_id"]: r for r in read_csv(D / "runs_measures.csv")}
runs = []
for rid in sorted(ledger):
    m = RX.fullmatch(rid)
    task, lang, agent, rep = m.group(1), m.group(2), m.group(3), int(m.group(4))
    arm = ARM[agent]
    L, M = ledger[rid], measures.get(rid, {})
    runs.append({
        "id": rid, "task": task, "lang": lang, "cell": f"{task}-{lang}", "arm": arm, "model": MODEL[arm],
        "round": 2 if arm in ("S2", "K2") else 1, "rep": rep,
        "cli": L["cli"], "model_id": L["model"], "active_s": int(L["active_s"]), "nudges": int(L["nudges"] or 0),
        "capped": L["cap_hit"] == "True", "check": L["final_check"],
        "comments": num(M.get("doc_per_code_line")), "documented": num(M.get("funcs_commented_share")),
        "early_exit": num(M.get("early_exit_per_1k")), "while": num(M.get("while_per_1k")),
        "keyword_tokens": num(M.get("keyword_tokens")),
    })
by_id = {r["id"]: r for r in runs}
assert len(runs) == 60, len(runs)

# ---------------------------------------------------------------- structural distances (sfs, structure lens, D16)
dist = {}
for r in read_csv(D / "sfs_structure_pairs.csv"):
    dist[(r["a"], r["b"])] = dist[(r["b"], r["a"])] = float(r["profile_distance"])
measured = sorted({a for a, _ in dist})
# nearest neighbour, exactly as measure/identify_model.py (sat-c-codex-r1 left out there: no function of >= 3 lines)
ids = [i for i in measured if i != "sat-c-codex-r1"]
hits = tot = 0
for i in ids:
    cand = [j for j in ids if j != i and by_id[j]["cell"] == by_id[i]["cell"]]
    near = min(cand, key=lambda j: dist[(i, j)])
    same_possible = any(by_id[j]["model"] == by_id[i]["model"] for j in cand)
    by_id[i]["nearest"] = {"id": near, "d": round(dist[(i, near)], 3), "same": by_id[near]["model"] == by_id[i]["model"],
                           "scored": same_possible,
                           "lineup": sorted(({"id": j, "d": round(dist[(i, j)], 3)} for j in cand), key=lambda x: x["d"])}
    if same_possible:
        tot += 1
        hits += by_id[near]["model"] == by_id[i]["model"]
assert (hits, tot) == (43, 52), (hits, tot)  # the published exploratory result
for rid in by_id:
    by_id[rid]["in_structure"] = rid in ids

ident = [json.loads(x) for x in (D / "identify_model.txt").read_text().splitlines() if x.strip()]
rel = json.loads((D / "relations_d16.json").read_text())["structure_d16"]

# ---------------------------------------------------------------- registered tests -> one scorecard
fam = json.loads((D / "families_d16.json").read_text())["families"]
sens = json.loads((D / "families_sensitivity.json").read_text()) if (D / "families_sensitivity.json").exists() else {}
sec = json.loads((D / "secondary.json").read_text())

# ---------------------------------------------------------------- follow-ups (exploratory), merged per run when present
followups = {}
for fd in sorted((ROOT / "followups").glob("*/")):
    entry = {"slug": fd.name}
    if (fd / "FINDING.md").exists():
        entry["finding_md"] = (fd / "FINDING.md").read_text()
    if (fd / "summary.json").exists():
        entry["summary"] = json.loads((fd / "summary.json").read_text())
    if (fd / "habits.json").exists():
        entry["habits"] = json.loads((fd / "habits.json").read_text())
    if (fd / "per_run.csv").exists():
        rows = read_csv(fd / "per_run.csv")
        cols = [c for c in rows[0] if c not in ("run_id", "arm", "cell", "rep", "task", "lang", "model")] if rows else []
        entry["columns"] = cols
        for r in rows:
            if r.get("run_id") in by_id:
                by_id[r["run_id"]].setdefault("fu", {})[fd.name] = {c: num(r[c]) if num(r[c]) is not None else r[c] for c in cols}
    if (fd / "per_run_edges").is_dir():  # the wiring maps: names and call edges only, copied next to the page
        entry["has_maps"] = True
        wd = OUT.parent / "wiring"
        wd.mkdir(exist_ok=True)
        for p in (fd / "per_run_edges").glob("*.json"):
            (wd / p.name).write_text(p.read_text())
    followups[fd.name] = entry

# ---------------------------------------------------------------- summary numbers the text quotes (computed, never typed)
def med(xs):
    xs = [x for x in xs if x is not None]
    return round(st.median(xs), 1) if xs else None


arm_time = {a: med([r["active_s"] / 60 for r in runs if r["arm"] == a]) for a in ARM.values()}
model_time = {m: med([r["active_s"] / 60 for r in runs if r["model"] == m]) for m in ("sonnet", "haiku", "codex")}
facts = {
    "programs": len(runs),
    "passed": sum(r["check"] == "PASS" for r in runs),  # within the run; the 2 capped runs pass on a later check
    "work_after_recheck": sum(r["check"] == "PASS" for r in runs) + sum(r["capped"] for r in runs),  # RESULTS.md section 1
    "cells": len({r["cell"] for r in runs}),
    "nn_hits": hits, "nn_of": tot, "nn_accuracy": ident[0]["accuracy"], "nn_chance": ident[0]["chance"],
    "nn_p": ident[0]["permutation_p"], "nn_portable": ident[1] if len(ident) > 1 else None,
    "median_minutes_by_arm": arm_time, "median_minutes_by_model": model_time,
    "cap_hits": [r["id"] for r in runs if r["capped"]],
    "failed": [r["id"] for r in runs if r["check"] != "PASS"],
    "comments_median_by_model": {m: round(st.median([r["comments"] for r in runs if r["model"] == m and r["comments"] is not None]), 4)
                                 for m in ("sonnet", "haiku", "codex")},
}

data = {
    "built_from": "agent-habits results/data at the working tree; GitGalaxy engine 7d2e1f627",
    "facts": facts,
    "runs": runs,
    "order": measured,
    "dist": [[round(dist.get((a, b), 0.0), 3) if a != b else 0 for b in measured] for a in measured],
    "groups": rel["groups"], "model_pairs": rel["model_pairs_same_cell"], "per_cell": rel["per_cell_r1"],
    "V2": rel["V2_registered"],
    "families": fam, "sensitivity": sens, "secondary": sec,
    "followups": followups,
    "langs": LANG,
}
OUT.write_text(json.dumps(data, separators=(",", ":")))
print(f"wrote {OUT} ({OUT.stat().st_size // 1024} KB): {len(runs)} runs, nn {hits}/{tot}, "
      f"follow-ups: {', '.join(followups) or 'none yet'}")
