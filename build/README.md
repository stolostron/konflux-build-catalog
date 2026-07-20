# Build Scripts

Scripts for generating, validating, and updating custom Tekton tasks in this repository.

| Script | Purpose |
| ------ | ------- |
| [`generate-tasks.sh`](generate-tasks.sh) | Builds task YAML from templates by inlining each step's shell script into the corresponding task definition under `tasks/`. |
| [`validate-tasks.sh`](./validate-tasks.sh) | Checks that every task directory has a matching YAML file and that `metadata.name` matches the directory name. |
| [`update-task-base-image.sh`](./update-task-base-image.sh) | Bumps the digest-pinned base image in each task template to the latest semantic version tag, then regenerates tasks. |
| [`update-task-refs.sh`](./update-task-refs.sh) | Updates git revision SHAs for local task references in a given pipeline file to the latest commit that changed each task. |
| [`migrate-task-versions.sh`](./migrate-task-versions.sh) | Runs Tekton task-bundle updates and applies pipeline migrations via `pipeline-migration-tool` across all files in `pipelines/`. |
