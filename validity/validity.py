#!/usr/bin/env python3
"""Scan-validity appraisal of GG extraction on the 60 agent-habits confirmation runs.

Reuses compare.py (imported read-only) for tree-sitter / ctags definitions and the
tri_comparison_reconcile pairing. Reads existing GG scans; never rescans. Looks at no study measure.

Run: PYTHONPATH=/home/joe/gitgalaxy/chess-study/engine /home/joe/gitgalaxy/venvs/doom-ci/bin/python validity.py
"""
from __future__ import annotations

import collections
import csv
import glob
import re
import sqlite3
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, "/home/joe/gitgalaxy/chess-study/compare")
import compare as cmp  # noqa: E402

# Every COBOL program here is compiled with `cobc -free` (build scripts), so ctags' fixed-format
# `Cobol` parser (ctags_reader.LANG_MAP default) misreads columns 1-7 (names like 'ART' for
# 'MAIN-START', '-EVALUATE'). Use ctags' own free-format parser instead; in memory only, no file edited.
# Set GG_VALIDITY_COBOL_CTAGS=Cobol to reproduce the fixed-format reading.
import os  # noqa: E402
cmp.ctags_reader.LANG_MAP["cobol"] = os.environ.get("GG_VALIDITY_COBOL_CTAGS", "CobolFree")

CONF = Path("/home/joe/gitgalaxy/chess-study/confirm")
SRC = CONF / "scan_src" / "confirm"
SCANS = CONF / "scans" / "confirm"
OUT = CONF / "validity"
RUN_RE = re.compile(r"^(chess|sat)-(c|java|python|rust|cobol)-(.+)-r(\d+)$")
CELL_EXT = {"c": {".c", ".h"}, "java": {".java"}, "python": {".py"}, "rust": {".rs"}, "cobol": {".cob", ".cbl", ".cpy"}}
SAMPLES_PER = 6


def file_kind(p: Path, rel: str) -> str:
    name = rel.rsplit("/", 1)[-1]
    if "." not in name or name.startswith("."):
        try:
            head = p.read_bytes()[:256]
        except OSError:
            head = b""
        if head.startswith(b"\x7fELF"):
            return "binary (ELF)"
        if head.startswith(b"#!"):
            first = head.split(b"\n", 1)[0].decode("utf-8", "replace")
            for k, v in (("python", "python"), ("bash", "shell"), ("/sh", "shell")):
                if k in first:
                    return v
        if name == ".gitignore":
            return "config (.gitignore)"
        return "(no extension)"
    ext = name[name.rfind("."):]
    for lang, exts in CELL_EXT.items():
        if ext in exts:
            return lang
    return {".sh": "shell", ".lock": "lockfile", ".toml": "build manifest (toml)", ".class": "build output (.class)",
            ".pyc": "build output (.pyc)", ".md": "markdown", ".txt": "plaintext"}.get(ext, f"other {ext}")


def text_stats(p: Path):
    b = p.read_bytes()
    lines = b.split(b"\n")
    if lines and lines[-1] == b"":
        lines = lines[:-1]
    return len(b), len(lines), max((len(x) for x in lines), default=0), lines


def ts_ct_only(path: Path, lang: str):
    """tree-sitter and ctags function definitions for a file GG never read (same calls as compare.gather_file)."""
    ts_funcs, ct_funcs = [], []
    if lang in cmp.tsaa.NODE_MAPS:
        spec = cmp.tsaa.NODE_MAPS[lang]
        tree = cmp.ts_parse(path, lang)
        ts_funcs, _ = cmp.tcg._walk_tree_sitter(tree.root_node, spec["func_node_types"], spec["class_node_types"], lang)
    if cmp.ctags_reader.ctags_available(lang):
        fk = cmp.ctags_reader.CTAGS_FUNC_KINDS.get(lang, set())
        for s in cmp.ctags_reader.read_ctags_symbols(path, lang):
            if cmp.tcg._is_ctags_synthetic_anon_name(s.name, lang):
                continue
            if s.kind in fk:
                ct_funcs.append(cmp.Occ(s.name, s.line if s.line >= 0 else None, cmp.tcg._count_ctags_signature_params(s.signature)))
    empty = {"gitgalaxy": [], "tree_sitter": [], "ctags": []}
    return {"gg_loc": {}, "gg_func_start_signal": 0, "gg_class_start_signal": 0,
            "function": {"gitgalaxy": [], "tree_sitter": ts_funcs, "ctags": ct_funcs}, "class": dict(empty),
            "gg_synthetic": 0, "ts_err": "", "ts_has_error": False}


