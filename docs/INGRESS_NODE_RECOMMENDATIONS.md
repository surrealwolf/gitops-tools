# Ingress and NodePort Node Recommendations

This document explains best practices for routing external traffic to Kubernetes services (Ingress and NodePort) with regard to control-plane vs worker nodes.

## Overview

In Kubernetes clusters, **worker nodes should be preferred for external traffic** to reduce load on control-plane components (API server, etcd, scheduler, controller manager). This applies to both Ingress and NodePort services.

## Current Cluster Setup

**Control-Plane Nodes:**
- `192.168.14.110` (nprd-apps-1)
- `192.168.14.111` (nprd-apps-2)
- `192.168.14.112` (nprd-apps-3)

**Worker Nodes:**
- `192.168.14.113` (nprd-apps-worker-1)
- `192.168.14.114` (nprd-apps-worker-2)
- `192.168.14.115` (nprd-apps-worker-3)

## Ingress Controller

### Current Setup

The ingress controller (nginx) is deployed as a **DaemonSet** and runs on **all 6 nodes** (both control-plane and worker nodes):

```
rke2-ingress-nginx-controller pods:
  - nprd-apps-1 (control-plane)      ✅ Running
  - nprd-apps-2 (control-plane)      ✅ Running
  - nprd-apps-3 (control-plane)      ✅ Running
  - nprd-apps-worker-1 (worker)      ✅ Running
  - nprd-apps-worker-2 (worker)      ✅ Running
  - nprd-apps-worker-3 (worker)      ✅ Running
```

### Recommended DNS Configuration

**For Ingress Hostnames** (e.g., `graylog.dataknife.net`, `harbor.dataknife.net`):

**Use Worker Nodes Only** (Recommended):
```
graylog.dataknife.net.    IN  A  192.168.14.113
graylog.dataknife.net.    IN  A  192.168.14.114
graylog.dataknife.net.    IN  A  192.168.14.115

harbor.dataknife.net.     IN  A  192.168.14.113
harbor.dataknife.net.     IN  A  192.168.14.114
harbor.dataknife.net.     IN  A  192.168.14.115
```

**Why Worker Nodes for Ingress?**

1. **Reduces Load on Control-Plane**: 
   - Control-plane nodes run critical cluster components (API server, etcd, scheduler)
   - External HTTP/HTTPS traffic can be resource-intensive
   - Better to isolate this load to worker nodes

2. **Separation of Concerns**:
   - Control-plane: Cluster management and orchestration
   - Worker nodes: Application workloads and external traffic

3. **Performance**:
   - Worker nodes are typically sized for application workloads
   - Control-plane nodes may have different resource allocations

4. **Security**:
   - External traffic should not directly hit control-plane nodes
   - Worker nodes can be hardened differently for external access

### Alternative: All Nodes (Maximum Redundancy)

If you want maximum redundancy and don't mind adding load to control-plane:

```
graylog.dataknife.net.    IN  A  192.168.14.110
graylog.dataknife.net.    IN  A  192.168.14.111
graylog.dataknife.net.    IN  A  192.168.14.112
graylog.dataknife.net.    IN  A  192.168.14.113
graylog.dataknife.net.    IN  A  192.168.14.114
graylog.dataknife.net.    IN  A  192.168.14.115
```

**Note**: This provides maximum redundancy but adds external traffic load to control-plane components.

## NodePort Services

### Current Setup: Graylog Syslog (SIEM)

The Graylog syslog service uses NodePort on port 30514 (UDP) for syslog/SIEM integration (UniFi CEF).

**Recommended DNS Configuration:**

```
graylog-syslog.dataknife.net.  IN  A  192.168.14.113
graylog-syslog.dataknife.net.  IN  A  192.168.14.114
graylog-syslog.dataknife.net.  IN  A  192.168.14.115
```

**Same Principle**: Use worker nodes to reduce load on control-plane components.

## How It Works

### Ingress Flow

1. **DNS Resolution**: Client resolves `graylog.dataknife.net` → Gets worker node IPs (113-115)
2. **Traffic Routing**: Client connects to worker node IP (e.g., 192.168.14.113:443)
3. **Ingress Controller**: Ingress controller pod on that worker node handles the request
4. **Service Routing**: Ingress controller routes to backend service (`graylog:9000`)

**Important**: Even though ingress controller pods run on all nodes, DNS should point to worker nodes only to avoid control-plane load.

### NodePort Flow

1. **DNS Resolution**: Client resolves `graylog-syslog.dataknife.net` → Gets worker node IPs (113-115)
2. **Traffic Routing**: Client connects to worker node IP:NodePort (e.g., 192.168.14.113:30514)
3. **Kubernetes Routing**: Kubernetes routes to service backend (`graylog-syslog:514`)
4. **Service Backend**: Request reaches the target pod (Graylog server with syslog input configured)

**Important**: NodePort works on all nodes, but DNS should target worker nodes to reduce control-plane load.

## Advanced: Restrict Ingress Controller to Worker Nodes

If you want to ensure ingress controller pods **only** run on worker nodes, you can configure the DaemonSet with nodeSelector:

```yaml
# This would require modifying the RKE2 ingress controller DaemonSet
# Typically done via Helm values or DaemonSet patch

spec:
  template:
    spec:
      nodeSelector:
        node-role.kubernetes.io/worker: ""
      tolerations:
        # Add tolerations if worker nodes have taints
```

**Note**: This is more advanced and may require coordination with Rancher/RKE2 configuration. The current setup with DNS pointing to worker nodes is sufficient for most use cases.

## Summary

**Recommendation: Use Worker Nodes for All External Traffic**

| Service Type | DNS Target | Recommendation |
|--------------|------------|----------------|
| Ingress (HTTPS) | Worker nodes (113-115) | ✅ Recommended |
| NodePort (UDP/TCP) | Worker nodes (113-115) | ✅ Recommended |
| All Nodes | Control-plane + Worker | ⚠️ Maximum redundancy, but adds control-plane load |

**Best Practice**: 
- **DNS**: Point all external traffic hostnames to worker nodes (113-115)
- **Ingress**: Even if ingress controller runs on all nodes, DNS should target worker nodes
- **NodePort**: Same principle - DNS should target worker nodes

**Benefits**:
- Reduces load on critical control-plane components
- Better separation of concerns
- Improved cluster stability
- Standard Kubernetes best practice

## References

- [Kubernetes Node Best Practices](https://kubernetes.io/docs/concepts/architecture/nodes/)
- [Ingress Controller Deployment Best Practices](https://kubernetes.github.io/ingress-nginx/deploy/)
- [RKE2 Ingress Configuration](https://docs.rancher.com/docs/rke2/networking/ingress/)
