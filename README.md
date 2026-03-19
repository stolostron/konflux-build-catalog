# Konflux Build Catalog

## Overview

In the Konflux environment, mintmaker creates "Konflux References Update" PRs for each repository's active release branches. Using the server foundation squad (which owns 10 repositories) as an example, if we set the renovate schedule to run daily, we need to handle 10×5 = 50 PRs (including z stream branches). This takes hours even if we just click the button to merge these PRs, and becomes even more time-consuming when PRs require migrations.

Since the PipelineSpec of each PipelineRun in Tekton files across repositories is essentially the same, we can centralize these common tasks into reusable pipelines. This repository provides common build pipelines that other repositories can reference using Tekton's PipelineRef feature, reducing the maintenance burden from 50+ daily PRs to just 1 PR in this central repository. As more repositories adopt these common pipelines, the efficiency improvement scales significantly.

## Pipelines

This repository contains the following pipelines:

- `pipelines/common.yaml`: The main common build pipeline for multi-platform container images. It aligns with [docker-build-multi-platform-oci-ta pipeline](https://github.com/konflux-ci/build-definitions/tree/main/pipelines/docker-build-multi-platform-oci-ta) and is used by most repositories.
- `pipelines/common-oci-ta.yaml`: A common pipeline for single-platform container image. It aligns with [docker-build-oci-ta pipeline](https://github.com/konflux-ci/build-definitions/tree/main/pipelines/docker-build-oci-ta) and is used by bundle repositories that do not require multi-platform builds, such as `multicluster-global-hub-operator-bundle`.
- `pipelines/common-fbc.yaml`: A common pipeline for FBC (File-Based Catalogs) builds. It aligns with [fbc-builder pipeline](https://github.com/konflux-ci/build-definitions/tree/main/pipelines/fbc-builder) and is used by repositories that build FBCs, such as `multicluster-global-hub-operator-catalog`.

### MCE Version Compatibility

For backward compatibility, MCE version-specific pipeline paths (`pipelines/common_mce_2.X.yaml`) are provided as symbolic links to `pipelines/common.yaml`. Repositories referencing these paths will continue to work without changes.

## Pipeline Architecture

The pipelines implement a comprehensive container build workflow:

1. **Initialization**: Validate build parameters and determine if build should proceed
2. **Source Management**: Clone repository using OCI artifacts for trusted builds
3. **Product Metadata**: Fetch product metadata and generate image labels (see [Automatic Image Label Injection](#automatic-image-label-injection))
4. **Dependency Management**: Prefetch dependencies using Cachi2 for hermetic builds
5. **Multi-Platform Build**: Build container images across multiple architectures (x86_64, arm64, ppc64le, s390x)
6. **Image Index**: Create OCI image index for multi-platform manifests
7. **Security Scanning**: Comprehensive security checks including:
   - Clair vulnerability scanning
   - SAST (Snyk, Coverity, Shell, Unicode)
   - Deprecated base image checks
   - RPM signature verification
   - Malware scanning (ClamAV)
8. **Source Image**: Build source images for compliance
9. **Metadata**: Apply tags and push Dockerfile for traceability

## Automatic Image Label Injection

The `fetch-product-metadata` task automatically generates and injects Red Hat required image labels (`cpe`, `name`, `version`) into container images at build time. **Downstream repositories no longer need to hardcode or manually update these labels in their Dockerfiles.**

### How It Works

The task runs in two steps:

**Step 1 — Parse output image**: Extracts `component`, `product` (acm/mce), and `version` from the Konflux output-image parameter (e.g. `registration-operator-mce-217` → component=`registration-operator`, product=`mce`, version=`2.17`).

**Step 2 — Fetch metadata from bundle repository**: Clones the corresponding bundle repository (`{product}-operator-bundle` at branch `{backplane|release}-{version}`) and extracts:

| Label | Source | Example |
|-------|--------|---------|
| `cpe` | Generated from product, version, and RHEL version | `cpe:/a:redhat:multicluster_engine:2.17::el9` |
| `name` | `config/{product}-manifest-gen-config.json` → `image-namespace/publish-name` | `multicluster-engine/registration-operator-rhel9` |
| `version` | `Z_RELEASE_VERSION` file | `v2.17.1` |

These labels are passed as the `LABELS` parameter to the `buildah-remote-oci-ta` build task, which applies them to the final container image via `--label` flags. Labels injected by the pipeline **override** any same-named labels in the Dockerfile.

### What This Means for Downstream Repositories

**Before** (manual, error-prone):
```dockerfile
# Hardcoded — must be updated every release
LABEL cpe="cpe:/a:redhat:multicluster_engine:2.11::el9"
LABEL name="multicluster-engine/registration-operator-rhel9"
LABEL version="v2.11.0"
```

**After** (automatic):
```dockerfile
# These labels are now injected by the pipeline at build time.
# You can either use empty placeholders or omit them entirely.
LABEL cpe=""
```

Other labels that are **not** auto-injected (e.g., `summary`, `description`, `io.k8s.display-name`, `com.redhat.component`, `io.openshift.tags`) should still be maintained in the Dockerfile as they are component-specific.

### Labels Reference

| Label | Auto-injected? | Where to maintain |
|-------|---------------|-------------------|
| `cpe` | Yes | Pipeline (no action needed) |
| `name` | Yes | Pipeline (no action needed) |
| `version` | Yes | Pipeline (no action needed) |
| `summary` | No | Dockerfile |
| `description` | No | Dockerfile |
| `com.redhat.component` | No | Dockerfile |
| `io.k8s.display-name` | No | Dockerfile |
| `io.k8s.description` | No | Dockerfile |
| `io.openshift.tags` | No | Dockerfile |

## Pipeline Selection Guide

Choose the appropriate pipeline based on your project requirements:

- **Multi-platform builds**: Use `pipelines/common.yaml`
- **Single-platform bundles**: Use `pipelines/common-oci-ta.yaml`
- **File-Based Catalogs**: Use `pipelines/common-fbc.yaml`

## Project Structure

```ini
.
├── pipelines/
│   ├── common.yaml              # Main common build pipeline for multi-platform container images
│   ├── common-fbc.yaml          # Common build pipeline for File-Based Catalogs
│   ├── common-oci-ta.yaml       # Common build pipeline for single-platform container images
│   └── common_mce_*.yaml        # Symlinks to common.yaml for backward compatibility
├── tasks/
│   └── fetch-product-metadata/  # Custom task for auto-generating image labels
├── v4.13/*                       # FBC build files for OpenShift 4.13
├── .tekton/                     # Konflux configuration for this project
│   ├── common-pipeline-*-pull-request.yaml  # PR configurations for all pipelines
│   └── common-pipeline-*-push.yaml          # Push configurations for all pipelines
├── .github/workflows/
│   ├── update-tekton-task-bundles.yaml    # Workflow to auto-update task bundles
│   └── auto-merge-automated-updates.yaml  # Workflow to auto-merge automated updates
└── update-tekton-task-bundles.sh          # Update script
```

## Project Self-Validation Mechanism

The pipelines in this repository are self-testing: the `.tekton/` configuration files reference the pipeline definitions from the `pipelines/` directory. This means every change to a pipeline automatically triggers corresponding build and EC (Enterprise Contract) checks, ensuring that updated pipelines are validated and usable before being merged.

For example, in `.tekton/common-pipeline-pull-request.yaml`:

```yaml
...
# ensure common.yaml is built and tested whenever it changes
    pipelinesascode.tekton.dev/on-cel-expression: event == "pull_request" && target_branch
      == "main" && ("pipelines/common.yaml".pathChanged() || ".tekton/common-pipeline-pull-request.yaml".pathChanged())
...
pipelineRef:
  resolver: git
  params:
    - name: url
      value: "https://github.com/stolostron/konflux-build-catalog.git"
    - name: revision
      value: '{{revision}}' # Uses the commit hash of the PR branch
    - name: pathInRepo
      value: pipelines/common.yaml
```

## Automatic Update Mechanism

This project includes two complementary GitHub Actions workflows for fully automated updates:

### Update Workflow (`.github/workflows/update-tekton-task-bundles.yaml`)

Runs daily at 02:00 UTC and:

1. Automatically checks for the latest versions of Tekton task bundles
2. Updates task references in pipeline files (`common.yaml`, `common-fbc.yaml`, `common-oci-ta.yaml`)
3. Creates a PR with the `automated-update` label if there are updates

### Auto-merge Workflow (`.github/workflows/auto-merge-automated-updates.yaml`)

Runs daily at 04:00 UTC (2 hours after the update workflow) and:

1. Identifies PRs with the `automated-update` label
2. Verifies that all status checks are passing and the PR is mergeable
3. Automatically merges qualifying PRs using squash merge
4. Deletes the merged branch automatically

This two-step process ensures that Tekton task bundle updates are not only created but also automatically merged when all validation checks pass, providing a fully hands-off update experience. You can also manually trigger either workflow as needed.

## How to Migrate to This Pattern

Replace the `pipelineSpec` section to `pipelineRef` in your repository's `.tekton/*.yaml` files with:

```yaml
pipelineRef:
  resolver: git
  params:
    - name: url
      value: "https://github.com/stolostron/konflux-build-catalog.git"
    - name: revision
      value: main
    - name: pathInRepo
      value: pipelines/common.yaml
```

Follow this PR to understand how to update your repository: https://github.com/stolostron/managedcluster-import-controller/pull/730

## Common Commands

### Update Tekton Task Bundles
```bash
# Update all bundle references to latest versions
bash update-tekton-task-bundles.sh pipelines/common.yaml

# Update multiple pipeline files at once
bash update-tekton-task-bundles.sh pipelines/common.yaml pipelines/common-fbc.yaml

# Update all pipeline files
bash update-tekton-task-bundles.sh pipelines/*.yaml
```

### Validate Pipeline YAML
```bash
# Validate YAML syntax for single file
yq eval pipelines/common.yaml > /dev/null

# Validate all pipeline files
for file in pipelines/*.yaml; do yq eval "$file" > /dev/null && echo "$file: OK"; done
```

## Important Rules

### Pipeline File Management
The `pipeline_file` matrix in `.github/workflows/update-tekton-task-bundles.yaml` is dynamically generated from the `pipelines/` directory (excluding symlinks). New pipeline files are automatically picked up by the workflow without manual matrix updates.

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

## Documentation

| Document | Description |
|----------|-------------|
| [docs/common-pipeline-configurations.md](docs/common-pipeline-configurations.md) | Special pipeline configuration parameters |
| [playbook/how-to-handle-a-migration-issue.md](playbook/how-to-handle-a-migration-issue.md) | How to handle a Tekton task migration issue |

## Related Links

- [Jira Issue: ACM-21507](https://issues.redhat.com/browse/ACM-21507)
- [Migration Example PR](https://github.com/stolostron/managedcluster-import-controller/pull/730)

## Key Technologies

- **Tekton Pipelines** - Kubernetes-native CI/CD
- **Buildah** - Container build tool
- **OCI Artifacts** - Trusted artifact storage
- **Multi-Platform Controller** - Cross-platform builds
- **Security Scanning** - Clair, Snyk, Coverity integration
