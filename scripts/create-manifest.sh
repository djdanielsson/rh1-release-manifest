#!/bin/bash
# Create a new release manifest
# Usage: ./create-manifest.sh v1.0.0

set -e

VERSION=$1
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 v1.0.0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST_FILE="$ROOT_DIR/releases/release-$VERSION.yaml"

# Check if manifest already exists
if [ -f "$MANIFEST_FILE" ]; then
  echo "Error: Manifest already exists: $MANIFEST_FILE"
  exit 1
fi

echo "Creating release manifest for $VERSION..."

# Get component versions
echo "Gathering component versions..."

# AAP Configuration
if [ -d "$ROOT_DIR/../aap-config-as-code" ]; then
  cd "$ROOT_DIR/../aap-config-as-code"
  AAP_CONFIG_SHA=$(git rev-parse HEAD)
  echo "  AAP Config: $AAP_CONFIG_SHA"
else
  echo "Warning: aap-config-as-code directory not found"
  AAP_CONFIG_SHA="REPLACE_WITH_ACTUAL_SHA"
fi

# Collections
if [ -d "$ROOT_DIR/../automation-collection-example" ]; then
  cd "$ROOT_DIR/../automation-collection-example"
  COLLECTION_SHA=$(git rev-parse HEAD)
  echo "  Collections: $COLLECTION_SHA"
else
  echo "Warning: automation-collection-example directory not found"
  COLLECTION_SHA="REPLACE_WITH_ACTUAL_SHA"
fi

# Execution Environment
EE_TAG="${VERSION#v}"  # Remove 'v' prefix
EE_IMAGE="quay.io/myorg/custom-ee:$EE_TAG"

if command -v podman &> /dev/null; then
  if podman inspect "$EE_IMAGE" &> /dev/null; then
    EE_DIGEST=$(podman inspect "$EE_IMAGE" --format='{{.Digest}}')
    echo "  EE Image: $EE_DIGEST"
  else
    echo "Warning: EE image not found locally: $EE_IMAGE"
    EE_DIGEST="REPLACE_WITH_ACTUAL_DIGEST"
  fi
else
  echo "Warning: podman not found, cannot get EE digest"
  EE_DIGEST="REPLACE_WITH_ACTUAL_DIGEST"
fi

# Create manifest from template
cd "$ROOT_DIR"
cat > "$MANIFEST_FILE" <<EOF
---
# Release $VERSION
version: "$VERSION"
created: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
created_by: "${USER}"
description: "Release $VERSION - Add description here"

components:
  aap_configuration:
    repository: "https://github.com/djdanielsson/rh1-aap-config-as-code.git"
    commit: "${AAP_CONFIG_SHA}"
    branch: "main"
    notes: "Add notes about AAP config changes"

  collections:
    repository: "https://github.com/djdanielsson/rh1-custom-collection.git"
    commit: "${COLLECTION_SHA}"
    branch: "main"
    notes: "Add notes about collection changes"

  execution_environment:
    registry: "quay.io"
    repository: "myorg/custom-ee"
    tag: "${EE_TAG}"
    digest: "${EE_DIGEST}"
    notes: "Add notes about EE changes"

environments:
  qa:
    deployed: null
    validated: false
    validated_by: null
    validated_at: null
    notes: ""

  prod:
    deployed: null
    validated: false
    validated_by: null
    validated_at: null
    notes: ""

validation:
  tests_required:
    - smoke-tests
    - integration-tests
    - security-scan

  tests_passed: []

  approval_required: true
  approved_by: null
  approved_at: null
  approval_notes: ""

metadata:
  jira_ticket: ""
  pull_requests: []
  documentation: ""
  rollback_tested: false
  rollback_procedure: ""
  known_issues: []
  workarounds: []
EOF

echo ""
echo "✓ Created: $MANIFEST_FILE"
echo ""
echo "Next steps:"
echo "1. Review and edit the manifest"
echo "2. Update description and notes"
echo "3. Commit: git add releases/ && git commit -m 'Release $VERSION'"
echo "4. Tag: git tag -a $VERSION -m 'Release $VERSION'"
echo "5. Push: git push origin main && git push origin $VERSION"

