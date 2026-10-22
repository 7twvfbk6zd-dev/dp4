# DS4 monitoring and LLM gateway

This directory deploys a small observability stack for the DS4 server on the
single-node 168 cluster:

- `new-api` on NodePort `30300`: OpenAI-compatible gateway with request,
  token, latency, and usage dashboards. It proxies to the existing `ds4`
  service and stores its SQLite database on the `new-api-data` PVC.
- Prometheus on ClusterIP `9090`: scrapes GPU and host metrics.
- Grafana on NodePort `30301`: pre-provisioned `DS4 GPU & Host` dashboard.
- `dcgm-exporter`: NVIDIA GPU utilization, memory, power, and temperature.
- `node-exporter`: host CPU, memory, filesystem, and network metrics.

## Images

The 168 host cannot reach Docker Hub directly. Pull through the DaoCloud
mirror, then import into containerd:

```bash
docker pull docker.m.daocloud.io/calciumion/new-api:v1.0.0-rc.46
docker pull docker.m.daocloud.io/grafana/grafana:11.4.0
docker pull nvcr.io/nvidia/k8s/dcgm-exporter:4.6.1-4.8.4-distroless
docker pull quay.io/prometheus/prometheus:v3.15.1
docker pull quay.io/prometheus/node-exporter:v1.12.1

docker save -o /tmp/aiops-images.tar \
  docker.m.daocloud.io/calciumion/new-api:v1.0.0-rc.46 \
  docker.m.daocloud.io/grafana/grafana:11.4.0 \
  nvcr.io/nvidia/k8s/dcgm-exporter:4.6.1-4.8.4-distroless \
  quay.io/prometheus/prometheus:v3.15.1 \
  quay.io/prometheus/node-exporter:v1.12.1

kubectl apply -f deploy/monitoring/import-images.yaml
kubectl wait --for=condition=Completed pod/aiops-imgimport --timeout=300s
kubectl delete pod/aiops-imgimport
```

## Secrets

```bash
kubectl -n aiops create secret generic new-api-session \
  --from-literal=session-secret="$(openssl rand -hex 32)"
kubectl -n aiops create secret generic grafana-admin \
  --from-literal=admin-password='replace-with-a-strong-password'
```

## Deploy

```bash
kubectl apply -k deploy/monitoring
kubectl -n aiops get pods -o wide
```

Then initialize New API and create the `ds4-local` channel and a `chatbox`
token:

```bash
NEW_API_ADMIN_PASSWORD='...' ./deploy/monitoring/bootstrap-new-api.sh
```

Point Chatbox at:

- Base URL: `http://172.16.0.168:30300/v1`
- Model: `deepseek-v4.1-flash`
- API key: the `sk-...` value printed by the bootstrap script

Grafana:

- URL: `http://172.16.0.168:30301`
- user: `admin`
- password: the `grafana-admin` secret value

## Rollback

Delete the workloads without deleting the PVCs first if you want to keep the
New API SQLite database and Prometheus/Grafana data:

```bash
kubectl -n aiops delete deployment new-api prometheus grafana
kubectl -n aiops delete daemonset dcgm-exporter node-exporter
kubectl -n aiops delete service new-api prometheus grafana dcgm-exporter node-exporter
```

The existing `ds4` deployment and its model/data are not modified by this
directory.
