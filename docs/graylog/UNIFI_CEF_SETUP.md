# UniFi CEF SIEM Integration Guide

Complete guide for configuring Graylog to accept UniFi logs in CEF (Common Event Format) SIEM format.

## Prerequisites

- Graylog is deployed and accessible at `https://graylog.dataknife.net`
- Graylog syslog service is configured (NodePort 30514)
- UniFi Network Application access (to configure SIEM integration)

## Step 1: Configure Syslog Input in Graylog

Graylog 7.0 uses a three-step process: Create Input, Create Stream, Create Index Set. The Setup Input wizard guides you through this process.

### 1.1: Create Input

1. **Log in to Graylog Web UI**
   - URL: `https://graylog.dataknife.net`
   - Username: `admin`
   - Password: `GN10hTf6YKtjF8cG`

2. **Navigate to Inputs**
   - Click **System** → **Inputs** in the top navigation

3. **Launch New Input**
   - Click the **Launch new input** button
   - Select **Syslog UDP** from the input type dropdown (**Important**: Use "Syslog UDP", not "CEF UDP")
   - Click **Launch new input**

4. **Configure Basic Input Settings**
   - **Title**: `UniFi Syslog CEF`
   - **Node**: Select your Graylog node (typically only one available)
   - **Bind address**: `0.0.0.0:514` (listen on all interfaces, port 514)
   - Configure other settings as needed
   - **Note**: Use Syslog UDP because UniFi sends CEF format wrapped in syslog headers. CEF UDP input expects pure CEF format and will fail to parse syslog-wrapped messages. Index Set is configured in the Setup Input wizard (next step)

5. **Launch Input**
   - Click **Launch input** to create the input
   - The input will be created but not yet fully configured

### 1.2: Setup Input (Create Stream and Index Set)

After creating the input, you must complete the Setup Input wizard to configure routing and index set assignment.

1. **Start Setup Input Wizard**
   - On the Inputs page, locate your "UniFi Syslog CEF" input
   - Click the **Setup Input** button next to the input

2. **Select Illuminate Packs (Optional)**
   - If Illuminate packs are available, you can select them
   - For basic setup, click **Skip Illuminate** to proceed

3. **Configure Data Routing - Create Stream**
   - Select **Route to a new stream**
   - **Stream Title**: `UniFi CEF Logs`
   - **Stream Description**: `UniFi Network Application security events and logs in CEF format from SIEM integration. Includes authentication events, connection events, firewall events, and security activities.`
   - **Index Set**: Create a new index set (see Step 1.3 below) or select existing "Default index set"
   - Click **Next**

4. **Input Diagnosis**
   - Review the input diagnosis page
   - Verify the input is running and configured correctly
   - Complete the setup

### 1.3: Create Index Set (if creating new)

If you chose to create a new index set in Step 1.2, configure it as follows:

- **Title**: `UniFi CEF Logs`
- **Description**: `Index set for UniFi Network Application CEF format security events and logs from SIEM integration.`
- **Index prefix**: `unifi-cef` (must be unique)
- **Analyzer**: `standard` (default)
- **Index Shards**: `1` (default)
- **Index Replica**: `0` (default)
- **Rotation**: `14 days`
- **Max. days in storage**: `18`
- **Min. days in storage**: `14`
- **Field Type Profile**: Leave default or select "info"
- All other advanced options: Keep defaults

## Step 2: Verify Input Configuration

After completing the Setup Input wizard, verify the input is running:

1. **Check Input Status**
   - Go to **System** → **Inputs**
   - Verify "UniFi Syslog CEF" shows as **Running** (green status)
   - The input should have an index set assigned (no "no such index []" errors)

2. **Verify Input Diagnostics** (Optional)
   - Click **More actions** → **Input Diagnosis** next to the input
   - Verify no errors are displayed
   - Check that the input is receiving data (if logs are being sent)

## Step 3: Verify Syslog Service

Check that the syslog NodePort service is accessible:

```bash
# Check service exists
kubectl get svc graylog-syslog -n managed-graylog

# Expected output:
# NAME             TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)           AGE
# graylog-syslog   NodePort   10.43.32.143    <none>        514:30514/UDP     9h
```

The service exposes port **30514** on all cluster nodes for external access.

## Step 4: Get Cluster Node IPs

Get the IP addresses of your cluster worker nodes (for UniFi configuration):

```bash
kubectl get nodes -l node-role.kubernetes.io/worker -o wide
```

Recommended: Use worker node IPs (not control-plane) to reduce load on cluster management components.

## Step 5: Configure UniFi Network Application

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

