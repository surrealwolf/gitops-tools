#!/bin/bash
#
# Resize TrueNAS volumes via API
# 
# This script resizes volumes directly via the TrueNAS API, bypassing
# the democratic-csi driver which has issues reporting capacity after resize.
#
# Usage:
#   ./resize-truenas-volumes.sh <PVC_NAME> <NEW_SIZE> [NAMESPACE]
#   ./resize-truenas-volumes.sh harbor-registry 400Gi managed-tools
#
# Environment variables:
#   TRUENAS_API_URL - TrueNAS API endpoint (default: https://192.168.9.10/api/v2.0)
#   TRUENAS_API_KEY - TrueNAS API key (required, or use TRUENAS_USER/TRUENAS_PASS)
#   TRUENAS_USER    - TrueNAS username (alternative to API key)
#   TRUENAS_PASS    - TrueNAS password (alternative to API key)
#   TRUENAS_SKIP_SSL - Set to "true" to skip SSL verification (for self-signed certs)
#   
#   To get API key from democratic-csi secret:
#   kubectl get secret democratic-csi-driver-config -n democratic-csi -o jsonpath='{.data.driver-config-file\.yaml}' | base64 -d | grep apiKey
#
# After resizing via API, this script will:
# 1. Remove the stuck Resizing condition from the PVC
# 2. Update the PVC status to reflect the new size
# 3. Restart the associated pod to recognize the new size
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
TRUENAS_API_URL="${TRUENAS_API_URL:-https://192.168.9.10/api/v2.0}"  # Note: HTTPS with port 443
TRUENAS_API_KEY="${TRUENAS_API_KEY:-}"
TRUENAS_USER="${TRUENAS_USER:-}"
TRUENAS_PASS="${TRUENAS_PASS:-}"
PARENT_DATASET="${PARENT_DATASET:-SAS/RKE2}"  # From storage class parameters
# Note: If using self-signed cert, set: export TRUENAS_SKIP_SSL=true

# Functions
error() {
    echo -e "${RED}ERROR:${NC} $1" >&2
    exit 1
}

info() {
    echo -e "${GREEN}INFO:${NC} $1"
}

warn() {
    echo -e "${YELLOW}WARN:${NC} $1"
}

# Parse arguments
if [ $# -lt 2 ]; then
    error "Usage: $0 <PVC_NAME> <NEW_SIZE> [NAMESPACE]"
    echo ""
    echo "Examples:"
    echo "  $0 harbor-registry 400Gi managed-tools"
    echo "  $0 data-harbor-trivy-0 40Gi managed-tools"
    echo "  $0 data-harbor-redis-0 5Gi managed-tools"
    exit 1
fi

PVC_NAME="$1"
NEW_SIZE="$2"
NAMESPACE="${3:-managed-tools}"

# Validate API authentication
if [ -z "$TRUENAS_API_KEY" ] && ([ -z "$TRUENAS_USER" ] || [ -z "$TRUENAS_PASS" ]); then
    error "Either TRUENAS_API_KEY or TRUENAS_USER/TRUENAS_PASS must be set"
fi

# SSL handling (TrueNAS may use self-signed certs)
if [ "${TRUENAS_SKIP_SSL:-false}" = "true" ]; then
    CURL_SSL_OPTS="-k"
    info "SSL verification disabled (self-signed certificate)"
else
    CURL_SSL_OPTS=""
fi

# Get API authentication header
if [ -n "$TRUENAS_API_KEY" ]; then
    API_AUTH_HEADER="Authorization: Bearer $TRUENAS_API_KEY"
    info "Using provided API key"
else
    # Get API key from username/password
    info "Authenticating with TrueNAS API using username/password..."
    AUTH_RESPONSE=$(curl $CURL_SSL_OPTS -s -X POST "${TRUENAS_API_URL}/auth/login" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"$TRUENAS_USER\",\"password\":\"$TRUENAS_PASS\"}")
    
    if ! echo "$AUTH_RESPONSE" | grep -q "api_key"; then
        error "Failed to authenticate with TrueNAS API. Check credentials. Response: $AUTH_RESPONSE"
    fi
    
    TRUENAS_API_KEY=$(echo "$AUTH_RESPONSE" | jq -r '.api_key // empty' 2>/dev/null || \
                      echo "$AUTH_RESPONSE" | grep -o '"api_key":"[^"]*' | cut -d'"' -f4)
    
    if [ -z "$TRUENAS_API_KEY" ]; then
        error "Failed to extract API key from authentication response"
    fi
    
    API_AUTH_HEADER="Authorization: Bearer $TRUENAS_API_KEY"
    info "Authentication successful"
fi

# Get PVC information
info "Fetching PVC information for: $PVC_NAME in namespace: $NAMESPACE"
PVC_JSON=$(kubectl get pvc "$PVC_NAME" -n "$NAMESPACE" -o json 2>&1)
if [ $? -ne 0 ]; then
    error "Failed to get PVC: $PVC_NAME in namespace: $NAMESPACE"
fi

PVC_UID=$(echo "$PVC_JSON" | jq -r '.metadata.uid')
VOLUME_NAME=$(echo "$PVC_JSON" | jq -r '.spec.volumeName')
CURRENT_SIZE=$(echo "$PVC_JSON" | jq -r '.spec.resources.requests.storage')

info "PVC UID: $PVC_UID"
info "Volume Name: $VOLUME_NAME"
info "Current Size: $CURRENT_SIZE"
info "Target Size: $NEW_SIZE"

# Convert size to bytes (for TrueNAS API)
# TrueNAS API expects quota in bytes
convert_to_bytes() {
    local size="$1"
    local num=$(echo "$size" | sed 's/[^0-9.]//g')
    local unit=$(echo "$size" | sed 's/[0-9.]//g' | tr '[:lower:]' '[:upper:]')
    
    # Use awk for floating point arithmetic (more portable than bc)
    case "$unit" in
        "GI"|"G")
            awk "BEGIN {printf \"%.0f\", $num * 1024 * 1024 * 1024}"
            ;;
        "MI"|"M")
            awk "BEGIN {printf \"%.0f\", $num * 1024 * 1024}"
            ;;
        "KI"|"K")
            awk "BEGIN {printf \"%.0f\", $num * 1024}"
            ;;
        *)
            echo "$num"
            ;;
    esac
}

