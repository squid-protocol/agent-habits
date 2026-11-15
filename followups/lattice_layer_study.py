"""Function-lattice (14-archetype) distribution layer after Seed-and-Extend on agent-habits."""

from __future__ import annotations

import csv
import json
import statistics
from collections import defaultdict
from pathlib import Path

import numpy as np
from scipy.spatial.distance import cdist, jensenshannon


def parse_run_id(rid: str) -> tuple[str, str, str, str]:
    parts = rid.split("-")
    return parts[0], parts[1], "-".join(parts[2:-1]), parts[-1]


def arm_family(arm: str) -> str:
    if arm in ("claude", "sonnet-b"):
        return "sonnet"
    if arm in ("haiku", "haiku-b"):
        return "haiku"
    return arm


def run_se(P: dict, R: dict, BL):
    cost = cdist(P["xd"], R["xd"], metric="euclidean")
    cost /= np.median(cost) + 1e-12
    T = BL.fused_gw(cost, P["hm"], R["hm"], alpha=0.5, eps=0.05, outer=40)
    fgw_cost = float(np.sum(T * cost))

    best_r = np.argmax(T, axis=1)
    best_q = np.argmax(T, axis=0)
    seeds = [(qi, int(best_r[qi]), float(T[qi, best_r[qi]]))
             for qi in range(P["n"]) if best_q[best_r[qi]] == qi]
    seeds.sort(key=lambda x: -x[2])
    if not seeds:
        return None
    k_seed = max(3, min(len(seeds), int(round(0.15 * len(seeds)))))
    top_seeds = seeds[:k_seed]

    delta = np.median(
        P["comp"][[s[0] for s in top_seeds]] - R["comp"][[s[1] for s in top_seeds]],
        axis=0,
    )
    matched = {qi: ri for qi, ri, _ in top_seeds}
    used_r = {ri for _, ri, _ in top_seeds}
    r_shifted = R["comp"] + delta
    r_snorm = r_shifted / np.maximum(np.linalg.norm(r_shifted, axis=1, keepdims=True), 1e-9)

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

    # Post-SE function-lattice layer metrics
    pairs = list(matched.items())
    arch_agree = sum(1 for qi, ri in pairs if P["arch"][qi] == R["arch"][ri]) / max(1, len(pairs))
    post_delta_res = float(np.median([
        np.linalg.norm(P["comp"][qi] - (R["comp"][ri] + delta))
        for qi, ri in pairs
    ]))
    loc_diff = float(np.median([
        abs(P["locs"][qi] - R["locs"][ri]) / max(P["locs"][qi], R["locs"][ri], 1)
        for qi, ri in pairs
    ]))
    return {
        "fgw_cost": fgw_cost,
        "se_n": len(matched),
        "se_cov": len(matched) / max(1, min(P["n"], R["n"])),
        "arch_agree": arch_agree,
        "post_delta_res": post_delta_res,
        "loc_diff": loc_diff,
    }


