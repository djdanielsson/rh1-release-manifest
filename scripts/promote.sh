#!/bin/bash
# Trigger promotion pipeline for a release manifest
# Usage: ./promote.sh v1.0.0 qa

set -e

VERSION=$1
ENVIRONMENT=$2

if [ -z "$VERSION" ] || [ -z "$ENVIRONMENT" ]; then
  echo "Usage: $0 <version> <environment>"
  echo "Example: $0 v1.0.0 qa"
  echo ""
  echo "Environments: qa, prod"
  exit 1
fi

if [ "$ENVIRONMENT" != "qa" ] && [ "$ENVIRONMENT" != "prod" ]; then
  echo "Error: Environment must be 'qa' or 'prod'"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST_FILE="$ROOT_DIR/releases/release-$VERSION.yaml"

# Check if manifest exists
if [ ! -f "$MANIFEST_FILE" ]; then
  echo "Error: Manifest not found: $MANIFEST_FILE"
  exit 1
fi

echo "Promoting $VERSION to $ENVIRONMENT..."
echo ""

# Validate manifest
echo "Validating manifest..."
"$SCRIPT_DIR/validate-manifest.sh" "$MANIFEST_FILE"
echo ""

# Check if environment is already deployed
if command -v yq &> /dev/null; then
  DEPLOYED=$(yq eval ".environments.$ENVIRONMENT.deployed" "$MANIFEST_FILE")
  if [ "$DEPLOYED" != "null" ] && [ -n "$DEPLOYED" ]; then
    echo "Warning: $ENVIRONMENT already deployed at: $DEPLOYED"
    read -p "Continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi

  # For prod, check if QA is validated
  if [ "$ENVIRONMENT" == "prod" ]; then
    QA_VALIDATED=$(yq eval ".environments.qa.validated" "$MANIFEST_FILE")
    if [ "$QA_VALIDATED" != "true" ]; then
      echo "Error: Cannot promote to prod - QA not validated"
      exit 1
    fi

    APPROVED_BY=$(yq eval ".validation.approved_by" "$MANIFEST_FILE")
    if [ "$APPROVED_BY" == "null" ] || [ -z "$APPROVED_BY" ]; then
      echo "Error: Cannot promote to prod - not approved"
      exit 1
    fi
  fi
fi

echo "Triggering Tekton promotion pipeline..."
echo ""

# Trigger Tekton pipeline
if command -v tkn &> /dev/null && command -v oc &> /dev/null; then
  tkn pipeline start promotion-pipeline \
    -n dev-tools \
    -p MANIFEST_VERSION="$VERSION" \
    -p TARGET_ENVIRONMENT="$ENVIRONMENT" \
    --use-param-defaults \
    --showlog
else
  echo "Note: tkn or oc command not found"
  echo "To trigger manually:"
  echo ""
  echo "  tkn pipeline start promotion-pipeline \\"
  echo "    -n dev-tools \\"
  echo "    -p MANIFEST_VERSION=\"$VERSION\" \\"
  echo "    -p TARGET_ENVIRONMENT=\"$ENVIRONMENT\" \\"
  echo "    --use-param-defaults \\"
  echo "    --showlog"
fi

echo ""
echo "✓ Promotion initiated for $VERSION to $ENVIRONMENT"

