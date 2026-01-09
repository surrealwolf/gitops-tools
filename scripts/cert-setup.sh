#!/bin/bash
# Certificate Setup Script
# This script installs Harbor wildcard certificate from Kubernetes to Docker
#
# Usage:
#   ./scripts/cert-setup.sh

set -e

NAMESPACE="${HARBOR_NAMESPACE:-managed-tools}"
SECRET_NAME="${HARBOR_TLS_SECRET:-wildcard-dataknife-net-tls}"
HARBOR_URL="${HARBOR_REGISTRY_URL:-harbor.dataknife.net}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Harbor Certificate Installation${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Configuration:"
echo "  Namespace: ${NAMESPACE}"
echo "  Secret: ${SECRET_NAME}"
echo "  Harbor URL: ${HARBOR_URL}"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl is not installed or not in PATH${NC}"
    exit 1
fi

# Check if secret exists
if ! kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" > /dev/null 2>&1; then
    echo -e "${RED}Error: Secret '${SECRET_NAME}' not found in namespace '${NAMESPACE}'${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Secret found in Kubernetes${NC}"
echo ""

# Extract certificate
echo "Extracting certificate from Kubernetes secret..."
TEMP_CERT=$(mktemp)
kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.tls\.crt}' | base64 -d > "${TEMP_CERT}"

if [ ! -s "${TEMP_CERT}" ]; then
    echo -e "${RED}Error: Failed to extract certificate${NC}"
    rm -f "${TEMP_CERT}"
    exit 1
fi

echo -e "${GREEN}✓ Certificate extracted${NC}"
echo ""

# Install certificate to Docker
CERT_DIR="/etc/docker/certs.d/${HARBOR_URL}"
CERT_FILE="${CERT_DIR}/ca.crt"

echo "Installing certificate to Docker..."
echo "  Directory: ${CERT_DIR}"
echo "  File: ${CERT_FILE}"
echo ""
echo "This requires sudo privileges..."

sudo mkdir -p "${CERT_DIR}"
sudo cp "${TEMP_CERT}" "${CERT_FILE}"
sudo chmod 644 "${CERT_FILE}"

rm -f "${TEMP_CERT}"

echo -e "${GREEN}✓ Certificate installed to ${CERT_FILE}${NC}"
echo ""

# Restart Docker
echo "Restarting Docker daemon..."
sudo systemctl restart docker
sleep 3

if docker info > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Docker restarted successfully${NC}"
else
    echo -e "${YELLOW}⚠️  Docker may need a moment to start${NC}"
fi
echo ""

# Verify certificate
echo "Verifying certificate installation..."
if [ -f "${CERT_FILE}" ]; then
    CERT_SUBJECT=$(openssl x509 -in "${CERT_FILE}" -noout -subject 2>/dev/null | sed 's/subject=//' || echo "unknown")
    echo -e "${GREEN}✓ Certificate file exists${NC}"
    echo "  Subject: ${CERT_SUBJECT}"
else
    echo -e "${RED}✗ Certificate file not found${NC}"
    exit 1
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Certificate Installation Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "You can now use Docker with Harbor:"
echo "  docker login ${HARBOR_URL} -u <username> -p <password>"
echo ""
echo "To test, run:"
echo "  ./scripts/harbor-test.sh"
echo ""
