#! /bin/bash

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
task_dir=$(realpath "${script_dir}/../tasks")
exit_code=0

echo "== Validating tasks"

for dir in "${task_dir}"/*; do
  task_name=$(basename "${dir}")

  if ! [[ -f $dir/${task_name}.yaml ]]; then
    echo "❌ YAML file for task ${task_name} not found"
    exit_code=1
    continue
  fi

  yaml_name=$(yq '.metadata.name' "${dir}/${task_name}.yaml")
  if [[ ${task_name} != "${yaml_name}" ]]; then
    echo "❌ Mismatch in YAML metadata.name: expected ${task_name} but got ${yaml_name}"
    exit_code=1
    continue
  fi

  echo "✅ ${task_name} is valid"
done

exit ${exit_code}
