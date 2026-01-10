# Graylog SIEM and Log Management

Graylog deployment for centralized log management and security monitoring with UniFi CEF support.

## Overview

Graylog is a comprehensive log management and SIEM (Security Information and Event Management) platform that provides:
- **Centralized Log Collection**: Collect logs from various sources including UniFi devices
- **Native CEF Support**: Built-in Common Event Format (CEF) parser for UniFi SIEM integration
- **Real-time Search**: Full-text search and analysis of log data
- **Dashboards and Alerts**: Visual dashboards and alerting capabilities
- **REST API**: Programmatic access to logs and configuration

## Architecture

Graylog consists of three main components:

1. **Graylog Server**: Main log processing and management server
2. **MongoDB**: Metadata store (users, dashboards, streams, etc.)
3. **OpenSearch**: Log storage and indexing engine

All components are deployed using the official Graylog Helm chart.

## Repository Structure

```
graylog/
├── base/                          # Base Graylog configuration
│   ├── fleet.yaml                # Base Fleet config (reference only)
│   ├── kustomization.yaml        # Kustomize base
│   ├── namespace.yaml            # Namespace definition (optional)
│   ├── graylog-helmchart.yaml    # Base Helm chart configuration
│   └── README.md                 # Base documentation
└── overlays/
    └── nprd-apps/                 # nprd-apps cluster overlay
        ├── fleet.yaml            # Cluster-specific Fleet config with targeting
        ├── kustomization.yaml    # Kustomize overlay
        ├── graylog-helmchart.yaml # Cluster-specific Helm values
        └── graylog-syslog-service.yaml # Syslog NodePort service for UniFi CEF
```

## Deployment

### Prerequisites

1. **Namespace**: `managed-tools` namespace must exist
2. **TLS Secret**: `wildcard-dataknife-net-tls` secret must exist for ingress
3. **Fleet GitRepo**: Configured to monitor `graylog/overlays/nprd-apps`

### Fleet Configuration

The main `fleet-gitrepo.yaml` should include:
```yaml
paths:
  - graylog/overlays/nprd-apps
```

### Automatic Deployment

Graylog will be deployed automatically by Fleet when:
1. Fleet syncs the GitRepo
2. The namespace and secrets exist
3. The cluster matches the target selector in `fleet.yaml`

### Manual Deployment (for testing)

```bash
# Apply the overlay directly
kubectl apply -k graylog/overlays/nprd-apps/

# Monitor deployment
kubectl get pods -n managed-tools -l app=graylog
kubectl get helmchart -n managed-tools
```

## Access

Once deployed, access Graylog at:

- **Web UI**: `https://graylog.dataknife.net` (via Ingress)
- **Default Credentials**:
  - Username: `admin`
  - Password: `admin` (default, change via web UI or `GRAYLOG_ROOT_PASSWORD_SHA2` env var)

## UniFi CEF Syslog Configuration

Graylog has native CEF (Common Event Format) support for UniFi SIEM integration.

### Step 1: Configure Syslog Input in Graylog

After deployment, configure the syslog input via Graylog web UI:

1. Log in to Graylog web UI at `https://graylog.dataknife.net`
2. Navigate to **System** → **Inputs**
3. Click **Launch new input**
4. Select **Syslog UDP**
5. Configure:
   - **Title**: UniFi Syslog CEF
   - **Bind address**: `0.0.0.0:514`
   - **Codec**: **CEF** (for Common Event Format parsing)
   - **Allow overriding date**: Yes
   - **Store full message**: Yes (optional, for debugging)
6. Click **Save** and **Start** the input

### Step 2: Configure UniFi Network Application

In your UniFi Network Application:

1. Go to **Settings** → **System Logs**
2. Scroll to **SIEM Integration**
3. Configure:
   - **Enable SIEM Integration**: Yes
   - **Syslog Server**: `<cluster-node-ip>:30514`
     - Example: `192.168.14.113:30514`
     - Use worker node IPs (see `docs/INGRESS_NODE_RECOMMENDATIONS.md`)
   - **Format**: CEF (Common Event Format)
4. Click **Save**

### Step 3: Verify Log Ingestion

1. In Graylog web UI, go to **Search**
2. Search for: `source:unifi` or `vendor:"Ubiquiti"`
3. You should see UniFi events appearing in real-time

## DNS Configuration

For optimal performance, configure DNS to point to worker nodes:

```
graylog.dataknife.net.      IN  A  192.168.14.113
graylog.dataknife.net.      IN  A  192.168.14.114
graylog.dataknife.net.      IN  A  192.168.14.115

graylog-syslog.dataknife.net.  IN  A  192.168.14.113
graylog-syslog.dataknife.net.  IN  A  192.168.14.114
graylog-syslog.dataknife.net.  IN  A  192.168.14.115
```

