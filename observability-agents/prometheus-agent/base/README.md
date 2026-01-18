# Prometheus Agent Base Configuration

This directory contains the base configuration for deploying Prometheus Agent to collect and push metrics to the centralized Prometheus instance.

## Overview

Prometheus Agent is a lightweight metrics collection agent that:
- Runs as a Deployment
- Scrapes metrics from node-exporter and kube-state-metrics
- Pushes metrics to central Prometheus via remote write API
- No local storage (stateless)

## Components

1. **Prometheus Agent**: Lightweight agent for remote write
2. **node-exporter**: DaemonSet for node-level metrics (CPU, memory, disk, network)
3. **kube-state-metrics**: Deployment for cluster state metrics (deployments, pods, services)

## Base Configuration

The base configuration provides:
- Standard scrape configurations for node-exporter and kube-state-metrics
- Remote write queue configuration
- Base resource limits

## Cluster-Specific Overrides

Each cluster overlay should override:
1. **Remote write endpoint**: Internal service URL (same cluster) or external URL (remote clusters)
2. **Cluster label**: Unique identifier for the cluster
3. **Resource limits**: Adjust based on cluster size

## Example Overlay Configuration

```yaml
# observability-agents/prometheus-agent/overlays/my-cluster/prometheus-agent-helmchart.yaml
config:
  global:
    external_labels:
      cluster: "my-cluster"
  remote_write:
    - url: https://prometheus.dataknife.net/api/v1/write  # External endpoint
```

## Deployment

Deploy via Fleet by monitoring the cluster-specific overlay path:
- `observability-agents/prometheus-agent/overlays/nprd-apps`
- `observability-agents/prometheus-agent/overlays/cluster-a`
- etc.
