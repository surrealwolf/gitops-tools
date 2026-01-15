# Graylog + OpenSearch TLS/SSL Setup Guide

## Overview

This document describes the setup and lessons learned from configuring Graylog to communicate with OpenSearch over HTTPS with self-signed certificates in a Kubernetes environment.

## Architecture

- **Graylog**: Log aggregation and analysis platform
- **OpenSearch**: Search and analytics engine (Elasticsearch-compatible)
- **OpenSearch Kubernetes Operator**: Manages OpenSearch cluster lifecycle
- **cert-manager**: Manages TLS certificates (for webhooks)
- **Fleet GitOps**: Continuous deployment of Kubernetes resources

## Key Challenges and Solutions

### 1. OpenSearch Self-Signed Certificates

**Problem**: OpenSearch operator generates self-signed certificates with hostname `node-0.example.com`, but Graylog connects to `graylog-opensearch` service.

**Solution**: 
- Extract OpenSearch CA certificate from the OpenSearch pod
- Import CA certificate into Graylog's Java truststore
- Use custom truststore location (writable volume) since default cacerts is read-only

### 2. Java Truststore in Container Images

**Problem**: The default Java cacerts file (`/opt/java/openjdk/lib/security/cacerts`) is read-only in container images. Changes made by init containers don't persist.

**Solution**:
- Copy cacerts to a writable shared volume (`/shared/cacerts`)
- Configure Java to use custom truststore via `GRAYLOG_SERVER_JAVA_OPTS`
- Use `emptyDir` volume shared between init containers and main container

### 3. Init Container Permissions

**Problem**: `keytool` needs write access to create/modify the truststore file.

**Solution**:
- Run init container as root (`securityContext.runAsUser: 0`)
- Copy cacerts to writable location before importing certificate

### 4. Fleet Job Immutability

**Problem**: Fleet shows errors when trying to patch Jobs because `spec.template` is immutable.

**Solution**:
- This is expected behavior - Fleet cannot patch Jobs
- Jobs are still created and run successfully
- The error is non-blocking and can be safely ignored
- Document this in the Job annotations

### 5. Hostname Verification

**Problem**: Even with CA certificate in truststore, hostname verification fails because certificate is for `node-0.example.com` but connection is to `graylog-opensearch`.

**Current Status**: 
- Certificate trust is working (no more "certificate signed by unknown authority" errors)
- Hostname verification is disabled via `GRAYLOG_ELASTICSEARCH_VERIFY_SSL=false`
- Future improvement: Configure OpenSearch to generate certificates with correct hostname

## Implementation Details

### OpenSearch CA Certificate ConfigMap

**File**: `graylog/overlays/nprd-apps/opensearch-ca-configmap.yaml`

Extracts the CA certificate from OpenSearch pod and stores it in a ConfigMap:

```bash
kubectl exec graylog-opensearch-masters-0 -n managed-graylog -c opensearch \
  -- cat /usr/share/opensearch/config/root-ca.pem
```

### CA Import Init Container

**Purpose**: Import OpenSearch CA certificate into Java truststore before Graylog starts.

**Key Features**:
- Runs as root to have write permissions
- Copies default cacerts to writable shared volume
- Imports CA certificate using `keytool`
- Verifies certificate was imported successfully

**Location**: Added to StatefulSet via `graylog-secret-patch-job.yaml`

### Custom Truststore Configuration

**Java System Properties** (via `GRAYLOG_SERVER_JAVA_OPTS`):
```
-Djavax.net.ssl.trustStore=/shared/cacerts
-Djavax.net.ssl.trustStorePassword=changeit
```

**Why Custom Truststore?**
- Default cacerts is read-only in container image
- Changes don't persist between container restarts
- Shared volume allows init container to write, main container to read

### Shared Volume

**Volume**: `shared-data` (emptyDir)
- Used by `mongodb-uri-builder` init container (MongoDB URI)
- Used by `opensearch-ca-importer` init container (truststore)
- Mounted read-only in main Graylog container

## File Structure

```
graylog/overlays/nprd-apps/
├── opensearch-ca-configmap.yaml      # OpenSearch CA certificate
├── graylog-secret-patch-job.yaml     # Patches StatefulSet with secrets and CA import
└── kustomization.yaml                 # Includes ConfigMap in resources
```

## Manual Steps (if needed)

### Extract OpenSearch CA Certificate

```bash
# Get certificate from OpenSearch pod
kubectl exec graylog-opensearch-masters-0 -n managed-graylog -c opensearch \
  -- cat /usr/share/opensearch/config/root-ca.pem > /tmp/opensearch-ca.pem

# Update ConfigMap
kubectl create configmap opensearch-ca \
  --from-file=ca.crt=/tmp/opensearch-ca.pem \
  -n managed-graylog \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Verify Certificate Import

```bash
# Check if certificate is in truststore
kubectl exec graylog-0 -n managed-graylog \
  -- keytool -list -keystore /shared/cacerts -storepass changeit -alias opensearch-ca
