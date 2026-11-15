"""Seed-and-Extend & 16-Track Call-Graph DNA analysis across agent-habits (60 runs)."""

from __future__ import annotations

import csv
import json
import re
from collections import defaultdict
from pathlib import Path

import numpy as np
from scipy.spatial import cKDTree
from scipy.spatial.distance import cdist


def norm_name(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", s.lower())


def discover_communities(n: int, edges: np.ndarray, locs: np.ndarray, k_keep: int = 16):
    adj = [defaultdict(int) for _ in range(n)]
    deg = np.zeros(n, dtype=np.float64)
    for u, v in edges.tolist():
        if u != v:
            adj[u][v] += 1
            adj[v][u] += 1
            deg[u] += 1
            deg[v] += 1
    m2 = max(1.0, float(np.sum(deg)))
    comm = list(range(n))
    tot_deg = deg.copy()
    for _ in range(20):
        moved = 0
        for i in range(n):
            if deg[i] == 0:
                continue
            ci = comm[i]
            cw = defaultdict(float)
            for j, w in adj[i].items():
                cw[comm[j]] += w
            tot_deg[ci] -= deg[i]
            best_c, best_gain = ci, 0.0
            for c, k_in in cw.items():
                gain = k_in - deg[i] * tot_deg[c] / m2
                if gain > best_gain + 1e-12:
                    best_gain = gain
                    best_c = c
            tot_deg[best_c] += deg[i]
            if best_c != ci:
                comm[i] = best_c
                moved += 1
        if moved == 0:
            break
    groups = defaultdict(list)
    for i, c in enumerate(comm):
        groups[c].append(i)
    ordered = sorted(groups.values(), key=lambda g: -sum(int(locs[i]) for i in g))
    kept = ordered[: k_keep - 1]
    rest = [i for g in ordered[k_keep - 1 :] for i in g]
    if rest:
        kept.append(rest)
    node_to_comm = np.zeros(n, dtype=np.int64)
    for cid, g in enumerate(kept):
        for i in g:
            node_to_comm[i] = cid
    return node_to_comm, kept


def seed_and_extend(P: dict, R: dict, BL):
    """Run unsupervised Seed-and-Extend from P -> R."""
    if P["n"] == 0 or R["n"] == 0:
        return None
    cost = cdist(P["xd"], R["xd"], metric="euclidean")
    cost /= np.median(cost) + 1e-12
    T = BL.fused_gw(cost, P["hm"], R["hm"], alpha=0.5, eps=0.05, outer=40)
    fgw_cost = float(np.sum(T * cost))

    best_r = np.argmax(T, axis=1)
    best_q = np.argmax(T, axis=0)
    seeds = [
        (qi, int(best_r[qi]), float(T[qi, best_r[qi]]))
        for qi in range(P["n"])
        if best_q[best_r[qi]] == qi
    ]
    seeds.sort(key=lambda x: -x[2])
    if not seeds:
        return {"t1_n": 0, "t1_hits": 0, "se_n": 0, "se_hits": 0, "fgw_cost": fgw_cost, "matched": {}}
    k_seed = max(3, min(len(seeds), int(round(0.15 * len(seeds)))))
    top_seeds = seeds[:k_seed]

    delta = np.median(
        P["comp"][[s[0] for s in top_seeds]] - R["comp"][[s[1] for s in top_seeds]],
        axis=0,
    )
    matched = {qi: ri for qi, ri, _ in top_seeds}
    used_r = {ri for _, ri, _ in top_seeds}
    r_snorm = (R["comp"] + delta) / np.maximum(
        np.linalg.norm(R["comp"] + delta, axis=1, keepdims=True), 1e-9
    )

    for _ in range(3):
        cand = []
        for qi in range(P["n"]):
            if qi in matched:
                continue
            qn = [u for u in P["nbrs"][qi] if u in matched]
            if not qn:
                continue
            rc_cnt = defaultdict(int)
            for u in qn:
                for rc in R["nbrs"][matched[u]]:
                    if rc not in used_r:
                        rc_cnt[rc] += 1
            for rc, cnt in rc_cnt.items():
                cand.append((float(np.dot(P["cnorm"][qi], r_snorm[rc])) + 0.1 * cnt, qi, rc))
        cand.sort(key=lambda x: -x[0])
        for _, qi, rc in cand:
            if qi in matched or rc in used_r:
                continue
            matched[qi] = rc
            used_r.add(rc)

    t1_hits = sum(
        1 for qi, ri, _ in top_seeds if norm_name(P["names"][qi]) == norm_name(R["names"][ri])
    )
    se_hits = sum(
        1 for qi, ri in matched.items() if norm_name(P["names"][qi]) == norm_name(R["names"][ri])
    )
    return {
        "t1_n": len(top_seeds),
        "t1_hits": t1_hits,
        "se_n": len(matched),
        "se_hits": se_hits,
        "fgw_cost": fgw_cost,
        "matched": matched,
    }


def parse_run_id(rid: str) -> tuple[str, str, str, str]:
    # e.g. chess-c-claude-r1, sat-python-sonnet-b-r2
    parts = rid.split("-")
    task = parts[0]
    lang = parts[1]
    rnd = parts[-1]
    arm = "-".join(parts[2:-1])
    return task, lang, arm, rnd


def arm_family(arm: str) -> str:
    if arm in ("claude", "sonnet-b"):
        return "sonnet"
    if arm in ("haiku", "haiku-b"):
        return "haiku"
    return arm


def main() -> int:
    from structural_fingerprint import blind as BL
    from structural_fingerprint import features as F
    from structural_fingerprint.fingerprint import build
    from structural_fingerprint.reference import load_reference
    from structural_fingerprint.scan_io import load_scan, resolve_scans

    confirm_dir = Path("/home/joe/gitgalaxy/chess-study/confirm/scans/confirm")
    d16_dir = Path("/home/joe/gitgalaxy/chess-study/confirm/scans/confirm-d16")
    ld_dir = Path("/srv/storage_16tb/projects/gitgalaxy/doom-study/rescan-6c7c6c1bc/scans/6c7c6c1bc/linuxdoom")

    ref = load_reference("portable")
    bp = BL.BlindParams()

    def load_run(name: str, db_path: Path):
        sc = load_scan(db_path, ref.signal_columns)
        ft = build(sc, ref, min_loc=3, keyword_mode="composition").functions
        bv = BL.blind_view(ft)
        if len(bv.rows) < 3:
            return None
        xd = BL.descriptors(bv, len(ref.archetype_names), bp.use_graph, bp.use_measures, None, bp.geometry_only)
        hm = BL.hop_matrix(bv, bp.hop_cap)
        comp_all = F.raw_features(
            ref, sc.loc, sc.complexity, sc.args, sc.keyword_density, sc.signals,
            keyword_mode="composition",
        )
        comp = comp_all[bv.rows]
        cnorm = comp / np.maximum(np.linalg.norm(comp, axis=1, keepdims=True), 1e-9)
        nbrs = defaultdict(set)
        for u, v in bv.edges.tolist():
            if u != v:
                nbrs[u].add(v); nbrs[v].add(u)
        names = [str(ft.name[r]) for r in bv.rows]
        locs = np.array([int(ft.loc[r]) for r in bv.rows], dtype=np.int64)
        return {
            "name": name, "n": len(bv.rows), "xd": xd, "hm": hm, "comp": comp,
            "cnorm": cnorm, "nbrs": nbrs, "edges": bv.edges, "names": names,
            "locs": locs, "tree": cKDTree(xd),
        }

    runs = {}
    for p in sorted(confirm_dir.iterdir()):
        if not p.is_dir():
            continue
        scan_dir = d16_dir / p.name if (d16_dir / p.name).is_dir() else p
        try:
            db = resolve_scans([scan_dir])[0]
            R = load_run(p.name, db)
            if R is not None:
                runs[p.name] = R
        except Exception as e:
            print(f"Skip {p.name}: {e}")

    print(f"Loaded {len(runs)} agent-habits runs.")
    ld = load_run("linuxdoom", resolve_scans([ld_dir])[0])

    # Pairwise Seed-and-Extend across all within-task pairs + sample cross-task + linuxdoom controls
    pair_rows = []
    run_names = sorted(runs.keys())
    for i, a in enumerate(run_names):
        ta, la, aa, ra = parse_run_id(a)
        fa = arm_family(aa)
        for b in run_names[i + 1 :]:
            tb, lb, ab, rb = parse_run_id(b)
            fb = arm_family(ab)
            # Run all same-task pairs; sample cross-task for same language/arm
            if ta != tb and not (la == lb and fa == fb):
                continue
            res = seed_and_extend(runs[a], runs[b], BL)
            if res is None:
                continue
            if ta != tb:
                cat = "cross_task_control"
            elif la == lb and fa == fb:
                cat = "same_task_same_lang_same_model"
            elif la == lb:
                cat = "same_task_same_lang_diff_model"
            elif fa == fb:
                cat = "same_task_diff_lang_same_model"
            else:
                cat = "same_task_diff_lang_diff_model"
            pair_rows.append({
                "a": a, "b": b, "category": cat,
                "task_a": ta, "task_b": tb, "lang_a": la, "lang_b": lb,
                "arm_a": fa, "arm_b": fb,
                "n_a": runs[a]["n"], "n_b": runs[b]["n"],
                "t1_n": res["t1_n"], "t1_hits": res["t1_hits"],
                "t1_prec": round(res["t1_hits"] / max(1, res["t1_n"]), 4),
                "se_n": res["se_n"], "se_hits": res["se_hits"],
                "se_prec": round(res["se_hits"] / max(1, res["se_n"]), 4),
                "fgw_cost": round(res["fgw_cost"], 4),
            })

    # Also test C runs against linuxdoom as cross-domain negative control
    for a in run_names:
        ta, la, aa, _ = parse_run_id(a)
        if la == "c":
            res = seed_and_extend(runs[a], ld, BL)
            if res:
                pair_rows.append({
                    "a": a, "b": "linuxdoom", "category": "doom_negative_control",
                    "task_a": ta, "task_b": "doom", "lang_a": la, "lang_b": "c",
                    "arm_a": arm_family(aa), "arm_b": "human",
                    "n_a": runs[a]["n"], "n_b": ld["n"],
                    "t1_n": res["t1_n"], "t1_hits": res["t1_hits"],
                    "t1_prec": round(res["t1_hits"] / max(1, res["t1_n"]), 4),
                    "se_n": res["se_n"], "se_hits": res["se_hits"],
                    "se_prec": round(res["se_hits"] / max(1, res["se_n"]), 4),
                    "fgw_cost": round(res["fgw_cost"], 4),
                })

    out_csv = Path(__file__).resolve().parent / "seed_and_extend_pairs.csv"
    with out_csv.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(pair_rows[0].keys()))
        w.writeheader()
        w.writerows(pair_rows)

    # Summarize by category
    by_cat = defaultdict(list)
    for r in pair_rows:
        by_cat[r["category"]].append(r)

    print("\nCategory summary (median FGW_cost, mean SE_prec, mean T1_prec):")
    for cat in [
        "same_task_same_lang_same_model",
        "same_task_same_lang_diff_model",
        "same_task_diff_lang_same_model",
        "same_task_diff_lang_diff_model",
        "cross_task_control",
        "doom_negative_control",
    ]:
        rows = by_cat[cat]
        if not rows:
            continue
        fgws = [r["fgw_cost"] for r in rows]
        ses = [r["se_prec"] for r in rows]
        t1s = [r["t1_prec"] for r in rows]
        print(
            f"  {cat:34s} (n={len(rows):3d}): "
            f"FGW median={np.median(fgws):.3f} [min={min(fgws):.3f}], "
            f"T1_prec={np.mean(t1s)*100:5.1f}%, SE_prec={np.mean(ses)*100:5.1f}%"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
