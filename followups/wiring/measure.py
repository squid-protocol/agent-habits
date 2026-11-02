"""EXPLORATORY follow-up (not registered): how each program's functions call each other ("wiring"), by model.

    /home/joe/gitgalaxy/venv/bin/python -I measure.py

Reads the GitGalaxy scans of the 60 confirmation runs (read-only) and writes, next to this file:
  per_run.csv, summary.json, per_run_edges/<run_id>.json

Scan used per run: the same roots as registered S1 (measure/secondary.py): the three Codex programs whose
original and D16 scans hold no functions use the formatter-wrapped rescans (confirm-wrapped); sat-c-codex-r1 uses
confirm-d16; every other run uses the original scan. Runs with no functions in any scan are left out and named.

Graph, per run:
  nodes  every function GitGalaxy found in a file of the cell's language (all sizes).
  edges  distinct caller -> callee pairs. A callee name (function_data.calls_out_to, one entry per distinct name a
         function calls) is internal when it names a node of the program (case-insensitive in COBOL); a name shared
         by several nodes links to each of them. A COBOL CALL of a program name links to that program's first
         paragraph. A call of a class name (constructor) links to its __init__ / same-named constructor if there is
         one, otherwise it is counted as "constructor, no body" and left out. Self-calls (recursion) are not edges.
         Every other name is "outside the program" (library, built-in, method of a library type, nested closure).
  The scanner's own resolved edges (fcall_data, dst_func_id) give a second, stricter graph; hub share is reported
  for it too as a sensitivity check (it misses many method calls, e.g. Rust `self.make()`).
Measures:
  functions, edges, fanout_mean = edges / functions,
  hub3_share = share of all edges that go into the 3 most-called functions; hub3_null = the same share expected if
    each caller's calls went to random other functions (500 seeded shuffles, out-degrees kept), the size control;
    hub3_excess = hub3_share - hub3_null,
  indeg_gini, depth = functions on the longest call chain from an entry (cycles collapsed to one step),
  never_called_share = share of non-entry functions no other function calls,
  outside_share = outside names / all callee names.
Entries: main, functions called from module level, test functions, and in COBOL each program's first paragraph (plus
empty SECTION headers falling through to the first paragraph that calls anything). GO TO (transfer) is not a call.
Runtime hooks (Python dunders; Java toString/equals/hashCode/compareTo/run/...; Rust fmt/cmp/eq/default/...) are not
counted as "never called", but are not chain roots.
"""

import csv
import json
import math
import random
import sqlite3
import statistics
from pathlib import Path

HERE = Path(__file__).resolve().parent
STUDY = HERE.parents[1]
SCANS = Path("/home/joe/gitgalaxy/chess-study/confirm/scans")
ROOT = {"chess-c-codex-r1": "confirm-wrapped", "chess-rust-codex-r1": "confirm-wrapped",
        "chess-rust-codex-r2": "confirm-wrapped", "sat-c-codex-r1": "confirm-d16"}
HOOKS = {"tostring", "equals", "hashcode", "compareto", "compare", "run", "call", "iterator", "close",
         "fmt", "cmp", "partial_cmp", "eq", "ne", "hash", "drop", "default", "from", "clone", "next", "deref",
         "index", "index_mut"}
MEASURES = ["functions", "edges", "fanout_mean", "hub3_share", "hub3_null", "hub3_excess", "indeg_gini", "depth",
            "never_called_share", "outside_share"]
PAIRS = [("X", "S"), ("X", "K"), ("S", "K")]
REPL = [("X", "S2"), ("X", "K2"), ("S2", "K2")]


def scan(rid):
    order = [ROOT[rid], "confirm"] if rid in ROOT else ["confirm"]
    for d in order + ["confirm-d16", "confirm-wrapped"]:
        dbs = list((SCANS / d / rid).glob("*_galaxy_master.db"))
        if dbs:
            con = sqlite3.connect(f"file:{dbs[0]}?mode=ro", uri=True)
            if con.execute("SELECT count(*) FROM function_data").fetchone()[0]:
                return d, con
            con.close()
    return None, None


