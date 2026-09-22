#! /bin/bash

set -euo pipefail  

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)

catalog_version=$(
  yq '.spec.params[] 
  | select(.name == "build-args").value[] 
  | select(. == "CATALOG_VERSION=v*") // ""' \
  "${script_dir}/../.tekton/common-pipeline-fbc-pull-request.yaml"
)

if [[ -z ${catalog_version} ]]; then
  echo "Error: CATALOG_VERSION not found in .tekton/common-pipeline-fbc-pull-request.yaml"
  exit 1
fi

catalog_version=${catalog_version#CATALOG_VERSION=}
catalog_image=registry.redhat.io/redhat/redhat-operator-index:${catalog_version}

# Creating bin directory
bin_dir="${script_dir}/bin"
mkdir -p "${bin_dir}"

echo "* Verifying the opm CLI"
OPM="${bin_dir}/opm"
system_os=$(uname -s | tr '[:upper:]' '[:lower:]')
system_arch=$(uname -m | sed 's/aarch64/arm64/' | sed 's/x86_64/amd64/')

# Setting to v1.61.0 since v1.63.0 adds an unsupported release field to the olm.package in the bundle
current_release_json=$(curl -s --fail --show-error "https://api.github.com/repos/operator-framework/operator-registry/releases/tags/v1.61.0")
current_release=$(printf '%s\n' "${current_release_json}" | jq -r '.tag_name')
if ! "${OPM}" version || [[ "$("${OPM}" version | grep -o "v[0-9]\+\.[0-9]\+\.[0-9]\+" | head -1)" != "${current_release}" ]]; then
  echo "Installing opm ${current_release}"
  download_url=$(printf '%s\n' "${current_release_json}" | jq -r '.assets[] | select(.name == "'"${system_os}"'-'"${system_arch}"'-opm").browser_download_url')
  curl --fail --show-error -sLo "${OPM}" "${download_url}"
  chmod +x "${OPM}"
  "${OPM}" version
fi

echo "* Refreshing test catalog"
"${OPM}" migrate -o=yaml "${catalog_image}" "${script_dir}/../test/fbc/catalog-migrate"

cp \
  "${script_dir}/../test/fbc/catalog-migrate/multicluster-global-hub-operator-rh/catalog.yaml" \
  "${script_dir}/../test/fbc/multicluster-global-hub-operator-rh/catalog.yaml"

yq '.' -i "${script_dir}/../test/fbc/multicluster-global-hub-operator-rh/catalog.yaml"

rm -rf "${script_dir}/../test/fbc/catalog-migrate"
