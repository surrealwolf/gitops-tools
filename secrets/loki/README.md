# Loki Stack Secrets

This directory contains example secret configurations for the Loki Stack deployment.

## Required Secrets

### Grafana Admin Password

The Grafana admin password can be configured via a Kubernetes secret. Create the secret before deploying the Loki Stack:

```bash
# Generate a secure password
GRAFANA_PASSWORD=$(openssl rand -base64 32 | tr -d '\n')

# Create the secret
kubectl create secret generic loki-credentials \
  --from-literal=adminPassword="$GRAFANA_PASSWORD" \
  -n grafana
```

Then update the `loki-helmchart.yaml` in the overlay to reference this secret:

```yaml
grafana:
  existingSecret: loki-credentials
  secretKey: adminPassword
```

## Secret Files

- `loki-credentials.yaml.example` - Example Grafana credentials secret

## Usage

1. Copy the example file:
   ```bash
   cp loki-credentials.yaml.example loki-credentials.yaml
   ```

2. Edit the file and set your actual password:
   ```bash
   # Generate password hash (Grafana uses plain text passwords in secrets)
   GRAFANA_PASSWORD=$(openssl rand -base64 32)
   # Edit loki-credentials.yaml and replace the password value
   ```

3. Apply the secret:
   ```bash
   kubectl apply -f loki-credentials.yaml -n managed-syslog
   ```

**Note**: Do NOT commit `loki-credentials.yaml` to Git. It should be in `.gitignore` or managed via external secret management.

## Default Credentials

If no secret is configured, Grafana will use:
- **Username**: `admin` (configured in Helm chart)
- **Password**: Auto-generated (check Grafana pod logs or use `kubectl get secret`)

To retrieve the auto-generated password:
```bash
kubectl get secret loki-stack-grafana -n grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

## Security Best Practices

1. **Use Strong Passwords**: Generate passwords using `openssl rand -base64 32`
2. **Rotate Regularly**: Change passwords periodically
3. **Use External Secret Management**: Consider using tools like:
   - Sealed Secrets
   - External Secrets Operator
   - HashiCorp Vault
4. **Restrict Access**: Limit who can read secrets in the cluster
5. **Monitor Access**: Audit secret access logs
