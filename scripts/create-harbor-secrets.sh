#!/bin/bash
# Create Harbor credentials secret
# This script prompts for passwords and creates the secret securely

set -e

NAMESPACE="${NAMESPACE:-managed-tools}"
SECRET_NAME="harbor-credentials"

echo "Creating Harbor credentials secret..."
echo ""

# Create namespace if it doesn't exist
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Prompt for Harbor admin password
read -sp "Enter Harbor admin password (default: Harbor12345): " HARBOR_PASSWORD
HARBOR_PASSWORD="${HARBOR_PASSWORD:-Harbor12345}"
echo ""

# Prompt for database password
read -sp "Enter database password (default: root123): " DB_PASSWORD
DB_PASSWORD="${DB_PASSWORD:-root123}"
echo ""

# Prompt for Redis password (optional)
read -sp "Enter Redis password (optional, press Enter for empty): " REDIS_PASSWORD
REDIS_PASSWORD="${REDIS_PASSWORD:-}"
echo ""

# Create the secret
kubectl create secret generic "${SECRET_NAME}" \
  --from-literal=harborAdminPassword="${HARBOR_PASSWORD}" \
  --from-literal=databasePassword="${DB_PASSWORD}" \
  --from-literal=redisPassword="${REDIS_PASSWORD}" \
  -n "${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✓ Harbor credentials secret '${SECRET_NAME}' created/updated in namespace '${NAMESPACE}'"
echo ""
echo "⚠️  Remember to change these passwords in production!"
