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

## Enforce gateway-only access

`ds4` runs with `hostNetwork`, so Kubernetes NetworkPolicy cannot restrict it.
The host-level guard drops every packet to `tcp/18080` except traffic from the
cluster pod network (`10.244.0.0/16`), localhost, and the node IPs. External
clients therefore have to use the New API gateway on `30300`.

Install on the 168 host:

```bash
scp deploy/monitoring/host/ds4-ingress-guard.sh \
    deploy/monitoring/host/ds4-ingress-guard.service \
    xszn@172.16.0.168:/tmp/

ssh xszn@172.16.0.168 '
  sudo install -m 755 /tmp/ds4-ingress-guard.sh /usr/local/sbin/
  sudo install -m 644 /tmp/ds4-ingress-guard.service /etc/systemd/system/
  sudo systemctl daemon-reload
  sudo systemctl enable --now ds4-ingress-guard.service
'
```

Verify from outside the cluster:

```bash
curl -m 5 http://172.16.0.168:18080/v1/models   # times out
curl -H "Authorization: Bearer $TOKEN" \
  http://172.16.0.168:30300/v1/models           # 200
```

Disable and remove the rules:

```bash
sudo systemctl disable --now ds4-ingress-guard.service
sudo iptables -D INPUT -s 10.244.0.0/16 -p tcp --dport 18080 -j ACCEPT
sudo iptables -D INPUT -s 127.0.0.1/32 -p tcp --dport 18080 -j ACCEPT
sudo iptables -D INPUT -s 192.168.5.170/32 -p tcp --dport 18080 -j ACCEPT
sudo iptables -D INPUT -s 172.16.0.168/32 -p tcp --dport 18080 -j ACCEPT
sudo iptables -D INPUT -p tcp --dport 18080 -j DROP
```

Update the pod CIDR in both the script and this document if the cluster
network is reconfigured.

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
