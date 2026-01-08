#!/bin/bash
# Generate self-signed wildcard certificate for *.dataknife.net
# This certificate can be used cluster-wide for internal services

set -e

CERT_DIR="${CERT_DIR:-./certs}"
DOMAIN="dataknife.net"
WILDCARD="*.${DOMAIN}"
SECRET_NAME="wildcard-dataknife-net-tls"
NAMESPACE="${NAMESPACE:-managed-tools}"

echo "Generating wildcard certificate for ${WILDCARD}..."

# Create certs directory if it doesn't exist
mkdir -p "${CERT_DIR}"

# Generate private key
openssl genrsa -out "${CERT_DIR}/wildcard-dataknife-net.key" 2048

# Generate certificate signing request
openssl req -new -key "${CERT_DIR}/wildcard-dataknife-net.key" \
  -out "${CERT_DIR}/wildcard-dataknife-net.csr" \
  -subj "/CN=${WILDCARD}/O=Dataknife Internal/L=Internal/ST=Internal/C=US" \
  -addext "subjectAltName=DNS:${WILDCARD},DNS:${DOMAIN},DNS:*.${DOMAIN}"

# Generate self-signed certificate (valid for 10 years)
openssl x509 -req -days 3650 \
  -in "${CERT_DIR}/wildcard-dataknife-net.csr" \
  -signkey "${CERT_DIR}/wildcard-dataknife-net.key" \
  -out "${CERT_DIR}/wildcard-dataknife-net.crt" \
  -extensions v3_req \
  -extfile <(
    echo "[v3_req]"
    echo "subjectAltName=DNS:${WILDCARD},DNS:${DOMAIN},DNS:*.${DOMAIN}"
  )

echo ""
echo "✓ Certificate generated successfully!"
echo ""
echo "Certificate files:"
echo "  Private Key: ${CERT_DIR}/wildcard-dataknife-net.key"
echo "  Certificate: ${CERT_DIR}/wildcard-dataknife-net.crt"
echo ""

# Create Kubernetes secret
echo "Creating Kubernetes secret '${SECRET_NAME}' in namespace '${NAMESPACE}'..."

# Create namespace if it doesn't exist
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Create or update the TLS secret
kubectl create secret tls "${SECRET_NAME}" \
  --cert="${CERT_DIR}/wildcard-dataknife-net.crt" \
  --key="${CERT_DIR}/wildcard-dataknife-net.key" \
  -n "${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✓ Kubernetes secret '${SECRET_NAME}' created/updated in namespace '${NAMESPACE}'"
echo ""
echo "To use this certificate in other namespaces, copy the secret:"
echo "  kubectl get secret ${SECRET_NAME} -n ${NAMESPACE} -o yaml | \\"
echo "    sed 's/namespace: ${NAMESPACE}/namespace: <target-namespace>/' | \\"
echo "    kubectl apply -f -"
echo ""
echo "Or create it cluster-wide by applying to each namespace as needed."
echo ""