## Step 6: Verify Log Ingestion

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

## Optional: Parse CEF Fields with Pipeline Rules

Since UniFi sends CEF format wrapped in syslog headers, the messages arrive as plain text. To extract structured CEF fields (deviceVendor, deviceProduct, severity, etc.), you can create a pipeline rule.

### Step 1: Create Pipeline Rule

1. Go to **System** → **Pipelines**
2. Click **"Manage rules"**
3. Click **"Create rule"**
4. Fill in:
   - **Title**: `Parse UniFi CEF Fields`
   - **Description**: `Extract CEF fields from UniFi syslog-wrapped messages`
5. In **"Rule source"**, paste this code:

```plaintext
rule "Parse UniFi CEF Fields"
when
    has_field("message")
then
    let msg = to_string($message.message);
    
    // Extract CEF line from syslog-wrapped message
    if (regex("CEF:", msg)) {
        // Find the CEF portion (everything after CEF:)
        let cef_match = regex("(CEF:\\d+\\|.*)$", msg);
        
        if (cef_match != null) {
            let cef_line = cef_match[1];
            let parts = split(cef_line, "|");
            
            // Parse CEF header: CEF:Version|Device Vendor|Device Product|Device Version|Signature ID|Name|Severity|Extension
            if (size(parts) >= 7) {
                // Set standard CEF fields
                set_field("cef_version", parts[0]);
                set_field("deviceVendor", parts[1]);
                set_field("deviceProduct", parts[2]);
                set_field("deviceVersion", parts[3]);
                set_field("signatureId", parts[4]);
                set_field("name", parts[5]);
                set_field("severity", to_long(parts[6]));
                
                // Parse extension fields if present
                if (size(parts) >= 8) {
                    let ext = parts[7];
                    set_field("cef_extensions", ext);
                    
                    // Extract common UniFi extension fields
                    // Source IP
                    let src_match = regex("src=([^\\s]+)", ext);
                    if (src_match != null) {
                        set_field("src", src_match[1]);
                    }
                    
                    // Destination IP
                    let dst_match = regex("dst=([^\\s]+)", ext);
                    if (dst_match != null) {
                        set_field("dst", dst_match[1]);
                    }
                    
                    // Action
                    let act_match = regex("act=([^\\s]+)", ext);
                    if (act_match != null) {
                        set_field("act", act_match[1]);
                    }
                    
                    // Device Event Class ID
                    let class_match = regex("deviceEventClassId=([^\\s]+)", ext);
                    if (class_match != null) {
                        set_field("deviceEventClassId", class_match[1]);
                    }
                    
                    // Protocol
                    let proto_match = regex("proto=([^\\s]+)", ext);
                    if (proto_match != null) {
                        set_field("proto", proto_match[1]);
                    }
                    
                    // Source Port
                    let spt_match = regex("spt=([^\\s]+)", ext);
                    if (spt_match != null) {
                        set_field("spt", spt_match[1]);
                    }
                    
                    // Destination Port
                    let dpt_match = regex("dpt=([^\\s]+)", ext);
                    if (dpt_match != null) {
                        set_field("dpt", dpt_match[1]);
                    }
                }
            }
        }
    }
end
```

6. Click **"Save"**

### Step 2: Create Pipeline

1. Go to **System** → **Pipelines**
2. Click **"Create pipeline"**
3. Fill in:
   - **Title**: `UniFi CEF Parser`
   - **Description**: `Parse CEF fields from UniFi messages`
4. Click **"Save pipeline"**
5. Click on **"UniFi CEF Parser"** pipeline
6. In **Stage 0**, click **"Add rule"**
7. Select **"Parse UniFi CEF Fields"** rule
8. Save

### Step 3: Connect Pipeline to Stream

1. Go to **Streams**
2. Click on **"UniFi CEF Logs"** stream
3. Click **"Manage connections"** (or **"Pipelines"** tab)
4. Click **"New connection"**
5. Select **"UniFi CEF Parser"** pipeline
6. Save

After completing these steps, new messages will have CEF fields extracted and searchable. Existing messages in the stream will not be reprocessed, but new messages will be parsed correctly.

## Additional Resources

- [UniFi SIEM Integration Guide](https://help.ui.com/hc/en-us/articles/33349041044119-UniFi-System-Logs-SIEM-Integration)
- [CEF Format Specification](https://community.microfocus.com/t5/ArcSight-Connectors/ArcSight-Common-Event-Format-CEF-Guide/ta-p/1677566)
- [Graylog Inputs Documentation](https://docs.graylog.org/docs/inputs)
