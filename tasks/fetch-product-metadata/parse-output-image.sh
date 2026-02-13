# shellcheck shell=bash

# Expected format: [<registry>/<repo>/<build-namespace>/]<component>-{acm|mce}-<XY>[:<tag>]
echo "* Parsing output image"
echo "  Output image: '${OUTPUT_IMAGE}'"
if [[ -z ${OUTPUT_IMAGE} ]]; then
  echo "error: output-image parameter is empty" >&2
  exit 1
fi

echo "* Extracting image repository"
output_image_repo=$(echo "${OUTPUT_IMAGE}" | grep -oE '[a-z0-9-]+-(acm|mce)-[0-9]+' || true)
echo "  Image repository: '${output_image_repo}'"
if [[ -z ${output_image_repo} ]]; then
  echo "error: failed to parse ACM or MCE image repository from image '${OUTPUT_IMAGE}'" >&2
  exit 1
fi
echo "* Extracting component"
component=$(echo "${output_image_repo}" | sed -E 's/-(acm|mce)-[0-9]+//')
echo "  Component: '${component}'"
if [[ -z ${component} ]] || [[ ${component} == "${output_image_repo}" ]]; then
  echo "error: failed to parse component from image repository '${output_image_repo}'" >&2
  exit 1
fi

echo "* Extracting product"
product=$(echo "${output_image_repo#"${component}-"}" | cut -d '-' -f 1)
echo "  Product: '${product}'"
if [[ -z ${product} ]] || [[ ${product} == "${output_image_repo}" ]]; then
  echo "error: failed to parse product from image repository '${output_image_repo}'" >&2
  exit 1
fi

case ${product} in
"acm")
  branch="release"
  ;;
"mce")
  branch="backplane"
  ;;
*)
  echo "error: unexpected product '${product}' from image repository '${output_image_repo}': product must be 'acm' or 'mce'" >&2
  exit 1
  ;;
esac

echo "* Extracting version"
parsed_version=${output_image_repo#"${component}-${product}-"}
version_y=${parsed_version#[0-9]}
version_x=${parsed_version%"${version_y}"}
version="${version_x}.${version_y}"

echo "  Version: '${parsed_version}' -> '${version}'"
if [[ -z ${parsed_version} ]] || [[ -z ${version_x} ]] || [[ -z ${version_y} ]] ||
  [[ ${version_x} == "${parsed_version}" ]] || [[ ${version_y} == "${parsed_version}" ]] ||
  [[ ${version_x} == "${product}" ]] || [[ ${version_y} == "${product}" ]]; then
  echo "error: failed to parse version from image repository '${output_image_repo}'" >&2
  exit 1
fi

# Write results for next steps to pipeline results files
echo -n "${component}" >"$(step.results.component.path)"
echo -n "${product}" >"$(step.results.product.path)"
echo -n "${branch}-${version}" >"$(step.results.branch.path)"
