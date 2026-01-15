# Graylog Secrets

This directory contains example secret templates for Graylog deployment.

## Secret Files

- `graylog-credentials.yaml.example` - Template for Graylog credentials

## Required Secrets

### graylog-credentials

Contains:
- `mongodb-password`: Password for MongoDB 'graylog' user
- `password-secret`: Graylog password encryption secret
- `root-password-sha2`: SHA2 hash of Graylog root user password

### graylog-opensearch-admin-password

**IMPORTANT**: This secret requires both `username` and `password` fields. The OpenSearch operator will fail with "username or password field missing" if only `password` is provided.

Contains:
- `username`: OpenSearch admin username (typically `admin`)
- `password`: OpenSearch admin password (random secure password)

**Create the secret:**
```bash
# Generate a secure password
OPENSEARCH_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')

# Create secret with both username and password
kubectl create secret generic graylog-opensearch-admin-password \
  --from-literal=username=admin \
  --from-literal=password="$OPENSEARCH_PASSWORD" \
  -n managed-graylog
```

**Verify the secret:**
```bash
kubectl get secret graylog-opensearch-admin-password -n managed-graylog -o jsonpath='{.data}' | jq 'keys'
# Should show: ["password", "username"]
```

### graylog-opensearch-admin-certs

**IMPORTANT**: This secret is automatically created by `scripts/generate-opensearch-certs.sh`. Do not create manually.

Contains:
- `admin.pem`: Admin certificate for securityadmin.sh
- `admin-key.pem`: Admin private key in PKCS8 format (required by securityadmin.sh)
- `ca.crt`: Root CA certificate

**Purpose**: Used by the OpenSearch security initialization job to run `securityadmin.sh` and create the `.opendistro_security` index.

**Regenerate if needed:**
```bash
cd /home/lee/git/gitops-tools
bash scripts/generate-opensearch-certs.sh
```

**Reference**: [OpenSearch Certificate Generation Documentation](https://docs.opensearch.org/latest/security/configuration/generate-certificates/)

## Setup Instructions

1. **Copy the example file:**
   ```bash
   cp secrets/graylog/graylog-credentials.yaml.example secrets/graylog/graylog-credentials.yaml
   ```

2. **Generate secure values:**
   ```bash
   # MongoDB password (32 bytes base64)
   openssl rand -base64 32
   
   # Graylog password secret (64 bytes base64)
   openssl rand -base64 64
   
   # Root password SHA2 hash
   echo -n "your-strong-password" | shasum -a 256 | cut -d' ' -f1
   # Example: echo -n "GN10hTf6YKtjF8cG" | shasum -a 256 | cut -d' ' -f1
   # Result: ddd6795c071cc1695410368d1221ddf508cc8543f1a8abfd6d7056a171395ea4
   ```

3. **Edit the secret file:**
   - Open `secrets/graylog/graylog-credentials.yaml`
   - Replace `CHANGE_ME` with your generated values
   - Update `root-password-sha2` with your password hash

4. **Apply the secret:**
   ```bash
   kubectl apply -f secrets/graylog/graylog-credentials.yaml
   ```

5. **Verify the secret exists:**
   ```bash
   kubectl get secret graylog-credentials -n managed-graylog
   ```

## Security Notes

- **NEVER** commit the actual `graylog-credentials.yaml` file to git
- Use `.gitignore` to ensure secrets are not accidentally committed
- Rotate secrets periodically
- Use strong, randomly generated passwords
- Store production secrets in a secure secret management system (e.g., Sealed Secrets, External Secrets Operator)

## Updating MongoDB Password

If you need to change the MongoDB password:

1. Update the secret:
   ```bash
   kubectl edit secret graylog-credentials -n managed-graylog
   # Update mongodb-password in stringData
   ```

2. Restart Graylog pods to pick up the new password:
   ```bash
   kubectl rollout restart statefulset graylog -n managed-graylog
   ```

## Rotating Credentials

To rotate credentials:

1. Generate new values for each credential
2. Update the secret in Kubernetes
3. Restart affected pods (Graylog StatefulSet)
4. Verify pods start successfully with new credentials
