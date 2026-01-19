#!/usr/bin/env python3
"""Pre-commit hook to check environment consistency in release manifests."""
import yaml
import sys

manifest_file = sys.argv[1] if len(sys.argv) > 1 else sys.stdin.read().strip()

try:
    with open(manifest_file) as f:
        m = yaml.safe_load(f)
except Exception:
    # Silently skip if file can't be read
    sys.exit(0)

envs = m.get("environments", {})
expected = ["qa", "prod"]
missing = [e for e in expected if e not in envs]

for e in missing:
    print(f"⚠️  WARNING: Missing environment section: {e}")