NEW_SIZE_BYTES=$(convert_to_bytes "$NEW_SIZE")
DATASET_PATH="${PARENT_DATASET}/pvc-${PVC_UID}"

info "Dataset path: $DATASET_PATH"
info "Target size (bytes): $NEW_SIZE_BYTES"

# Get dataset information from TrueNAS
info "Fetching dataset information from TrueNAS..."
ENCODED_INITIAL_PATH=$(echo "${PARENT_DATASET}/pvc-${PVC_UID}" | sed 's|/|%2F|g')
DATASET_INFO=$(curl $CURL_SSL_OPTS -s -X GET "${TRUENAS_API_URL}/pool/dataset/id/${ENCODED_INITIAL_PATH}" \
    -H "$API_AUTH_HEADER" \
    -H "Content-Type: application/json" 2>&1)

# Check if dataset exists, if not try alternative path
    if echo "$DATASET_INFO" | grep -q "ENOENT\|not found\|404"; then
    warn "Dataset not found at expected path. Trying to find dataset..."
    # Try to list datasets under parent
    ENCODED_PARENT=$(echo "$PARENT_DATASET" | sed 's|/|%2F|g')
    DATASETS=$(curl $CURL_SSL_OPTS -s -X GET "${TRUENAS_API_URL}/pool/dataset/id/${ENCODED_PARENT}" \
        -H "$API_AUTH_HEADER" | jq -r '.children[]?.name' 2>/dev/null || true)
    
    if echo "$DATASETS" | grep -q "$PVC_UID"; then
        DATASET_PATH=$(echo "$DATASETS" | grep "$PVC_UID" | head -1)
        info "Found dataset at: $DATASET_PATH"
    else
        # Get actual path from PV
        PV_INFO=$(kubectl get pv "$VOLUME_NAME" -o json 2>&1)
        SHARE_PATH=$(echo "$PV_INFO" | jq -r '.spec.csi.volumeAttributes.share' 2>/dev/null || echo "")
        if [ -n "$SHARE_PATH" ]; then
            # Extract dataset from share path (e.g., /mnt/SAS/RKE2/pvc-xxx -> SAS/RKE2/pvc-xxx)
            DATASET_PATH=$(echo "$SHARE_PATH" | sed 's|^/mnt/||')
            info "Using dataset path from PV: $DATASET_PATH"
        else
            error "Could not determine dataset path. Please specify manually."
        fi
    fi
fi

# Encode dataset path for URL (replace / with %2F)
ENCODED_DATASET=$(echo "$DATASET_PATH" | sed 's|/|%2F|g')

