# GitOps Tools

GitOps repository for deploying managed Kubernetes tools to the `nprd-apps` cluster using Rancher Fleet.

## Quick Start

1. **Generate TLS certificate**: `./scripts/generate-wildcard-cert.sh`
2. **Setup Harbor**: `./scripts/harbor-setup.sh all`
3. **Setup Runners**: `./scripts/runner-setup.sh all`
4. **Deploy via Fleet**: Configure GitRepo to monitor the tool directories

See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) for detailed setup instructions.

## Tools

- **Harbor**: Container image registry with DockerHub proxy cache
- **GitHub Runner**: GitHub Actions self-hosted runners
- **GitLab Runner**: GitLab CI/CD runners

## Structure

```
.
├── harbor/          # Harbor registry deployment
├── github-runner/   # GitHub Actions runners
├── gitlab-runner/   # GitLab CI/CD runners
├── scripts/         # Setup and utility scripts
├── secrets/         # Secret templates and examples
└── docs/            # Detailed documentation
```

## Documentation

- [Deployment Guide](docs/DEPLOYMENT.md) - Complete setup and deployment instructions for all tools
- [Harbor Guide](docs/HARBOR.md) - Harbor registry setup, storage, and usage
- [Changelog](docs/CHANGELOG.md) - Version history

## Cluster Information

- **Cluster**: nprd-apps
- **Namespace**: managed-tools

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.
