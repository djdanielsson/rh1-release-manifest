# Release Manifest Tekton Pipelines (Pipelines as Code)

This directory contains **Pipelines as Code (PAC)** definitions for release management.

## Overview

These pipelines follow the standard development process used across the project:

- **Pipelines as Code (PAC)** approach with PipelineRun definitions in `.tekton/`
- **Tekton v1** API (not v1beta1)
- **Reusable tasks** from `cluster-config/tekton-tasks/`
- **Consistent tooling** using `ghcr.io/ansible/community-ansible-dev-tools:v25.9.0`

## Pipelines

| Pipeline | Trigger | Purpose |
|----------|---------|---------|
| `pr-validation.yaml` | Pull Request | Validates manifest YAML syntax, schema, and structure |
| `push-main.yaml` | Push to main | Validates manifests after merge |
| `release-tag.yaml` | Tag push (`YY.M.D-PATCH`) | Creates release manifest with locked versions |
| `promote.yaml` | Manual | Promotes release between environments (dev→qa, qa→prod) |
| `rollback.yaml` | Manual | Rolls back environment to previous release |

## How It Works

### Automatic Triggers

The PAC controller watches for events and triggers pipelines:

```bash
# On PR open/update → pr-validation.yaml runs
# On push to main → push-main.yaml runs
# On tag push (26.1.5-0) → release-tag.yaml runs
```

### Manual Triggers

Promotion and rollback are triggered manually via `tkn` CLI or Tekton Dashboard:

```bash
# Promote dev → qa
tkn pipeline start release-manifest-promote \
  -p version=26.1.5-0 \
  -p from_environment=dev \
  -p to_environment=qa \
  -w name=source,volumeClaimTemplateFile=pvc-template.yaml \
  -w name=aap-config,volumeClaimTemplateFile=pvc-template.yaml

# Rollback qa to previous version
tkn pipeline start release-manifest-rollback \
  -p target_version=26.1.4-0 \
  -p environment=qa \
  -p reason="Bug found in 26.1.5-0" \
  -p dry_run=false \
  -w name=source,volumeClaimTemplateFile=pvc-template.yaml \
  -w name=aap-config,volumeClaimTemplateFile=pvc-template.yaml
```

## Required Secrets

AAP credentials are required for promotion and rollback operations:

```bash
# Managed via ExternalSecrets from HashiCorp Vault
# Secrets are created in the ci-rh1-release-manifest namespace:
#   - aap-dev-credentials
#   - aap-qa-credentials
#   - aap-prod-credentials
```

Each secret contains:
- `host`: AAP controller URL
- `username`: AAP username
- `password`: AAP password

## Version Format

All versions follow **CalVer: YY.M.D-PATCH**

Examples:
- `26.1.5-0` - January 5, 2026, initial release
- `26.1.5-1` - January 5, 2026, first patch
- `26.12.25-0` - December 25, 2026, initial release

## Shared Tasks

These pipelines use shared tasks from `cluster-config/tekton-tasks/`:

| Task | Purpose |
|------|---------|
| `git-clone` | ClusterTask for cloning repositories |
| `git-commit-push` | Commit and push changes |
| `validate-calver-version` | Validate CalVer format |
| `molecule` | Run Molecule tests |
| `ansible-galaxy-collection-build` | Build collections |
| `ansible-galaxy-collection-publish` | Publish collections |

## Migration from Legacy Pipelines

The legacy `tekton/` directory has been superseded by this `.tekton/` PAC approach:

| Legacy | PAC Replacement |
|--------|-----------------|
| `tekton/pipelines/create-release.yaml` | `.tekton/release-tag.yaml` |
| `tekton/pipelines/promote.yaml` | `.tekton/promote.yaml` |
| `tekton/pipelines/rollback.yaml` | `.tekton/rollback.yaml` |
| `tekton/triggers/*` | PAC annotations in PipelineRun metadata |

Key improvements:
- ✅ Uses `tekton.dev/v1` API
- ✅ PAC triggers via annotations (no separate EventListeners)
- ✅ Consistent with other repository CI pipelines
- ✅ Reuses shared tasks
- ✅ Uses `community-ansible-dev-tools` image

## Development

### Testing Locally

```bash
# Validate YAML syntax
yamllint .tekton/

# Check Tekton resources
tkn pipeline list
tkn pipelinerun list
```

### Debugging

```bash
# View pipeline run logs
tkn pipelinerun logs <run-name> -f

# Describe a failed run
tkn pipelinerun describe <run-name>
```

## Integration with cluster-config

These pipelines are deployed via ArgoCD from `cluster-config`:

```yaml
# cluster-config/applications/ci-rh1-release-manifest/kustomization.yaml
resources:
  - ci-rh1-release-manifest-namespace.yml
  - rh1-release-manifest-repository.yml
  - pipeline-serviceaccount.yml
  - aap-credentials-externalsecret.yml
```

The `Repository` resource tells PAC to watch this repo and run pipelines from `.tekton/`.
