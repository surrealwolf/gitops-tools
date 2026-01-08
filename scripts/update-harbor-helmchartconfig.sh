#!/bin/bash
# Update Harbor HelmChartConfig with passwords from secret
# This allows Harbor to deploy with actual passwords

set -e

NAMESPACE="${NAMESPACE:-managed-tools}"
SECRET_NAME="harbor-credentials"
CONFIG_FILE="harbor/base/harbor-helmchartconfig.yaml"

echo "Updating Harbor HelmChartConfig with passwords from secret..."

# Check if secret exists
if ! kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
    echo "Error: Secret '${SECRET_NAME}' not found in namespace '${NAMESPACE}'"
    echo "Please create it first using: ./scripts/create-harbor-secrets.sh"
    exit 1
fi

# Extract passwords from secret
HARBOR_PASSWORD=$(kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.harborAdminPassword}' | base64 -d)
DB_PASSWORD=$(kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" -o jsonpath='{.data.databasePassword}' | base64 -d)

# Create temporary file with updated values
TMP_FILE=$(mktemp)
cat > "${TMP_FILE}" << EOF
apiVersion: helm.cattle.io/v1
kind: HelmChartConfig
metadata:
  name: harbor
  namespace: managed-tools
spec:
  valuesContent: |-
    # Passwords from harbor-credentials secret
    harborAdminPassword: "${HARBOR_PASSWORD}"
    database:
      internal:
        password: "${DB_PASSWORD}"
EOF

# Update the config file
mv "${TMP_FILE}" "${CONFIG_FILE}"

echo ""
echo "✓ Updated ${CONFIG_FILE} with passwords from secret"
echo ""
echo "⚠️  Note: This file now contains passwords in plaintext."
echo "   It should be gitignored or use Sealed Secrets for production."
echo ""
echo "To apply:"
echo "  kubectl apply -f ${CONFIG_FILE}"
echo ""
