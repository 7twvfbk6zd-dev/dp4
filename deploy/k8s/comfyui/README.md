# ComfyUI on 168

Single-node Kubernetes deployment for AI comic/video workflows. It uses one
GPU from the pool left free by `ds4` and exposes the UI on NodePort `30188`.

## Prerequisites

The host data directory must exist before the PV is mounted:

```bash
mkdir -p /mapdata1/comfyui
```

Create the UI secret once. The token is the stable login token used in the URL:

```bash
kubectl -n comfyui create secret generic comfyui-auth \
  --from-literal=password='<change-me>' \
  --from-literal=token='<change-me-too>'
```

## Deploy

```bash
kubectl apply -f deploy/k8s/comfyui/comfyui.yaml
kubectl -n comfyui rollout status deploy/comfyui
```

Read the token and open the UI:

```bash
TOKEN=$(kubectl -n comfyui get secret comfyui-auth \
  -o jsonpath='{.data.token}' | base64 -d)
echo http://172.16.0.168:30188/?token=$TOKEN
```

The browser stores the token as a cookie after the first visit.

The pod requests `nvidia.com/gpu: 1`. Do not change it to four GPUs: native
ComfyUI runs one workflow on one GPU. Scale with additional replicas and
separate services when parallel scene generation is needed.

## Starter models

Run the model download on the Kubernetes node before starting the first
workflow:

```bash
bash deploy/k8s/comfyui/download-models.sh
```

The script downloads to `/mapdata1/comfyui/ComfyUI/models` by default. Override
that path with `COMFYUI_MODELS_DIR` when the data directory is different. It
uses `aria2c` when available and falls back to resumable `curl` downloads.
Existing non-empty files are skipped, so it is safe to rerun after a failure.

| Directory | Model | Purpose |
| --- | --- | --- |
| `checkpoints` | `sd_xl_base_1.0.safetensors` | SDXL base generation |
| `vae` | `sdxl_vae.safetensors` | SDXL VAE |
| `controlnet` | `controlnet-canny-sdxl-fp16.safetensors` | Pose and line-art composition |
| `controlnet` | `controlnet-depth-sdxl-fp16.safetensors` | Scene depth composition |
| `ipadapter` | `ip-adapter-plus-face_sdxl_vit-h.safetensors` | Character face consistency |
| `ipadapter` | `ip-adapter-plus_sdxl_vit-h.safetensors` | General style and subject reference |
| `clip_vision` | `CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors` | Image encoder for IP-Adapter |
| `loras` | `sd_xl_offset_example-lora_1.0.safetensors` | SDXL LoRA loader smoke test |

The set is about 17 GB. The IP-Adapter nodes come from
`ComfyUI_IPAdapter_plus`, installed under
`/mapdata1/comfyui/ComfyUI/custom_nodes`. If the container cannot read the
downloaded files, align ownership with the container user:

```bash
sudo chown -R 1000:1000 /mapdata1/comfyui/ComfyUI/models
```

Refresh the ComfyUI page after downloading so the model selectors rescan the
directories.

## Workflows

The reproducible character-sheet, comic-panel, and four-panel storyboard
workflows are in `workflows/`. See `workflows/README.md` for upload, submit,
batch generation, dialogue layout, polling, and tuning instructions. The
phased plan and current status are tracked in `ROADMAP.md`.

## Storage

`/mapdata1/comfyui` is mounted at `/workspace`. AI-Dock stores generated
outputs, custom nodes, caches, and downloaded models below this directory.
Keep large checkpoints on this volume, not on the 204 GiB root filesystem.

## Security

The UI is exposed on the LAN without TLS. Use the generated password, and do
not expose `30188` to the public internet. For remote access, prefer an SSH
tunnel:

```bash
kubectl -n comfyui port-forward svc/comfyui 8188:8188
```

Then open `http://127.0.0.1:8188/`.
