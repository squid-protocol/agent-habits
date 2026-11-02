"""EXPLORATORY follow-up (not pre-registered): size and shape of each program, compared between models within cells.

Reads the GitGalaxy scan of each run (default scan; for the four D16-flagged Codex runs the D16 rescan when it has
functions). Only files in the cell's language count (build.sh, README, a stray Python fuzz script in a Rust cell are
ignored); test files in the cell language are counted (they are code the agent wrote).
If a scan read no cell-language file (aperture-blocked dense Codex files), size measures fall back to the source
(non-blank lines; these files have no comment lines, D16) and function measures are left empty (run named in
summary.json "excluded_from_function_measures").
Also measured from source: non-whitespace characters, a size that does not depend on how much code is packed per line.

Run: /home/joe/gitgalaxy/venv/bin/python -I measure.py   (writes per_run.csv and summary.json next to this file)
"""
import csv, json, math, sqlite3, statistics
from pathlib import Path

HERE = Path(__file__).resolve().parent
STUDY = Path("/home/joe/nyx_projects/agent-habits")
CONFIRM = Path("/home/joe/gitgalaxy/chess-study/confirm")
SCANS, SCANS_D16, SRC = CONFIRM / "scans/confirm", CONFIRM / "scans/confirm-d16", CONFIRM / "scan_src/confirm"
FLAGGED = {"chess-c-codex-r1", "chess-rust-codex-r1", "chess-rust-codex-r2", "sat-c-codex-r1"}
EXT = {"c": {".c", ".h"}, "java": {".java"}, "python": {".py"}, "rust": {".rs"}, "cobol": {".cob", ".cbl", ".cpy"}}
SIZE = ["code_lines", "n_files", "nonws_chars", "chars_per_line"]
FUNC = ["n_funcs", "median_func_len", "p90_func_len", "median_decisions", "max_decisions", "share_funcs_gt10_decisions"]
MEASURES = SIZE + FUNC


def db_rows(db, lang):
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    files = con.execute("SELECT id, file_path, coding_loc FROM file_data WHERE lower(language)=?", (lang,)).fetchall()
    ids = [f[0] for f in files]
    funcs = con.execute(f"SELECT loc, complexity FROM function_data WHERE file_id IN ({','.join('?' * len(ids))})",
                        ids).fetchall() if ids else []
    con.close()
    return files, funcs


def nonws(path):
    return sum(1 for ch in path.read_text(errors="ignore") if not ch.isspace())


def measure(rid, lang):
    db = SCANS / rid / f"{rid}_galaxy_master.db"
    files, funcs = db_rows(db, lang)
    source = "scan"
    if rid in FLAGGED:
        d16 = SCANS_D16 / rid / f"{rid}_galaxy_master.db"
        f2, fn2 = db_rows(d16, lang)
        if fn2:
            files, funcs, source = f2, fn2, "scan-d16"
    m = {"size_source": source}
    if files:
        paths = [SRC / rid / f[1] for f in files]
        m["code_lines"] = sum(f[2] for f in files)
    else:  # scan read no program file: count from source
        paths = [p for p in (SRC / rid).rglob("*") if p.is_file() and p.suffix in EXT[lang] and ".gitgalaxy" not in p.parts]
        m["code_lines"] = sum(1 for p in paths for ln in p.read_text(errors="ignore").splitlines() if ln.strip())
        m["size_source"] = "source-fallback"
    m["n_files"] = len(paths)
    m["nonws_chars"] = sum(nonws(p) for p in paths)
    m["chars_per_line"] = round(m["nonws_chars"] / m["code_lines"], 1)
    if funcs:
        locs = sorted(f[0] for f in funcs)
        dps = sorted(f[1] for f in funcs)
        m["n_funcs"] = len(funcs)
        m["median_func_len"] = statistics.median(locs)
        m["p90_func_len"] = round(statistics.quantiles(locs, n=10, method="inclusive")[8], 1) if len(locs) > 1 else locs[0]
        m["median_decisions"] = statistics.median(dps)
        m["max_decisions"] = dps[-1]
        m["share_funcs_gt10_decisions"] = round(sum(d > 10 for d in dps) / len(dps), 3)
    else:
        m.update({k: None for k in FUNC})
    return m


def sign_p(a, b):
    n, k = a + b, min(a, b)
    if n == 0:
        return None
    return min(1.0, 2 * sum(math.comb(n, i) for i in range(k + 1)) / 2 ** n)


