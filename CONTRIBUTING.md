# Contributing to GitOps Tools

Thank you for your interest in contributing to GitOps Tools! This document provides guidelines and instructions for contributing.

## Code of Conduct

This project adheres to a Code of Conduct that all contributors are expected to follow. Please read [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before contributing.

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/your-username/gitops-tools.git`
3. Create a branch for your changes: `git checkout -b feature/your-feature-name`

## Development Guidelines

### Kubernetes Manifest Standards

- Follow Kubernetes best practices for all manifests
- Use Kustomize for configuration management
- Keep base configurations generic and reusable
- Use overlays for cluster-specific customizations
- Always specify resource limits and requests
- Label all resources appropriately

### GitOps Principles

- All changes should be declarative and idempotent
- Avoid hardcoding values; use ConfigMaps and Secrets
- Document cluster-specific configurations
- Test manifests locally before committing

### File Organization

- Base manifests go in `{tool}/base/`
- Cluster-specific overlays go in `{tool}/overlays/{cluster-name}/`
- Each tool should have its own directory following the same pattern

### Commit Messages

Use conventional commit format:

```
type(scope): subject

body (optional)

footer (optional)
```

Types:
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting, etc.)
- `refactor`: Code refactoring
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

Examples:
```
feat(harbor): add ingress configuration for nprd-apps
fix(harbor): correct resource limits for harbor-core
docs: update README with new tool information
```

## Pull Request Process

1. Ensure your changes follow the development guidelines
2. Update documentation as needed
3. Test your changes (if applicable)
4. Update CHANGELOG.md with your changes
5. Create a pull request with a clear description
6. Reference any related issues

### Pull Request Checklist

- [ ] Code follows project guidelines
- [ ] Documentation is updated
- [ ] CHANGELOG.md is updated
- [ ] Commits follow conventional commit format
- [ ] No secrets or sensitive data are committed
- [ ] Manifests are validated (if applicable)

## Security

- **Never commit secrets or sensitive data**
- Use Kubernetes Secrets or external secret management
- Review all manifests for security best practices
- Report security vulnerabilities privately

## Questions?

If you have questions or need help, please:
- Open an issue for discussion
- Check existing documentation
- Review similar implementations in the repository

Thank you for contributing! 🎉
