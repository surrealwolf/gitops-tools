# GitLab Runner

This directory contains the base configuration for deploying GitLab Runner with Kubernetes executor to Kubernetes clusters.

## Overview

GitLab Runner executes GitLab CI/CD jobs in Kubernetes pods. Each job runs in a separate pod, providing isolation and scalability.

## Architecture

- **Runner Pod**: The main GitLab Runner pod that polls GitLab for jobs
- **Job Pods**: Ephemeral pods created for each CI/CD job
- **Kubernetes Executor**: Uses Kubernetes API to create and manage job pods

## Prerequisites

1. **GitLab Instance**: Access to a GitLab instance (GitLab.com or self-hosted)
2. **Runner Registration Token**: Obtain a registration token from your GitLab project, group, or instance
3. **Kubernetes Cluster**: Access to a Kubernetes cluster with:
   - RBAC enabled
   - Ability to create pods and services

## Installation

### Step 1: Obtain Runner Registration Token

**For Project-level Runner:**
1. Go to your GitLab project
2. Navigate to **Settings** → **CI/CD** → **Runners**
3. Expand **Expand runners settings**
4. Copy the **Registration token**

**For Group-level Runner:**
1. Go to your GitLab group
2. Navigate to **Settings** → **CI/CD** → **Runners**
3. Copy the **Registration token**

**For Instance-level Runner:**
1. Go to **Admin Area** → **Overview** → **Runners**
2. Copy the **Registration token**

### Step 2: Create Runner Token Secret

Create a Kubernetes secret with the runner token:

```bash
# Create secret with runner registration token
kubectl create secret generic gitlab-runner-secret \
  --from-literal=runner-registration-token='<YOUR_RUNNER_TOKEN>' \
  -n managed-cicd
```

Alternatively, you can update the HelmChart to use the token directly (not recommended for production).

### Step 3: Update Configuration

Update `gitlab-runner-helmchart.yaml` with:
- `gitlabUrl`: Your GitLab instance URL (e.g., `https://gitlab.com` or `https://gitlab.example.com`)
- `runnerRegistrationToken`: Set to your runner token (or use Fleet HelmChartConfig to inject from secret)

To use the secret, you can:
1. Use Fleet HelmChartConfig to inject the token from the secret
2. Or manually extract and set the token:
   ```bash
   kubectl get secret gitlab-runner-secret -n managed-cicd -o jsonpath='{.data.runner-registration-token}' | base64 -d
   ```

### Step 4: Deploy Runner

The runner will be deployed automatically by Fleet when:
1. The namespace `managed-cicd` exists
2. The runner token secret exists (if using secret)
3. Fleet syncs the GitRepo

Monitor deployment:
```bash
kubectl get pods -n managed-cicd -l app=gitlab-runner
kubectl get helmchart -n managed-cicd
```

### Step 5: Verify Runner Registration

1. Go to your GitLab project/group/instance settings
2. Navigate to **Runners** section
3. Verify the runner appears and is active (green circle)

## Configuration

### Runner Resources

The runner pod resources are configured in `gitlab-runner-helmchart.yaml`. Adjust CPU and memory limits as needed.

### Job Pod Resources

Job pod resources are configured in the `runners.config` section:
- `cpu_limit`: Maximum CPU for job pods
- `memory_limit`: Maximum memory for job pods
- `cpu_request`: CPU request for job pods
- `memory_request`: Memory request for job pods

### Scaling and Concurrent Jobs

**Job Pod Scaling:**
- GitLab Runner with Kubernetes executor creates a **new pod for each CI/CD job**
- Jobs run in parallel based on the `concurrent` setting
- This provides automatic scaling of job execution capacity
- Set `concurrent` to control how many jobs can run simultaneously (default: 4)

**Runner Pod Scaling:**
- The GitLab Runner pod itself is a single instance that polls for jobs
- For high availability, you can run multiple runner pods (increase HelmChart replicas)
- Each runner pod can handle up to `concurrent` jobs simultaneously

**Example Scaling Scenarios:**
- `concurrent: 4` with 1 runner pod = up to 4 parallel jobs
- `concurrent: 4` with 2 runner pods = up to 8 parallel jobs
- `concurrent: 10` with 1 runner pod = up to 10 parallel jobs

**Note:** The runner pod itself doesn't auto-scale, but job pods are created on-demand. Adjust `concurrent` based on your cluster capacity and job requirements.

### Kubernetes Executor Settings

The Kubernetes executor configuration is in `runners.config`:
- `namespace`: Namespace where job pods are created
- `image`: Default Docker image for jobs (can be overridden in `.gitlab-ci.yml`)
- `privileged`: Whether to run pods in privileged mode (default: false)

