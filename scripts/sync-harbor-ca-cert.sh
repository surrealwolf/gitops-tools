#!/bin/bash
# Extract Harbor Registry CA Certificate for GitLab Runner
# This script extracts the CA certificate from Harbor's registry endpoint
# and creates a secret for GitLab Runner job pods to access Harbor registry
#
# Since Harbor uses the default ingress certificate, we extract the certificate
# directly from the Harbor registry endpoint (or from ingress controller default cert)
#
# Usage:
#   ./scripts/sync-harbor-ca-cert.sh
#
# Alternative: If the default ingress certificate is already trusted by the system,
# you may not need this script. However, Docker/containerd in job pods may still
# require explicit certificate trust configuration.

set -e

HARBOR_URL="${HARBOR_URL:-harbor.dataknife.net}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-managed-cicd}"
TARGET_SECRET="${TARGET_SECRET:-harbor-ca-cert}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Extract Harbor CA Certificate for GitLab Runner${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Configuration:"
echo "  Harbor URL: ${HARBOR_URL}"
echo "  Target Namespace: ${TARGET_NAMESPACE}"
echo "  Target Secret: harbor-ca-cert (CA certificate only, no private key)"
echo ""
echo "Note: Harbor now uses the default ingress certificate."
echo "This script extracts the certificate from the Harbor registry endpoint."
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Check if openssl is available for certificate extraction
if ! command -v openssl &> /dev/null; then
    echo -e "${RED}Error: openssl is not installed or not in PATH${NC}"
    exit 1
fi

# Create target namespace if it doesn't exist
if ! kubectl get namespace "${TARGET_NAMESPACE}" > /dev/null 2>&1; then
    echo "Creating namespace ${TARGET_NAMESPACE}..."
    kubectl create namespace "${TARGET_NAMESPACE}"
    echo -e "${GREEN}✓ Namespace created${NC}"
fi

# Extract certificate from Harbor registry endpoint
echo "Extracting CA certificate from Harbor registry endpoint..."
TEMP_CERT=$(mktemp)

# Method 1: Try to get certificate from Harbor endpoint using openssl
if echo | openssl s_client -showcerts -connect "${HARBOR_URL}:443" -servername "${HARBOR_URL}" 2>/dev/null | \
   sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > "${TEMP_CERT}" && \
   [ -s "${TEMP_CERT}" ]; then
    echo -e "${GREEN}✓ Certificate extracted from Harbor endpoint${NC}"
else
    # Method 2: Try to get from ingress controller's default certificate secret
    echo "Attempting to extract from ingress controller default certificate..."
    
    # Try to find the default ingress certificate secret (nginx-ingress typically uses ingress-nginx-admission)
    # Or check for ingress controller's default certificate
    INGRESS_NS="${INGRESS_NS:-ingress-nginx}"
    
    if kubectl get secret -n "${INGRESS_NS}" 2>/dev/null | grep -q "default.*tls\|ingress.*cert"; then
        DEFAULT_CERT_SECRET=$(kubectl get secret -n "${INGRESS_NS}" -o name | grep -E "default.*tls|ingress.*cert" | head -1 | cut -d/ -f2)
        if [ -n "${DEFAULT_CERT_SECRET}" ]; then
            kubectl get secret "${DEFAULT_CERT_SECRET}" -n "${INGRESS_NS}" -o jsonpath='{.data.tls\.crt}' | base64 -d > "${TEMP_CERT}"
            echo -e "${GREEN}✓ Certificate extracted from ingress controller secret${NC}"
        fi
    fi
    
    if [ ! -s "${TEMP_CERT}" ]; then
        echo -e "${YELLOW}Warning: Could not automatically extract certificate${NC}"
        echo -e "${YELLOW}Please manually extract the CA certificate from Harbor and save it to: ${TEMP_CERT}${NC}"
        echo -e "${YELLOW}Or run: openssl s_client -showcerts -connect ${HARBOR_URL}:443 -servername ${HARBOR_URL} < /dev/null 2>/dev/null | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > ${TEMP_CERT}${NC}"
        exit 1
    fi
fi

# Extract the CA certificate (usually the last certificate in the chain, or the root)
# For simplicity, we'll use the full certificate chain as the CA cert
# In practice, you might want to extract just the root/intermediate CA
CA_CERT=$(mktemp)
openssl x509 -in "${TEMP_CERT}" -out "${CA_CERT}" -outform PEM 2>/dev/null || cp "${TEMP_CERT}" "${CA_CERT}"

# Create secret with only ca.crt (no private key)
# This prevents Docker from looking for client certificates
echo "Creating harbor-ca-cert secret in ${TARGET_NAMESPACE} namespace..."
kubectl create secret generic "${TARGET_SECRET}" \
  --from-file=ca.crt="${CA_CERT}" \
  -n "${TARGET_NAMESPACE}" \
  --dry-run=client -o yaml | \
  kubectl apply -f -

rm -f "${TEMP_CERT}" "${CA_CERT}"

if kubectl get secret "${TARGET_SECRET}" -n "${TARGET_NAMESPACE}" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Secret '${TARGET_SECRET}' created/updated in namespace '${TARGET_NAMESPACE}'${NC}"
else
    echo -e "${RED}Error: Failed to create secret${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Certificate Extraction Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "The Harbor CA certificate has been extracted and stored in the GitLab Runner namespace."
echo "GitLab Runner job pods can now pull/push images from Harbor registry."
echo ""
echo "To verify:"
echo "  kubectl get secret ${TARGET_SECRET} -n ${TARGET_NAMESPACE}"
echo ""
