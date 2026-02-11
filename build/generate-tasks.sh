#! /bin/bash

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
task_dir=$(realpath "${script_dir}/../tasks")

for task_dir in "${task_dir}"/*; do
  if [[ ! -d ${task_dir} ]]; then
    continue
  fi

  task_name=$(basename "${task_dir}")
  echo "* Generating task ${task_name}"

  if ! [[ -f "${task_dir}/${task_name}.yaml.template" ]]; then
    echo "error: task template ${task_dir}/${task_name}.yaml.template not found" >&2
    exit 1
  fi

  cp "${task_dir}/${task_name}.yaml.template" "${task_dir}/${task_name}.yaml"

  for step in $(yq '.spec.steps[].name' "${task_dir}/${task_name}.yaml.template"); do
    echo "  - Generating step ${step}"
    step_script=$(cat "${task_dir}/${step}.sh")
    if ! [[ -f "${task_dir}/${step}.sh" ]]; then
      echo "error: step script ${step}.sh not found" >&2
      exit 1
    fi

    step_script=${step_script} yq -i '.spec.steps[] |= select(.name == "'"${step}"'") |= .script = strenv(step_script)' "${task_dir}/${task_name}.yaml"
  done
done
