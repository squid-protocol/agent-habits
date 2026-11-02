"""Apply the frozen agent-habits measurement code to the confirmation runs (PREREGISTRATION.md section 7 + D14).

    python adapter.py             # writes runs_measures.csv, families.json, families.md here

No frozen file is edited: each is imported and given only paths and repo lists (D14). Measures per run:
  H1 doc_per_code_line   landscape.profile on the run's scan, cell language only (D14); all-language value beside it
  H2 funcs_commented_share   comments/extract -> classify -> analyze (per_repo.csv)
  H3 early exits per 1,000 keyword tokens: COBOL cells EXIT PARAGRAPH + EXIT PERFORM (exit_kinds.RX); others `return`
  H4 python_helper       >= 1 Python function with loc >= 3 in the run's scan (non-Python cells)
  H5 while per 1,000 keyword tokens (non-COBOL cells)
Families: A S vs X, B K vs X (one-sided, registered directions); C K vs S, D S vs S', E K vs K' (two-sided).
Holm within each family. Cell value = the arm's r1 run.
"""

import collections
import contextlib
import csv
import importlib
import io
import json
import math
import re
import sqlite3
import sys
from pathlib import Path

STUDY = Path("/home/joe/gitgalaxy/chess-study")
CONFIRM = STUDY / "confirm"
HERE = CONFIRM / "measure"
SRC = CONFIRM / "scan_src" / "confirm"
SCANS = CONFIRM / "scans" / "confirm"
sys.path[:0] = [str(STUDY), str(STUDY / "comments")]

import landscape as L  # noqa: E402
import keyword_diff as K  # noqa: E402
import pooled  # noqa: E402

with contextlib.redirect_stdout(io.StringIO()):
    import exit_kinds  # noqa: E402  (its module-level loop prints the exploratory counts; only RX is used)
EXIT_RX = exit_kinds.RX

ARMS = {"claude": "S", "sonnet-b": "S2", "codex": "X", "haiku": "K", "haiku-b": "K2"}
LANG_GG = {"c": "c", "cpp": "cpp", "java": "java", "python": "python", "rust": "rust", "cobol": "cobol"}


MSRC = CONFIRM / "measure_src"  # D15: H2, H3, H5 read this copy


def build_measure_src() -> list[str]:
    """D15: copy each run; rename every extension-less file whose first line is a `#!` naming python to `<name>.py`."""
    import shutil
    renamed = []
    if MSRC.exists():
        shutil.rmtree(MSRC)
    shutil.copytree(SRC, MSRC, ignore=shutil.ignore_patterns(".gitgalaxy", "__pycache__"))
    for p in MSRC.rglob("*"):
        if p.is_file() and not p.suffix:
            try:
                first = p.open("rb").readline(200)
            except OSError:
                continue
            if first.startswith(b"#!") and b"python" in first:
                p.rename(p.with_name(p.name + ".py"))
                renamed.append(str(p.relative_to(MSRC)))
    return renamed


def runs() -> list[dict]:
    out = []
    for d in sorted(SRC.iterdir()):
        m = re.fullmatch(r"(chess|sat)-(c|java|python|rust|cobol)-(claude|codex|haiku|haiku-b|sonnet-b)-r(\d)", d.name)
        if not m:
            raise SystemExit(f"unexpected run dir {d.name}")
        out.append({"run_id": d.name, "task": m[1], "lang": m[2], "agent": m[3], "arm": ARMS[m[3]], "rep": int(m[4]),
                    "cell": f"{m[1]}-{m[2]}"})
    return out


def scan_db(run_id: str) -> Path:
    return next((SCANS / run_id).glob("*_galaxy_master.db"))


def h1(run: dict) -> tuple[float | None, float | None]:
    L.SCANS = SCANS
    keep = set(L.NON_CODE)
    try:
        all_langs = L.profile(run["run_id"])["doc_per_code_line"]
        con = sqlite3.connect(f"file:{scan_db(run['run_id'])}?mode=ro", uri=True)
        langs = {l for (l,) in con.execute("SELECT DISTINCT lower(language) FROM file_data") if l}
        con.close()
        L.NON_CODE = (langs | keep) - {LANG_GG[run["lang"]]}
        cell_only = L.profile(run["run_id"])["doc_per_code_line"]
    finally:
        L.NON_CODE = keep
    return cell_only, all_langs


