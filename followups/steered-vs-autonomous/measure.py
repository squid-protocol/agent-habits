"""Follow-up (exploratory, not registered): which exploratory habits survived the move from Acher's human-steered
pairs to the autonomous runs. Computes only what no existing results file holds, with the study's own definitions:

1. Steered pairs, secondary measures on the confirmation-engine rescans (scans/explore):
   fan_out_mean, complexity_median (landscape.profile, as secondary.py S1/S2), bitwise_ops per 100 function LOC in
   the cell language (as secondary.py S5). Non-COBOL pairs only, as S1/S2/S5.
2. Autonomous runs, the same three measures for Haiku (K) vs Codex (X), r1 runs, using secondary.py's own
   profile()/bitwise() (D16 scan roots). S vs X is recomputed only to check it matches secondary.json.
3. Steered pairs, the exploratory keyword leans (keywords_confirm.EXPLORATORY_LEANS) counted with keyword_diff
   (code only, cell language) on the original checkouts, as explore_rescan.py does.

    /home/joe/gitgalaxy/venv/bin/python -I measure.py OUT.json   # writes the computed numbers to OUT.json
(habits.json carries them, each with its source)
"""

import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1] / "measure"))

import adapter as A  # noqa: E402
import secondary as SEC  # noqa: E402
import explore_rescan as ER  # noqa: E402
import keywords_confirm as KC  # noqa: E402


def explore_profile(repo):
    A.L.SCANS = ER.EXPLORE_SCANS
    try:
        return A.L.profile(repo)
    finally:
        A.L.SCANS = A.SCANS


def explore_bitwise(repo, lang):
    import sqlite3
    db = next((ER.EXPLORE_SCANS / repo).glob("*_galaxy_master.db"))
    con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    r = con.execute("SELECT sum(f.loc), sum(coalesce(f.bitwise_ops, 0)) FROM function_data f JOIN file_data d ON d.id = f.file_id "
                    "WHERE lower(d.language) = ? AND f.loc >= 3", (lang,)).fetchone()
    con.close()
    return 100.0 * (r[1] or 0) / r[0] if r[0] else None


def count(per, claude_higher_is_habit):
    """per: [(cell, claude, codex)] -> counts; 'agree' = cells leaning the exploratory way."""
    per = [p for p in per if None not in p[1:]]
    c_hi = sum(a > b for _, a, b in per)
    x_hi = sum(b > a for _, a, b in per)
    tie = len(per) - c_hi - x_hi
    return {"claude_higher": c_hi, "codex_higher": x_hi, "tie": tie, "cells": len(per),
            "agree": c_hi if claude_higher_is_habit else x_hi,
            "per_cell": [(c, round(a, 3), round(b, 3)) for c, a, b in per]}


def main():
    out = {}
    # 1. steered secondary
    non_cobol = {c: v for c, v in ER.PAIRS.items() if not c.endswith("cobol")}
    prof = {repo: explore_profile(repo) for pair in non_cobol.values() for repo in pair}
    st = {}
    for name, field, claude_hab in (("fan_out", "fan_out_mean", True), ("complexity", "complexity_median", False)):
        st[name] = count([(c, prof[cc].get(field), prof[cx].get(field)) for c, (cc, cx) in non_cobol.items()], claude_hab)
    st["bitwise"] = count([(c, explore_bitwise(cc, c.split("-")[1]), explore_bitwise(cx, c.split("-")[1]))
                           for c, (cc, cx) in non_cobol.items()], True)
    out["steered_secondary_rescan"] = st

    # 2. autonomous secondary, K vs X (and S vs X as a check against secondary.json)
    rs = A.runs()
    r1 = {(r["cell"], r["arm"]): r["run_id"] for r in rs if r["rep"] == 1}
    cells = sorted({r["cell"] for r in rs if not r["cell"].endswith("cobol")})
    aut = {}
    for arm in ("S", "K"):
        p = {r1[(c, a)]: SEC.profile(r1[(c, a)]) for c in cells for a in (arm, "X")}
        d = {}
        for name, field, claude_hab in (("fan_out", "fan_out_mean", True), ("complexity", "complexity_median", False)):
            d[name] = count([(c, p[r1[(c, arm)]].get(field), p[r1[(c, "X")]].get(field)) for c in cells], claude_hab)
        d["bitwise"] = count([(c, SEC.bitwise(r1[(c, arm)], c.split("-")[1]), SEC.bitwise(r1[(c, "X")], c.split("-")[1]))
                              for c in cells], True)
        aut[arm] = d
    out["autonomous_secondary"] = aut

    # 3. steered keyword leans
    A.K.ROOTS = ER.REPO_ROOTS
    kcounts = {}
    for cell, (cc, cx) in ER.PAIRS.items():
        lang = cell.split("-")[1]
        for arm, repo in (("C", cc), ("X", cx)):
            c = A.K.counts(repo, lang)
            tot = sum(c.values()) or 1
            kcounts[(cell, arm)] = {k: 1000 * v / tot for k, v in c.items()}
    kw = []
    for lang, word, side in KC.EXPLORATORY_LEANS:
        cs = [c for c in ER.PAIRS if (lang == "*" and not c.endswith("cobol")) or c.endswith("-" + lang)]
        per = [(c, kcounts[(c, "C")].get(word, 0.0), kcounts[(c, "X")].get(word, 0.0)) for c in cs]
        kw.append({"lang": lang, "keyword": word, "exploratory_side": side, **count(per, side == "claude")})
    out["steered_keywords"] = kw

    Path(sys.argv[1]).write_text(json.dumps(out, indent=1) + "\n")
    for k, v in st.items():
        print("steered", k, {x: v[x] for x in ("claude_higher", "codex_higher", "tie")})
    for arm, d in aut.items():
        for k, v in d.items():
            print("auton", arm, k, {x: v[x] for x in ("claude_higher", "codex_higher", "tie")})
    for r in kw:
        print("kw", r["lang"], r["keyword"], r["exploratory_side"], {x: r[x] for x in ("claude_higher", "codex_higher", "tie")})


if __name__ == "__main__":
    main()
