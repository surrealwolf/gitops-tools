# GitHub Actions Runner Groups Configuration

## Current Setup

**Repository-Level Runners** (Currently Active)
- ✅ Working and jobs are executing
- ✅ Simple - no additional configuration needed
- ✅ Secure - only `DataKnifeAI/gitops-tools` can use these runners
- ❌ One deployment per repository
- ❌ Less flexible for multiple repositories

## When to Use Runner Groups

Use **Organization-Level Runners with Groups** if you:
- Have multiple repositories that need runners
- Want centralized runner management
- Need to control which repos can use which runners
- Want to share runners across repositories

## Setting Up Organization-Level Runners with Groups

### Step 1: Create a Runner Group in GitHub

1. Go to: https://github.com/organizations/DataKnifeAI/settings/actions/runners
2. Click **"New runner group"**
3. Name it (e.g., "kubernetes-runners" or "default")
4. Choose repository access:
   - **All repositories** - All repos in org can use
   - **Selected repositories** - Choose specific repos
5. Click **"Create group"**

### Step 2: Configure Repository Access

1. In the runner group settings, go to **"Repository access"**
2. Add repositories that should have access:
   - Click **"Add repository"**
   - Select repositories (e.g., `gitops-tools`)
   - Click **"Add"**

### Step 3: Enable Public Repository Access (Optional)

⚠️ **Security Warning**: Allowing public repos to use self-hosted runners is risky!

If you have public repositories and want them to use self-hosted runners:

1. In the runner group settings, find **"Allow public repositories"**
2. Enable the toggle
3. **Understand the risks**:
   - Forks of public repos can run code on your runners
   - Malicious code could access your infrastructure
   - Only enable if you trust all public repos in the group

**Recommendation**: Keep this disabled unless absolutely necessary.

### Step 4: Update RunnerDeployment

Update `runnerdeployment.yaml` to use organization-level with runner group:

```yaml
spec:
  template:
    spec:
      # Organization-level runner
      organization: DataKnifeAI
      
      # Assign to runner group (created in Step 1)
      runnerGroup: kubernetes-runners  # or "default"
      
      # Labels (single label only - ARC limitation)
      labels:
        - self-hosted
```

### Step 5: Apply Changes

```bash
git add github-runner/overlays/nprd-apps/runnerdeployment.yaml
git commit -m "feat: switch to organization-level runners with group"
git push
```

Fleet will update the deployment, and new organization-level runners will be created.

## Comparison

| Feature | Repository-Level | Organization-Level with Groups |
|---------|-----------------|-------------------------------|
| Setup Complexity | Simple | Requires group configuration |
| Multi-Repo Support | No (one per repo) | Yes (shared across repos) |
| Access Control | Automatic | Manual (via groups) |
| Security | High (isolated) | Medium (shared) |
| Management | Per-repo | Centralized |
| Public Repo Support | Automatic | Requires flag |

## Current Recommendation

**Keep Repository-Level** if:
- You only have a few repositories
- Each repo needs isolated runners
- You want the simplest setup

**Switch to Organization-Level** if:
- You have many repositories
- You want to share runners
- You need centralized management
- You want to control access via groups

## Security Best Practices

1. **Runner Groups**: Use groups to restrict access
2. **Public Repos**: Disable public repo access unless necessary
3. **Selected Repos**: Use "Selected repositories" instead of "All repositories"
4. **Monitoring**: Monitor runner activity regularly
5. **Isolation**: Consider separate groups for different security levels

## References

- [GitHub Docs: Managing access to self-hosted runners using groups](https://docs.github.com/en/actions/hosting-your-own-runners/managing-access-to-self-hosted-runners-using-groups)
- [GitHub Docs: Security hardening for GitHub Actions](https://docs.github.com/en/actions/security/security-hardening-for-github-actions)
