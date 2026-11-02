"""Write the README's figures (../figures/*.svg) from the article's own chart code, so both editions show the same charts.

Serves this folder, opens index.html?export in headless Chrome (light theme), and saves each chart as a standalone SVG
with its colours and fonts inlined. Run after build_data.py:  python3 -I article/export_figures.py
"""
import html
import json
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parent / "figures"
srv = subprocess.Popen([sys.executable, "-I", "-m", "http.server", "8791", "--bind", "127.0.0.1"], cwd=HERE,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    time.sleep(1)
    dom = subprocess.run(["google-chrome", "--headless=new", "--disable-gpu", "--window-size=1300,4000",
                          "--virtual-time-budget=15000", "--dump-dom", "http://127.0.0.1:8791/?export"],
                         capture_output=True, text=True, timeout=120).stdout
finally:
    srv.terminate()
i = dom.rindex('<pre id="export">') + len('<pre id="export">')
figs = json.loads(html.unescape(dom[i:dom.index("</pre>", i)]))
OUT.mkdir(exist_ok=True)
for name, svg in figs.items():
    (OUT / f"{name}.svg").write_text('<?xml version="1.0" encoding="UTF-8"?>\n' + svg + "\n")
print(f"wrote {len(figs)} figures to {OUT}: {', '.join(figs)}")
