#!/usr/bin/env bash
#
# verify-release-signatures.sh
# Verify Cosign signatures for release manifests and optional EE image references.
#
# Usage: ./scripts/verify-release-signatures.sh [manifest-file-or-directory]
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
PUBKEY="${COSIGN_PUBKEY_FILE:-}"

error() {
    echo -e "${RED}ERROR: $*${NC}" >&2
    ERRORS=$((ERRORS + 1))
}

success() {
    echo -e "${GREEN}$*${NC}"
}

warning() {
    echo -e "${YELLOW}WARNING: $*${NC}"
}

verify_manifest_file() {
    local manifest="$1"
    local sig="${manifest}.sig"

    if [ ! -f "$manifest" ]; then
        error "Manifest not found: $manifest"
        return
    fi

    if [ ! -f "$sig" ]; then
        warning "No signature file for $manifest (expected $sig)"
        return
    fi

    if ! command -v cosign >/dev/null 2>&1; then
        warning "cosign not installed; skipping signature verification for $manifest"
        return
    fi

    if [ -z "$PUBKEY" ]; then
        warning "COSIGN_PUBKEY_FILE not set; skipping cosign verify-blob for $manifest"
        return
    fi

    if cosign verify-blob --key "$PUBKEY" --signature "$sig" "$manifest"; then
        success "Manifest signature valid: $manifest"
    else
        error "Manifest signature verification failed: $manifest"
    fi
}

main() {
    local target="${1:-releases}"

    if [ -f "$target" ]; then
        verify_manifest_file "$target"
    elif [ -d "$target" ]; then
        for manifest in "$target"/release-*.yml "$target"/release-*.yaml; do
            [ -f "$manifest" ] || continue
            verify_manifest_file "$manifest"
        done
    else
        error "Target not found: $target"
        exit 1
    fi

    if [ "$ERRORS" -gt 0 ]; then
        exit 1
    fi
    success "Signature verification complete"
}

main "$@"
