"""EXPLORATORY follow-up (not preregistered): does more time make different code?

Re-runnable: /home/joe/gitgalaxy/venv/bin/python -I measure.py  (writes per_run.csv, summary.json beside this file)

Inputs (read-only):
  runs/runs.csv                         active_s, sessions, nudges, cap_hit, final_check (harness ledger)
  results/data/runs_measures.csv        run_id -> arm / cell / rep
  runs/code/<run>/                      the programs as written (line counts are taken here, scanner-independent)
  validity/definitions.csv              ctags function counts (all 60 runs; GitGalaxy's own count is missing for the
                                        4 dense Codex runs its aperture blocked, so ctags is used throughout)
  <confirm>/runs/<run>/agent-home/      agent transcripts (Claude Code project jsonl incl. subagents; Codex rollout
                                        jsonl): every tool call whose command runs `/check/check chess|sat` is one
                                        self-check (practice checker). The harness also checks once per session.

Size measures (cell-language files only: by extension, or an extension-less file whose #! line names python):
  code_lines     non-blank lines that are not comment-only
  comment_lines  comment-only lines (//, /* */ blocks, #, Python docstring blocks, COBOL *>; all COBOL is -free)
  bytes          bytes of those files (Codex sometimes packs many statements per line, so lines undercount it)
"""
import csv
import json
import math
import re
import statistics as st
from itertools import combinations
from pathlib import Path

from scipy.stats import spearmanr

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
CONFIRM_RUNS = Path("/home/joe/gitgalaxy/chess-study/confirm/runs")
EXT = {"c": {".c", ".h"}, "java": {".java"}, "python": {".py"}, "rust": {".rs"}, "cobol": {".cob", ".cbl", ".cpy"}}
MODEL = {"S": "Sonnet", "S2": "Sonnet", "K": "Haiku", "K2": "Haiku", "X": "Codex"}
CHECK_RE = re.compile(r"/check/check\s+(?:chess|sat)\b")


def cell_files(rid, lang):
    out = []
    for p in sorted((REPO / "runs" / "code" / rid).rglob("*")):
        if not p.is_file() or any(part in {"target", ".git", "__pycache__"} for part in p.parts):
            continue
        if p.suffix in EXT[lang]:
            out.append(p)
        elif p.suffix == "" and lang == "python":
            try:
                first = p.open("rb").readline()
            except OSError:
                continue
            if first.startswith(b"#!") and b"python" in first:
                out.append(p)
    return out


def count_lines(text, lang):
    code = comment = 0
    in_block = False      # /* */ (C-like) or triple-quote docstring (python)
    quote = None
    for raw in text.splitlines():
        s = raw.strip()
        if not s:
            continue
        if lang == "cobol":
            if s.startswith("*>"):  # all programs are built with `cobc -free`: only *> starts a comment
                comment += 1
            else:
                code += 1
            continue
        if lang == "python":
            if in_block:
                comment += 1
                if quote in s:
                    in_block = False
                continue
            if s.startswith("#"):
                comment += 1
                continue
            m = re.match(r'^[rRuUbB]?("""|\'\'\')', s)
            if m:  # a statement that is only a (doc)string
                comment += 1
                q = m.group(1)
                if s.count(q) == 1 or (s == q):
                    in_block, quote = True, q
                continue
            code += 1
            continue
        # C, Java, Rust
        if in_block:
            comment += 1
            if "*/" in s:
                in_block = False
                rest = s.split("*/", 1)[1].strip()
                if rest:
                    comment -= 1
                    code += 1
            continue
        if s.startswith("//"):
            comment += 1
        elif s.startswith("/*"):
            comment += 1
            if "*/" not in s[2:]:
                in_block = True
            elif s.split("*/", 1)[1].strip():
                comment -= 1
                code += 1
        else:
            code += 1
    return code, comment


def transcripts(rid):
    home = CONFIRM_RUNS / rid / "agent-home"
    return sorted(set(home.glob("projects/**/*.jsonl")) | set(home.glob("sessions/**/*.jsonl")))


def tool_calls(rid):
    """(timestamp, command-text) for every tool call in the run's transcripts, plus first event timestamp."""
    calls, first = [], None
    for f in transcripts(rid):
        for line in f.open(errors="ignore"):
            try:
                d = json.loads(line)
            except ValueError:
                continue
            ts = d.get("timestamp")
            if ts and (first is None or ts < first):
                first = ts
            if d.get("type") == "assistant":  # Claude Code
                for c in (d.get("message") or {}).get("content") or []:
                    if isinstance(c, dict) and c.get("type") == "tool_use":
                        calls.append((ts, json.dumps(c.get("input"))))
            p = d.get("payload") if isinstance(d.get("payload"), dict) else {}
            if d.get("type") == "response_item" and p.get("type") in ("custom_tool_call", "function_call", "local_shell_call"):
                calls.append((ts, json.dumps(p.get("input") or p.get("arguments") or p.get("action"))))
    return calls, first


