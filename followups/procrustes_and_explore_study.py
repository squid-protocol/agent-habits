"""Experiment #1 (Orthogonal Procrustes vs Translation) + #2 (Held-out explore/ cc vs codex attribution)."""

from __future__ import annotations

from collections import defaultdict
from pathlib import Path

import numpy as np
from scipy.linalg import orthogonal_procrustes
from scipy.spatial.distance import cosine, jensenshannon

from structural_fingerprint import blind as BL
from structural_fingerprint.fingerprint import build
from structural_fingerprint.lattice import keyword_lattice_profile
from structural_fingerprint.reference import load_reference
from structural_fingerprint.scan_io import load_scan, resolve_scans


def parse_confirm_id(rid: str) -> tuple[str, str, str, str]:
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


def load_kw_runs(scan_root: Path, d16_root: Path | None, ref) -> dict[str, dict]:
    out = {}
    for p in sorted(scan_root.iterdir()):
        if not p.is_dir():
            continue
        scan_dir = d16_root / p.name if (d16_root and (d16_root / p.name).is_dir()) else p
        try:
            sc = load_scan(resolve_scans([scan_dir])[0], ref.signal_columns)
            ft = build(sc, ref, min_loc=3, keyword_mode="composition").functions
            bv = BL.blind_view(ft)
            if len(bv.rows) < 3:
                continue
            _, _, kw_dist = keyword_lattice_profile(sc.signals, bv.rows)
            out[p.name] = {"n": len(bv.rows), "kw_dist": kw_dist}
        except Exception:
            pass
    return out


def parse_explore_id(rid: str) -> tuple[str, str, str] | None:
    # e.g. agentic-chessengine-c-cc, agentic-cobol-doom-codex, agentic-cobol-sat-cc
    if rid.endswith("-cc"):
        model = "claude"
        stem = rid[:-3]
    elif rid.endswith("-codex"):
        model = "codex"
        stem = rid[:-6]
    else:
        return None
    if stem.startswith("agentic-chessengine-"):
        lang = stem.split("-")[-1]
        return "chess", lang, model
    if stem.startswith("agentic-cobol-"):
        task = stem.split("-")[-1]
        return task, "cobol", model
    return None


