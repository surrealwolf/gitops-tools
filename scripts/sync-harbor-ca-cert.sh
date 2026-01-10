#!/bin/bash
# Sync Wildcard CA Certificate to GitLab Runner Namespace
# This script copies the wildcard-dataknife-net-tls secret from managed-tools
# to managed-cicd namespace for GitLab Runner job pods to access Harbor registry
#
# Usage:
#   ./scripts/sync-harbor-ca-cert.sh

set -e

SOURCE_NAMESPACE="${SOURCE_NAMESPACE:-managed-tools}"
SOURCE_SECRET="${SOURCE_SECRET:-wildcard-dataknife-net-tls}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-managed-cicd}"
TARGET_SECRET="${TARGET_SECRET:-harbor-ca-cert}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Sync Wildcard Certificate for GitLab Runner${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Configuration:"
echo "  Source Namespace: ${SOURCE_NAMESPACE}"
echo "  Source Secret: ${SOURCE_SECRET}"
echo "  Target Namespace: ${TARGET_NAMESPACE}"
echo "  Target Secret: harbor-ca-cert (CA certificate only, no private key)"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Check if source secret exists
if ! kubectl get secret "${SOURCE_SECRET}" -n "${SOURCE_NAMESPACE}" > /dev/null 2>&1; then
    echo -e "${RED}Error: Secret '${SOURCE_SECRET}' not found in namespace '${SOURCE_NAMESPACE}'${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Source secret found${NC}"

# Create target namespace if it doesn't exist
if ! kubectl get namespace "${TARGET_NAMESPACE}" > /dev/null 2>&1; then
    echo "Creating namespace ${TARGET_NAMESPACE}..."
    kubectl create namespace "${TARGET_NAMESPACE}"
    echo -e "${GREEN}✓ Namespace created${NC}"
fi

# Extract CA certificate and create a secret with only ca.crt (no private key)
# This prevents Docker from looking for client certificates
echo "Extracting CA certificate and creating harbor-ca-cert secret in ${TARGET_NAMESPACE} namespace..."
kubectl get secret "${SOURCE_SECRET}" -n "${SOURCE_NAMESPACE}" -o jsonpath='{.data.tls\.crt}' | base64 -d | \
  kubectl create secret generic harbor-ca-cert \
  --from-literal=ca.crt=/dev/stdin \
  -n "${TARGET_NAMESPACE}" \
  --dry-run=client -o yaml | \
  kubectl apply -f -

if kubectl get secret harbor-ca-cert -n "${TARGET_NAMESPACE}" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Secret 'harbor-ca-cert' created/updated in namespace '${TARGET_NAMESPACE}'${NC}"
else
    echo -e "${RED}Error: Failed to create secret${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Certificate Sync Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "The wildcard certificate has been synced to the GitLab Runner namespace."
echo "GitLab Runner job pods can now pull/push images from Harbor registry."
echo ""
echo "To verify:"
echo "  kubectl get secret ${TARGET_SECRET} -n ${TARGET_NAMESPACE}"
echo ""
