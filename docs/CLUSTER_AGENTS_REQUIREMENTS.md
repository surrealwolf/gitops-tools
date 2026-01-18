# Cluster Agents Requirements

## Overview

To collect metrics and logs from all clusters into the centralized observability platform on **nprd-apps** cluster (`managed-syslog` namespace), each remote cluster needs to deploy lightweight agents.

## Required Components Per Cluster

### 1. Logs → Loki: **Promtail** (DaemonSet)

**Purpose**: Collects and pushes logs to central Loki instance

**Deployment**:
- Type: DaemonSet (one pod per node)
- Namespace: `managed-syslog` (or cluster-specific namespace)

**Configuration Required**:
```yaml
clients:
  - url: https://loki.dataknife.net/loki/api/v1/push  # External endpoint
    # OR for internal cluster access:
    # - url: http://loki-distributor.managed-syslog.svc.cluster.local:3100/loki/api/v1/push
```

**Labels Added**:
- `cluster: <cluster-name>` - Identifies which cluster the logs come from
- Standard Kubernetes labels (namespace, pod, container, etc.)

**Resources**:
- CPU: 100-200m per node
- Memory: 128-256Mi per node

**What it does**:
- Discovers pods via Kubernetes service discovery
- Scrapes logs from `/var/log/pods/` on each node
- Adds cluster and pod metadata as labels
- Pushes logs to Loki distributor via HTTP

---

### 2. Metrics → Prometheus: **Prometheus Agent** (Remote Write)

**Purpose**: Collects and pushes metrics to central Prometheus instance

**Deployment**:
- Type: Deployment or DaemonSet
- Namespace: `managed-syslog` (or cluster-specific namespace)

**Configuration Required**:
```yaml
remoteWrite:
  - url: https://prometheus.dataknife.net/api/v1/write  # External endpoint
    # OR for internal cluster access:
    # - url: http://prometheus-kube-prometheus-prometheus.managed-syslog.svc.cluster.local:9090/api/v1/write
    queueConfig:
      maxSamplesPerSend: 1000
      maxShards: 200
      capacity: 2500
```

**What it scrapes**:
- node-exporter (node metrics: CPU, memory, disk, network)
- kube-state-metrics (cluster state: deployments, pods, services)
- ServiceMonitors/PodMonitors (application metrics)

**Labels Added**:
- `cluster: <cluster-name>` - Identifies which cluster metrics come from
- Standard Prometheus labels

**Resources**:
- CPU: 500m
- Memory: 512Mi-1Gi

**What it does**:
- Scrapes metrics from local cluster components
- Adds cluster label to all metrics
- Pushes metrics to central Prometheus via remote write API
- No local storage (stateless)

---

## Alternative: Pull Model (If Remote Write Not Possible)

If you cannot use remote write, you can use the **pull model**:

### Components to Deploy:
1. **node-exporter** (DaemonSet) - Node metrics
2. **kube-state-metrics** (Deployment) - Cluster state metrics
3. **Expose via LoadBalancer/Ingress** - For central Prometheus to scrape

### Central Prometheus Configuration:
Add `additionalScrapeConfigs` to scrape metrics from remote clusters:
```yaml
additionalScrapeConfigs:
  - job_name: 'remote-cluster-a-node-exporter'
    static_configs:
      - targets: ['node-exporter-cluster-a.example.com:9100']
    relabel_configs:
      - target_label: cluster
        replacement: 'cluster-a'
  - job_name: 'remote-cluster-a-kube-state-metrics'
    static_configs:
      - targets: ['kube-state-metrics-cluster-a.example.com:8080']
    relabel_configs:
      - target_label: cluster
        replacement: 'cluster-a'
```

---

## Summary Table

