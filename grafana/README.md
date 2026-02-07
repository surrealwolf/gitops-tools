# Loki Stack

This directory contains GitOps configurations for deploying the Loki Stack (Loki + Promtail + Grafana) to replace Graylog/OpenSearch for log aggregation and visualization.

## Overview

The Loki Stack provides a modern, cloud-native logging solution that replaces the traditional Graylog/OpenSearch stack:

- **Loki**: Log aggregation system (replaces OpenSearch/Elasticsearch)
- **Promtail**: Log collection agent (replaces Filebeat/Logstash)
- **Grafana**: Visualization and query interface (replaces Graylog UI)

## Why Loki?

### Advantages over Graylog/OpenSearch

1. **Simpler Architecture**: Single binary, no separate search index
2. **Lower Resource Usage**: More efficient storage and query patterns
3. **Native Kubernetes Integration**: Built for Kubernetes with automatic pod discovery
4. **LogQL**: Powerful query language optimized for logs
5. **Grafana Integration**: Native integration with Grafana for visualization
6. **Cost Effective**: Lower storage and compute requirements
7. **Faster Queries**: Optimized for log queries vs. general-purpose search

### When to Use Loki

- ✅ Log aggregation and analysis
- ✅ Kubernetes-native log collection
- ✅ Time-series log queries
- ✅ Integration with Prometheus/Grafana stack
- ✅ Cost-effective log storage

### When to Consider Alternatives

- ❌ Full-text search across all fields (Elasticsearch is better)
- ❌ Complex analytics and aggregations (Elasticsearch is better)
- ❌ Very high cardinality use cases (may need tuning)

## Migration (grafana namespace + TrueNAS CSI)

The Loki stack has been migrated to:
- **Namespace**: `grafana` (from `managed-syslog`)
- **Storage**: `truenas-csi-nfs` (TrueNAS CSI, replacing Democratic CSI `truenas-nfs`)
- **Data**: Fresh start (data loss accepted for inaccessible stack)

Before deploying, create the Grafana credentials secret in the new namespace:
```bash
kubectl create secret generic loki-credentials \
  --from-literal=adminPassword="$(openssl rand -base64 32)" \
  -n grafana
```

## Structure

```
grafana/
├── base/                          # Base Loki Stack configuration
│   ├── fleet.yaml                # Base Fleet config
│   ├── kustomization.yaml        # Kustomize base
│   ├── namespace.yaml            # Namespace definition
│   ├── loki-helmchart.yaml       # Loki Stack Helm chart (base values)
│   └── README.md                 # Base documentation
└── overlays/
    └── nprd-apps/                 # nprd-apps cluster overlay
        ├── fleet.yaml            # Cluster-specific Fleet config with targeting
        ├── kustomization.yaml   # Kustomize overlay
        ├── loki-helmchart.yaml   # Override base Helm values for nprd-apps
        └── grafana-ingress.yaml  # Grafana ingress (fallback)
```

## Components

### Loki

Log aggregation system that stores and indexes logs efficiently:

- **Storage**: Filesystem-based (can use S3-compatible storage)
- **Retention**: Configurable (default 14 days for nprd-apps)
- **Scalability**: Horizontal scaling via replicas
- **Query Language**: LogQL (Log Query Language)

### Promtail

Log collection agent that runs as a DaemonSet:

- **Automatic Discovery**: Discovers pods via Kubernetes service discovery
- **Label Extraction**: Automatically extracts labels from pod metadata
- **Multi-line Support**: Handles multi-line log entries
- **Relabeling**: Flexible log routing and filtering

### Grafana

Visualization and query interface:

- **Pre-configured Datasource**: Loki datasource configured automatically
- **LogQL Support**: Full LogQL query language support
- **Dashboards**: Can import Loki-specific dashboards
- **Alerting**: Built-in alerting support

### Vector (Syslog Receiver)

Syslog receiver for external log ingestion:

- **Socket UDP**: Receives raw UDP data on port 514 (exposed via NodePort 30514)
  - Uses `socket` source (not `syslog`) to handle raw CEF format that may not conform to RFC 3164/5424