def secs(a, b):
    from datetime import datetime
    f = lambda t: datetime.fromisoformat(t.replace("Z", "+00:00"))
    return (f(b) - f(a)).total_seconds()


def main():
    arms = {r["run_id"]: r for r in csv.DictReader((REPO / "results/data/runs_measures.csv").open())}
    ledger = {r["run_id"]: r for r in csv.DictReader((REPO / "runs/runs.csv").open())}
    ctags = {r["run"]: r for r in csv.DictReader((REPO / "validity/definitions.csv").open()) if r["level"] == "run"}
    rows = []
    for rid, a in sorted(arms.items()):
        L = ledger[rid]
        lang = rid.split("-")[1]
        files = cell_files(rid, lang)
        code = comment = nbytes = 0
        for p in files:
            b = p.read_bytes()
            nbytes += len(b)
            c, m = count_lines(b.decode("utf-8", "ignore"), lang)
            code, comment = code + c, comment + m
        calls, first = tool_calls(rid)
        checks = [ts for ts, cmd in calls if CHECK_RE.search(cmd)]
        active = int(L["active_s"])
        sessions, nudges = int(L["sessions"]), int(L["nudges"])
        checker_runs = len(checks) + sessions  # agent self-checks + one harness check per session
        first_check_s = secs(first, min(checks)) if checks and first else None
        rows.append({
            "run_id": rid, "arm": a["arm"], "model": MODEL[a["arm"]], "cell": a["cell"], "rep": int(a["rep"]),
            "active_s": active, "sessions": sessions, "nudges": nudges, "nudged": nudges > 0,
            "capped": L["cap_hit"] == "True", "passed": L["final_check"] == "PASS",
            "self_checks": len(checks), "checker_runs": checker_runs,
            "s_per_checker_run": round(active / checker_runs, 1),
            "s_to_first_self_check": None if first_check_s is None else round(first_check_s, 1),
            "tool_calls": len(calls),
            "code_lines": code, "comment_lines": comment, "bytes": nbytes, "files": len(files),
            "functions": int(ctags[rid]["ctags_funcs"]),
            "gg_functions": int(ctags[rid]["gg_funcs"]) if ctags[rid]["gg_status"] == "read" else None,
        })
    with (HERE / "per_run.csv").open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)

    med = lambda xs: st.median(xs) if xs else None
    by = lambda key: {k: [r for r in rows if r[key] == k] for k in sorted({r[key] for r in rows})}
    S = {}

    # 1. where the time goes
    S["where_time_goes"] = {arm: {
        "runs": len(rs), "median_active_s": med([r["active_s"] for r in rs]),
        "median_self_checks": med([r["self_checks"] for r in rs]),
        "median_checker_runs": med([r["checker_runs"] for r in rs]),
        "median_s_per_checker_run": med([r["s_per_checker_run"] for r in rs]),
        "median_s_to_first_self_check": med([r["s_to_first_self_check"] for r in rs if r["s_to_first_self_check"] is not None]),
        "runs_never_self_checked": sum(r["self_checks"] == 0 for r in rs),
        "median_tool_calls": med([r["tool_calls"] for r in rs]),
        "median_s_per_tool_call": med([r["active_s"] / r["tool_calls"] for r in rs if r["tool_calls"]]),
        "nudged_runs": sum(r["nudged"] for r in rs), "capped_runs": sum(r["capped"] for r in rs),
        "failed_runs": sum(not r["passed"] for r in rs)} for arm, rs in by("arm").items()}

    # 2a. between models, same cell and same rep: ratio slow/fast
    idx = {(r["cell"], r["arm"], r["rep"]): r for r in rows}
    def ratios(pairs):
        out = {"n_cells": 0}
        res = {k: [] for k in ("active_s", "code_lines", "functions", "comment_lines", "bytes")}
        for x, y in pairs:  # x / y
            for k in res:
                if y[k] and x[k] is not None:
                    res[k].append(x[k] / y[k])
            out["n_cells"] += 1
        for k, v in res.items():
            out[f"median_ratio_{k}"] = round(med(v), 2) if v else None
            out[f"cells_higher_{k}"] = f"{sum(t > 1 for t in v)} of {len(v)}"
        return out
    cells = sorted({r["cell"] for r in rows})
    KS = [(idx[c, k, 1], idx[c, s, 1]) for c in cells for k, s in (("K", "S"), ("K2", "S2"))]
    KX = [(idx[c, k, 1], idx[c, "X", 1]) for c in cells for k in ("K", "K2")]
    XS = [(idx[c, "X", 1], idx[c, s, 1]) for c in cells for s in ("S", "S2")]
    S["between_models_same_cell"] = {"Haiku/Sonnet (K/S and K2/S2, rep 1)": ratios(KS),
                                     "Haiku/Codex (K/X and K2/X, rep 1)": ratios(KX),
                                     "Codex/Sonnet (X/S and X/S2, rep 1)": ratios(XS)}

    # 2b. within a model, same cell: is the slower run the bigger one?
    def slower_bigger(pairs, k):
        bigger = smaller = tie = tie_time = 0
        for x, y in pairs:
            if x["active_s"] == y["active_s"]:
                tie_time += 1
                continue
            slow, fast = (x, y) if x["active_s"] > y["active_s"] else (y, x)
            d = slow[k] - fast[k]
            bigger += d > 0
            smaller += d < 0
            tie += d == 0
        return {"slower_bigger": bigger, "slower_smaller": smaller, "ties": tie, "time_ties": tie_time,
                "binomial_two_sided_p": round(binom_p(bigger, bigger + smaller), 3)}
    main_pairs = {"Sonnet (S r1 vs S2 r1)": [(idx[c, "S", 1], idx[c, "S2", 1]) for c in cells],
                  "Haiku (K r1 vs K2 r1)": [(idx[c, "K", 1], idx[c, "K2", 1]) for c in cells],
                  "Codex (X r1 vs X r2)": [(idx[c, "X", 1], idx[c, "X", 2]) for c in cells if (c, "X", 2) in idx]}
    main_pairs["all three models"] = [p for v in main_pairs.values() for p in v]
    groups = {}
    for r in rows:
        groups.setdefault((r["model"], r["cell"]), []).append(r)
    all_pairs = [p for g in groups.values() for p in combinations(g, 2)]
    S["within_model_same_cell"] = {
        name: {k: slower_bigger(pairs, k) for k in ("code_lines", "functions", "comment_lines", "bytes")} | {"pairs": len(pairs)}
        for name, pairs in main_pairs.items()}
    S["within_model_same_cell"]["sensitivity: every same-model same-cell pair (not independent)"] = {
        k: slower_bigger(all_pairs, k) for k in ("code_lines", "functions", "comment_lines", "bytes")} | {"pairs": len(all_pairs)}
    ok = lambda ps: [(x, y) for x, y in ps if x["passed"] and y["passed"] and not x["capped"] and not y["capped"]]
    S["within_model_same_cell"]["sensitivity: main pairs, passed and uncapped only"] = {
        k: slower_bigger(ok(main_pairs["all three models"]), k) for k in ("code_lines", "functions", "comment_lines")} | {
        "pairs": len(ok(main_pairs["all three models"]))}

    # 3. Spearman: raw, and cell-adjusted (log of value / cell median)
    def rho(rs, k, adjust=False, ref=None):
        if adjust:
            ref = ref or rows  # reference group for the cell medians
            cm = {c: (med([r["active_s"] for r in ref if r["cell"] == c]), med([r[k] for r in ref if r["cell"] == c])) for c in cells}
            xs = [math.log(r["active_s"] / cm[r["cell"]][0]) for r in rs]
            ys = [math.log(max(r[k], 1) / max(cm[r["cell"]][1], 1)) for r in rs]
        else:
            xs, ys = [r["active_s"] for r in rs], [r[k] for r in rs]
        res = spearmanr(xs, ys)
        return {"n": len(rs), "rho": round(float(res.statistic), 2), "p": round(float(res.pvalue), 3)}
    sp = {}
    for k in ("code_lines", "comment_lines", "functions", "bytes"):
        sp[k] = {"overall raw": rho(rows, k), "overall, cell-adjusted": rho(rows, k, True)}
        for arm, rs in by("arm").items():
            sp[k][f"{arm} cell-adjusted"] = rho(rs, k, True)
        for m, rs in by("model").items():
            sp[k][f"{m} (both rounds) cell-adjusted"] = rho(rs, k, True)
            if m != "Codex":  # Codex has one run in 8 of its 10 cells: own-cell deviations would be all zero
                sp[k][f"{m} (both rounds) adjusted to the model's own cell median"] = rho(rs, k, True, rs)
    S["spearman_active_time_vs_size"] = sp
    S["note"] = ("EXPLORATORY, not preregistered. Cell-adjusted = log(value / median of that task+language cell), so "
                 "COBOL-vs-Python size differences do not masquerade as a time effect.")
    (HERE / "summary.json").write_text(json.dumps(S, indent=1) + "\n")
    print(json.dumps(S, indent=1))


def binom_p(k, n):
    if n == 0:
        return 1.0
    pk = [math.comb(n, i) / 2 ** n for i in range(n + 1)]
    return min(1.0, sum(p for p in pk if p <= pk[k] + 1e-12))


if __name__ == "__main__":
    main()