### Cache Configuration

Cache is configured to use Kubernetes volumes:
- `cacheType: kubernetes`: Uses Kubernetes volumes for cache
- `cachePath: /cache`: Cache mount path
- `cacheShared: true`: Share cache between jobs

### Harbor Registry Integration

GitLab Runner is configured to work with the Harbor private container registry. This requires certificate configuration in two places:

1. **Docker-in-Pod Certificate Trust** - For `docker login` and `docker build` commands executed inside job pods
2. **Kubernetes Image Pull Certificate Trust** - For containerd to pull images from Harbor when creating job pods

#### Certificate Configuration Components

**1. Harbor CA Certificate Secret**

Since Harbor uses the default ingress certificate, the Harbor CA certificate is extracted directly from the Harbor registry endpoint and stored in a dedicated secret for GitLab Runner:

```bash
# Extract Harbor CA certificate and create secret in GitLab Runner namespace
./scripts/sync-harbor-ca-cert.sh
```

This script:
- Extracts the CA certificate from Harbor's registry endpoint (which uses the default ingress certificate)
- Creates `harbor-ca-cert` secret in `managed-cicd` namespace with only `ca.crt` (no private key)
- Prevents Docker from expecting client certificates
- Uses `openssl` to connect to Harbor and extract the certificate chain

**2. Docker Certificate Mount in Job Pods**

The GitLab Runner Helm chart configuration mounts the Harbor CA certificate into job pods at `/etc/docker/certs.d/harbor.dataknife.net/ca.crt`:

```yaml
[[runners.kubernetes.volumes.secret]]
  name = "harbor-ca-cert"
  mount_path = "/etc/docker/certs.d/harbor.dataknife.net"
  read_only = true
```

This allows Docker commands inside job pods to trust Harbor's certificate.

**3. RKE2/containerd Registry Configuration (DaemonSet)**

A DaemonSet (`containerd-harbor-cert-config`) runs on each node to configure containerd/RKE2 to trust Harbor certificates for image pulls. It:

- Creates `/etc/rancher/rke2/registries.yaml` with Harbor registry configuration
- Places the CA certificate at `/etc/rancher/rke2/harbor-ca.crt`
- Also configures containerd certs.d directory for compatibility
- Runs as a privileged pod with host network access

**Configuration File Structure:**

The DaemonSet creates `/etc/rancher/rke2/registries.yaml`:

```yaml
mirrors:
  "harbor.dataknife.net":
    endpoint:
      - "https://harbor.dataknife.net"
configs:
  "harbor.dataknife.net":
    tls:
      ca_file: "/etc/rancher/rke2/harbor-ca.crt"
```

**Important Notes:**

- The DaemonSet configuration is cluster-specific and located in the overlay directory: `gitlab-runner/overlays/nprd-apps/containerd-harbor-cert-daemonset.yaml`
- RKE2 requires a service restart (`rke2-server` on control-plane nodes, `rke2-agent` on worker nodes) to pick up `registries.yaml` changes
- The DaemonSet maintains the configuration files and will recreate them if deleted
- For K3s clusters, the paths would be `/etc/rancher/k3s/` instead of `/etc/rancher/rke2/`

#### Updating Harbor Certificate

When the Harbor certificate is updated (or when the default ingress certificate changes):

1. **Re-extract the Harbor CA certificate:**
   ```bash
   ./scripts/sync-harbor-ca-cert.sh
   ```
   
   This will automatically extract the current certificate from Harbor's endpoint.

2. **Restart RKE2 services on all nodes** (required for containerd to pick up changes):
   ```bash
   # On control-plane nodes
   sudo systemctl restart rke2-server

   # On worker nodes
   sudo systemctl restart rke2-agent
   ```

   The DaemonSet will automatically update the configuration files, but RKE2 needs a restart to reload `registries.yaml`.

3. **Restart GitLab Runner pods** (to pick up new certificate in mounted secret):
   ```bash
   kubectl rollout restart deployment gitlab-runner -n managed-cicd
   ```

#### Verification

**Verify certificate secret exists:**
```bash
kubectl get secret harbor-ca-cert -n managed-cicd
```

**Verify DaemonSet is running:**
```bash
kubectl get daemonset containerd-harbor-cert-config -n managed-cicd
kubectl get pods -n managed-cicd -l app=containerd-harbor-cert-config
```

**Verify registries.yaml on a node:**
```bash
ssh ubuntu@<node-ip> "sudo cat /etc/rancher/rke2/registries.yaml"
```

