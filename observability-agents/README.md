# Observability Agents

This directory contains GitOps configurations for deploying observability agents (Promtail and Prometheus Agent) to collect logs and metrics from all clusters and push them to the centralized observability platform on **nprd-apps** cluster.

## Overview

The observability agents are lightweight components that run on each cluster to:
- **Promtail**: Collect and push logs to central Loki
- **Prometheus Agent**: Collect and push metrics to central Prometheus

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Central Platform (nprd-apps cluster - managed-syslog)      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                  │
│  │  Loki    │  │Prometheus│  │  Grafana │                  │
│  └──────────┘  └──────────┘  └──────────┘                  │
│       ▲              ▲                                        │
└───────┼──────────────┼───────────────────────────────────────┘
        │              │
        │              │
┌───────┴──────────────┴───────────────────────────────────────┐
│  Each Cluster (nprd-apps, cluster-a, cluster-b, etc.)        │
│  ┌──────────┐  ┌─────────────────┐  ┌──────────────────┐    │
│  │ Promtail │  │Prometheus Agent │  │ node-exporter    │    │
│  │(Daemon)  │  │ (Remote Write)  │  │ (Daemon)         │    │
│  └──────────┘  └─────────────────┘  └──────────────────┘    │
│  ┌──────────────────────────────────────────────────┐        │
│  │ kube-state-metrics                               │        │
│  └──────────────────────────────────────────────────┘        │
└───────────────────────────────────────────────────────────────┘
```

## Structure

```
observability-agents/
├── promtail/
│   ├── base/                          # Base Promtail configuration
│   │   ├── fleet.yaml
│   │   ├── kustomization.yaml
│   │   ├── namespace.yaml
│   │   ├── promtail-helmchart.yaml
│   │   └── README.md
│   └── overlays/
│       ├── nprd-apps/                 # nprd-apps cluster overlay
│       │   ├── fleet.yaml            # Fleet targeting
│       │   ├── kustomization.yaml
│       │   └── promtail-helmchart.yaml
│       ├── cluster-a/                 # cluster-a overlay
│       │   ├── fleet.yaml
│       │   ├── kustomization.yaml
│       │   └── promtail-helmchart.yaml
│       └── cluster-b/                 # cluster-b overlay
│           ├── fleet.yaml
│           ├── kustomization.yaml
│           └── promtail-helmchart.yaml
└── prometheus-agent/
    ├── base/                          # Base Prometheus Agent configuration
    │   ├── fleet.yaml
    │   ├── kustomization.yaml
    │   ├── namespace.yaml
    │   ├── prometheus-agent-helmchart.yaml
    │   ├── node-exporter-helmchart.yaml
    │   ├── kube-state-metrics-helmchart.yaml
    │   └── README.md
    └── overlays/
        ├── nprd-apps/                 # nprd-apps cluster overlay
        │   ├── fleet.yaml
        │   ├── kustomization.yaml
        │   ├── prometheus-agent-helmchart.yaml
        │   ├── node-exporter-helmchart.yaml
        │   └── kube-state-metrics-helmchart.yaml
        ├── cluster-a/                 # cluster-a overlay
        │   └── ...
        └── cluster-b/                 # cluster-b overlay
            └── ...
```

## Components

### Promtail

**Purpose**: Collect and push logs to central Loki

**Deployment**: DaemonSet (one pod per node)

**Configuration**:
- **nprd-apps**: Uses internal service endpoint (`http://loki-distributor.managed-syslog.svc.cluster.local:3100`)
- **Other clusters**: Uses external endpoint (`https://loki.dataknife.net/loki/api/v1/push`)

**Cluster Label**: Each overlay sets `cluster: <cluster-name>` in external labels

### Prometheus Agent

**Purpose**: Collect and push metrics to central Prometheus

**Deployment**: Deployment (with node-exporter DaemonSet and kube-state-metrics Deployment)

