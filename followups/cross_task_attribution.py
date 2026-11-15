"""Cross-task model attribution: compare DOOM/control COBOL repos against agent-habits COBOL runs."""

from __future__ import annotations

import csv
import statistics
from collections import defaultdict
from pathlib import Path

from structural_fingerprint.lattice import seed_and_extend_with_lattice
from structural_fingerprint.reference import load_reference
from structural_fingerprint.scan_io import load_scan, resolve_scans


def arm_family(run_name: str) -> str:
    # e.g. chess-cobol-claude-r1
    arm = "-".join(run_name.split("-")[2:-1])
    if arm in ("claude", "sonnet-b"):
        return "sonnet"
    if arm in ("haiku", "haiku-b"):
        return "haiku"
    return arm


def main() -> int:
    ref = load_reference("portable")
    confirm_dir = Path("/home/joe/gitgalaxy/chess-study/confirm/scans/confirm")
    doom_scans = Path("/srv/storage_16tb/projects/gitgalaxy/doom-study/rescan-6c7c6c1bc/scans/6c7c6c1bc")

    targets = {
        "agentic-cobol-doom-cc": resolve_scans([doom_scans / "agentic-cobol-doom-cc"])[0],
        "agentic-cobol-doom-codex": resolve_scans([doom_scans / "agentic-cobol-doom-codex"])[0],
        "fps-cob": resolve_scans([doom_scans / "fps-cob"])[0],
        "carddemo-cobol-ctrl": Path("/tmp/doom-controls-new/scans/carddemo-cobol-ctrl_galaxy_master_master.db"),
    }

    cobol_runs = {}
    for p in sorted(confirm_dir.iterdir()):
        if p.is_dir() and "-cobol-" in p.name:
            cobol_runs[p.name] = load_scan(resolve_scans([p])[0], ref.signal_columns)

    rows = []
    for tname, tdb in targets.items():
        sc_t = load_scan(tdb, ref.signal_columns)
        by_fam = defaultdict(list)
        for rname, sc_r in cobol_runs.items():
            res = seed_and_extend_with_lattice(sc_t, sc_r, ref)
            fam = arm_family(rname)
            by_fam[fam].append(res)
            rows.append({
                "target": tname,
                "agent_run": rname,
                "model_family": fam,
                "fgw_cost": round(res.fgw_cost, 4),
                "kw_jsd": round(res.kw_jsd, 4),
                "arch_jsd": round(res.arch_jsd, 4),
                "matched_kw_cos": round(res.matched_kw_cos, 4),
                "matched_arch_agree": round(res.matched_arch_agree, 4),
            })

        print(f"\n=== {tname} (n_funcs={sc_t.loc.shape[0]}) vs agent-habits COBOL runs ===")
        for fam in ("sonnet", "haiku", "codex"):
            rs = by_fam[fam]
            print(
                f"  vs {fam:6s} (n={len(rs)}): "
                f"kw_JSD={statistics.mean(r.kw_jsd for r in rs):.3f}, "
                f"FGW={statistics.mean(r.fgw_cost):.3f}"
                if False else
                f"  vs {fam:6s} (n={len(rs)}): "
                f"kw_JSD={statistics.mean(r.kw_jsd for r in rs):.3f} [min={min(r.kw_jsd for r in rs):.3f}], "
                f"FGW={statistics.mean(r.fgw_cost for r in rs):.3f}, "
                f"kw_cos={statistics.mean(r.matched_kw_cos for r in rs):.3f}, "
                f"arch_agree={statistics.mean(r.matched_arch_agree for r in rs)*100:4.1f}%"
            )

    out_csv = Path(__file__).resolve().parent / "cross_task_attribution.csv"
    with out_csv.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
