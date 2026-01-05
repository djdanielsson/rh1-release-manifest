# Ansible Release Manifest Repository

**Purpose**: Version-lock all components for atomic promotion
**Repository**: https://github.com/djdanielsson/rh1-release-manifest.git
**Pattern**: YAML manifests with Git SHAs and image digests

## Overview

This repository contains release manifests that define the exact versions of all components (collections, EE images, AAP configuration) that should be deployed together as a single atomic unit.

**Constitution Compliance**: Article III (Atomic Promotion)

## What is a Release Manifest?

A release manifest is a YAML file that locks the versions of all components in your automation platform:

- **AAP Configuration**: Git commit SHA
- **Ansible Collections**: Git commit SHA
- **Execution Environment**: Container image digest
- **Other Components**: Any additional versioned artifacts

### Why Use Release Manifests?

1. **Atomicity**: All components promoted together, never individually
2. **Reproducibility**: Exact same versions in QA and Prod
3. **Rollback**: Simply revert to previous manifest
4. **Traceability**: Know exactly what's deployed where
5. **Testing**: Test the exact combination that goes to production

## Repository Structure

```
automation-release-manifest/
├── README.md                       # This file
├── .gitignore                      # Git ignore patterns
├── releases/                       # Release manifest files
│   ├── release-dev.yaml            # Dev manifest (always HEAD)
│   └── release-25.01.05.0.yaml     # Versioned releases
├── schemas/                        # JSON schemas
│   └── release-manifest-schema.json
├── templates/                      # Template manifests
│   └── release-template.yaml
├── tekton/                         # Tekton pipelines (primary workflow)
│   ├── kustomization.yaml          # Deploy with: oc apply -k tekton/
│   ├── README.md                   # Tekton usage documentation
│   ├── tasks/
│   │   ├── validate-version.yaml   # Validate YY.MM.DD.PATCH format
│   │   ├── create-manifest.yaml    # Create release manifest
│   │   ├── validate-manifest.yaml  # Validate manifest structure
│   │   ├── promote-environment.yaml # Deploy to environment
│   │   └── rollback.yaml           # Rollback to previous version
│   ├── pipelines/
│   │   ├── create-release.yaml     # Full release creation workflow
│   │   ├── promote.yaml            # Promote between environments
│   │   └── rollback.yaml           # Rollback pipeline
│   └── triggers/
│       └── release-trigger.yaml    # EventListener and templates
└── scripts/                        # Helper scripts (for local use)
    ├── generate-version.sh         # Generate YY.MM.DD.PATCH version
    ├── validate-version.sh         # Validate version format
    ├── create-release-tag.sh       # Create git release tag
    ├── validate-manifest.sh        # Validate manifest format
    ├── validate-manifest-schema.py # Schema validation
    └── promote.sh                  # Promote to environment (legacy)

```

## Manifest Format

### Basic Manifest Structure

```yaml
---
# Release Manifest v1.0.0
version: "1.0.0"
created: "2025-10-29T10:00:00Z"
created_by: "platform-team"
description: "Initial production release"

components:
  # AAP Configuration repository
  aap_configuration:
    repository: "https://github.com/djdanielsson/rh1-aap-config-as-code.git"
    commit: "abc123def456789..."
    branch: "main"

  # Ansible Collection repository
  collections:
    repository: "https://github.com/djdanielsson/rh1-custom-collection.git"
    commit: "def456abc123789..."
    branch: "main"

  # Execution Environment image
  execution_environment:
    registry: "quay.io"
    repository: "myorg/custom-ee"
    tag: "1.0.0"
    digest: "sha256:fedcba987654321..."

environments:
  qa:
    deployed: "2025-10-29T11:00:00Z"
    validated: true
    validated_by: "qa-team"

  prod:
    deployed: null
    validated: false
    validated_by: null

validation:
  tests_passed:
    - smoke-tests
    - integration-tests
    - security-scan
  approval_required: true
  approved_by: null
  approved_at: null
```

## Creating a Release

### 1. Gather Component Versions

```bash
# Get AAP config commit SHA
cd ../aap-config-as-code
AAP_CONFIG_SHA=$(git rev-parse HEAD)

# Get collection commit SHA
cd ../automation-collection-example
COLLECTION_SHA=$(git rev-parse HEAD)

# Get EE image digest
EE_DIGEST=$(podman inspect quay.io/myorg/custom-ee:1.0.0 \
  --format='{{.Digest}}')
```

