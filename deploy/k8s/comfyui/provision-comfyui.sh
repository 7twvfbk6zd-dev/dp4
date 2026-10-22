#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
INSTANCE="${COMFYUI_INSTANCE:-main}"
REF="${COMFYUI_REF:-v0.42.1}"
COMFYUI_DIR="$WORKSPACE/ComfyUI"
VENV="${COMFYUI_VENV:-/opt/environments/python/comfyui}"
MARKER="$WORKSPACE/.comfyui-${INSTANCE}-provisioned"
ROLLBACK_DIR="$WORKSPACE/.rollback"
CONSTRAINTS="$WORKSPACE/.comfyui-${INSTANCE}-constraints.txt"
REF_VERSION="${REF#v}"
PRESERVE=(models input output custom_nodes user)

if [[ "$COMFYUI_DIR" != "$WORKSPACE/ComfyUI" ]]; then
  echo "Refusing unexpected ComfyUI path: $COMFYUI_DIR" >&2
  exit 1
fi

normalize_version() {
  printf '%s' "${1#v}"
}

source_version() {
  if [[ -f "$COMFYUI_DIR/comfyui_version.py" ]]; then
    sed -n 's/^__version__ = "\(.*\)"/\1/p' "$COMFYUI_DIR/comfyui_version.py" | head -n 1
  elif [[ -f "$MARKER" ]]; then
    sed -n 's/^ref=//p' "$MARKER" | head -n 1
  elif [[ -n "${COMFYUI_BUILD_REF:-}" ]]; then
    printf '%s\n' "$COMFYUI_BUILD_REF"
  else
    printf 'unknown\n'
  fi
}

requirements_hash() {
  if [[ -f "$COMFYUI_DIR/requirements.txt" ]]; then
    sha256sum "$COMFYUI_DIR/requirements.txt" | cut -d' ' -f1
  else
    printf 'missing\n'
  fi
}

marker_value() {
  local key="$1"
  [[ -f "$MARKER" ]] || return 0
  sed -n "s/^${key}=//p" "$MARKER" | head -n 1
}

dependencies_ready() {
  "$VENV/bin/python" - <<'PY' >/dev/null 2>&1
import av
import comfy_aimdo
import comfy_kitchen
import torch
PY
}

CURRENT_VERSION="$(normalize_version "$(source_version)")"
CURRENT_HASH="$(requirements_hash)"

if [[ "$CURRENT_VERSION" == "$REF_VERSION" ]] \
  && [[ "$(marker_value ref)" == "$REF" ]] \
  && [[ "$(marker_value requirements_sha256)" == "$CURRENT_HASH" ]] \
  && dependencies_ready; then
  echo "ComfyUI $REF is already provisioned for $INSTANCE"
  exit 0
fi

if [[ "$CURRENT_VERSION" != "$REF_VERSION" ]]; then
  ARCHIVE="$WORKSPACE/.comfyui-${INSTANCE}-${REF}.tar.gz"
  STAGE="$WORKSPACE/.comfyui-${INSTANCE}-${REF}.stage"
  BACKUP="$WORKSPACE/.comfyui-${INSTANCE}-preserve"

  echo "Replacing ComfyUI $CURRENT_VERSION with $REF for $INSTANCE"
  rm -rf "$STAGE" "$BACKUP"
  mkdir -p "$STAGE" "$BACKUP" "$ROLLBACK_DIR"
  curl -fL --retry 5 --retry-delay 3 --max-time 600 -o "$ARCHIVE" \
    "https://codeload.github.com/Comfy-Org/ComfyUI/tar.gz/refs/tags/$REF"
  tar -xzf "$ARCHIVE" -C "$STAGE" --strip-components=1
  if [[ ! -f "$STAGE/main.py" ]]; then
    echo "Downloaded ComfyUI archive is incomplete" >&2
    exit 1
  fi

  if [[ -d "$COMFYUI_DIR" ]]; then
    BACKUP_TAR="$ROLLBACK_DIR/ComfyUI-${INSTANCE}-${CURRENT_VERSION}-$(date -u +%Y%m%dT%H%M%SZ).tar.gz"
    tar -czf "$BACKUP_TAR" \
      --exclude='ComfyUI/models' \
      --exclude='ComfyUI/input' \
      --exclude='ComfyUI/output' \
      --exclude='ComfyUI/custom_nodes' \
      --exclude='ComfyUI/user' \
      --exclude='ComfyUI/*.log' \
      --exclude='ComfyUI/__pycache__' \
      -C "$WORKSPACE" ComfyUI
    echo "Created rollback archive: $BACKUP_TAR"
  fi

  for name in "${PRESERVE[@]}"; do
    if [[ -e "$COMFYUI_DIR/$name" ]]; then
      mv "$COMFYUI_DIR/$name" "$BACKUP/$name"
    fi
  done
  rm -rf "$COMFYUI_DIR"
  mv "$STAGE" "$COMFYUI_DIR"
  for name in "${PRESERVE[@]}"; do
    if [[ -e "$BACKUP/$name" ]]; then
      mv "$BACKUP/$name" "$COMFYUI_DIR/$name"
    fi
  done
  rm -rf "$BACKUP" "$ARCHIVE"
fi

cat > "$CONSTRAINTS" <<'EOF'
torch==2.4.1+cu121
torchvision==0.19.1+cu121
torchaudio==2.4.1+cu121
EOF

echo "Installing ComfyUI $REF dependencies for $INSTANCE"
PIP_DISABLE_PIP_VERSION_CHECK=1 "$VENV/bin/pip" install --no-cache-dir \
  -r "$COMFYUI_DIR/requirements.txt" \
  -c "$CONSTRAINTS" \
  --extra-index-url https://download.pytorch.org/whl/cu121

if ! "$VENV/bin/pip" check; then
  echo "WARNING: pip check reported dependency conflicts" >&2
fi

if ! dependencies_ready; then
  echo "Required ComfyUI imports failed after dependency installation" >&2
  exit 1
fi

INSTALLED_VERSION="$(normalize_version "$(source_version)")"
if [[ "$INSTALLED_VERSION" != "$REF_VERSION" ]]; then
  echo "Installed ComfyUI version is $INSTALLED_VERSION, expected $REF_VERSION" >&2
  exit 1
fi

mkdir -p \
  "$COMFYUI_DIR/models/diffusion_models" \
  "$COMFYUI_DIR/models/text_encoders" \
  "$COMFYUI_DIR/models/vae"

cat > "$MARKER" <<EOF
ref=$REF
requirements_sha256=$(requirements_hash)
provisioned_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
echo "Provisioned ComfyUI $REF for $INSTANCE"
