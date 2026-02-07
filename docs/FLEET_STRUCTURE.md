# Fleet GitOps Structure Guide

This document explains the Fleet GitOps structure and how deployments are organized in this repository.

## Current Fleet Configuration

The Fleet GitRepo monitors **overlay directories only** to prevent bundle conflicts:

```yaml
paths:
  - github-runner/overlays/nprd-apps
  - gitlab-runner/overlays/nprd-apps
  - harbor/overlays/nprd-apps
  - grafana/overlays/nprd-apps
```

## Why Overlay-Only Monitoring?

### Problem with Root/Base Monitoring

If Fleet monitors the root directory (`.`) or base directories:
- Fleet creates **separate bundles** for each directory
- Base and overlay bundles both try to deploy the same resources
- Results in ownership conflicts and `ErrApplied` errors
- Example: `gitops-tools-nprd-apps-grafana-base` and `gitops-tools-nprd-apps-grafana-overlays-nprd-apps` both deploying config

### Solution: Overlay-Only Pattern

Each overlay directory contains **all necessary files** (copied from base):
- No dependency on `../../base/` references
- Each overlay is self-contained
- Fleet creates only one bundle per overlay
- No conflicts between base and overlay bundles

## Repository Structure

```
.
├── github-runner/
│   ├── base/                    # Base configuration (reference only)
│   │   ├── kustomization.yaml
│   │   ├── github-runner-controller-helmchart.yaml
│   │   └── runnerdeployment.yaml
│   └── overlays/
│       └── nprd-apps/           # Cluster-specific overlay (deployed)
│           ├── fleet.yaml       # Cluster targeting
│           ├── kustomization.yaml
│           ├── github-runner-controller-helmchart.yaml  # Copied from base
│           └── runnerdeployment.yaml                    # Copied from base
│
├── gitlab-runner/
│   ├── base/                    # Base configuration (reference only)
│   └── overlays/
│       └── nprd-apps/           # Cluster-specific overlay (deployed)
│           ├── fleet.yaml
│           ├── kustomization.yaml
│           └── gitlab-runner-helmchart.yaml  # Copied from base
│
├── harbor/
│   ├── base/                    # Base configuration (reference only)
│   └── overlays/
│       └── nprd-apps/           # Cluster-specific overlay (deployed)
│           ├── fleet.yaml
│           ├── kustomization.yaml
│           ├── harbor-helmchart.yaml         # Copied from base
│           ├── postgresql-cluster.yaml       # Copied from base
│           └── postgresql-database.yaml      # Copied from base
│
└── grafana/
    ├── base/                    # Base configuration (reference only)
    │   ├── fleet.yaml
    │   ├── kustomization.yaml
    │   ├── namespace.yaml
    │   ├── loki-helmchart.yaml
    │   ├── promtail-helmchart.yaml
    │   ├── grafana-helmchart.yaml
    │   ├── prometheus-helmchart.yaml
    │   └── README.md
    └── overlays/
        └── nprd-apps/           # Cluster-specific overlay (deployed)
            ├── fleet.yaml
            ├── kustomization.yaml
            ├── loki-helmchart.yaml
            ├── promtail-helmchart.yaml
            ├── grafana-helmchart.yaml
            ├── prometheus-helmchart.yaml
            └── vector-*.yaml    # Syslog for UniFi CEF
```

## Key Patterns

### 1. Overlay Kustomization Pattern

Each overlay's `kustomization.yaml` references **local files** (not `../base/`):

```yaml
# ✅ CORRECT (Harbor, GitHub Runner, GitLab Runner, Loki)
resources:
  - harbor-helmchart.yaml
  - postgresql-cluster.yaml
  - loki-helmchart.yaml
  - promtail-helmchart.yaml
  - grafana-helmchart.yaml

# ❌ WRONG (causes Fleet errors)
resources:
  - ../../base/harbor-helmchart.yaml
```

### 2. Fleet Targeting

Each overlay has a `fleet.yaml` that targets the cluster:

```yaml
defaultNamespace: managed-tools

targetCustomizations:
  - name: nprd-apps
    clusterSelector:
      matchLabels:
        management.cattle.io/cluster-display-name: nprd-apps
```

### 3. Base Directory Purpose

Base directories serve as:
- **Reference/template** for creating overlays
- **Documentation** of base configuration
- **NOT deployed directly** by Fleet

## Fleet Bundle Naming

Fleet creates bundles with names based on the monitored path:

- `github-runner/overlays/nprd-apps` → `gitops-tools-nprd-apps-github-runner-overlays-n-<hash>`
- `harbor/overlays/nprd-apps` → `gitops-tools-nprd-apps-harbor-overlays-nprd-apps`
- `grafana/overlays/nprd-apps` → `gitops-tools-nprd-apps-grafana-overlays-nprd-apps`

## Common Issues and Solutions

### Issue: `ErrApplied - '../../base' doesn't exist`

**Cause**: Overlay kustomization references `../../base/` but Fleet processes bundles separately.

**Solution**: Copy base files into overlay directory and reference them locally.

### Issue: Ownership Metadata Conflicts

**Cause**: Both base and overlay bundles trying to manage the same resources.

**Solution**: Monitor only overlay directories, not base or root.

### Issue: Multiple Bundles for Same Resources

**Cause**: Fleet monitoring root directory (`.`) creates bundles for every subdirectory.

**Solution**: Specify exact overlay paths in GitRepo `paths` field.

## Updating Base Configuration

When updating base configuration:

1. **Update base files** (for reference/documentation)
2. **Copy updated files to overlay** (for actual deployment)
3. **Commit and push** - Fleet will deploy from overlay

Example:
```bash
# Update base
vim harbor/base/harbor-helmchart.yaml

# Copy to overlay
cp harbor/base/harbor-helmchart.yaml harbor/overlays/nprd-apps/

# Commit
git add harbor/
git commit -m "feat: update Harbor configuration"
git push
```

## Verification

Check Fleet status:
```bash
# On manager cluster
kubectl get bundle -n fleet-default | grep <tool-name>
kubectl describe bundle <bundle-name> -n fleet-default

# On target cluster
kubectl get pods -n <namespace> -l app=<tool-name>
kubectl get all -n <namespace> -l app=<tool-name>
```

## Best Practices

1. ✅ **Always monitor overlay directories** in Fleet GitRepo
2. ✅ **Copy base files to overlay** when creating new tools
3. ✅ **Keep base directories** for reference and documentation
4. ✅ **Use local file references** in overlay kustomization.yaml
5. ✅ **Test overlay independently** - should work without base directory
6. ❌ **Don't reference `../../base/`** in overlay kustomizations
7. ❌ **Don't monitor root directory** (creates too many bundles)
8. ❌ **Don't monitor base directories** (causes conflicts)

## Current Status

All tools follow the overlay-only pattern:
- ✅ **Harbor**: Working (overlay contains all files)
- ✅ **GitHub Runner**: Working (overlay contains all files)
- ✅ **GitLab Runner**: Working (overlay contains all files)
- ✅ **Grafana Stack**: Working (overlay contains Helm charts and services)
