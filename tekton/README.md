# Release Management Tekton Pipelines

Tekton pipelines for managing releases, promotions, and rollbacks.

## Structure

```
tekton/
├── kustomization.yaml          # Deploy all resources with: oc apply -k .
├── tasks/
│   ├── validate-version.yaml   # Validate YY.MM.DD.PATCH format
│   ├── create-manifest.yaml    # Create release manifest file
│   ├── validate-manifest.yaml  # Validate manifest structure
│   ├── promote-environment.yaml # Deploy to an environment
│   └── rollback.yaml           # Rollback task
├── pipelines/
│   ├── create-release.yaml     # Full release creation workflow
│   ├── promote.yaml            # Promote between environments
│   └── rollback.yaml           # Rollback pipeline
└── triggers/
    └── release-trigger.yaml    # EventListener and templates
```

## Prerequisites

- OpenShift Pipelines (Tekton) operator installed
- `git-clone` ClusterTask available
- AAP credentials secrets configured per environment

### Required Secrets

Create secrets for each environment:

```bash
# Dev environment
oc create secret generic aap-dev-credentials \
  --from-literal=host=https://aap-dev.example.com \
  --from-literal=username=admin \
  --from-literal=password=<password>

# QA environment
oc create secret generic aap-qa-credentials \
  --from-literal=host=https://aap-qa.example.com \
  --from-literal=username=admin \
  --from-literal=password=<password>

# Prod environment
oc create secret generic aap-prod-credentials \
  --from-literal=host=https://aap-prod.example.com \
  --from-literal=username=admin \
  --from-literal=password=<password>
```

## Deployment

```bash
# Deploy all pipelines and tasks
oc apply -k tekton/

# Or deploy individually
oc apply -f tekton/tasks/
oc apply -f tekton/pipelines/
oc apply -f tekton/triggers/
```

## Usage

### Create a Release

```bash
# Using tkn CLI
tkn pipeline start create-release \
  -p VERSION=25.01.05.0 \
  -p DESCRIPTION="Initial release" \
  -w name=source,volumeClaimTemplateFile=pvc-template.yaml \
  -w name=aap-config-source,volumeClaimTemplateFile=pvc-template.yaml \
  -w name=collection-source,volumeClaimTemplateFile=pvc-template.yaml \
  -w name=shared-data,emptyDir=""

# Using EventListener (HTTP POST)
curl -X POST http://el-release-management-listener:8080 \
  -H "Content-Type: application/json" \
  -d '{
    "action": "create-release",
    "version": "25.01.05.0",
    "description": "Initial release"
  }'
```

### Promote a Release

```bash
# Dev → QA
tkn pipeline start promote \
  -p VERSION=25.01.05.0 \
  -p FROM_ENVIRONMENT=dev \
  -p TO_ENVIRONMENT=qa \
  -w name=source,volumeClaimTemplateFile=pvc-template.yaml \
  -w name=aap-config,volumeClaimTemplateFile=pvc-template.yaml

# QA → Prod
tkn pipeline start promote \
  -p VERSION=25.01.05.0 \
  -p FROM_ENVIRONMENT=qa \
  -p TO_ENVIRONMENT=prod \
  -w name=source,volumeClaimTemplateFile=pvc-template.yaml \
  -w name=aap-config,volumeClaimTemplateFile=pvc-template.yaml
```

### Rollback

```bash
# Rollback QA to a previous version
tkn pipeline start rollback \
  -p TARGET_VERSION=25.01.04.0 \
  -p ENVIRONMENT=qa \
  -p REASON="Bug found in 25.01.05.0" \
  -w name=source,volumeClaimTemplateFile=pvc-template.yaml \
  -w name=aap-config,volumeClaimTemplateFile=pvc-template.yaml

# Dry-run (validate without applying)
tkn pipeline start rollback \
  -p TARGET_VERSION=25.01.04.0 \
  -p ENVIRONMENT=prod \
  -p DRY_RUN=true \
  -w name=source,volumeClaimTemplateFile=pvc-template.yaml \
  -w name=aap-config,volumeClaimTemplateFile=pvc-template.yaml
```

## Pipeline Details

### create-release Pipeline

1. **validate-version**: Validates YY.MM.DD.PATCH format
2. **get-aap-commit**: Clones aap-config-as-code and gets HEAD SHA
3. **get-collection-commit**: Clones collection repo and gets HEAD SHA
4. **get-ee-digest**: Gets EE image digest via skopeo
5. **create-manifest**: Creates the release manifest YAML
6. **validate-manifest**: Validates manifest structure
7. **commit-and-push**: Commits and tags the release

### promote Pipeline

1. **validate-promotion-path**: Ensures valid path (dev→qa or qa→prod)
2. **check-source-deployment**: Verifies release was deployed to source env
3. **require-prod-approval**: Gate for production promotions
4. **deploy**: Applies configuration to target environment
5. **commit-promotion**: Records promotion in manifest

### rollback Pipeline

1. **validate-version**: Validates target version format
2. **validate-environment**: Ensures valid environment
3. **check-manifest-exists**: Verifies target manifest exists
4. **rollback**: Applies previous configuration
5. **commit-rollback**: Records rollback history in manifest

## Version Format

All versions follow **CalVer: YY.MM.DD.PATCH**

Examples:
- `25.01.05.0` - January 5, 2025, initial release
- `25.01.05.1` - January 5, 2025, first patch
- `25.01.06.0` - January 6, 2025, new day's release

## Integration with cluster-config

These pipelines are designed to be deployed via ArgoCD from the `cluster-config` repository:

```yaml
# cluster-config/applications/release-management-ci/kustomization.yaml
resources:
  - ../../base/namespace.yaml
  - https://github.com/djdanielsson/rh1-release-manifest//tekton?ref=main
```

