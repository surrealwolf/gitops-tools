# GitHub Organization Setup for Runners

## Current Status

- **Current GitHub account**: `surrealwolf` (personal account)
- **DataKnife organization**: Does not exist yet
- **Runner configuration**: Currently set to `surrealwolf` organization

## Options

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
5. Transfer repositories from `surrealwolf` to `DataKnife` (optional)
6. Update runner configuration to use `DataKnife` organization

### Option 2: Convert Personal Account to Organization

**Pros:**
- Keeps existing repositories in place
- No need to transfer repos

**Cons:**
- **Irreversible** - cannot convert back to personal account
- Requires creating a new personal account first
- Some personal data won't transfer (SSH keys, OAuth tokens, etc.)

**Steps:**
1. Create a new personal GitHub account (for yourself)
2. Go to `surrealwolf` account → Settings → Organizations
3. Click "Turn surrealwolf into an organization"
4. Assign the new personal account as owner
5. Complete the conversion

## After Creating Organization

Once you have the DataKnife organization:

1. **Update runner configuration:**
   ```yaml
   organization: DataKnife  # or dataknife (depending on what you create)
   ```

2. **Update GitHub token permissions:**
   - Ensure your PAT has access to the new organization
   - Or create a new token with org access

3. **Commit and push:**
   ```bash
   git add github-runner/base/runnerdeployment.yaml
   git commit -m "feat: update runner to use DataKnife organization"
   git push
   ```

## Quick Decision Guide

- **Want to keep personal account separate?** → Create new DataKnife org
- **Want to keep all repos in current account?** → Convert account to org
- **Using dataknife.net domain?** → Create DataKnife org (better alignment)
