#!/bin/bash
set -euo pipefail
cd /mapdata1/tools/ds4-main
MODEL='gguf/DeepSeek-V4.1-Flash-1017-IQ2_XXS-Q2_K-imatrix.gguf'
SIZE=$(stat -c %s "$MODEL")
THREADS=${WARM_THREADS:-4}
echo "warming $MODEL into page cache with $THREADS readers..."
for ((i=0; i<THREADS; i++)); do
    SKIP=$((SIZE / THREADS * i))
    if ((i == THREADS - 1)); then
        COUNT=$((SIZE - SKIP))
    else
        COUNT=$((SIZE / THREADS))
    fi
    dd if="$MODEL" of=/dev/null bs=8M iflag=skip_bytes,count_bytes skip=$SKIP count=$COUNT status=none &
done
wait
fincore "$MODEL"
