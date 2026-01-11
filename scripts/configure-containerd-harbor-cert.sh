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

NAMESPACE="${HARBOR_NAMESPACE:-managed-tools}"
SECRET_NAME="${HARBOR_TLS_SECRET:-wildcard-dataknife-net-tls}"
HARBOR_URL="${HARBOR_REGISTRY_URL:-harbor.dataknife.net}"

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
echo "  Namespace: ${NAMESPACE}"
echo "  Secret: ${SECRET_NAME}"
echo "  Harbor URL: ${HARBOR_URL}"
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

# Check if kubectl is available and secret exists
if command -v kubectl &> /dev/null; then
    if kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Secret found in Kubernetes${NC}"
        
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
    else
        echo -e "${YELLOW}Warning: Secret '${SECRET_NAME}' not found in namespace '${NAMESPACE}'${NC}"
        echo -e "${YELLOW}You may need to provide the certificate file manually${NC}"
        TEMP_CERT=""
    fi
else
    echo -e "${YELLOW}Warning: kubectl not available. Cannot extract certificate from secret.${NC}"
    echo -e "${YELLOW}Please provide the certificate file manually or ensure kubectl is available${NC}"
    TEMP_CERT=""
fi

# Create certificate directory
echo "Creating certificate directory..."
${SUDO} mkdir -p "${CERT_DIR}"

# Copy certificate
if [ -n "${TEMP_CERT}" ] && [ -f "${TEMP_CERT}" ]; then
    echo "Installing certificate to containerd..."
    ${SUDO} cp "${TEMP_CERT}" "${CERT_FILE}"
    ${SUDO} chmod 644 "${CERT_FILE}"
    rm -f "${TEMP_CERT}"
    echo -e "${GREEN}✓ Certificate installed to ${CERT_FILE}${NC}"
else
    echo -e "${YELLOW}Certificate file not available. Please manually copy the certificate to:${NC}"
    echo -e "${YELLOW}  ${CERT_FILE}${NC}"
    exit 1
fi

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
