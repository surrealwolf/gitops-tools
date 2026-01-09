# Deployment Guide

This guide walks you through deploying Harbor, GitHub, and GitLab runners to your cluster.

## Prerequisites

1. **Kubernetes cluster** with:
   - `kubectl` configured and accessible
   - Rancher Fleet or another GitOps operator installed
   - RBAC enabled
   - Sufficient resources for runners

2. **GitHub Access** (for GitHub Runner):
   - GitHub Personal Access Token (PAT) with `repo` scope, OR
   - GitHub App credentials

3. **GitLab Access** (for GitLab Runner):
   - GitLab instance URL
   - Runner registration token

## Quick Start

### Step 1: Get Tokens

**GitHub Token:**
1. Go to: https://github.com/settings/tokens
2. Create token with `repo` and `admin:org` scopes
3. Copy the token

**GitLab Token:**
1. Go to your GitLab RaaS group
2. Settings → CI/CD → Runners
3. Copy the group runner registration token

### Step 2: Create Secrets

Run the setup script:

```bash
# Interactive mode
./scripts/runner-setup.sh

# OR non-interactive mode
GITHUB_TOKEN=<token> GITLAB_TOKEN=<token> GITLAB_URL=<url> ./scripts/runner-setup.sh all
```

### Step 3: Update Configuration

1. **GitHub Runner**: Edit `github-runner/base/runnerdeployment.yaml`
   - Replace `<YOUR_GITHUB_ORG>` with your organization name

2. **GitLab Runner**: Edit `gitlab-runner/base/gitlab-runner-helmchart.yaml`
   - Set `gitlabUrl` to your GitLab instance URL
   - Use `./scripts/runner-config.sh` to update token via HelmChartConfig

### Step 4: Commit and Push

```bash
git add .
git commit -m "feat: configure runners"
git push
```

Fleet will automatically deploy!

## Detailed Deployment Steps

### Step 1: Create Required Namespaces

```bash
# Create managed-cicd namespace (if it doesn't exist)
kubectl create namespace managed-cicd --dry-run=client -o yaml | kubectl apply -f -

# The actions-runner-system namespace will be created by Helm
```

### Step 2: Create GitHub Authentication Secret

**Option A: Using the script (Recommended)**

```bash
./scripts/runner-setup.sh github
```

**Option B: Manual creation**

```bash
# Create namespace
kubectl create namespace actions-runner-system

# Create secret with PAT
kubectl create secret generic actions-runner-controller \
  --from-literal=github_token='<YOUR_GITHUB_PAT>' \
  -n actions-runner-system
```

### Step 3: Create GitLab Runner Token Secret

**Option A: Using the script (Recommended)**

```bash
./scripts/runner-setup.sh gitlab
```

**Option B: Manual creation**

```bash
kubectl create secret generic gitlab-runner-secret \
  --from-literal=runner-registration-token='<YOUR_GITLAB_RUNNER_TOKEN>' \
  -n managed-cicd
```

### Step 4: Update Configuration Files

**GitHub Runner:**

1. Edit `github-runner/base/runnerdeployment.yaml`:
   - Update `repository: <YOUR_GITHUB_ORG>/<YOUR_REPO>`
   - Or change to `organization: <YOUR_GITHUB_ORG>` for org-level runners

2. (Optional) Adjust autoscaling in `github-runner/base/horizontalrunnerautoscaler.yaml`:
   - `minReplicas`: Minimum number of runners (default: 1)
   - `maxReplicas`: Maximum number of runners (default: 10)
   - `scaleUpThreshold`: When to scale up (default: 0.75 = 75% busy)
   - `scaleDownThreshold`: When to scale down (default: 0.25 = 25% busy)

**GitLab Runner:**

1. Edit `gitlab-runner/base/gitlab-runner-helmchart.yaml`:
   - Update `gitlabUrl: https://gitlab.com` (or your GitLab instance URL)

2. Update token via HelmChartConfig (recommended - token never goes to git):
   ```bash
   ./scripts/runner-config.sh
   ```

3. (Optional) Adjust `concurrent` setting for more parallel jobs:
   - Current: `concurrent: 4` (4 parallel jobs)
   - Increase for more capacity (e.g., `concurrent: 10`)

### Step 5: Configure Fleet GitRepo

Ensure your Fleet GitRepo is monitoring the appropriate paths:

```yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: gitops-tools
  namespace: fleet-default
spec:
  repo: <YOUR_REPO_URL>
  branch: main
  paths:
    - github-runner/overlays/nprd-apps
    - gitlab-runner/overlays/nprd-apps
    - harbor/overlays/nprd-apps
```

### Step 6: Update Fleet Cluster Targeting

Edit the `fleet.yaml` files in the overlay directories to match your cluster labels:

```bash
# Find your cluster labels
kubectl get clusters.management.cattle.io -o yaml | grep -A 10 labels

# Update fleet.yaml files:
# - github-runner/overlays/nprd-apps/fleet.yaml
# - gitlab-runner/overlays/nprd-apps/fleet.yaml
# - harbor/overlays/nprd-apps/fleet.yaml
```

Uncomment and set the appropriate label, for example:
```yaml
targetCustomizations:
  - name: nprd-apps
    clusterSelector:
      matchLabels:
        managed.cattle.io/cluster-name: nprd-apps
```

### Step 7: Commit and Push Changes

```bash
# Commit your configuration changes
git add .
git commit -m "feat: configure runners and Harbor for deployment"
git push
```

### Step 8: Monitor Deployment

**Check Fleet Status:**

