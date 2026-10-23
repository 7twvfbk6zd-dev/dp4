#!/usr/bin/env bash
# Prepare host paths shared by SwarmUI and the ComfyUI instance.
set -euo pipefail

ROOT="${SWARMUI_ROOT:-/mapdata1/swarmui}"
COMFY_MODELS="${COMFYUI_MODELS_DIR:-/mapdata1/comfyui/ComfyUI/models}"
SWARM_SRC="${SWARMUI_SRC:-/home/xszn/swarmui-src}"
SWARMUI_VERSION="${SWARMUI_VERSION:-0.9.8.4}"

mkdir -p "$ROOT/Data" "$ROOT/Output"

# SwarmUI expects Category names (Stable-Diffusion, Lora, ...) while ComfyUI
# stores them as checkpoints/loras/... Create relative symlinks so both see
# the same files. Only empty directories are replaced.
for pair in \
  "Stable-Diffusion:checkpoints" \
  "Lora:loras" \
  "VAE:vae" \
  "Embeddings:embeddings" \
  "ControlNet:controlnet" \
  "ClipVision:clip_vision" ; do
  link="${pair%%:*}"
  target="${pair##*:}"
  [ -d "$COMFY_MODELS/$target" ] || continue
  [ -L "$COMFY_MODELS/$link" ] && continue
  if [ -d "$COMFY_MODELS/$link" ] && [ -z "$(ls -A "$COMFY_MODELS/$link")" ]; then
    rmdir "$COMFY_MODELS/$link"
  fi
  [ -e "$COMFY_MODELS/$link" ] || ln -s "$target" "$COMFY_MODELS/$link"
done

# SwarmUI injects its own ComfyUI nodes into every workflow.
for node in SwarmComfyCommon SwarmComfyExtra ; do
  src="$SWARM_SRC/src/BuiltinExtensions/ComfyUIBackend/ExtraNodes/$node"
  dst="$COMFY_MODELS/../custom_nodes"
  [ -d "$src" ] || continue
  mkdir -p "$dst"
  rm -rf "$dst/$node"
  cp -r "$src" "$dst/$node"
done

# SwarmUI redirects /Text2Image to the first-run installer while IsInstalled is
# false, which would otherwise re-download ComfyUI and models on every fresh
# volume. A backend registered by hand does not flip this flag on its own.
SETTINGS="$ROOT/Settings.fds"
if [ -f "$SETTINGS" ]; then
  if ! grep -q '^IsInstalled: true' "$SETTINGS" || grep -q '^LaunchMode: install' "$SETTINGS"; then
    cp -a "$SETTINGS" "$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)"
    sed -i -E \
      -e 's/^IsInstalled:.*/IsInstalled: true/' \
      -e "s/^InstallDate:.*/InstallDate: $(date +%F)/" \
      -e "s/^InstallVersion:.*/InstallVersion: $SWARMUI_VERSION/" \
      -e 's/^LaunchMode:.*/LaunchMode: none/' \
      "$SETTINGS"
    echo "Marked SwarmUI as installed. Restart the deployment to apply."
  fi
else
  echo "Settings.fds not found yet. Start SwarmUI once, then rerun this script."
fi

echo "SwarmUI host paths ready. Restart ComfyUI after installing new nodes."