def h4(run: dict) -> int:
    con = sqlite3.connect(f"file:{scan_db(run['run_id'])}?mode=ro", uri=True)
    n = con.execute("SELECT count(*) FROM function_data f JOIN file_data d ON d.id = f.file_id "
                    "WHERE lower(d.language) = 'python' AND f.loc >= 3").fetchone()[0]
    con.close()
    return int(n > 0)


def keyword_measures(run: dict) -> dict:
    K.ROOTS = [MSRC]  # D15
    lang = run["lang"]
    c = K.counts(run["run_id"], lang)
    total = sum(c.values())
    out = {"keyword_tokens": total, "while_per_1k": None, "return_per_1k": None, "exit_per_1k": None}
    if not total:
        return out
    if lang == "cobol":
        exits = 0
        for p in (MSRC / run["run_id"]).rglob("*"):  # D15
            if p.is_file() and p.suffix.lower() in K.EXT["cobol"] and not (K.SKIP_DIRS & {x.lower() for x in p.parts}):
                t = K.code_only(p.read_text(encoding="utf-8", errors="ignore"), "cobol")
                exits += sum(1 for m in EXIT_RX.finditer(t) if (m.group(1) or "").upper().split()[:1] in (["PARAGRAPH"], ["PERFORM"]))
        out["exit_per_1k"] = round(1000 * exits / total, 3)
    else:
        out["while_per_1k"] = round(1000 * c.get("while", 0) / total, 3)
        out["return_per_1k"] = round(1000 * c.get("return", 0) / total, 3)
    return out


def comments_measures(rs: list[dict]) -> dict:
    """Run the frozen comment pipeline on the runs, outputs redirected to HERE/comments (D14)."""
    out_dir = HERE / "comments"
    out_dir.mkdir(parents=True, exist_ok=True)
    scratch = Path("/tmp/gitgalaxy-scratch/claude/agent-habits-confirm")
    (scratch / "code_only").mkdir(parents=True, exist_ok=True)
    mods = {}
    for name in ("extract", "classify", "analyze"):
        mods[name] = importlib.import_module(name)
        mods[name].OUT = str(out_dir)
        for attr, val in (("TEXT_CACHE", str(scratch / "comment_blocks_text.jsonl")), ("CODE_DIR", str(scratch / "code_only"))):
            if hasattr(mods[name], attr):
                setattr(mods[name], attr, val)
    mods["extract"].REPOS = [(r["cell"], r["lang"], r["arm"], str(MSRC / r["run_id"]), "pair") for r in rs]  # D15
    import time
    t0 = time.time()
    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
        for name in ("extract", "classify"):
            mods[name].main()
        try:
            mods["analyze"].main()
        except ZeroDivisionError:
            # analyze.py's descriptive flag-rate summary hard-codes the exploratory agent names ("claude", "codex",
            # "claude-redo") and divides by zero for the confirmation arms. It runs AFTER per_repo.csv (the only
            # file H2 reads) is written; accept the failure only if per_repo.csv was written in this run.
            if (out_dir / "per_repo.csv").stat().st_mtime < t0:
                raise
    per = {row["repo"]: row for row in csv.DictReader(open(out_dir / "per_repo.csv"))}
    return {r["run_id"]: float(per[r["run_id"]]["funcs_commented_share"]) for r in rs}  # extract keys repos by basename


def one_sided_p(k: int, n: int) -> float:
    return 1.0 if n == 0 else sum(math.comb(n, i) for i in range(k, n + 1)) / 2 ** n


def holm(ps: dict) -> dict:
    order = sorted(ps, key=lambda k: ps[k])
    adj, run_max, m = {}, 0.0, len(ps)
    for i, k in enumerate(order):
        run_max = max(run_max, min(1.0, (m - i) * ps[k]))
        adj[k] = round(run_max, 4)
    return adj


