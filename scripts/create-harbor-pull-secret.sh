#!/bin/bash
# Create Kubernetes image pull secret for Harbor robot account
# This secret allows pods to pull images from Harbor registry
#
# Usage:
#   ./scripts/create-harbor-pull-secret.sh [namespace] [secret-name]
#   ./scripts/create-harbor-pull-secret.sh default harbor-registry-secret
#   ./scripts/create-harbor-pull-secret.sh managed-tools harbor-registry-secret

set -e

# Load .env file if it exists
if [ -f .env ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        export "$line" 2>/dev/null || true
    done < .env
fi

# Configuration
NAMESPACE="${1:-default}"
SECRET_NAME="${2:-harbor-registry-secret}"
HARBOR_URL="${HARBOR_REGISTRY_URL:-${HARBOR_URL:-harbor.dataknife.net}}"
ROBOT_USER=$(grep "^HARBOR_ROBOT_ACCOUNT_FULL_NAME=" .env 2>/dev/null | cut -d'=' -f2- || echo "${HARBOR_ROBOT_ACCOUNT_FULL_NAME}")
ROBOT_PASS="${HARBOR_ROBOT_ACCOUNT_SECRET}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Harbor Image Pull Secret Creation${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Configuration:"
echo "  Namespace: ${NAMESPACE}"
echo "  Secret Name: ${SECRET_NAME}"
echo "  Harbor URL: ${HARBOR_URL}"
echo "  Robot Account: ${ROBOT_USER:-<not set>}"
echo ""

# Verify robot account credentials
if [ -z "$ROBOT_USER" ] || [ -z "$ROBOT_PASS" ]; then
    echo -e "${RED}Error: Robot account credentials not found${NC}"
    echo ""
    echo "Required environment variables:"
    echo "  HARBOR_ROBOT_ACCOUNT_FULL_NAME"
    echo "  HARBOR_ROBOT_ACCOUNT_SECRET"
    echo ""
    echo "These should be in your .env file. If not, create the robot account first:"
    echo "  ./scripts/harbor-setup.sh robot"
    exit 1
fi

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Create namespace if it doesn't exist
echo "Creating namespace if it doesn't exist..."
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - > /dev/null
echo -e "${GREEN}✓ Namespace ready${NC}"
echo ""

# Check if secret already exists
if kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    echo -e "${YELLOW}Secret '${SECRET_NAME}' already exists in namespace '${NAMESPACE}'${NC}"
    read -p "Do you want to delete and recreate it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete secret "${SECRET_NAME}" -n "${NAMESPACE}" > /dev/null
        echo -e "${GREEN}✓ Existing secret deleted${NC}"
    else
        echo "Aborted."
        exit 0
    fi
    echo ""
fi

# Create the image pull secret
echo "Creating image pull secret..."
kubectl create secret docker-registry "${SECRET_NAME}" \
  --docker-server="${HARBOR_URL}" \
  --docker-username="${ROBOT_USER}" \
  --docker-password="${ROBOT_PASS}" \
  --docker-email="noreply@dataknife.net" \
  -n "${NAMESPACE}" > /dev/null

echo -e "${GREEN}✓ Image pull secret '${SECRET_NAME}' created in namespace '${NAMESPACE}'${NC}"
echo ""

# Verify the secret
echo "Verifying secret..."
if kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" &>/dev/null; then
    echo -e "${GREEN}✓ Secret verified${NC}"
    echo ""
    echo "Secret details:"
    kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.type}{"\n"}' | head -1
    echo ""
else
    echo -e "${RED}✗ Secret verification failed${NC}"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Image Pull Secret Created Successfully${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Usage in Pods:"
echo ""
echo "Add to pod spec:"
echo "  spec:"
echo "    imagePullSecrets:"
echo "    - name: ${SECRET_NAME}"
echo ""
echo "Or patch the default service account for namespace-wide use:"
echo "  kubectl patch serviceaccount default -n ${NAMESPACE} \\"
echo "    -p '{\"imagePullSecrets\":[{\"name\":\"${SECRET_NAME}\"}]}'"
echo ""
