# UniFi Integration with Wazuh

This guide explains how to integrate Ubiquiti UniFi devices with Wazuh for centralized logging and security monitoring.

## Overview

UniFi devices (switches, access points, gateways, etc.) can send syslog messages directly to Wazuh for centralized logging and analysis. This integration enables:

- Centralized network device logging
- Security event monitoring from UniFi devices
- Alert generation for network events
- Historical log analysis

## Prerequisites

- Wazuh Server deployed and running
- Wazuh Server exposed externally via NodePort on port 30514 UDP (maps to internal 514 UDP)
- UniFi Network Application (Controller) access
- Network connectivity between UniFi devices and Wazuh Server
- (Optional) DNS configured for hostname access - see [UNIFI_DNS_SETUP.md](./UNIFI_DNS_SETUP.md)

## Configuration Steps

### 1. Configure Wazuh Server (Already Done)

The Wazuh Server is configured with:
- **Syslog listener**: Port 514 UDP (internal, standard SIEM port)
- **Service type**: NodePort (works immediately without LoadBalancer)
- **External access**: Any cluster node IP on NodePort 30514 UDP

**Service Details:**
- **Internal**: `wazuh-server:514` (UDP)
- **External**: `<cluster-node-ip>:30514` (UDP)
- **Note**: NodePort 30514 maps to internal port 514 UDP
- **Why NodePort?**: Standard port 514 requires privileged access; NodePort works immediately

### 2. Get Wazuh Server Access Address

```bash
# Get cluster node IPs (use any of these)
kubectl --context=nprd-apps get nodes -o wide

# Get node IPs directly
kubectl --context=nprd-apps get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}'

# Verify service is configured correctly
kubectl --context=nprd-apps get svc -n managed-tools wazuh-server
```

**Example Node IPs:**
- **Recommended (Worker Nodes)**: `192.168.14.113`, `192.168.14.114`, `192.168.14.115`
- **All Nodes**: `192.168.14.110-115` (includes control-plane nodes)
- **External Syslog**: `<node-ip>:30514` (UDP) OR use hostname `wazuh-syslog.dataknife.net:30514`
- NodePort `30514` maps to internal port `514` UDP

**Important**: 
- Use **any cluster node IP** with port **30514** (UDP). All nodes can receive syslog traffic.
- **Recommended**: Use worker nodes (113-115) to reduce load on control-plane components
- **Best Practice**: Use hostname with multiple A records pointing to worker nodes for redundancy - see [UNIFI_DNS_SETUP.md](./UNIFI_DNS_SETUP.md)

### 3. Configure UniFi Network Application

#### For UniFi Network Application 8.5+ (Newer versions):

1. **Access UniFi Controller:**
   - Log in to your UniFi Network Application

2. **Navigate to Settings:**
   - Click **Settings** (gear icon) → **CyberSecure** → **Traffic Logging**

3. **Enable SIEM Server:**
   - In the **Activity Logging (Syslog)** section:
     - Enable **SIEM Server**
     - **Server Address**: 
       - **Option 1 (Recommended)**: Use hostname `wazuh-syslog.dataknife.net` (with DNS round-robin)
       - **Option 2**: Use any cluster node IP (e.g., `192.168.14.110`)
       - Get IPs with: `kubectl --context=nprd-apps get nodes -o wide`
       - For DNS setup, see [UNIFI_DNS_SETUP.md](./UNIFI_DNS_SETUP.md)
     - **Port**: `30514` (NodePort, NOT 514 - maps to internal port 514)
     - **Protocol**: UDP
     - **Categories**: Select log categories to forward:
       - Authentication events
       - Security events
       - Wireless events
       - Network events
       - (Select all relevant categories)

4. **Apply Changes:**
   - Click **Apply Changes**

#### For UniFi Network Application 8.4 and Older:

1. **Access UniFi Controller:**
   - Log in to your UniFi Network Application

2. **Navigate to Settings:**
   - Click **Settings** → **System** → **Integrations**

3. **Enable SIEM Server:**
   - Under **SIEM Server** section:
     - Enable **SIEM Server**
     - **Server Address**: 
       - **Option 1 (Recommended)**: Use hostname `wazuh-syslog.dataknife.net` (with DNS round-robin)
       - **Option 2**: Use any cluster node IP (e.g., `192.168.14.110`)
       - Get IPs with: `kubectl --context=nprd-apps get nodes -o wide`
       - For DNS setup, see [UNIFI_DNS_SETUP.md](./UNIFI_DNS_SETUP.md)
     - **Port**: `30514` (NodePort, NOT 514 - maps to internal port 514)
     - **Protocol**: UDP
     - Select log categories

4. **Apply Changes:**
   - Click **Apply Changes**

### 4. Verify Log Reception

#### Check Wazuh Server Logs:

```bash
# Check if syslog is being received
kubectl --context=nprd-apps logs -n managed-tools wazuh-server-0 --tail=100 | grep -i "syslog\|unifi\|514"

# Check for incoming connections on port 514
kubectl --context=nprd-apps exec -n managed-tools wazuh-server-0 -- netstat -ulnp | grep 514
```

#### Check Wazuh Dashboard:

1. **Access Dashboard:**
   - URL: https://wazuh.dataknife.net
   - Login with `admin/admin`

2. **View Events:**
   - Navigate to **Security Events** or **Events**
   - Filter by source IP (your UniFi device IPs)
   - Filter by log source if custom decoders are configured

3. **Search for UniFi Logs:**
   - Use search: `source:unifi` or `hostname:unifi*`
   - Or search by device IP

## Optional: Custom UniFi Decoders and Rules

To properly parse and alert on UniFi-specific log formats, you can enable custom decoders and rules.