def extra_tags(lang, name, slot, lines, present):
    """Our own structural tags for a disagreeing slot (from line text shape only)."""
    line = next((o.line for o in slot.values() if o is not None and o.line), None)
    tags = []
    if not line or line > len(lines):
        return tags, line, 0, 0
    raw = lines[line - 1].decode("utf-8", "replace")
    ln_len = len(raw)
    indent = len(raw) - len(raw.lstrip(" \t"))
    if ln_len > 200:
        tags.append("dense line (>200 chars)")
    return tags, line, ln_len, indent


def ts_spans(path: Path, lang: str) -> dict[int, int]:
    """start line -> line span (end-start+1) for every tree-sitter function node (NODE_MAPS types)."""
    spec = cmp.tsaa.NODE_MAPS[lang]
    tree = cmp.ts_parse(path, lang)
    out, stack = {}, [tree.root_node]
    while stack:
        n = stack.pop()
        if n.type in spec["func_node_types"]:
            out.setdefault(n.start_point[0] + 1, n.end_point[0] - n.start_point[0] + 1)
        stack.extend(n.children)
    return out


SPAN_ROWS: list = []


def span_check(run, arm, cell, rel, conn, fid, path):
    if cell not in cmp.tsaa.NODE_MAPS:
        return
    ts = ts_spans(path, cell)
    c = collections.Counter()
    worst = []
    for name, start, loc in conn.execute("SELECT func_name, start_line, loc FROM function_data WHERE file_id = ?", (fid,)):
        if name in cmp.tsaa._SYNTHETIC_GG_FUNC_NAMES or start is None:
            continue
        span = next((ts[s] for s in (start, start + 1, start - 1) if s in ts), None)
        if span is None:
            c["gg_unpaired"] += 1
            continue
        c["pairs"] += 1
        d = (loc or 0) - span
        c["gg_loc_sum"] += loc or 0
        c["ts_span_sum"] += span
        if d == 0:
            c["equal"] += 1
        elif abs(d) <= 2:
            c["within_2"] += 1
        elif d > 0:
            c["gg_longer_gt2"] += 1
            worst.append((d, name, start, loc, span))
        else:
            c["gg_shorter_gt2"] += 1
            worst.append((d, name, start, loc, span))
    worst.sort(key=lambda w: -abs(w[0]))
    SPAN_ROWS.append({"run": run, "arm": arm, "cell_lang": cell, "file": rel, **{k: c[k] for k in ("pairs", "equal", "within_2", "gg_longer_gt2", "gg_shorter_gt2", "gg_unpaired", "gg_loc_sum", "ts_span_sum")},
                      "worst": "; ".join(f"{n}@{s} GG={l} TS={sp}" for _, n, s, l, sp in worst[:3])})


