#!/usr/bin/env bash
set -euo pipefail
GPU=${1:?gpu index}
SLOT=${2:?slot}
shift 2
cd /mapdata1/tools/ds4-main
export LD_LIBRARY_PATH=/mapdata1/tools/cuda-12.8/lib64:${LD_LIBRARY_PATH:-}
export CUDA_VISIBLE_DEVICES=$GPU
export DS4_CUDA_NO_DIRECT_IO=1
export DS4_CUDA_KEEP_MODEL_PAGES=1
export DS4_CUDA_LOAD_THREADS=6
export DS4_CUDA_NO_ATTN_Q_B_F16_CACHE=1
export DS4_CUDA_NO_ATTENTION_OUTPUT_F16_CACHE=1
export DS4_LOCK_FILE=/tmp/ds4-epn-worker-$SLOT.lock
export DS4_TP_SHM=1
export DS4_TP_WORLD=${DS4_TP_WORLD:-4}
export DS4_TP_EXPERT_ONLY=1
export DS4_TP_GATE_TIMEOUT_MS=${DS4_TP_GATE_TIMEOUT_MS:-30000}
MODEL=/mapdata1/tools/ds4-main/gguf/DeepSeek-V4.1-Flash-1017-IQ2_XXS-Q2_K-imatrix.gguf
CTX=${DS4_CTX:-32768}
CACHE=${DS4_EXPERT_CACHE:-768}
PREFILL=${DS4_PREFILL:-2048}
exec ./ds4 --cuda --ssd-streaming --ctx "$CTX"   --ssd-streaming-cache-experts "$CACHE" --prefill-chunk "$PREFILL" -m "$MODEL"   --tensor-parallel --role worker --coordinator 127.0.0.1 19090 "$@"
