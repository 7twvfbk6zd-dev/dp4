#!/bin/bash
set -uo pipefail
MODEL=${DS4_MODEL:-/models/DeepSeek-V4.1-Flash-1017-IQ2_XXS-Q2_K-imatrix.gguf}
VISION=${DS4_VISION:-/models/DeepSeek-V4.1-Flash-Vision.gguf}
CTX=${DS4_CTX:-131072}
CACHE=${DS4_EXPERT_CACHE:-512}
PREFILL=${DS4_PREFILL:-2048}
WORLD=${DS4_TP_WORLD:-4}
BATCHED=${DS4_BATCHED_SESSION:-0}
CORS=${DS4_CORS:-1}
VIS=${CUDA_VISIBLE_DEVICES:-0,1,2,3}
pick() { echo "$VIS" | cut -d, -f"$1"; }

export LD_LIBRARY_PATH=/opt/ds4/lib
export DS4_CUDA_NO_DIRECT_IO=1
export DS4_CUDA_KEEP_MODEL_PAGES=1
export DS4_CUDA_LOAD_THREADS=6
export DS4_CUDA_NO_ATTN_Q_B_F16_CACHE=1
export DS4_CUDA_NO_ATTENTION_OUTPUT_F16_CACHE=1
export DS4_TP_SHM=1
export DS4_TP_WORLD="$WORLD"
export DS4_TP_EXPERT_ONLY=1
export DS4_TP_GATE_TIMEOUT_MS=60000
export DS4_METAL_DISABLE_V41_WIDE_CHUNK=1
export DS4_METAL_DISABLE_V41_8K_CHUNK=1
export DS4_TP_RUN_ID="$(date +%s%N)-$$"

COMMON=(--cuda --ssd-streaming --ctx "$CTX" --ssd-streaming-cache-experts "$CACHE" --prefill-chunk "$PREFILL" -m "$MODEL" --vision "$VISION" --tensor-parallel)
LEADER_EXTRA=()
if [ "$CORS" -gt 0 ]; then
  LEADER_EXTRA+=(--cors)
fi
if [ "$BATCHED" -gt 0 ]; then
  LEADER_EXTRA+=(--batched-session "$BATCHED")
fi

cleanup() { kill $(jobs -p) 2>/dev/null; wait 2>/dev/null; }
trap cleanup TERM INT

echo "ds4: starting rank 0 on gpu $(pick 1) (batched_session=${BATCHED} cors=${CORS})"
CUDA_VISIBLE_DEVICES=$(pick 1) DS4_LOCK_FILE=/tmp/ds4-leader.lock \
  /opt/ds4/ds4-server "${COMMON[@]}" "${LEADER_EXTRA[@]}" --role coordinator --listen 127.0.0.1 19090 --host 0.0.0.0 --port 18080 &
sleep 3

slot=2
while [ "$slot" -le "$WORLD" ]; do
  echo "ds4: starting worker rank $((slot-1)) on gpu $(pick "$slot")"
  CUDA_VISIBLE_DEVICES=$(pick "$slot") DS4_LOCK_FILE=/tmp/ds4-worker-$slot.lock \
    /opt/ds4/ds4 "${COMMON[@]}" --role worker --coordinator 127.0.0.1 19090 &
  slot=$((slot+1))
  sleep 1
done

wait -n
echo "ds4: a rank exited, shutting down pod"
cleanup
