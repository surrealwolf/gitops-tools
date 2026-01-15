#!/bin/bash
# Generate OpenSearch TLS certificates with correct hostnames for Graylog
# This script generates certificates that include the service hostname and pod hostnames

set -e

CERT_DIR="${CERT_DIR:-./certs/opensearch}"
NAMESPACE="${NAMESPACE:-managed-graylog}"
CLUSTER_NAME="${CLUSTER_NAME:-graylog-opensearch}"
SERVICE_HOSTNAME="${CLUSTER_NAME}"
FULL_SERVICE_HOSTNAME="${SERVICE_HOSTNAME}.${NAMESPACE}.svc.cluster.local"

# Hostnames to include in certificate
HOSTNAMES=(
  "${SERVICE_HOSTNAME}"
  "${FULL_SERVICE_HOSTNAME}"
  "${SERVICE_HOSTNAME}.${NAMESPACE}.svc"
  "${CLUSTER_NAME}-masters-0"
  "${CLUSTER_NAME}-masters-0.${NAMESPACE}.svc.cluster.local"
  "${CLUSTER_NAME}-data-0"
  "${CLUSTER_NAME}-data-0.${NAMESPACE}.svc.cluster.local"
  "localhost"
  "127.0.0.1"
)

echo "Generating OpenSearch TLS certificates for ${CLUSTER_NAME}..."
echo "Hostnames: ${HOSTNAMES[*]}"
echo ""

# Create cert directory
mkdir -p "${CERT_DIR}"

# Generate CA private key
echo "Generating CA private key..."
openssl genrsa -out "${CERT_DIR}/root-ca.key" 4096

# Generate CA certificate (valid for 10 years)
echo "Generating CA certificate..."
openssl req -new -x509 -days 3650 -key "${CERT_DIR}/root-ca.key" \
  -out "${CERT_DIR}/root-ca.pem" \
  -subj "/CN=OpenSearch-Root-CA/O=Graylog/L=Internal/ST=Internal/C=US"

# Generate node private key
echo "Generating node private key..."
openssl genrsa -out "${CERT_DIR}/esnode-key.pem" 2048

# Create certificate signing request
echo "Generating certificate signing request..."
# Build SAN list
SAN_LIST=""
for hostname in "${HOSTNAMES[@]}"; do
  if [ -z "$SAN_LIST" ]; then
    SAN_LIST="DNS:${hostname}"
  else
    SAN_LIST="${SAN_LIST},DNS:${hostname}"
  fi
done
# Add IP addresses
SAN_LIST="${SAN_LIST},IP:127.0.0.1,IP:::1"

openssl req -new -key "${CERT_DIR}/esnode-key.pem" \
  -out "${CERT_DIR}/esnode.csr" \
  -subj "/CN=${SERVICE_HOSTNAME}/OU=OpenSearch/O=Graylog/L=Internal/ST=Internal/C=US" \
  -addext "subjectAltName=${SAN_LIST}"

# Generate node certificate signed by CA (valid for 10 years)
echo "Generating node certificate..."
openssl x509 -req -days 3650 \
  -in "${CERT_DIR}/esnode.csr" \
  -CA "${CERT_DIR}/root-ca.pem" \
  -CAkey "${CERT_DIR}/root-ca.key" \
  -CAcreateserial \
  -out "${CERT_DIR}/esnode.pem" \
  -extensions v3_req \
  -extfile <(
    echo "[v3_req]"
    echo "subjectAltName=${SAN_LIST}"
    echo "keyUsage=digitalSignature,keyEncipherment"
    echo "extendedKeyUsage=serverAuth,clientAuth"
  )

# Clean up CSR
rm -f "${CERT_DIR}/esnode.csr"

# Generate admin private key (for securityadmin.sh)
echo "Generating admin private key..."
openssl genrsa -out "${CERT_DIR}/admin-key-temp.pem" 2048

# Convert admin key to PKCS8 format (required by securityadmin.sh)
# Per OpenSearch docs: https://docs.opensearch.org/latest/security/configuration/generate-certificates/
echo "Converting admin key to PKCS8 format..."
openssl pkcs8 -inform PEM -outform PEM -in "${CERT_DIR}/admin-key-temp.pem" \
  -topk8 -nocrypt -v1 PBE-SHA1-3DES \
  -out "${CERT_DIR}/admin-key.pem"

