#!/bin/bash

# Use this script to update the Tekton Task Bundle references used in a Pipeline or a PipelineRun.
# update-tekton-task-bundles.sh .tekton/*.yaml
# The script is copied and modified from https://konflux-ci.dev/docs/troubleshooting/builds/#:~:text=You%20can%20find%20the%20newest,For%20example

set -euo pipefail

# Function to log messages to stderr so they don't interfere with JSON output
log() {
    echo "$@" >&2
}

# Detect OS and set sed in-place flag accordingly
if [[ "$OSTYPE" == "darwin"* ]]; then
  SED_INPLACE=(-i '')
else
  SED_INPLACE=(-i)
fi

FILES=$@

if [ $# -eq 0 ]; then
    log "Usage: $0 <file1> [file2] [file3] ..."
    log "Example: $0 pipelines/common.yaml pipelines/common_mce_2.10.yaml"
    exit 1
fi

log "Processing files: $FILES"

# Find existing image references
OLD_REFS="$(\
    yq '... | select(has("resolver")) | .params // [] | .[] | select(.name == "bundle") | .value'  $FILES | \
    grep -v -- '---' | \
    sort -u \
)"

if [ -z "$OLD_REFS" ]; then
    log "No Tekton task bundle references found in the specified files."
    echo "[]"
    exit 0
fi

log "Found $(echo "$OLD_REFS" | wc -l) unique bundle references"

# Array to store migration data
migration_data=()

# Find updates for image references
for old_ref in ${OLD_REFS}; do
    log "Processing bundle reference: $old_ref"

    repo_tag="${old_ref%@*}"
    repo="${repo_tag%:*}"
    old_tag="${repo_tag##*:}"
    old_digest="${old_ref##*@}"

    log "  Repository: $repo"
    log "  Current tag: $old_tag"

    # Get available tags
    if ! tags=$(skopeo list-tags docker://${repo} 2>/dev/null | yq '.Tags[]' | tr -d '"'); then
        log "  Warning: Failed to fetch tags for $repo, skipping..."
        continue
    fi

    main_tags=$(echo "$tags" | grep -E '^[0-9]+(\.[0-9]+)*$' || true)
    if [ -z "$main_tags" ]; then
        log "  Warning: No semantic version tags found for $repo, skipping..."
        continue
    fi

    latest_main_tag=$(echo "$main_tags" | sort -V | tail -n1)
    log "  Latest available tag: $latest_main_tag"

    if [[ "$old_tag" != "$latest_main_tag" ]]; then
        log "  Migration required: $old_tag → $latest_main_tag"
        task_name=$(basename $repo)
        task_name=${task_name#task-}

        # Get new digest for the latest tag
        if ! new_digest=$(skopeo inspect docker://${repo}:${latest_main_tag} 2>/dev/null | yq '.Digest' | tr -d '"'); then
            log "  Warning: Failed to get digest for ${repo}:${latest_main_tag}, skipping..."
            continue
        fi

        # Find which files contain this reference
        for file in $FILES; do
            if grep -q "$old_ref" "$file" 2>/dev/null; then
                log "    Found in file: $file"
                # Create JSON object for this migration
                migration_entry=$(cat <<EOF
  {
    "depName": "$repo",
    "link": "https://github.com/konflux-ci/build-definitions/tree/main/task/${task_name}",
    "currentValue": "$old_tag",
    "currentDigest": "$old_digest",
    "newValue": "$latest_main_tag",
    "newDigest": "$new_digest",
    "packageFile": "$file",
    "parentDir": ".",
    "depTypes": ["tekton-bundle"]
  }
EOF
)
                migration_data+=("$migration_entry")
            fi
        done
    else
        log "  No migration needed (already at latest version)"
    fi

    # Update digest references (this always happens to ensure we have the latest digest)
    if ! new_digest=$(skopeo inspect docker://${repo}:${old_tag} 2>/dev/null | yq '.Digest' | tr -d '"'); then
        log "  Warning: Failed to get current digest for ${repo}:${old_tag}, skipping digest update..."
        continue
    fi

    new_ref="${repo}:${old_tag}@${new_digest}"
    log "  Updating digest: $old_ref → $new_ref"

    for file in $FILES; do
        if [ -f "$file" ]; then
            sed "${SED_INPLACE[@]}" -e "s!${old_ref}!${new_ref}!g" "$file"
        fi
    done
done

log "Processing complete."

# Output migration data in JSON format
if [ ${#migration_data[@]} -gt 0 ]; then
    log "Found ${#migration_data[@]} migration(s) required."
    echo "["
    for i in "${!migration_data[@]}"; do
        echo "${migration_data[$i]}"
        if [ $i -lt $((${#migration_data[@]} - 1)) ]; then
            echo ","
        fi
    done
    echo "]"
else
    log "No migrations required."
    echo "[]"
fi
