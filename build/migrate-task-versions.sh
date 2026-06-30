#! /usr/bin/env bash

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)

cd "${script_dir}/.." || exit 1

for tool in pipx jq skopeo; do
    if ! command -v ${tool} &>/dev/null; then
        echo "${tool} is not installed. Exiting."
        exit 1
    fi
done

pmt_version=""

if command -v pmt &>/dev/null; then
    pmt_version=$(pipx list --json | jq -r '.venvs["pipeline-migration-tool"].metadata.main_package.package_version // ""')
fi

if [[ ${pmt_version} =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "pipeline-migration-tool version: ${pmt_version}"
    echo "In case of issues, try to update the pipeline-migration-tool using:"
    echo "  pipx upgrade pipeline-migration-tool"
else
    echo "pipeline-migration-tool is not installed. Install it using:"
    echo "  pipx install git+https://github.com/konflux-ci/pipeline-migration-tool"
    exit 1
fi

if ((BASH_VERSINFO[0] < 4)); then
    echo "bash version is less than v4. Direct your PATH to a version v4 or higher."
    exit 1
fi

mapfile -t files < <(find pipelines -type f)

./update-tekton-task-bundles.sh "${files[@]}" >migration_data.json

if [[ ! -s migration_data.json ]]; then
    echo "No migration data found"
    rm migration_data.json || true
    exit 0
fi

pipeline-migration-tool migrate --upgrades-file=migration_data.json

bundles=$(jq -r '.[] | .depName + ":" + .newValue + "@" + .newDigest' migration_data.json | sort -u)

bundles_args=()
for bundle in ${bundles}; do
    bundles_args+=("--new-bundle=${bundle}")
done

file_args=()
for file in "${files[@]}"; do
    file_args+=("--pipeline-file=${file}")
done

pmt migrate "${bundles_args[@]}" "${file_args[@]}"

rm migration_data.json || true
