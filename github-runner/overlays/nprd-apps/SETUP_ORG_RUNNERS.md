# Setting Up Organization-Level Runners

## Quick Setup Guide

This guide walks you through setting up organization-level runners with a runner group that has access to all repositories.

## Step 1: Create Runner Group in GitHub

1. Navigate to organization settings:
   ```
   https://github.com/organizations/DataKnifeAI/settings/actions/runners
   ```

2. Click **"New runner group"** button

3. Configure the group:
   - **Name**: `NRPD Auto Scale` (must match `runnerGroup` in `runnerdeployment.yaml`)
   - **Repository access**: Select **"All repositories"**
   - Click **"Create group"**

4. (Optional) Configure public repository access:
   - In the group settings, find **"Allow public repositories"**
   - Enable if you want public repos to use these runners
   - ⚠️ **Security Warning**: Only enable if you understand the risks
   - Forks of public repos can run code on your runners if enabled

## Step 2: Verify Configuration

The runner group should:
- ✅ Be named `NRPD Auto Scale`
- ✅ Have access to "All repositories"
- ✅ Be visible in the runner groups list

## Step 3: Apply Configuration

Once the runner group is created in GitHub:

```bash
# The configuration is already updated in runnerdeployment.yaml
# Just commit and push:
git add github-runner/overlays/nprd-apps/runnerdeployment.yaml
git commit -m "feat: switch to organization-level runners with group"
git push
```

Fleet will automatically:
1. Remove old repository-level runners
2. Create new organization-level runners
3. Register them with the `kubernetes-runners` group
4. Make them available to all repositories in the organization

## Step 4: Verify Runners

After Fleet updates (1-2 minutes):

1. Check runners in Kubernetes:
   ```bash
   kubectl --context=nprd-apps get runner -n managed-cicd
   ```

2. Check runners in GitHub:
   - Go to: https://github.com/organizations/DataKnifeAI/settings/actions/runners
   - Click on the `NRPD Auto Scale` group
   - Verify runners appear and are "Online"

3. Test with a workflow:
   - Trigger a workflow in any repository
   - Verify it uses the organization-level runners

## Troubleshooting

### Runners Not Appearing

- **Check runner group exists**: Verify `NRPD Auto Scale` group exists in GitHub
- **Check group name matches**: Must exactly match `runnerGroup` in YAML
- **Check Fleet status**: `kubectl --context=nprd-apps get gitrepo -A`

### Jobs Not Starting

- **Check repository access**: Verify group has "All repositories" access
- **Check runner labels**: Ensure workflow uses `runs-on: self-hosted`
- **Check runner status**: Runners should be "Online" in GitHub

### Public Repo Access Issues

- **If public repos can't use runners**: Enable "Allow public repositories" in group settings
- **Security risk**: Understand that forks can trigger workflows if enabled
- **Recommendation**: Keep disabled unless necessary

## Rollback

If you need to rollback to repository-level runners:

1. Update `runnerdeployment.yaml`:
   ```yaml
   repository: DataKnifeAI/gitops-tools
   # Comment out organization and runnerGroup
   ```

2. Commit and push:
   ```bash
   git add github-runner/overlays/nprd-apps/runnerdeployment.yaml
   git commit -m "revert: switch back to repository-level runners"
   git push
   ```

## Benefits of Organization-Level Runners

- ✅ **Centralized Management**: One deployment serves all repos
- ✅ **Resource Efficiency**: Shared runners across repositories
- ✅ **Flexibility**: Easy to add/remove repositories from group
- ✅ **Scalability**: Better for organizations with many repos

## Security Considerations

1. **Runner Groups**: Use groups to control access
2. **Repository Access**: Start with "Selected repositories" if unsure
3. **Public Repos**: Disable public repo access unless necessary
4. **Monitoring**: Monitor runner activity regularly
5. **Isolation**: Consider separate groups for different security levels
