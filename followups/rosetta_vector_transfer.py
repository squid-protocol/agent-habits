"""Test zero-shot language translation vectors from keyword-rosetta on agent-habits and doom-dna."""

from __future__ import annotations

import sqlite3
from collections import defaultdict
from pathlib import Path

import numpy as np
from scipy.spatial.distance import jensenshannon

from structural_fingerprint import blind as BL
from structural_fingerprint.fingerprint import build
from structural_fingerprint.lattice import keyword_lattice_profile
from structural_fingerprint.reference import load_reference
from structural_fingerprint.scan_io import load_scan, resolve_scans


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


def parse_confirm_id(rid: str) -> tuple[str, str, str, str]:
    parts = rid.split("-")
    return parts[0], parts[1], "-".join(parts[2:-1]), parts[-1]


def arm_family(arm: str) -> str:
    if arm in ("claude", "sonnet-b"):
        return "sonnet"
    if arm in ("haiku", "haiku-b"):
        return "haiku"
    return arm


def main() -> int:
    ref = load_reference("portable")
    sig_cols = list(ref.signal_columns)

    # 1. Load 32-keyword-family centroids per language from keyword-rosetta (language-crucible v4.3.1 DB)
    db_path = Path("/home/joe/gitgalaxy/language-crucible/raw_output/v4.3.1/data_galaxy_master.db")
    conn = sqlite3.connect(db_path)
    col_sql = ", ".join(f"COALESCE(fn.{c}, 0)" for c in sig_cols)
    q = f"""
      SELECT LOWER(f.language), {col_sql}
      FROM file_data f
      JOIN function_data fn ON fn.file_id = f.id
      WHERE fn.loc >= 3
    """
    by_lang_sigs = defaultdict(list)
    for row in conn.execute(q):
        by_lang_sigs[row[0]].append(row[1:])
    conn.close()

    rosetta_dist = {}
    for lang, rows in by_lang_sigs.items():
        if len(rows) < 20:
            continue
        _, _, dist = keyword_lattice_profile(np.asarray(rows, dtype=np.float64))
        rosetta_dist[lang] = dist

    print(f"Loaded {len(rosetta_dist)} languages (>=20 funcs) from keyword-rosetta.")
    target_langs = ["c", "python", "rust", "java", "cobol", "go", "dart", "csharp", "fortran"]
    available = [l for l in target_langs if l in rosetta_dist]
    global_rosetta = np.mean([rosetta_dist[l] for l in ["c", "python", "rust", "java", "cobol"]], axis=0)
    print("Available target languages:", available)

    # 2. Test zero-shot Rosetta language-vector transfer on agent-habits (56 confirm runs)
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
            task, lang, arm, _ = parse_confirm_id(p.name)
            runs[p.name] = {"task": task, "lang": lang, "fam": arm_family(arm), "kw_dist": kw_dist}
        except Exception:
            pass

    for task in ("chess", "sat"):
        names = sorted(k for k, v in runs.items() if v["task"] == task)
        raw_s, raw_d, ros_s, ros_d = [], [], [], []
        for i, a in enumerate(names):
            ra = runs[a]
            va_ros = np.clip(ra["kw_dist"] - (rosetta_dist[ra["lang"]] - global_rosetta), 0.0, None)
            va_ros /= max(1e-9, float(va_ros.sum()))
            for b in names[i + 1 :]:
                rb = runs[b]
                if ra["lang"] == rb["lang"]:
                    continue
                vb_ros = np.clip(rb["kw_dist"] - (rosetta_dist[rb["lang"]] - global_rosetta), 0.0, None)
                vb_ros /= max(1e-9, float(vb_ros.sum()))
                d_raw = float(jensenshannon(ra["kw_dist"] + 1e-9, rb["kw_dist"] + 1e-9))
                d_ros = float(jensenshannon(va_ros + 1e-9, vb_ros + 1e-9))
                if ra["fam"] == rb["fam"]:
                    raw_s.append(d_raw); ros_s.append(d_ros)
                else:
                    raw_d.append(d_raw); ros_d.append(d_ros)
        print(f"\n=== agent-habits ({task}) cross-language with ZERO-SHOT Rosetta delta ===")
        print(f"  Raw kw_JSD     : same={np.median(raw_s):.3f} vs diff={np.median(raw_d):.3f} | AUC={roc_auc([-x for x in raw_s], [-x for x in raw_d]):.3f}")
        print(f"  Rosetta kw_JSD : same={np.median(ros_s):.3f} vs diff={np.median(ros_d):.3f} | AUC={roc_auc([-x for x in ros_s], [-x for x in ros_d]):.3f}")

    # 3. Test zero-shot Rosetta C -> target delta on doom-dna translations
    doom_scans = Path("/srv/storage_16tb/projects/gitgalaxy/doom-study/rescan-6c7c6c1bc/scans/6c7c6c1bc")
    sc_ld = load_scan(resolve_scans([doom_scans / "linuxdoom"])[0], ref.signal_columns)
    ft_ld = build(sc_ld, ref, min_loc=3, keyword_mode="composition").functions
    bv_ld = BL.blind_view(ft_ld)
    _, _, ld_kw = keyword_lattice_profile(sc_ld.signals, bv_ld.rows)

    print("\n=== doom-dna translations vs linuxdoom (raw vs Rosetta C->L delta) ===")
    for port, lang in [("gore", "go"), ("dartdoom", "dart"), ("managed-doom", "csharp"), ("mochadoom", "java"), ("doomf77", "fortran")]:
        sc_p = load_scan(resolve_scans([doom_scans / port])[0], ref.signal_columns)
        ft_p = build(sc_p, ref, min_loc=3, keyword_mode="composition").functions
        bv_p = BL.blind_view(ft_p)
        _, _, p_kw = keyword_lattice_profile(sc_p.signals, bv_p.rows)
        # Predict port kw_dist from linuxdoom + (rosetta[lang] - rosetta["c"])
        pred_kw = np.clip(ld_kw + (rosetta_dist[lang] - rosetta_dist["c"]), 0.0, None)
        pred_kw /= max(1e-9, float(pred_kw.sum()))
        d_raw = float(jensenshannon(ld_kw + 1e-9, p_kw + 1e-9))
        d_ros = float(jensenshannon(pred_kw + 1e-9, p_kw + 1e-9))
        print(f"  {port:14s} ({lang:7s}): raw_JSD={d_raw:.3f} -> Rosetta-shifted_JSD={d_ros:.3f} (delta={d_ros-d_raw:+.3f})")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
