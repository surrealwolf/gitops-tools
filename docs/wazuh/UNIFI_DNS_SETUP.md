# DNS Setup for Wazuh SIEM Integration

This guide explains how to set up a DNS hostname for Wazuh syslog/SIEM integration using multiple cluster node IPs for redundancy.

## Overview

Instead of using a single node IP, you can create a DNS A record with multiple IPs (round-robin DNS) that points to the first 3 cluster nodes. This provides:

- **Redundancy**: If one node goes down, DNS will resolve to another
- **Load Distribution**: Syslog traffic can be distributed across nodes
- **Easier Management**: Use a hostname instead of IP addresses

## DNS Configuration

### Option 1: Using Your DNS Server

**Recommended: Worker Nodes Only** (Best Practice)

Create multiple A records pointing to worker nodes to reduce load on control-plane components:

```
wazuh-syslog.dataknife.net.  IN  A  192.168.14.113
wazuh-syslog.dataknife.net.  IN  A  192.168.14.114
wazuh-syslog.dataknife.net.  IN  A  192.168.14.115
```

**Alternative: All Nodes** (Maximum Redundancy)

For maximum redundancy, include all nodes (both control-plane and worker):

```
wazuh-syslog.dataknife.net.  IN  A  192.168.14.110
wazuh-syslog.dataknife.net.  IN  A  192.168.14.111
wazuh-syslog.dataknife.net.  IN  A  192.168.14.112
wazuh-syslog.dataknife.net.  IN  A  192.168.14.113
wazuh-syslog.dataknife.net.  IN  A  192.168.14.114
wazuh-syslog.dataknife.net.  IN  A  192.168.14.115
```

**Recommendation**: Use worker nodes (113-115) for better separation of concerns. Control-plane nodes handle critical cluster operations and should have reduced external traffic load.

**How it works:**
- DNS server returns all 3 IPs in response
- Client (UniFi Controller) picks one IP and uses it
- Provides automatic failover if first IP is unreachable
- DNS TTL determines how often clients refresh the IP list

### Option 2: Using CoreDNS (Kubernetes)

If you want to manage DNS within Kubernetes, you can add entries to CoreDNS:

```bash
# Edit CoreDNS ConfigMap
kubectl --context=nprd-apps edit configmap coredns -n kube-system

# Add hostname mapping in hosts section (recommended: worker nodes):
hosts {
    192.168.14.113 wazuh-syslog.dataknife.net
    192.168.14.114 wazuh-syslog.dataknife.net
    192.168.14.115 wazuh-syslog.dataknife.net
    fallthrough
}

# Or for all nodes (maximum redundancy):
hosts {
    192.168.14.110 wazuh-syslog.dataknife.net
    192.168.14.111 wazuh-syslog.dataknife.net
    192.168.14.112 wazuh-syslog.dataknife.net
    192.168.14.113 wazuh-syslog.dataknife.net
    192.168.14.114 wazuh-syslog.dataknife.net
    192.168.14.115 wazuh-syslog.dataknife.net
    fallthrough
}
```

**Note**: CoreDNS `hosts` plugin typically returns all matching IPs, providing round-robin behavior.

### Option 3: Using External DNS Provider

If you're using an external DNS provider (e.g., DNS server on your network):

1. **Access your DNS server configuration**
2. **Create multiple A records:**
   - Hostname: `wazuh-syslog.dataknife.net`
   - Type: A
   - **Recommended IPs**: `192.168.14.113`, `192.168.14.114`, `192.168.14.115` (worker nodes)
   - **Or all IPs**: `192.168.14.110-115` (all nodes for maximum redundancy)
   - TTL: 300-600 seconds (5-10 minutes)

## Get Cluster Node IPs

### Recommended: Worker Nodes (Best Practice)

For external traffic, it's best practice to use worker nodes instead of control-plane nodes to reduce load on critical control components.

```bash
# Get worker node IPs (recommended)
kubectl --context=nprd-apps get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'

# Or get all nodes and filter manually
kubectl --context=nprd-apps get nodes -o wide
```

**Recommended Worker Nodes:**
- `192.168.14.113` (nprd-apps-worker-1)
- `192.168.14.114` (nprd-apps-worker-2)
- `192.168.14.115` (nprd-apps-worker-3)

### Alternative: All Nodes (Maximum Redundancy)

For maximum redundancy, you can include all nodes:

```bash
# Get all cluster node IPs
kubectl --context=nprd-apps get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'
```

**All Nodes:**
- `192.168.14.110` (control-plane)
- `192.168.14.111` (control-plane)
- `192.168.14.112` (control-plane)
- `192.168.14.113` (worker)
- `192.168.14.114` (worker)
- `192.168.14.115` (worker)

**Note**: Using all nodes provides maximum redundancy but includes control-plane nodes which handle critical cluster operations.

