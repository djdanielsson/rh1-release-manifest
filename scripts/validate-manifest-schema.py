#!/usr/bin/env python3
"""
Validate release manifests against JSON schema.

This script validates Ansible Automation Platform release manifests
against the JSON schema to ensure constitutional compliance and data integrity.

Constitutional Alignment:
- Article III: Atomic Promotion - Validates manifest structure
- Article IV: Production-Grade Quality - Ensures quality standards
- Article V: Zero-Trust Security - Validates security metadata

Usage:
    ./validate-manifest-schema.py <manifest-file>
    ./validate-manifest-schema.py releases/release-v1.0.0.yaml
"""

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List

try:
    import jsonschema
    from jsonschema import validate, ValidationError, SchemaError
except ImportError:
    print("❌ Error: jsonschema package not installed")
    print("Install with: pip install jsonschema")
    sys.exit(1)

try:
    import yaml
except ImportError:
    print("❌ Error: PyYAML package not installed")
    print("Install with: pip install PyYAML")
    sys.exit(1)


class Colors:
    """ANSI color codes for terminal output."""
    GREEN = '\033[92m'
    RED = '\033[91m'
    YELLOW = '\033[93m'
    BLUE = '\033[94m'
    RESET = '\033[0m'
    BOLD = '\033[1m'


def load_schema(schema_path: Path) -> Dict[str, Any]:
    """Load JSON schema from file."""
    try:
        with open(schema_path, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        print(f"{Colors.RED}❌ Schema file not found: {schema_path}{Colors.RESET}")
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"{Colors.RED}❌ Invalid JSON schema: {e}{Colors.RESET}")
        sys.exit(1)


def load_manifest(manifest_path: Path) -> Dict[str, Any]:
    """Load YAML manifest from file."""
    try:
        with open(manifest_path, 'r') as f:
            return yaml.safe_load(f)
    except FileNotFoundError:
        print(f"{Colors.RED}❌ Manifest file not found: {manifest_path}{Colors.RESET}")
        sys.exit(1)
    except yaml.YAMLError as e:
        print(f"{Colors.RED}❌ Invalid YAML manifest: {e}{Colors.RESET}")
        sys.exit(1)


def validate_semantic_version(version: str) -> bool:
    """Validate semantic version format."""
    import re
    pattern = r'^v\d+\.\d+\.\d+(-[a-z0-9]+)?$'
    return bool(re.match(pattern, version))


def validate_commit_sha(sha: str) -> bool:
    """Validate Git commit SHA format."""
    import re
    pattern = r'^[a-f0-9]{40}$'
    return bool(re.match(pattern, sha))


def validate_image_digest(digest: str) -> bool:
    """Validate container image digest format."""
    import re
    pattern = r'^sha256:[a-f0-9]{64}$'
    return bool(re.match(pattern, digest))


def additional_validations(manifest: Dict[str, Any]) -> List[str]:
    """
    Perform additional validations beyond JSON schema.
    
    Constitutional Compliance:
    - Ensures all components have proper versioning
    - Validates security scan results for production
    - Checks approval requirements
    """
    warnings = []
    
    # Check environment-specific requirements
    environment = manifest.get('metadata', {}).get('environment', '')
    
    # Production-specific validations (Article IV: Production-Grade Quality)
    if environment == 'prod':
        spec = manifest.get('spec', {})
        
        # Check for security scan
        if 'securityScan' not in spec:
            warnings.append("⚠️  Production release missing security scan results")
        elif not spec['securityScan'].get('passed', False):
            warnings.append("⚠️  Production release has failing security scan")
        
        # Check for approvals (Article II: Separation of Duties)
        if 'approvals' not in spec or len(spec['approvals']) == 0:
            warnings.append("⚠️  Production release missing approvals")
        
        # Check for test results
        if 'tests' not in spec:
            warnings.append("⚠️  Production release missing test results")
        elif not spec['tests'].get('passed', False):
            warnings.append("⚠️  Production release has failing tests")
    
    # Validate component versions
    for component in manifest.get('spec', {}).get('components', []):
        version = component.get('version', '')
        if version and not validate_semantic_version(version):
            warnings.append(
                f"⚠️  Component '{component.get('name')}' has invalid "
                f"semantic version: {version}"
            )
        
        # Validate commit SHA if present
        commit_sha = component.get('commitSha', '')
        if commit_sha and not validate_commit_sha(commit_sha):
            warnings.append(
                f"⚠️  Component '{component.get('name')}' has invalid "
                f"commit SHA: {commit_sha}"
            )
        
        # Validate image digest if present (for EEs)
        image_digest = component.get('imageDigest', '')
        if image_digest and not validate_image_digest(image_digest):
            warnings.append(
                f"⚠️  Component '{component.get('name')}' has invalid "
                f"image digest: {image_digest}"
            )
    
    # Check for rollback target in production
    if environment == 'prod':
        if 'rollbackTarget' not in manifest.get('spec', {}):
            warnings.append(
                "⚠️  Production release should specify rollbackTarget"
            )
    
    return warnings


