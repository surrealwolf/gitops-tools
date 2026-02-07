# Loki Base Configuration

Base configuration for Loki Stack deployment using Helm charts.

## Structure

```
grafana/
├── base/                          # Base configuration (reference only)
│   ├── fleet.yaml
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── loki-helmchart.yaml        # Reference – overlay has RustFS S3 config
│   ├── promtail-helmchart.yaml
│   ├── grafana-helmchart.yaml
│   ├── prometheus-helmchart.yaml  # Metrics (kube-prometheus-stack)
│   └── README.md
└── overlays/
    └── nprd-apps/                 # nprd-apps cluster overlay (deployed by Fleet)
        ├── fleet.yaml
        ├── kustomization.yaml
        ├── loki-helmchart.yaml
        ├── promtail-helmchart.yaml
        ├── grafana-helmchart.yaml
        ├── prometheus-helmchart.yaml
        └── vector-*.yaml          # Syslog receiver for UniFi CEF
```

## Components

The Loki Stack includes three main components:

1. **Loki**: Log aggregation system (replacement for OpenSearch/Elasticsearch)
2. **Promtail**: Log collection agent (replacement for Filebeat/Logstash)
3. **Grafana**: Visualization and query interface (replacement for Graylog UI)

## Configuration

Base files are **reference only** – Fleet deploys from the overlay. The overlay has cluster-specific config (e.g. Loki with RustFS S3).

### Loki Features

- **Storage**: RustFS S3-compatible (external); credentials from `loki-rustfs-credentials` secret
- **Retention**: Configurable retention period (default 7 days)
- **Scalability**: Can scale horizontally by increasing replicas
- **Query Performance**: Optimized for log queries with LogQL query language

### Promtail Features

- **Automatic Discovery**: Discovers pods via Kubernetes service discovery
- **Label Extraction**: Automatically extracts labels from pod metadata
- **Multi-line Log Support**: Handles multi-line log entries
- **Relabeling**: Flexible log routing and filtering

### Grafana Features

- **Pre-configured Datasource**: Loki datasource configured automatically
- **LogQL Support**: Full LogQL query language support
- **Dashboards**: Can import Loki-specific dashboards
- **Alerting**: Built-in alerting support

## Deployment

The Loki Stack HelmChart will be deployed automatically by Fleet when:
1. The namespace `grafana` exists
2. Fleet syncs the GitRepo

Monitor deployment:
```bash
kubectl get helmchart -n grafana
kubectl get pods -n grafana
kubectl get ingress -n grafana
```

## Access

Once deployed, access the services at:

- **Grafana**: `https://grafana.dataknife.net` (via Ingress, configured in overlay)
  - Username: `admin`
  - Password: Set via secret (configured per overlay)

- **Loki API**: `https://loki.dataknife.net` (via Ingress, configured in overlay)
  - Loki HTTP API endpoint for direct queries
  - Grafana datasource uses internal service (`http://loki:3100`)

## LogQL Queries

Loki uses LogQL (Log Query Language) for querying logs. Example queries:

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

## Migration from Graylog/OpenSearch

When replacing Graylog/OpenSearch with Loki:

1. **Stop Graylog ingestion**: Disable log forwarding to Graylog
2. **Deploy Loki Stack**: Deploy this configuration
3. **Verify Promtail**: Ensure Promtail is collecting logs from all namespaces
4. **Configure Grafana**: Set up dashboards and alerts in Grafana
5. **Update Applications**: Update applications to use Loki endpoints if needed
6. **Archive Old Logs**: Export important logs from Graylog before decommissioning

## Documentation

- [Loki Documentation](https://grafana.com/docs/grafana/latest/)
- [Promtail Documentation](https://grafana.com/docs/grafana/latest/clients/promtail/)
- [LogQL Documentation](https://grafana.com/docs/grafana/latest/logql/)
- [Grafana Loki Helm Chart](https://github.com/grafana/helm-charts/tree/main/charts/loki-stack)
