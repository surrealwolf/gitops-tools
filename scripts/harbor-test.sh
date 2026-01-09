#!/bin/bash
# Harbor Test Script
# This script tests Harbor push/pull functionality for both local registry and proxy cache
#
# Usage:
#   ./scripts/harbor-test.sh

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
HARBOR_URL="${HARBOR_REGISTRY_URL:-harbor.dataknife.net}"
ROBOT_USER=$(grep "^HARBOR_ROBOT_ACCOUNT_FULL_NAME=" .env 2>/dev/null | cut -d'=' -f2- || echo "${HARBOR_ROBOT_ACCOUNT_FULL_NAME}")
ROBOT_PASS="${HARBOR_ROBOT_ACCOUNT_SECRET}"
CERT_FILE="/etc/docker/certs.d/${HARBOR_URL}/ca.crt"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Harbor Push/Pull Tests${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Verify robot account is set
if [ -z "$ROBOT_USER" ] || [ -z "$ROBOT_PASS" ]; then
    echo -e "${RED}Error: Robot account credentials not found in .env file${NC}"
    echo "  Required: HARBOR_ROBOT_ACCOUNT_FULL_NAME and HARBOR_ROBOT_ACCOUNT_SECRET"
    exit 1
fi

# Check if certificate is installed
if [ ! -f "$CERT_FILE" ]; then
    echo -e "${YELLOW}⚠️  Certificate not found at ${CERT_FILE}${NC}"
    echo "Please install the certificate first:"
    echo "  ./scripts/cert-setup.sh"
    exit 1
fi
echo -e "${GREEN}✓ Certificate found${NC}"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Docker is running${NC}"
echo ""

# Test 1: Login
echo -e "${GREEN}Test 1: Login to Harbor${NC}"
if echo "${ROBOT_PASS}" | docker login ${HARBOR_URL} -u "${ROBOT_USER}" --password-stdin > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Successfully logged in${NC}"
else
    echo -e "${RED}✗ Failed to login${NC}"
    exit 1
fi
echo ""

# Test 2: Push to local registry
echo -e "${GREEN}Test 2: Push to local registry (library project)${NC}"
TEST_TAG="test-$(date +%s)"
docker tag alpine:latest ${HARBOR_URL}/library/test-alpine:${TEST_TAG} 2>/dev/null || docker pull alpine:latest > /dev/null 2>&1 && docker tag alpine:latest ${HARBOR_URL}/library/test-alpine:${TEST_TAG}
if docker push ${HARBOR_URL}/library/test-alpine:${TEST_TAG} > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Successfully pushed ${HARBOR_URL}/library/test-alpine:${TEST_TAG}${NC}"
else
    echo -e "${RED}✗ Failed to push to local registry${NC}"
    exit 1
fi
echo ""

# Test 3: Pull from local registry
echo -e "${GREEN}Test 3: Pull from local registry${NC}"
docker rmi ${HARBOR_URL}/library/test-alpine:${TEST_TAG} 2>/dev/null || true
if docker pull ${HARBOR_URL}/library/test-alpine:${TEST_TAG} > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Successfully pulled from local registry${NC}"
else
    echo -e "${RED}✗ Failed to pull from local registry${NC}"
    exit 1
fi
echo ""

# Test 4: Pull from DockerHub cache
echo -e "${GREEN}Test 4: Pull from DockerHub cache (dockerhub project)${NC}"
if docker pull ${HARBOR_URL}/dockerhub/nginx:alpine > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Successfully pulled from DockerHub cache${NC}"
else
    echo -e "${YELLOW}⚠️  Failed to pull from DockerHub cache${NC}"
    echo "  Note: This may indicate proxy cache is not configured"
    exit 1
fi
echo ""

# Test 5: Pull from DockerHub cache again (should use cache)
echo -e "${GREEN}Test 5: Pull from DockerHub cache again (should use cache)${NC}"
docker rmi ${HARBOR_URL}/dockerhub/nginx:alpine 2>/dev/null || true
if docker pull ${HARBOR_URL}/dockerhub/nginx:alpine > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Successfully pulled from cache${NC}"
else
    echo -e "${RED}✗ Failed to pull from cache${NC}"
    exit 1
fi
echo ""

# Cleanup
echo "Cleaning up test images..."
docker rmi ${HARBOR_URL}/library/test-alpine:${TEST_TAG} 2>/dev/null || true
docker rmi ${HARBOR_URL}/dockerhub/nginx:alpine 2>/dev/null || true
echo ""

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}All Tests Passed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Results:"
echo "  1. ✓ Login to Harbor"
echo "  2. ✓ Push to local registry (library project)"
echo "  3. ✓ Pull from local registry"
echo "  4. ✓ Pull from DockerHub cache (dockerhub project)"
echo "  5. ✓ Pull from DockerHub cache again (cached)"
echo ""
echo "Harbor is working correctly for both:"
echo "  - Local registry (push/pull): ${HARBOR_URL}/library/"
echo "  - DockerHub cache (pull only): ${HARBOR_URL}/dockerhub/"
echo ""
