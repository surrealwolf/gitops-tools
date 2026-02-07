# Prometheus Stack

This directory contains GitOps configurations for deploying the Prometheus Stack (Prometheus + Alertmanager + node-exporter + kube-state-metrics) for comprehensive metrics monitoring alongside the Loki log aggregation stack.

## Overview

The Prometheus Stack provides metrics monitoring capabilities that complement the Loki log aggregation system:

- **Prometheus**: Metrics collection and storage (complements Loki for logs)
- **Alertmanager**: Alert management and routing
- **node-exporter**: Node-level metrics (CPU, memory, disk, network)
- **kube-state-metrics**: Cluster state metrics (Deployments, Pods, Services, etc.)
- **Prometheus Operator**: Manages Prometheus and ServiceMonitor/PodMonitor CRDs

## Why Prometheus?

### Advantages

1. **Native Kubernetes Integration**: Designed for Kubernetes with ServiceMonitor/PodMonitor CRDs
2. **Comprehensive Metrics**: Covers cluster, node, and application-level metrics
3. **PromQL**: Powerful query language for metrics
4. **Grafana Integration**: Native integration with Grafana (already deployed)
5. **Alerting**: Built-in alerting rules for Kubernetes
6. **Scalability**: Handles high-cardinality metrics efficiently

### Use Cases

- ✅ Cluster resource monitoring (CPU, memory, disk)
- ✅ Application metrics collection
- ✅ Kubernetes component health monitoring
- ✅ Alerting on critical conditions
- ✅ Integration with Grafana dashboards
- ✅ Time-series metrics storage and querying

## Structure

```
prometheus/
├── base/                          # Base Prometheus Stack configuration
│   ├── fleet.yaml                # Base Fleet config
│   ├── kustomization.yaml        # Kustomize base
│   ├── namespace.yaml            # Namespace definition
│   ├── prometheus-helmchart.yaml # Prometheus Stack Helm chart (base values)
│   └── README.md                 # Base documentation
└── overlays/
    └── nprd-apps/                 # nprd-apps cluster overlay
        ├── fleet.yaml            # Cluster-specific Fleet config with targeting
        ├── kustomization.yaml   # Kustomize overlay
        └── prometheus-helmchart.yaml  # Override base Helm values for nprd-apps
```

## Components

### Prometheus

Metrics collection and storage system:
- **Storage**: PVC-based (200Gi for nprd-apps)
- **Retention**: 30 days (configurable)
- **Discovery**: Automatically discovers ServiceMonitors and PodMonitors
- **Query Language**: PromQL

### Alertmanager

Alert management and routing:
- **Retention**: 7 days (nprd-apps)
- **Storage**: 20Gi PVC
- **Features**: Alert grouping, routing, and silencing

### node-exporter

DaemonSet that collects node-level metrics:
- **Metrics**: CPU, memory, disk I/O, network, filesystem
- **Collection**: One pod per node
- **Exposed Port**: 9100

### kube-state-metrics

Exposes cluster state as metrics:
- **Metrics**: Deployment status, Pod phases, Service endpoints, etc.
- **Usage**: Essential for Kubernetes monitoring dashboards

### Prometheus Operator

Manages Prometheus deployments and CRDs:
- **CRDs**: ServiceMonitor, PodMonitor, PrometheusRule, AlertmanagerConfig
- **Features**: Automatic target discovery and configuration

## Deployment

### Prerequisites

1. **Namespace**: The `managed-syslog` namespace will be created automatically
2. **Fleet GitRepo**: Configured to monitor the `prometheus/overlays/nprd-apps` path
3. **Grafana**: Already deployed in the Loki stack (will be updated with Prometheus datasource)

### Deployment Steps

1. **Deploy via Fleet**:
   - Fleet will automatically deploy when GitRepo syncs
   - Monitor deployment: `kubectl get pods -n managed-syslog -w`

2. **Verify Deployment**:
   ```bash
   # Check Helm chart
   kubectl get helmchart -n managed-syslog prometheus
   
   # Check pods
   kubectl get pods -n managed-syslog | grep prometheus
   
   # Check services
   kubectl get svc -n managed-syslog | grep prometheus
   
   # Check Prometheus UI (port-forward)
   kubectl port-forward -n managed-syslog svc/prometheus-kube-prometheus-prometheus 9090:9090
   ```

3. **Verify Metrics Collection**:
   ```bash
   # Check targets in Prometheus UI (after port-forward)
   # Navigate to: http://localhost:9090/targets
   
   # Verify node-exporter is collecting metrics
   kubectl get pods -n managed-syslog -l app.kubernetes.io/name=prometheus-node-exporter
   
   # Verify kube-state-metrics is running
   kubectl get pods -n managed-syslog -l app.kubernetes.io/name=kube-state-metrics
   ```

## Access

Once deployed, access Prometheus at:

- **Prometheus UI**: Port-forward to service `prometheus-kube-prometheus-prometheus` on port 9090
- **Alertmanager UI**: Port-forward to service `prometheus-kube-prometheus-alertmanager` on port 9093
- **Grafana**: Already accessible at `https://grafana.dataknife.net` (will include Prometheus datasource)

## Configuration

### Storage Sizing

The nprd-apps overlay is configured with:
- **Prometheus Storage**: 200Gi (sized for 30 days retention)
- **Alertmanager Storage**: 20Gi