### Enable UniFi Decoders (Optional):

1. **Uncomment in kustomization.yaml:**
   ```yaml
   # Uncomment this line:
   - wazuh-unifi-decoder-configmap.yaml
   ```

2. **Mount decoders in StatefulSet:**
   Add to `wazuh-server-statefulset.yaml`:
   ```yaml
   volumeMounts:
     - name: unifi-decoders
       mountPath: /var/ossec/etc/decoders/custom/unifi_decoders.xml
       subPath: unifi_decoders.xml
       readOnly: true
     - name: unifi-rules
       mountPath: /var/ossec/etc/rules/custom/unifi_rules.xml
       subPath: unifi_rules.xml
       readOnly: true
   
   volumes:
     - name: unifi-decoders
       configMap:
         name: wazuh-unifi-decoder-config
     - name: unifi-rules
       configMap:
         name: wazuh-unifi-decoder-config
   ```

3. **Restart Wazuh Server:**
   ```bash
   kubectl --context=nprd-apps delete pod -n managed-tools wazuh-server-0
   ```

### Test Custom Decoders:

```bash
# Test decoder with sample log
kubectl --context=nprd-apps exec -n managed-tools wazuh-server-0 -- /var/ossec/bin/wazuh-logtest
```

## Troubleshooting

### UniFi Devices Not Sending Logs

1. **Check Network Connectivity:**
   ```bash
   # Get cluster node IP
   NODE_IP=$(kubectl --context=nprd-apps get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
   
   # From UniFi device network, test connectivity to NodePort
   # Replace <node-ip> with actual cluster node IP
   nc -u -v <node-ip> 30514
   
   # Example: nc -u -v 192.168.14.110 30514
   ```

2. **Check Firewall Rules:**
   - Ensure UDP port **30514** is allowed from UniFi devices to cluster node IPs
   - Check if any network policies block UDP traffic
   - Verify firewall allows traffic to any cluster node

3. **Verify Service is Exposed:**
   ```bash
   kubectl --context=nprd-apps get svc -n managed-tools wazuh-server
   # Should show NodePort with port 30514/UDP
   ```

4. **Check UniFi Configuration:**
   - Verify server address and port in UniFi Controller
   - Ensure correct protocol (UDP)
   - Check that log categories are selected

### Wazuh Not Receiving Logs

1. **Check Syslog Listener:**
   ```bash
   kubectl --context=nprd-apps exec -n managed-tools wazuh-server-0 -- netstat -ulnp | grep 514
   ```

2. **Verify ossec.conf Configuration:**
   ```bash
   kubectl --context=nprd-apps exec -n managed-tools wazuh-server-0 -- grep -A 5 "connection>syslog" /var/ossec/etc/ossec.conf
   ```

3. **Check Wazuh Logs for Errors:**
   ```bash
   kubectl --context=nprd-apps logs -n managed-tools wazuh-server-0 --tail=200 | grep -i error
   ```

4. **Test Syslog Reception:**
   ```bash
   # Get cluster node IP
   NODE_IP=$(kubectl --context=nprd-apps get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
   
   # Send test syslog message to NodePort 30514
   echo "test unifi message" | nc -u $NODE_IP 30514
   
   # Check Wazuh logs
   kubectl --context=nprd-apps logs -n managed-tools wazuh-server-0 --tail=50 | grep -i "test"
   ```

## Network Configuration

### Ports Used:

| Port | Protocol | Purpose | Access |
|------|----------|---------|--------|
| 514 | UDP | Syslog/SIEM (internal) | Cluster internal only |
| 30514 | UDP | Syslog/SIEM (NodePort) | Any cluster node IP:30514 |
| 1514 | TCP | Agent connections | Cluster internal only |
| 1515 | UDP | Agent auth | Cluster internal only |
| 55000 | TCP | API | Cluster internal only |

**Note**: NodePort 30514 maps to internal port 514 UDP. Use `<node-ip>:30514` for external access.

### Firewall Rules:

Ensure the following firewall rules allow traffic:

**From UniFi Devices → Cluster Nodes:**
- UDP port **30514** (NodePort, maps to internal port 514)
- Use any cluster node IP (e.g., `192.168.14.110:30514`)

**Optional (if exposing agent ports):**
- TCP port 1514 (agents)
- UDP port 1515 (agent auth)

## Log Categories

UniFi devices can send various log categories. Recommended categories to enable:

- **Authentication**: User login/logout events
- **Security**: Security alerts and events
- **Wireless**: WiFi connection events
- **Network**: Network configuration changes
- **System**: System-level events

## Storage Considerations

With UniFi syslog enabled:
- **Expected volume**: ~100-500KB per device per day (depending on log level)
- **For 10 UniFi devices**: ~1-5MB per day
- **For 2 weeks retention**: ~14-70MB (minimal impact)

Your current 50Gi Indexer storage is more than sufficient for UniFi logs.

## Next Steps

1. ✅ Configure Wazuh Server (already done)
2. ⏳ Configure UniFi Controller to send syslog
3. ⏳ Verify logs are being received
4. ⏳ (Optional) Enable custom decoders for better parsing
5. ⏳ Create custom dashboards/views for UniFi events

## References

- [Wazuh Syslog Documentation](https://documentation.wazuh.com/current/user-manual/capabilities/log-data-collection/syslog.html)
- [UniFi Syslog Configuration](https://help.ui.com/hc/en-us/articles/360012282373-UniFi-Ubiquiti-Syslog)
- [Wazuh Custom Decoders Guide](https://documentation.wazuh.com/current/user-manual/capabilities/log-data-collection/creating-custom-decoders.html)
