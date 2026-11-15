"""Keyword-family lattice & Seed-and-Extend vs archetype/keyword cluster distributions on agent-habits."""

from __future__ import annotations

import csv
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

    pairs = list(matched.items())
    arch_agree = sum(1 for qi, ri in pairs if P["arch"][qi] == R["arch"][ri]) / max(1, len(pairs))
    kw_dom_agree = sum(1 for qi, ri in pairs if P["kw_dom"][qi] == R["kw_dom"][ri]) / max(1, len(pairs))
    kw_cos = float(np.median([
        float(np.dot(P["kw_norm"][qi], R["kw_norm"][ri]))
        for qi, ri in pairs
    ]))
    return {
        "fgw_cost": fgw_cost,
        "arch_agree": arch_agree,
        "kw_dom_agree": kw_dom_agree,
        "kw_cos": kw_cos,
    }


def roc_auc(pos_scores: list[float], neg_scores: list[float]) -> float:
    """Exact rank-based ROC AUC (higher score = positive)."""
    if not pos_scores or not neg_scores:
        return 0.5
    wins = 0.0
    total = len(pos_scores) * len(neg_scores)
    for p in pos_scores:
        for n in neg_scores:
            if p > n:
                wins += 1.0
            elif p == n:
                wins += 0.5
    return wins / total


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
    sig_cols = list(ref.signal_columns)
    n_sig = len(sig_cols)

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

        # 32 keyword-family lattice per function (composition)
        sigs = np.asarray(sc.signals, dtype=np.float64)[bv.rows]
        sig_sums = np.maximum(sigs.sum(axis=1, keepdims=True), 1.0)
        kw_comp = sigs / sig_sums
        kw_norm = kw_comp / np.maximum(np.linalg.norm(kw_comp, axis=1, keepdims=True), 1e-9)
        kw_dom = np.argmax(sigs, axis=1)
        # Repo-level keyword-family composition (mean across functions) & dominant-family histogram
        kw_repo_dist = kw_comp.mean(axis=0)
        kw_repo_dist = kw_repo_dist / max(1e-9, kw_repo_dist.sum())

        arch = np.array([int(ft.archetype[r]) for r in bv.rows], dtype=np.int64)
        cnt = np.bincount(arch, minlength=n_arch).astype(np.float64)
        arch_dist = cnt / max(1.0, cnt.sum())

        return {
            "name": name, "n": len(bv.rows), "xd": xd, "hm": hm, "comp": comp,
            "cnorm": cnorm, "nbrs": nbrs, "arch": arch, "arch_dist": arch_dist,
            "kw_norm": kw_norm, "kw_dom": kw_dom, "kw_repo_dist": kw_repo_dist,
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

    print(f"Loaded {len(runs)} runs; {n_sig} keyword families.")

    # 1. Top keyword-family differences across codex / haiku / sonnet
    by_arm_kw = defaultdict(list)
    for name, R in runs.items():
        _, _, arm, _ = parse_run_id(name)
        by_arm_kw[arm_family(arm)].append(R["kw_repo_dist"])

    arms = sorted(by_arm_kw.keys())
    means = {a: np.mean(by_arm_kw[a], axis=0) for a in arms}
    spread = [(float(max(means[a][i] for a in arms) - min(means[a][i] for a in arms)), i) for i in range(n_sig)]
    spread.sort(reverse=True)

    print("\n=== Top 12 Discriminating Keyword Families Across Models ===")
    print(f"{'keyword_family':28s}" + "".join(f"{a:>9s}" for a in arms))
    for _, idx in spread[:12]:
        print(f"{sig_cols[idx]:28s}" + "".join(f"{means[a][idx]*100:8.2f}%" for a in arms))

    # 2. Pairwise Seed-and-Extend vs Archetype Cluster vs Keyword-Family Lattice
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
            arch_jsd = float(jensenshannon(runs[a]["arch_dist"] + 1e-9, runs[b]["arch_dist"] + 1e-9))
            kw_jsd = float(jensenshannon(runs[a]["kw_repo_dist"] + 1e-9, runs[b]["kw_repo_dist"] + 1e-9))
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
                "a": a, "b": b, "category": cat,
                "fgw_cost": round(se["fgw_cost"], 4),
                "arch_jsd": round(arch_jsd, 4),
                "arch_agree": round(se["arch_agree"], 4),
                "kw_jsd": round(kw_jsd, 4),
                "kw_dom_agree": round(se["kw_dom_agree"], 4),
                "kw_cos": round(se["kw_cos"], 4),
            })

    out_csv = Path(__file__).resolve().parent / "keyword_lattice_pairs.csv"
    with out_csv.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    print("\n=== Medians: Seed-and-Extend vs Archetype Cluster vs Keyword-Family Lattice ===")
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
            f"FGW={statistics.median(x['fgw_cost'] for x in rs):.3f} | "
            f"arch_JSD={statistics.median(x['arch_jsd'] for x in rs):.3f}, arch_agree={statistics.median(x['arch_agree'] for x in rs)*100:4.1f}% | "
            f"kw_JSD={statistics.median(x['kw_jsd'] for x in rs):.3f}, kw_dom={statistics.median(x['kw_dom_agree'] for x in rs)*100:4.1f}%, kw_cos={statistics.median(x['kw_cos'] for x in rs):.3f}"
        )

    # 3. ROC AUC for differentiating same-model vs diff-model within same_task + same_lang
    pos = by_cat["same_task_same_lang_same_model"]
    neg = by_cat["same_task_same_lang_diff_model"]
    print("\n=== ROC AUC: Same-Model vs Diff-Model (same task & lang) ===")
    print(f"  1) Call-graph FGW (-fgw_cost)          : {roc_auc([-x['fgw_cost'] for x in pos], [-x['fgw_cost'] for x in neg]):.3f}")
    print(f"  2) 14-Archetype dist (-arch_JSD)       : {roc_auc([-x['arch_jsd'] for x in pos], [-x['arch_jsd'] for x in neg]):.3f}")
    print(f"  3) Post-SE Archetype agree (arch_agree): {roc_auc([x['arch_agree'] for x in pos], [x['arch_agree'] for x in neg]):.3f}")
    print(f"  4) 32-Keyword-Family dist (-kw_JSD)    : {roc_auc([-x['kw_jsd'] for x in pos], [-x['kw_jsd'] for x in neg]):.3f}")
    print(f"  5) Post-SE Keyword dom agree           : {roc_auc([x['kw_dom_agree'] for x in pos], [x['kw_dom_agree'] for x in neg]):.3f}")
    print(f"  6) Post-SE Keyword cosine              : {roc_auc([x['kw_cos'] for x in pos], [x['kw_cos'] for x in neg]):.3f}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
