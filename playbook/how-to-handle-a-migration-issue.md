# How to Handle a Migration Issue

Migration issues are automatically created when the `update-tekton-task-bundles.yaml` GitHub workflow detects Tekton task bundles that require manual intervention due to breaking changes between versions.

## When Migration Issues Occur

Migration issues are created when:
- A Tekton task bundle has a major version update with breaking changes
- The automated update process cannot safely upgrade the bundle version
- Manual review and testing are required before applying the changes

## Example Migration Issue

Reference: https://github.com/stolostron/konflux-build-catalog/issues/76

### Typical Issue Structure:

```markdown
## Tekton Task Bundle Migration Required

The automated Tekton task bundle update process has detected that **1** task bundle(s) require migration to newer versions in **common-oci-ta.yaml**.

### Migration Details:
- **quay.io/konflux-ci/tekton-catalog/task-clamav-scan**: 0.2 → 0.3
  - Link: https://github.com/konflux-ci/build-definitions/tree/main/task/clamav-scan
  - Package File: pipelines/common-oci-ta.yaml

### Action Required:
Please review the migration details above and manually update the task bundles. The automated update process has been halted to prevent potential breaking changes.

### Migration Data (JSON):
[Contains detailed migration information including current/new versions and digests]

### Next Steps:
1. Review the changes required for each task bundle
2. Test the new versions in a development environment
3. Manually update the task bundle references
4. Close this issue once migration is complete
```

## Resolution Steps

1. **Find Migration Documentation**
   - Use the task link from the issue to locate the migration guide
   - Migration docs are typically at: `{task-link}/{new-version}/MIGRATION.md`
   - Example: `https://github.com/konflux-ci/build-definitions/blob/main/task/clamav-scan/0.3/MIGRATION.md`

2. **Review Breaking Changes**
   - Read the migration documentation thoroughly
   - Understand what changes are required in pipeline configurations
   - Identify any parameter changes, removals, or additions

3. **Update Pipeline Files**
   - Apply the required changes to the specified `packageFile`
   - Update task bundle references, parameters, and configurations
   - Ensure all affected pipeline variants are updated consistently

4. **Create Pull Request**
   - Submit a PR with the migration changes
   - Reference the migration issue in the PR description (e.g., "Fixes #76")
   - Include a clear description of changes made

5. **Close Issue**
   - The issue will automatically close when the PR is merged
   - Verify all pipeline files are updated correctly