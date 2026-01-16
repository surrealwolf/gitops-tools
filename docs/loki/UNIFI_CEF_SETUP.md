# UniFi CEF SIEM Integration Guide for Loki

Complete guide for configuring Loki Stack to accept UniFi logs in CEF (Common Event Format) SIEM format via syslog.

## Prerequisites

- Loki Stack is deployed and accessible
- Grafana is accessible at `https://grafana.dataknife.net`
- Vector syslog receiver is deployed (NodePort 30514)
- DNS configured: `vector.dataknife.net` → cluster node IPs
- UniFi Network Application access (to configure SIEM integration)

## Architecture

```
UniFi Device → Syslog UDP (vector.dataknife.net:30514) → Vector Receiver → Parse CEF → Loki → Grafana
```

**Service Details:**
- **Vector Service**: NodePort type
- **UDP Port**: 514 (internal) → 30514 (NodePort)
- **DNS**: `vector.dataknife.net:30514` (point to cluster node IPs)
- **Metrics**: `https://vector.dataknife.net/metrics` (Prometheus metrics endpoint via ingress, port 9598)
- **Health**: API server on port 8686 (internal)

## Step 1: Verify Vector Syslog Receiver

1. **Check Vector Deployment**:
   ```bash
   kubectl get deployment vector-syslog -n managed-syslog
   kubectl get pods -n managed-syslog -l app=vector,component=syslog
   ```

2. **Check Syslog Service**:
   ```bash
   kubectl get svc vector-syslog -n managed-syslog
   # Should show NodePort 30514 for UDP port 514
   # Type: NodePort
   # Ports: 514:30514/UDP (syslog), 9598/TCP (metrics)
   ```

3. **Check Vector Logs**:
   ```bash
   kubectl logs -n managed-syslog -l app=vector,component=syslog
   ```

## Step 2: Configure UniFi Network Application

1. **Log in to UniFi Network Application**

2. **Navigate to SIEM Integration**:
   - Go to **Settings** → **System Logs**
   - Scroll to **SIEM Integration** section

3. **Configure Syslog Server**:
   - **Enable SIEM Integration**: ✅ Yes
   - **Syslog Server**: `vector.dataknife.net:30514`
     - **Recommended**: Use DNS name `vector.dataknife.net:30514`
     - **Alternative**: Use direct node IP (worker nodes recommended)
     - Example: `192.168.14.113:30514`
   - **Format**: **CEF** (Common Event Format)
   - **Protocol**: UDP (default)

4. **Click**: **Apply Changes** or **Save**

**DNS Configuration:**
Point `vector.dataknife.net` A records to cluster node IPs:
- `192.168.14.113` (worker-1)
- `192.168.14.114` (worker-2)
- `192.168.14.115` (worker-3)

This provides redundancy - if one node is unavailable, UniFi can use another.

## Step 3: Verify Log Ingestion

### Test Syslog Reception

Send a test CEF message to verify Vector is receiving syslog:

```bash
# Get a cluster node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

# Send test CEF message (using DNS)
echo 'CEF:0|Ubiquiti|UniFi|7.4.162|USG|Firewall Test|5|src=192.168.1.100 dst=192.168.1.200 act=block' | \
  nc -u vector.dataknife.net 30514

# Or using direct node IP
echo 'CEF:0|Ubiquiti|UniFi|7.4.162|USG|Firewall Test|5|src=192.168.1.100 dst=192.168.1.200 act=block' | \
  nc -u $NODE_IP 30514
```

### Check Vector Logs

```bash
# Check Vector is receiving syslog
kubectl logs -n managed-syslog -l app=vector,component=syslog --tail=50

# Should show parsed CEF messages
```

### Query Logs in Grafana

1. **Log in to Grafana**:
   - URL: `https://grafana.dataknife.net`
   - Username: `admin`
   - Password: From `loki-credentials` secret

2. **Navigate to Explore**:
   - Click **Explore** in the left menu

3. **Query UniFi CEF Logs**:
   ```logql
   # All UniFi CEF logs
   {app="unifi-cef", format="cef", source="syslog"}
   
   # Filter by device vendor
   {app="unifi-cef", device_vendor="Ubiquiti"}
   
   # Filter by severity
   {app="unifi-cef"} | json | severity >= 5
   
   # Search for specific events
   {app="unifi-cef"} |= "Firewall"
   
   # Filter by namespace (all UniFi logs)
   {namespace="unifi", app="unifi-cef"}
   ```

## Step 4: Create Grafana Dashboards

### Basic UniFi CEF Dashboard

1. **Create New Dashboard**:
   - Go to **Dashboards** → **New Dashboard**

