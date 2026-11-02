"""Section 6: the exploratory set re-read with the confirmation engine (7d2e1f627), reported beside the confirmation,
never pooled. The 10 exploratory pairs (Claude Code vs Codex, acherm/agentic-*): H1-H5 measures and their
direction counts, exactly as the confirmation computes them (H1 cell language only, D14).
H2 comes from the exploratory comment pipeline's outputs (engine-independent); H3, H5 from keyword_diff on the
original checkouts; H1, H4 from the rescans (scans/explore).
"""

import csv
import json
import sqlite3
from pathlib import Path

import adapter as A

PAIRS = {  # cell -> (claude repo, codex repo)
    "chess-c": ("agentic-chessengine-c-cc", "agentic-chessengine-c-codex"),
    "chess-cpp": ("agentic-chessengine-cpp-cc", "agentic-chessengine-cpp-codex"),
    "chess-java": ("agentic-chessengine-java-cc", "agentic-chessengine-java-codex"),
    "chess-python": ("agentic-chessengine-python-cc", "agentic-chessengine-python-codex"),
    "chess-rust": ("agentic-chessengine-rust-cc", "agentic-chessengine-rust-codex"),
    "chess-cobol": ("agentic-chessengine-cobol-cc", "agentic-chessengine-cobol-codex"),
    "compress-cobol": ("agentic-cobol-compress-cc", "agentic-cobol-compress"),
    "doom-cobol": ("agentic-cobol-doom-cc", "agentic-cobol-doom-codex"),
    "pygame-cobol": ("agentic-cobol-pygame-cc", "agentic-cobol-pygame"),
    "sat-cobol": ("agentic-cobol-sat-cc", "agentic-cobol-sat-codex"),
}
EXPLORE_SCANS = A.CONFIRM / "scans" / "explore"
REPO_ROOTS = [Path("/home/joe/gitgalaxy/chess-study/repos"), Path("/home/joe/gitgalaxy/cobol-agents/repos")]
STUDY_COMMENTS = A.STUDY / "comments" / "per_repo.csv"


def h1(repo, lang):
    A.L.SCANS = EXPLORE_SCANS
    keep = set(A.L.NON_CODE)
    try:
        db = next((EXPLORE_SCANS / repo).glob("*_galaxy_master.db"))
        con = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
        langs = {l for (l,) in con.execute("SELECT DISTINCT lower(language) FROM file_data") if l}
        py = con.execute("SELECT count(*) FROM function_data f JOIN file_data d ON d.id = f.file_id "
                         "WHERE lower(d.language) = 'python' AND f.loc >= 3").fetchone()[0]
        con.close()
        A.L.NON_CODE = (langs | keep) - {lang}
        v = A.L.profile(repo)["doc_per_code_line"]
    finally:
        A.L.NON_CODE = keep
        A.L.SCANS = A.SCANS
    return v, int(py > 0)


def main():
    A.K.ROOTS = REPO_ROOTS
    comments = {}
    for r in csv.DictReader(open(STUDY_COMMENTS)):
        comments[Path(r["repo"]).name] = float(r["funcs_commented_share"])
    rows = {}
    for cell, (cc, cx) in PAIRS.items():
        lang = cell.split("-")[1]
        for arm, repo in (("S", cc), ("X", cx)):
            doc, py = h1(repo, lang)
            c = A.K.counts(repo, lang)
            tot = sum(c.values()) or 1
            if lang == "cobol":
                ex = 0
                root = next(r / repo for r in REPO_ROOTS if (r / repo).is_dir())
                for p in root.rglob("*"):
                    if p.is_file() and p.suffix.lower() in A.K.EXT["cobol"] and not (A.K.SKIP_DIRS & {x.lower() for x in p.parts}):
                        t = A.K.code_only(p.read_text(encoding="utf-8", errors="ignore"), "cobol")
                        ex += sum(1 for m in A.EXIT_RX.finditer(t) if (m.group(1) or "").upper().split()[:1] in (["PARAGRAPH"], ["PERFORM"]))
                early, wh = 1000 * ex / tot, None
            else:
                early, wh = 1000 * c.get("return", 0) / tot, 1000 * c.get("while", 0) / tot
            rows[(cell, arm)] = {"doc_per_code_line": doc, "funcs_commented_share": comments.get(repo),
                                 "early_exit_per_1k": early, "python_helper": py if lang != "python" else None,
                                 "while_per_1k": wh if lang != "cobol" else None}
    res = A.family(rows, "S", "X", True)
    out = {"engine": (A.CONFIRM / "engine.sha").read_text().strip(), "tests": res}
    (A.HERE / "explore_rescan.json").write_text(json.dumps(out, indent=1) + "\n")
    for mid, t in res.items():
        print(f"  H{mid} {t['measure']:24} cells {t['cells']:2}  Claude>{t['S_higher']:2}  Codex>{t['X_higher']:2}  tie {t['tie']}  "
              f"p {t['p']:.4f}  (exploratory; not a test)")


if __name__ == "__main__":
    main()
