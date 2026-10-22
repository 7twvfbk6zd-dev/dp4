#!/usr/bin/env bash
set -euo pipefail
cd /mapdata1/tools/ds4-main
export LD_LIBRARY_PATH=/mapdata1/tools/cuda-12.8/lib64:${LD_LIBRARY_PATH:-}
export CUDA_VISIBLE_DEVICES=0
export DS4_CUDA_NO_DIRECT_IO=1
export DS4_CUDA_KEEP_MODEL_PAGES=1
export DS4_CUDA_LOAD_THREADS=6
export DS4_CUDA_NO_ATTN_Q_B_F16_CACHE=1
export DS4_CUDA_NO_ATTENTION_OUTPUT_F16_CACHE=1
export DS4_LOCK_FILE=/tmp/ds4-ep4-leader.lock
export DS4_TP_SHM=1
export DS4_TP_WORLD=4
export DS4_TP_EXPERT_ONLY=1
export DS4_TP_GATE_TIMEOUT_MS=${DS4_TP_GATE_TIMEOUT_MS:-30000}
MODEL=/mapdata1/tools/ds4-main/gguf/DeepSeek-V4.1-Flash-1017-IQ2_XXS-Q2_K-imatrix.gguf
exec ./ds4-server --cuda --ssd-streaming --ctx 2048 \
  --ssd-streaming-cache-experts 1024 --prefill-chunk 512 -m "$MODEL" \
  --tensor-parallel --role coordinator --listen 127.0.0.1 19090 \
  --host 127.0.0.1 --port 18080 "$@"