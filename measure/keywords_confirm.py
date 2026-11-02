"""Keyword usage across the confirmation arms, with the frozen keyword_diff counting (code only, cell language only,
read from the D15 measurement copy). r1 run per arm per cell.

1. S6 (registered secondary): COBOL cells, X uses CALL more than S; S uses EVALUATE more than X (one-sided sign tests,
   uncorrected, per the registration).
2. Replication check (descriptive): the keyword leans noted in the exploratory pairs (2026-11-01, before any
   confirmation run existed), re-read on the new runs.
3. Discovery (exploratory): per model pair, keywords leaning the same way in all cells where either uses them
   (>= 3 cells), and keywords used (>= 2 times) by one model in a language and never by the other.
"""

import collections
import json
import math

import adapter as A

K = A.K
K.ROOTS = [A.MSRC]

EXPLORATORY_LEANS = [  # (language, keyword, which side used it more in the exploratory pairs: "codex" or "claude")
    ("cobol", "CALL", "codex"), ("cobol", "GOBACK", "codex"), ("cobol", "COMP-5", "codex"), ("cobol", "LINKAGE", "codex"),
    ("cobol", "EXIT", "codex"), ("cobol", "FILLER", "claude"), ("cobol", "REDEFINES", "claude"), ("cobol", "EVALUATE", "claude"),
    ("cobol", "COMPUTE", "claude"), ("cobol", "DISPLAY", "claude"),
    ("rust", "#[inline", "claude"), ("rust", "unsafe", "claude"), ("rust", "static", "claude"),
    ("c", "bool", "claude"), ("c", "extern", "claude"),
    ("java", "throw", "codex"), ("java", "synchronized", "codex"),
    ("python", "@dataclass", "codex"), ("python", "pass", "codex"), ("python", "with", "codex"),
    ("*", "while", "claude"), ("*", "return", "codex"), ("*", "if", "codex"), ("*", "for", "claude"),
]


def one_sided(k, n):
    return 1.0 if n == 0 else sum(math.comb(n, i) for i in range(k, n + 1)) / 2 ** n


def main():
    rs = [r for r in A.runs() if r["rep"] == 1]
    A.build_measure_src()
    counts = {}
    for r in rs:
        c = K.counts(r["run_id"], r["lang"])
        tot = sum(c.values()) or 1
        counts[(r["cell"], r["arm"])] = {k: 1000 * v / tot for k, v in c.items()} | {"__raw__": dict(c), "__tot__": tot}
    cells = sorted({r["cell"] for r in rs})
    model_of = {"S": "sonnet", "S2": "sonnet", "X": "codex", "K": "haiku", "K2": "haiku"}
    out = {}

    # 1. S6
    s6 = {}
    for kw, hi, lo in (("CALL", "X", "S"), ("EVALUATE", "S", "X")):
        per = [(c, round(counts[(c, hi)].get(kw, 0), 2), round(counts[(c, lo)].get(kw, 0), 2)) for c in cells if c.endswith("cobol")]
        k = sum(a > b for _, a, b in per); n = sum(a != b for _, a, b in per)
        s6[f"{hi} uses {kw} more than {lo}"] = {"per_cell": per, "agree": k, "of": n, "p_one_sided": round(one_sided(k, n), 3)}
    out["S6_registered"] = s6

    # 2. replication of the exploratory leans: per model pair (Sonnet/Haiku vs Codex), share of cells leaning the noted way
    rep = []
    for lang, kw, side in EXPLORATORY_LEANS:
        cs = [c for c in cells if lang == "*" and not c.endswith("cobol") or c.endswith("-" + lang)]
        for claude_arm in ("S", "K"):
            agree = against = tie = 0
            for c in cs:
                a, x = counts[(c, claude_arm)].get(kw, 0), counts[(c, "X")].get(kw, 0)
                if a == x:
                    tie += 1
                elif (a > x) == (side == "claude"):
                    agree += 1
                else:
                    against += 1
            rep.append({"lang": lang, "keyword": kw, "exploratory_side": side, "claude_arm": model_of[claude_arm],
                        "cells_agree": agree, "cells_against": against, "tie_or_unused": tie})
    out["replication_of_exploratory_leans"] = rep

    # 3. discovery
    disc = {}
    for a, b in (("S", "X"), ("K", "X"), ("K", "S")):
        consistent, only = [], collections.defaultdict(list)
        langs = sorted({c.split("-")[1] for c in cells})
        for lang in langs:
            cs = [c for c in cells if c.endswith("-" + lang)]
            for side, other in ((a, b), (b, a)):
                used = collections.Counter()
                for c in cs:
                    raw_s, raw_o = counts[(c, side)]["__raw__"], counts[(c, other)]["__raw__"]
                    for kw, n in raw_s.items():
                        if n >= 2 and raw_o.get(kw, 0) == 0:
                            used[kw] += n
                for kw, n in used.most_common(8):
                    only[f"{model_of[side]} only ({lang})"].append(f"{kw}({n})")
        allkw = set()
        for c in cells:
            allkw |= {k for k in counts[(c, a)] if not k.startswith("__")} | {k for k in counts[(c, b)] if not k.startswith("__")}
        for kw in sorted(allkw):
            per = [(c, counts[(c, a)].get(kw, 0), counts[(c, b)].get(kw, 0)) for c in cells]
            per = [p for p in per if p[1] or p[2]]
            hi_a = sum(x > y for _, x, y in per); hi_b = sum(y > x for _, x, y in per)
            if len(per) >= 3 and (hi_a == len(per) or hi_b == len(per)):
                consistent.append({"keyword": kw, "more_in": model_of[a] if hi_a else model_of[b], "cells": len(per),
                                   "p_two_sided": round(min(1, 2 * 0.5 ** len(per)), 4)})
        disc[f"{model_of[a]} vs {model_of[b]}"] = {"consistent_all_cells": sorted(consistent, key=lambda d: -d["cells"]),
                                                   "only_one_side": dict(only)}
    out["discovery_exploratory"] = disc
    (A.HERE / "keywords_confirm.json").write_text(json.dumps(out, indent=1) + "\n")

    print("== S6 (registered secondary, uncorrected)")
    for k, v in s6.items():
        print(f"  {k}: {v['agree']} of {v['of']} cells, p = {v['p_one_sided']}  {v['per_cell']}")
    print("\n== Replication of exploratory keyword leans (cells agreeing / against / tie-or-unused)")
    for r in rep:
        print(f"  {r['lang']:6} {r['keyword']:12} expl: {r['exploratory_side']:6} more | {r['claude_arm']:6} vs codex: "
              f"{r['cells_agree']} agree, {r['cells_against']} against, {r['tie_or_unused']} tie/unused")
    print("\n== Discovery (exploratory; ~150 keywords tested)")
    for pair, d in disc.items():
        print(f"\n-- {pair}: keywords leaning the same way in every cell that uses them (>= 3 cells)")
        for c in d["consistent_all_cells"][:12]:
            print(f"   {c['keyword']:14} more in {c['more_in']:6} {c['cells']} cells  p2 = {c['p_two_sided']}")
        for side, kws in d["only_one_side"].items():
            print(f"   {side}: {', '.join(kws)}")


if __name__ == "__main__":
    main()
