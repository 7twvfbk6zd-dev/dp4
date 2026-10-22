#!/usr/bin/env bash
set -euo pipefail
cd /mapdata1/tools/ds4-main
pkill -x ds4-server 2>/dev/null || true
pkill -x ds4 2>/dev/null || true
sleep 3
export DS4_TP_RUN_ID="$(date +%s%N)-$$"
export DS4_TP_GATE_TIMEOUT_MS=${DS4_TP_GATE_TIMEOUT_MS:-30000}
rm -f tp-leader.log tp-worker1.log tp-worker2.log tp-worker3.log
nohup ./run-ep4-leader.sh > tp-leader.log 2>&1 < /dev/null &
echo $! > tp-leader.pid
sleep 2
for slot in 1 2 3; do
  nohup ./run-ep4-worker.sh "$slot" "$slot" > "tp-worker$slot.log" 2>&1 < /dev/null &
  echo $! > "tp-worker$slot.pid"
  sleep 1
done
sleep 20
echo "run_id=$DS4_TP_RUN_ID"
echo "leader_pid=$(cat tp-leader.pid) workers=$(cat tp-worker1.pid),$(cat tp-worker2.pid),$(cat tp-worker3.pid)"
pgrep -a -x ds4-server || true
pgrep -a -x ds4 || true