- **DNS Access**: `vector.dataknife.net:30514` (point DNS to cluster node IPs)
- **CEF Parsing**: Automatically parses CEF (Common Event Format) from UniFi devices
- **Loki Forwarding**: Forwards parsed logs to Loki distributor with proper labels
- **Metrics**: Prometheus metrics exposed at `https://vector.dataknife.net/metrics` (port 9598)
- **Health Checks**: API server on port 8686 (internal)
- **UniFi Integration**: Configured for UniFi SIEM CEF format
- **Configuration**: Follows official Vector documentation patterns

## Deployment

### Prerequisites

1. **Namespace**: The `grafana` namespace will be created automatically
2. **TLS Secret**: For Grafana ingress, ensure `wildcard-dataknife-net-tls` exists
3. **Fleet GitRepo**: Configured to monitor the `grafana/overlays/nprd-apps` path

### Deployment Steps

1. **Create Grafana Admin Password Secret** (recommended):
   ```bash
   GRAFANA_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')
   kubectl create secret generic loki-credentials \
     --from-literal=adminPassword="$GRAFANA_PASSWORD" \
     -n grafana
   ```

2. **Deploy via Fleet**:
   - Fleet will automatically deploy when GitRepo syncs
   - Monitor deployment: `kubectl get pods -n grafana -w`

4. **Verify Deployment**:
   ```bash
   # Check Helm chart
   kubectl get helmchart -n grafana
   
   # Check pods
   kubectl get pods -n grafana
   
   # Check services
   kubectl get svc -n grafana
   
   # Check ingress
   kubectl get ingress -n grafana
   ```

## Access

Once deployed, access the services at:

- **Grafana**: `https://grafana.dataknife.net` (via Ingress)
  - Username: `admin`
  - Password: From `loki-credentials` secret in `grafana` namespace, or auto-generated (check pod logs)

- **Loki API**: `https://loki.dataknife.net` (via Ingress)
  - Loki HTTP API endpoint for direct queries
  - Grafana datasource uses internal service (`http://loki-query-frontend:3100`)

- **Vector Metrics**: `https://vector.dataknife.net/metrics` (via Ingress)
  - Prometheus metrics endpoint (port 9598)
  - Health endpoint: API server on port 8686 (internal)
  - Syslog endpoint: `vector.dataknife.net:30514` (UDP, NodePort)

## Configuration

### Storage Sizing

The nprd-apps overlay is configured with:
- **Loki Storage**: 250Gi (sized for 14 days retention + growth)
  - Base: 2 UniFi instances @ ~250MB/day each = 7GB for 14 days
  - With overhead: ~10.5GB
  - Growth factor (20x): ~210GB
  - Recommended: 250GB for safety margin
- **Grafana Storage**: 10Gi (for dashboards and configuration)

### Retention

- **Base**: 7 days
- **nprd-apps Overlay**: 14 days

To change retention, update `reject_old_samples_max_age` and `max_look_back_period` in the Helm chart values.

### Resource Limits

**Loki** (nprd-apps):
- Requests: 1000m CPU, 2Gi memory
- Limits: 4000m CPU, 8Gi memory

**Promtail** (nprd-apps):
- Requests: 200m CPU, 256Mi memory
- Limits: 1000m CPU, 1Gi memory

**Grafana** (nprd-apps):
- Requests: 200m CPU, 256Mi memory
- Limits: 1000m CPU, 1Gi memory

## LogQL Queries

Loki uses LogQL (Log Query Language) for querying logs. Example queries:

### Basic Queries

```logql
# Count logs by namespace
sum(count_over_time({namespace="default"}[5m]))

# Filter logs by label
{app="nginx"} |= "error"

# Rate of errors
rate({app="nginx"} |= "error" [5m])

# Top 10 log sources
topk(10, sum by (app) (count_over_time({}[5m])))
```

### Advanced Queries

```logql
# Error rate by namespace
sum(rate({} |= "error" [5m])) by (namespace)

# Logs with specific label combinations
{namespace="production", app="api"} | json | level="error"

# Extract and aggregate
{app="nginx"} | regexp "(?P<status>\\d{3})" | sum by (status) (count_over_time({}[1m]))
```

