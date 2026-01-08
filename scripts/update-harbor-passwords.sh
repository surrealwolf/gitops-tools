#!/bin/bash
# Update Harbor HelmChart with passwords from secret
# This script extracts passwords from the secret and updates the HelmChartConfig

set -e

NAMESPACE="${NAMESPACE:-managed-tools}"
SECRET_NAME="harbor-credentials"
HELMCHARTCONFIG="harbor/base/harbor-helmchartconfig.yaml"

echo "Updating Harbor passwords from secret..."

# Check if secret exists
if ! kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "Error: Secret '${SECRET_NAME}' not found in namespace '${NAMESPACE}'"
    echo "Please create it first using: ./scripts/create-harbor-secrets.sh"
    exit 1
fi

# Extract passwords from secret
HARBOR_PASSWORD=$(kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.harborAdminPassword}' | base64 -d)
DB_PASSWORD=$(kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.databasePassword}' | base64 -d)

# Update HelmChartConfig (this is a manual step - you'll need to apply it)
echo ""
echo "Passwords extracted from secret. Update ${HELMCHARTCONFIG} with:"
echo ""
echo "  harborAdminPassword: \"${HARBOR_PASSWORD}\""
echo "  database:"
echo "    internal:"
echo "      password: \"${DB_PASSWORD}\""
echo ""
echo "⚠️  Note: For security, consider using Sealed Secrets or External Secrets Operator"
echo "   to encrypt secrets in Git instead of storing them in plain HelmChartConfig"
echo ""