def gini(xs):
    xs = sorted(xs)
    n, s = len(xs), sum(xs)
    if not n or not s:
        return 0.0
    return sum((2 * i - n + 1) * x for i, x in enumerate(xs)) / (n * s)


def hub3(indeg, m):
    return sum(sorted(indeg, reverse=True)[:3]) / m if m else None


def hub3_null(nodes, edges, reps=500, seed=7):
    """Expected top-3 share if each function kept its number of distinct callees but chose them at random."""
    if not edges:
        return None
    outd = {}
    for s, _ in edges:
        outd[s] = outd.get(s, 0) + 1
    rng = random.Random(seed)
    ids = list(nodes)
    vals = []
    for _ in range(reps):
        ind = dict.fromkeys(ids, 0)
        for s, k in outd.items():
            for t in rng.sample([i for i in ids if i != s], min(k, len(ids) - 1)):
                ind[t] += 1
        vals.append(hub3(ind.values(), len(edges)))
    return statistics.mean(vals)


def depth(nodes, edges, roots):
    """Longest chain (in functions) from a root, each strongly connected group counted once (Tarjan, iterative)."""
    adj = {n: [] for n in nodes}
    for s, t in edges:
        adj[s].append(t)
    index, low, comp, stack, on, c, cnt = {}, {}, {}, [], set(), 0, 0
    for v0 in nodes:
        if v0 in index:
            continue
        work = [(v0, 0)]
        while work:
            v, i = work.pop()
            if i == 0:
                index[v] = low[v] = c
                c += 1
                stack.append(v)
                on.add(v)
            if i < len(adj[v]):
                work.append((v, i + 1))
                w = adj[v][i]
                if w not in index:
                    work.append((w, 0))
                elif w in on:
                    low[v] = min(low[v], index[w])
                continue
            for w in adj[v]:
                if w in on:
                    low[v] = min(low[v], low[w])
            if low[v] == index[v]:
                while True:
                    w = stack.pop()
                    on.discard(w)
                    comp[w] = cnt
                    if w == v:
                        break
                cnt += 1
    cadj = {i: set() for i in range(cnt)}
    for s, t in edges:
        if comp[s] != comp[t]:
            cadj[comp[s]].add(comp[t])
    memo = {}
    for k in range(cnt):  # Tarjan numbers components in reverse topological order: callees first
        memo[k] = 1 + max((memo[j] for j in cadj[k]), default=0)
    return max((memo[comp[r]] for r in roots), default=None)


