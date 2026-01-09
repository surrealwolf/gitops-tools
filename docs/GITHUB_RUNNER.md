# GitHub Runner Documentation

This directory contains comprehensive documentation for GitHub Actions Runner setup and configuration.

## Documentation Index

- **[OFFICIAL_ARC.md](github-runner/OFFICIAL_ARC.md)** - Official vs Community ARC Controller comparison
- **[MIGRATION_TO_OFFICIAL_ARC.md](github-runner/MIGRATION_TO_OFFICIAL_ARC.md)** - Guide for migrating to official ARC
- **[RUNNER_GROUPS.md](github-runner/RUNNER_GROUPS.md)** - Runner groups configuration guide
- **[RUNNER_GROUP_ISSUE.md](github-runner/RUNNER_GROUP_ISSUE.md)** - Troubleshooting runner group assignment
- **[SETUP_ORG_RUNNERS.md](github-runner/SETUP_ORG_RUNNERS.md)** - Setting up organization-level runners

## Quick Links

- [GitHub Actions Runner Controller Official Docs](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller)
- [Runner Groups Documentation](https://docs.github.com/en/actions/hosting-your-own-runners/managing-access-to-self-hosted-runners-using-groups)

## Current Setup

This repository uses GitHub Actions Runner Controller to manage self-hosted runners in Kubernetes.

- **Controller**: Official GitHub-supported ARC (`gha-runner-scale-set-controller`)
- **Runner Group**: NRPD Auto Scale
- **Organization**: DataKnifeAI
- **Namespace**: managed-cicd