# Generate admin certificate signing request
echo "Generating admin certificate signing request..."
openssl req -new -key "${CERT_DIR}/admin-key.pem" \
  -out "${CERT_DIR}/admin.csr" \
  -subj "/CN=graylog-opensearch-admin/OU=OpenSearch/O=Graylog/L=Internal/ST=Internal/C=US"

# Generate admin certificate signed by CA (valid for 10 years)
echo "Generating admin certificate..."
openssl x509 -req -days 3650 \
  -in "${CERT_DIR}/admin.csr" \
  -CA "${CERT_DIR}/root-ca.pem" \
  -CAkey "${CERT_DIR}/root-ca.key" \
  -CAcreateserial \
  -sha256 \
  -out "${CERT_DIR}/admin.pem"

# Clean up temp files
rm -f "${CERT_DIR}/admin-key-temp.pem"
rm -f "${CERT_DIR}/admin.csr"

echo ""
echo "✓ Certificates generated successfully!"
echo ""
echo "Certificate files:"
echo "  CA Certificate: ${CERT_DIR}/root-ca.pem"
echo "  CA Key: ${CERT_DIR}/root-ca.key"
echo "  Node Certificate: ${CERT_DIR}/esnode.pem"
echo "  Node Key: ${CERT_DIR}/esnode-key.pem"
echo "  Admin Certificate: ${CERT_DIR}/admin.pem"
echo "  Admin Key (PKCS8): ${CERT_DIR}/admin-key.pem"
echo ""

# Verify certificate
echo "Certificate details:"
openssl x509 -in "${CERT_DIR}/esnode.pem" -text -noout | grep -A 5 "Subject Alternative Name"

echo ""
echo "Creating Kubernetes secrets..."

# Create namespace if it doesn't exist
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Create HTTP TLS secret (certificate and key)
echo "Creating HTTP TLS secret..."
kubectl create secret generic "${CLUSTER_NAME}-http-certs" \
  --from-file=tls.crt="${CERT_DIR}/esnode.pem" \
  --from-file=tls.key="${CERT_DIR}/esnode-key.pem" \
  --from-file=ca.crt="${CERT_DIR}/root-ca.pem" \
  -n "${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Create Transport TLS secret (certificate and key)
echo "Creating Transport TLS secret..."
kubectl create secret generic "${CLUSTER_NAME}-transport-certs" \
  --from-file=tls.crt="${CERT_DIR}/esnode.pem" \
  --from-file=tls.key="${CERT_DIR}/esnode-key.pem" \
  --from-file=ca.crt="${CERT_DIR}/root-ca.pem" \
  -n "${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Create CA secret
echo "Creating CA secret..."
kubectl create secret generic "${CLUSTER_NAME}-ca" \
  --from-file=ca.crt="${CERT_DIR}/root-ca.pem" \
  -n "${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

# Create Admin certificate secret (for securityadmin.sh)
echo "Creating Admin certificate secret..."
kubectl create secret generic "${CLUSTER_NAME}-admin-certs" \
  --from-file=admin.pem="${CERT_DIR}/admin.pem" \
  --from-file=admin-key.pem="${CERT_DIR}/admin-key.pem" \
  --from-file=ca.crt="${CERT_DIR}/root-ca.pem" \
  -n "${NAMESPACE}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✓ Kubernetes secrets created/updated in namespace '${NAMESPACE}'"
echo ""
echo "Secrets:"
echo "  - ${CLUSTER_NAME}-http-certs"
echo "  - ${CLUSTER_NAME}-transport-certs"
echo "  - ${CLUSTER_NAME}-ca"
echo "  - ${CLUSTER_NAME}-admin-certs (for securityadmin.sh)"
echo ""
echo "Next steps:"
echo "  1. Update opensearch-cluster.yaml to use custom certificates:"
echo "     security.tls.http.generate: false"
echo "     security.tls.http.secret.name: ${CLUSTER_NAME}-http-certs"
echo "     security.tls.http.caSecret.name: ${CLUSTER_NAME}-ca"
echo "     security.tls.transport.generate: false"
echo "     security.tls.transport.secret.name: ${CLUSTER_NAME}-transport-certs"
echo "     security.tls.transport.caSecret.name: ${CLUSTER_NAME}-ca"
