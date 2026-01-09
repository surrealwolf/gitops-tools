# Harbor Registry Guide

This guide covers Harbor registry setup, configuration, storage, and usage.

## Overview

Harbor is deployed as a container registry with:
- **Local registry** (`library` project) for pushing/pulling your own images
- **DockerHub proxy cache** (`dockerhub` project) for caching Docker Hub images on-demand
- **Robot accounts** for CI/CD automation
- **PostgreSQL database** (external, managed by CloudNativePG operator)

## Quick Setup

### Step 1: Create Harbor Secrets

```bash
./scripts/harbor-setup.sh secrets
```

This creates the `harbor-credentials` secret with database and Redis passwords.

### Step 2: Create Robot Account

```bash
./scripts/harbor-setup.sh robot
```

This creates a robot account for CI/CD builds. The credentials will be saved to your `.env` file.

### Step 3: Create DockerHub Proxy Cache

```bash
# First, create the DockerHub registry endpoint in Harbor UI:
# Administration → Registries → New Endpoint
#   Name: DockerHub
#   Type: Docker Hub
#   Endpoint URL: https://registry-1.docker.io

# Then create the proxy cache project:
./scripts/harbor-setup.sh proxy
```

### Step 4: Install Certificate (for Docker client)

```bash
./scripts/cert-setup.sh
```

This installs the Harbor TLS certificate so Docker can verify it.

### Step 5: Test Harbor

```bash
./scripts/harbor-test.sh
```

This runs comprehensive tests for push/pull to both local registry and DockerHub cache.

## Configuration Summary

### 1. Harbor Registry (Library Project)
- **Project Name**: `library`
- **Status**: Public, ready to use
- **Purpose**: Default registry for pushing/pulling images

### 2. Robot Account
- **Full Name**: `robot$library+ci-builder` (example)
- **Secret**: Stored in `.env` file (do not commit)
- **Project**: `library`
- **Permissions**: Push, Pull, Create artifacts
- **Purpose**: Automated CI/CD builds and image pushes

**Credentials stored in `.env` file (not committed to git):**
```bash
HARBOR_ROBOT_ACCOUNT_NAME=ci-builder
HARBOR_ROBOT_ACCOUNT_SECRET=<your-secret-here>
HARBOR_ROBOT_ACCOUNT_FULL_NAME=robot$library+ci-builder
```

**⚠️ Important**: The robot account secret is stored in `.env` file which is gitignored. Never commit actual secrets to git.

### 3. DockerHub Registry Endpoint
- **Name**: `DockerHub`
- **Type**: `docker-hub`
- **URL**: `https://registry-1.docker.io`
- **Status**: Configured and ready

### 4. DockerHub Proxy Cache Project
- **Project Name**: `dockerhub`
- **Status**: Created and public
- **Proxy Cache**: ✅ **ENABLED**