| Component | Purpose | Type | Network Direction | Resources |
|-----------|---------|------|-------------------|-----------|
| **Promtail** | Push logs to Loki | DaemonSet | Outbound (push) | 100-200m CPU, 128-256Mi RAM per node |
| **Prometheus Agent** | Push metrics to Prometheus | Deployment | Outbound (push) | 500m CPU, 512Mi-1Gi RAM |
| **node-exporter** (alternative) | Expose node metrics | DaemonSet | Inbound (pull) | 100m CPU, 64Mi RAM per node |
| **kube-state-metrics** (alternative) | Expose cluster metrics | Deployment | Inbound (pull) | 200m CPU, 256Mi RAM |

---

## Deployment Configuration

### Promtail Configuration (Per Cluster)

```yaml
# promtail/cluster-<name>/promtail-helmchart.yaml
config:
  clients:
    - url: https://loki.dataknife.net/loki/api/v1/push  # External
      externalLabels:
        cluster: <cluster-name>
      tenant_id: ""  # Leave empty unless using multi-tenancy
```

### Prometheus Agent Configuration (Per Cluster)

```yaml
# prometheus-agent/cluster-<name>/prometheus-agent-helmchart.yaml
config:
  global:
    external_labels:
      cluster: <cluster-name>
  remoteWrite:
    - url: https://prometheus.dataknife.net/api/v1/write  # External
      queueConfig:
        maxSamplesPerSend: 1000
        maxShards: 200
  scrape_configs:
    - job_name: 'node-exporter'
      kubernetes_sd_configs:
        - role: endpoints
      relabel_configs:
        - source_labels: [__meta_kubernetes_endpoints_name]
          regex: 'prometheus-node-exporter'
          action: keep
    - job_name: 'kube-state-metrics'
      kubernetes_sd_configs:
        - role: endpoints
      relabel_configs:
        - source_labels: [__meta_kubernetes_endpoints_name]
          regex: 'kube-state-metrics'
          action: keep
```

---

## Network Requirements

### Outbound (Push Model) - Recommended

**From each cluster to nprd-apps**:
- Loki: HTTPS to `https://loki.dataknife.net/loki/api/v1/push`
- Prometheus: HTTPS to `https://prometheus.dataknife.net/api/v1/write`

**Firewall rules**: Allow outbound HTTPS (443) from cluster nodes

### Inbound (Pull Model) - Alternative

**From nprd-apps to each cluster**:
- node-exporter: HTTP to `<cluster>:9100`
- kube-state-metrics: HTTP to `<cluster>:8080`

**Firewall rules**: Allow inbound HTTP (9100, 8080) to cluster nodes from nprd-apps

---

## Security Considerations

### Authentication

1. **Loki**: Configure authentication if needed
   ```yaml
   clients:
     - url: https://loki.dataknife.net/loki/api/v1/push
       bearer_token_file: /var/run/secrets/loki/token
   ```

2. **Prometheus**: Configure authentication if needed
   ```yaml
   remoteWrite:
     - url: https://prometheus.dataknife.net/api/v1/write
       basic_auth:
         username: <user>
         password: <pass>
       # OR
       bearer_token_file: /var/run/secrets/prometheus/token
   ```

### TLS/SSL

- Use HTTPS endpoints with valid certificates
- Or use internal cluster networking if available

---

## Recommended Architecture

**Central Platform (nprd-apps)**:
- Loki (receives logs)
- Prometheus (receives metrics via remote write)
- Grafana (visualization)

**Each Remote Cluster**:
- Promtail (pushes logs → Loki)
- Prometheus Agent (pushes metrics → Prometheus)
- Optional: node-exporter + kube-state-metrics (if not included in agent)

---

## Next Steps

1. ✅ Central platform already deployed on nprd-apps
2. ⏳ Create Fleet configurations for Promtail and Prometheus Agent
3. ⏳ Configure external endpoints (ingress) for Loki and Prometheus
4. ⏳ Deploy agents to each cluster via Fleet
5. ⏳ Verify logs and metrics are flowing into central platform
