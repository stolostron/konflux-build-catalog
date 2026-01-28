# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a **Konflux Build Catalog** repository that contains Tekton pipeline definitions for multi-arch container image builds. The repository provides standardized CI/CD pipelines for Red Hat's Stolostron project.

## Key Components

### Pipeline Files
The `pipelines/` directory contains standardized Tekton pipeline definitions for different build scenarios and MCE (Multicluster Engine) versions:

**Core Pipelines:**
- `pipelines/common.yaml` - Main multi-arch build pipeline with comprehensive security scanning
- `pipelines/common-oci-ta.yaml` - Single-platform container build pipeline for bundle repositories
- `pipelines/common-fbc.yaml` - File-Based Catalogs (FBC) build pipeline

**MCE Compatibility Symlinks:**
- `pipelines/common_mce_*.yaml` - Symbolic links to `common.yaml` for backward compatibility with existing repository references

### Automation
- `update-tekton-task-bundles.sh` - Updates Tekton task bundle references to latest versions
- `.github/workflows/update-tekton-task-bundles.yaml` - Daily automation for bundle updates
- `.github/workflows/auto-merge-automated-updates.yaml` - Auto-merges successful automated updates

### Container Image
- `Dockerfile` - Minimal container for catalog validation and testing

### Self-Validation
- `.tekton/` directory contains PipelineRun configurations that test pipeline changes automatically
- Each pipeline change triggers corresponding build and Enterprise Contract (EC) checks

## Pipeline Architecture

The pipelines implement a comprehensive container build workflow:

1. **Initialization**: Validate build parameters and determine if build should proceed
2. **Source Management**: Clone repository using OCI artifacts for trusted builds
3. **Dependency Management**: Prefetch dependencies using Cachi2 for hermetic builds
4. **Multi-Platform Build**: Build container images across multiple architectures (x86_64, arm64, ppc64le, s390x)
5. **Image Index**: Create OCI image index for multi-platform manifests
6. **Security Scanning**: Comprehensive security checks including:
   - Clair vulnerability scanning
   - SAST (Snyk, Coverity, Shell, Unicode)
   - Deprecated base image checks
   - RPM signature verification
   - Malware scanning (ClamAV)
7. **Source Image**: Build source images for compliance
8. **Metadata**: Apply tags and push Dockerfile for traceability

## Common Commands

### Update Tekton Task Bundles
```bash
# Update all bundle references to latest versions
bash update-tekton-task-bundles.sh pipelines/common.yaml

# Update multiple pipeline files at once
bash update-tekton-task-bundles.sh pipelines/common.yaml pipelines/common-fbc.yaml

# Check for required migrations (used in CI)
bash update-tekton-task-bundles.sh pipelines/common.yaml > migration_data.json

# Update all pipeline files
bash update-tekton-task-bundles.sh pipelines/*.yaml
```

### Manual Pipeline Updates
```bash
# Edit pipeline definitions
vim pipelines/common.yaml

# Validate YAML syntax for single file
yq eval pipelines/common.yaml > /dev/null

# Validate all pipeline files
for file in pipelines/*.yaml; do yq eval "$file" > /dev/null && echo "$file: OK"; done

# Check pipeline differences
git diff pipelines/
```

### Container Operations
```bash
# Build local container for testing
docker build -t konflux-build-catalog:test .

# Run container to inspect contents
docker run -it konflux-build-catalog:test /bin/bash
```

## Development Workflow

1. **Bundle Updates**: Run `update-tekton-task-bundles.sh` to get latest task versions
2. **Validation**: Changes trigger automated testing via GitHub Actions using `.tekton/` configurations
3. **Automated Updates**: Daily workflow creates PRs for bundle updates and auto-merges successful ones
4. **Review**: All changes require approval from approvers listed in `OWNERS`

## Important Rules

### Pipeline File Management
**CRITICAL**: When adding or changing any file in the `pipelines/` directory, you MUST update the `pipeline_file` matrix list in `.github/workflows/update-tekton-task-bundles.yaml` to include the new/changed pipeline file. This ensures the automated bundle update process covers all pipeline files.

Example: If you add `pipelines/new-pipeline.yaml`, update the workflow matrix:
```yaml
strategy:
  matrix:
    pipeline_file:
      - common.yaml
      - common-fbc.yaml
      - common-oci-ta.yaml
      - new-pipeline.yaml  # Add new files here
```

### Tekton Configuration Synchronization
**CRITICAL**: Files in `.tekton/` directory are linked to specific pipeline files through the `pipelinesascode.tekton.dev/on-cel-expression` annotation. When adding, renaming, or modifying pipeline files, you MUST ensure the corresponding `.tekton` files reference the correct pipeline file paths.

Example CEL expression patterns:
```yaml
# For pipelines/common.yaml
pipelinesascode.tekton.dev/on-cel-expression: event == "pull_request" && target_branch == "main" && ("pipelines/common.yaml".pathChanged() || ".tekton/common-pipeline-pull-request.yaml".pathChanged())

# For pipelines/common-fbc.yaml
pipelinesascode.tekton.dev/on-cel-expression: event == "pull_request" && target_branch == "main" && ("pipelines/common-fbc.yaml".pathChanged() || ".tekton/common-pipeline-fbc-pull-request.yaml".pathChanged())
```

If you rename `pipelines/common.yaml` to `pipelines/new-name.yaml`, update ALL related `.tekton` files to reference the new path in their CEL expressions.

## Pipeline Usage

### Referencing Pipelines in Other Repositories
```yaml
pipelineRef:
  resolver: git
  params:
    - name: url
      value: "https://github.com/stolostron/konflux-build-catalog.git"
    - name: revision
      value: main
    - name: pathInRepo
      value: pipelines/common.yaml  # or common-oci-ta.yaml, common-fbc.yaml
```

### Pipeline Selection Guide
- **Multi-platform builds**: Use `pipelines/common.yaml`
- **Single-platform bundles**: Use `pipelines/common-oci-ta.yaml`
- **File-Based Catalogs**: Use `pipelines/common-fbc.yaml`

Note: MCE version-specific paths (`pipelines/common_mce_X.Y.yaml`) are symlinks to `common.yaml` for backward compatibility.

## Key Technologies
- **Tekton Pipelines** - Kubernetes-native CI/CD
- **Buildah** - Container build tool
- **OCI Artifacts** - Trusted artifact storage
- **Multi-Platform Controller** - Cross-platform builds
- **Security Scanning** - Clair, Snyk, Coverity integration

## Playbook

* How to handle a migration issue: @playbook/how-to-handle-a-migration-issue.md
