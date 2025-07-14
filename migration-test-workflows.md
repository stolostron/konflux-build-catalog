# Migration Test Workflows

This document describes the two GitHub Actions workflows designed to automate migration testing and monitoring.

## Overview

The migration test workflows provide automated testing capabilities to validate pipeline configurations and Konflux integrations:

1. **Create Migration Test PR** - Manually triggered workflow to create test PRs
2. **Check Migration Test Status** - Daily automated monitoring of test PR status

## Workflows

### 1. Create Migration Test PR

**File**: `.github/workflows/create-migration-test-pr.yaml`

#### Purpose
Creates a test Pull Request to validate current pipeline configuration and Konflux integration.

#### Trigger
- **Manual only** (`workflow_dispatch`)
- Available in GitHub Actions tab → "Create Migration Test PR" → "Run workflow"

#### Features
- ✅ Creates timestamped test branch
- ✅ Generates test PR with current timestamp
- ✅ Automatically adds `migration-test` label
- ✅ Sets PR to **HOLD** status
- ✅ Creates test documentation file
- ✅ Provides detailed PR description

#### Usage
1. Go to GitHub Actions tab
2. Select "Create Migration Test PR"
3. Click "Run workflow"
4. Optionally provide a test description
5. Wait for PR creation

#### Generated PR Features
- **Title**: `[MIGRATION-TEST] Test PR - YYYY-MM-DD HH:MM:SS UTC`
- **Labels**: `migration-test`, `automated`, `hold`
- **Status**: Automatically placed on hold with `/hold` comment
- **Content**: Test information file in `.migration-test/` directory

### 2. Check Migration Test Status

**File**: `.github/workflows/check-migration-test-status.yaml`

#### Purpose
Daily monitoring of migration test PRs to detect and report check failures.

#### Trigger
- **Scheduled**: Daily at 08:00 UTC
- **Manual**: Available for testing via `workflow_dispatch`

#### Features
- 🔍 Finds all open PRs with `migration-test` label
- ✅ Checks all PR check runs and commit statuses
- 🚨 Identifies failed checks, especially Konflux-related
- 📝 Creates/updates issues for failed PRs
- 📊 Provides detailed failure analysis

#### Monitoring Scope
- **All check runs** on migration test PRs
- **Commit statuses** for comprehensive coverage
- **Konflux-specific checks** (highlighted separately)
- **Tekton pipeline** execution status
- **Build and test** processes

#### Issue Creation
When failures are detected:
- **New Issue**: Created for first-time failures
- **Update Existing**: Comments added to existing failure issues
- **Labels**: `migration-test-failure`, `automated`, `bug`
- **Content**: Detailed failure analysis with links

## Labels Used

| Label | Purpose |
|-------|---------|
| `migration-test` | Identifies test PRs for monitoring |
| `automated` | Marks automated PRs/issues |
| `hold` | Prevents accidental merging of test PRs |
| `migration-test-failure` | Marks issues reporting test failures |
| `bug` | Categorizes failure issues |

## Workflow Integration

### With Existing Workflows
- Compatible with existing `update-tekton-task-bundles.yaml`
- Uses same Konflux pipeline configurations
- Leverages existing Tekton task definitions

### With Konflux
- Tests actual pipeline execution
- Validates current task bundle versions
- Checks integration with build processes
- Monitors multi-platform builds

## Best Practices

### Creating Test PRs
1. **Regular Testing**: Create test PRs before major changes
2. **Descriptive Names**: Use meaningful test descriptions
3. **Monitor Results**: Check PR status after creation
4. **Clean Up**: Close test PRs when no longer needed

### Monitoring Results
1. **Daily Review**: Check for new failure issues
2. **Quick Response**: Address Konflux failures promptly
3. **Root Cause**: Investigate recurring failures
4. **Documentation**: Update configurations based on findings

### Issue Management
1. **Triage**: Review automated failure issues daily
2. **Assignment**: Assign issues to appropriate team members
3. **Resolution**: Fix underlying issues, not just symptoms
4. **Closure**: Close issues when PRs pass or are closed

## Troubleshooting

### Common Issues

#### Test PR Creation Fails
- Check repository permissions
- Verify GitHub token has required scopes
- Ensure branch naming doesn't conflict

#### Status Check Fails
- Verify GitHub API access
- Check PR label accuracy
- Review check run permissions

#### Missing Konflux Checks
- Confirm Konflux integration is active
- Verify pipeline configurations
- Check Tekton task bundle versions

### Manual Intervention

#### Force Check Run
```bash
# Trigger manual status check
gh workflow run check-migration-test-status.yaml
```

#### Create Test PR Manually
```bash
# Alternative manual PR creation
git checkout -b migration-test-manual-$(date +%Y%m%d)
mkdir -p .migration-test
echo "Manual test" > .migration-test/manual-test.txt
git add .migration-test/
git commit -s -m "test: manual migration test"
git push origin migration-test-manual-$(date +%Y%m%d)
```

## Security Considerations

- Uses `GITHUB_TOKEN` with minimal required permissions
- No external API calls or data exposure
- Automated actions are read-only except for issue creation
- All generated content is within repository scope

## Future Enhancements

- Integration with Slack/Teams notifications
- Trend analysis of failure patterns
- Automatic retry of failed checks
- Integration with release processes
