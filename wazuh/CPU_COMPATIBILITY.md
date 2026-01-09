# Wazuh CPU Compatibility Issue

## Problem

Wazuh Docker images starting from version 4.12.0 require **x86-64-v2** CPU features, but the cluster nodes don't support this instruction set.

**Error Message:**
```
Fatal glibc error: CPU does not support x86-64-v2
```

## Affected Components

- `wazuh-indexer` - CrashLoopBackOff
- `wazuh-dashboard` - CrashLoopBackOff  
- `wazuh-server` - Running (uses different base image that may be compatible)

## Root Cause

The cluster nodes have older CPUs that don't support x86-64-v2 instruction set. The x86-64-v2 baseline requires:
- SSE3, SSSE3, SSE4.1, SSE4.2
- POPCNT
- CMPXCHG16B

These features were introduced in Intel Core 2 and AMD K10 processors (circa 2006-2007).

## Solutions

### Option 1: Use Older Wazuh Version (Attempted)

Tried Wazuh versions:
- ❌ 4.14.0 - Requires x86-64-v2
- ❌ 4.13.1 - Requires x86-64-v2
- ❌ 4.12.0 - Requires x86-64-v2
- ❌ 4.11.0 - Requires x86-64-v2

**Status**: All tested versions (4.11.0+) require x86-64-v2. Need to try 4.10.x or earlier, or use alternative solutions.

### Option 2: Build Custom Images

Build Wazuh images from source on compatible base images:
- Use older base images (e.g., Ubuntu 20.04, Debian 10)
- Compile Wazuh from source
- Create custom Docker images

### Option 3: Use Alternative Deployment

- Deploy Wazuh on VMs with compatible CPUs
- Use Wazuh Cloud service
- Deploy on different cluster nodes with x86-64-v2 support

### Option 4: Upgrade Cluster Hardware

If possible, upgrade cluster nodes to CPUs that support x86-64-v2:
- Most CPUs from 2007+ support x86-64-v2
- Check CPU compatibility before upgrading

## Verification

Check if 4.11.0 works:
```bash
kubectl get pods -n managed-tools -l app=wazuh
kubectl logs wazuh-indexer-0 -n managed-tools
kubectl logs wazuh-dashboard-<pod-name> -n managed-tools
```

If 4.11.0 still fails, try:
- 4.10.3 (last 4.10.x release)
- 4.9.2 (last 4.9.x release)
- 4.8.2 (last 4.8.x release)

## Current Status

- **Wazuh Server**: Running (1/1) - May be using compatible image
- **Wazuh Indexer**: CrashLoopBackOff - CPU compatibility issue
- **Wazuh Dashboard**: CrashLoopBackOff - CPU compatibility issue

## References

- [Wazuh Docker Hub](https://hub.docker.com/u/wazuh)
- [x86-64-v2 Wikipedia](https://en.wikipedia.org/wiki/X86-64#Microarchitecture_levels)
- [Wazuh Release Notes](https://documentation.wazuh.com/current/release-notes/index.html)
