#!/bin/bash
# Second batch (owner, 2026-11-01): the remaining 7 Claude and 7 Codex runs, in the D8 pinned lanes.
# Claude lane starts at once (cores 0-2); the Codex lane waits for the first batch's Codex lane to finish (cores 3-5).
cd "$(dirname "$0")" || exit 9
AH_CPUSET=0-2 bash batch_n.sh 7 0 > ../lane2_claude.log 2>&1 &
( while pgrep -f "batch_n.sh 0 4" >/dev/null; do sleep 30; done
  echo "== $(date -u +%FT%TZ) first Codex lane finished; starting the second" > ../lane2_codex.log
  AH_CPUSET=3-5 bash batch_n.sh 0 7 >> ../lane2_codex.log 2>&1 ) &
wait
echo "== $(date -u +%FT%TZ) batch 2 done"