def rel_diff(a, b):  # symmetric relative difference, |a-b| / mean(a,b)
    if a is None or b is None:
        return None
    return 0.0 if a == b else abs(a - b) / ((a + b) / 2)


def main():
    runs = list(csv.DictReader(open(STUDY / "results/data/runs_measures.csv")))
    rows = []
    for r in runs:
        lang = r["cell"].split("-")[1]
        rows.append({"run_id": r["run_id"], "arm": r["arm"], "cell": r["cell"], "rep": int(r["rep"]), **measure(r["run_id"], lang)})
    rows.sort(key=lambda x: (x["cell"], x["arm"], x["rep"]))
    with open(HERE / "per_run.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["run_id", "arm", "cell", "rep", *MEASURES, "size_source"])
        w.writeheader()
        w.writerows(rows)

    cells = sorted({r["cell"] for r in rows})
    by = {(r["cell"], r["arm"], r["rep"]): r for r in rows}

    def pair(a, b):
        out = {}
        for m in MEASURES:
            ah = bh = ties = na = 0
            for c in cells:
                x, y = by[(c, a, 1)][m], by[(c, b, 1)][m]
                if x is None or y is None:
                    na += 1
                elif x > y:
                    ah += 1
                elif y > x:
                    bh += 1
                else:
                    ties += 1
            out[m] = {f"{a} higher": ah, f"{b} higher": bh, "ties": ties, "missing": na, "sign_p_two_sided": sign_p(ah, bh)}
        return out

    pairs = {f"{a} vs {b}": pair(a, b) for a, b in
             [("S", "X"), ("K", "X"), ("K", "S"), ("S2", "X"), ("K2", "X"), ("K2", "S2")]}

    arm_medians = {}
    for arm in ["S", "S2", "K", "K2", "X"]:
        arm_medians[arm] = {m: statistics.median(v) if (v := [by[(c, arm, 1)][m] for c in cells if by[(c, arm, 1)][m] is not None]) else None
                            for m in MEASURES}

    within_between = {}
    for m in MEASURES:
        within = [d for c in cells for a, b in [("S", "S2"), ("K", "K2")] if (d := rel_diff(by[(c, a, 1)][m], by[(c, b, 1)][m])) is not None]
        between = [d for c in cells for a, b in [("S", "X"), ("K", "X"), ("K", "S")] if (d := rel_diff(by[(c, a, 1)][m], by[(c, b, 1)][m])) is not None]
        rep2 = [d for c in cells for arm in ["S", "S2", "K", "K2", "X"] if (c, arm, 2) in by
                if (d := rel_diff(by[(c, arm, 1)][m], by[(c, arm, 2)][m])) is not None]
        mw, mb = statistics.median(within), statistics.median(between)
        within_between[m] = {"median_rel_diff_same_model_S_S2_K_K2": round(mw, 3), "n_within": len(within),
                             "median_rel_diff_between_models_round1": round(mb, 3), "n_between": len(between),
                             "ratio_within_over_between": round(mw / mb, 2) if mb else None,
                             "median_rel_diff_same_model_same_round_r1_vs_r2": round(statistics.median(rep2), 3) if rep2 else None,
                             "n_r1_vs_r2": len(rep2)}

    summary = {
        "status": "EXPLORATORY, not pre-registered; 10 cells; many comparisons (10 measures x 6 pairs); single counts are hypotheses",
        "notes": ["rel_diff = |a-b| / mean(a,b), per cell", "pair counts use rep 1 only; S2/K2 vs X reuse the same X runs",
                  "arm medians are across cells and mix languages/tasks",
                  "code_lines is line-based and depends on how densely code is packed; nonws_chars does not"],
        "excluded_from_function_measures": [r["run_id"] for r in rows if r["n_funcs"] is None],
        "size_from_source_fallback": [r["run_id"] for r in rows if r["size_source"] == "source-fallback"],
        "used_d16_rescan": [r["run_id"] for r in rows if r["size_source"] == "scan-d16"],
        "arm_medians_round1_rep1": arm_medians,
        "pair_counts_within_cells": pairs,
        "within_vs_between_model": within_between,
    }
    json.dump(summary, open(HERE / "summary.json", "w"), indent=1)


if __name__ == "__main__":
    main()
