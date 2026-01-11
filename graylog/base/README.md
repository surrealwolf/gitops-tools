# Graylog Base Configuration

Base configuration for Graylog deployment using Helm charts.

## Structure

```
graylog/
├── base/                          # Base Graylog configuration
│   ├── fleet.yaml                # Base Fleet config (typically not deployed directly)
│   ├── kustomization.yaml        # Kustomize base
│   ├── namespace.yaml            # Namespace definition (optional if exists)
│   ├── graylog-helmchart.yaml    # Graylog Helm chart configuration
│   └── README.md                 # This file
└── overlays/
    └── nprd-apps/                 # nprd-apps cluster overlay
        ├── fleet.yaml            # Cluster-specific Fleet config with targeting
        ├── kustomization.yaml    # Kustomize overlay
        └── graylog-helmchart.yaml # Override base Helm values for nprd-apps
```

## Components

Graylog requires three main components:

1. **Graylog Server**: Main log management server
2. **MongoDB**: Metadata store (users, dashboards, streams, etc.)
3. **OpenSearch/Elasticsearch**: Log storage and indexing

The Helm chart can deploy all three components automatically.

## Configuration

### Base Configuration (`graylog-helmchart.yaml`)

- **MongoDB**: Internal deployment with 20Gi storage (sufficient for metadata)
- **OpenSearch**: Internal deployment with 50Gi storage (base size, overlay increases to 250Gi)
- **Graylog**: Single replica with 2Gi heap
- **Ingress**: Disabled (enabled in overlay for cluster-specific host)

### Overlay Configuration (`graylog/overlays/nprd-apps/`)

Cluster-specific customizations:
- **OpenSearch**: 250Gi storage (sized for 2 weeks retention + growth)
  - Base: 2 UniFi instances @ ~250MB/day each = 7GB for 14 days
  - With overhead: ~10.5GB
  - Growth factor (20x): ~210GB
  - Recommended: 250GB for safety margin
- Ingress with host `graylog.dataknife.net`
- External URI configuration
- Password secrets
- Resource limits
- Syslog input configuration for UniFi CEF

### Overlay Configuration (`graylog/overlays/nprd-apps/`)

Cluster-specific customizations:
- Ingress with host `graylog.dataknife.net`
- External URI configuration
- Password secrets
- Resource limits
- Syslog input configuration for UniFi CEF

## Deployment

The Graylog HelmChart will be deployed automatically by Fleet when:
1. The namespace `managed-tools` exists
2. The TLS secret `wildcard-dataknife-net-tls` exists (for ingress)
3. Fleet syncs the GitRepo

Monitor deployment:
```bash
kubectl get helmchart -n managed-tools
kubectl get pods -n managed-tools -l app=graylog
kubectl get ingress -n managed-tools -l app=graylog
```

## Access

Once deployed, access Graylog at:
- **URL**: `https://graylog.dataknife.net` (via Ingress)
- **Default credentials**: Configured in overlay
  - Username: `admin`
  - Password: Set via `GRAYLOG_ROOT_PASSWORD_SHA2` environment variable (SHA256 hash)
  - **Note**: `GRAYLOG_ROOT_PASSWORD_SHA2` must be a SHA256 hash, not a plain password
  - Password hash is stored in secret (configured per overlay)

## UniFi CEF Syslog Configuration

After deployment, configure syslog input via Graylog web UI:

1. Go to **System** → **Inputs**
2. Click **Launch new input**
3. Select **Syslog UDP**
4. Configure:
   - **Title**: UniFi Syslog CEF
   - **Bind address**: 0.0.0.0:514
   - **Codec**: CEF (for Common Event Format parsing)
   - **Allow overriding date**: Yes
5. Save and start the input

Alternatively, expose syslog via NodePort service (configured in overlay) for external access.

## Documentation

- [Graylog Documentation](https://docs.graylog.org/)
- [Graylog Helm Chart](https://github.com/Graylog2/charts)
- [UniFi SIEM Integration](https://help.ui.com/hc/en-us/articles/33349041044119-UniFi-System-Logs-SIEM-Integration)
