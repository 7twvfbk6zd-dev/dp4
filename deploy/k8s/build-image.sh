#!/usr/bin/env bash
# Build the container image from the binaries already built in the repo root.
set -euo pipefail
cd "$(dirname "$0")"
REPO_ROOT=$(cd ../.. && pwd)
CUDA_LIB_DIR=${CUDA_LIB_DIR:-/mapdata1/tools/cuda-12.8/lib64}
IMAGE=${IMAGE:-ds4:v2}

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp "$REPO_ROOT/ds4-server" "$REPO_ROOT/ds4" "$STAGE/"
mkdir -p "$STAGE/lib"
for f in libcudart.so.12 libcublas.so.12 libcublasLt.so.12 libnvJitLink.so.12; do
  cp -L "$CUDA_LIB_DIR/$f" "$STAGE/lib/"
done
# host libstdc++ is newer than ubuntu 20.04's (GLIBCXX_3.4.29 required)
cp -L "$(readlink -f /lib/x86_64-linux-gnu/libstdc++.so.6)" "$STAGE/lib/libstdc++.so.6"

cp Dockerfile entrypoint.sh "$STAGE/"
docker build -t "$IMAGE" "$STAGE"
echo "built $IMAGE"