def graph(rid, lang):
    root, con = scan(rid)
    if con is None:
        return None
    q = ("SELECT f.id, f.func_name, f.loc, f.parent_class_id, f.start_line, f.file_id, f.calls_out_to, d.file_path "
         "FROM function_data f JOIN file_data d ON d.id = f.file_id WHERE lower(d.language) = ?")
    rows = con.execute(q, (lang,)).fetchall()
    if not rows:
        con.close()
        return None
    norm = (lambda s: (s or "").upper()) if lang == "cobol" else (lambda s: s or "")
    nodes = {r[0]: {"name": r[1], "loc": r[2]} for r in rows}
    byname = {}
    for r in rows:
        byname.setdefault(norm(r[1]), []).append(r[0])
    classes = {cid: name for cid, name in con.execute("SELECT id, class_name FROM class_data")}
    cls_target = {}
    for cid, cname in classes.items():
        members = [r for r in rows if r[3] == cid]
        if lang == "cobol":
            if members:
                cls_target[norm(cname)] = [min(members, key=lambda r: (r[5], r[4] or 0))[0]]
        else:
            ctor = [r[0] for r in members if r[1] in ("__init__", cname)]
            cls_target.setdefault(norm(cname), [])
            cls_target[norm(cname)] += ctor
    edges, n_names, n_out, n_ctor = set(), 0, 0, 0
    for r in rows:
        for callee in json.loads(r[6] or "[]"):
            n_names += 1
            k = norm(callee)
            if k in byname:
                for t in byname[k]:
                    if t != r[0]:
                        edges.add((r[0], t))
            elif k in cls_target:
                if cls_target[k]:
                    for t in cls_target[k]:
                        if t != r[0]:
                            edges.add((r[0], t))
                else:
                    n_ctor += 1
            else:
                n_out += 1
    strict = {(s, t) for s, t in con.execute("SELECT src_func_id, dst_func_id FROM fcall_data WHERE src_func_id IS NOT NULL "
                                            "AND dst_func_id IS NOT NULL") if s in nodes and t in nodes and s != t}
    glob = {t for (t,) in con.execute("SELECT dst_func_id FROM fcall_data WHERE src_func_id IS NULL AND dst_func_id IS NOT NULL")}
    con.close()
    entries = {i for i, n in nodes.items() if n["name"].lower() in ("main", "__main__") or n["name"].lower().startswith("test")}
    entries |= glob & set(nodes)
    entries |= {r[0] for r in rows if "test" in (r[7] or "").lower()}
    if lang == "cobol":
        # each program's first paragraph, plus the empty headers (SECTION lines) it falls through to reach the first
        # paragraph that calls anything
        progs = {}
        for r in rows:
            progs.setdefault((r[5], r[3]), []).append(r)
        for members in progs.values():
            for r in sorted(members, key=lambda r: r[4] or 0):
                entries.add(r[0])
                if json.loads(r[6] or "[]"):
                    break
    hooks = {i for i, n in nodes.items() if n["name"].lower() in HOOKS or (n["name"].startswith("__") and n["name"].endswith("__"))}
    return root, nodes, sorted(edges), strict, entries, hooks, n_names, n_out, n_ctor


def measure(rid, lang):
    g = graph(rid, lang)
    if g is None:
        return None, None
    root, nodes, edges, strict, entries, hooks, n_names, n_out, n_ctor = g
    indeg = dict.fromkeys(nodes, 0)
    outdeg = dict.fromkeys(nodes, 0)
    for s, t in edges:
        indeg[t] += 1
        outdeg[s] += 1
    sin = dict.fromkeys(nodes, 0)
    for _, t in strict:
        sin[t] += 1
    n, m = len(nodes), len(edges)
    roots = entries or {i for i in nodes if indeg[i] == 0}
    cand = [i for i in nodes if i not in entries and i not in hooks]
    null = hub3_null(nodes, edges)
    h3 = hub3(indeg.values(), m)
    top = sorted(nodes, key=lambda i: -indeg[i])[:3]
    row = {"scan": root, "functions": n, "edges": m, "fanout_mean": round(m / n, 3),
           "hub3_share": round(h3, 4) if h3 is not None else None,
           "hub3_null": round(null, 4) if null is not None else None,
           "hub3_excess": round(h3 - null, 4) if null is not None else None,
           "indeg_gini": round(gini(list(indeg.values())), 4),
           "depth": depth(list(nodes), edges, roots),
           "never_called_share": round(sum(indeg[i] == 0 for i in cand) / len(cand), 4) if cand else None,
           "outside_share": round(n_out / n_names, 4) if n_names else None,
           "callee_names": n_names, "outside_names": n_out, "ctor_no_body": n_ctor, "entries": len(entries),
           "roots_fallback": int(not entries),
           "strict_edges": len(strict), "strict_hub3_share": round(hub3(sin.values(), len(strict)), 4) if strict else None,
           "top3": "; ".join(f"{nodes[i]['name']}({indeg[i]})" for i in top)}
    js = {"nodes": [{"id": i, "name": v["name"], "loc": v["loc"], "in": indeg[i], "out": outdeg[i], "entry": i in entries}
                    for i, v in nodes.items()], "edges": [[s, t] for s, t in edges]}
    return row, js


def p_two_sided(k, n):
    if n == 0:
        return None
    lo = min(k, n - k)
    return min(1.0, 2 * sum(math.comb(n, i) for i in range(lo + 1)) / 2 ** n)