def validate_manifest_file(manifest_path: Path, schema_path: Path, verbose: bool = False) -> bool:
    """
    Validate a manifest file against the schema.
    
    Returns:
        True if validation passes, False otherwise
    """
    print(f"\n{Colors.BLUE}{Colors.BOLD}🔍 Validating Release Manifest{Colors.RESET}")
    print(f"Manifest: {manifest_path}")
    print(f"Schema:   {schema_path}")
    print()
    
    # Load schema and manifest
    schema = load_schema(schema_path)
    manifest = load_manifest(manifest_path)
    
    if verbose:
        print(f"{Colors.BLUE}Manifest content:{Colors.RESET}")
        print(yaml.dump(manifest, default_flow_style=False))
        print()
    
    # Validate against JSON schema
    try:
        validate(instance=manifest, schema=schema)
        print(f"{Colors.GREEN}✅ Schema validation passed{Colors.RESET}")
    except ValidationError as e:
        print(f"{Colors.RED}❌ Schema validation failed:{Colors.RESET}")
        print(f"   {e.message}")
        if e.path:
            print(f"   Path: {' -> '.join(str(p) for p in e.path)}")
        if verbose:
            print(f"\n{Colors.YELLOW}Full error:{Colors.RESET}")
            print(e)
        return False
    except SchemaError as e:
        print(f"{Colors.RED}❌ Schema itself is invalid:{Colors.RESET}")
        print(f"   {e.message}")
        return False
    
    # Perform additional validations
    warnings = additional_validations(manifest)
    if warnings:
        print(f"\n{Colors.YELLOW}⚠️  Additional warnings:{Colors.RESET}")
        for warning in warnings:
            print(f"   {warning}")
    
    # Summary
    print(f"\n{Colors.GREEN}{Colors.BOLD}✅ Validation complete!{Colors.RESET}")
    print(f"Environment: {manifest.get('metadata', {}).get('environment', 'unknown')}")
    print(f"Version:     {manifest.get('metadata', {}).get('version', 'unknown')}")
    print(f"Components:  {len(manifest.get('spec', {}).get('components', []))}")
    
    if warnings:
        print(f"\n{Colors.YELLOW}Note: Warnings do not fail validation but should be reviewed.{Colors.RESET}")
    
    return True


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Validate Ansible Automation Platform release manifest',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s releases/release-v1.0.0.yaml
  %(prog)s releases/release-dev.yaml --verbose
  %(prog)s releases/release-prod.yaml --schema custom-schema.json
        """
    )
    parser.add_argument(
        'manifest',
        type=Path,
        help='Path to release manifest YAML file'
    )
    parser.add_argument(
        '--schema',
        type=Path,
        default=Path(__file__).parent.parent / 'schemas' / 'release-manifest-schema.json',
        help='Path to JSON schema file (default: schemas/release-manifest-schema.json)'
    )
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Enable verbose output'
    )
    
    args = parser.parse_args()
    
    # Validate manifest
    success = validate_manifest_file(args.manifest, args.schema, args.verbose)
    
    sys.exit(0 if success else 1)


if __name__ == '__main__':
    main()

