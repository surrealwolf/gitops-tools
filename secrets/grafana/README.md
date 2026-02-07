# Grafana Stack Secrets

## Grafana Admin Credentials

The Grafana Helm chart auto-generates admin credentials on first install. No manual secret creation is required.

- **Username**: `admin` (configured in Helm chart)
- **Password**: Auto-generated and stored in the `grafana` secret

To retrieve the admin password:
```bash
kubectl get secret grafana -n grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

## Security Best Practices

1. **Rotate Regularly**: Change passwords periodically via Grafana UI (Admin → Users)
2. **Use Strong Passwords**: If manually changing, use `openssl rand -base64 32`
3. **Consider External Secret Management**: For production, tools like Sealed Secrets or External Secrets Operator can manage credentials
4. **Restrict Access**: Limit who can read secrets in the cluster

## Loki RustFS Credentials

Loki uses RustFS (S3-compatible) for storage. Create the secret before deploying:

```bash
kubectl create secret generic loki-rustfs-credentials \
  --from-literal=accessKeyId='<RUSTFS_ACCESS_KEY>' \
  --from-literal=secretAccessKey='<RUSTFS_SECRET_KEY>' \
  -n grafana
```

The Loki Helm chart reads credentials from this secret via `global.extraEnvFrom` and `-config.expand-env=true`. No credentials in Git. Use Sealed Secrets for GitOps.
