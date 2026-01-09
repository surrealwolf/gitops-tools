# Terraform Integration for GitHub Runner Controller

## Overview

This repository manages **only runner definitions** (AutoscalingRunnerSet), not the controller itself. The GitHub Actions Runner Controller (`gha-runner-scale-set-controller`) is managed by a separate Terraform project.

## Responsibilities

### This Repository (GitOps)
- ✅ Manages runner definitions (`AutoscalingRunnerSet`)
- ✅ Configures runner scale sets (min/max runners, labels, resources)
- ✅ Defines runner groups and organization/repository associations
- ✅ Manages runner pod templates and resources

### Terraform Project
- ✅ Manages controller deployment (`gha-runner-scale-set-controller`)
- ✅ Creates and manages authentication secrets
- ✅ Manages controller RBAC and service accounts
- ✅ Handles controller configuration and updates

## Secret Configuration

The `AutoscalingRunnerSet` requires a `githubConfigSecret` field that references a Kubernetes secret containing GitHub authentication credentials.

### Secret Name

The secret name must match what the Terraform project creates. Common names:
- `github-app-secret` (for GitHub App authentication)
- `github-token-secret` (for PAT authentication)
- Custom name configured in Terraform

**Action Required**: Verify the secret name in your Terraform project and update `autoscalingrunnerset.yaml` if different:

```yaml
spec:
  githubConfigSecret: <SECRET_NAME_FROM_TERRAFORM>
```

### Secret Location

The secret must exist in the same namespace as the AutoscalingRunnerSet:
- Namespace: `managed-cicd`
- Secret: Must exist before AutoscalingRunnerSet is deployed

### Secret Contents

**For GitHub App (Recommended):**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: github-app-secret
  namespace: managed-cicd
type: Opaque
data:
  github_app_id: <base64-encoded-app-id>
  github_app_installation_id: <base64-encoded-installation-id>
  github_app_private_key: <base64-encoded-private-key>
```

**For Personal Access Token:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: github-token-secret
  namespace: managed-cicd
type: Opaque
data:
  github_token: <base64-encoded-token>
```

## Current Configuration

**AutoscalingRunnerSet** (`github-runner/overlays/nprd-apps/autoscalingrunnerset.yaml`):
- `githubConfigSecret: github-app-secret` (TODO: Verify with Terraform)
- `githubConfigUrl: https://github.com/DataKnifeAI`
- `runnerGroup: NRPD Auto Scale`
- `minRunners: 2`
- `maxRunners: 10`

## Verification

### Check if Secret Exists

```bash
# List secrets in managed-cicd namespace
kubectl --context=nprd-apps get secret -n managed-cicd | grep -i github

# Check specific secret (if you know the name)
kubectl --context=nprd-apps get secret github-app-secret -n managed-cicd
```

### Verify Secret Name in AutoscalingRunnerSet

```bash
# Check current configuration
kubectl --context=nprd-apps get autoscalingrunnerset github-runner-scale-set -n managed-cicd -o yaml | grep githubConfigSecret
```

### Verify Secret is Used Correctly

```bash
# Check AutoscalingRunnerSet status
kubectl --context=nprd-apps describe autoscalingrunnerset github-runner-scale-set -n managed-cicd

# Check for authentication errors in listener logs
kubectl --context=nprd-apps logs -n managed-cicd -l app.kubernetes.io/name=gha-rs-listener | grep -i "auth\|secret\|error"
```

## Troubleshooting

### Secret Not Found

If AutoscalingRunnerSet fails with "secret not found" error:

1. **Verify secret exists:**
   ```bash
   kubectl --context=nprd-apps get secret -n managed-cicd
   ```

2. **Check Terraform output** for secret name:
   ```bash
   # In Terraform project
   terraform output -json | jq '.github_secret_name'
   ```

3. **Update AutoscalingRunnerSet** to use correct secret name:
   ```yaml
   spec:
     githubConfigSecret: <ACTUAL_SECRET_NAME>
   ```

### Authentication Errors

If runners fail to authenticate:

1. **Verify secret contents** (if you have access):
   ```bash
   kubectl --context=nprd-apps get secret github-app-secret -n managed-cicd -o yaml
   ```

2. **Check listener logs** for authentication errors:
   ```bash
   kubectl --context=nprd-apps logs -n managed-cicd -l app.kubernetes.io/name=gha-rs-listener --tail=100
   ```

3. **Contact Terraform project maintainers** to verify:
   - Secret name is correct
   - Secret contains required fields
   - Secret is in the correct namespace

## Integration Points

### Terraform Outputs

The Terraform project should provide outputs that this repository can reference:
- Secret name
- Namespace
- Controller version/deployment info

### GitOps Workflow

1. **Terraform deploys controller and secrets**
2. **This repository deploys AutoscalingRunnerSet** (via Fleet)
3. **Controller watches AutoscalingRunnerSet** and creates listeners/runners
4. **Runners register with GitHub** using credentials from secret

## Best Practices

1. **Secret Management**: Secrets should be created by Terraform, not this repository
2. **Namespace Consistency**: Ensure secrets are in the same namespace as AutoscalingRunnerSet
3. **Secret Naming**: Use consistent naming between Terraform and GitOps
4. **Documentation**: Document secret names and locations in both projects
5. **Validation**: Verify secret exists before deploying AutoscalingRunnerSet

## References

- [Official ARC Documentation](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller)
- [Authentication Guide](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/authenticate-to-the-api)
- [AutoscalingRunnerSet Spec](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/deploy-runner-scale-sets)

