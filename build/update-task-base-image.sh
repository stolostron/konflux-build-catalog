#! /bin/bash

set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
task_dir=$(realpath "${script_dir}/../tasks")

# Detect OS and set sed in-place flag accordingly
if [[ "$OSTYPE" == "darwin"* ]]; then
  SED_INPLACE=(-i '')
else
  SED_INPLACE=(-i)
fi

for dir in "${task_dir}"/*; do
  if [[ ! -d ${dir} ]]; then
    continue
  fi

  task_name=$(basename "${dir}")
  echo "* Updating task ${task_name}"

  if ! [[ -f "${dir}/${task_name}.yaml.template" ]]; then
    echo "error: task template ${dir}/${task_name}.yaml.template not found" >&2
    exit 1
  fi

  base_image=$(yq -e '.spec.stepTemplate.image' "${task_dir}/${task_name}/${task_name}.yaml.template")
  echo "  - Base image: ${base_image}"
  image_and_tag=${base_image%@sha256:*}
  image_tag=${image_and_tag##*:}
  image_repo=${image_and_tag%:*}

  # Validate image format contains both tag and digest
  if [[ ! ${base_image} =~ @sha256: ]]; then
    echo "ERROR: Base image does not contain digest pinning" >&2
    exit 1
  fi

  if [[ -z ${image_and_tag} ]]; then
    echo "ERROR: failed to parse image and tag from ${base_image}" >&2
    exit 1
  fi

  if [[ -z ${image_repo} || -z ${image_tag} ]]; then
    echo "ERROR: failed to parse image repo or tag from ${base_image}" >&2
    exit 1
  fi

  latest_version_tag=$(skopeo list-tags "docker://${image_repo}" | yq '.Tags[]' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort --version-sort | tail -n 1 || true)

  if [[ -z ${latest_version_tag} ]]; then
    echo "ERROR: failed to fetch latest version tag for ${image_repo}" >&2
    exit 1
  fi

  if [[ ${image_tag} == "${latest_version_tag}" ]]; then
    echo "  - Tag ${image_tag} is up-to-date"
    continue
  else
    echo "  - Updating tag ${image_tag} to ${latest_version_tag}"
  fi

  latest_version_digest=$(skopeo inspect --override-os linux --override-arch amd64 "docker://${image_repo}:${latest_version_tag}" | yq '.Digest')
  if [[ -z ${latest_version_digest} || ! ${latest_version_digest} =~ ^sha256: ]]; then
    echo "ERROR: failed to fetch digest for ${image_repo}:${latest_version_tag}" >&2
    exit 1
  fi

  new_image="${image_repo}:${latest_version_tag}@${latest_version_digest}"
  echo "  - New image: ${new_image}"
  sed "${SED_INPLACE[@]}" -e "s!${base_image}!${new_image}!g" "${task_dir}/${task_name}/${task_name}.yaml.template"
done

"${script_dir}/generate-tasks.sh"