def compare(val, cells, a, b, meas):
    out = {}
    for mname in meas:
        ah = bh = ti = 0
        per = []
        for c in cells:
            x, y = val.get((c, a), {}).get(mname), val.get((c, b), {}).get(mname)
            if x is None or y is None:
                continue
            per.append([c, x, y])
            if x > y:
                ah += 1
            elif y > x:
                bh += 1
            else:
                ti += 1
        out[mname] = {f"{a}_higher": ah, f"{b}_higher": bh, "ties": ti, "p_two_sided": p_two_sided(ah, ah + bh),
                      "non_cobol": [sum(1 for c, x, y in per if not c.endswith("cobol") and x > y),
                                    sum(1 for c, x, y in per if not c.endswith("cobol") and y > x)],
                      "per_cell": per}
    return out


def main():
    runs = list(csv.DictReader(open(STUDY / "results" / "data" / "runs_measures.csv")))
    (HERE / "per_run_edges").mkdir(exist_ok=True)
    out_rows, excluded, val = [], [], {}
    for r in runs:
        rid, cell, arm, rep = r["run_id"], r["cell"], r["arm"], int(r["rep"])
        row, js = measure(rid, cell.split("-")[1])
        if row is None:
            excluded.append(rid)
            continue
        (HERE / "per_run_edges" / f"{rid}.json").write_text(json.dumps(js))
        out_rows.append({"run_id": rid, "cell": cell, "arm": arm, "rep": rep, **row})
        if rep == 1:
            val[(cell, arm)] = row
    cols = list(out_rows[0])
    with open(HERE / "per_run.csv", "w", newline="") as f:
        w = csv.DictWriter(f, cols)
        w.writeheader()
        w.writerows(out_rows)
    cells = sorted({r["cell"] for r in runs})
    meas = MEASURES + ["strict_hub3_share"]
    med = {}
    for arm in ("S", "S2", "K", "K2", "X"):
        rs = [v for (c, a), v in val.items() if a == arm]
        med[arm] = {"runs": len(rs), **{m: (round(statistics.median([v[m] for v in rs if v[m] is not None]), 4)
                                            if any(v[m] is not None for v in rs) else None) for m in meas}}
        nc = [v for (c, a), v in val.items() if a == arm and not c.endswith("cobol")]
        med[arm]["hub3_share_non_cobol"] = round(statistics.median([v["hub3_share"] for v in nc if v["hub3_share"] is not None]), 4)
    within = {}
    for m in meas:
        d = {}
        for same, other in (("S", "S2"), ("K", "K2")):
            ws, bs, closer = [], [], 0
            for c in cells:
                a, b, x = (val.get((c, k), {}).get(m) for k in (same, other, "X"))
                if None in (a, b, x):
                    continue
                ws.append(abs(a - b))
                bs.append(abs(a - x))
                closer += abs(a - b) < abs(a - x)
            d[f"{same}-{other}_vs_{same}-X"] = {"cells": len(ws), "within_closer": closer,
                                               "median_abs_within": round(statistics.median(ws), 4) if ws else None,
                                               "median_abs_between": round(statistics.median(bs), 4) if bs else None}
        within[m] = d
    summary = {
        "label": "EXPLORATORY, not registered. Round-1 runs (rep 1); one program per arm per cell.",
        "excluded_runs": {rid: "no functions in any scan" for rid in excluded},
        "scan_roots": {r["run_id"]: r["scan"] for r in out_rows if r["scan"] != "confirm"},
        "arm_medians_round1": med,
        "round1_pairs": {f"{a}_vs_{b}": compare(val, cells, a, b, meas) for a, b in PAIRS},
        "round2_replication": {f"{a}_vs_{b}": compare(val, cells, a, b, meas) for a, b in REPL},
        "within_vs_between": within,
        "comparisons_made": len(meas) * (len(PAIRS) + len(REPL)),
    }
    (HERE / "summary.json").write_text(json.dumps(summary, indent=1))


if __name__ == "__main__":
    main()
