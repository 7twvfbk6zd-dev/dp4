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
git remote set-url origin https://github.com/Comfy-Org/ComfyUI.git
git fetch --depth 1 origin "refs/tags/$REF:refs/tags/$REF"
git checkout -f "$REF"

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
