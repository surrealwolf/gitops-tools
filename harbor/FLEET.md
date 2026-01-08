# Fleet GitOps Configuration Guide

This document explains the Fleet GitOps setup for Harbor deployment.

## Repository Structure

```
harbor/
├── base/                    # Base Harbor configuration
│   ├── fleet.yaml          # Base Fleet config (typically not deployed directly)
│   ├── kustomization.yaml  # Kustomize base
│   ├── namespace.yaml
│   ├── harbor-helmchart.yaml
│   └── harbor-helmchartconfig.yaml
└── overlays/
    └── nprd-apps/           # nprd-apps cluster overlay
        ├── fleet.yaml       # Cluster-specific Fleet config with targeting
        └── kustomization.yaml
```

## Fleet Configuration

### GitRepo Setup

Your Fleet GitRepo resource should be configured to monitor one of these paths:

#### Recommended: Monitor Overlay Directory
```yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: gitops-tools
  namespace: fleet-default
spec:
  repo: https://github.com/your-org/gitops-tools
  branch: main
  paths:
    - harbor/overlays/nprd-apps
```

**Benefits:**
- Uses cluster-specific overlay
- Cluster targeting configured in `fleet.yaml`
- Clean separation of base and overlays

#### Alternative: Monitor Root Directory
```yaml
apiVersion: fleet.cattle.io/v1alpha1
kind: GitRepo
metadata:
  name: gitops-tools
  namespace: fleet-default
spec:
  repo: https://github.com/your-org/gitops-tools
  branch: main
  # No paths specified - Fleet creates bundles for each directory
```

**Benefits:**
- Fleet automatically discovers all bundles
- Each directory becomes a bundle
- Overlays use their own `fleet.yaml` for targeting

#### Not Recommended: Monitor Base Only
```yaml
spec:
  paths:
    - harbor/base
```

**Issues:**
- Won't use overlay configurations
- Deploys to all clusters (unless base `fleet.yaml` has targeting)
- Loses cluster-specific customizations

## Cluster Targeting

The `harbor/overlays/nprd-apps/fleet.yaml` file configures which cluster receives this deployment.

### Finding Your Cluster Labels

```bash
# List all clusters and their labels
kubectl get clusters.management.cattle.io -o yaml | grep -A 10 labels

# Or get specific cluster
kubectl get cluster.management.cattle.io <cluster-name> -o yaml | grep -A 10 labels
```

### Common Label Patterns

Update `harbor/overlays/nprd-apps/fleet.yaml` with labels that match your cluster:

```yaml
targetCustomizations:
  - name: nprd-apps
    clusterSelector:
      matchLabels:
        managed.cattle.io/cluster-name: nprd-apps
        # OR
        cluster-name: nprd-apps
        # OR
        environment: nprd
```

## Troubleshooting

### Bundle Not Deploying

1. **Check GitRepo status:**
   ```bash
   kubectl get gitrepo -n fleet-default
   kubectl describe gitrepo <name> -n fleet-default
   ```

2. **Check Bundle status:**
   ```bash
   kubectl get bundle -n fleet-default
   kubectl describe bundle <bundle-name> -n fleet-default
   ```

3. **Verify cluster targeting:**
   ```bash
   # Check if bundle has correct targetCustomizations
   kubectl get bundle -n fleet-default -o yaml | grep -A 20 targetCustomizations
   
   # Verify cluster labels match
   kubectl get clusters.management.cattle.io -o yaml | grep -A 10 labels
   ```

4. **Check BundleDeployment:**
   ```bash
   kubectl get bundledeployment -n fleet-default
   kubectl describe bundledeployment <name> -n fleet-default
   ```

### Bundle Deploying to Wrong Cluster

- Verify `fleet.yaml` clusterSelector matches your cluster labels
- Check if base `fleet.yaml` is being used instead of overlay
- Ensure GitRepo monitors the correct path

### HelmChart Not Created

1. **Check if namespace exists:**
   ```bash
   kubectl get namespace managed-tools
   ```

2. **Check HelmChart resource:**
   ```bash
   kubectl get helmchart -n managed-tools
   kubectl describe helmchart harbor -n managed-tools
   ```

3. **Verify secrets exist:**
   ```bash
   kubectl get secret harbor-credentials -n managed-tools
   kubectl get secret wildcard-dataknife-net-tls -n managed-tools
   ```

## Best Practices

1. **Use overlays for cluster-specific configs** - Keep base generic
2. **Monitor overlay directory** - More explicit and clear
3. **Test cluster targeting** - Verify labels match before deploying
4. **Monitor Fleet status** - Set up alerts for bundle failures
5. **Use Fleet labels** - Add `fleet.cattle.io/bundle-name` labels if needed

## Additional Resources

- [Fleet Documentation](https://fleet.rancher.io/)
- [Fleet Examples](https://github.com/rancher/fleet-examples)
- [Kustomize Documentation](https://kustomize.io/)
