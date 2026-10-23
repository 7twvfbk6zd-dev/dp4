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

The deployment provisions the current ComfyUI release (`v0.42.1`) before the
server starts. The version is set by `COMFYUI_REF` in `comfyui.yaml`. The
provisioning script keeps `models`, `input`, `output`, `custom_nodes`, and
`user`, and writes a source-only rollback archive under
`/mapdata1/comfyui/.rollback` before replacing an existing tree.
The script URL is pinned to a jsDelivr commit because the 168 node cannot
reliably reach `raw.githubusercontent.com`; update both manifests when the
provisioning script changes.

ComfyUI `v0.42.1` pulls in `comfy-aimdo`, which requires PyTorch 2.8+ and
CUDA 12.8+. The provisioning constraints therefore upgrade the runtime to
`torch 2.8.0+cu128`, `torchvision 0.23.0+cu128`, and
`torchaudio 2.8.0+cu128`. The host driver is 570.133.07, which supports CUDA
12.8. The old xformers wheel is removed because it is compiled against
PyTorch 2.4; ComfyUI falls back to PyTorch scaled dot-product attention.

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

## Image-to-video evaluation

`video.yaml` adds a second, isolated ComfyUI deployment for image-to-video
experiments. It requests one GPU, uses its own data volume at
`/mapdata1/comfyui-video`, and listens on NodePort `30189`. The existing SDXL
deployment and `ds4` GPUs 4-7 are left untouched.

Both ComfyUI instances provision the same release from `COMFYUI_REF` in their
deployment manifests. The video instance keeps its own source tree and data
volume, so it can be upgraded and tested independently of the SDXL instance.

Create the host directory and deploy:

```bash
mkdir -p /mapdata1/comfyui-video
sudo chown -R 1000:1000 /mapdata1/comfyui-video
kubectl apply -f deploy/k8s/comfyui/video.yaml
kubectl -n comfyui rollout status deploy/comfyui-video --timeout=20m
```

Download the Wan2.2 TI2V 5B weights (about 18 GB):

```bash
bash deploy/k8s/comfyui/download-video-models.sh
```

The model set is:

| Directory | Model | Purpose |
| --- | --- | --- |
| `diffusion_models` | `wan2.2_ti2v_5B_fp16.safetensors` | Wan2.2 5B video diffusion |
| `text_encoders` | `umt5_xxl_fp8_e4m3fn_scaled.safetensors` | Text encoder |
| `vae` | `wan2.2_vae.safetensors` | Wan2.2 video VAE |

Open `http://172.16.0.168:30189/?token=<token>` and use the API on the same
port. Keep `30189` on the LAN and do not expose it to the public internet.

The first startup can take several minutes while it downloads ComfyUI and
installs the pinned requirements. Startup is protected by a 30-minute
`startupProbe`. On later restarts the script exits quickly when the recorded
ref, `requirements.txt` hash, and required imports all match. Because the
Python venv lives outside the persistent volume, missing packages are
reinstalled automatically after a pod restart.

To upgrade, change `COMFYUI_REF` in the deployment manifest, push the commit,
then run `kubectl apply -f deploy/k8s/comfyui/comfyui.yaml` and
`kubectl rollout restart deploy/comfyui`. Roll back by extracting the desired
archive from `.rollback` after moving the current preserved directories aside.

## Workflows

The reproducible character-sheet, comic-panel, and four-panel storyboard
workflows are in `workflows/`. See `workflows/README.md` for upload, submit,
batch generation, dialogue layout, polling, and tuning instructions. The
phased plan and current status are tracked in `ROADMAP.md`.

## MCP for Codex

The `comfyui-api` Service exposes ComfyUI on NodePort `30191` and bypasses the
Caddy login, so a local MCP client can call the API without a token. Keep this
port on the LAN: it is unauthenticated.

Install the official MCP server and its CLI on the machine running Codex:

```powershell
uv tool install comfy-mcp
uv tool install "comfy-cli>=1.14.0"
```

Register it in `~/.codex/config.toml`:

```toml
[mcp_servers.comfyui]
type = "stdio"
command = "C:/Users/Administrator/.local/bin/comfy-mcp.exe"

[mcp_servers.comfyui.env]
COMFYUI_URL = "http://172.16.0.168:30191"
COMFY_BIN = "C:/Users/Administrator/.local/bin/comfy.exe"
```

Restart Codex, then run `workflows/sdxl-text2image.api.json` with
`run_workflow`. `generate_image` and `run_template` depend on comfy-cli's
template gallery, which times out from this network; a local API-format
workflow submitted with `run_workflow` avoids the gallery entirely.

`run_workflow` has no model parameter: the checkpoint is the
`CheckpointLoaderSimple.ckpt_name` field inside the JSON. To switch within the
SDXL family, generate a workflow for the target file:

```powershell
python deploy/k8s/comfyui/workflows/make_workflow.py `
  --checkpoint other_model.safetensors --prompt "your prompt" `
  --out "$env:TEMP\job.json"
```

Then call `run_workflow` with `%TEMP%\job.json`. List the exact names ComfyUI
sees with:

```powershell
curl.exe -s http://172.16.0.168:30191/object_info/CheckpointLoaderSimple
```

Models are read from `/mapdata1/comfyui/ComfyUI/models/checkpoints`. A
different architecture (Flux, Z-Image, SD 1.5) needs its own node graph, not
just a new checkpoint name, so add a matching API workflow to `workflows/`.

## Storage

`/mapdata1/comfyui` is mounted at `/workspace`. AI-Dock stores generated
outputs, custom nodes, caches, and downloaded models below this directory.
Keep large checkpoints on this volume, not on the 204 GiB root filesystem.

## Security

The UI is exposed on the LAN without TLS. Use the generated password, and do
not expose `30188` or the unauthenticated `30191` API port to the public
internet. For remote access, prefer an SSH tunnel:

```bash
kubectl -n comfyui port-forward svc/comfyui 8188:8188
```

Then open `http://127.0.0.1:8188/`.