def main() -> int:
    ref = load_reference("portable")
    confirm_dir = Path("/home/joe/gitgalaxy/chess-study/confirm/scans/confirm")
    d16_dir = Path("/home/joe/gitgalaxy/chess-study/confirm/scans/confirm-d16")
    explore_dir = Path("/home/joe/gitgalaxy/chess-study/confirm/scans/explore")

    confirm_raw = load_kw_runs(confirm_dir, d16_dir, ref)
    confirm = {}
    for k, v in confirm_raw.items():
        task, lang, arm, rnd = parse_confirm_id(k)
        confirm[k] = {**v, "task": task, "lang": lang, "arm": arm, "fam": arm_family(arm), "rnd": rnd}

    explore_raw = load_kw_runs(explore_dir, None, ref)
    print(f"Loaded {len(confirm)} confirm runs, {len(explore_raw)} explore runs.")

    # --- Experiment #1: Orthogonal Procrustes vs Pure Translation (leave-one-task-out on confirm) ---
    print("\n=== Experiment #1: Orthogonal Procrustes vs Pure Translation (diff-lang pairs) ===")
    for test_task, train_task in [("sat", "chess"), ("chess", "sat")]:
        # Pair each (arm, rnd) across languages in train_task to map each language onto global mean space
        by_arm_lang = {}
        by_lang = defaultdict(list)
        for v in confirm.values():
            if v["task"] == train_task:
                by_arm_lang[(v["arm"], v["rnd"], v["lang"])] = v["kw_dist"]
                by_lang[v["lang"]].append(v["kw_dist"])

        lang_mean = {l: np.mean(vs, axis=0) for l, vs in by_lang.items()}
        global_mean = np.mean(list(lang_mean.values()), axis=0)

        # Build paired matrices X_L -> Y_global_arm_mean for orthogonal Procrustes
        arms_in_train = sorted({(v["arm"], v["rnd"]) for v in confirm.values() if v["task"] == train_task})
        arm_global = {}
        for arm, rnd in arms_in_train:
            vecs = [by_arm_lang[(arm, rnd, l)] - lang_mean[l] for l in lang_mean if (arm, rnd, l) in by_arm_lang]
            if vecs:
                arm_global[(arm, rnd)] = np.mean(vecs, axis=0)

        W_lang = {}
        for l in lang_mean:
            X, Y = [], []
            for arm, rnd in arms_in_train:
                if (arm, rnd, l) in by_arm_lang and (arm, rnd) in arm_global:
                    X.append(by_arm_lang[(arm, rnd, l)] - lang_mean[l])
                    Y.append(arm_global[(arm, rnd)])
            if len(X) >= 2:
                R_mat, _ = orthogonal_procrustes(np.vstack(X), np.vstack(Y))
                W_lang[l] = R_mat
            else:
                W_lang[l] = np.eye(len(global_mean))

        test_names = sorted(k for k, v in confirm.items() if v["task"] == test_task)
        raw_s, raw_d = [], []
        trn_s, trn_d = [], []
        prc_s, prc_d = [], []

        for i, a in enumerate(test_names):
            ra = confirm[a]
            va_trn = np.clip(ra["kw_dist"] - (lang_mean[ra["lang"]] - global_mean), 0.0, None)
            va_trn /= max(1e-9, float(va_trn.sum()))
            va_prc = (ra["kw_dist"] - lang_mean[ra["lang"]]) @ W_lang[ra["lang"]]
            for b in test_names[i + 1 :]:
                rb = confirm[b]
                if ra["lang"] == rb["lang"]:
                    continue
                vb_trn = np.clip(rb["kw_dist"] - (lang_mean[rb["lang"]] - global_mean), 0.0, None)
                vb_trn /= max(1e-9, float(vb_trn.sum()))
                vb_prc = (rb["kw_dist"] - lang_mean[rb["lang"]]) @ W_lang[rb["lang"]]

                d_raw = float(jensenshannon(ra["kw_dist"] + 1e-9, rb["kw_dist"] + 1e-9))
                d_trn = float(jensenshannon(va_trn + 1e-9, vb_trn + 1e-9))
                d_prc = float(np.linalg.norm(va_prc - vb_prc))
                if ra["fam"] == rb["fam"]:
                    raw_s.append(d_raw); trn_s.append(d_trn); prc_s.append(d_prc)
                else:
                    raw_d.append(d_raw); trn_d.append(d_trn); prc_d.append(d_prc)

        print(f"  Held-out {test_task:5s} (fit on {train_task}):")
        print(f"    Raw JSD         : AUC={roc_auc([-x for x in raw_s], [-x for x in raw_d]):.3f} (med {np.median(raw_s):.3f} vs {np.median(raw_d):.3f})")
        print(f"    Translation JSD : AUC={roc_auc([-x for x in trn_s], [-x for x in trn_d]):.3f} (med {np.median(trn_s):.3f} vs {np.median(trn_d):.3f})")
        print(f"    Procrustes L2   : AUC={roc_auc([-x for x in prc_s], [-x for x in prc_d]):.3f} (med {np.median(prc_s):.3f} vs {np.median(prc_d):.3f})")

    # --- Experiment #2: Zero-shot Claude vs Codex attribution on held-out explore/ ---
    lang_mean_all = defaultdict(list)
    for v in confirm.values():
        lang_mean_all[v["lang"]].append(v["kw_dist"])
    lang_cent = {l: np.mean(vs, axis=0) for l, vs in lang_mean_all.items()}

    # Train ridge-regularized linear difference (Claude centroid - Codex centroid) in language-centered space
    claude_res = [v["kw_dist"] - lang_cent[v["lang"]] for v in confirm.values() if v["fam"] in ("sonnet", "haiku")]
    codex_res = [v["kw_dist"] - lang_cent[v["lang"]] for v in confirm.values() if v["fam"] == "codex"]
    w_clf = np.mean(claude_res, axis=0) - np.mean(codex_res, axis=0)
    w_clf /= max(1e-9, float(np.linalg.norm(w_clf)))

    print("\n=== Experiment #2: Zero-Shot Claude vs Codex Attribution on Held-Out explore/ ===")
    cc_scores, cx_scores = [], []
    for name, v in sorted(explore_raw.items()):
        parsed = parse_explore_id(name)
        if not parsed:
            continue
        task, lang, model = parsed
        if lang not in lang_cent:
            print(f"  Skip {name} (unseen lang={lang})")
            continue
        res = v["kw_dist"] - lang_cent[lang]
        score = float(np.dot(res, w_clf))  # positive => Claude, negative => Codex
        pred = "claude" if score >= 0 else "codex"
        ok = "OK" if pred == model else "MISS"
        print(f"  {name:34s} (task={task:5s}, lang={lang:6s}, true={model:6s}) -> score={score:+.4f} pred={pred:6s} [{ok}]")
        if model == "claude":
            cc_scores.append(score)
        else:
            cx_scores.append(score)

    acc = (sum(s >= 0 for s in cc_scores) + sum(s < 0 for s in cx_scores)) / max(1, len(cc_scores) + len(cx_scores))
    auc = roc_auc(cc_scores, cx_scores)
    print(f"\n  Held-out explore/ (n={len(cc_scores)+len(cx_scores)}): Accuracy={acc*100:.1f}%, ROC AUC={auc:.3f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
