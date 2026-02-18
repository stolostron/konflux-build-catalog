# shellcheck shell=bash

if [[ ${SKIP_METADATA_FETCH} == "true" ]]; then
  echo "* Skipping metadata fetch"
  echo -n "" >"$(results.z-stream-version.path)"
  echo -n "[]" >"$(results.image-labels.path)"
  exit 0
fi

if [[ -z ${PRODUCT} ]] || [[ -z ${BRANCH} ]]; then
  echo "error: PRODUCT or BRANCH is not set to parse product metadata from bundle repository" >&2
  exit 1
fi

repo="${PRODUCT}-operator-bundle"

echo "* Cloning '${repo}' repository at branch '${BRANCH}'"
git clone \
  --depth 1 \
  --branch "${BRANCH}" \
  "https://github.com/stolostron/${repo}"

cd "${repo}" || {
  echo "error: failed to change directory to '${repo}'" >&2
  exit 1
}

echo "* Extracting Z-stream version"
if ! [[ -f Z_RELEASE_VERSION ]]; then
  echo "error: Z_RELEASE_VERSION file not found" >&2
  exit 1
fi

z_stream_version=$(cat Z_RELEASE_VERSION)
echo "  Z-stream version: '${z_stream_version}'"

echo "* Extracting GA image repository"
config_path="config/${PRODUCT}-manifest-gen-config.json"
if ! [[ -f ${config_path} ]]; then
  echo "error: ${config_path} file not found" >&2
  exit 1
fi

ga_image_namespace=$(jq -r '.["product-images"].["image-namespace"] // ""' "${config_path}")
ga_image_name=$(
  jq -er '.["product-images"].["image-list"][]
    | select(.["konflux-component-name"] == "'"${COMPONENT}"'")
    | .["publish-name"] // ""' "${config_path}"
)
echo "  GA image namespace: '${ga_image_namespace}'"
echo "  GA image name: '${ga_image_name}'"
if [[ -z ${ga_image_namespace} ]] || [[ -z ${ga_image_name} ]]; then
  echo "error: failed to parse GA image namespace or name from ${config_path}" >&2
  exit 1
fi

if [[ ${PRODUCT} == "mce" ]]; then
  PRODUCT="multicluster_engine"
fi

# Write results for task result files
cpe="cpe:/a:redhat:${PRODUCT}:${BRANCH#*-}::${ga_image_name##*-rh}"
name="${ga_image_namespace}/${ga_image_name}"
version="v${z_stream_version}"

echo "* Writing results to task result files"
echo -n "  z-stream-version: "
echo -n "${z_stream_version}" | tee "$(results.z-stream-version.path)"
echo
echo -n "  image-labels: "
printf '["cpe=%s","name=%s","version=%s"]' "${cpe}" "${name}" "${version}" | tee "$(results.image-labels.path)"
echo
