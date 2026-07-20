#!/bin/bash

# Use this script to update the Tekton Task Bundle references used in a Pipeline or a PipelineRun.
# update-tekton-task-bundles.sh .tekton/*.yaml
# The script is copied and modified from https://konflux-ci.dev/docs/troubleshooting/builds/#manually-update-task-bundles

set -euo pipefail

migrate=${MIGRATE:-false}

function log() {
    echo "${1}" >&2
}

if [[ "${migrate}" == "true" ]]; then
    log "INFO: Enabling task version migration"
else
    log "INFO: Disabling task version migration (set MIGRATE=true to enable)"
fi

# Detect OS and set sed in-place flag accordingly
if [[ "$OSTYPE" == "darwin"* ]]; then
    SED_INPLACE=(-i '')
else
    SED_INPLACE=(-i)
fi

if [[ -z "$*" ]]; then
    log "ERROR: at least one pipeline file is required"
    exit 1
fi

FILES=("$@")

# Find existing image references
OLD_REFS="$(
    yq '... | select(has("resolver")) | .params // [] | .[] | select(.name == "bundle") | .value' "${FILES[@]}" |
        grep -v -- '---' |
        sort -u
)"

# Array to store migration data
migration_data=()

# Find updates for image references
for old_ref in ${OLD_REFS}; do
    log "==="
    log "INFO: Checking reference ${old_ref}"

    repo_tag="${old_ref%@*}"
    repo="${repo_tag%:*}"
    old_tag="${repo_tag##*:}"
    old_digest="${old_ref##*@}"

    log "INFO: Fetching tags for repository ${repo}"
    tags=$(skopeo list-tags "docker://${repo}" | yq '.Tags[]')

    main_tags=$(echo "$tags" | grep -E '^[0-9]+(\.[0-9]+)*$')
    latest_main_tag=$(echo "$main_tags" | sort -V | tail -n1)

    if [[ "$old_tag" != "$latest_main_tag" ]]; then
        task_name=$(basename "${repo}")
        task_name=${task_name#task-}

        # Get new digest for the latest tag
        new_digest=$(skopeo inspect --no-tags "docker://${repo}:${latest_main_tag}" | yq '.Digest')

        # Find which files contain this reference
        for file in "${FILES[@]}"; do
            if [[ -L ${file} ]]; then
                log "INFO: Skipping symlink file ${file}"
                continue
            fi

            log "INFO: Checking pipeline file ${file}"

            if grep -q "${old_ref}" "${file}" 2>/dev/null; then
                if [[ "${migrate}" == "true" ]]; then
                    old_tag=${latest_main_tag}
                fi
                case ${task_name} in
                    init|git-clone*|apply-tags|prefetch-dependencies*|push-dockerfile*|source-build*)
                        task_repo=build-pipeline-tasks;;
                    *fbc*|*opm*|github-sarif-upload|sbom-json-check)
                        task_repo=konflux-operator-tasks;;
                    sast*)
                        task_repo=konflux-sast-tasks;;
                    scan*|deprecated-image-check)
                        task_repo=konflux-test-tasks;;
                    *)
                        task_repo=build-definitions;;
                esac
                # Create JSON object for this migration
                migration_entry=$(
                    cat <<EOF
  {
    "depName": "${repo}",
    "link": "https://github.com/konflux-ci/${task_repo}/tree/main/task/${task_name}",
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

    target_tag=${old_tag}
    if [[ "${migrate}" == "true" ]]; then
        target_tag=${latest_main_tag}
    fi
    new_digest=$(skopeo inspect --no-tags "docker://${repo}:${target_tag}" | yq '.Digest')
    new_ref="${repo}:${target_tag}@${new_digest}"
    if [[ ${old_ref} == "${new_ref}" ]]; then
        log "INFO: Reference is already up-to-date. Continuing."
        continue
    fi
    for file in "${FILES[@]}"; do
        if [[ -L ${file} ]]; then
            log "INFO: skipping symlink file ${file}"
            continue
        fi
        if ! grep -q "${old_ref}" "${file}" 2>/dev/null; then
            log "INFO: skipping file ${file} not containing ${old_ref}"
            continue
        fi
        log "INFO: Updating pipeline file ${file}"
        sed "${SED_INPLACE[@]}" -e "s!${old_ref}!${new_ref}!g" "${file}"
    done
done

# Output migration data in JSON format
if [[ ${#migration_data[@]} -gt 0 ]]; then
    (
        echo "["
        for i in "${!migration_data[@]}"; do
            echo "${migration_data[$i]}"
            if [[ $i -lt $((${#migration_data[@]} - 1)) ]]; then
                echo ","
            fi
        done
        echo "]"
    ) | jq
fi