### 2. Create Manifest File

```bash
# Use the template
cp templates/release-template.yaml releases/release-v1.0.0.yaml

# Edit with actual values
vi releases/release-v1.0.0.yaml
```

### 3. Commit and Tag

```bash
git add releases/release-v1.0.0.yaml
git commit -m "Release v1.0.0: Initial production release"
git tag -a v1.0.0 -m "Release v1.0.0"
git push origin main
git push origin v1.0.0
```

## Tekton Pipelines

All release, promotion, and rollback workflows are implemented as Tekton pipelines in the `tekton/` directory.

### Deploy Pipelines

```bash
# Deploy all Tekton resources to your cluster
oc apply -k tekton/
```

### Create Release Pipeline

Creates a new release manifest by locking component versions:

```bash
tkn pipeline start create-release \
  -p VERSION=25.01.05.0 \
  -p DESCRIPTION="Initial release" \
  -w name=source,volumeClaimTemplateFile=pvc-template.yaml \
  -w name=aap-config-source,volumeClaimTemplateFile=pvc-template.yaml \
  -w name=collection-source,volumeClaimTemplateFile=pvc-template.yaml \
  -w name=shared-data,emptyDir=""
```

### Promote Pipeline

Promotes a validated release from one environment to the next:

```bash
# Dev → QA
tkn pipeline start promote \
  -p VERSION=25.01.05.0 \
  -p FROM_ENVIRONMENT=dev \
  -p TO_ENVIRONMENT=qa \
  -w name=source,volumeClaimTemplateFile=pvc-template.yaml \
  -w name=aap-config,volumeClaimTemplateFile=pvc-template.yaml

# QA → Prod (requires approval)
tkn pipeline start promote \
  -p VERSION=25.01.05.0 \
  -p FROM_ENVIRONMENT=qa \
  -p TO_ENVIRONMENT=prod \
  -w name=source,volumeClaimTemplateFile=pvc-template.yaml \
  -w name=aap-config,volumeClaimTemplateFile=pvc-template.yaml
```

### Rollback Pipeline

Rolls back an environment to a previous release version:

```bash
# Rollback QA
tkn pipeline start rollback \
  -p TARGET_VERSION=25.01.04.0 \
  -p ENVIRONMENT=qa \
  -p REASON="Bug found in 25.01.05.0" \
  -w name=source,volumeClaimTemplateFile=pvc-template.yaml \
  -w name=aap-config,volumeClaimTemplateFile=pvc-template.yaml

# Dry-run mode (validate without applying)
tkn pipeline start rollback \
  -p TARGET_VERSION=25.01.04.0 \
  -p ENVIRONMENT=prod \
  -p DRY_RUN=true \
  -w name=source,volumeClaimTemplateFile=pvc-template.yaml \
  -w name=aap-config,volumeClaimTemplateFile=pvc-template.yaml
```

See `tekton/README.md` for complete documentation

## Workflow Examples

### Standard Promotion Flow

```
1. Dev Testing
   ↓
2. Create Release Manifest (lock versions)
   ↓
3. Promotion Pipeline → QA
   ↓
4. QA Validation
   ↓
5. Update Manifest (mark QA validated)
   ↓
6. Approval Gate
   ↓
7. Promotion Pipeline → Prod
   ↓
8. Update Manifest (mark Prod deployed)
```

### Rollback Flow

```
1. Issue Detected in Prod
   ↓
2. Identify Last Good Manifest (e.g., v1.0.0)
   ↓
3. Run Promotion Pipeline with v1.0.0
   ↓
4. All components rolled back atomically
   ↓
5. Update current manifest (mark as rolled back)
```

## Manifest Lifecycle

### States

1. **Created**: Manifest created, not deployed
2. **QA Deployed**: Deployed to QA environment
3. **QA Validated**: Passed all QA tests
4. **Approved**: Approved for production
5. **Prod Deployed**: Deployed to production
6. **Verified**: Production verification complete
7. **Rolled Back**: Replaced by newer or older manifest

### Transitions

```yaml
# releases/release-v1.0.0.yaml

# Initial state
environments:
  qa:
    deployed: null
    validated: false

# After QA deployment
environments:
  qa:
    deployed: "2025-10-29T11:00:00Z"
    validated: false

# After QA validation
environments:
  qa:
    deployed: "2025-10-29T11:00:00Z"
    validated: true
    validated_by: "qa-team"

validation:
  approved_by: "platform-lead"
  approved_at: "2025-10-29T14:00:00Z"

# After prod deployment
environments:
  qa:
    deployed: "2025-10-29T11:00:00Z"
    validated: true
  prod:
    deployed: "2025-10-29T15:00:00Z"
    validated: true
```

