#!/bin/bash
cd /mapdata1/tools/ds4-main
MODEL='gguf/DeepSeek-V4.1-Flash-1017-IQ2_XXS-Q2_K-imatrix.gguf'
export LD_LIBRARY_PATH=/mapdata1/tools/cuda-12.8/lib64
export DS4_CUDA_NO_DIRECT_IO=1
export DS4_CUDA_KEEP_MODEL_PAGES=1
export DS4_CUDA_LOAD_THREADS=6
export DS4_CUDA_NO_ATTN_Q_B_F16_CACHE=1
export DS4_CUDA_NO_ATTENTION_OUTPUT_F16_CACHE=1
exec ./ds4-server --cuda --ssd-streaming --ctx 2048 --ssd-streaming-cache-experts 1024 --prefill-chunk 512 --host 127.0.0.1 --port 18080 -m "$MODEL" "$@"
