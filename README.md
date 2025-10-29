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
│   ├── release-v1.0.0.yaml
│   ├── release-v1.1.0.yaml
│   └── release-v2.0.0.yaml
├── templates/                      # Template manifests
│   └── release-template.yaml
└── scripts/                        # Helper scripts
    ├── create-manifest.sh          # Generate new manifest
    ├── validate-manifest.sh        # Validate manifest format
    └── promote.sh                  # Promote to environment

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

## Using Manifests in Pipelines

### Promotion Pipeline

The Tekton promotion pipeline reads the manifest and deploys all components:

```yaml
# Simplified Tekton pipeline
apiVersion: tekton.dev/v1beta1
kind: Pipeline
metadata:
  name: promotion-pipeline
spec:
  params:
    - name: MANIFEST_VERSION
      description: Release manifest version (e.g., v1.0.0)
  
  tasks:
    # 1. Parse manifest
    - name: parse-manifest
      taskRef:
        name: manifest-parser-task
      params:
        - name: MANIFEST_VERSION
          value: $(params.MANIFEST_VERSION)
    
    # 2. Deploy AAP config
    - name: deploy-aap-config
      runAfter: [parse-manifest]
      params:
        - name: COMMIT_SHA
          value: $(tasks.parse-manifest.results.aap-config-sha)
    
    # 3. Build/Deploy EE
    - name: deploy-ee
      runAfter: [parse-manifest]
      params:
        - name: IMAGE_DIGEST
          value: $(tasks.parse-manifest.results.ee-digest)
    
    # 4. Validate
    - name: validate-deployment
      runAfter: [deploy-aap-config, deploy-ee]
```

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

## Helper Scripts

### create-manifest.sh

```bash
#!/bin/bash
# Create a new release manifest

VERSION=$1
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>"
  exit 1
fi

# Get component versions
AAP_CONFIG_SHA=$(cd ../aap-config-as-code && git rev-parse HEAD)
COLLECTION_SHA=$(cd ../automation-collection-example && git rev-parse HEAD)
EE_DIGEST=$(podman inspect quay.io/myorg/custom-ee:latest --format='{{.Digest}}')

# Create manifest from template
cat > releases/release-${VERSION}.yaml <<EOF
---
version: "${VERSION}"
created: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
created_by: "${USER}"
description: "Release ${VERSION}"

components:
  aap_configuration:
    repository: "https://github.com/djdanielsson/rh1-aap-config-as-code.git"
    commit: "${AAP_CONFIG_SHA}"
    branch: "main"
  
  collections:
    repository: "https://github.com/djdanielsson/rh1-custom-collection.git"
    commit: "${COLLECTION_SHA}"
    branch: "main"
  
  execution_environment:
    registry: "quay.io"
    repository: "myorg/custom-ee"
    tag: "${VERSION}"
    digest: "${EE_DIGEST}"

environments:
  qa:
    deployed: null
    validated: false
  prod:
    deployed: null
    validated: false

validation:
  tests_passed: []
  approval_required: true
  approved_by: null
  approved_at: null
EOF

echo "Created releases/release-${VERSION}.yaml"
```

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

## Best Practices

### 1. Semantic Versioning

Follow semantic versioning for manifest versions:

```
v1.0.0 - Major.Minor.Patch
v1.0.1 - Patch: Bug fixes only
v1.1.0 - Minor: New features, backward compatible
v2.0.0 - Major: Breaking changes
```

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

### Automatic Manifest Creation

```yaml
# GitHub Actions example
name: Create Release Manifest
on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Release version (e.g., v1.0.0)'
        required: true

jobs:
  create-manifest:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Create manifest
        run: |
          ./scripts/create-manifest.sh ${{ github.event.inputs.version }}
      
      - name: Commit manifest
        run: |
          git add releases/
          git commit -m "Release ${{ github.event.inputs.version }}"
          git tag ${{ github.event.inputs.version }}
          git push origin main
          git push origin ${{ github.event.inputs.version }}
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

- **Tekton Pipelines**: ../cluster-config/tekton/pipelines/
- **AAP Config**: ../aap-config-as-code/
- **Collections**: ../automation-collection-example/
- **Execution Environment**: ../automation-ee-example/
- **Project Docs**: ../specs/001-cloud-native-ansible-lifecycle/

---

**Last Updated**: 2025-10-29  
**Maintained By**: Platform Team  
**Questions**: File issue in this repository