### Rollback Process

Rollback is implemented as a dedicated Tekton pipeline that:

1. Validates the target version exists
2. Extracts component versions from the target manifest
3. Checks out the exact AAP configuration commit
4. Applies configuration to the target environment
5. Records rollback history in the manifest

```bash
# Rollback prod to previous version
tkn pipeline start rollback \
  -p TARGET_VERSION=25.01.04.0 \
  -p ENVIRONMENT=prod \
  -p REASON="Critical bug in 25.01.05.0"
```

See `tekton/pipelines/rollback.yaml` for implementation details.

## Helper Scripts

### Version Management Scripts

#### generate-version.sh

Generates current version in YY.MM.DD.PATCH format:

```bash
#!/bin/bash
# Generate version string in YY.MM.DD.PATCH format

PATCH=${1:-0}
VERSION=$(date +"%y.%m.%d").${PATCH}
echo "${VERSION}"

# Usage:
./scripts/generate-version.sh     # Output: 25.01.05.0
./scripts/generate-version.sh 1   # Output: 25.01.05.1
```

#### validate-version.sh

Validates version format:

```bash
#!/bin/bash
# Validate version string format: YY.MM.DD.PATCH

./scripts/validate-version.sh 25.01.05.0    # ✅ Valid
./scripts/validate-version.sh 25.1.5.0      # ❌ Invalid (missing leading zeros)
```

#### create-release-tag.sh

Interactive tool to create git release tags:

```bash
#!/bin/bash
# Create a release tag with proper format

./scripts/create-release-tag.sh         # Create 25.01.05.0
./scripts/create-release-tag.sh 1       # Create 25.01.05.1 (hotfix)
./scripts/create-release-tag.sh 0 "Release message"
```

### Manifest Creation (Tekton)

The preferred method to create manifests is via the Tekton pipeline:

```bash
tkn pipeline start create-release \
  -p VERSION=25.01.05.0 \
  -p DESCRIPTION="Release description"
```

This pipeline:
1. Validates version format (YY.MM.DD.PATCH)
2. Clones aap-config-as-code and gets HEAD SHA
3. Clones collection repo and gets HEAD SHA
4. Gets EE image digest via skopeo
5. Creates the release manifest YAML
6. Validates manifest structure
7. Commits and tags the release

See `tekton/tasks/create-manifest.yaml` for implementation.

### validate-manifest.sh

```bash
#!/bin/bash
# Validate manifest format

MANIFEST=$1
if [ ! -f "$MANIFEST" ]; then
  echo "Error: Manifest file not found: $MANIFEST"
  exit 1
fi

# Check YAML syntax
yamllint $MANIFEST || exit 1

# Check required fields
REQUIRED_FIELDS=(
  "version"
  "components.aap_configuration.commit"
  "components.collections.commit"
  "components.execution_environment.digest"
)

for field in "${REQUIRED_FIELDS[@]}"; do
  VALUE=$(yq eval ".$field" $MANIFEST)
  if [ "$VALUE" == "null" ] || [ -z "$VALUE" ]; then
    echo "Error: Required field missing: $field"
    exit 1
  fi
done

echo "✓ Manifest validation passed"
```

## Secrets Management

All secrets are managed via **HashiCorp Vault**:

```yaml
# Vault paths for release automation
secret/data/release-manifest:
  github-token: "<token-for-git-operations>"
  
secret/data/aap-dev:
  controller_host: "https://aap-dev.apps.cluster.example.com"
  controller_password: "<from-vault>"
  
secret/data/aap-qa:
  controller_host: "https://aap-qa.apps.cluster.example.com"
  controller_password: "<from-vault>"
  
secret/data/aap-prod:
  controller_host: "https://aap-prod.apps.cluster.example.com"
  controller_password: "<from-vault>"
```

## Best Practices

### 1. CalVer Versioning (YY.MM.DD.PATCH)

This platform uses Calendar Versioning:

```
25.01.05.0 - January 5, 2025, initial release
25.01.05.1 - January 5, 2025, hotfix 1
25.01.06.0 - January 6, 2025, new release
```

See [VERSIONING-STRATEGY.md](../docs/VERSIONING-STRATEGY.md) for complete details.

