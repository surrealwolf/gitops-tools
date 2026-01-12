# UniFi CEF SIEM Syslog - Quick Start Guide

Quick reference for UniFi CEF syslog setup after initial configuration.

## Current Status

✅ **Syslog Service**: Configured (NodePort 30514)
✅ **Syslog Input**: Created in Graylog (may need to be started via web UI)
✅ **Documentation**: Available in `docs/graylog/UNIFI_CEF_SETUP.md`

## Node IPs for UniFi Configuration

**Recommended (Worker Nodes):**
- `192.168.14.113:30514`
- `192.168.14.114:30514`

**Alternative (Control Plane Nodes):**
- `192.168.14.110:30514`
- `192.168.14.111:30514`
- `192.168.14.112:30514`

## Quick Verification Steps

### 1. Verify Syslog Input is Running

```bash
# Check via API
curl -k -u admin:GN10hTf6YKtjF8cG -H "X-Requested-By: curl" \
  https://graylog.dataknife.net/api/system/inputs

# Or check via web UI:
# - Log in: https://graylog.dataknife.net (admin/GN10hTf6YKtjF8cG)
# - Go to: System → Inputs
# - Look for: "UniFi Syslog CEF"
# - Status should show: "Running" (green)
# - If not running, click "Start"
```

### 2. Test Syslog Reception

```bash
# Send a test CEF message
echo 'CEF:0|Ubiquiti|UniFi|7.4.162|USG|Firewall Test|5|src=192.168.1.100 dst=192.168.1.200 act=block' | \
  nc -u <node-ip> 30514

# Check Graylog search for the test message
# Web UI: Search → query: "test" → time range: Last 5 minutes
```

### 3. Configure UniFi Network Application

1. **Log in to UniFi Network Application**
2. **Navigate to**: Settings → System Logs
3. **Scroll to**: SIEM Integration section
4. **Configure**:
   - **Enable SIEM Integration**: ✅ Yes
   - **Syslog Server**: `<node-ip>:30514` (use one of the IPs above)
   - **Format**: **CEF** (Common Event Format)
   - **Protocol**: UDP (default)
5. **Click**: Apply Changes or Save

### 4. Verify Log Ingestion

In Graylog web UI:
- Go to: **Search**
- Search for:
  ```
  source:unifi
  vendor:"Ubiquiti"
  deviceVendor:"Ubiquiti"
  ```
- Events should appear within seconds of UniFi sending them

## Troubleshooting

### Input Not Running
- **Web UI**: System → Inputs → "UniFi Syslog CEF" → Click "Start"
- **Check logs**: `kubectl logs graylog-0 -n managed-graylog -c graylog-app | grep -i syslog`

### No Logs Appearing
1. Verify input is running (status: "Running")
2. Check input statistics: System → Inputs → "UniFi Syslog CEF" → Check "Received Messages"
3. Test connectivity: `nc -u -v <node-ip> 30514`
4. Verify UniFi configuration is saved and active

### CEF Fields Not Parsed
- Verify Codec is set to **CEF** (not Raw)
- Check message format starts with `CEF:`
- Ensure UniFi is configured with "Format: CEF"

## Full Documentation

See `docs/graylog/UNIFI_CEF_SETUP.md` for complete setup instructions and troubleshooting.
