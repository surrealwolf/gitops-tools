#!/bin/bash
# Run Harbor push/pull tests after certificate is installed
# This script will check if the certificate is installed and run all tests

set -e

# Load .env file if it exists
if [ -f .env ]; then
    # Read .env file line by line to handle $ characters properly
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        # Export the variable (this preserves $ characters)
        export "$line" 2>/dev/null || true
    done < .env
fi

HARBOR_URL="${HARBOR_REGISTRY_URL:-harbor.dataknife.net}"
# Read robot account directly from .env to preserve $ character
ROBOT_USER=$(grep "^HARBOR_ROBOT_ACCOUNT_FULL_NAME=" .env 2>/dev/null | cut -d'=' -f2- || echo "${HARBOR_ROBOT_ACCOUNT_FULL_NAME}")
ROBOT_PASS="${HARBOR_ROBOT_ACCOUNT_SECRET}"

CERT_FILE="/etc/docker/certs.d/${HARBOR_URL}/ca.crt"

echo "=========================================="
echo "Harbor Push/Pull Tests"
echo "=========================================="
echo ""

# Check if certificate is installed
if [ ! -f "$CERT_FILE" ]; then
    echo "⚠️  Certificate not found at ${CERT_FILE}"
    echo ""
    echo "Please install the certificate first:"
    echo "  sudo mkdir -p /etc/docker/certs.d/${HARBOR_URL}"
    echo "  sudo cp /tmp/harbor-cert.pem ${CERT_FILE}"
    echo "  sudo chmod 644 ${CERT_FILE}"
    echo "  sudo systemctl restart docker"
    echo ""
    exit 1
fi

echo "✓ Certificate found at ${CERT_FILE}"
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "Error: Docker is not running"
    exit 1
fi

echo "✓ Docker is running"
echo ""

# Test 1: Login
echo "=========================================="
echo "Test 1: Login to Harbor"
echo "=========================================="
if echo "${ROBOT_PASS}" | docker login ${HARBOR_URL} -u "${ROBOT_USER}" --password-stdin > /dev/null 2>&1; then
    echo "✓ Successfully logged in to Harbor"
else
    echo "✗ Failed to login to Harbor"
    exit 1
fi
echo ""

# Test 2: Push to local registry
echo "=========================================="
echo "Test 2: Push to local registry (library project)"
echo "=========================================="
TEST_TAG="test-$(date +%s)"
docker tag alpine:latest ${HARBOR_URL}/library/test-alpine:${TEST_TAG}
if docker push ${HARBOR_URL}/library/test-alpine:${TEST_TAG} > /dev/null 2>&1; then
    echo "✓ Successfully pushed ${HARBOR_URL}/library/test-alpine:${TEST_TAG}"
else
    echo "✗ Failed to push to local registry"
    exit 1
fi
echo ""

# Test 3: Pull from local registry
echo "=========================================="
echo "Test 3: Pull from local registry"
echo "=========================================="
docker rmi ${HARBOR_URL}/library/test-alpine:${TEST_TAG} 2>/dev/null || true
if docker pull ${HARBOR_URL}/library/test-alpine:${TEST_TAG} > /dev/null 2>&1; then
    echo "✓ Successfully pulled ${HARBOR_URL}/library/test-alpine:${TEST_TAG}"
else
    echo "✗ Failed to pull from local registry"
    exit 1
fi
echo ""

# Test 4: Pull from DockerHub cache
echo "=========================================="
echo "Test 4: Pull from DockerHub cache (dockerhub project)"
echo "=========================================="
if docker pull ${HARBOR_URL}/dockerhub/nginx:alpine > /dev/null 2>&1; then
    echo "✓ Successfully pulled ${HARBOR_URL}/dockerhub/nginx:alpine"
else
    echo "✗ Failed to pull from DockerHub cache"
    echo "  Note: This may indicate proxy cache is not configured"
    exit 1
fi
echo ""

# Test 5: Pull from DockerHub cache again (should use cache)
echo "=========================================="
echo "Test 5: Pull from DockerHub cache again (should use cache)"
echo "=========================================="
docker rmi ${HARBOR_URL}/dockerhub/nginx:alpine 2>/dev/null || true
if docker pull ${HARBOR_URL}/dockerhub/nginx:alpine > /dev/null 2>&1; then
    echo "✓ Successfully pulled ${HARBOR_URL}/dockerhub/nginx:alpine (from cache)"
else
    echo "✗ Failed to pull from cache"
    exit 1
fi
echo ""

# Summary
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo ""
echo "✓ All tests passed!"
echo ""
echo "Results:"
echo "  1. ✓ Login to Harbor"
echo "  2. ✓ Push to local registry (library project)"
echo "  3. ✓ Pull from local registry"
echo "  4. ✓ Pull from DockerHub cache (dockerhub project)"
echo "  5. ✓ Pull from DockerHub cache again (cached)"
echo ""
echo "Harbor images:"
docker images | grep "${HARBOR_URL}" | head -5
echo ""