```

### Check Graylog Connection

```bash
# View Graylog logs for OpenSearch connection status
kubectl logs graylog-0 -n managed-graylog | grep -i "opensearch\|elasticsearch"
```

## Troubleshooting

### Certificate Trust Errors

**Symptom**: `None of the TrustManagers trust this certificate chain`

**Check**:
1. Verify CA certificate is in ConfigMap: `kubectl get configmap opensearch-ca -n managed-graylog`
2. Check init container logs: `kubectl logs graylog-0 -n managed-graylog -c opensearch-ca-importer`
3. Verify truststore exists: `kubectl exec graylog-0 -n managed-graylog -- ls -la /shared/cacerts`
4. Check JAVA_OPTS: `kubectl exec graylog-0 -n managed-graylog -- env | grep JAVA_OPTS`

### Hostname Verification Errors

**Symptom**: `Hostname graylog-opensearch not verified`

**Solution**: 
- Currently disabled via `GRAYLOG_ELASTICSEARCH_VERIFY_SSL=false`
- Future: Configure OpenSearch to generate certificates with correct hostname

### Fleet Job Errors

**Symptom**: `cannot patch "graylog-secret-patch" with kind Job: spec.template: Invalid value: field is immutable`

**Solution**: 
- This is expected - Fleet cannot patch Jobs
- Job still runs successfully
- Error is non-blocking and can be ignored

### Truststore Not Found

**Symptom**: `Keystore file does not exist: /shared/cacerts`

**Check**:
1. Verify init container completed: `kubectl logs graylog-0 -n managed-graylog -c opensearch-ca-importer`
2. Check shared volume mount: `kubectl describe pod graylog-0 -n managed-graylog | grep -A 5 "shared-data"`
3. Verify init container has shared-data mount

### Missing Index Error

**Symptom**: Graylog shows "no such index []" or "missing index" errors after deployment.

**Cause**: After initial deployment, Graylog's default index set must be configured before it can create indices. In some cases, the index may need to be created manually in OpenSearch first.

**Solution Option 1: Configure Index Set in Graylog (Recommended)**

1. Log in to Graylog web UI at `https://graylog.dataknife.net`
2. Navigate to **System** → **Indices**
3. Click on **"Default index set"**
4. Configure index rotation (Daily), retention (14 days), and settings (1 shard, 0 replicas)
5. Click **Save** - Graylog will automatically create the first index
6. The "missing index" error should disappear after the index is created

**Solution Option 2: Manually Create Index in OpenSearch**

If Graylog cannot create the index automatically, create it manually in OpenSearch:

1. **Get OpenSearch admin credentials:**
   ```bash
   # Get username and password from secret
   OPENSEARCH_USER=$(kubectl get secret graylog-opensearch-admin-password -n managed-graylog -o jsonpath='{.data.username}' | base64 -d)
   OPENSEARCH_PASS=$(kubectl get secret graylog-opensearch-admin-password -n managed-graylog -o jsonpath='{.data.password}' | base64 -d)
   ```

2. **Port-forward to OpenSearch service:**
   ```bash
   kubectl port-forward -n managed-graylog svc/graylog-opensearch 9200:9200
   ```

3. **Create the index manually (in another terminal):**
   ```bash
   # Create default Graylog index (graylog_0)
   curl -X PUT "https://localhost:9200/graylog_0" \
     -u "${OPENSEARCH_USER}:${OPENSEARCH_PASS}" \
     -k \
     -H "Content-Type: application/json" \
     -d '{
       "settings": {
         "number_of_shards": 1,
         "number_of_replicas": 0,
         "index.refresh_interval": "5s"
       }
     }'
   
   # Verify index was created
   curl -X GET "https://localhost:9200/_cat/indices?v" \
     -u "${OPENSEARCH_USER}:${OPENSEARCH_PASS}" \
     -k
   ```

4. **Alternative: Create index via OpenSearch pod:**
   ```bash
   # Exec into OpenSearch pod
   kubectl exec -it -n managed-graylog graylog-opensearch-masters-0 -c opensearch -- bash
   
   # Inside the pod, create the index
   curl -X PUT "https://localhost:9200/graylog_0" \
     -u "admin:${OPENSEARCH_PASS}" \
     --cacert /usr/share/opensearch/config/root-ca.pem \
     -H "Content-Type: application/json" \
     -d '{
       "settings": {
         "number_of_shards": 1,
         "number_of_replicas": 0,
         "index.refresh_interval": "5s"
       }
     }'
   ```

5. **After creating the index, configure Graylog index set:**
   - Log in to Graylog web UI at `https://graylog.dataknife.net`
   - Navigate to **System** → **Indices**
   - Click on **"Default index set"**
   - Configure rotation and retention settings
   - Click **Save**

**Note**: The index name pattern depends on your Graylog index set configuration. Default is `graylog_0`, `graylog_1`, etc. Check Graylog index set settings to determine the correct index name pattern.

