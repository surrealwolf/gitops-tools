# Migration to Official ARC Controller

## Current Status

**✅ Official Controller Deployed:**
- Controller: `gha-runner-scale-set-controller-gha-rs-controller`
- Version: `0.13.1`
- Image: `ghcr.io/actions/gha-runner-scale-set-controller`
- Status: Running

**⚠️ Old Controller Still Running:**
- Controller: `actions-runner-controller` (community version)
- Version: `v0.27.6`
- Image: `summerwind/actions-runner-controller`
- Status: Still managing old RunnerDeployment

**📋 Old Configuration Still Active:**
- RunnerDeployment: `github-runner-deployment`
- Runners: 2 active
- Group: "NRPD Auto Scale"

## Next Steps

### Step 1: Create AutoscalingRunnerSet

Two options:

**Option A: Using HelmChart (Recommended for Fleet)**
- Use `gha-runner-scale-set-helmchart.yaml`
- Fleet will manage via HelmChart resource
- Easier to maintain with Fleet

**Option B: Direct AutoscalingRunnerSet Resource**
- Use `autoscalingrunnerset.yaml`
- Direct CRD deployment
- More explicit control

### Step 2: Authentication Setup

Official ARC requires authentication. Two options:

**Option A: GitHub App (Recommended)**
```bash
# Create GitHub App in organization settings
# Install on organization
# Get App ID, Installation ID, and private key

kubectl create secret generic github-app-secret \
  --from-literal=github_app_id='<APP_ID>' \
  --from-literal=github_app_installation_id='<INSTALLATION_ID>' \
  --from-literal=github_app_private_key='<PRIVATE_KEY>' \
  -n managed-cicd
```

**Option B: Personal Access Token (PAT)**
```bash
# Less secure but simpler
# Create PAT with admin:org scope

kubectl create secret generic github-pat-secret \
  --from-literal=github_token='<TOKEN>' \
  -n managed-cicd
```

### Step 3: Deploy AutoscalingRunnerSet

**If using HelmChart:**
```bash
# Update kustomization.yaml to include helmchart
# Commit and push - Fleet will deploy
```

**If using direct resource:**
```bash
kubectl apply -f autoscalingrunnerset.yaml
```

### Step 4: Verify New Runners

1. Check AutoscalingRunnerSet:
   ```bash
   kubectl --context=nprd-apps get autoscalingrunnerset -n managed-cicd
   ```

2. Check Listeners:
   ```bash
   kubectl --context=nprd-apps get autoscalinglistener -n managed-cicd
   ```

3. Check Ephemeral Runners:
   ```bash
   kubectl --context=nprd-apps get ephemeralrunner -n managed-cicd
   ```

4. Check in GitHub:
   - Go to: https://github.com/organizations/DataKnifeAI/settings/actions/runners
   - Click on "NRPD Auto Scale" group
   - Verify new runners appear (different names)

### Step 5: Test Workflows

1. Trigger a workflow
2. Verify it uses new runners
3. Check runner logs
4. Verify ephemeral runners clean up after job

### Step 6: Remove Old Configuration

Once new runners are working:

1. **Remove RunnerDeployment:**
   ```bash
   kubectl --context=nprd-apps delete runnerdeployment github-runner-deployment -n managed-cicd
   ```

2. **Remove HorizontalRunnerAutoscaler:**
   ```bash
   kubectl --context=nprd-apps delete horizontalrunnerautoscaler github-runner-autoscaler -n managed-cicd
   ```

3. **Wait for old runners to clean up:**
   ```bash
   kubectl --context=nprd-apps get runner -n managed-cicd
   # Wait until all runners are deleted
   ```

4. **(Optional) Remove old controller:**
   ```bash
   # Only if you're sure you don't need it
   kubectl --context=nprd-apps delete helmchart actions-runner-controller -n managed-cicd
   ```

## Key Differences

| Feature | Community (Old) | Official (New) |
|---------|----------------|----------------|
| **CRD** | RunnerDeployment | AutoscalingRunnerSet |
| **Architecture** | Direct pods | Listener + Ephemeral |
| **Labels** | Single label only | Multiple labels supported |
| **Scaling** | HorizontalRunnerAutoscaler | Built-in scaling |
| **Ephemeral** | Optional field | Default behavior |
| **Authentication** | PAT or GitHub App | GitHub App recommended |
| **Runner Groups** | Limited support | Full support |

## Configuration Mapping

**Old (RunnerDeployment):**
```yaml
spec:
  replicas: 1
  template:
    spec:
      organization: DataKnifeAI
      group: NRPD Auto Scale
      labels: [self-hosted]
      ephemeral: true
```

**New (AutoscalingRunnerSet):**
```yaml
spec:
  githubConfigUrl: https://github.com/DataKnifeAI
  runnerGroup: NRPD Auto Scale
  runnerScaleSetName: nprd-autoscale-runners
  minRunners: 2
  maxRunners: 10
  labels: [self-hosted, kubernetes, linux]
  # Ephemeral is default - no need to specify
```

## Benefits of Official ARC

✅ **Better Runner Group Support**: Full support for runner groups
✅ **Multiple Labels**: Can use multiple labels (unlike community version)
✅ **Efficient Scaling**: Ephemeral runners are default and more efficient
✅ **Official Support**: GitHub maintains and supports
✅ **Better Metrics**: Built-in Prometheus metrics
✅ **Future-Proof**: Active development by GitHub

## Troubleshooting

### Runners Not Appearing

1. **Check AutoscalingRunnerSet status:**
   ```bash
   kubectl --context=nprd-apps describe autoscalingrunnerset -n managed-cicd
   ```

2. **Check listener logs:**
   ```bash
   kubectl --context=nprd-apps logs -n managed-cicd -l app.kubernetes.io/name=gha-rs-listener
   ```

3. **Check controller logs:**
   ```bash
   kubectl --context=nprd-apps logs -n actions-runner-system -l app.kubernetes.io/name=gha-rs-controller
   ```

4. **Verify runner group exists:**
   - https://github.com/organizations/DataKnifeAI/settings/actions/runners
   - Ensure "NRPD Auto Scale" group exists

### Authentication Issues

1. **Check secret exists:**
   ```bash
   kubectl --context=nprd-apps get secret github-app-secret -n managed-cicd
   ```

2. **Verify secret keys:**
   ```bash
   kubectl --context=nprd-apps get secret github-app-secret -n managed-cicd -o jsonpath='{.data}' | jq 'keys'
   ```

3. **Check controller logs for auth errors**

## References

- [Official ARC Documentation](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller)
- [Deploy Runner Scale Sets](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/deploy-runner-scale-sets)
- [Quickstart Guide](https://docs.github.com/en/actions/tutorials/quickstart-for-actions-runner-controller)
- [Authentication](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/authenticate-to-the-api)
