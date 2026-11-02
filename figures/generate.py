#!/usr/bin/env python3
"""Generate the two evidence figures embedded in the README from committed result files."""
from html import escape
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "figures"


def svg_start(width, height, title, desc):
    return [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">',
        f'<title id="title">{escape(title)}</title>',
        f'<desc id="desc">{escape(desc)}</desc>',
        '<rect width="100%" height="100%" rx="18" fill="#101827"/>',
        '<style>text{font-family:Inter,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}.muted{fill:#aab6c7}.white{fill:#f5f7fb}.small{font-size:15px}.label{font-size:17px}.headline{font-size:25px;font-weight:700}</style>',
    ]


def text(x, y, value, cls="white", size=None, weight=None):
    attrs = f'class="{cls}"'
    if size:
        attrs += f' font-size="{size}"'
    if weight:
        attrs += f' font-weight="{weight}"'
    return f'<text x="{x}" y="{y}" {attrs}>{escape(str(value))}</text>'


def fingerprint_figure():
    raw = json.loads((ROOT / "results/data/identify_model.txt").read_text().splitlines()[0])
    relation = json.loads((ROOT / "results/data/relations_d16.json").read_text())["structure_d16"]["groups"]
    values = [
        ("Same-model nearest neighbour", raw["accuracy"], "#60d394", f'{raw["hits"]} of {raw["of"]} programs'),
        ("Chance baseline", raw["chance"], "#8492a6", "model mix in this sample"),
    ]
    w, h = 900, 410
    s = svg_start(w, h, "A structural fingerprint can identify the generating model", "Exploratory nearest-neighbour result: 43 of 52 programs matched to a same-model nearest neighbour, compared with a 27 percent chance baseline. Median structural distance was 0.32 within a model and 0.62 between models for the same task and language.")
    s += [text(42, 48, "A structural fingerprint can carry a model signal", "white headline"), text(42, 78, "Exploratory nearest-neighbour result · same task and language", "muted small")]
    chart_x, chart_w = 300, 530
    for i, (label, value, color, note) in enumerate(values):
        y = 138 + i * 84
        s.append(text(42, y + 7, label.replace("\n", " "), "white label"))
        s.append(f'<rect x="{chart_x}" y="{y-17}" width="{chart_w}" height="27" rx="13" fill="#263347"/>')
        s.append(f'<rect x="{chart_x}" y="{y-17}" width="{chart_w*value:.1f}" height="27" rx="13" fill="{color}"/>')
        s.append(text(chart_x + chart_w + 12, y + 5, f'{value:.0%}', "white label", weight="700"))
        s.append(text(chart_x, y + 34, note, "muted small"))
    # Distance comparison uses the D16 result table directly.
    within = relation["1 same task+language, same model (another run)"]["median"]
    between = relation["2 same task+language, different model"]["median"]
    s += [text(42, 325, "Median structural distance", "white label", weight="700"),
          text(42, 354, f"Same model  {within:.2f}", "white small"),
          text(300, 354, f"Different model  {between:.2f}", "white small"),
          text(42, 390, "Permutation p = 0.0005 · exploratory analysis; replication is still needed", "muted small")]
    s.append('</svg>')
    (OUT / "structural-fingerprint.svg").write_text("\n".join(s) + "\n")


def hypotheses_figure():
    # These are the registered D16 outcomes in RESULTS.md, represented as direction counts.
    rows = [
        ("Sonnet vs Codex: early exits", 9, 10, "p = .054 after Holm · inconclusive", "#f2b84b"),
        ("Haiku vs Sonnet: comment volume", 10, 10, "Holm p = .010 · confirmed", "#60d394"),
        ("Haiku vs Sonnet: documented functions", 10, 10, "Holm p = .010 · confirmed", "#60d394"),
        ("Sonnet vs Codex: fan-out", 0, 7, "direction reversed in all 7 testable cells", "#ef7777"),
    ]
    w, h = 900, 480
    s = svg_start(w, h, "The preregistered results did not support the original headline", "Registered findings: the original Sonnet versus Codex early-exit hypothesis was inconclusive after Holm correction; Haiku exceeded Sonnet on comment volume and documented functions in all ten cells; the exploratory fan-out direction reversed in all seven testable cells.")
    s += [text(42, 48, "The result was more specific than the headline", "white headline"), text(42, 78, "Registered comparisons · cells matching the predicted direction, not effect size", "muted small")]
    x0, maxw = 42, 520
    for i, (label, count, total, verdict, color) in enumerate(rows):
        y = 122 + i * 78
        s.append(text(x0, y, label, "white label"))
        s.append(f'<rect x="{x0}" y="{y+12}" width="{maxw}" height="15" rx="7" fill="#263347"/>')
        s.append(f'<rect x="{x0}" y="{y+12}" width="{maxw*count/total:.1f}" height="15" rx="7" fill="{color}"/>')
        s.append(text(x0 + maxw + 18, y + 25, f"{count}/{total}", "white label", weight="700"))
        s.append(text(x0, y + 49, verdict, "muted small"))
    s += [text(42, 463, "The headline Sonnet–Codex family confirmed no hypothesis after correction. Full tests and sensitivities: RESULTS.md.", "muted small")]
    s.append('</svg>')
    (OUT / "registered-findings.svg").write_text("\n".join(s) + "\n")


if __name__ == "__main__":
    fingerprint_figure()
    hypotheses_figure()
