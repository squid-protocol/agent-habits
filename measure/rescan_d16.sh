#!/bin/bash
# D16: rescan the runs whose cell-language source the saturation gate blocked, with the gate's bound raised to the
# engine's own lenient bound (DECLARED_PORT_MAX_LINE_LENGTH = 5000) for those runs only. Same pinned engine, no code
# edit: APERTURE_CONFIG["MAX_LINE_LENGTH"] is set before galaxyscope imports. Outputs: scans/confirm-d16/<run>.
set -u
C=/home/joe/gitgalaxy/chess-study/confirm
for r in chess-c-codex-r1 chess-rust-codex-r1 chess-rust-codex-r2 sat-c-codex-r1; do
  out=$C/scans/confirm-d16/$r; rm -rf "$out"; mkdir -p "$out"
  ( cd "$out" && PYTHONPATH="$C/engine" GITGALAXY_LICENSE_KEY=COMMUNITY_FREE_TIER GITGALAXY_DISABLE_GIT_HISTORY=1 \
    /home/joe/gitgalaxy/venv/bin/python - "$C/scan_src/confirm/$r" "$out/" > "$out/scan.log" 2>&1 <<'EOF'
import runpy, sys
import gitgalaxy.standards.gitgalaxy_config as cfg
cfg.APERTURE_CONFIG["MAX_LINE_LENGTH"] = 5000
src, out = sys.argv[1], sys.argv[2]
sys.argv = ["galaxyscope", src, "--output", out]
runpy.run_module("gitgalaxy.galaxyscope", run_name="__main__")
EOF
  )
  echo "$r rc=$?"
done
