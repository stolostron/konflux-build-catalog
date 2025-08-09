# Konflux Build Catalog

## Overview

In the Konflux environment, mintmaker creates "Konflux References Update" PRs for each repository's active release branches. Using the server foundation squad (which owns 10 repositories) as an example, if we set the renovate schedule to run daily, we need to handle 10×5 = 50 PRs (including z stream branches). This takes hours even if we just click the button to merge these PRs, and becomes even more time-consuming when PRs require migrations.

Since the PipelineSpec of each PipelineRun in Tekton files across repositories is essentially the same, we can centralize these common tasks into reusable pipelines. This repository provides common build pipelines that other repositories can reference using Tekton's PipelineRef feature, reducing the maintenance burden from 50+ daily PRs to just 1 PR in this central repository. As more repositories adopt these common pipelines, the efficiency improvement scales significantly.

## Pipelines

This repository contains the following pipelines:
- `pipelines/common.yaml`: The main common build pipeline for multi-platform container images. It aligns with [docker-build-multi-platform-oci-ta pipeline](https://github.com/konflux-ci/build-definitions/tree/main/pipelines/docker-build-multi-platform-oci-ta) and is used by most repositories.

- `pipelines/common-oci-ta.yaml`: A common pipeline for single-platform container image. It aligns with [docker-build-oci-ta pipeline](https://github.com/konflux-ci/build-definitions/tree/main/pipelines/docker-build-oci-ta) and is used by bundle repositories that do not require multi-platform builds, such as `multicluster-global-hub-operator-bundle`.

- `pipelines/common-fbc.yaml`: A common pipeline for FBC (File-Based Catalogs) builds. It aligns with [fbc-builder pipeline](https://github.com/konflux-ci/build-definitions/tree/main/pipelines/fbc-builder) and is used by repositories that build FBCs, such as `multicluster-global-hub-operator-catalog`.

## Project Structure

```
.
├── pipelines/
│   ├── common.yaml              # Main common build pipeline to a multi-platform container image
│   ├── common-fbc.yaml          # Main common build pipeline to a file-based catalogs image
│   ├── common-oci-ta.yaml       # Main common build pipeline to a single-platform container image
│   └── common_mce_2.10.yaml     # Common pipeline for MCE 2.10
├── v4.13/*                       # FBC build files for OpenShift 4.13
├── .tekton/                     # Konflux configuration for this project
├── .github/workflows/
│   └── update-tekton-task-bundles.yaml    # Workflow to auto-update task bundles
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
2. Updates task references in `pipelines/common.yaml` and `pipelines/common_mce_2.10.yaml`
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
      value: pipelines/common.yaml # or pipelines/common_mce_2.10.yaml for MCE 2.10 branches
```

Follow this PR to understand how to update your repository: https://github.com/stolostron/managedcluster-import-controller/pull/730

## Related Links

- [Jira Issue: ACM-21507](https://issues.redhat.com/browse/ACM-21507)
- [Migration Example PR](https://github.com/stolostron/managedcluster-import-controller/pull/730)
