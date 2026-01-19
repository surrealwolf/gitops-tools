#!/bin/bash
# Configure containerd on K3s nodes to trust Harbor registry certificate
# This allows Kubernetes to pull images from Harbor registry
#
# Usage:
#   ./scripts/configure-containerd-harbor-cert.sh
#
# Note: This script must be run on each K3s node with sudo privileges
#       or use it with a DaemonSet/init container

set -e

HARBOR_URL="${HARBOR_REGISTRY_URL:-harbor.dataknife.net}"
# Note: Harbor now uses the default ingress certificate
# This script extracts the certificate from the Harbor endpoint or uses a provided certificate file
CERT_FILE="${HARBOR_CERT_FILE:-}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Configure containerd for Harbor Registry${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Configuration:"
echo "  Harbor URL: ${HARBOR_URL}"
echo "  Certificate file: ${CERT_FILE:-<will be extracted from endpoint>}"
echo ""
echo "Note: Harbor now uses the default ingress certificate."
echo "This script will extract the certificate from the Harbor endpoint if not provided."
echo ""

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}Warning: Not running as root. This script requires sudo privileges.${NC}"
    echo -e "${YELLOW}Attempting to use sudo...${NC}"
    SUDO="sudo"
else
    SUDO=""
fi

# Determine containerd certs directory (K3s specific)
if [ -d "/var/lib/rancher/k3s/agent/etc/containerd/certs.d" ]; then
    # K3s containerd certs directory
    CERT_BASE_DIR="/var/lib/rancher/k3s/agent/etc/containerd/certs.d"
elif [ -d "/etc/containerd/certs.d" ]; then
    # Standard containerd certs directory
    CERT_BASE_DIR="/etc/containerd/certs.d"
else
    echo -e "${YELLOW}Warning: containerd certs directory not found in standard locations${NC}"
    echo -e "${YELLOW}Attempting to create /etc/containerd/certs.d${NC}"
    CERT_BASE_DIR="/etc/containerd/certs.d"
fi

CERT_DIR="${CERT_BASE_DIR}/${HARBOR_URL}"
CERT_FILE="${CERT_DIR}/ca.crt"

echo "Certificate directory: ${CERT_DIR}"
echo "Certificate file: ${CERT_FILE}"
echo ""

# Extract certificate from Harbor endpoint or use provided file
TEMP_CERT=$(mktemp)

if [ -n "${CERT_FILE}" ] && [ -f "${CERT_FILE}" ]; then
    # Use provided certificate file
    echo "Using provided certificate file: ${CERT_FILE}"
    cp "${CERT_FILE}" "${TEMP_CERT}"
    echo -e "${GREEN}✓ Certificate file found${NC}"
elif command -v openssl &> /dev/null; then
    # Extract certificate from Harbor endpoint
    echo "Extracting certificate from Harbor endpoint..."
    if echo | openssl s_client -showcerts -connect "${HARBOR_URL}:443" -servername "${HARBOR_URL}" 2>/dev/null | \
       sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > "${TEMP_CERT}" && \
       [ -s "${TEMP_CERT}" ]; then
        echo -e "${GREEN}✓ Certificate extracted from Harbor endpoint${NC}"
    else
        echo -e "${YELLOW}Warning: Could not extract certificate from endpoint${NC}"
        echo -e "${YELLOW}Please provide the certificate file manually using: HARBOR_CERT_FILE=/path/to/cert.crt ${0}${NC}"
        rm -f "${TEMP_CERT}"
        exit 1
    fi
else
    echo -e "${RED}Error: openssl not available and no certificate file provided${NC}"
    echo -e "${RED}Please install openssl or provide certificate file using: HARBOR_CERT_FILE=/path/to/cert.crt${NC}"
    rm -f "${TEMP_CERT}"
    exit 1
fi

# Create certificate directory
echo "Creating certificate directory..."
${SUDO} mkdir -p "${CERT_DIR}"

# Copy certificate
echo "Installing certificate to containerd..."
${SUDO} cp "${TEMP_CERT}" "${CERT_FILE}"
${SUDO} chmod 644 "${CERT_FILE}"
rm -f "${TEMP_CERT}"
echo -e "${GREEN}✓ Certificate installed to ${CERT_FILE}${NC}"

# Restart containerd (if running as systemd service)
if systemctl is-active --quiet containerd 2>/dev/null; then
    echo ""
    echo "Restarting containerd service..."
    ${SUDO} systemctl restart containerd
    echo -e "${GREEN}✓ containerd restarted${NC}"
elif systemctl is-active --quiet k3s-agent 2>/dev/null; then
    echo ""
    echo -e "${YELLOW}K3s agent detected. Restarting k3s-agent...${NC}"
    ${SUDO} systemctl restart k3s-agent
    echo -e "${GREEN}✓ k3s-agent restarted${NC}"
elif systemctl is-active --quiet k3s 2>/dev/null; then
    echo ""
    echo -e "${YELLOW}K3s server detected. Restarting k3s...${NC}"
    ${SUDO} systemctl restart k3s
    echo -e "${GREEN}✓ k3s restarted${NC}"
else
    echo -e "${YELLOW}Warning: containerd/k3s service not found or not running as systemd service${NC}"
    echo -e "${YELLOW}You may need to restart containerd manually${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Configuration Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "containerd is now configured to trust Harbor registry certificates."
echo "Kubernetes can now pull images from ${HARBOR_URL}"
echo ""
echo "To verify:"
echo "  kubectl run test-pull --image=${HARBOR_URL}/dockerhub/library/alpine:latest --rm -it --restart=Never -- echo 'Success'"
echo ""
