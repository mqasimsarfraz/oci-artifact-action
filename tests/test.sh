#!/usr/bin/env bash

set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT

assert_eq() {
	local expected=$1
	local actual=$2

	if [ "${expected}" != "${actual}" ]; then
		echo "expected '${expected}', got '${actual}'" >&2
		exit 1
	fi
}

run_prepare() {
	local operation=$1
	local correlation_id=$2
	local output=$3
	local runner_temp

	runner_temp="${tmp}/runner-$(basename "${output}")"

	mkdir -p "${runner_temp}"

	GITHUB_OUTPUT=${output} \
	GITHUB_REPOSITORY=mqasimsarfraz/oci-artifact-action \
	GITHUB_RUN_ATTEMPT=2 \
	GITHUB_RUN_ID=1234 \
	INPUT_COMPRESSION_LEVEL=0 \
	INPUT_CORRELATION_ID=${correlation_id} \
	INPUT_DESTINATION='' \
	INPUT_GITHUB_TOKEN='' \
	INPUT_NAME="test artifact" \
	INPUT_OPERATION=${operation} \
	INPUT_OVERWRITE=false \
	INPUT_PATH="${tmp}/layout" \
	INPUT_REPOSITORY='' \
	INPUT_RETENTION_DAYS=1 \
	INPUT_RUN_ID='' \
	RUNNER_TEMP="${runner_temp}" \
	bash "${root}/scripts/prepare.sh"
}

mkdir -p "${tmp}/layout/blobs/sha256"
printf '{"imageLayoutVersion":"1.0.0"}\n' > "${tmp}/layout/oci-layout"
printf '{"schemaVersion":2,"manifests":[]}\n' > "${tmp}/layout/index.json"
printf 'blob\n' > "${tmp}/layout/blobs/sha256/example"
printf 'hidden\n' > "${tmp}/layout/.metadata"

prepare_output="${tmp}/prepare-output"
run_prepare upload "linux/amd64 build #42" "${prepare_output}"

artifact_name=$(sed -n 's/^artifact-name=//p' "${prepare_output}")
staging_dir=$(sed -n 's/^staging-dir=//p' "${prepare_output}")
assert_eq "test-artifact-linux-amd64-build-42-e108f5a83801" "${artifact_name}"

pack_output="${tmp}/pack-output"
GITHUB_OUTPUT=${pack_output} \
SOURCE_PATH="${tmp}/layout" \
STAGING_DIR="${staging_dir}" \
bash "${root}/scripts/pack.sh"

[ -s "${staging_dir}/payload.tar" ]

destination="${tmp}/download"
unpack_output="${tmp}/unpack-output"
DESTINATION=${destination} \
GITHUB_OUTPUT=${unpack_output} \
STAGING_DIR=${staging_dir} \
bash "${root}/scripts/unpack.sh"

diff -r "${tmp}/layout" "${destination}/layout"

second_prepare_output="${tmp}/second-prepare-output"
run_prepare download "linux/amd64 build #42" "${second_prepare_output}"
second_artifact_name=$(sed -n 's/^artifact-name=//p' "${second_prepare_output}")
assert_eq "${artifact_name}" "${second_artifact_name}"

different_prepare_output="${tmp}/different-prepare-output"
run_prepare download "linux/arm64 build #42" "${different_prepare_output}"
different_artifact_name=$(sed -n 's/^artifact-name=//p' "${different_prepare_output}")
if [ "${artifact_name}" = "${different_artifact_name}" ]; then
	echo "different correlation IDs generated the same artifact name" >&2
	exit 1
fi

printf 'tampered\n' >> "${staging_dir}/payload.tar"
if DESTINATION="${tmp}/tampered" GITHUB_OUTPUT="${tmp}/tampered-output" STAGING_DIR="${staging_dir}" \
	bash "${root}/scripts/unpack.sh" >/dev/null 2>&1; then
	echo "tampered payload unexpectedly passed verification" >&2
	exit 1
fi

echo "All tests passed"