def main() -> int:
    from structural_fingerprint import blind as BL
    from structural_fingerprint import features as F
    from structural_fingerprint.fingerprint import build
    from structural_fingerprint.reference import load_reference
    from structural_fingerprint.scan_io import load_scan, resolve_scans

    confirm_dir = Path("/home/joe/gitgalaxy/chess-study/confirm/scans/confirm")
    d16_dir = Path("/home/joe/gitgalaxy/chess-study/confirm/scans/confirm-d16")

    ref = load_reference("portable")
    bp = BL.BlindParams()
    n_arch = len(ref.archetype_names)

    def load_run(name: str, db_path: Path):
        sc = load_scan(db_path, ref.signal_columns)
        ft = build(sc, ref, min_loc=3, keyword_mode="composition").functions
        bv = BL.blind_view(ft)
        if len(bv.rows) < 3:
            return None
        xd = BL.descriptors(bv, n_arch, bp.use_graph, bp.use_measures, None, bp.geometry_only)
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
        arch = np.array([int(ft.archetype[r]) for r in bv.rows], dtype=np.int64)
        locs = np.array([int(ft.loc[r]) for r in bv.rows], dtype=np.int64)
        cnt = np.bincount(arch, minlength=n_arch).astype(np.float64)
        dist = cnt / max(1.0, cnt.sum())
        w_cnt = np.bincount(arch, weights=locs, minlength=n_arch).astype(np.float64)
        w_dist = w_cnt / max(1.0, w_cnt.sum())
        return {
            "name": name, "n": len(bv.rows), "xd": xd, "hm": hm, "comp": comp,
            "cnorm": cnorm, "nbrs": nbrs, "arch": arch, "locs": locs,
            "dist": dist, "w_dist": w_dist,
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
        except Exception:
            pass

    print(f"Loaded {len(runs)} runs across {n_arch} archetypes: {list(ref.archetype_names)}")

    # 1. Per-model 14-archetype lattice profile
    by_arm_dist = defaultdict(list)
    for name, R in runs.items():
        _, _, arm, _ = parse_run_id(name)
        by_arm_dist[arm_family(arm)].append(R["dist"])

    print("\n=== Mean 14-Archetype Lattice Distribution by Model Family ===")
    header = "archetype                 " + "  ".join(f"{a:>8s}" for a in sorted(by_arm_dist))
    print(header)
    for idx, aname in enumerate(ref.archetype_names):
        vals = [np.mean([d[idx] for d in by_arm_dist[a]]) * 100 for a in sorted(by_arm_dist)]
        print(f"{aname:26s}" + "  ".join(f"{v:7.1f}%" for v in vals))

    # 2. Post-SE + Lattice layer across categories
    rows = []
    names = sorted(runs.keys())
    for i, a in enumerate(names):
        ta, la, aa, _ = parse_run_id(a)
        fa = arm_family(aa)
        for b in names[i + 1 :]:
            tb, lb, ab, _ = parse_run_id(b)
            fb = arm_family(ab)
            if ta != tb and not (la == lb and fa == fb):
                continue
            se = run_se(runs[a], runs[b], BL)
            if se is None:
                continue
            jsd = float(jensenshannon(runs[a]["dist"] + 1e-9, runs[b]["dist"] + 1e-9))
            w_jsd = float(jensenshannon(runs[a]["w_dist"] + 1e-9, runs[b]["w_dist"] + 1e-9))
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
            rows.append({
                "a": a, "b": b, "category": cat, "arm_a": fa, "arm_b": fb,
                "fgw_cost": round(se["fgw_cost"], 4),
                "se_cov": round(se["se_cov"], 4),
                "arch_jsd": round(jsd, 4),
                "arch_w_jsd": round(w_jsd, 4),
                "matched_arch_agree": round(se["arch_agree"], 4),
                "post_delta_res": round(se["post_delta_res"], 4),
                "matched_loc_diff": round(se["loc_diff"], 4),
            })

    out_csv = Path(__file__).resolve().parent / "lattice_layer_pairs.csv"
    with out_csv.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    print("\n=== Post-SE Function-Lattice Differentiation by Category (medians) ===")
    by_cat = defaultdict(list)
    for r in rows:
        by_cat[r["category"]].append(r)
    for cat in [
        "same_task_same_lang_same_model",
        "same_task_same_lang_diff_model",
        "same_task_diff_lang_same_model",
        "same_task_diff_lang_diff_model",
        "cross_task_control",
    ]:
        rs = by_cat[cat]
        print(
            f"  {cat:32s} (n={len(rs):3d}): "
            f"FGW={statistics.median(x['fgw_cost'] for x in rs):.3f}, "
            f"arch_JSD={statistics.median(x['arch_jsd'] for x in rs):.3f}, "
            f"matched_arch_agree={statistics.median(x['matched_arch_agree'] for x in rs)*100:5.1f}%, "
            f"post_delta_res={statistics.median(x['post_delta_res'] for x in rs):.3f}, "
            f"loc_diff={statistics.median(x['matched_loc_diff'] for x in rs)*100:4.1f}%"
        )

    # 3. Within same-task, same-lang, diff-model: can lattice JSD / arch_agree separate model pairs?
    print("\n=== Same-Task, Same-Lang Diff-Model Pairs vs Same-Model Pairs ===")
    for pair_lbl, flt in [
        ("sonnet <-> sonnet", lambda r: r["category"] == "same_task_same_lang_same_model" and r["arm_a"] == "sonnet"),
        ("haiku  <-> haiku",  lambda r: r["category"] == "same_task_same_lang_same_model" and r["arm_a"] == "haiku"),
        ("sonnet <-> haiku",  lambda r: r["category"] == "same_task_same_lang_diff_model" and {r["arm_a"], r["arm_b"]} == {"sonnet", "haiku"}),
        ("sonnet <-> codex",  lambda r: r["category"] == "same_task_same_lang_diff_model" and {r["arm_a"], r["arm_b"]} == {"sonnet", "codex"}),
        ("haiku  <-> codex",  lambda r: r["category"] == "same_task_same_lang_diff_model" and {r["arm_a"], r["arm_b"]} == {"haiku", "codex"}),
    ]:
        rs = [r for r in rows if flt(r)]
        if not rs:
            continue
        print(
            f"  {pair_lbl:18s} (n={len(rs):2d}): "
            f"FGW={statistics.median(x['fgw_cost'] for x in rs):.3f}, "
            f"arch_JSD={statistics.median(x['arch_jsd'] for x in rs):.3f}, "
            f"matched_arch_agree={statistics.median(x['matched_arch_agree'] for x in rs)*100:5.1f}%, "
            f"post_delta_res={statistics.median(x['post_delta_res'] for x in rs):.3f}"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
