#!/bin/bash
# Runner Configuration Script
# This script updates GitLab Runner registration token in HelmChartConfig
#
# Usage:
#   ./scripts/runner-config.sh

set -e

NAMESPACE="${NAMESPACE:-managed-cicd}"
SECRET_NAME="${SECRET_NAME:-gitlab-runner-secret}"
HELMCHARTCONFIG_NAME="gitlab-runner"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}Updating GitLab Runner registration token in HelmChartConfig${NC}"
echo "Token will be extracted from Kubernetes secret and applied to cluster only."
echo ""

# Check if secret exists
if ! kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo -e "${RED}Error: Secret '$SECRET_NAME' not found in namespace '$NAMESPACE'${NC}"
    echo ""
    echo "Create the secret first:"
    echo "  ./scripts/runner-setup.sh gitlab"
    exit 1
fi

# Extract token from secret
echo "Extracting token from secret..."
TOKEN=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" \
  -o jsonpath='{.data.runner-registration-token}' | base64 -d)

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
    echo -e "${RED}Error: Failed to extract token from secret${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Token extracted successfully${NC}"
echo ""

# Escape the token for YAML
ESCAPED_TOKEN=$(echo "$TOKEN" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')

# Check if HelmChartConfig exists
if kubectl get helmchartconfig "$HELMCHARTCONFIG_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo "Updating existing HelmChartConfig..."
    TMP_FILE=$(mktemp)
    cat > "$TMP_FILE" <<EOF
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: $HELMCHARTCONFIG_NAME
  namespace: $NAMESPACE
spec:
  valuesContent: |-
    runnerRegistrationToken: "$ESCAPED_TOKEN"
EOF
    kubectl apply -f "$TMP_FILE"
    rm -f "$TMP_FILE"
else
    echo "Creating new HelmChartConfig..."
    cat <<EOF | kubectl apply -f -
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: $HELMCHARTCONFIG_NAME
  namespace: $NAMESPACE
spec:
  valuesContent: |-
    runnerRegistrationToken: "$ESCAPED_TOKEN"
EOF
fi

echo ""
echo -e "${GREEN}✓ HelmChartConfig updated successfully${NC}"
echo ""
echo "✅ Token is now in:"
echo "   - Kubernetes secret: $SECRET_NAME"
echo "   - HelmChartConfig: $HELMCHARTCONFIG_NAME (in cluster only)"
echo ""
echo "❌ Token is NOT in:"
echo "   - Git repository ✅"
echo "   - Any committed files ✅"
echo ""
echo "Fleet will automatically merge the HelmChartConfig with the HelmChart."
echo "The runner should pick up the new token on the next sync."
