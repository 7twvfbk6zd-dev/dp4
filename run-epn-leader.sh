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
export DS4_LOCK_FILE=/tmp/ds4-epn-leader.lock
export DS4_TP_SHM=1
export DS4_TP_WORLD=${DS4_TP_WORLD:-4}
export DS4_TP_EXPERT_ONLY=1
export DS4_TP_GATE_TIMEOUT_MS=${DS4_TP_GATE_TIMEOUT_MS:-30000}
export DS4_METAL_DISABLE_V41_WIDE_CHUNK=1
export DS4_METAL_DISABLE_V41_8K_CHUNK=1
MODEL=${DS4_MODEL:-/mapdata1/tools/ds4-main/gguf/DeepSeek-V4.1-Flash-1017-IQ2_XXS-Q2_K-imatrix.gguf}
VISION=${DS4_VISION:-/mapdata1/tools/ds4-main/gguf/DeepSeek-V4.1-Flash-Vision.gguf}
CTX=${DS4_CTX:-32768}
CACHE=${DS4_EXPERT_CACHE:-512}
PREFILL=${DS4_PREFILL:-2048}
exec ./ds4-server --cuda --ssd-streaming --ctx "$CTX"   --ssd-streaming-cache-experts "$CACHE" --prefill-chunk "$PREFILL" -m "$MODEL"   --vision "$VISION" --tensor-parallel --role coordinator --listen 127.0.0.1 19090   --host ${DS4_HOST:-0.0.0.0} --port 18080 "$@"