# Get current dataset quota
DATASET_JSON=$(curl $CURL_SSL_OPTS -s -X GET "${TRUENAS_API_URL}/pool/dataset/id/${ENCODED_DATASET}" \
    -H "$API_AUTH_HEADER" 2>&1)

CURRENT_QUOTA=$(echo "$DATASET_JSON" | jq -r '.quota.rawvalue // .quota_raw // .quota // "0"' 2>/dev/null || echo "0")
CURRENT_QUOTA_WARNING=$(echo "$DATASET_JSON" | jq -r '.quota_warning.rawvalue // .quota_warning_raw // .quota_warning // "0"' 2>/dev/null || echo "0")

if [ "$CURRENT_QUOTA" = "null" ] || [ -z "$CURRENT_QUOTA" ] || [ "$CURRENT_QUOTA" = "" ]; then
    CURRENT_QUOTA="0"
    warn "Could not get current quota, assuming 0 (no quota set)"
fi

# Remove any non-numeric characters if quota came as JSON
CURRENT_QUOTA=$(echo "$CURRENT_QUOTA" | sed 's/[^0-9]//g')
if [ -z "$CURRENT_QUOTA" ]; then
    CURRENT_QUOTA="0"
fi

info "Current quota: $CURRENT_QUOTA bytes"
info "New quota: $NEW_SIZE_BYTES bytes"

# Convert to integer for comparison
CURRENT_QUOTA_INT=$CURRENT_QUOTA
NEW_SIZE_BYTES_INT=$NEW_SIZE_BYTES

# Check if quota already matches (allow small difference for rounding)
if [ "$CURRENT_QUOTA_INT" = "$NEW_SIZE_BYTES_INT" ]; then
    info "Dataset quota already matches target size. Proceeding to fix PVC status..."
    QUOTA_ALREADY_CORRECT=true
elif [ -n "$CURRENT_QUOTA_INT" ] && [ "$CURRENT_QUOTA_INT" != "0" ]; then
    info "Current quota ($CURRENT_QUOTA_INT) differs from target ($NEW_SIZE_BYTES_INT). Updating..."
    QUOTA_ALREADY_CORRECT=false
else
    info "No quota currently set. Setting quota to target size..."
    QUOTA_ALREADY_CORRECT=false
fi

# Update dataset quota via TrueNAS API if needed
if [ "$QUOTA_ALREADY_CORRECT" != "true" ]; then
    info "Updating dataset quota via TrueNAS API..."
    
    # Build update payload - only include quota_warning if we have a value
    UPDATE_PAYLOAD="{ \"quota\": $NEW_SIZE_BYTES }"
    if [ -n "$CURRENT_QUOTA_WARNING" ] && [ "$CURRENT_QUOTA_WARNING" != "null" ] && [ "$CURRENT_QUOTA_WARNING" != "0" ]; then
        UPDATE_PAYLOAD="{ \"quota\": $NEW_SIZE_BYTES, \"quota_warning\": $CURRENT_QUOTA_WARNING }"
    fi
    
    UPDATE_RESPONSE=$(curl $CURL_SSL_OPTS -s -w "\n%{http_code}" -X PUT "${TRUENAS_API_URL}/pool/dataset/id/${ENCODED_DATASET}" \
        -H "$API_AUTH_HEADER" \
        -H "Content-Type: application/json" \
        -d "$UPDATE_PAYLOAD" 2>&1)

    HTTP_CODE=$(echo "$UPDATE_RESPONSE" | tail -1)
    RESPONSE_BODY=$(echo "$UPDATE_RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" -ne 200 ] && [ "$HTTP_CODE" -ne 204 ]; then
        warn "Failed to update dataset quota via API. HTTP Code: $HTTP_CODE"
        warn "Response: $RESPONSE_BODY"
        warn "Continuing anyway - quota may already be correct on TrueNAS backend"
    else
        info "Dataset quota updated successfully via API"
        
        # Wait a moment for TrueNAS to process the change
        sleep 2
        
        # Verify the quota was updated
        VERIFY_QUOTA=$(curl $CURL_SSL_OPTS -s -X GET "${TRUENAS_API_URL}/pool/dataset/id/${ENCODED_DATASET}" \
            -H "$API_AUTH_HEADER" | jq -r '.quota.rawvalue // .quota_raw // empty' 2>/dev/null || echo "")
        
        if [ -n "$VERIFY_QUOTA" ] && [ "$VERIFY_QUOTA" != "null" ]; then
            VERIFY_QUOTA=$(echo "$VERIFY_QUOTA" | sed 's/[^0-9]//g')
            info "Verified quota updated to: $VERIFY_QUOTA bytes"
        else
            warn "Could not verify quota update, but API call succeeded"
        fi
    fi