See `docs/INGRESS_NODE_RECOMMENDATIONS.md` for detailed DNS configuration guidance.

## API Access

Graylog provides a comprehensive REST API for programmatic access:

### Search Logs

```bash
# Search UniFi logs
curl -u admin:admin \
  -X POST https://graylog.dataknife.net/api/search/universal/relative \
  -H "Content-Type: application/json" \
  -d '{"query":"source:unifi", "range":3600}'
```

### GraphQL API (v4.0+)

```bash
curl -u admin:admin \
  -X POST https://graylog.dataknife.net/api/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ search(queryString: \"source:unifi\") { messages { message } } }"}'
```

See [Graylog API Documentation](https://docs.graylog.org/docs/http-api) for full API reference.

## Resource Requirements

### Graylog Server
- **CPU**: 500m request, 2000m limit
- **Memory**: 1Gi request, 4Gi limit
- **Heap**: 2Gi (50% of memory limit)

### MongoDB
- **CPU**: 100m request, 500m limit
- **Memory**: 256Mi request, 512Mi limit
- **Storage**: 20Gi persistent volume

### OpenSearch
- **CPU**: 500m request, 2000m limit
- **Memory**: 2Gi request, 4Gi limit
- **Heap**: 2Gi (50% of memory limit)
- **Storage**: 250Gi persistent volume (sized for 2 weeks retention + growth)
  - Base: 2 UniFi instances @ ~250MB/day each = 7GB for 14 days
  - With overhead: ~10.5GB
  - Growth factor (20x): ~210GB
  - Recommended: 250GB for safety margin

## Index Rotation and Retention Configuration

After deployment, configure index rotation and retention for 2 weeks:

1. Log in to Graylog web UI at `https://graylog.dataknife.net`
2. Navigate to **System** → **Indices**
3. Configure the default index set:
   - **Index Rotation**:
     - Strategy: **Daily** (rotate index every day at midnight UTC)
     - Max number of indices: **20** (14 days + 6 day buffer)
   - **Index Retention**:
     - Strategy: **Delete indices** after retention period
     - Max age: **14 days** (2 weeks)
     - Action: Delete closed indices older than 14 days
   - **Index Configuration**:
     - Shards per index: **1** (single node setup)
     - Replicas: **0** (single node setup)
     - Index optimization: After rotation

These settings ensure:
- ✅ 2 weeks of log retention (14 daily indices)
- ✅ Efficient storage usage with daily rotation
- ✅ Automatic cleanup of old indices
- ✅ Headroom for growth (20 indices = 6 day buffer)

See `graylog-index-config.yaml` for detailed documentation.

## Troubleshooting

### Graylog Web UI Not Accessible

1. Check ingress:
   ```bash
   kubectl get ingress -n managed-tools -l app=graylog
   ```

2. Check service:
   ```bash
   kubectl get svc -n managed-tools -l app=graylog
   ```

3. Check pods:
   ```bash
   kubectl get pods -n managed-tools -l app=graylog
   kubectl logs -n managed-tools -l app=graylog,component=server
   ```

### Syslog Not Receiving Logs

1. Verify syslog input is running:
   - Check Graylog web UI → System → Inputs
   - Ensure input shows "Running" status

2. Check syslog service:
   ```bash
   kubectl get svc -n managed-tools graylog-syslog
   ```

3. Test syslog reception:
   ```bash
   # From a test pod or node
   echo "CEF:0|test|test|1.0|test|test|5|" | nc -u <node-ip> 30514
   ```

4. Check Graylog logs:
   ```bash
   kubectl logs -n managed-tools -l app=graylog,component=server | grep -i syslog
   ```

### Logs Not Appearing in Search

1. Check OpenSearch health:
   ```bash
   kubectl logs -n managed-tools -l app=graylog,component=opensearch
   ```

2. Verify index creation:
   - Check Graylog web UI → System → Indices
   - Ensure indices are being created and rotated

3. Check for parsing errors:
   - Search for: `_exists_:gl2_parser_error`
   - Review CEF codec configuration

## Documentation

- [Graylog Official Documentation](https://docs.graylog.org/)
- [Graylog Helm Chart](https://github.com/Graylog2/charts)
- [UniFi SIEM Integration Guide](https://help.ui.com/hc/en-us/articles/33349041044119-UniFi-System-Logs-SIEM-Integration)
- [CEF Format Specification](https://community.microfocus.com/t5/ArcSight-Connectors/ArcSight-Common-Event-Format-CEF-Guide/ta-p/1677566)
