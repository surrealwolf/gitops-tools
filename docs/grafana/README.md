# Grafana Stack Documentation

Documentation for the Grafana stack (Loki, Grafana, Promtail, Vector) deployed via Fleet to the nprd-apps cluster.

## Overview

| Component | Purpose |
|-----------|---------|
| **Loki** | Log aggregation (S3 storage via RustFS on TrueNAS) |
| **Grafana** | Visualization, dashboards, LogQL queries |
| **Promtail** | Kubernetes pod log collection (DaemonSet) |
| **Vector** | Syslog receiver for UniFi CEF format |

**Namespace:** `grafana`  
**Cluster:** nprd-apps (Fleet path: `grafana/overlays/nprd-apps`)

## Storage: RustFS (S3)

Loki uses **RustFS** on TrueNAS as S3-compatible object storage (no in-cluster MinIO).

- **Endpoint:** `http://192.168.9.5:30292` (configurable per overlay)
- **Buckets:** `loki-chunks`, `loki-ruler` (create in RustFS WebUI)
- **Credentials:** Create `loki-rustfs-credentials` secret; Loki reads from it via `extraEnvFrom` (no plain text in values)

**Setup guide:** [RUSTFS_LOKI_SETUP.md](RUSTFS_LOKI_SETUP.md)  
**Bucket settings:** Disable Object Lock and versioning; Loki handles retention via its compactor.

**Create secret before first deploy:**
```bash
kubectl create secret generic loki-rustfs-credentials \
  --from-literal=accessKeyId='<ACCESS_KEY>' \
  --from-literal=secretAccessKey='<SECRET_KEY>' \
  -n grafana
```

Use Sealed Secrets or External Secrets for production. Do not commit credentials to Git.

## Access

| Service | URL |
|---------|-----|
| Grafana | `https://grafana.dataknife.net` |
| Loki API | `https://loki.dataknife.net` |
| Vector metrics | `https://vector.dataknife.net/metrics` |
| Vector syslog | `vector.dataknife.net:30514` (UDP) |

**Grafana credentials:** Username `admin`, password from:
```bash
kubectl get secret grafana -n grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

## Loki Endpoints (Microservices Mode)

For Vector/Promtail and Grafana datasource:

| Service | Endpoint | Use |
|---------|----------|-----|
| loki-gateway | `http://loki-gateway:80` | General routing |
| loki-distributor | `http://loki-distributor:3100` | Log ingestion |
| loki-query-frontend | `http://loki-query-frontend:3100` | Queries |

## UniFi CEF Syslog

Vector receives UniFi CEF logs on UDP 30514 and forwards to Loki.

**Configure UniFi:** Settings → System Logs → SIEM Integration → `vector.dataknife.net:30514`, Format: CEF

**Detailed guide:** [UNIFI_CEF_SETUP.md](UNIFI_CEF_SETUP.md)

## Fleet Troubleshooting

### Helm adoption / orphaned resources

If you see `ClusterRole "loki-clusterrole" exists and cannot be imported` (or similar for grafana, promtail):

**Option A – Adopt existing resources:**
```bash
kubectl annotate clusterrole loki-clusterrole \
  meta.helm.sh/release-name=loki meta.helm.sh/release-namespace=grafana --overwrite
# Repeat for loki-clusterrolebinding, grafana-clusterrole, grafana-clusterrolebinding, promtail (role + binding)
kubectl delete job -n grafana helm-install-loki helm-install-grafana helm-install-promtail
```

**Option B – Delete orphaned resources (clean slate):**
```bash
kubectl delete clusterrole loki-clusterrole grafana-clusterrole promtail
kubectl delete clusterrolebinding loki-clusterrolebinding grafana-clusterrolebinding promtail
kubectl delete job -n grafana helm-install-loki helm-install-grafana helm-install-promtail
```

Do **not** delete `prometheus-kube-prometheus-*` resources.

### Namespace ownership

If `Namespace "grafana" exists and cannot be imported`:
```bash
kubectl annotate namespace grafana \
  meta.helm.sh/release-name=gitops-tools-nprd-apps-grafana-overlays-nprd-apps \
  meta.helm.sh/release-namespace=grafana --overwrite
kubectl label namespace grafana app.kubernetes.io/managed-by=Helm --overwrite
```

### Fleet agent TLS / Unauthorized

See [FLEET_SYNC.md](../FLEET_SYNC.md) for TLS verification and registration issues.

## Vector / Promtail Notes

- **Vector Loki endpoint:** Use `http://loki-gateway:80` or `http://loki-distributor:3100` (not `loki:3100` in microservices mode)
- **Promtail:** Same endpoint; path `/loki/api/v1/push`
- **Vector port 514:** Requires `CAP_NET_BIND_SERVICE` or `runAsUser: 0` for privileged port
- **Vector image:** Prefer `vectordotdev/vector` over deprecated `timberio/vector`

## Documentation Index

| Document | Description |
|----------|-------------|
| [RUSTFS_LOKI_SETUP.md](RUSTFS_LOKI_SETUP.md) | RustFS on TrueNAS setup for Loki S3 |
| [rustfs-loki-policy.example.json](rustfs-loki-policy.example.json) | Example IAM policy for Loki access to loki-chunks and loki-ruler |
| [UNIFI_CEF_SETUP.md](UNIFI_CEF_SETUP.md) | UniFi CEF syslog integration |
| [FLEET_SYNC.md](../FLEET_SYNC.md) | Fleet sync troubleshooting |