```bash
# Check GitRepo sync status
kubectl get gitrepo -n fleet-default
kubectl describe gitrepo <your-gitrepo-name> -n fleet-default

# Check Bundle status
kubectl get bundle -n fleet-default
kubectl describe bundle <bundle-name> -n fleet-default
```

**Check GitHub Runner Controller:**

```bash
# Check controller pod
kubectl get pods -n actions-runner-system
kubectl logs -n actions-runner-system -l app=actions-runner-controller

# Check RunnerDeployment
kubectl get runnerdeployment -n managed-cicd
kubectl describe runnerdeployment github-runner-deployment -n managed-cicd

# Check runner pods
kubectl get pods -n managed-cicd -l runner-deployment-name=github-runner-deployment
```

**Check GitLab Runner:**

```bash
# Check runner pod
kubectl get pods -n managed-cicd -l app=gitlab-runner
kubectl logs -n managed-cicd -l app=gitlab-runner

# Check HelmChart
kubectl get helmchart -n managed-cicd
kubectl describe helmchart gitlab-runner -n managed-cicd
```

### Step 9: Verify Runners are Active

**GitHub Runner:**

1. Go to your GitHub repository
2. Navigate to **Settings** → **Actions** → **Runners**
3. Verify runners appear with status "Online"
4. Check that autoscaling is working by triggering a workflow

**GitLab Runner:**

1. Go to your GitLab project/group/instance
2. Navigate to **Settings** → **CI/CD** → **Runners**
3. Verify runner appears with green circle (active)
4. Test by running a CI/CD pipeline

## Token Setup Details

### GitHub Organization Runner Token

For organization-level runners, you need a GitHub Personal Access Token (PAT) or GitHub App.

**Option 1: Personal Access Token (Recommended for quick setup)**

1. Go to GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
2. Click "Generate new token (classic)"
3. Give it a name (e.g., "Kubernetes Runner Controller")
4. Select scopes:
   - ✅ `repo` (Full control of private repositories)
   - ✅ `admin:org` (if managing organization runners)
5. Click "Generate token"
6. **Copy the token immediately** (you won't see it again)

**Option 2: GitHub App (Recommended for organizations)**

1. Go to your organization → Settings → Developer settings → GitHub Apps
2. Click "New GitHub App"
3. Configure:
   - Name: "Kubernetes Runner Controller"
   - Homepage URL: Your organization URL
   - Permissions:
     - Actions: Read and write
     - Metadata: Read-only
4. Generate a private key
5. Install the app on your organization
6. Note the App ID, Installation ID, and save the private key

### GitLab Group Runner Token (RaaS Group)

1. Go to your GitLab instance
2. Navigate to the **RaaS** group
3. Go to **Settings** → **CI/CD**
4. Expand **Runners** section
5. Under **Group runners**, find the registration token
6. Copy the token

**Note:** If you don't see group runners, you may need to:
- Ensure you have Maintainer/Owner permissions on the group
- Or use an instance-level runner token from Admin Area

## GitHub Organization Setup

### Option 1: Create New DataKnife Organization (Recommended)

**Pros:**
- Keeps personal account separate
- Better aligns with your domain (dataknife.net)
- More professional setup
- Can transfer repos as needed

**Steps:**
1. Go to https://github.com/organizations/new
2. Choose organization name: `DataKnife` or `dataknife`
3. Choose plan (Free tier works for most cases)
4. Create organization
5. Transfer repositories from personal account to `DataKnife` (optional)
6. Update runner configuration to use `DataKnife` organization

### Option 2: Convert Personal Account to Organization

**Pros:**
- Keeps existing repositories in place
- No need to transfer repos

**Cons:**
- **Irreversible** - cannot convert back to personal account
- Requires creating a new personal account first
- Some personal data won't transfer (SSH keys, OAuth tokens, etc.)

## Troubleshooting

### GitHub Runner Issues

**Controller not starting:**
```bash
# Check secret exists
kubectl get secret actions-runner-controller -n actions-runner-system

# Check controller logs
kubectl logs -n actions-runner-system -l app=actions-runner-controller
```

**Runners not appearing:**
```bash
# Check RunnerDeployment status
kubectl describe runnerdeployment github-runner-deployment -n managed-cicd

# Check autoscaler status
kubectl describe horizontalrunnerautoscaler github-runner-autoscaler -n managed-cicd

# Check for runner pods
kubectl get pods -n managed-cicd -l runner-deployment-name=github-runner-deployment
```

### GitLab Runner Issues

**Runner not registering:**
```bash
# Check secret exists
kubectl get secret gitlab-runner-secret -n managed-cicd

# Check runner logs
kubectl logs -n managed-cicd -l app=gitlab-runner | grep -i register

# Verify GitLab URL is accessible
```

**Jobs not running:**
```bash
# Check runner pod logs
kubectl logs -n managed-cicd -l app=gitlab-runner

# Check for job pods
kubectl get pods -n managed-cicd

# Verify RBAC permissions
kubectl auth can-i create pods --namespace=managed-cicd
```

## Next Steps After Deployment

1. **Configure runner labels** (GitHub) or **tags** (GitLab) for workflow targeting
2. **Adjust resource limits** based on your workload requirements
3. **Monitor autoscaling behavior** and tune thresholds if needed
4. **Set up monitoring/alerting** for runner health
5. **Review security settings** (network policies, RBAC, etc.)

## Additional Resources

- [GitHub Actions Runner Controller Docs](https://github.com/actions/actions-runner-controller)
- [GitLab Runner Kubernetes Executor Docs](https://docs.gitlab.com/runner/executors/kubernetes/)
- [Fleet Documentation](https://fleet.rancher.io/)
