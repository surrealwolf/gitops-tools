# UniFi CEF SIEM Integration Guide

Complete guide for configuring Graylog to accept UniFi logs in CEF (Common Event Format) SIEM format.

## Prerequisites

- Graylog is deployed and accessible at `https://graylog.dataknife.net`
- Graylog syslog service is configured (NodePort 30514)
- UniFi Network Application access (to configure SIEM integration)

## Step 1: Configure Syslog Input in Graylog

1. **Log in to Graylog Web UI**
   - URL: `https://graylog.dataknife.net`
   - Username: `admin`
   - Password: `GN10hTf6YKtjF8cG`

2. **Navigate to Inputs**
   - Click **System** → **Inputs** in the top navigation

3. **Launch New Input**
   - Click the **Launch new input** button
   - Select **Syslog UDP** from the input type dropdown

4. **Configure Input Settings**
   - **Title**: `UniFi Syslog CEF`
   - **Node**: Select your Graylog node (typically only one available)
   - **Bind address**: `0.0.0.0:514` (listen on all interfaces, port 514)
   - **Codec**: **CEF** (Common Event Format) - **CRITICAL: This parses UniFi CEF logs**
   - **Allow overriding date**: ✅ Yes (checked)
   - **Store full message**: ✅ Yes (optional, helpful for debugging)
   - **Reject connection attempts when queue is full**: ✅ Yes (recommended)

5. **Save and Start**
   - Click **Save** to create the input
   - After saving, click **Start** to activate the input
   - Verify status shows as **Running** (green)

## Step 2: Verify Syslog Service

Check that the syslog NodePort service is accessible:

```bash
# Check service exists
kubectl get svc graylog-syslog -n managed-graylog

# Expected output:
# NAME             TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)           AGE
# graylog-syslog   NodePort   10.43.32.143    <none>        514:30514/UDP     9h
```

The service exposes port **30514** on all cluster nodes for external access.

## Step 3: Get Cluster Node IPs

Get the IP addresses of your cluster worker nodes (for UniFi configuration):

```bash
kubectl get nodes -l node-role.kubernetes.io/worker -o wide
```

Recommended: Use worker node IPs (not control-plane) to reduce load on cluster management components.

## Step 4: Configure UniFi Network Application

1. **Access UniFi Network Application**
   - Log in to your UniFi Network Application web interface

2. **Navigate to System Logs Settings**
   - Go to **Settings** → **System Logs**
   - Scroll down to **SIEM Integration** section

3. **Configure SIEM Integration**
   - **Enable SIEM Integration**: ✅ Yes
   - **Syslog Server**: `<worker-node-ip>:30514`
     - Example: `192.168.14.113:30514`
     - Use any worker node IP address (load balancing across nodes)
   - **Format**: **CEF** (Common Event Format)
   - **Protocol**: UDP (default)

4. **Save Configuration**
   - Click **Apply Changes** or **Save**

## Step 5: Verify Log Ingestion

1. **In Graylog Web UI**
   - Go to **Search** (in top navigation)

2. **Search for UniFi Logs**
   - Try these search queries:
     ```
     source:unifi
     vendor:"Ubiquiti"
     deviceVendor:"Ubiquiti"
     ```
   - Or search for specific event types:
     ```
     deviceProduct:"UniFi" AND severity:"Medium"
     ```

3. **Verify CEF Fields are Parsed**
   - Click on a log message to view details
   - Verify these CEF fields are present:
     - `deviceVendor`: Should show "Ubiquiti"
     - `deviceProduct`: Should show "UniFi" or device model
     - `deviceVersion`: Device firmware version
     - `severity`: Event severity level
     - `name`: Event name/type
     - `message`: Full event message

4. **Real-time Verification**
   - Trigger an event in UniFi (e.g., user login, device connection)
   - Check Graylog search - events should appear within seconds

## Troubleshooting

### No Logs Appearing

1. **Verify Input is Running**
   ```bash
   # In Graylog UI: System → Inputs
   # Should show "UniFi Syslog CEF" as "Running"
   ```

2. **Check Input Statistics**
   - In Graylog UI: System → Inputs → Click on "UniFi Syslog CEF"
   - Check **Received Messages** counter - should be incrementing

3. **Test Syslog Reception**
   ```bash
   # From any machine that can reach cluster nodes
   echo 'CEF:0|Ubiquiti|UniFi|7.4.162|USG|Firewall|5|src=192.168.1.100 dst=192.168.1.200 act=block' | nc -u <node-ip> 30514
   
   # Check Graylog search for the test message
   ```

4. **Check Network Connectivity**
   ```bash
   # From UniFi device or network, test UDP connectivity
   nc -u -v <node-ip> 30514
   # Should connect (press Ctrl+C to exit)
   ```

5. **Check Graylog Pod Logs**
   ```bash
   kubectl logs graylog-0 -n managed-graylog -c graylog-app | grep -i "syslog\|input\|cef"
   ```

### Logs Appear but CEF Fields Not Parsed

1. **Verify Codec is Set to CEF**
   - System → Inputs → UniFi Syslog CEF → Edit
   - Ensure **Codec** is set to **CEF** (not Raw or other)

2. **Check Message Format**
   - View raw message in Graylog
   - Verify it starts with `CEF:` prefix
   - UniFi should send CEF format when "Format: CEF" is selected

3. **Test with Sample CEF Message**
   ```bash
   echo 'CEF:0|Ubiquiti|UniFi|7.4.162|USG|Firewall|5|src=192.168.1.100 dst=192.168.1.200' | nc -u <node-ip> 30514
   ```

### Firewall Issues

Ensure firewall rules allow UDP traffic on port 30514:

```bash
# If using firewall, allow UDP port 30514
# Example for UFW:
sudo ufw allow 30514/udp

# Example for firewalld:
sudo firewall-cmd --add-port=30514/udp --permanent
sudo firewall-cmd --reload
```

## Common CEF Events from UniFi

UniFi sends various event types in CEF format:

- **Authentication Events**: User logins, logouts
- **Network Events**: Device connections, disconnections
- **Firewall Events**: Blocked connections, port scans
- **System Events**: Device status changes, updates

Search examples:
```
# All authentication events
deviceEventClassId:"authentication"

# Firewall blocks
name:"Firewall" AND severity:"Medium"

# User connections
deviceEventClassId:"connection"
```

## API Configuration (Alternative)

If you prefer to configure via API instead of web UI:

```bash
# Get Graylog API token (create in web UI: System → Users → Create Token)

# Create syslog input via API
curl -X POST https://graylog.dataknife.net/api/system/inputs \
  -H "Authorization: Basic <base64-encoded-username:token>" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "UniFi Syslog CEF",
    "type": "org.graylog2.inputs.syslog.udp.SyslogUDPInput",
    "global": false,
    "configuration": {
      "bind_address": "0.0.0.0",
      "port": 514,
      "codec": "CEF",
      "allow_override_date": true,
      "store_full_message": true
    },
    "node": "<graylog-node-id>"
  }'
```

## Additional Resources

- [UniFi SIEM Integration Guide](https://help.ui.com/hc/en-us/articles/33349041044119-UniFi-System-Logs-SIEM-Integration)
- [CEF Format Specification](https://community.microfocus.com/t5/ArcSight-Connectors/ArcSight-Common-Event-Format-CEF-Guide/ta-p/1677566)
- [Graylog Inputs Documentation](https://docs.graylog.org/docs/inputs)
