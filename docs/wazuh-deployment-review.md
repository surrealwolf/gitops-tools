# Wazuh Deployment Review for nprd-apps

This document reviews how to deploy Wazuh to the `nprd-apps` cluster following the same GitOps pattern used for Harbor.

## Overview

Wazuh is an open-source security monitoring platform that includes:
- **Wazuh Indexer**: Stores and indexes security data (based on OpenSearch)
- **Wazuh Server (Manager)**: Analyzes data from agents and triggers alerts
- **Wazuh Dashboard**: Web UI for visualizing and managing security events

## Deployment Pattern

Following the Harbor deployment pattern, Wazuh should be structured as:

```
wazuh/
├── base/                      # Base Wazuh configuration
│   ├── fleet.yaml            # Base Fleet config (typically not deployed directly)
│   ├── kustomization.yaml    # Kustomize base
│   ├── namespace.yaml        # managed-tools namespace (if needed)
│   ├── wazuh-indexer-helmchart.yaml      # Wazuh Indexer HelmChart (if available)
│   ├── wazuh-server-helmchart.yaml       # Wazuh Server HelmChart (if available)
│   ├── wazuh-dashboard-helmchart.yaml    # Wazuh Dashboard HelmChart (if available)
│   └── README.md             # Base configuration documentation
└── overlays/
    └── nprd-apps/            # nprd-apps cluster overlay
        ├── fleet.yaml        # Cluster-specific Fleet config with targeting
        └── kustomization.yaml
```

## Wazuh Kubernetes Deployment Options