### Retention

- **Base**: 15 days
- **nprd-apps Overlay**: 30 days

To change retention, update `retention` in the Helm chart values.

### Resource Limits

**Prometheus** (nprd-apps):
- Requests: 1000m CPU, 2Gi memory
- Limits: 4000m CPU, 8Gi memory

**Alertmanager** (nprd-apps):
- Requests: 200m CPU, 256Mi memory
- Limits: 1000m CPU, 1Gi memory

**node-exporter** (nprd-apps):
- Requests: 100m CPU, 128Mi memory
- Limits: 500m CPU, 256Mi memory

**kube-state-metrics** (nprd-apps):
- Requests: 200m CPU, 256Mi memory
- Limits: 500m CPU, 512Mi memory

## ServiceMonitors and PodMonitors

The Prometheus Operator automatically discovers metrics targets via:

- **ServiceMonitor**: Scrapes metrics from services
- **PodMonitor**: Scrapes metrics from pods

### Example: ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: my-namespace
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

### Example: PodMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: my-app
  namespace: my-namespace
spec:
  selector:
    matchLabels:
      app: my-app
  podMetricsEndpoints:
  - port: metrics
    interval: 30s
```

## PromQL Queries

Prometheus uses PromQL (Prometheus Query Language) for querying metrics. Example queries:

### Basic Queries

```promql
# CPU usage percentage
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Memory usage
node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes

# Disk usage
100 - ((node_filesystem_avail_bytes{mountpoint="/"} * 100) / node_filesystem_size_bytes{mountpoint="/"})

# Pod count by namespace
count by (namespace) (kube_pod_info)

# Container restarts
rate(kube_pod_container_status_restarts_total[5m])
```

### Advanced Queries

```promql
# Request rate by service
sum(rate(nginx_http_requests_total[5m])) by (service)

# Error rate percentage
sum(rate(http_requests_total{status=~"5.."}[5m])) / sum(rate(http_requests_total[5m])) * 100

# Top 10 pods by CPU usage
topk(10, sum by (pod, namespace) (rate(container_cpu_usage_seconds_total[5m])))

# Node availability
avg_over_time(up{job="node-exporter"}[1h])
```

## Integration with Grafana

Grafana is already deployed in the Loki stack. The Prometheus datasource will be automatically added to Grafana (configured in the Loki overlay).

### Pre-configured Dashboards

You can import pre-configured Kubernetes dashboards:
- **Node Exporter Full**: Dashboard ID 1860
- **Kubernetes / Compute Resources / Cluster**: Dashboard ID 15757
- **Kubernetes / Compute Resources / Namespace (Pods)**: Dashboard ID 15758
- **Kubernetes / Compute Resources / Pod**: Dashboard ID 15759

Import via Grafana UI: Configuration → Data Sources → Prometheus → Dashboards

## Alerting Rules

The Prometheus Stack includes default alerting rules for:

- **Kubernetes**: API server, etcd, kubelet, kube-proxy
- **Node**: CPU, memory, disk, network
- **Prometheus**: Prometheus itself and Prometheus Operator
- **General**: Cluster and application health

Alerts are automatically discovered via PrometheusRule CRDs.

## Troubleshooting

### Prometheus Not Collecting Metrics

1. Check Prometheus targets:
   ```bash
   kubectl port-forward -n managed-syslog svc/prometheus-kube-prometheus-prometheus 9090:9090
   # Navigate to http://localhost:9090/targets
   ```

2. Check ServiceMonitors:
   ```bash
   kubectl get servicemonitors -A
   kubectl describe servicemonitor <name> -n <namespace>
   ```

3. Check Prometheus Operator logs:
   ```bash
   kubectl logs -n managed-syslog -l app.kubernetes.io/name=prometheus-operator
   ```

### node-exporter Not Running

1. Check DaemonSet:
   ```bash
   kubectl get daemonset -n managed-syslog -l app.kubernetes.io/name=prometheus-node-exporter
   kubectl describe daemonset prometheus-kube-prometheus-node-exporter -n managed-syslog
   ```

2. Check pods:
   ```bash
   kubectl get pods -n managed-syslog -l app.kubernetes.io/name=prometheus-node-exporter
   kubectl logs -n managed-syslog -l app.kubernetes.io/name=prometheus-node-exporter
   ```

### Metrics Not Appearing in Grafana

1. Verify Prometheus datasource is configured in Grafana
2. Check Prometheus is accessible from Grafana:
   ```bash
   kubectl exec -n managed-syslog -it deployment/loki-stack-grafana -- wget -O- http://prometheus-kube-prometheus-prometheus:9090/api/v1/status/config
   ```

3. Verify ServiceMonitor/PodMonitor labels match Prometheus selector

## Documentation

- [Prometheus Documentation](https://prometheus.io/docs/)
- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)
- [kube-prometheus-stack Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
- [PromQL Documentation](https://prometheus.io/docs/prometheus/latest/querying/basics/)
- [ServiceMonitor CRD](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api.md#servicemonitor)
- [PrometheusRule CRD](https://github.com/prometheus-operator/prometheus-operator/blob/main/Documentation/api.md#prometheusrule)

## See Also

- [Grafana Stack](../grafana/README.md) - Log aggregation and visualization
- [Base Configuration README](base/README.md)