MEASURES = {  # id -> (field, higher_side_is_first_arm_for_directional, cells filter)
    "1": ("doc_per_code_line", True, lambda c: True),
    "2": ("funcs_commented_share", True, lambda c: True),
    "3": ("early_exit_per_1k", False, lambda c: True),
    "4": ("python_helper", False, lambda c: not c.endswith("-python")),
    "5": ("while_per_1k", True, lambda c: not c.endswith("-cobol")),
}


def family(rows: dict, a: str, b: str, directional: bool) -> dict:
    """a, b: arms. Directional: H1, H2, H5 predict a > b; H3, H4 predict b > a (b is Codex in A and B)."""
    res, ps = {}, {}
    cells = sorted({c for (c, arm) in rows if arm == a} & {c for (c, arm) in rows if arm == b})
    for mid, (field, a_higher, keep) in MEASURES.items():
        ahi = bhi = tie = 0
        per = []
        for c in cells:
            if not keep(c):
                continue
            x, y = rows[(c, a)].get(field), rows[(c, b)].get(field)
            if x is None or y is None:
                continue
            per.append((c, x, y))
            if x > y:
                ahi += 1
            elif y > x:
                bhi += 1
            else:
                tie += 1
        if directional:
            k = ahi if a_higher else bhi
            p = one_sided_p(k, ahi + bhi)
        else:
            p = pooled.sign_p(ahi, ahi + bhi)
        ps[mid] = p
        res[mid] = {"measure": field, "cells": len(per), f"{a}_higher": ahi, f"{b}_higher": bhi, "tie": tie,
                    "predicted": (f"{a} > {b}" if a_higher else f"{b} > {a}") if directional else "two-sided",
                    "p": round(p, 4), "per_cell": per}
    for mid, padj in holm(ps).items():
        res[mid]["p_holm"] = padj
    return res


def main() -> None:
    rs = runs()
    print(len(rs), "runs")
    renamed = build_measure_src()
    print(len(renamed), "extension-less Python programs renamed (D15)")
    (HERE / "d15_renamed.txt").write_text("\n".join(renamed) + "\n")
    cm = comments_measures(rs)
    table = []
    for r in rs:
        cell_only, all_langs = h1(r)
        kw = keyword_measures(r)
        row = {**r, "doc_per_code_line": cell_only, "doc_per_code_line_all_langs": all_langs,
               "funcs_commented_share": cm[r["run_id"]], "python_helper": h4(r) if r["lang"] != "python" else None, **kw}
        row["early_exit_per_1k"] = kw["exit_per_1k"] if r["lang"] == "cobol" else kw["return_per_1k"]
        table.append(row)
    cols = ["run_id", "cell", "arm", "rep", "doc_per_code_line", "doc_per_code_line_all_langs", "funcs_commented_share",
            "early_exit_per_1k", "python_helper", "while_per_1k", "keyword_tokens"]
    with open(HERE / "runs_measures.csv", "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(table)
    r1 = {(t["cell"], t["arm"]): t for t in table if t["rep"] == 1}
    fams = {
        "A": ("S", "X", True), "B": ("K", "X", True),
        "C": ("K", "S", False), "D": ("S", "S2", False), "E": ("K", "K2", False),
    }
    out = {name: {"arms": [a, b], "directional": d, "tests": family(r1, a, b, d)} for name, (a, b, d) in fams.items()}
    (HERE / "families.json").write_text(json.dumps(out, indent=1) + "\n")
    lines = []
    for name, f in out.items():
        a, b = f["arms"]
        lines.append(f"## Family {name}: {a} vs {b} ({'one-sided' if f['directional'] else 'two-sided'}, Holm)")
        for mid, t in f["tests"].items():
            lines.append(f"  {name}{mid} {t['measure']:24} cells {t['cells']:2}  {a}>{t[f'{a}_higher']:2}  {b}>{t[f'{b}_higher']:2}  "
                         f"tie {t['tie']}  pred {t['predicted']:9}  p {t['p']:.4f}  holm {t['p_holm']:.4f}")
    (HERE / "families.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
