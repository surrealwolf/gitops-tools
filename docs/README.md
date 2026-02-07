# GitOps Tools Documentation

This directory contains comprehensive documentation for all tools and services managed in this GitOps repository.

## Documentation Index

### GitHub Runner
- **[GitHub Runner Overview](GITHUB_RUNNER.md)** - Complete guide for GitHub Actions Runner Controller
  - [Official ARC Controller](github-runner/OFFICIAL_ARC.md) - Official vs Community ARC comparison
  - [Migration Guide](github-runner/MIGRATION_TO_OFFICIAL_ARC.md) - Migrating to official ARC
  - [Runner Groups](github-runner/RUNNER_GROUPS.md) - Runner groups configuration
  - [Runner Group Troubleshooting](github-runner/RUNNER_GROUP_ISSUE.md) - Troubleshooting runner group issues
  - [Setup Organization Runners](github-runner/SETUP_ORG_RUNNERS.md) - Setting up org-level runners

### GitLab Runner
- **[GitLab Runner Base Configuration](../gitlab-runner/base/README.md)** - GitLab CI/CD runner setup, configuration, and Harbor integration

### Harbor
- **[Harbor Documentation](HARBOR.md)** - Harbor container registry setup and configuration

### Loki Stack
- **[Grafana Stack Documentation](../grafana/README.md)** - Loki log aggregation and visualization (Loki + Promtail + Grafana)
- **[UniFi CEF Setup](grafana/UNIFI_CEF_SETUP.md)** - UniFi CEF syslog integration guide

### General
- **[Deployment Guide](DEPLOYMENT.md)** - General deployment procedures
- **[Fleet Structure](FLEET_STRUCTURE.md)** - Fleet GitOps structure and organization
- **[Changelog](CHANGELOG.md)** - Project changelog

## Quick Links

- [Main Repository README](../README.md)
- [Contributing Guide](../CONTRIBUTING.md)
- [Code of Conduct](../CODE_OF_CONDUCT.md)

## Repository Structure

```
.
├── docs/                      # Documentation (this directory)
├── github-runner/            # GitHub Actions Runner Controller
├── gitlab-runner/            # GitLab Runner
├── harbor/                   # Harbor container registry
├── grafana/                  # Grafana Stack (Loki + Promtail + Grafana)
└── secrets/                  # Secret templates and examples
```

