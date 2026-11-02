#!/bin/bash
# D8: wait for the in-progress unpinned run to finish, then run two pinned lanes in parallel:
# Claude on cores 0-2 (N_CLAUDE runs), Codex on cores 3-5 (N_CODEX runs). Each lane: one run at a time, frozen order.
#   setsid nohup bash lanes.sh 4 4 > ../lanes.log 2>&1 < /dev/null &
N_CLAUDE=${1:?}; N_CODEX=${2:?}
cd "$(dirname "$0")" || exit 9
while pgrep -f "run.py --next" >/dev/null; do sleep 20; done
echo "== $(date -u +%FT%TZ) previous run finished; starting lanes"
AH_CPUSET=0-2 bash batch_n.sh "$N_CLAUDE" 0 > ../lane_claude.log 2>&1 &
AH_CPUSET=3-5 bash batch_n.sh 0 "$N_CODEX" > ../lane_codex.log 2>&1 &
wait
echo "== $(date -u +%FT%TZ) both lanes done"
