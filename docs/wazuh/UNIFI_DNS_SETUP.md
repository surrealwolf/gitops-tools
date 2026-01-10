# DNS Setup for Wazuh SIEM Integration

This guide explains how to set up a DNS hostname for Wazuh syslog/SIEM integration using multiple cluster node IPs for redundancy.

## Overview

Instead of using a single node IP, you can create a DNS A record with multiple IPs (round-robin DNS) that points to the first 3 cluster nodes. This provides:

- **Redundancy**: If one node goes down, DNS will resolve to another
- **Load Distribution**: Syslog traffic can be distributed across nodes
- **Easier Management**: Use a hostname instead of IP addresses

## DNS Configuration

### Option 1: Using Your DNS Server

Create multiple A records for the same hostname pointing to the first 3 cluster nodes:

```
wazuh-syslog.dataknife.net.  IN  A  192.168.14.110
wazuh-syslog.dataknife.net.  IN  A  192.168.14.111
wazuh-syslog.dataknife.net.  IN  A  192.168.14.112
```

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

# Add hostname mapping in hosts section:
hosts {
    192.168.14.110 wazuh-syslog.dataknife.net
    192.168.14.111 wazuh-syslog.dataknife.net
    192.168.14.112 wazuh-syslog.dataknife.net
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
   - IPs: `192.168.14.110`, `192.168.14.111`, `192.168.14.112`
   - TTL: 300-600 seconds (5-10 minutes)

## Get Cluster Node IPs

```bash
# Get first 3 cluster node IPs
kubectl --context=nprd-apps get nodes -o jsonpath='{range .items[0:3]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'
```

Current first 3 nodes:
- `192.168.14.110`
- `192.168.14.111`
- `192.168.14.112`

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

1. **DNS Server Configuration:**
   ```
   wazuh-syslog.dataknife.net.  IN  A  192.168.14.110
   wazuh-syslog.dataknife.net.  IN  A  192.168.14.111
   wazuh-syslog.dataknife.net.  IN  A  192.168.14.112
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
