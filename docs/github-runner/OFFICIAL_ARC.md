# Official Actions Runner Controller (ARC)

## Overview

There are **two versions** of Actions Runner Controller:

1. **Community Version** (what you're currently using)
2. **Official GitHub-Supported Version** (newer, recommended)

## Community Version (Current Setup)

**Repository:** `summerwind/actions-runner-controller`

**Status:** Community-maintained, still active but not officially supported by GitHub

**CRDs:**
- `RunnerDeployment` (actions.summerwind.dev/v1alpha1)
- `RunnerReplicaSet`
- `Runner`
- `HorizontalRunnerAutoscaler`

**Architecture:**
- Direct runner pod management
- Runner pods register directly with GitHub
- Simpler but less scalable

**Helm Chart:**
```yaml
chart: actions-runner-controller
repo: https://actions-runner-controller.github.io/actions-runner-controller
image: summerwind/actions-runner-controller
```

**Current Version:** v0.27.6

**Pros:**
- ✅ Mature and stable
- ✅ Well-documented
- ✅ Large community
- ✅ Simple architecture

**Cons:**
- ❌ Not officially supported by GitHub
- ❌ Limited runner group support
- ❌ Less efficient scaling
- ❌ No official SLA

## Official GitHub-Supported Version

**Repository:** `actions/actions-runner-controller` (GitHub official)

**Status:** Officially developed and maintained by GitHub

**CRDs:**
- `AutoscalingRunnerSet` (actions.github.com/v1beta1)
- `AutoscalingListener`
- `EphemeralRunnerSet`
- `EphemeralRunner`

**Architecture:**
- Listener-based architecture
- Ephemeral runners (created on-demand)
- More efficient scaling
- Better resource utilization

**Helm Charts:**
- `gha-runner-scale-set-controller` (controller)
- `gha-runner-scale-set` (runner scale sets)

**Repository:**
```
https://github.com/actions/actions-runner-controller
```

**Documentation:**
- https://docs.github.com/en/actions/tutorials/use-actions-runner-controller
- https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller

**Pros:**
- ✅ Officially supported by GitHub
- ✅ Better runner group support
- ✅ More efficient scaling (ephemeral runners)
- ✅ Better resource utilization
- ✅ Active development by GitHub
- ✅ Official documentation and support

**Cons:**
- ⚠️ Different architecture (requires migration)
- ⚠️ Newer (less community examples)
- ⚠️ Different CRDs (not compatible with old version)

## Key Differences

| Feature | Community Version | Official Version |
|---------|------------------|-----------------|
| **Maintainer** | Community | GitHub |
| **CRD** | RunnerDeployment | AutoscalingRunnerSet |
| **API Group** | actions.summerwind.dev | actions.github.com |
| **Architecture** | Direct pods | Listener + Ephemeral |
| **Scaling** | Pod-based | Ephemeral runners |
| **Runner Groups** | Limited support | Full support |
| **Documentation** | Community | Official GitHub docs |
| **Support** | Community | GitHub official |

## Your Current Setup

**You're using:** Community version (summerwind)

**Evidence:**
- Controller: `summerwind/actions-runner-controller:v0.27.6`
- CRDs: `runnerdeployments.actions.summerwind.dev`
- Configuration: `RunnerDeployment` CRD

**Note:** You also have the new CRDs installed (`autoscalingrunnersets.actions.github.com`), but you're not using them yet.

## Should You Migrate?

### Keep Community Version If:
- ✅ Current setup works well
- ✅ You don't need advanced features
- ✅ You want to avoid migration effort
- ✅ Community support is sufficient

### Migrate to Official Version If:
- ✅ You want official GitHub support
- ✅ You need better runner group support
- ✅ You want more efficient scaling
- ✅ You want future-proof solution
- ✅ You need official SLA/support

## Migration Path

If you decide to migrate:

1. **Install Official ARC:**
   ```bash
   helm repo add actions-runner-controller \
     https://actions-runner-controller.github.io/actions-runner-controller
   helm install arc \
     actions-runner-controller/gha-runner-scale-set-controller \
     -n actions-runner-system
   ```

2. **Create AutoscalingRunnerSet:**
   - Different CRD structure
   - Uses values.yaml configuration
   - See: https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/deploy-runner-scale-sets

3. **Migrate Configuration:**
   - Convert RunnerDeployment → AutoscalingRunnerSet
   - Update authentication (GitHub App recommended)
   - Test in staging first

4. **Remove Old Version:**
   - Uninstall community ARC
   - Remove old CRDs (if desired)

## References

### Official GitHub Documentation
- [About Actions Runner Controller](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners-with-actions-runner-controller/about-actions-runner-controller)
- [Deploy Runner Scale Sets](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/deploy-runner-scale-sets)
- [Quickstart](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/quickstart)

### Community Version
- [GitHub Repository](https://github.com/actions/actions-runner-controller)
- [Community Documentation](https://github.com/actions/actions-runner-controller/blob/master/docs/)

## Recommendation

**For now:** Keep using the community version since it's working well.

**Future consideration:** Plan migration to official version when:
- You need better runner group support
- You want official GitHub support
- You're doing a major infrastructure update
- You need more efficient scaling

The official version is the future direction, but the community version is still viable for current needs.
