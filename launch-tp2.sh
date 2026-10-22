#!/usr/bin/env bash
set -euo pipefail
cd /mapdata1/tools/ds4-main
pkill -x ds4-server 2>/dev/null || true
pkill -x ds4 2>/dev/null || true
sleep 3
# A fresh shared-memory object per launch avoids a worker attaching to a
# segment left behind by the previous run.
export DS4_TP_RUN_ID="$(date +%s%N)-$$"
export DS4_TP_GATE_TIMEOUT_MS=${DS4_TP_GATE_TIMEOUT_MS:-30000}
rm -f tp-leader.log tp-worker.log
nohup ./run-tp2-leader.sh > tp-leader.log 2>&1 < /dev/null &
echo $! > tp-leader.pid
sleep 2
nohup ./run-tp2-worker.sh > tp-worker.log 2>&1 < /dev/null &
echo $! > tp-worker.pid
sleep 12
echo "run_id=$DS4_TP_RUN_ID leader_pid=$(cat tp-leader.pid) worker_pid=$(cat tp-worker.pid)"
pgrep -x ds4-server || true