**Components**:
1. **Prometheus Agent**: Scrapes and pushes metrics via remote write
2. **node-exporter**: Exposes node-level metrics (CPU, memory, disk, network)
3. **kube-state-metrics**: Exposes cluster state metrics (deployments, pods, services)

**Configuration**:
- **nprd-apps**: Uses internal service endpoint (`http://prometheus-kube-prometheus-prometheus.managed-syslog.svc.cluster.local:9090/api/v1/write`)
- **Other clusters**: Uses external endpoint (`https://prometheus.dataknife.net/api/v1/write`)

**Cluster Label**: Each overlay sets `cluster: <cluster-name>` in external labels

## Fleet Configuration

Each cluster overlay has its own `fleet.yaml` with cluster targeting:

```yaml
targetCustomizations:
  - name: <cluster-name>
    clusterSelector:
      matchLabels:
        management.cattle.io/cluster-display-name: <cluster-name>
```

## Deployment

### Adding a New Cluster

1. **Create overlay directories**:
   ```bash
   mkdir -p observability-agents/promtail/overlays/<new-cluster>
   mkdir -p observability-agents/prometheus-agent/overlays/<new-cluster>
   ```

2. **Copy and customize**:
   - Copy from existing overlay (e.g., `cluster-a`)
   - Update cluster name in:
     - `fleet.yaml` (clusterSelector)
     - `promtail-helmchart.yaml` (externalLabels.cluster)
     - `prometheus-agent-helmchart.yaml` (externalLabels.cluster)

3. **Update Fleet GitRepo**:
   Add paths to `fleet-gitrepo.yaml`:
   ```yaml
   paths:
     - observability-agents/promtail/overlays/<new-cluster>
     - observability-agents/prometheus-agent/overlays/<new-cluster>
   ```

### Remote Cluster Configuration

For clusters that don't have direct access to nprd-apps:

1. **Configure external endpoints** in overlay:
   - Loki: `https://loki.dataknife.net/loki/api/v1/push`
   - Prometheus: `https://prometheus.dataknife.net/api/v1/write`

2. **Add authentication** (if required):
   ```yaml
   # Promtail
   clients:
     - url: https://loki.dataknife.net/loki/api/v1/push
       bearer_token_file: /var/run/secrets/loki/token
   
   # Prometheus Agent
   remote_write:
     - url: https://prometheus.dataknife.net/api/v1/write
       basic_auth:
         username: <user>
         password: <pass>
   ```

## Network Requirements

### Outbound (Push Model)

**From each cluster to nprd-apps**:
- Loki: HTTPS to `https://loki.dataknife.net/loki/api/v1/push`
- Prometheus: HTTPS to `https://prometheus.dataknife.net/api/v1/write`

**Firewall rules**: Allow outbound HTTPS (443) from cluster nodes

### Internal (Same Cluster)

**nprd-apps cluster only**:
- Loki: Internal service (`loki-distributor.managed-syslog.svc.cluster.local:3100`)
- Prometheus: Internal service (`prometheus-kube-prometheus-prometheus.managed-syslog.svc.cluster.local:9090`)

## Resources Per Cluster

### Promtail
- CPU: 100-200m per node
- Memory: 128-256Mi per node

### Prometheus Agent
- CPU: 200-500m
- Memory: 256Mi-1Gi

### node-exporter
- CPU: 100m per node
- Memory: 64-128Mi per node

### kube-state-metrics
- CPU: 100-200m
- Memory: 128-256Mi

## See Also

- [Cluster Agents Requirements](../docs/CLUSTER_AGENTS_REQUIREMENTS.md) - Detailed requirements documentation
- [Multi-Cluster Observability](../docs/MULTI_CLUSTER_OBSERVABILITY.md) - Architecture overview
- [Loki Stack](../loki/README.md) - Central Loki deployment
- [Prometheus Stack](../prometheus/README.md) - Central Prometheus deployment