See `graylog-index-config.yaml` for detailed configuration settings.

## Best Practices

1. **Use ConfigMaps for CA Certificates**: Store CA certificates in ConfigMaps for easy updates
2. **Shared Volumes for Init Containers**: Use `emptyDir` volumes to share data between init containers and main container
3. **Run Init Containers as Root**: When modifying system files (like truststore), run as root
4. **Verify Certificate Import**: Always verify certificate was successfully imported
5. **Document Fleet Limitations**: Document that Fleet Job errors are expected and non-blocking

## Future Improvements

1. **Proper Hostname in Certificates**: Configure OpenSearch operator to generate certificates with service hostname
2. **Certificate Rotation**: Automate CA certificate updates when OpenSearch certificates rotate
3. **Truststore Management**: Consider using a dedicated truststore management tool
4. **Hostname Verification**: Re-enable hostname verification once certificates have correct hostnames

## OpenSearch Certificates

OpenSearch requires multiple certificates for secure communication:

1. **Node Certificates**: Used for HTTP and transport layer communication
2. **Admin Certificate**: Used by `securityadmin.sh` to initialize the `.opendistro_security` index

### Certificate Generation

Certificates are generated using `scripts/generate-opensearch-certs.sh`:

```bash
cd /home/lee/git/gitops-tools
bash scripts/generate-opensearch-certs.sh
```

This script creates:
- **Root CA**: `root-ca.pem` and `root-ca.key`
- **Node Certificate**: `esnode.pem` and `esnode-key.pem` (for HTTP and transport)
- **Admin Certificate**: `admin.pem` and `admin-key.pem` (PKCS8 format, for securityadmin.sh)

The admin certificate key is automatically converted to PKCS8 format, which is required by `securityadmin.sh` per the [OpenSearch documentation](https://docs.opensearch.org/latest/security/configuration/generate-certificates/).

### Kubernetes Secrets

The script creates the following secrets:

1. **`graylog-opensearch-http-certs`**: Node certificate for HTTP layer
2. **`graylog-opensearch-transport-certs`**: Node certificate for transport layer
3. **`graylog-opensearch-ca`**: Root CA certificate
4. **`graylog-opensearch-admin-certs`**: Admin certificate (for securityadmin.sh)
   - `admin.pem`: Admin certificate
   - `admin-key.pem`: Admin key in PKCS8 format
   - `ca.crt`: Root CA certificate

### OpenSearch Admin Password Secret

**IMPORTANT**: The `graylog-opensearch-admin-password` secret must contain both `username` and `password` fields. The OpenSearch operator will fail with error "username or password field missing" if only `password` is provided.

**Create the secret:**
```bash
# Generate a secure password
OPENSEARCH_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')

# Create secret with both username and password
kubectl create secret generic graylog-opensearch-admin-password \
  --from-literal=username=admin \
  --from-literal=password="$OPENSEARCH_PASSWORD" \
  -n managed-graylog
```

**Verify the secret:**
```bash
kubectl get secret graylog-opensearch-admin-password -n managed-graylog -o jsonpath='{.data}' | jq 'keys'
# Should show: ["password", "username"]
```

**If you only have password field, add username:**
```bash
kubectl patch secret graylog-opensearch-admin-password -n managed-graylog \
  --type='json' \
  -p="[{\"op\": \"add\", \"path\": \"/data/username\", \"value\": \"$(echo -n 'admin' | base64)\"}]"
```

## OpenSearch Security Initialization

The OpenSearch operator should automatically initialize the `.opendistro_security` index, but sometimes this fails. A manual initialization job (`opensearch-security-init-job.yaml`) runs `securityadmin.sh` to create the index if needed.

**Reference**: [OpenSearch Forum - Missing Index Solution](https://forum.opensearch.org/t/opensearch-deployment-with-opensearch-operator-failure-no-such-index-opendistro-security-solved/20001)

The job:
1. Waits for OpenSearch cluster to be ready
2. Uses the admin certificate (PKCS8 format) from `graylog-opensearch-admin-certs` secret
3. Runs `securityadmin.sh` to initialize the `.opendistro_security` index
4. Verifies the index was created successfully

## References

- [Graylog Documentation](https://go2docs.graylog.org/)
- [OpenSearch Kubernetes Operator](https://opensearch.org/docs/latest/install-and-configure/install-opensearch/kubernetes/)
- [Java Keytool Documentation](https://docs.oracle.com/javase/8/docs/technotes/tools/unix/keytool.html)
- [Kubernetes Init Containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)

## Related Files

- `graylog/overlays/nprd-apps/opensearch-ca-configmap.yaml` - CA certificate ConfigMap
- `graylog/overlays/nprd-apps/graylog-secret-patch-job.yaml` - StatefulSet patching job
- `graylog/overlays/nprd-apps/kustomization.yaml` - Kustomize configuration
- `graylog/base/opensearch-cluster.yaml` - OpenSearch cluster definition
