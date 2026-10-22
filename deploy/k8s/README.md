# Kubernetes deployment

Runs the 4-GPU tensor-parallel server as a single pod on a single-node
cluster. All four ranks live in one pod because TP uses localhost TCP and
shared memory between the coordinator and the workers.

## Requirements

- Kubernetes node with `runtimeClassName: nvidia` available
  (containerd + `nvidia-container-runtime`, `nvidia.com/gpu` advertised)
- At least 4 free GPUs on the node
- GGUF files on the node at `/mapdata1/tools/ds4-main/gguf`
  (`DeepSeek-V4.1-Flash-*.gguf` and `DeepSeek-V4.1-Flash-Vision.gguf`)
- Docker on the node (only used to build/save the image)

## Build

```bash
make cuda CUDA_ARCH=sm_89 CUDA_HOME=/mapdata1/tools/cuda-12.8
./deploy/k8s/build-image.sh          # IMAGE=ds4:v2 by default
```

The image bundles `ds4-server`, `ds4`, the CUDA runtime libraries and the
host `libstdc++` (Ubuntu 20.04's is too old for `GLIBCXX_3.4.29`).
The 341GB weights are **not** in the image; they are mounted from the host.

## Import into containerd

The node's containerd socket is root-only, so import through a privileged
pod:

```bash
docker save -o /tmp/ds4.tar ds4:v2
kubectl apply -f deploy/k8s/import-image.yaml
kubectl wait --for=condition=Completed pod/imgimport --timeout=300s
kubectl delete pod imgimport
```

## Deploy

```bash
kubectl apply -f deploy/k8s/ds4.yaml
kubectl -n ds4 rollout status deploy/ds4
curl http://127.0.0.1:18080/v1/models
```

## Operate

```bash
kubectl -n ds4 get pod -o wide
kubectl -n ds4 logs deploy/ds4 -f
kubectl -n ds4 rollout restart deploy/ds4     # ~35s to Ready
kubectl -n ds4 scale deploy/ds4 --replicas=0  # release the 4 GPUs
kubectl -n ds4 scale deploy/ds4 --replicas=1
kubectl delete -f deploy/k8s/ds4.yaml         # remove namespace + service
```

## Multi-session batching

`--batched-session` is disabled (`DS4_BATCHED_SESSION=0`). On 24GB cards the
planner requires 25.5-27.9GiB *before* the expert cache for two sessions, which
exceeds the 23.5GiB safe budget, and the TP path additionally deadlocks at the
rank gate. Requests from multiple clients are therefore queued on one resident
session.

## Design notes

- `replicas: 1` is deliberate. Each replica needs 4 exclusive GPUs, and the
  node only has 8; two replicas would also race on the same NVMe while
  streaming a 341GB model. This workload scales vertically (more GPUs per
  rank set), not horizontally.
- `hostNetwork: true` keeps the endpoint at `node-ip:18080`, so existing
  clients do not change. Consequence: only one pod can bind that port.
- No memory limit on purpose: the process keeps model pages in the page
  cache (`DS4_CUDA_KEEP_MODEL_PAGES=1`), and a cgroup limit would evict them
  and destroy throughput.
- `/dev/shm` is a 16Gi memory-backed emptyDir; the TP rank gate needs more
  than the 64Mi default.