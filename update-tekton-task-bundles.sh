#!/bin/bash

# Use this script to update the Tekton Task Bundle references used in a Pipeline or a PipelineRun.
# update-tekton-task-bundles.sh .tekton/*.yaml
# The script is copied and modified from https://konflux-ci.dev/docs/troubleshooting/builds/#manually-update-task-bundles

set -euo pipefail

# Detect OS and set sed in-place flag accordingly
if [[ "$OSTYPE" == "darwin"* ]]; then
  SED_INPLACE=(-i '')
else
  SED_INPLACE=(-i)
fi

FILES=( "$@" )

# Find existing image references
OLD_REFS="$(\
    yq '... | select(has("resolver")) | .params // [] | .[] | select(.name == "bundle") | .value'  "${FILES[@]}" | \
    grep -v -- '---' | \
    sort -u \
)"

# Array to store migration data
migration_data=()

# Find updates for image references
for old_ref in ${OLD_REFS}; do
    repo_tag="${old_ref%@*}"
    repo="${repo_tag%:*}"
    old_tag="${repo_tag##*:}"
    old_digest="${old_ref##*@}"

    tags=$(skopeo list-tags "docker://${repo}" | yq '.Tags[]' | tr -d '"')

    main_tags=$(echo "$tags" | grep -E '^[0-9]+(\.[0-9]+)*$')
    latest_main_tag=$(echo "$main_tags" | sort -V | tail -n1)

    if [[ "$old_tag" != "$latest_main_tag" ]]; then
        task_name=$(basename "${repo}")
        task_name=${task_name#task-}

        # Get new digest for the latest tag
        new_digest=$(skopeo inspect "docker://${repo}:${latest_main_tag}" | yq '.Digest' | tr -d '"')

        # Find which files contain this reference
        for file in "${FILES[@]}"; do
            if grep -q "${old_ref}" "${file}" 2>/dev/null; then
                # Create JSON object for this migration
                migration_entry=$(cat <<EOF
  {
    "depName": "${repo}",
    "link": "https://github.com/konflux-ci/build-definitions/tree/main/task/${task_name}",
    "currentValue": "${old_tag}",
    "currentDigest": "${old_digest}",
    "newValue": "${latest_main_tag}",
    "newDigest": "${new_digest}",
    "packageFile": "${file}",
    "parentDir": ".",
    "depTypes": ["tekton-bundle"]
  }
EOF
)
                migration_data+=("$migration_entry")
            fi
        done
    fi

    new_digest=$(skopeo inspect "docker://${repo}:${old_tag}" | yq '.Digest')
    new_ref="${repo}:${old_tag}@${new_digest}"
    for file in "${FILES[@]}"; do
        sed "${SED_INPLACE[@]}" -e "s!${old_ref}!${new_ref}!g" "$file"
    done
done

# Output migration data in JSON format
if [[ ${#migration_data[@]} -gt 0 ]]; then
    echo "["
    for i in "${!migration_data[@]}"; do
        echo "${migration_data[$i]}"
        if [[ $i -lt $((${#migration_data[@]} - 1)) ]]; then
            echo ","
        fi
    done
    echo "]"
fi
