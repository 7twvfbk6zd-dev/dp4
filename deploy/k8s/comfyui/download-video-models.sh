#!/usr/bin/env bash
set -euo pipefail

ROOT="${COMFYUI_VIDEO_MODELS_DIR:-/mapdata1/comfyui-video/ComfyUI/models}"
MS="https://modelscope.cn/models/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/master/split_files"

ARIA2C="${ARIA2C:-}"
if [[ -z "$ARIA2C" ]]; then
  ARIA2C="$(command -v aria2c || true)"
fi
if [[ -z "$ARIA2C" && -x /mapdata1/tools/aria2/usr/bin/aria2c ]]; then
  ARIA2C=/mapdata1/tools/aria2/usr/bin/aria2c
  export LD_LIBRARY_PATH=/mapdata1/tools/aria2/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
fi
if [[ -z "$ARIA2C" ]] && ! command -v curl >/dev/null 2>&1; then
  echo "ERROR: install aria2c or curl first" >&2
  exit 1
fi

download() {
  local dir="$1" name="$2" url="$3" expected="$4"
  mkdir -p "$dir"
  if [[ -s "$dir/$name" && "$(stat -c%s "$dir/$name")" == "$expected" ]]; then
    echo "SKIP  $name ($(du -h "$dir/$name" | cut -f1))"
    return 0
  fi
  echo "START $name"
  if [[ -n "$ARIA2C" ]]; then
    "$ARIA2C" -x 8 -s 8 -k 1M -c --file-allocation=none --max-tries=10 \
      --retry-wait=5 --console-log-level=warn --summary-interval=30 \
      -d "$dir" -o "$name" "$url"
  else
    curl -fL --retry 10 --retry-delay 5 -C - -o "$dir/$name" "$url"
  fi
  local actual
  actual="$(stat -c%s "$dir/$name")"
  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: $name has $actual bytes, expected $expected" >&2
    exit 1
  fi
  echo "DONE  $name ($(du -h "$dir/$name" | cut -f1))"
}

download "$ROOT/diffusion_models" "wan2.2_ti2v_5B_fp16.safetensors" \
  "$MS/diffusion_models/wan2.2_ti2v_5B_fp16.safetensors" 9999658848
download "$ROOT/text_encoders" "umt5_xxl_fp8_e4m3fn_scaled.safetensors" \
  "$MS/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors" 6735906897
download "$ROOT/vae" "wan2.2_vae.safetensors" \
  "$MS/vae/wan2.2_vae.safetensors" 1409400960

echo "ALL_DONE"