**Test Harbor access from a job pod:**
```yaml
# In .gitlab-ci.yml
test_harbor:
  script:
    - docker login harbor.dataknife.net -u <username> -p <password>
    - docker pull harbor.dataknife.net/dockerhub/library/alpine:latest
```

## Security Considerations

- **Token Security**: Store runner tokens in Kubernetes secrets (encrypted at rest)
- **RBAC**: The runner requires RBAC permissions to create and manage pods
- **Privileged Mode**: Avoid running jobs in privileged mode unless necessary
- **Resource Limits**: Always set resource limits on job pods to prevent resource exhaustion
- **Network Policies**: Consider implementing network policies to restrict job pod network access

## Troubleshooting

**Runner not starting:**
```bash
# Check runner logs
kubectl logs -n managed-cicd -l app=gitlab-runner

# Verify secret exists
kubectl get secret gitlab-runner-secret -n managed-cicd

# Check RBAC permissions
kubectl get clusterrolebinding | grep gitlab-runner
```

**Runner not registering:**
```bash
# Check runner pod logs for registration errors
kubectl logs -n managed-cicd -l app=gitlab-runner | grep -i "register"

# Verify GitLab URL is correct and accessible
# Verify runner token is correct
```

**Jobs not running:**
```bash
# Check for job pods
kubectl get pods -n managed-cicd

# Check runner logs for job execution errors
kubectl logs -n managed-cicd -l app=gitlab-runner | grep -i "job"

# Verify Kubernetes executor permissions
kubectl auth can-i create pods --namespace=managed-cicd
```

**Job pods failing:**
```bash
# Check job pod logs
kubectl logs -n managed-cicd <job-pod-name>

# Check job pod events
kubectl describe pod <job-pod-name> -n managed-cicd
```

**Harbor certificate errors:**

**Error: `tls: failed to verify certificate: x509: certificate signed by unknown authority`**

This error can occur in two scenarios:

1. **Docker commands in job pods** (e.g., `docker login`, `docker build`):
   - Verify the `harbor-ca-cert` secret exists: `kubectl get secret harbor-ca-cert -n managed-cicd`
   - Verify the secret is mounted in the GitLab Runner Helm chart configuration
   - Check job pod logs to confirm certificate is mounted: `kubectl logs <job-pod-name> -n managed-cicd`
   - Run `./scripts/sync-harbor-ca-cert.sh` to recreate the secret

2. **Kubernetes image pulls** (e.g., `Error: ErrImagePull` during pod creation):
   - Verify the DaemonSet is running: `kubectl get daemonset containerd-harbor-cert-config -n managed-cicd`
   - Check DaemonSet pod logs: `kubectl logs -n managed-cicd -l app=containerd-harbor-cert-config --tail=50`
   - Verify `registries.yaml` exists on nodes: `ssh ubuntu@<node-ip> "sudo cat /etc/rancher/rke2/registries.yaml"`
   - Restart RKE2 services on all nodes (required after DaemonSet creates/updates files):
     ```bash
     # On control-plane nodes
     sudo systemctl restart rke2-server
     # On worker nodes
     sudo systemctl restart rke2-agent
     ```

**Error: `missing client certificate tls.cert for key tls.key`**

This occurs when the secret contains both `tls.crt` and `tls.key`. Docker interprets this as a client certificate requirement.

- Solution: Use `harbor-ca-cert` secret with only `ca.crt` (no private key)
- Run `./scripts/sync-harbor-ca-cert.sh` to create the correct secret format

**Certificate not mounted in job pods:**
```bash
# Verify secret exists
kubectl get secret harbor-ca-cert -n managed-cicd

# Check GitLab Runner Helm chart values for volume mount configuration
kubectl get helmchart gitlab-runner -n managed-cicd -o yaml | grep -A 10 harbor-ca-cert

# Restart GitLab Runner pods to pick up secret changes
kubectl rollout restart deployment gitlab-runner -n managed-cicd
```

**DaemonSet not running on nodes:**
```bash
# Check DaemonSet status
kubectl get daemonset containerd-harbor-cert-config -n managed-cicd

# Check DaemonSet pod logs
kubectl logs -n managed-cicd -l app=containerd-harbor-cert-config

# Verify DaemonSet configuration file exists in overlay
ls -la gitlab-runner/overlays/nprd-apps/containerd-harbor-cert-daemonset.yaml
```

## References

- [GitLab Runner Kubernetes Executor Documentation](https://docs.gitlab.com/runner/executors/kubernetes/)
- [GitLab Runner Helm Chart](https://docs.gitlab.com/runner/install/kubernetes.html)
- [GitLab Runner Configuration](https://docs.gitlab.com/runner/configuration/)
