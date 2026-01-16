# Release Manifest Tekton Pipelines

This directory contains Pipelines as Code (PAC) definitions for release management.

## Release Process Overview

### Dev Environment
- Uses `main` / `latest` for all resources
- Projects have `scm_update_on_launch: true`
- EE tagged as `:dev`
- No release required - just merge to main

### Creating a Release

1. **Create a release manifest file** in `releases/release-YY.M.D-PATCH.yaml`
2. **Push to main** - triggers `release-create.yaml` pipeline
3. **Pipeline orchestrates**:
   - Tags the playbooks repository with the version
   - Tags the collection repository with the version
   - Updates `galaxy.yml` version and builds the collection
   - Publishes the collection internally
   - Builds the EE with the new collection version
   - Publishes the EE to the registry
   - Updates the release manifest with commit SHAs and digests
   - Updates `config/release-versions.yml` with the new version
   - Updates `config/environments.yml` tracking

### Promoting a Release

1. **Run promote pipeline** manually
2. **Pipeline reads release manifest** to get version mappings
3. **Updates aap-config-as-code files** with the release versions:
   - `scm_branch` → release tag (or `main` for dev)
   - `image` → EE with release tag
   - `scm_update_on_launch` → `false` for qa/prod
4. **Applies config to AAP** for the target environment
5. **Updates tracking** in manifest and `config/environments.yml`

## Pipelines

| Pipeline | Trigger | Purpose |
|----------|---------|---------|
| `pr-validation.yaml` | Pull Request | Validates manifest YAML and schema |
| `push-main.yaml` | Push to main | Validates manifests |
| `release-create.yaml` | Push manifest file | Builds collection, EE, tags repos |
| `promote.yaml` | Manual | Deploys release to environment |
| `rollback.yaml` | Manual | Rolls back to previous release |

## Directory Structure

```
automation-release-manifest/
├── .tekton/                    # Pipelines as Code
│   ├── release-create.yaml     # Build and publish on release
│   ├── promote.yaml            # Deploy to environment
│   └── rollback.yaml           # Rollback
├── config/
│   ├── release-versions.yml    # Current version mappings
│   └── environments.yml        # Environment release tracking
├── releases/
│   ├── release-dev.yaml        # Dev manifest (always HEAD)
│   └── release-26.1.15-0.yaml  # Versioned releases
├── templates/
│   └── release-template.yaml   # Template for new releases
└── schemas/
    └── release-manifest-schema.json
```

## Release Manifest Structure

```yaml
version: "26.1.15-0"
created: "2026-01-15T00:00:00Z"

components:
  playbooks:
    repository: "https://github.com/.../rh1-automation-playbooks.git"
    commit: "abc123..."  # Set by pipeline
    tag: "26.1.15-0"     # Set by pipeline
  collections:
    repository: "https://github.com/.../rh1-custom-collection.git"
    commit: "def456..."  # Set by pipeline
    tag: "26.1.15-0"     # Set by pipeline
  execution_environment:
    registry: "quay.io"
    repository: "myorg/custom-ee"
    tag: "26.1.15-0"     # Set by pipeline
    digest: "sha256:..."  # Set by pipeline

# Maps to aap-config-as-code files
version_mappings:
  jt_plat_configure_webserver:
    project_version: "26.1.15-0"
    ee_version: "26.1.15-0"
  jt_plat_configure_database:
    project_version: "26.1.15-0"
    ee_version: "26.1.15-0"

environments:
  dev:
    deployed: null
  qa:
    deployed: "2026-01-15T10:00:00Z"
  prod:
    deployed: null
```

## aap-config-as-code File Structure

Each `jt_*.yml` file contains EE, Project, and JT definitions:

```yaml
# jt_plat_configure_webserver.yml
controller_execution_environments_plat_configure_webserver:
  - name: "plat_automation_ee"
    image: "quay.io/myorg/custom-ee:26.1.15-0"  # Updated by promote

controller_projects_plat_configure_webserver:
  - name: "plat_webserver_config_playbooks"
    scm_branch: "26.1.15-0"          # Updated by promote
    scm_update_on_launch: false       # false for qa/prod, true for dev

controller_templates_plat_configure_webserver:
  - name: "plat_configure_webserver_{{ env }}"
    project: "plat_webserver_config_playbooks"
    execution_environment: "plat_automation_ee"
```

## Usage

### Create a Release

```bash
# Copy template
cp templates/release-template.yaml releases/release-26.1.16-0.yaml

# Edit and push
git add releases/release-26.1.16-0.yaml
git commit -m "Release 26.1.16-0"
git push origin main

# Pipeline runs automatically
```

### Promote to QA

```bash
tkn pipeline start release-promote \
  -p version=26.1.16-0 \
  -p environment=qa \
  -w name=source,volumeClaimTemplateFile=pvc.yaml \
  -w name=aap-config,volumeClaimTemplateFile=pvc.yaml
```

### Promote to Prod

```bash
tkn pipeline start release-promote \
  -p version=26.1.16-0 \
  -p environment=prod \
  -w name=source,volumeClaimTemplateFile=pvc.yaml \
  -w name=aap-config,volumeClaimTemplateFile=pvc.yaml
```

### Rollback

```bash
tkn pipeline start release-rollback \
  -p target_version=26.1.15-0 \
  -p environment=prod \
  -p reason="Bug in 26.1.16-0"
```

## Required Secrets

```yaml
# AAP credentials per environment
aap-dev-credentials:
  host: https://aap-dev.example.com
  username: admin
  password: <password>

aap-qa-credentials: ...
aap-prod-credentials: ...

# Collection publishing
galaxy-credentials:
  server: https://galaxy.ansible.com
  token: <token>

# EE registry
quay-credentials:
  username: <user>
  password: <password>
```

## Version Format

CalVer: **YY.M.D-PATCH**

- `26.1.15-0` - January 15, 2026, initial release
- `26.1.15-1` - January 15, 2026, first hotfix
- `26.1.16-0` - January 16, 2026, new release
