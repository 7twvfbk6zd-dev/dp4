#!/usr/bin/env bash
set -euo pipefail
if kubectl get deploy ds4 -n ds4 >/dev/null 2>&1; then
  echo "ds4 is managed by k8s (deploy/ds4). Refusing to start host processes." >&2
  echo "Use: kubectl scale deploy/ds4 -n ds4 --replicas=1" >&2
  exit 1
fi
cd /mapdata1/tools/ds4-main
WORLD=${DS4_TP_WORLD:-4}
export DS4_TP_WORLD=$WORLD
pkill -x ds4-server 2>/dev/null || true
pkill -x ds4 2>/dev/null || true
sleep 3
export DS4_TP_RUN_ID="$(date +%s%N)-$$"
export DS4_TP_GATE_TIMEOUT_MS=${DS4_TP_GATE_TIMEOUT_MS:-60000}
rm -f tp-leader.log tp-worker*.log
nohup ./run-epn-leader.sh > tp-leader.log 2>&1 < /dev/null &
echo $! > tp-leader.pid
sleep 2
slot=1
while [ "$slot" -lt "$WORLD" ]; do
  nohup ./run-epn-worker.sh "$slot" "$slot" > "tp-worker$slot.log" 2>&1 < /dev/null &
  echo $! > "tp-worker$slot.pid"
  slot=$((slot + 1))
  sleep 1
done
sleep 20
echo "world=$WORLD run_id=$DS4_TP_RUN_ID"
echo "leader_pid=$(cat tp-leader.pid)"
pgrep -a -x ds4-server || true
pgrep -c -x ds4 || true