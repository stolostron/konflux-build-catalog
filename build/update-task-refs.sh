#! /bin/bash

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
task_dir=$(realpath "${script_dir}/../tasks")
pipeline_file=${1}

# Detect OS and set sed in-place flag accordingly
if [[ ${OSTYPE} == "darwin"* ]]; then
  SED_INPLACE=(-i '')
else
  SED_INPLACE=(-i)
fi

if [[ -z ${pipeline_file} ]]; then
  echo "error: a pipeline file positional argument is required" >&2
  exit 1
fi

if ! [[ -f "${script_dir}/../${pipeline_file}" ]]; then
  echo "error: the provided pipeline file ${pipeline_file} does not exist" >&2
  exit 1
fi

echo "== Updating task references in ${pipeline_file}"

for dir in "${task_dir}"/*; do
  task_name=$(basename "${dir}")
  latest_sha=$(git log --pretty=format:"%H" -1 -- "${task_dir}/${task_name}/${task_name}.yaml")
  current_sha=$(yq '.spec.tasks[] 
    | select(.name == "'"${task_name}"'") 
    | .taskRef.params[] 
    | select(.name == "revision") 
    | .value' "${pipeline_file}")
  if [[ -z ${current_sha} ]]; then
    echo "* Task ${task_name} not found"
    continue
  fi
  if ! (git rev-parse --quiet --verify "${current_sha}^{commit}"); then
    echo "* Skipping task ${task_name} not referencing a SHA: ${current_sha}"
    continue
  fi
  if [[ ${current_sha} == "${latest_sha}" ]]; then
    echo "* Task ${task_name} is already up to date"
    continue
  fi
  echo "x Updating task ${task_name} to ${latest_sha}"
  sed "${SED_INPLACE[@]}" "s/${current_sha}/${latest_sha}/g" "${pipeline_file}"
done
