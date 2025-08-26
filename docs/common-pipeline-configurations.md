# Common Pipeline Special Configurations

This document describes special configuration parameters in the common pipeline that require specific attention or customization for different teams and use cases.

## Table of Contents

- [MCE Version Configuration](#mce-version-configuration)
- [Slack Notification Configuration](#slack-notification-configuration)
- [Package Manager Configuration](#package-manager-configuration)
  - [use-dev-package-managers](#use-dev-package-managers)
- [Symlink Check Configuration](#symlink-check-configuration)
  - [enable-symlink-check](#enable-symlink-check)

## MCE Version Configuration

```yaml
- default: "v2.9.1"
  name: mce-version
  description: The version of the MCE mce-version
```

The `mce-version` parameter is used by certain squads (e.g., Server Foundation squad) as a build argument passed to the build task. This parameter helps ensure compatibility with specific MCE (Multicluster Engine) versions during the build process.

The example: https://github.com/stolostron/ocm/blob/6ee73a6ca83c9b51515c4603e80fb61ea54a6409/build/Dockerfile.registration-operator.rhtap#L7-L11

## Slack Notification Configuration

The common pipeline supports sending Slack notifications when pipeline runs fail.

The example configuration: https://github.com/stolostron/ocm/blob/6ee73a6ca83c9b51515c4603e80fb61ea54a6409/.tekton/registration-operator-mce-29-push.yaml#L36-L41

The example notification: https://redhat-internal.slack.com/archives/C081F071A2E/p1752742340556909

## Package Manager Configuration

### use-dev-package-managers
```yaml
- default: "false"
  name: use-dev-package-managers
  description: Whether to use development package managers
  type: string
```

**Default**: `false`
**Special Use Case**: Global Hub squad requires this parameter to be set to `true` for their specific build requirements.

The example usage: https://github.com/stolostron/multicluster-global-hub/blob/8493875d0e7703d59f2fa47ef669874e7a155769/.tekton/multicluster-global-hub-agent-globalhub-1-6-pull-request.yaml#L45-L46

## Symlink Check Configuration

### enable-symlink-check
```yaml
- default: "true"
  name: enable-symlink-check
  description: Whether to enable symlink checking during build
  type: string
```

**Default**: `true`
**Special Use Case**: Application Lifecycle squad requires this parameter to be set to `false` to disable symlink checking in their build process.

The example usage: https://github.com/stolostron/multicloud-operators-subscription/blob/main/.tekton/multicluster-operators-subscription-acm-215-push.yaml