2. **Add Panels**:

   **Panel 1: Log Volume Over Time**
   ```logql
   sum(count_over_time({app="unifi-cef"}[5m]))
   ```

   **Panel 2: Logs by Device Product**
   ```logql
   sum by (device_product) (count_over_time({app="unifi-cef"}[5m]))
   ```

   **Panel 3: Logs by Severity**
   ```logql
   sum by (severity) (count_over_time({app="unifi-cef"}[5m]))
   ```

   **Panel 4: Recent UniFi Events**
   ```logql
   {app="unifi-cef"} | json
   ```

## CEF Field Mapping

Vector parses CEF format and extracts the following fields:

- `cef_version`: CEF version (typically "0")
- `device_vendor`: Device vendor (e.g., "Ubiquiti")
- `device_product`: Device product (e.g., "UniFi")
- `device_version`: Device version (e.g., "7.4.162")
- `signature_id`: Event signature ID (e.g., "USG")
- `cef_name`: Event name (e.g., "Firewall")
- `severity`: Severity level (0-10)
- Extension fields: Parsed from CEF extension (e.g., `src`, `dst`, `act`)

## Common CEF Events from UniFi

UniFi sends various event types in CEF format:

- **Authentication Events**: User logins, logouts
- **Network Events**: Device connections, disconnections
- **Firewall Events**: Blocked connections, port scans
- **System Events**: Device status changes, updates

### Example LogQL Queries

```logql
# All authentication events
{app="unifi-cef"} | json | deviceEventClassId="authentication"

# Firewall blocks
{app="unifi-cef"} | json | cef_name="Firewall" AND severity >= 5

# User connections
{app="unifi-cef"} | json | deviceEventClassId="connection"

# High severity events
{app="unifi-cef"} | json | severity >= 7

# Events from specific source IP
{app="unifi-cef"} | json | src="192.168.1.100"
```

## Troubleshooting

### Vector Not Receiving Logs

1. **Check Vector Pod Status**:
   ```bash
   kubectl get pods -n managed-syslog -l app=vector,component=syslog
   kubectl describe pod -n managed-syslog -l app=vector,component=syslog
   ```

2. **Check Vector Logs**:
   ```bash
   kubectl logs -n managed-syslog -l app=vector,component=syslog
   ```

3. **Verify Service**:
   ```bash
   kubectl get svc vector-syslog -n managed-syslog
   kubectl describe svc vector-syslog -n managed-syslog
   ```

4. **Test UDP Port**:
   ```bash
   # From a node, test if port is listening
   nc -u -v localhost 514
   ```

### Logs Not Appearing in Loki

1. **Check Vector Configuration**:
   ```bash
   kubectl get configmap vector-config -n managed-syslog -o yaml
   ```

2. **Verify Loki Endpoint**:
   ```bash
   # Check if Loki distributor service is accessible (microservices mode)
   kubectl get svc loki-distributor -n managed-syslog
   kubectl port-forward -n managed-syslog svc/loki-distributor 3100:3100
   curl http://localhost:3100/ready
   
   # Check Vector configuration
   kubectl get configmap vector-config -n managed-syslog -o yaml
   ```