## Verify DNS Resolution

```bash
# Test DNS resolution (should return all 3 IPs)
dig +short wazuh-syslog.dataknife.net

# Or using nslookup
nslookup wazuh-syslog.dataknife.net

# Test connectivity to hostname
nc -u -v wazuh-syslog.dataknife.net 30514
```

## UniFi Controller Configuration

Once DNS is configured, use the hostname in UniFi Controller:

1. **Navigate**: Settings → CyberSecure → Traffic Logging → SIEM Server
2. **Enable SIEM Server**:
   - **Server Address**: `wazuh-syslog.dataknife.net` (use hostname instead of IP)
   - **Port**: `30514` (NodePort)
   - **Protocol**: UDP
   - Select log categories

**Benefits of using hostname:**
- Easier to update if IPs change (just update DNS)
- Automatic failover if one node goes down
- Cleaner configuration

## How UDP with Multiple IPs Works

**Important Notes for UDP Syslog:**

1. **Client Behavior**: 
   - UniFi Controller will resolve DNS to get all IPs
   - Typically picks the first IP and uses it consistently
   - If first IP fails, may try other IPs

2. **NodePort Redundancy**:
   - All cluster nodes listen on NodePort 30514
   - Traffic to any node IP:30514 reaches the same Wazuh Server service
   - Kubernetes routes all NodePort traffic to the same backend

3. **No Load Balancing Needed**:
   - Since all NodePort traffic goes to the same service/pod, load balancing across IPs isn't critical
   - Multiple IPs primarily provide redundancy and failover

## Troubleshooting

### DNS Not Resolving

```bash
# Check if hostname resolves
dig wazuh-syslog.dataknife.net

# Check from UniFi Controller network
nslookup wazuh-syslog.dataknife.net
```

### Client Can't Reach Hostname

1. **Verify DNS resolution works from UniFi network:**
   ```bash
   # From UniFi Controller or device on same network
   nslookup wazuh-syslog.dataknife.net
   ```

2. **Test connectivity:**
   ```bash
   nc -u -v wazuh-syslog.dataknife.net 30514
   ```

3. **Verify firewall allows UDP 30514:**
   - Ensure UDP port 30514 is open from UniFi devices to cluster nodes
   - Test with: `nc -u -v <node-ip> 30514`

### DNS Returns Wrong IPs

1. **Check DNS TTL**: Lower TTL for faster updates (300-600 seconds)
2. **Flush DNS cache** on UniFi Controller if possible
3. **Verify all 3 IPs are correct** and nodes are healthy

## Alternative: Single IP (Simpler)

If you prefer a simpler setup without DNS round-robin:

1. **Use a single node IP directly** in UniFi Controller
2. **Example**: `192.168.14.110:30514`
3. **Note**: If that specific node goes down, you'll need to update UniFi config to use another node IP

For production with high availability, DNS round-robin is recommended.

## Network Requirements

- **DNS Resolution**: UniFi devices must be able to resolve `wazuh-syslog.dataknife.net` (or your chosen hostname)
- **Network Connectivity**: UDP port 30514 must be open from UniFi devices to all cluster nodes
- **DNS TTL**: Set appropriate TTL (300-600 seconds recommended)

## Example Complete Setup

### Recommended: Worker Nodes Only

1. **DNS Server Configuration (Best Practice):**
   ```
   wazuh-syslog.dataknife.net.  IN  A  192.168.14.113
   wazuh-syslog.dataknife.net.  IN  A  192.168.14.114
   wazuh-syslog.dataknife.net.  IN  A  192.168.14.115
   ```

### Alternative: All Nodes (Maximum Redundancy)

1. **DNS Server Configuration (All Nodes):**
   ```
   wazuh-syslog.dataknife.net.  IN  A  192.168.14.110
   wazuh-syslog.dataknife.net.  IN  A  192.168.14.111
   wazuh-syslog.dataknife.net.  IN  A  192.168.14.112
   wazuh-syslog.dataknife.net.  IN  A  192.168.14.113
   wazuh-syslog.dataknife.net.  IN  A  192.168.14.114
   wazuh-syslog.dataknife.net.  IN  A  192.168.14.115
   ```

2. **UniFi Controller:**
   - Server Address: `wazuh-syslog.dataknife.net`
   - Port: `30514`
   - Protocol: UDP

3. **Verify:**
   ```bash
   # From UniFi network
   nslookup wazuh-syslog.dataknife.net
   nc -u -v wazuh-syslog.dataknife.net 30514
   ```

## References

- [DNS Round-Robin](https://en.wikipedia.org/wiki/Round-robin_DNS)
- [CoreDNS Documentation](https://coredns.io/plugins/hosts/)
- Main integration guide: [UNIFI_INTEGRATION.md](./UNIFI_INTEGRATION.md)
