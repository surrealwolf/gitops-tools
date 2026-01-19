# Multi-Cluster Observability Setup

This document describes what needs to be deployed on each cluster to push logs and metrics to the centralized observability platform running on **nprd-apps** cluster in the `managed-syslog` namespace.

## Architecture Overview

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
│  Remote Cluster A                                             │
│  ┌──────────┐  ┌─────────────────┐                          │
│  │ Promtail │  │ Prometheus Agent│                          │
│  │ (Daemon) │  │ (Remote Write)  │                          │
│  └──────────┘  └─────────────────┘                          │
└───────────────────────────────────────────────────────────────┘
        │              │
┌───────┴──────────────┴───────────────────────────────────────┐
│  Remote Cluster B                                             │
│  ┌──────────┐  ┌─────────────────┐                          │
│  │ Promtail │  │ Prometheus Agent│                          │
│  │ (Daemon) │  │ (Remote Write)  │                          │
│  └──────────┘  └─────────────────┘                          │
└───────────────────────────────────────────────────────────────┘
```

## What Each Cluster Needs

### 1. Logs → Loki (via Promtail)

**Component**: Promtail (DaemonSet)

**What it does**:
- Runs on each node as a DaemonSet
- Scrapes pod logs from `/var/log/pods/`
- Pushes logs to Loki distributor via HTTP

**Configuration needed**:
- Loki endpoint URL (external endpoint for remote clusters)
- Cluster label to identify logs from different clusters

**Resources per cluster**:
- CPU: 100-200m per node
- Memory: 128-256Mi per node

### 2. Metrics → Prometheus (via Remote Write)

**Component**: Prometheus Agent (Remote Write Mode)

**What it does**:
- Runs as a Deployment/DaemonSet
- Scrapes metrics from node-exporter, kube-state-metrics, and ServiceMonitors
- Pushes metrics to Prometheus via remote write API

**Configuration needed**:
- Prometheus remote write endpoint URL
- Metrics collection configuration (what to scrape)

**Resources per cluster**:
- CPU: 500m
- Memory: 512Mi-1Gi

**Alternative**: If you prefer pull model, deploy:
- node-exporter (DaemonSet)
- kube-state-metrics (Deployment)
- Expose metrics endpoints via LoadBalancer/Ingress for central Prometheus to scrape

## Deployment Options

### Option 1: Fleet-based (Recommended)

Deploy Promtail and Prometheus Agent to all clusters via Fleet with cluster-specific configurations.

### Option 2: Manual Deployment

Deploy agents to each cluster manually with cluster-specific configuration.

### Option 3: Hybrid

Use Fleet for managed clusters, manual deployment for external/unmanaged clusters.

## Required Information

For each remote cluster, you need:

1. **Cluster Name/Label**: To identify metrics/logs in Grafana
2. **Network Access**: 
   - Loki endpoint: `https://loki.dataknife.net` (or internal endpoint)
   - Prometheus remote write endpoint: `https://prometheus.dataknife.net/api/v1/write` (or internal)
3. **Authentication** (if required):
   - Loki: Basic auth or bearer token
   - Prometheus: Basic auth or bearer token

## Next Steps

1. Create base configurations for Promtail and Prometheus Agent
2. Create cluster-specific overlays with cluster labels and endpoints
3. Update Fleet GitRepo to include remote cluster paths
4. Configure ingress/external access for Loki and Prometheus APIs
