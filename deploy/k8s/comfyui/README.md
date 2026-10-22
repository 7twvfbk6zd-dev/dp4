# ComfyUI on 168

Single-node Kubernetes deployment for AI comic/video workflows. It uses one
GPU from the pool left free by `ds4` and exposes the UI on NodePort `30188`.

## Prerequisites

The host data directory must exist before the PV is mounted:

```bash
mkdir -p /mapdata1/comfyui
```

Create the UI password secret once:

```bash
kubectl -n comfyui create secret generic comfyui-auth \
  --from-literal=password='<change-me>'
```

## Deploy

```bash
kubectl apply -f deploy/k8s/comfyui/comfyui.yaml
kubectl -n comfyui rollout status deploy/comfyui
```

Open `http://172.16.0.168:30188/` and log in as `admin`.

The pod requests `nvidia.com/gpu: 1`. Do not change it to four GPUs: native
ComfyUI runs one workflow on one GPU. Scale with additional replicas and
separate services when parallel scene generation is needed.

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