3. **Check Loki Logs**:
   ```bash
   kubectl logs -n managed-syslog -l app=loki
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

### CEF Parsing Issues

If CEF fields are not being parsed correctly:

1. **Check Vector Logs** for parsing errors:
   ```bash
   kubectl logs -n managed-syslog -l app=vector,component=syslog | grep -i error
   ```

2. **Verify CEF Format**:
   - UniFi should send CEF format when "Format: CEF" is selected
   - Test with sample message (see Step 3)
   - Vector uses `socket` source to handle raw CEF format (not RFC-compliant syslog)

3. **Check Raw Messages**:
   ```logql
   # View raw messages before parsing
   {app="unifi-cef"} | line_format "{{.message}}"
   ```

4. **Verify Socket Source Configuration**:
   - Vector uses `socket` source (not `syslog`) to accept raw UDP data
   - This handles CEF format that may not have proper syslog headers
   - Check config: `kubectl get configmap vector-config -n managed-syslog -o yaml`

## DNS and Node Configuration

**Recommended: Use DNS (vector.dataknife.net)**
- Point `vector.dataknife.net` A records to worker node IPs:
  - `192.168.14.113` (nprd-apps-worker-1)
  - `192.168.14.114` (nprd-apps-worker-2)
  - `192.168.14.115` (nprd-apps-worker-3)
- UniFi config: `vector.dataknife.net:30514`
- Provides redundancy - if one node fails, others are available

**Alternative: Direct Node IP**
- Check with: `kubectl get nodes -o wide`
- Use any worker node InternalIP with port 30514
- Example: `192.168.14.113:30514`

## Comparison with Graylog

| Feature | Graylog | Loki + Vector |
|---------|---------|---------------|
| Syslog Input | Built-in | Vector receiver |
| CEF Parsing | Built-in codec | Vector remap transform |
| Query Language | Graylog Query | LogQL |
| Storage | OpenSearch | Loki (more efficient) |
| Visualization | Graylog UI | Grafana |

## Migration from Graylog

When migrating from Graylog:

1. **Deploy Loki Stack** with Vector syslog receiver
2. **Configure UniFi** to point to new NodePort (30514)
3. **Verify Log Ingestion** in Grafana
4. **Export Important Logs** from Graylog before decommissioning
5. **Update Dashboards** to use LogQL instead of Graylog queries

## Vector Configuration

The Vector configuration follows official Vector documentation:

**Socket Source (Raw UDP):**
- Type: `socket` (used instead of `syslog` to handle raw CEF format that may not conform to RFC 3164/5424)
- Mode: `udp`
- Address: `0.0.0.0:514`
- Framing: `newline_delimited`
- Reference: [Vector Socket Source Docs](https://vector.dev/docs/reference/configuration/sources/socket/)

**Loki Sink:**
- Type: `loki`
- Endpoint: `http://loki-distributor:3100`
- Path: `/loki/api/v1/push` (explicit per docs)
- Encoding: `json`
- Labels: `namespace`, `app`, `source`, `format`
- Reference: [Vector Loki Sink Docs](https://vector.dev/docs/reference/configuration/sinks/loki/)

**Current Configuration:**
```yaml
sources:
  syslog_udp:
    type: socket
    mode: udp
    address: "0.0.0.0:514"
    framing:
      method: newline_delimited
  
  internal_metrics:
    type: internal_metrics

transforms:
  parse_cef:
    type: remap
    inputs:
      - syslog_udp
    source: |
      # Handle raw socket data - extract message field
      message_text = string!(.message)
      # Check if message contains CEF (might have syslog prefix)
      cef_message = message_text
      if match(message_text, r'CEF:') {
        # Extract CEF portion if there's a syslog prefix
        cef_match = match(message_text, r'CEF:.*')
        if cef_match != null {
          cef_message = cef_match
        }
      }
      if match(cef_message, r'^CEF:') {
        # Parse CEF format...
      }

sinks:
  loki:
    type: loki
    inputs:
      - parse_cef
    endpoint: "http://loki-distributor:3100"
    path: "/loki/api/v1/push"
    encoding:
      codec: json
    labels:
      namespace: unifi
      app: unifi-cef
      source: syslog
      format: cef
    remove_label_fields: true
  
  prometheus_exporter:
    type: prometheus_exporter
    inputs:
      - internal_metrics
    address: "0.0.0.0:9598"
    default_namespace: vector
```

**Note:** Vector uses `socket` source instead of `syslog` source to handle raw CEF format that may not conform to RFC 3164/5424 syslog standards. This allows Vector to receive and parse UniFi CEF messages that may arrive without proper syslog headers.

## Metrics and Monitoring

Vector exposes Prometheus metrics at `https://vector.dataknife.net/metrics`:

- **Metrics Endpoint**: `https://vector.dataknife.net/metrics` (Prometheus format)
- **Health Endpoint**: API server on port 8686 (internal, used for health checks)
- **Metrics Include**:
  - Event counts (received, sent, dropped)
  - Component performance metrics
  - Buffer statistics
  - Error rates

Example metrics:
- `vector_buffer_sent_events_total{component_id="loki"}` - Events sent to Loki
- `vector_component_received_event_bytes_total{component_id="parse_cef"}` - Bytes processed by CEF parser
- `vector_component_errors_total` - Error counts by component

## Documentation

- [Vector Documentation](https://vector.dev/docs/)
- [Vector Socket Source](https://vector.dev/docs/reference/configuration/sources/socket/)
- [Vector Loki Sink](https://vector.dev/docs/reference/configuration/sinks/loki/)
- [Vector Prometheus Exporter Sink](https://vector.dev/docs/reference/configuration/sinks/prometheus_exporter/)
- [Vector Remap Transform](https://vector.dev/docs/reference/vrl/)
- [Loki LogQL](https://grafana.com/docs/loki/latest/logql/)
- [UniFi SIEM Integration](https://help.ui.com/hc/en-us/articles/33349041044119-UniFi-System-Logs-SIEM-Integration)
