#!/usr/bin/env python3
"""Pre-commit hook to validate release manifest structure."""
import yaml
import sys

manifest_file = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read().strip()

try:
    with open(manifest_file) as f:
        m = yaml.safe_load(f)
except Exception as e:
    print(f"❌ Error reading manifest {manifest_file}: {e}")
    sys.exit(1)

errors = []
if "version" not in m:
    errors.append("Missing version")
if "components" not in m:
    errors.append("Missing components")
else:
    if "aap_configuration" not in m["components"]:
        errors.append("Missing aap_configuration")
    if "collections" not in m["components"]:
        errors.append("Missing collections")
    if "execution_environment" not in m["components"]:
        errors.append("Missing execution_environment")

if errors:
    print(f"❌ Invalid manifest: {manifest_file}")
    print("Errors:", ", ".join(errors))
    sys.exit(1)

print(f"✅ Valid manifest: {manifest_file}")