## Migration from Graylog/OpenSearch

### Migration Steps

1. **Deploy Loki Stack**: Deploy this configuration alongside Graylog
2. **Verify Collection**: Ensure Promtail is collecting logs from all namespaces
3. **Test Queries**: Verify LogQL queries work correctly
4. **Configure Dashboards**: Set up Grafana dashboards for common queries
5. **Update Applications**: Update applications to use Loki endpoints if needed
6. **Archive Old Logs**: Export important logs from Graylog before decommissioning
7. **Decommission Graylog**: Once verified, remove Graylog/OpenSearch

### Query Translation

**Graylog Query**:
```
source:nginx AND level:ERROR
```

**Loki LogQL Equivalent**:
```logql
{app="nginx"} |= "ERROR"
```

**Graylog Query**:
```
source:api AND http_status_code:500
```

**Loki LogQL Equivalent**:
```logql
{app="api"} | json | status_code=500
```

## Troubleshooting

### Promtail Not Collecting Logs

1. Check Promtail pods:
   ```bash
   kubectl get pods -n grafana -l app=promtail
   kubectl logs -n grafana -l app=promtail
   ```

2. Verify Promtail has access to node logs:
   ```bash
   kubectl describe daemonset promtail -n grafana
   ```

3. Check Promtail configuration:
   ```bash
   kubectl get configmap loki-stack-promtail -n grafana -o yaml
   ```

### Loki Not Receiving Logs

1. Check Loki service:
   ```bash
   kubectl get svc loki -n grafana
   ```

2. Test Loki endpoint:
   ```bash
   kubectl port-forward -n grafana svc/loki 3100:3100
   curl http://localhost:3100/ready
   ```

3. Check Loki logs:
   ```bash
   kubectl logs -n grafana -l app=loki
   ```

### Grafana Not Accessible

1. Check ingress:
   ```bash
   kubectl get ingress -n grafana
   kubectl describe ingress grafana -n grafana
   ```

2. Verify TLS secret exists:
   ```bash
   kubectl get secret wildcard-dataknife-net-tls -n grafana
   ```

3. Check Grafana service:
   ```bash
   kubectl get svc loki-stack-grafana -n grafana
   ```

## Documentation

- [Loki Documentation](https://grafana.com/docs/grafana/latest/)
- [Promtail Documentation](https://grafana.com/docs/grafana/latest/clients/promtail/)
- [LogQL Documentation](https://grafana.com/docs/grafana/latest/logql/)
- [Grafana Loki Helm Chart](https://github.com/grafana/helm-charts/tree/main/charts/loki-stack)
- [Grafana Documentation](https://grafana.com/docs/grafana/latest/)

## UniFi CEF Syslog Integration

The Loki Stack includes Vector as a syslog receiver for UniFi CEF format logs:

- **Service Type**: NodePort (UDP port 30514 for external access)
- **DNS Access**: `vector.dataknife.net:30514` (point DNS to cluster node IPs)
- **Source Type**: Socket source (handles raw CEF format, not RFC-compliant syslog)
- **CEF Parsing**: Automatically parses CEF format and extracts fields
- **Loki Integration**: Forwards to Loki distributor with labels (`namespace=unifi`, `app=unifi-cef`, `source=syslog`, `format=cef`)
- **Metrics**: Prometheus metrics available at `https://vector.dataknife.net/metrics`
- **Configuration**: Follows official Vector documentation ([Socket Source](https://vector.dev/docs/reference/configuration/sources/socket/), [Loki Sink](https://vector.dev/docs/reference/configuration/sinks/grafana/), [Prometheus Exporter Sink](https://vector.dev/docs/reference/configuration/sinks/prometheus_exporter/))

See [UniFi CEF Setup Guide](docs/grafana/UNIFI_CEF_SETUP.md) for detailed configuration instructions.

## See Also

- [Base Configuration README](base/README.md)
- [Secrets Documentation](../secrets/grafana/README.md)
- [UniFi CEF Setup Guide](docs/grafana/UNIFI_CEF_SETUP.md)