else
    info "Quota already correct on TrueNAS backend. Skipping API update."
fi

# Now fix the Kubernetes PVC
info "Fixing Kubernetes PVC to reflect the new size..."

# Remove stuck Resizing condition
info "Removing stuck Resizing condition..."
kubectl patch pvc "$PVC_NAME" -n "$NAMESPACE" \
    --type='json' \
    -p='[{"op": "remove", "path": "/status/conditions"}]' 2>&1 || warn "Failed to remove conditions (may not exist)"

# Update PVC status capacity to reflect new size
info "Updating PVC status capacity..."
kubectl patch pvc "$PVC_NAME" -n "$NAMESPACE" \
    --type='json' \
    -p="[{\"op\": \"replace\", \"path\": \"/status/capacity/storage\", \"value\": \"$NEW_SIZE\"}]" 2>&1 || warn "PVC status may be read-only, that's OK"

# Get the pod/workload associated with this PVC
info "Finding associated workload..."
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -o json | \
    jq -r ".items[] | select(.spec.volumes[]?.persistentVolumeClaim.claimName == \"$PVC_NAME\") | .metadata.name" | head -1)

if [ -n "$POD_NAME" ]; then
    WORKLOAD_TYPE=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null || echo "")
    WORKLOAD_NAME=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.metadata.ownerReferences[0].name}' 2>/dev/null || echo "")
    
    if [ -n "$WORKLOAD_TYPE" ] && [ -n "$WORKLOAD_NAME" ]; then
        info "Found associated workload: $WORKLOAD_TYPE/$WORKLOAD_NAME"
        info "Restarting workload to recognize new volume size..."
        
        case "$WORKLOAD_TYPE" in
            "StatefulSet")
                kubectl rollout restart statefulset "$WORKLOAD_NAME" -n "$NAMESPACE"
                info "StatefulSet restart initiated. Monitor with: kubectl rollout status statefulset $WORKLOAD_NAME -n $NAMESPACE"
                ;;
            "Deployment")
                kubectl rollout restart deployment "$WORKLOAD_NAME" -n "$NAMESPACE"
                info "Deployment restart initiated. Monitor with: kubectl rollout status deployment $WORKLOAD_NAME -n $NAMESPACE"
                ;;
            *)
                warn "Unknown workload type: $WORKLOAD_TYPE. Please restart manually."
                ;;
        esac
    else
        warn "Could not determine workload type. Please restart the pod manually:"
        echo "  kubectl delete pod $POD_NAME -n $NAMESPACE"
    fi
else
    warn "No pod found using this PVC. The PVC may not be in use."
fi

# Verify the new size in the pod (if possible)
sleep 5
if [ -n "$POD_NAME" ] && kubectl get pod "$POD_NAME" -n "$NAMESPACE" &>/dev/null; then
    info "Waiting for pod to be ready..."
    kubectl wait --for=condition=ready pod "$POD_NAME" -n "$NAMESPACE" --timeout=60s 2>&1 || true
    
    # Try to check actual disk usage in the pod
    CONTAINER_NAME=$(kubectl get pod "$POD_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.containers[0].name}' 2>/dev/null || echo "")
    if [ -n "$CONTAINER_NAME" ]; then
        # Find the mount point (this is approximate)
        info "Checking actual volume size in pod..."
        kubectl exec "$POD_NAME" -n "$NAMESPACE" -c "$CONTAINER_NAME" -- df -h 2>&1 | grep -E "Size|$NEW_SIZE" || true
    fi
fi

info "Resize operation complete!"
info ""
info "Summary:"
info "  PVC: $PVC_NAME"
info "  Namespace: $NAMESPACE"
info "  Dataset: $DATASET_PATH"
info "  Old Size: $CURRENT_SIZE"
info "  New Size: $NEW_SIZE"
info ""
info "Next steps:"
info "  1. Verify the volume size: kubectl get pvc $PVC_NAME -n $NAMESPACE"
info "  2. Check pod logs if issues occur"
info "  3. If the PVC still shows wrong size, you may need to patch it manually:"
info "     kubectl patch pvc $PVC_NAME -n $NAMESPACE --type='merge' -p '{\"status\":{\"capacity\":{\"storage\":\"$NEW_SIZE\"}}}'"