According to the [Harbor documentation](https://goharbor.io/docs/main/administration/configure-proxy-cache/), proxy cache can only be enabled when creating a project, not on an existing project. The project was recreated with proxy cache enabled from the start.

## Usage Examples

### Push to Local Registry (Library Project)

```bash
# Login with robot account
docker login harbor.dataknife.net \
  -u 'robot$library+ci-builder' \
  -p '${HARBOR_ROBOT_ACCOUNT_SECRET}'

# Tag and push an image
docker tag my-image:latest harbor.dataknife.net/library/my-image:latest
docker push harbor.dataknife.net/library/my-image:latest
```

### Pull from DockerHub Cache (DockerHub Project)

The proxy cache is now enabled and ready to use:

```bash
# Pull an image through the proxy cache
# First pull: Harbor fetches from DockerHub and caches it
docker pull harbor.dataknife.net/dockerhub/library/nginx:latest

# For official images, always include 'library' namespace
docker pull harbor.dataknife.net/dockerhub/library/hello-world:latest

# Subsequent pulls: Served from Harbor's cache
docker pull harbor.dataknife.net/dockerhub/library/nginx:latest
```

**Important**: According to Harbor documentation, when pulling official images or from single-level repositories, you must include the `library` namespace. For example:
- Official Docker Hub image: `nginx:latest` → `harbor.dataknife.net/dockerhub/library/nginx:latest`
- Public Docker Hub image: `goharbor/harbor-core:dev` → `harbor.dataknife.net/dockerhub/goharbor/harbor-core:dev`

### Pull from Local Registry

```bash
# Pull an image you pushed to the library project
docker pull harbor.dataknife.net/library/my-image:latest
```

## Storage Configuration

### Current Storage Allocation

| Component | Size | Percentage | Purpose |
|-----------|------|------------|---------|
| **Registry** | 400Gi | 80% | Container images (main storage) |
| **Chartmuseum** | 50Gi | 10% | Helm charts |
| **Trivy** | 40Gi | 8% | Vulnerability scans |
| **Jobservice** | 5Gi | 1% | Job data and logs |
| **Redis** | 5Gi | 1% | Cache data |
| **Database** | 1Gi | - | Note: PostgreSQL has separate 20Gi x 2 = 40Gi storage |
| **PostgreSQL** | 20Gi x 2 | - | Database (40Gi total) |

**Total Harbor Storage**: 501Gi (plus 40Gi PostgreSQL = 541Gi total)

### Storage Class

- **Storage Class**: `truenas-nfs` (default)
- **Volume Expansion**: ✅ Supported (`allowVolumeExpansion: true`)
- **Access Mode**: ReadWriteOnce (RWO)

### Registry Storage Considerations

The registry component stores all container images. Storage requirements depend on:

- **Number of images**: More images = more storage needed
- **Image sizes**: Larger images (e.g., ML models, databases) need more space
- **Retention policies**: How long images are kept
- **Proxy cache usage**: DockerHub proxy cache also uses registry storage
- **Tag policies**: Multiple tags per image increase storage

### Recommended Sizes

- **Development/Testing**: 20-50Gi
- **Small Production**: 100-200Gi
- **Medium Production**: 200-500Gi
- **Large Production**: 500Gi-2Ti or more

## Expanding Storage

### Option 1: Update HelmChart (Recommended for GitOps)

Update `harbor/base/harbor-helmchart.yaml`:

```yaml
persistence:
  persistentVolumeClaim:
    registry:
      size: 400Gi  # Increase as needed
```

Commit and push. Fleet will update the HelmChart, and Harbor will recreate the PVC with the new size.

⚠️ **Warning**: Recreating the PVC will delete existing data unless `resourcePolicy: "keep"` is set. Consider backing up important images first.

### Option 2: Expand Existing PVC (No Data Loss)

If the storage class supports volume expansion (truenas-nfs does), you can expand the PVC directly:

```bash
# Expand registry PVC
kubectl patch pvc harbor-registry -n managed-tools \
  -p '{"spec":{"resources":{"requests":{"storage":"400Gi"}}}}'

# Wait for expansion to complete
kubectl wait --for=condition=FileSystemResizePending pvc/harbor-registry -n managed-tools --timeout=5m

# Restart registry pod to apply new size
kubectl rollout restart deployment harbor-registry -n managed-tools
```

### Option 3: Manual PVC Expansion

1. Edit the PVC:
   ```bash
   kubectl edit pvc harbor-registry -n managed-tools
   ```

2. Update the `spec.resources.requests.storage` field

3. Wait for expansion to complete

4. Restart the registry pod if needed

## Monitoring Storage Usage

### Check PVC Sizes

```bash
kubectl get pvc -n managed-tools -o custom-columns=NAME:.metadata.name,SIZE:.spec.resources.requests.storage,USED:.status.capacity.storage
```

### Check Storage Usage Inside Pods

```bash
# Registry storage usage
kubectl exec -n managed-tools deployment/harbor-registry -c registry -- df -h /storage

# Chartmuseum storage usage
kubectl exec -n managed-tools deployment/harbor-chartmuseum -c chartmuseum -- df -h /chart_storage

# Trivy storage usage
kubectl exec -n managed-tools statefulset/harbor-trivy -c trivy -- df -h /var/lib/trivy
```

### Harbor UI

1. Go to Harbor UI: https://harbor.dataknife.net
2. Navigate to **Administration** → **Registries**
3. Check storage usage in project statistics

## Storage Best Practices

1. **Set retention policies**: Automatically clean up old images
2. **Monitor usage**: Set up alerts for storage thresholds
3. **Regular cleanup**: Remove unused images and tags
4. **Use proxy cache wisely**: DockerHub proxy cache can consume significant storage
5. **Plan for growth**: Allocate more storage than initially needed
6. **Backup strategy**: Regular backups of important images

## Verification

### Check Projects
```bash
# Use Harbor admin credentials from .env file or Harbor UI
curl -s -k -u "admin:${HARBOR_ADMIN_PASSWORD}" \
  "https://harbor.dataknife.net/api/v2.0/projects" | \
  jq -r '.[] | "\(.name): public=\(.metadata.public), proxy_cache=\(.registry_id // "none")"'
```

### Check Robot Accounts
```bash
curl -s -k -u "admin:${HARBOR_ADMIN_PASSWORD}" \
  "https://harbor.dataknife.net/api/v2.0/projects/library/robots" | \
  jq -r '.[] | "\(.name)"'
```

### Check Registry Endpoints
```bash
curl -s -k -u "admin:${HARBOR_ADMIN_PASSWORD}" \
  "https://harbor.dataknife.net/api/v2.0/registries" | \
  jq -r '.[] | "\(.name): \(.type), URL=\(.url)"'
```

### Verify Proxy Cache is Enabled
```bash
curl -s -k -u "admin:${HARBOR_ADMIN_PASSWORD}" \
  "https://harbor.dataknife.net/api/v2.0/projects?name=dockerhub" | \
  jq -r '.[] | select(.name == "dockerhub") | {
    name: .name,
    project_id: .project_id,
    registry_id: .registry_id,
    proxy_cache_enabled: (if .registry_id != null and .registry_id != 0 then "YES" else "NO" end)
  }'
```

**⚠️ Note**: Replace `${HARBOR_ADMIN_PASSWORD}` with your actual Harbor admin password from `.env` file or Harbor UI. Never commit passwords to git.

## How Proxy Cache Works

According to the [Harbor documentation](https://goharbor.io/docs/main/administration/configure-proxy-cache/):

1. **First pull**: When a pull request comes to the proxy cache project and the image is not cached, Harbor pulls the image from Docker Hub and serves it as if it's a local image. The image is then cached for future requests.

2. **Subsequent pulls**: Harbor checks the image's latest manifest in Docker Hub:
   - If unchanged: Serves from cache
   - If updated: Pulls new image from Docker Hub, serves it, and caches it
   - If Docker Hub unreachable: Serves from cache
   - If image removed from Docker Hub: No image is served

3. **Rate limiting**: As of Harbor v2.1.1+, Harbor uses HEAD requests to check for updates, which doesn't trigger Docker Hub's rate limiter. Only actual pulls count towards the rate limit.

## Important Notes

- ⚠️ **Proxy cache can only be enabled when creating a project** - it cannot be enabled on existing projects. This is why the option is greyed out in the UI for existing projects.
- The robot account secret cannot be retrieved after creation - keep it secure
- Images are cached on-demand when you pull them through the proxy
- Official Docker Hub images require the `library` namespace in the pull path
- By default, Harbor creates a 7-day retention policy for proxy cache projects
- Proxy cache projects cannot receive pushes - they are read-only (pull from Docker Hub only)

## Troubleshooting

### Proxy cache option is greyed out in UI
- This is expected behavior - proxy cache can only be enabled when creating a project
- Solution: Delete the project and recreate it with proxy cache enabled using `./scripts/harbor-setup.sh proxy`

### Images not caching
- Verify proxy cache is enabled: Check that `registry_id` is not null/0
- Check Harbor logs for errors
- Ensure the registry endpoint is reachable
- Verify you're using the correct pull path format

### Rate limiting issues
- Ensure Harbor version is v2.1.1 or later
- Consider adding Docker Hub credentials to the registry endpoint to increase rate limits
- Harbor v2.1.1+ uses HEAD requests which don't count towards rate limits

### PVC Full

If a PVC is full:

1. **Immediate**: Expand the PVC using Option 2 or 3 above
2. **Cleanup**: Remove unused images and tags
3. **Review**: Check retention policies and adjust if needed

### Storage Class Issues

If storage class doesn't support expansion:

1. Check storage class: `kubectl get storageclass truenas-nfs -o yaml`
2. Look for `allowVolumeExpansion: true`
3. If false, you'll need to recreate the PVC (backup data first)

### Data Loss Prevention

When recreating PVCs:

1. Ensure `resourcePolicy: "keep"` is set in HelmChart
2. Backup important images before changes
3. Use Harbor's replication feature to sync to another registry
4. Export images before PVC recreation

## References

- [Harbor Storage Documentation](https://goharbor.io/docs/latest/administration/configuring-storage/)
- [Harbor Proxy Cache Documentation](https://goharbor.io/docs/main/administration/configure-proxy-cache/)
- [Kubernetes Volume Expansion](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#expanding-persistent-volumes-claims)
