#!/bin/bash
# Validate release manifest format and required fields
# Usage: ./validate-manifest.sh releases/release-v1.0.0.yaml

set -e

MANIFEST=$1
if [ -z "$MANIFEST" ]; then
  echo "Usage: $0 <manifest-file>"
  echo "Example: $0 releases/release-v1.0.0.yaml"
  exit 1
fi

if [ ! -f "$MANIFEST" ]; then
  echo "Error: Manifest file not found: $MANIFEST"
  exit 1
fi

echo "Validating manifest: $MANIFEST"
echo ""

# Check if required tools are available
if ! command -v yq &> /dev/null; then
  echo "Warning: yq not found, skipping detailed validation"
  echo "Install with: pip install yq"
  SKIP_YQ=true
fi

# Check YAML syntax
echo "Checking YAML syntax..."
if command -v yamllint &> /dev/null; then
  if yamllint "$MANIFEST"; then
    echo "✓ YAML syntax valid"
  else
    echo "✗ YAML syntax invalid"
    exit 1
  fi
else
  echo "Warning: yamllint not found, skipping YAML validation"
fi
echo ""

# Check required fields
if [ "$SKIP_YQ" != "true" ]; then
  echo "Checking required fields..."

  REQUIRED_FIELDS=(
    ".version"
    ".components.aap_configuration.commit"
    ".components.collections.commit"
    ".components.execution_environment.digest"
  )

  ALL_VALID=true
  for field in "${REQUIRED_FIELDS[@]}"; do
    VALUE=$(yq eval "$field" "$MANIFEST")
    if [ "$VALUE" == "null" ] || [ -z "$VALUE" ] || [ "$VALUE" == "REPLACE_WITH_ACTUAL_SHA" ] || [ "$VALUE" == "REPLACE_WITH_ACTUAL_DIGEST" ]; then
      echo "✗ Required field missing or needs replacement: $field"
      ALL_VALID=false
    else
      echo "✓ $field: ${VALUE:0:40}..."
    fi
  done

  if [ "$ALL_VALID" = false ]; then
    echo ""
    echo "✗ Validation failed - please update manifest"
    exit 1
  fi
fi

echo ""
echo "✓ Manifest validation passed"
echo ""

# Display summary
if [ "$SKIP_YQ" != "true" ]; then
  VERSION=$(yq eval '.version' "$MANIFEST")
  AAP_SHA=$(yq eval '.components.aap_configuration.commit' "$MANIFEST" | cut -c1-8)
  COL_SHA=$(yq eval '.components.collections.commit' "$MANIFEST" | cut -c1-8)
  EE_TAG=$(yq eval '.components.execution_environment.tag' "$MANIFEST")

  echo "Release Summary:"
  echo "  Version: $VERSION"
  echo "  AAP Config: $AAP_SHA"
  echo "  Collections: $COL_SHA"
  echo "  EE Tag: $EE_TAG"
fi