### 2. Always Use Git SHAs

Never use branch names or tags in manifests, always full commit SHAs:

```yaml
# Good
commit: "abc123def456789012345678901234567890abcd"

# Bad
commit: "main"
commit: "v1.0.0"
```

### 3. Use Image Digests

Always use image digests, not tags:

```yaml
# Good
digest: "sha256:fedcba9876543210..."

# Bad (tags are mutable)
tag: "latest"
```

### 4. Test in QA First

Always deploy to QA and validate before production:

```yaml
validation:
  tests_passed:
    - smoke-tests
    - integration-tests
    - performance-tests
    - security-scan
```

### 5. Require Approval

Require explicit approval for production:

```yaml
validation:
  approval_required: true
  approved_by: "platform-lead"
  approved_at: "2025-10-29T14:00:00Z"
```

## Troubleshooting

### Manifest Parse Error

```bash
# Validate YAML syntax
yamllint releases/release-v1.0.0.yaml

# Check structure
yq eval '.' releases/release-v1.0.0.yaml
```

### Component Not Found

```bash
# Verify Git commit exists
git ls-remote https://github.com/djdanielsson/rh1-aap-config-as-code.git abc123...

# Verify image digest exists
podman manifest inspect quay.io/myorg/custom-ee@sha256:abc123...
```

### Deployment Failed

```bash
# Check pipeline logs
tkn pipelinerun logs promotion-run-xyz -f

# Verify manifest was parsed correctly
oc logs -n dev-tools deployment/manifest-parser
```

## Integration with CI/CD

### Tekton EventListener (Recommended)

Trigger pipelines via HTTP POST to the EventListener:

```bash
# Create a new release
curl -X POST http://el-release-management-listener:8080 \
  -H "Content-Type: application/json" \
  -d '{
    "action": "create-release",
    "version": "25.01.05.0",
    "description": "Initial release"
  }'

# Promote a release
curl -X POST http://el-release-management-listener:8080 \
  -H "Content-Type: application/json" \
  -d '{
    "action": "promote",
    "version": "25.01.05.0",
    "from_environment": "dev",
    "to_environment": "qa"
  }'

# Rollback
curl -X POST http://el-release-management-listener:8080 \
  -H "Content-Type: application/json" \
  -d '{
    "action": "rollback",
    "version": "25.01.04.0",
    "environment": "qa",
    "reason": "Bug found"
  }'
```

### ArgoCD Integration

The Tekton pipelines can be deployed via ArgoCD from the cluster-config repository:

```yaml
# cluster-config/applications/release-management-ci/kustomization.yaml
resources:
  - ../../base/namespace.yaml
  - https://github.com/djdanielsson/rh1-release-manifest//tekton?ref=main
```

## Manifest Versioning Strategy

### Development

```yaml
# releases/release-dev.yaml
# Updated automatically on every merge to main
version: "dev"
components:
  aap_configuration:
    commit: "<latest-main-sha>"
```

### QA/Staging

```yaml
# releases/release-v1.0.0-rc1.yaml
# Release candidates for testing
version: "1.0.0-rc1"
```

### Production

```yaml
# releases/release-v1.0.0.yaml
# Stable, tested, approved releases
version: "1.0.0"
```

## Links

### Related Repositories
- **Cluster Config** (Platform GitOps): https://github.com/djdanielsson/rh1-cluster-config
  - Tekton Pipelines: https://github.com/djdanielsson/rh1-cluster-config/tree/main/tekton/pipelines
- **AAP Config as Code**: https://github.com/djdanielsson/rh1-aap-config-as-code
- **Ansible Collection**: https://github.com/djdanielsson/rh1-custom-collection
- **Execution Environment**: https://github.com/djdanielsson/rh1-custom-ee

### Documentation
- **Project Workspace**: https://github.com/djdanielsson/rh1_ansible_code_lifecycle
- **Project Specs**: https://github.com/djdanielsson/rh1_ansible_code_lifecycle/tree/main/specs/001-cloud-native-ansible-lifecycle
- **Quickstart Guide**: https://github.com/djdanielsson/rh1_ansible_code_lifecycle/blob/main/specs/001-cloud-native-ansible-lifecycle/quickstart.md
- **Constitution**: https://github.com/djdanielsson/rh1_ansible_code_lifecycle/blob/main/.specify/memory/constitution.md

---

**Last Updated**: 2025-10-29
**Maintained By**: Platform Team
**Questions**: File issue in this repository

