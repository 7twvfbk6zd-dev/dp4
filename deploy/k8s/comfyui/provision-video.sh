#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
COMFYUI_DIR="$WORKSPACE/ComfyUI"
VENV="${COMFYUI_VENV:-/opt/environments/python/comfyui}"
REF="v0.3.68"
MARKER="$WORKSPACE/.comfyui-video-provisioned"

if [[ -f "$MARKER" ]]; then
  echo "Video workspace already provisioned"
  exit 0
fi

cd "$COMFYUI_DIR"
ARCHIVE="$WORKSPACE/.comfyui-$REF.tar.gz"
STAGE="$WORKSPACE/.comfyui-$REF"
BACKUP="$WORKSPACE/.comfyui-preserve"
curl -fL --retry 5 --retry-delay 3 --max-time 300 -o "$ARCHIVE" \
  "https://codeload.github.com/Comfy-Org/ComfyUI/tar.gz/refs/tags/$REF"
rm -rf "$STAGE" "$BACKUP"
mkdir -p "$STAGE" "$BACKUP"
tar -xzf "$ARCHIVE" -C "$STAGE" --strip-components=1
for name in models input output custom_nodes; do
  if [[ -d "$COMFYUI_DIR/$name" ]]; then
    mv "$COMFYUI_DIR/$name" "$BACKUP/$name"
  fi
done
rm -rf "$COMFYUI_DIR"
mv "$STAGE" "$COMFYUI_DIR"
for name in models input output custom_nodes; do
  if [[ -d "$BACKUP/$name" ]]; then
    mv "$BACKUP/$name" "$COMFYUI_DIR/$name"
  fi
done
rm -rf "$BACKUP" "$ARCHIVE"
cd "$COMFYUI_DIR"

cat > "$WORKSPACE/.video-constraints.txt" <<'EOF'
torch==2.4.1+cu121
torchvision==0.19.1+cu121
torchaudio==2.4.1+cu121
EOF

"$VENV/bin/pip" install --no-cache-dir \
  -r requirements.txt \
  -c "$WORKSPACE/.video-constraints.txt" \
  --extra-index-url https://download.pytorch.org/whl/cu121

mkdir -p \
  "$COMFYUI_DIR/models/diffusion_models" \
  "$COMFYUI_DIR/models/text_encoders" \
  "$COMFYUI_DIR/models/vae"

date -u +%Y-%m-%dT%H:%M:%SZ > "$MARKER"
echo "Provisioned ComfyUI $REF"