def main():
    excl_rows, def_rows, cov_rows, samples = [], [], [], collections.defaultdict(list)
    cause_tot = collections.Counter()
    cause_arm = collections.Counter()
    tree_cache: dict = {}
    for run_dir in sorted(SRC.iterdir()):
        run = run_dir.name
        m = RUN_RE.match(run)
        task, cell, arm, rep = m.groups()
        (db,) = glob.glob(str(SCANS / run / "*_galaxy_master.db"))
        conn = sqlite3.connect(db)
        read = {r[1]: (r[0], r[2]) for r in conn.execute("SELECT id, file_path, language FROM file_data")}
        excluded = {r[0]: r[1] for r in conn.execute("SELECT file_path, exclusion_reason FROM excluded_artifacts")}
        files = sorted(str(p.relative_to(run_dir)) for p in run_dir.rglob("*") if p.is_file() and ".gitgalaxy" not in p.relative_to(run_dir).parts)
        cov = collections.Counter()
        cov_max_line_read = 0
        cov_max_line_all = 0
        dense_files = []
        for rel in files:
            p = run_dir / rel
            kind = file_kind(p, rel)
            size, nlines, maxlen, lines = text_stats(p)
            is_cell = kind == cell
            if rel not in read:
                reason = excluded.get(rel, "not recorded (no file_data or excluded_artifacts row)")
                is_source = kind in CELL_EXT or kind == "shell"
                excl_rows.append({"run": run, "arm": arm, "task": task, "cell_lang": cell, "file": rel, "file_kind": kind,
                                  "gg_reason": reason, "size_bytes": size, "lines": nlines if not kind.startswith("binary") else "",
                                  "max_line_len": maxlen if not kind.startswith("binary") else "",
                                  "is_source_code": int(is_source), "is_main_cell_source": int(is_cell)})
            if not is_cell:
                continue
            cov["files"] += 1
            cov["bytes"] += size
            cov["lines"] += nlines
            cov_max_line_all = max(cov_max_line_all, maxlen)
            cov["lines_over_200"] += sum(1 for x in lines if len(x) > 200)
            cov["lines_over_400"] += sum(1 for x in lines if len(x) > 400)
            if rel in read:
                fid, gg_lang = read[rel]
                cov["files_read"] += 1
                cov["bytes_read"] += size
                cov["lines_read"] += nlines
                cov_max_line_read = max(cov_max_line_read, maxlen)
                fr = cmp.gather_file(conn, fid, rel, p, cell)
                span_check(run, arm, cell, rel, conn, fid, p)
                status = "read by GG"
                if gg_lang != cell:
                    status = f"read by GG as {gg_lang}"
            else:
                fr = ts_ct_only(p, cell)
                status = "excluded by GG"
                gg_lang = ""
            tools = cmp.available(cell, "function")
            acc = collections.Counter()
            occs = fr["function"]
            for t in cmp.TOOLS3:
                acc[t] = len(occs[t]) if t in tools else 0
            for name, slot in cmp.slots_for(occs, tools, "function", cell):
                present = frozenset(t for t, o in slot.items() if o is not None)
                lab = cmp.shape_label(present, tools)
                acc[lab] += 1
                for other in ("tree_sitter", "ctags"):
                    g, o = slot.get("gitgalaxy"), slot.get(other)
                    if g is None or o is None or g.args is None or o.args is None:
                        continue
                    if g.line and o.line and abs(g.line - o.line) > cmp.tcr._ARGS_LINE_SPREAD_MAX:
                        continue
                    acc[f"args_{other}_cmp"] += 1
                    acc[f"args_{other}_eq"] += int(g.args == o.args)
                    if g.args != o.args and len(samples[("args", other, cell)]) < SAMPLES_PER:
                        samples[("args", other, cell)].append({"run": run, "name": name, "file": rel,
                            "lines": {"GG": g.line, other: o.line}, "line_len": 0, "indent": 0,
                            "cause": f"args GG={g.args} {other}={o.args}"})
                if lab == "all":
                    continue
                if status == "excluded by GG":
                    cause = "saturation exclusion (GG never read the file)" if "Saturation" in excluded.get(rel, "") else "file excluded by GG"
                else:
                    cause = cmp.guess_cause(cell, "function", name, present, tools, slot, fr, p, tree_cache)
                tags, line, ln_len, indent = extra_tags(cell, name, slot, lines, present)
                cls = cmp.cause_class(cause)
                if tags and status != "excluded by GG":
                    cls = cls + " + " + ",".join(tags)
                cause_tot[(cell, lab, cls)] += 1
                cause_arm[(arm, cell, lab, cls)] += 1
                key = (cell, lab, cls)
                if len(samples[key]) < SAMPLES_PER:
                    samples[key].append({"run": run, "name": name, "file": rel,
                                         "lines": {cmp.SHORT[t]: (slot[t].line if slot[t] else None) for t in tools},
                                         "line_len": ln_len, "indent": indent, "cause": cause})
            def_rows.append({"run": run, "arm": arm, "task": task, "cell_lang": cell, "file": rel, "gg_status": status,
                             "tools": "+".join(cmp.SHORT[t] for t in tools),
                             "gg_funcs": acc["gitgalaxy"], "ts_funcs": acc["tree_sitter"] if "tree_sitter" in tools else "",
                             "ctags_funcs": acc["ctags"], "matched_all": acc["all"],
                             "gg_only": acc["GG_only"], "ts_only": acc["TS_only"] if "tree_sitter" in tools else "",
                             "ctags_only": acc["CT_only"],
                             "gg_ts_not_ct": acc["GG+TS_only"], "gg_ct_not_ts": acc["GG+CT_only"], "ts_ct_not_gg": acc["TS+CT_only"],
                             "gg_synthetic_units": fr["gg_synthetic"],
                             "args_eq_gg_ts": acc["args_tree_sitter_eq"], "args_cmp_gg_ts": acc["args_tree_sitter_cmp"],
                             "args_eq_gg_ct": acc["args_ctags_eq"], "args_cmp_gg_ct": acc["args_ctags_cmp"], "ts_has_error_nodes": int(bool(fr["ts_has_error"]))})
        cov_rows.append({"run": run, "arm": arm, "task": task, "cell_lang": cell,
                         "cell_files": cov["files"], "cell_files_read": cov["files_read"],
                         "cell_bytes": cov["bytes"], "cell_bytes_read": cov["bytes_read"],
                         "share_bytes_read": round(cov["bytes_read"] / cov["bytes"], 4) if cov["bytes"] else "",
                         "cell_lines": cov["lines"], "cell_lines_read": cov["lines_read"],
                         "share_lines_read": round(cov["lines_read"] / cov["lines"], 4) if cov["lines"] else "",
                         "max_line_len_all": cov_max_line_all, "lines_over_200": cov["lines_over_200"],
                         "lines_over_400": cov["lines_over_400"]})
    write(OUT / "exclusions.csv", excl_rows)
    write(OUT / "coverage.csv", cov_rows)
    write(OUT / "spans.csv", SPAN_ROWS)
    # per-run aggregate rows + per-arm rows, split by GG status
    agg_rows = []
    num = ["gg_funcs", "ts_funcs", "ctags_funcs", "matched_all", "gg_only", "ts_only", "ctags_only", "gg_ts_not_ct", "gg_ct_not_ts", "ts_ct_not_gg", "gg_synthetic_units", "args_eq_gg_ts", "args_cmp_gg_ts", "args_eq_gg_ct", "args_cmp_gg_ct"]
    def agg(keyf, level):
        g = collections.OrderedDict()
        for r in def_rows:
            k = keyf(r)
            d = g.setdefault(k, collections.Counter())
            d["files"] += 1
            for n in num:
                d[n] += int(r[n] or 0)
        for k, d in g.items():
            row = {"level": level, "run": k[0], "arm": k[1], "cell_lang": k[2], "gg_status": k[3], "files": d["files"]}
            row.update({n: d[n] for n in num})
            if k[2].startswith("cobol"):
                row["ts_funcs"] = row["ts_only"] = ""
            agg_rows.append(row)
    agg(lambda r: (r["run"], r["arm"], r["cell_lang"], "read" if r["gg_status"].startswith("read") else "excluded"), "run")
    agg(lambda r: ("*", r["arm"], r["cell_lang"], "read" if r["gg_status"].startswith("read") else "excluded"), "arm x lang")
    grp = lambda r: "cobol (GG vs ctags only)" if r["cell_lang"] == "cobol" else "c+java+python+rust"
    agg(lambda r: ("*", r["arm"], grp(r), "read" if r["gg_status"].startswith("read") else "excluded"), "arm")
    agg(lambda r: ("*", r["arm"], grp(r), "all"), "arm (all files)")
    write(OUT / "definitions.csv", agg_rows)
    write(OUT / "definitions_by_file.csv", def_rows)
    cr = [{"cell_lang": k[0], "shape": k[1], "cause_class": k[2], "slots": v} for k, v in cause_tot.most_common()]
    write(OUT / "definition_causes.csv", cr)
    ca = [{"arm": k[0], "cell_lang": k[1], "shape": k[2], "cause_class": k[3], "slots": v} for k, v in sorted(cause_arm.items())]
    write(OUT / "definition_causes_by_arm.csv", ca)
    with open(OUT / "samples_raw.txt", "w") as fh:
        for key, lst in sorted(samples.items(), key=lambda kv: -cause_tot[kv[0]]):
            fh.write(f"## {' | '.join(map(str, key))} | total {cause_tot.get(key, '')}\n")
            for s in lst:
                fh.write(f"  {s['run']} {s['file']} {s['name']} lines={s['lines']} len={s['line_len']} indent={s['indent']} :: {s['cause']}\n")


def write(path, rows):
    if not rows:
        return
    keys = list(rows[0].keys())
    for r in rows:
        for k in r:
            if k not in keys:
                keys.append(k)
    with open(path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=keys)
        w.writeheader()
        w.writerows(rows)


if __name__ == "__main__":
    main()
