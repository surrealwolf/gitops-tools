# Vector and Promtail Configuration Review

## Current Status

### Vector (Syslog Receiver)
- **Status**: CrashLoopBackOff
- **Purpose**: Receives UniFi CEF syslog on UDP 514, parses CEF format, forwards to Loki
- **Issues Identified**:
  1. **Outdated Image**: Using `timberio/vector:0.38.0-alpine` (very old, from 2021)
  2. **Loki Endpoint**: Using `http://loki:3100` but in microservices mode should use `loki-gateway:80` or `loki-distributor:3100`
  3. **Security Context**: `runAsNonRoot: true` with `runAsUser: 1000` may prevent binding to privileged port 514
  4. **Vector 0.38.0**: May not support the Loki sink format we're using

### Promtail (Kubernetes Log Collector)
- **Status**: Running but not ready (complaining about no logs found)
- **Purpose**: Collects logs from Kubernetes pods and forwards to Loki
- **Issues Identified**:
  1. **Loki Endpoint**: Using `http://loki:3100` but in microservices mode should use `loki-gateway:80` or `loki-distributor:3100`
  2. **Loki Not Ready**: Loki microservices components may not be fully ready yet
  3. **Path Configuration**: May need adjustment for container runtime (containerd vs docker)

## Recommended Fixes

### 1. Update Vector Configuration

#### Update Vector Image
- **Current**: `timberio/vector:0.38.0-alpine`
- **Recommended**: `vectordotdev/vector:0.36.0-alpine` (stable, supports Loki sink)
- **Alternative**: `vectordotdev/vector:latest-alpine` (latest stable)

#### Fix Loki Endpoint
- **Current**: `http://loki:3100`
- **Recommended**: `http://loki-gateway:80` (uses gateway for routing)
- **Alternative**: `http://loki-distributor:3100` (direct to distributor)

#### Fix Security Context for UDP Port 514
- **Issue**: Port 514 is privileged (< 1024), requires root or CAP_NET_BIND_SERVICE
- **Options**:
  1. Use `runAsUser: 0` (root) - not recommended for security
  2. Add `capabilities.add: ["NET_BIND_SERVICE"]` - recommended
  3. Use non-privileged port (e.g., 1514) and map via service

#### Update Vector ConfigMap
- Fix Loki sink endpoint
- Ensure label template syntax is correct for Vector version

### 2. Update Promtail Configuration

#### Fix Loki Endpoint
- **Current**: `http://loki:3100/loki/api/v1/push`
- **Recommended**: `http://loki-gateway:80/loki/api/v1/push`
- **Alternative**: `http://loki-distributor:3100/loki/api/v1/push`

#### Verify Path Configuration
- Ensure `/var/log/pods` and `/var/lib/docker/containers` are correctly mounted
- Verify container runtime (containerd vs docker) path format

## Implementation Plan

### Phase 1: Fix Vector
1. Update Vector image to modern version
2. Fix Loki endpoint to use gateway service
3. Fix security context for UDP port binding
4. Test Vector deployment

### Phase 2: Fix Promtail
1. Update Loki endpoint in Promtail config
2. Verify path mounts and container runtime
3. Wait for Loki microservices to be fully ready
4. Test Promtail log collection

### Phase 3: Verification
1. Test Vector syslog reception
2. Test Promtail Kubernetes log collection
3. Verify logs appear in Loki
4. Verify logs queryable in Grafana

## Service Discovery in Microservices Mode

In microservices mode, Loki services are:
- `loki-gateway:80` - Gateway (recommended for external access)
- `loki-distributor:3100` - Distributor (direct log ingestion)
- `loki-querier:3100` - Querier (query endpoint)
- `loki-query-frontend:3100` - Query frontend (query optimization)

For log ingestion, use:
- **Vector/Promtail**: `loki-gateway:80` or `loki-distributor:3100`
- **Grafana**: `loki-gateway:80` or `loki-query-frontend:3100`

## Notes

- Vector 0.38.0 is from 2021 and may have security vulnerabilities
- Modern Vector versions use `vectordotdev/vector` image repository (not `timberio/vector`)
- Loki microservices mode requires using the correct service endpoints
- Gateway service provides routing and is recommended for external access