According to the [Wazuh Kubernetes documentation](https://documentation.wazuh.com/current/installation-guide/installation-alternatives/kubernetes-deployment.html), Wazuh can be deployed on Kubernetes using:

### Option 1: Official Wazuh Kubernetes Manifest (Recommended)

Wazuh provides official Kubernetes manifests that can be customized and deployed via GitOps. These are available from the [Wazuh repository](https://github.com/wazuh/wazuh-kubernetes).

**Structure:**
- Raw Kubernetes YAML manifests (not Helm charts)
- Need to be converted to Kustomize resources
- Components deployed separately (Indexer, Server, Dashboard)

**Key Components:**
- StatefulSets for persistent data (Indexer, Server)
- Deployments for stateless components
- Services for internal communication
- ConfigMaps for configuration
- Secrets for credentials and certificates

### Option 2: Wazuh Helm Chart (Community/Third-Party)

Some community-maintained Helm charts may exist, but Wazuh doesn't provide an official Helm chart repository like Harbor does.

**Considerations:**
- Verify chart maintenance status
- Review security and compatibility
- May need custom modifications

### Option 3: Operator-Based Deployment

Wazuh doesn't have an official Kubernetes operator, so this would require custom development.

## Recommended Approach: Kubernetes Manifests + Kustomize

Given that Wazuh provides official Kubernetes manifests and your repository uses Kustomize, the recommended approach is:

1. **Use official Wazuh Kubernetes manifests** from the Wazuh repository
2. **Convert to Kustomize resources** following the Harbor pattern
3. **Deploy via Fleet** with cluster targeting

## Prerequisites

Based on the Harbor pattern and Wazuh requirements:

### 1. Namespace
- **Namespace**: `managed-tools` (shared with other tools)
- Ensure namespace exists before deployment

### 2. TLS Certificates
- Use existing `wildcard-dataknife-net-tls` secret for Dashboard ingress
- Wazuh components use internal TLS for inter-component communication
- Generate internal certificates using Wazuh's certificate generation tools

### 3. Storage
- **Storage Class**: `truenas-nfs` (matching Harbor pattern)
- **Wazuh Indexer**: Requires persistent storage for data
- **Wazuh Server**: Requires persistent storage for logs and configuration
- **Wazuh Dashboard**: Typically stateless (no persistent storage needed)

### 4. Resources
- **CPU**: Based on expected load and agent count
- **Memory**: Indexer requires significant memory (4GB+ recommended)
- **Storage**: 
  - Indexer: 50GB+ (depends on retention)
  - Server: 10GB+ (depends on log retention)

### 5. Network
- Ingress for Dashboard (external access)
- Internal services for component communication
- Load balancer or NodePort for agent connections (if external)

## Deployment Structure

### Base Configuration (`wazuh/base/`)

**kustomization.yaml:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: managed-tools

resources:
  - wazuh-indexer-deployment.yaml
  - wazuh-indexer-service.yaml
  - wazuh-indexer-statefulset.yaml
  - wazuh-server-deployment.yaml
  - wazuh-server-service.yaml
  - wazuh-server-statefulset.yaml
  - wazuh-dashboard-deployment.yaml
  - wazuh-dashboard-service.yaml
  - wazuh-dashboard-ingress.yaml
  - wazuh-configmap.yaml
  - wazuh-secrets.yaml

commonLabels:
  app: wazuh
  managed-by: gitops
```

**fleet.yaml:**
```yaml
defaultNamespace: managed-tools

# Uncomment to prevent base bundle from being deployed directly
# targetCustomizations: []
```

### Overlay Configuration (`wazuh/overlays/nprd-apps/`)

**kustomization.yaml:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: managed-tools

resources:
  - ../../base

# Cluster-specific patches for nprd-apps
patches:
  - path: resource-limits.yaml
  - path: storage-class.yaml
```

**fleet.yaml:**
```yaml
defaultNamespace: managed-tools

targetCustomizations:
  - name: nprd-apps
    clusterSelector:
      matchLabels:
        # Update to match your nprd-apps cluster labels
        managed.cattle.io/cluster-name: nprd-apps
```

## Key Configuration Files

### 1. Wazuh Indexer Configuration
- Persistent volumes for data storage
- Resource limits and requests
- Cluster configuration (if multi-node)
- Security settings

### 2. Wazuh Server Configuration
- Connection to Indexer
- Agent enrollment settings
- Rule and decoder configuration
- Active response settings

### 3. Wazuh Dashboard Configuration
- Connection to Indexer
- Authentication settings
- TLS/SSL configuration
- Ingress configuration

### 4. Secrets Management
- Indexer credentials
- Server API keys
- Dashboard admin password
- TLS certificates

## Wazuh-Specific Considerations

### Component Communication
- Components communicate over TLS
- Need to generate certificates using Wazuh tools
- Certificates stored in Kubernetes secrets

### Agent Connections
- Wazuh agents connect to Wazuh Server
- May need LoadBalancer or NodePort service
- Consider agent enrollment tokens

### Data Persistence
- Indexer data must be persisted
- Server logs and configuration should be persisted
- Backup strategy needed

### Resource Requirements
- **Indexer**: CPU and memory intensive
- **Server**: Moderate resources
- **Dashboard**: Lightweight

### Security
- All components use TLS internally
- Dashboard should use HTTPS via ingress
- Secure credential management

## Steps to Deploy

### Step 1: Get Wazuh Kubernetes Manifests

```bash
# Clone Wazuh Kubernetes repository
git clone https://github.com/wazuh/wazuh-kubernetes.git
cd wazuh-kubernetes

# Review available deployment configurations
ls -la
```

### Step 2: Generate Certificates

```bash
# Download Wazuh installation assistant
curl -sO https://packages.wazuh.com/4.14/wazuh-install.sh
chmod 744 wazuh-install.sh

# Generate certificates
./wazuh-install.sh -g

# Extract certificates to create Kubernetes secrets
# This creates wazuh-install-files.tar
```

### Step 3: Create Base Manifests

1. Copy relevant manifests from Wazuh Kubernetes repository
2. Adapt to your cluster requirements
3. Add Kustomize labels and annotations
4. Configure storage classes
5. Set resource limits

### Step 4: Create Secrets

```bash
# Create namespace if not exists
kubectl create namespace managed-tools --dry-run=client -o yaml | kubectl apply -f -

# Create Wazuh secrets from certificates
kubectl create secret generic wazuh-certs \
  --from-file=wazuh-indexer.pem \
  --from-file=wazuh-indexer-key.pem \
  --from-file=wazuh-server.pem \
  --from-file=wazuh-server-key.pem \
  --from-file=wazuh-dashboard.pem \
  --from-file=wazuh-dashboard-key.pem \
  -n managed-tools

# Create Wazuh credentials secret
kubectl create secret generic wazuh-credentials \
  --from-literal=indexer-password='<secure-password>' \
  --from-literal=server-password='<secure-password>' \
  --from-literal=dashboard-password='<secure-password>' \
  -n managed-tools
```

### Step 5: Configure Ingress

Use the existing wildcard certificate for Dashboard:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wazuh-dashboard
  namespace: managed-tools
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - wazuh.dataknife.net
      secretName: wildcard-dataknife-net-tls
  rules:
    - host: wazuh.dataknife.net
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: wazuh-dashboard
                port:
                  number: 5601
```

### Step 6: Deploy via GitOps

Configure Fleet GitRepo to monitor:
```yaml
spec:
  repo: <your-repo-url>
  branch: main
  paths:
    - wazuh/overlays/nprd-apps
```

## Monitoring Deployment

```bash
# Check Fleet status
kubectl get bundle -n fleet-default | grep wazuh
kubectl describe bundle wazuh-nprd-apps -n fleet-default

# Check Wazuh components
kubectl get pods -n managed-tools -l app=wazuh
kubectl get statefulsets -n managed-tools
kubectl get services -n managed-tools -l app=wazuh
kubectl get ingress -n managed-tools

# Check component logs
kubectl logs -n managed-tools -l app=wazuh,component=indexer
kubectl logs -n managed-tools -l app=wazuh,component=server
kubectl logs -n managed-tools -l app=wazuh,component=dashboard
```

## Reference Documentation

- [Wazuh Kubernetes Deployment Guide](https://documentation.wazuh.com/current/installation-guide/installation-alternatives/kubernetes-deployment.html)
- [Wazuh Kubernetes Configuration](https://documentation.wazuh.com/current/installation-guide/installation-alternatives/kubernetes-configuration.html)
- [Wazuh Indexer Documentation](https://documentation.wazuh.com/current/user-manual/wazuh-indexer/index.html)
- [Wazuh Server Documentation](https://documentation.wazuh.com/current/user-manual/wazuh-server/index.html)
- [Wazuh Dashboard Documentation](https://documentation.wazuh.com/current/user-manual/wazuh-dashboard/index.html)
- [Wazuh GitHub - Kubernetes](https://github.com/wazuh/wazuh-kubernetes)

## Comparison with Harbor Deployment

| Aspect | Harbor | Wazuh |
|--------|--------|-------|
| Helm Chart | Official (`helm.goharbor.io`) | No official Helm chart |
| Deployment Method | HelmChart CRD | Kubernetes manifests + Kustomize |
| Database | External PostgreSQL (CloudNativePG) | Embedded in Indexer (OpenSearch) |
| Components | Single Helm chart (multi-component) | Separate components (Indexer, Server, Dashboard) |
| Certificate Management | Wildcard cert for ingress | Internal TLS + wildcard cert for ingress |
| Storage | Multiple PVCs (registry, chartmuseum, etc.) | Indexer PVC (primary), Server PVC (secondary) |

## Next Steps

1. Review [Wazuh Kubernetes official documentation](https://documentation.wazuh.com/current/installation-guide/installation-alternatives/kubernetes-deployment.html)
2. Download Wazuh Kubernetes manifests from GitHub
3. Adapt manifests to match your cluster configuration
4. Create base Kustomize structure following Harbor pattern
5. Generate Wazuh certificates
6. Create overlay for nprd-apps with Fleet targeting
7. Test deployment in non-production environment first
