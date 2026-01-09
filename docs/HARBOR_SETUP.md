# Harbor Setup Summary

This document summarizes the Harbor registry, robot account, and DockerHub proxy cache configuration.

## ✅ Completed Setup

### 1. Harbor Registry (Library Project)
- **Project Name**: `library`
- **Status**: Public, ready to use
- **Purpose**: Default registry for pushing/pulling images

### 2. Robot Account
- **Full Name**: `robot$library+ci-builder`
- **Secret**: `<stored in .env file - do not commit>`
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
- **ID**: `1`
- **Status**: Configured and ready

### 4. DockerHub Proxy Cache Project ✅
- **Project Name**: `dockerhub`
- **Project ID**: `3`
- **Registry ID**: `1` (proxy cache enabled)
- **Status**: Created and public
- **Proxy Cache**: ✅ **ENABLED**

According to the [Harbor documentation](https://goharbor.io/docs/main/administration/configure-proxy-cache/), proxy cache can only be enabled when creating a project, not on an existing project. The project was recreated with proxy cache enabled from the start.

## Usage Examples

### Push to Local Registry (Library Project)

```bash
# Login with robot account
# Get credentials from .env file or Harbor UI
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

## Scripts Available

- `scripts/create-harbor-robot-account.sh` - Create robot accounts
- `scripts/create-harbor-dockerhub-mirror.sh` - Create DockerHub registry endpoint
- `scripts/create-proxy-cache-project.sh` - Create proxy cache project (recreates if needed)
- `scripts/configure-dockerhub-proxy.sh` - Attempt to configure proxy cache via API (deprecated - use create-proxy-cache-project.sh instead)

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

**Proxy cache option is greyed out in UI:**
- This is expected behavior - proxy cache can only be enabled when creating a project
- Solution: Delete the project and recreate it with proxy cache enabled using `create-proxy-cache-project.sh`

**Images not caching:**
- Verify proxy cache is enabled: Check that `registry_id` is not null/0
- Check Harbor logs for errors
- Ensure the registry endpoint is reachable
- Verify you're using the correct pull path format

**Rate limiting issues:**
- Ensure Harbor version is v2.1.1 or later
- Consider adding Docker Hub credentials to the registry endpoint to increase rate limits
- Harbor v2.1.1+ uses HEAD requests which don't count towards rate limits

