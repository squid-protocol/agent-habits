"""The public edition for the GitGalaxy docs wiki: the interactive article plus a Markdown text edition made from README.md.

  python3 -I article/build_wiki.py <gitgalaxy checkout>/docs/wiki/museum-of-code

writes  agent-habits/                 index.html (complete document: search, social and schema.org metadata), data.json,
                                      wiring/*.json, figures/*.svg, collage.png (1200x600 social card of the hero map)
        every-model-has-a-tell.md     the text edition (README with repository links made absolute)
"""
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
REPO = "https://github.com/squid-protocol/agent-habits"
SLUG, TEXT = "agent-habits", "every-model-has-a-tell.md"
URL = f"https://squid-protocol.github.io/gitgalaxy/museum-of-code/{SLUG}/"
TITLE = "Every Model Has a Tell"
DESC = ("Three AI coding models (Claude Sonnet, Claude Haiku and OpenAI Codex) built programs for the same ten jobs, 60 in "
        "all. Measured by structure alone, each model kept its own handwriting. An interactive study by Joe Esquibel, made "
        "with the GitGalaxy code-scanning engine.")


def rep(s, a, b):
    assert s.count(a) == 1, (s.count(a), a[:80])
    return s.replace(a, b)


def interactive(out: Path) -> None:
    page = (HERE / "index.html").read_text()
    ld = {"@context": "https://schema.org", "@type": "Article", "headline": f"{TITLE}: three AI models, the same ten jobs",
          "description": DESC, "author": {"@type": "Person", "name": "Joe Esquibel"}, "datePublished": "2026-11-02",
          "url": URL, "image": URL + "collage.png", "isBasedOn": REPO,
          "publisher": {"@type": "Organization", "name": "GitGalaxy", "url": "https://github.com/squid-protocol/gitgalaxy"}}
    meta = f"""<meta name="author" content="Joe Esquibel">
<link rel="canonical" href="{URL}">
<meta property="og:type" content="article">
<meta property="og:title" content="{TITLE}">
<meta property="og:description" content="{DESC}">
<meta property="og:url" content="{URL}">
<meta property="og:image" content="{URL}collage.png">
<meta name="twitter:card" content="summary_large_image">
<script type="application/ld+json">{json.dumps(ld)}</script>
"""
    page = re.sub(r'<meta name="description" content="[^"]*">', f'<meta name="description" content="{DESC}">', page)
    page = rep(page, "<title>Every Model Has a Tell</title>\n", "<title>Every Model Has a Tell</title>\n" + meta)
    page = rep(page, '<a href="data.json" id="dl">', '<a href="data.json" id="dl" download="agent-habits-data.json">')
    page = rep(page, '<p class="do">Pick a program to see its habits and its line-up of look-alikes.',
               f'<p class="do">The <a href="../{TEXT[:-3]}/">text edition</a> has every number without the interactives. Pick a program to see its habits and its line-up of look-alikes.')
    out.mkdir(parents=True, exist_ok=True)
    (out / "index.html").write_text(page)
    shutil.copy(HERE / "data.json", out / "data.json")
    for sub, src in (("wiring", HERE / "wiring"), ("figures", ROOT / "figures")):
        (out / sub).mkdir(exist_ok=True)
        for f in sorted(src.iterdir()):
            shutil.copy(f, out / sub / f.name)


def collage(out: Path) -> None:
    """1200x600 social card: the title over the hero map."""
    svg = (ROOT / "figures" / "map.svg").read_text().split("\n", 1)[1]
    card = f"""<!doctype html><meta charset="utf-8"><style>
body{{margin:0;width:1200px;height:600px;background:#f6f7f8;font-family:Archivo,Helvetica,Arial,sans-serif;overflow:hidden}}
h1{{margin:0;padding:34px 48px 0;font-size:64px;font-weight:900;letter-spacing:-2px;color:#15202b}}
p{{margin:6px 48px 0;font-size:24px;color:#4a5663}} svg{{display:block;width:1120px;height:auto;margin:6px auto 0}}</style>
<h1>{TITLE}</h1><p>Three AI models, the same ten jobs, 60 programs: the shape of the code gave each model away.</p>{svg}"""
    with tempfile.TemporaryDirectory() as td:
        f = Path(td) / "card.html"
        f.write_text(card)
        subprocess.run(["google-chrome", "--headless=new", "--disable-gpu", "--hide-scrollbars", "--window-size=1200,600",
                        f"--screenshot={out / 'collage.png'}", f.as_uri()], capture_output=True, timeout=60)


def text_edition(museum: Path) -> None:
    md = (ROOT / "README.md").read_text()
    head, body = md.split("\n", 1)

    def fix(m):
        link = m.group(1)
        if link.startswith(("http", "#", "mailto:")):
            return m.group(0)
        if link.startswith("figures/") and link.endswith(".svg"):
            return f"]({SLUG}/{link})"
        path, _, frag = link.partition("#")
        kind = "tree" if path.endswith("/") or "." not in Path(path).name else "blob"
        return f"]({REPO}/{kind}/main/{path.rstrip('/')}{'#' + frag if frag else ''})"
    body = re.sub(r"\]\(([^)]+)\)", fix, body)
    body, n = re.subn(r"\*By Joe Esquibel, with the GitGalaxy code-scanning engine · November 2026\.\*.*?\n\n",
                      f"*By Joe Esquibel, with the GitGalaxy code-scanning engine · November 2026.* Every number links to the file it "
                      f"came from in the study's repository, [{REPO.split('//')[1]}]({REPO}), which holds everything needed to "
                      f"check it.\n\n", body, count=1, flags=re.S)
    assert n == 1
    body, n = re.subn(r"!\[Programs group by language first;.*?\n\n\*Programs group by language first;.*?\*\n\n", "", body, count=1, flags=re.S)
    assert n == 1  # the hero map is already the social card at the top
    body = rep(body, "Everything needed to corroborate the numbers above is in this repository.",
               f"Everything needed to corroborate the numbers above is in the [study's repository]({REPO}).")
    body = rep(body, "the scripts read them by absolute path. Then", "the scripts read them by absolute path. Then, in that repository,")
    body = re.sub(r"\n### The interactive edition\n.*?(?=\n## )", "\n", body, flags=re.S)
    front = f'---\ndescription: "{DESC}"\n---\n'
    intro = (f"\n> **This is the text edition.** The full article is interactive: hover any program, re-sort the distance map,\n"
             f"> draw the wiring for any job, and open a card for each of the 60 programs.\n"
             f"> **[Open the interactive article →]({SLUG}/index.html)**\n\n"
             f"[![{TITLE}: a map of the 59 programs GitGalaxy could read, grouped by language and coloured by model]({SLUG}/collage.png)]({SLUG}/index.html)\n")
    (museum / TEXT).write_text(front + head + "\n" + intro + body)


if __name__ == "__main__":
    museum = Path(sys.argv[1])
    out = museum / SLUG
    interactive(out)
    collage(out)
    text_edition(museum)
    print(f"wrote {out} ({len(list(out.rglob('*')))} files) and {museum / TEXT}")
