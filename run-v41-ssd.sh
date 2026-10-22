#!/bin/bash
cd /mapdata1/tools/ds4-main
MODEL='gguf/DeepSeek-V4.1-Flash-1017-IQ2_XXS-Q2_K-imatrix.gguf'
export LD_LIBRARY_PATH=/mapdata1/tools/cuda-12.8/lib64
unset DS4_CUDA_NO_DIRECT_IO DS4_CUDA_KEEP_MODEL_PAGES DS4_CUDA_MMAP_STREAM_COPY
exec ./ds4 --cuda --ssd-streaming --ctx 2048 --ssd-streaming-cache-experts 1024 --prefill-chunk 512 -m "$MODEL" "$@"
