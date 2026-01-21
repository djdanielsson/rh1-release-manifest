#!/usr/bin/env bash
#
# validate-manifest.sh
# Validates release manifest files for structure, versions, and production safety
#
# Usage: ./validate-manifest.sh [manifest-file-or-directory]
#   If no argument provided, validates all releases/*.yaml files
#
# Requirements:
#   - python3 with PyYAML module
#   - yq (optional, for enhanced version validation)
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
ERRORS=0
WARNINGS=0

# Helper functions
error() {
    echo -e "${RED}❌ ERROR: $*${NC}" >&2
    ((ERRORS++))
}

warning() {
    echo -e "${YELLOW}⚠️  WARNING: $*${NC}" >&2
    ((WARNINGS++))
}

success() {
    echo -e "${GREEN}✅ $*${NC}"
}

info() {
    echo "ℹ️  $*"
}

# Validate manifest structure using Python
validate_structure() {
    local manifest="$1"
    info "Validating structure of $manifest..."

    local result
    result=$(python3 - "$manifest" <<'PYTHON_EOF'
import sys
try:
    import yaml
except ImportError:
    print("ERROR: PyYAML module not found. Install with: pip install pyyaml")
    sys.exit(2)

manifest_file = sys.argv[1]

try:
    with open(manifest_file) as f:
        m = yaml.safe_load(f)

    if not m:
        print("ERROR: Empty or invalid YAML file")
        sys.exit(1)

    # Check for required top-level fields
    required_fields = ['release_version', 'release_components']
    missing = [f for f in required_fields if f not in m]

    if missing:
        print(f"Missing required fields: {missing}")
        sys.exit(1)

    # Check for required components
    required_components = ['aap_configuration', 'collections', 'execution_environment', 'playbooks']
    components = m.get('release_components', {})
    missing_components = [c for c in required_components if c not in components]

    if missing_components:
        print(f"Missing required components: {missing_components}")
        sys.exit(1)

    print("Structure valid")
except Exception as e:
    print(f"Error: {e}")
    sys.exit(1)
PYTHON_EOF
)
    local exit_code=$?

    if [ $exit_code -eq 2 ]; then
        error "$result"
        error "Python yaml module not installed - skipping structure validation"
        return 0  # Don't fail if dependency is missing
    elif [ $exit_code -eq 0 ]; then
        success "Structure valid for $manifest"
    else
        error "Structure validation failed for $manifest: $result"
        return 1
    fi
}

# Validate version format (semantic versioning)
validate_version_format() {
    local manifest="$1"
    info "Validating version format in $manifest..."

    local version
    if command -v yq &> /dev/null; then
        version=$(yq eval '.release_version' "$manifest" 2>/dev/null || echo "null")
    else
        # Fallback to grep if yq is not available
        version=$(grep -E "^release_version:" "$manifest" | head -1 | sed 's/release_version:[[:space:]]*["'"'"']*\([^"'"'"']*\)["'"'"']*/\1/' | tr -d ' ')
    fi

    if [ "$version" = "null" ] || [ -z "$version" ]; then
        error "No release_version found in $manifest"
        return 1
    fi

    # Version format: YY.M.DD-N (e.g., 26.1.21-1)
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?$ ]]; then
        error "Invalid version format: $version in $manifest"
        error "Expected format: YY.M.DD-N (e.g., 26.1.21-1)"
        return 1
    fi

    success "Valid version: $version"
}

# Check commit SHA format
validate_commit_shas() {
    local manifest="$1"
    info "Checking commit SHAs in $manifest..."

    if grep -E "commit:" "$manifest" | grep -v "^#" > /dev/null; then
        if ! grep -E "commit:\s*\"?[a-f0-9]{40}\"?" "$manifest" > /dev/null; then
            warning "Commit SHAs should be 40 character hex strings in $manifest"
        else
            success "Commit SHAs format valid"
        fi
    else
        info "No commit SHAs found in $manifest"
    fi
}

# Check image digest format
validate_image_digests() {
    local manifest="$1"
    info "Checking image digests in $manifest..."

    if grep -E "digest:" "$manifest" | grep -v "^#" > /dev/null; then
        if ! grep -E "digest:\s*\"?sha256:[a-f0-9]{64}\"?" "$manifest" > /dev/null; then
            warning "Image digests should be sha256:... format in $manifest"
        else
            success "Image digests format valid"
        fi
    else
        info "No image digests found in $manifest"
    fi
}

