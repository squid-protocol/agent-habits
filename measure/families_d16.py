"""D16 primary version of the registered families: the scan-based measure H1 for the runs the aperture blocked.

Rule (D16, fixed before the validity appraisal): flagged runs are rescanned with the saturation bound lifted for
that run only (scans/confirm-d16/); where the rescan reads the cell-language source, its value is used. Where a
second gate still blocks it (Packed Payload Guard, no config switch), D16's fallback applies; for H1 the source's
own comment-line count decides: these files have no comment line at all (checked per file, consistent with the
tree-sitter/ctags appraisal in confirm/validity/), so doc_loc is 0 under any line counting and H1 = 0.0.
H2, H3, H5 read source directly and H4's Python files were not blocked: unchanged.
Writes families_d16.json / families_d16.md beside the default version (families.json).
"""

import csv
import json
import re
from pathlib import Path

import adapter as A

FLAGGED = ["chess-c-codex-r1", "chess-rust-codex-r1", "chess-rust-codex-r2", "sat-c-codex-r1"]
COMMENT = re.compile(r"//|/\*|^\s*\*")


def main() -> None:
    rows = {r["run_id"]: r for r in csv.DictReader(open(A.HERE / "runs_measures.csv"))}
    notes = {}
    for rid in FLAGGED:
        lang = rows[rid]["cell"].split("-")[1]
        src = [p for p in (A.SRC / rid).rglob("*") if p.is_file() and p.suffix in {".c": [".c", ".h"], "rust": [".rs"]}.get(lang, [".rs"])]
        comment_lines = sum(1 for p in src for ln in p.read_text(errors="ignore").splitlines() if COMMENT.search(ln))
        d16 = A.CONFIRM / "scans" / "confirm-d16" / rid
        A.L.SCANS = d16.parent
        keep = set(A.L.NON_CODE)
        try:
            import sqlite3
            db = next(d16.glob("*_galaxy_master.db"))
            con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
            langs = {l for (l,) in con.execute("SELECT DISTINCT lower(language) FROM file_data") if l}
            read = con.execute("SELECT count(*) FROM file_data WHERE lower(language) = ? AND coding_loc > 0", (lang,)).fetchone()[0]
            con.close()
            A.L.NON_CODE = (langs | keep) - {lang}
            value = A.L.profile(rid)["doc_per_code_line"] if read else None
        finally:
            A.L.NON_CODE = keep
            A.L.SCANS = A.SCANS
        if value is None:
            if comment_lines:
                raise SystemExit(f"{rid}: blocked and has {comment_lines} comment lines; D16 fallback needs the wrapped copy")
            value, how = 0.0, f"still blocked after the D16 rescan; source has 0 comment lines -> H1 = 0"
        else:
            how = f"D16 rescan read it; H1 from the rescan"
        notes[rid] = {"doc_per_code_line": value, "how": how, "source_comment_lines": comment_lines}
        rows[rid]["doc_per_code_line"] = value
    table = []
    for r in rows.values():
        t = dict(r)
        for k in ("doc_per_code_line", "funcs_commented_share", "early_exit_per_1k", "while_per_1k", "python_helper"):
            t[k] = None if t[k] in ("", None) else float(t[k])
        t["rep"] = int(t["rep"])
        table.append(t)
    r1 = {(t["cell"], t["arm"]): t for t in table if t["rep"] == 1}
    fams = {"A": ("S", "X", True), "B": ("K", "X", True), "C": ("K", "S", False), "D": ("S", "S2", False), "E": ("K", "K2", False)}
    out = {"d16_notes": notes,
           "families": {n: {"arms": [a, b], "directional": d, "tests": A.family(r1, a, b, d)} for n, (a, b, d) in fams.items()}}
    (A.HERE / "families_d16.json").write_text(json.dumps(out, indent=1) + "\n")
    lines = ["# D16 primary version (flagged Codex runs filled per D16)", ""]
    for rid, n in notes.items():
        lines.append(f"- {rid}: H1 = {n['doc_per_code_line']} ({n['how']})")
    for name, f in out["families"].items():
        a, b = f["arms"]
        lines.append(f"\n## Family {name}: {a} vs {b} ({'one-sided' if f['directional'] else 'two-sided'}, Holm)")
        for mid, t in f["tests"].items():
            lines.append(f"  {name}{mid} {t['measure']:24} cells {t['cells']:2}  {a}>{t[f'{a}_higher']:2}  {b}>{t[f'{b}_higher']:2}  "
                         f"tie {t['tie']}  pred {t['predicted']:9}  p {t['p']:.4f}  holm {t['p_holm']:.4f}")
    (A.HERE / "families_d16.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
