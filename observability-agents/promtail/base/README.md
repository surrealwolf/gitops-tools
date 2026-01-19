# Promtail Base Configuration

This directory contains the base configuration for deploying Promtail to collect and push logs to the centralized Loki instance.

## Overview

Promtail is a log collection agent that:
- Runs as a DaemonSet (one pod per node)
- Discovers and scrapes pod logs from `/var/log/pods/`
- Pushes logs to the central Loki instance with cluster labels

## Base Configuration

The base configuration provides:
- Standard log scraping configuration
- Kubernetes pod discovery
- Label extraction from pod metadata
- Base resource limits

## Cluster-Specific Overrides

Each cluster overlay should override:
1. **Loki endpoint**: Internal service URL (same cluster) or external URL (remote clusters)
2. **Cluster label**: Unique identifier for the cluster
3. **Resource limits**: Adjust based on cluster size

## Example Overlay Configuration

```yaml
# observability-agents/promtail/overlays/poc-apps/promtail-helmchart.yaml
config:
  clients:
    - url: https://loki.dataknife.net/loki/api/v1/push  # External endpoint
      externalLabels:
        cluster: "poc-apps"
```

## Deployment

Deploy via Fleet by monitoring the cluster-specific overlay path:
- `observability-agents/promtail/overlays/nprd-apps`
- `observability-agents/promtail/overlays/cluster-a`
- etc.
