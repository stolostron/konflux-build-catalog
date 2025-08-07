# Konflux Build Catalog

## Motivation

In the Konflux environment, mintmaker creates "Konflux References Update" PRs for each repository's active release branches. Using the server foundation squad (which owns 10 repositories) as an example, if we set the renovate schedule to run daily, we need to handle 10×5 = 50 PRs (including z stream branches). This takes hours even if we just click the button to merge these PRs. Additionally, if a PR needs a "migration", it takes even more time.

On the other hand, the PipelineSpec of each PipelineRun in the Tekton files across repositories is the same, which means we can put common tasks in one Pipeline and make them reusable.

## Solution

In Tekton, we can use PipelineRef to refer to another Pipeline in a PipelineRun. We can onboard a git repository (konflux-build-catalog) containing the common pipeline to Konflux, and let other repositories refer to the common Pipeline in their Tekton files.

Konflux will only update the digest references in this konflux-build-catalog repository. This can reduce the number of PRs from 50+ to 1 PR every day. As more repositories adopt this common pipeline, the greater the efficiency improvement this approach can deliver.

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
├── .tekton/                     # Konflux configuration for this project
├── .github/workflows/
│   └── update-tekton-task-bundles.yaml  # Workflow to auto-update task bundles
└── update-tekton-task-bundles.sh       # Update script
```

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

### Migration Example

Follow this PR to understand how to update your repository: https://github.com/stolostron/managedcluster-import-controller/pull/730

### Migrated Repositories

The following repositories are already using the common build pipeline:
- cluster-proxy
- cluster-proxy-addon
- managedcluster-import-controller
- ocm
- managed-serviceaccount

## Automatic Update Mechanism

This project includes a daily GitHub Actions workflow (`.github/workflows/update-tekton-task-bundles.yaml`) that:

1. Automatically checks for the latest versions of Tekton task bundles
2. Updates task references in `pipelines/common.yaml` and `pipelines/common_mce_2.10.yaml`
3. Creates a PR if there are updates

You can also manually trigger this workflow to update task bundles immediately.

## Project Self-Validation Mechanism

This project has onboarded itself to Konflux, and its `.tekton` configuration also references its own `common.yaml`:

```yaml
# .tekton/konflux-build-catalog-pull-request.yaml
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

This means:

1. **Every image update PR triggers Konflux checks**: When the automatic update workflow creates a PR, Konflux will run builds using the updated `common.yaml`
2. **Ensures updated pipeline is usable**: Every updated `common.yaml` is validated through the actual build process for its usability
3. **Prevents breaking changes**: If the updated pipeline has issues, the PR checks will fail, preventing the merge of breaking changes

## Maintenance and Contribution

We are looking for squads closer to build and release to co-maintain this repository and enhance it. If you're interested in participating in maintenance, please contact the project maintainers.

## Related Links

- [Jira Issue: ACM-21507](https://issues.redhat.com/browse/ACM-21507)
- [Migration Example PR](https://github.com/stolostron/managedcluster-import-controller/pull/730)
