#!/bin/bash
# Scan every confirmation run and the exploratory set with the pinned engine (PREREGISTRATION.md section 6).
# Each repo is copied without .git and target/ (Rust build output) and scanned with git history disabled.
# Scans only: no registered measure is computed here.
#   setsid nohup bash scan_all.sh > scan_all.log 2>&1 < /dev/null &
set -u
C=/home/joe/gitgalaxy/chess-study/confirm
ENGINE=$C/engine
PY=/home/joe/gitgalaxy/venv/bin/python
SRC=$C/scan_src; OUT=$C/scans
mkdir -p "$SRC" "$OUT"
list=$C/scan_list.txt; : > "$list"
for d in $C/runs/*/; do r=$(basename "$d"); echo "confirm $r $d/repo" >> "$list"; done
for r in agentic-chessengine-c-cc agentic-chessengine-c-codex agentic-chessengine-cpp-cc agentic-chessengine-cpp-codex \
         agentic-chessengine-java-cc agentic-chessengine-java-codex agentic-chessengine-python-cc agentic-chessengine-python-codex \
         agentic-chessengine-rust-cc agentic-chessengine-rust-codex agentic-chessengine-cobol-cc agentic-chessengine-cobol-codex; do
  echo "explore $r /home/joe/gitgalaxy/chess-study/repos/$r" >> "$list"; done
for r in agentic-cobol-compress-cc agentic-cobol-compress agentic-cobol-doom-cc agentic-cobol-doom-codex \
         agentic-cobol-pygame-cc agentic-cobol-pygame agentic-cobol-sat-cc agentic-cobol-sat-codex; do
  echo "explore $r /home/joe/gitgalaxy/cobol-agents/repos/$r" >> "$list"; done
scan_one() {
  set -u
  kind=$1; r=$2; repo=$3
  dst=$SRC/$kind/$r; out=$OUT/$kind/$r
  [ -f "$out/done" ] && { echo "skip $kind/$r"; return; }
  rm -rf "$dst" "$out"; mkdir -p "$dst" "$out"
  ( cd "$repo" && tar --exclude=./.git --exclude=./target -cf - . ) | tar -xf - -C "$dst"
  start=$(date +%s)
  ( cd "$out" && PYTHONPATH="$ENGINE" GITGALAXY_LICENSE_KEY=COMMUNITY_FREE_TIER GITGALAXY_DISABLE_GIT_HISTORY=1 \
      timeout 1800 nice "$PY" -m gitgalaxy.galaxyscope "$dst" --output "$out/" > "$out/scan.log" 2>&1 )
  rc=$?
  echo "$rc" > "$out/rc"; [ $rc = 0 ] && touch "$out/done"
  echo "scanned $kind/$r rc=$rc $(( $(date +%s) - start ))s"
}
export -f scan_one; export SRC OUT ENGINE PY
wc -l < "$list"
xargs -P 3 -L 1 bash -c 'scan_one "$0" "$1" "$2"' < "$list"
echo "== $(date -u +%FT%TZ) scans done: $(find $OUT -name done | wc -l) of $(wc -l < $list)"