# Check production safety (no latest/main/master tags)
validate_production_safety() {
    local manifest="$1"
    local filename
    filename=$(basename "$manifest")

    # Only check production/versioned releases
    if [[ "$filename" =~ ^release-v.*\.yaml$ ]] || [[ "$filename" =~ ^release-prod.*\.yaml$ ]]; then
        info "Checking production safety for $manifest..."

        if grep -iE "latest|:main\b|:master\b" "$manifest" | grep -v "^#" | grep -v "branch:" > /dev/null; then
            error "VIOLATION: Cannot use latest/main/master in versioned release: $manifest"
            error "Constitution Article III: Atomic Promotion requires locked versions"
            return 1
        fi

        success "No latest/main/master references found"
    else
        info "Skipping production safety check (not a versioned release)"
    fi
}

# Validate a single manifest file
validate_manifest_file() {
    local manifest="$1"

    if [ ! -f "$manifest" ]; then
        error "File not found: $manifest"
        return 1
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "Validating: $manifest"
    echo "═══════════════════════════════════════════════════════════"

    # Run all validations
    validate_structure "$manifest" || true
    validate_version_format "$manifest" || true
    validate_commit_shas "$manifest" || true
    validate_image_digests "$manifest" || true
    validate_production_safety "$manifest" || true
}

# Check for duplicate versions across all manifests
check_duplicate_versions() {
    local manifest_dir="$1"
    info "Checking for duplicate versions..."

    if ! command -v yq &> /dev/null; then
        warning "yq is not installed - skipping duplicate version check"
        return 0
    fi

    # Use a temporary file to track versions (more portable than associative arrays)
    local temp_file
    temp_file=$(mktemp)
    trap "rm -f $temp_file" EXIT

    local has_duplicates=0

    for manifest in "$manifest_dir"/release-*.yaml "$manifest_dir"/release-*.yml; do
        if [ -f "$manifest" ]; then
            local version
            version=$(yq eval '.release_version' "$manifest" 2>/dev/null || echo "null")
            
            if [ "$version" = "null" ] || [ -z "$version" ]; then
                continue
            fi

            local filename
            filename=$(basename "$manifest")

            # Check if version already exists
            if grep -q "^${version}:" "$temp_file" 2>/dev/null; then
                local first_file
                first_file=$(grep "^${version}:" "$temp_file" | cut -d: -f2-)
                error "Duplicate version found: $version"
                error "  - $first_file"
                error "  - $filename"
                has_duplicates=1
            else
                echo "${version}:${filename}" >> "$temp_file"
            fi
        fi
    done

    if [ $has_duplicates -eq 0 ]; then
        success "No duplicate versions found"
    else
        return 1
    fi
}

# Main execution
main() {
    local target="${1:-releases}"

    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║         Release Manifest Validation Script               ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo ""

    # Check dependencies
    if ! command -v python3 &> /dev/null; then
        error "python3 is not installed"
        exit 1
    fi

    if ! command -v yq &> /dev/null; then
        warning "yq is not installed - version checks will be limited"
    fi

    # Determine what to validate
    if [ -f "$target" ]; then
        # Single file
        validate_manifest_file "$target"
    elif [ -d "$target" ]; then
        # Directory - validate all release manifests
        local found_files=0
        for manifest in "$target"/release-*.yaml "$target"/release-*.yml; do
            if [ -f "$manifest" ]; then
                validate_manifest_file "$manifest"
                found_files=1
            fi
        done

        if [ $found_files -eq 0 ]; then
            error "No release manifest files found in $target"
            exit 1
        fi

        # Check for duplicate versions
        echo ""
        check_duplicate_versions "$target" || true
    else
        error "Target not found: $target"
        exit 1
    fi

    # Summary
    echo ""
    echo "═══════════════════════════════════════════════════════════"
    echo "Validation Summary"
    echo "═══════════════════════════════════════════════════════════"
    echo "Errors:   $ERRORS"
    echo "Warnings: $WARNINGS"
    echo ""

    if [ $ERRORS -gt 0 ]; then
        error "Validation failed with $ERRORS error(s)"
        exit 1
    elif [ $WARNINGS -gt 0 ]; then
        warning "Validation completed with $WARNINGS warning(s)"
        exit 0
    else
        success "All validations passed!"
        exit 0
    fi
}

# Run main function
main "$@"
