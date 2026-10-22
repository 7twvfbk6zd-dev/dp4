#!/usr/bin/env bash
set -euo pipefail

ROOT="${COMFYUI_MODELS_DIR:-/mapdata1/comfyui/ComfyUI/models}"
MS="https://modelscope.cn/models"

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
  local dir="$1" name="$2" url="$3"
  mkdir -p "$dir"
  if [[ -s "$dir/$name" ]]; then
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
  echo "DONE  $name ($(du -h "$dir/$name" | cut -f1))"
}

download "$ROOT/checkpoints" "sd_xl_base_1.0.safetensors" \
  "$MS/AI-ModelScope/stable-diffusion-xl-base-1.0/resolve/master/sd_xl_base_1.0.safetensors"
download "$ROOT/vae" "sdxl_vae.safetensors" \
  "$MS/AI-ModelScope/sdxl-vae-fp16-fix/resolve/master/sdxl_vae.safetensors"
download "$ROOT/controlnet" "controlnet-canny-sdxl-fp16.safetensors" \
  "$MS/AI-ModelScope/controlnet-canny-sdxl-1.0/resolve/master/diffusion_pytorch_model.fp16.safetensors"
download "$ROOT/controlnet" "controlnet-depth-sdxl-fp16.safetensors" \
  "$MS/AI-ModelScope/controlnet-depth-sdxl-1.0/resolve/master/diffusion_pytorch_model.fp16.safetensors"
download "$ROOT/ipadapter" "ip-adapter-plus-face_sdxl_vit-h.safetensors" \
  "$MS/AI-ModelScope/IP-Adapter/resolve/master/sdxl_models/ip-adapter-plus-face_sdxl_vit-h.safetensors"
download "$ROOT/ipadapter" "ip-adapter-plus_sdxl_vit-h.safetensors" \
  "$MS/AI-ModelScope/IP-Adapter/resolve/master/sdxl_models/ip-adapter-plus_sdxl_vit-h.safetensors"
download "$ROOT/clip_vision" "CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors" \
  "$MS/AI-ModelScope/CLIP-ViT-H-14-laion2B-s32B-b79K/resolve/master/model.safetensors"
download "$ROOT/loras" "sd_xl_offset_example-lora_1.0.safetensors" \
  "$MS/AI-ModelScope/stable-diffusion-xl-base-1.0/resolve/master/sd_xl_offset_example-lora_1.0.safetensors"

echo "ALL_DONE"
