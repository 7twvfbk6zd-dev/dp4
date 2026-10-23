# SwarmUI

Simple prompt-driven web UI on top of the existing ComfyUI instance.

- URL: `http://172.16.0.168:30190`
- Namespace: `swarmui`
- Data: `/mapdata1/swarmui` (PVC `swarmui-data`)
- SwarmUI never loads a model or touches the GPU. Every generation is sent to
  the `comfyui` deployment in namespace `comfyui`.

## Architecture

```
browser -> swarmui:7801 (NodePort 30190)
             |
             +-> comfyui-direct.comfyui.svc.cluster.local:8188
                   -> ComfyUI pod 0.0.0.0:18188
```

`comfyui-direct` is a ClusterIP-only Service. It bypasses the ai-dock Caddy
login page (NodePort `30188` stays password protected) and is reachable only
from inside the cluster.

## ComfyUI prerequisites

The ComfyUI deployment must listen on all interfaces and use a fast PyPI
mirror while provisioning:

```yaml
- name: COMFYUI_ARGS
  value: --listen 0.0.0.0
- name: PIP_INDEX_URL
  value: https://mirrors.cloud.tencent.com/pypi/simple
```

SwarmUI also needs:

1. Its own ComfyUI nodes in `ComfyUI/custom_nodes`:
   `SwarmComfyCommon` and `SwarmComfyExtra`.
2. Model folders named `Stable-Diffusion`, `Lora`, `VAE`, `Embeddings`,
   `ControlNet`, `ClipVision`. They are relative symlinks to ComfyUI's
   `checkpoints`, `loras`, `vae`, `embeddings`, `controlnet`, `clip_vision`.

Run `provision-swarmui.sh` on the node, then restart ComfyUI:

```bash
sudo bash deploy/k8s/swarmui/provision-swarmui.sh
kubectl -n comfyui exec deploy/comfyui -- supervisorctl restart comfyui
```

The ComfyUI pod rebuilds its Python venv from the image on every restart, so a
pod restart re-runs dependency provisioning. Keep `PIP_INDEX_URL` pointed at a
mirror; installing from pypi.org directly can take hours.

## Image

SwarmUI `0.9.8-Beta` is built from upstream source:

```bash
git clone https://github.com/mcmonkeyprojects/SwarmUI /home/xszn/swarmui-src
cd /home/xszn/swarmui-src
# Dockerfile.k8s uses mcr.m.daocloud.io/dotnet/sdk:8.0-bookworm-slim
docker build -t swarmui:v1 -f Dockerfile.k8s .
docker save -o /tmp/swarmui.tar swarmui:v1
# import through the privileged pod pattern in deploy/k8s/import-image.yaml
```

## Deploy

```bash
mkdir -p /mapdata1/swarmui/{Data,Output}
kubectl apply -f deploy/k8s/swarmui/swarmui.yaml
```

### Skip the first-run installer

SwarmUI redirects `/Text2Image` to `/Install` until `IsInstalled: true` is set
in `/mapdata1/swarmui/Settings.fds`. Registering a backend by hand does **not**
set this flag, and submitting the wizard clones a second ComfyUI into
`dlbackend/ComfyUI` (from GitHub, which is very slow here) and downloads the
selected models.

Once the pod has generated `Settings.fds`, mark the instance installed and
restart:

```bash
sudo bash deploy/k8s/swarmui/provision-swarmui.sh
kubectl -n swarmui rollout restart deploy/swarmui
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:30190/Text2Image  # 200
```

The script is idempotent and also resets `LaunchMode: install` to `none`.

Register the backend once (setting key `Address` is case-sensitive):

```bash
SID=$(curl -s -H 'Content-Type: application/json' -d '{}' \
  -X POST http://127.0.0.1:30190/API/GetNewSession \
  | sed -n 's/.*"session_id":"\([^"]*\)".*/\1/p')

curl -s -H 'Content-Type: application/json' \
  -d "{\"session_id\":\"$SID\",\"type_id\":\"comfyui_api\"}" \
  -X POST http://127.0.0.1:30190/API/AddNewBackend

curl -s -H 'Content-Type: application/json' \
  -d "{\"session_id\":\"$SID\",\"backend_id\":0,\"title\":\"ComfyUI\",\"settings\":{\"Address\":\"http://comfyui-direct.comfyui.svc.cluster.local:8188\"}}" \
  -X POST http://127.0.0.1:30190/API/EditBackend
```

Smoke test:

```bash
curl -s -H 'Content-Type: application/json' \
  -d "{\"session_id\":\"$SID\",\"images\":1,\"prompt\":\"a red apple\",\"model\":\"sd_xl_base_1.0.safetensors\",\"width\":1024,\"height\":1024,\"steps\":20}" \
  -X POST http://127.0.0.1:30190/API/GenerateText2Image
```

## Rollback

```bash
kubectl delete namespace swarmui
kubectl -n comfyui delete svc comfyui-direct
kubectl -n comfyui set env deploy/comfyui COMFYUI_ARGS- PIP_INDEX_URL-
```

Removing the env vars restores loopback-only ComfyUI and restarts the pod.
