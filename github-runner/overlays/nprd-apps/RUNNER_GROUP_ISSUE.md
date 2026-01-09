# Runner Group Assignment Issue

## Problem

Runners are going to the "default" group instead of "NRPD Auto Scale" group, even though the `group` field is correctly configured in `RunnerDeployment`.

## Root Cause

The old community version of Actions Runner Controller (summerwind/actions-runner-controller) has limitations with runner group assignment:

1. **Runner group must exist BEFORE runners are created** - If the group doesn't exist when runners register, they default to "default" group
2. **Group field may not be used during registration** - The old ARC version may not properly pass the group during the GitHub registration process
3. **Runners created before group exists** - If runners were created before the "NRPD Auto Scale" group existed, they won't automatically move

## Current Configuration

The configuration is correct:
```yaml
spec:
  template:
    spec:
      organization: DataKnifeAI
      group: NRPD Auto Scale  # ✅ Field is set correctly
```

## Solutions

### Option 1: Ensure Group Exists First (Recommended)

1. **Create the runner group in GitHub UI first:**
   - Go to: https://github.com/organizations/DataKnifeAI/settings/actions/runners
   - Click "New runner group"
   - Name: "NRPD Auto Scale"
   - Repository access: "All repositories"
   - Create the group

2. **Delete and recreate runners:**
   ```bash
   kubectl --context=nprd-apps delete runner -n managed-cicd --all
   ```
   Runners will automatically recreate and should register with the correct group.

### Option 2: Manually Move Runners in GitHub UI

1. Go to: https://github.com/organizations/DataKnifeAI/settings/actions/runners
2. Click on "default" group
3. Select runners you want to move
4. Click "Move to group" → Select "NRPD Auto Scale"
5. Confirm the move

Runners will stay in the correct group after manual assignment.

### Option 3: Upgrade to New GitHub-Supported ARC

The new GitHub-supported version (gha-runner-scale-set) has better support for runner groups. However, this requires:

- Different CRDs (AutoscalingRunnerSet instead of RunnerDeployment)
- Different architecture (Listener-based)
- Migration from old to new version
- See: https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/deploy-runner-scale-sets

## Verification

After applying a solution, verify:

1. **Check runners in Kubernetes:**
   ```bash
   kubectl --context=nprd-apps get runner -n managed-cicd -o json | jq '.items[].spec.group'
   ```
   Should show: `"NRPD Auto Scale"`

2. **Check in GitHub UI:**
   - Go to: https://github.com/organizations/DataKnifeAI/settings/actions/runners
   - Click on "NRPD Auto Scale" group
   - Verify runners appear there (not in "default")

3. **Test workflow:**
   - Trigger a workflow in any repository
   - Verify it uses runners from "NRPD Auto Scale" group

## Notes

- The old community ARC version (summerwind) has known limitations with runner groups
- The `group` field exists and is applied, but may not be used during registration
- Manual assignment in GitHub UI is the most reliable method for the old version
- The new GitHub-supported ARC has better runner group support

## References

- [GitHub Docs: Runner Scale Sets](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/deploy-runner-scale-sets)
- [Community ARC: RunnerDeployment](https://github.com/actions/actions-runner-controller)
- [GitHub Docs: Managing Runner Groups](https://docs.github.com/en/actions/hosting-your-own-runners/managing-access-to-self-hosted-runners-using-groups)
