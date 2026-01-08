#!/bin/bash
# Complete setup script for Harbor encrypted credentials
# This creates the secret and provides instructions for using it

set -e

NAMESPACE="${NAMESPACE:-managed-tools}"
SECRET_NAME="harbor-credentials"

echo "=========================================="
echo "Harbor Credentials Setup"
echo "=========================================="
echo ""

# Run the secret creation script
./scripts/create-harbor-secrets.sh

echo ""
echo "=========================================="
echo "Next Steps:"
echo "=========================================="
echo ""
echo "The secret '${SECRET_NAME}' has been created in namespace '${NAMESPACE}'."
echo ""
echo "To use these credentials with Harbor:"
echo ""
echo "1. The Harbor HelmChart is configured to use empty passwords by default"
echo "2. You need to manually update the HelmChart valuesContent with the passwords"
echo "   OR use a HelmChartConfig to override the values"
echo ""
echo "To get the passwords from the secret:"
echo "  kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o jsonpath='{.data.harborAdminPassword}' | base64 -d"
echo "  kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o jsonpath='{.data.databasePassword}' | base64 -d"
echo ""
echo "⚠️  For production, consider using:"
echo "   - Sealed Secrets (https://github.com/bitnami-labs/sealed-secrets)"
echo "   - External Secrets Operator (https://external-secrets.io/)"
echo "   - SOPS with Age/PGP encryption"
echo ""
