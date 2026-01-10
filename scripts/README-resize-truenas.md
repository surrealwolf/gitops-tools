# Resize TrueNAS Volumes via API

This script resizes TrueNAS volumes directly via the API, bypassing the democratic-csi driver issue where PVCs get stuck in "Resizing" state.

## Problem

The democratic-csi FreeNAS/TrueNAS driver has a known issue where it returns `capacity_bytes: 0` during volume expansion, causing PVCs to remain in "Resizing" state indefinitely, even after the expansion completes on the backend.

## Solution

This script:
1. Resizes the dataset directly via TrueNAS API
2. Removes the stuck "Resizing" condition from the PVC
3. Updates the PVC status to reflect the new size
4. Restarts associated pods to recognize the new volume size

## Prerequisites

- `kubectl` configured with access to the cluster
- `jq` installed (for JSON parsing)
- `bc` installed (for size calculations)
- `curl` installed
- TrueNAS API access (API key or username/password)

## Usage

### Basic Usage

```bash
# Set API key
export TRUENAS_API_KEY="your-api-key-here"
export TRUENAS_SKIP_SSL="true"  # If using self-signed certificate

# Resize a PVC
./scripts/resize-truenas-volumes.sh harbor-registry 400Gi managed-tools
./scripts/resize-truenas-volumes.sh data-harbor-trivy-0 40Gi managed-tools
./scripts/resize-truenas-volumes.sh data-harbor-redis-0 5Gi managed-tools
```

### Using Username/Password

```bash
export TRUENAS_USER="admin"
export TRUENAS_PASS="your-password"
export TRUENAS_SKIP_SSL="true"

./scripts/resize-truenas-volumes.sh harbor-registry 400Gi managed-tools
```

### Getting API Key from democratic-csi Config

The API key is stored in the democratic-csi secret:

```bash
# Extract API key from secret
kubectl get secret democratic-csi-driver-config -n democratic-csi \
  -o jsonpath='{.data.driver-config-file\.yaml}' | base64 -d | grep -A1 apiKey

# Or decode and view full config
kubectl get secret democratic-csi-driver-config -n democratic-csi \
  -o jsonpath='{.data.driver-config-file\.yaml}' | base64 -d
```

Then extract the `apiKey` value from the output.

### Custom TrueNAS Endpoint

If your TrueNAS server is at a different address:

```bash
export TRUENAS_API_URL="https://your-truenas-host:443/api/v2.0"
export TRUENAS_API_KEY="your-api-key"
export TRUENAS_SKIP_SSL="true"  # If self-signed

./scripts/resize-truenas-volumes.sh <pvc-name> <size> <namespace>
```

## Examples

### Resize harbor-registry from 5Gi to 400Gi

```bash
export TRUENAS_API_KEY="2-PHjhswY0SJKTbWcbK39Q9Sd0bixMTE0HsIyVkW2e1aR3CkxnrY0GSHjT9FeOGE"
export TRUENAS_SKIP_SSL="true"

./scripts/resize-truenas-volumes.sh harbor-registry 400Gi managed-tools
```

### Resize StatefulSet PVCs

```bash
# Harbor Trivy
./scripts/resize-truenas-volumes.sh data-harbor-trivy-0 40Gi managed-tools

# Harbor Redis  
./scripts/resize-truenas-volumes.sh data-harbor-redis-0 5Gi managed-tools
```

## Size Formats

Supported size formats:
- `400Gi` - Gibibytes (recommended)
- `40Gi` - Gibibytes
- `5Gi` - Gibibytes
- `500M` or `500Mi` - Megabytes/Mebibytes
- Bytes (numeric value)

## Verification

After running the script, verify the resize:

```bash
# Check PVC status
kubectl get pvc harbor-registry -n managed-tools

# Check actual size in pod
kubectl exec -n managed-tools deployment/harbor-registry -c registry -- df -h /storage

# Check no Resizing conditions
kubectl get pvc -n managed-tools -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.conditions[*].type}{"\n"}{end}'
```

## Troubleshooting

### Error: "Failed to authenticate with TrueNAS API"

- Check your API key is correct
- Verify the TrueNAS API URL is accessible
- If using HTTPS with self-signed cert, set `TRUENAS_SKIP_SSL="true"`

### Error: "Could not determine dataset path"

- The script tries multiple methods to find the dataset
- Check the PV volumeHandle matches the dataset name on TrueNAS
- You may need to manually specify the dataset path in the script

### Error: "Failed to update dataset quota"

- Verify TrueNAS has sufficient space
- Check the dataset exists and is accessible
- Verify the API key has permissions to modify datasets
- Check TrueNAS logs for quota-related errors

### PVC still shows old size after script

- The script updates the PVC status, but Kubernetes may revert it
- Try manually patching the PVC status:
  ```bash
  kubectl patch pvc <pvc-name> -n <namespace> --type='merge' \
    -p '{"status":{"capacity":{"storage":"<new-size>"}}}'
  ```
- Restart the pod to pick up the new volume size

## Notes

- The script requires direct API access to TrueNAS
- Resizing via API bypasses the democratic-csi driver issue
- Always verify backups before resizing production volumes
- For StatefulSets, ensure you also update the `volumeClaimTemplate` in GitOps manifests

## References

- [TrueNAS API Documentation](https://www.truenas.com/docs/api/)
- [TrueNAS Dataset Quota Management](https://www.truenas.com/docs/core/storage/pools/managing/)
- [Kubernetes Volume Expansion](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#expanding-persistent-volumes-claims)
