# Harbor Deployment

This directory contains the base Harbor deployment configuration using Helm charts.

## TLS Certificate Setup

Since `harbor.dataknife.net` is only available internally, Let's Encrypt cannot be used. You need to create a TLS secret manually.

### Option 1: Self-Signed Certificate (Quick Setup)

```bash
# Generate self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout harbor.key \
  -out harbor.crt \
  -subj "/CN=harbor.dataknife.net" \
  -addext "subjectAltName=DNS:harbor.dataknife.net,DNS:notary.harbor.dataknife.net"

# Create the TLS secret in the managed-tools namespace
kubectl create namespace managed-tools --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret tls harbor-tls \
  --cert=harbor.crt \
  --key=harbor.key \
  -n managed-tools
```

### Option 2: Internal CA Certificate (Recommended for Production)

If you have an internal CA:

```bash
# Generate certificate signing request
openssl req -new -newkey rsa:2048 -nodes \
  -keyout harbor.key \
  -out harbor.csr \
  -subj "/CN=harbor.dataknife.net" \
  -addext "subjectAltName=DNS:harbor.dataknife.net,DNS:notary.harbor.dataknife.net"

# Sign with your internal CA (adjust paths as needed)
openssl x509 -req -in harbor.csr \
  -CA /path/to/ca.crt \
  -CAkey /path/to/ca.key \
  -CAcreateserial \
  -out harbor.crt \
  -days 365

# Create the TLS secret
kubectl create namespace managed-tools --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret tls harbor-tls \
  --cert=harbor.crt \
  --key=harbor.key \
  -n managed-tools
```

### Option 3: Use Existing Certificate

If you already have a certificate and key:

```bash
kubectl create namespace managed-tools --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret tls harbor-tls \
  --cert=/path/to/your/cert.crt \
  --key=/path/to/your/cert.key \
  -n managed-tools
```

## Important Notes

- The TLS secret must be created **before** Harbor is deployed
- The secret name must be exactly `harbor-tls` as specified in the HelmChart configuration
- The certificate must include Subject Alternative Names (SAN) for both:
  - `harbor.dataknife.net`
  - `notary.harbor.dataknife.net`
- For self-signed certificates, clients will need to trust the certificate or CA

## Default Credentials

**⚠️ CHANGE THESE IN PRODUCTION!**

- Harbor Admin Username: `admin`
- Harbor Admin Password: `Harbor12345` (set in `harbor-helmchart.yaml`)

## Deployment

The Harbor HelmChart will be deployed automatically by Fleet when:
1. The namespace `managed-tools` exists
2. The TLS secret `harbor-tls` exists
3. Fleet syncs the GitRepo

Monitor deployment:
```bash
kubectl get helmchart -n managed-tools
kubectl get pods -n managed-tools
kubectl get ingress -n managed-tools
```
