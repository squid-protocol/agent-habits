"""Test language translation vector (delta) adjustment on 32-keyword-family lattice in agent-habits."""

from __future__ import annotations

from collections import defaultdict
from pathlib import Path

import numpy as np
from scipy.spatial.distance import jensenshannon

from structural_fingerprint import blind as BL
from structural_fingerprint.fingerprint import build
from structural_fingerprint.lattice import keyword_lattice_profile
from structural_fingerprint.reference import load_reference
from structural_fingerprint.scan_io import load_scan, resolve_scans


def parse_run_id(rid: str) -> tuple[str, str, str, str]:
    parts = rid.split("-")
    return parts[0], parts[1], "-".join(parts[2:-1]), parts[-1]


def arm_family(arm: str) -> str:
    if arm in ("claude", "sonnet-b"):
        return "sonnet"
    if arm in ("haiku", "haiku-b"):
        return "haiku"
    return arm


def roc_auc(pos: list[float], neg: list[float]) -> float:
    if not pos or not neg:
        return 0.5
    wins = 0.0
    for p in pos:
        for n in neg:
            if p > n:
                wins += 1.0
            elif p == n:
                wins += 0.5
    return wins / (len(pos) * len(neg))


def main() -> int:
    ref = load_reference("portable")
    confirm_dir = Path("/home/joe/gitgalaxy/chess-study/confirm/scans/confirm")
    d16_dir = Path("/home/joe/gitgalaxy/chess-study/confirm/scans/confirm-d16")

    runs = {}
    for p in sorted(confirm_dir.iterdir()):
        if not p.is_dir():
            continue
        scan_dir = d16_dir / p.name if (d16_dir / p.name).is_dir() else p
        try:
            sc = load_scan(resolve_scans([scan_dir])[0], ref.signal_columns)
            ft = build(sc, ref, min_loc=3, keyword_mode="composition").functions
            bv = BL.blind_view(ft)
            if len(bv.rows) < 3:
                continue
            _, _, kw_dist = keyword_lattice_profile(sc.signals, bv.rows)
            task, lang, arm, _ = parse_run_id(p.name)
            runs[p.name] = {
                "task": task, "lang": lang, "fam": arm_family(arm),
                "kw_dist": kw_dist,
            }
        except Exception:
            pass

    print(f"Loaded {len(runs)} runs.")

    # Leave-one-task-out language translation vector:
    # Estimate language centroids from the OTHER task (e.g. calibrate on chess, test on sat; and vice-versa).
    for test_task, train_task in [("sat", "chess"), ("chess", "sat")]:
        train_by_lang = defaultdict(list)
        for r in runs.values():
            if r["task"] == train_task:
                train_by_lang[r["lang"]].append(r["kw_dist"])
        lang_centroid = {l: np.mean(vs, axis=0) for l, vs in train_by_lang.items()}
        global_centroid = np.mean(list(lang_centroid.values()), axis=0)

        test_names = sorted(k for k, v in runs.items() if v["task"] == test_task)
        raw_same, raw_diff = [], []
        adj_same, adj_diff = [], []

        for i, a in enumerate(test_names):
            ra = runs[a]
            # Project onto language-centered space by subtracting (lang_centroid[lang] - global_centroid)
            adj_a = np.clip(ra["kw_dist"] - (lang_centroid[ra["lang"]] - global_centroid), 0.0, None)
            adj_a = adj_a / max(1e-9, float(adj_a.sum()))
            for b in test_names[i + 1 :]:
                rb = runs[b]
                if ra["lang"] == rb["lang"]:
                    continue
                adj_b = np.clip(rb["kw_dist"] - (lang_centroid[rb["lang"]] - global_centroid), 0.0, None)
                adj_b = adj_b / max(1e-9, float(adj_b.sum()))

                d_raw = float(jensenshannon(ra["kw_dist"] + 1e-9, rb["kw_dist"] + 1e-9))
                d_adj = float(jensenshannon(adj_a + 1e-9, adj_b + 1e-9))
                if ra["fam"] == rb["fam"]:
                    raw_same.append(d_raw)
                    adj_same.append(d_adj)
                else:
                    raw_diff.append(d_raw)
                    adj_diff.append(d_adj)

        print(f"\n=== Held-out task = {test_task} (delta calibrated on {train_task}) ===")
        print(f"  Raw diff-lang kw_JSD : same_model={np.median(raw_same):.3f} vs diff_model={np.median(raw_diff):.3f} | AUC={roc_auc([-x for x in raw_same], [-x for x in raw_diff]):.3f}")
        print(f"  Adj diff-lang kw_JSD : same_model={np.median(adj_same):.3f} vs diff_model={np.median(adj_diff):.3f} | AUC={roc_auc([-x for x in adj_same], [-x for x in adj_diff]):.3f}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
