#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

case "${INPUT_OPERATION}" in
upload | download) ;;
*) fail "operation must be 'upload' or 'download', got '${INPUT_OPERATION}'" ;;
esac

case "${INPUT_OVERWRITE}" in
true | false) ;;
*) fail "overwrite must be 'true' or 'false', got '${INPUT_OVERWRITE}'" ;;
esac

if ! [[ "${INPUT_COMPRESSION_LEVEL}" =~ ^[0-9]$ ]]; then
	fail "compression-level must be an integer from 0 to 9"
fi

if ! [[ "${INPUT_RETENTION_DAYS}" =~ ^[1-9][0-9]*$ ]]; then
	fail "retention-days must be a positive integer"
fi

if [ "${INPUT_OPERATION}" = upload ]; then
	[ -n "${INPUT_PATH}" ] || fail "path is required for the upload operation"
	[ -e "${INPUT_PATH}" ] || [ -L "${INPUT_PATH}" ] || fail "path does not exist: ${INPUT_PATH}"
fi

if [[ "${INPUT_NAME}" == *$'\n'* ]]; then
	fail "name must not contain a newline"
fi

correlation_id=${INPUT_CORRELATION_ID}
if [ -z "${correlation_id}" ]; then
	correlation_id="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
fi
if [[ "${correlation_id}" == *$'\n'* ]]; then
	fail "correlation-id must not contain a newline"
fi

slugify() {
	local value=$1
	local fallback=$2
	local slug

	slug=$(printf '%s' "${value}" |
		LC_ALL=C tr -cs 'A-Za-z0-9._-' '-' |
		sed -e 's/^-*//' -e 's/-*$//' |
		cut -c1-80)
	if [ -z "${slug}" ]; then
		slug=${fallback}
	fi
	printf '%s' "${slug}"
}

name_slug=$(slugify "${INPUT_NAME}" "oci-artifact")
correlation_slug=$(slugify "${correlation_id}" "correlation")
correlation_hash=$(printf '%s' "${correlation_id}" | {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum
	else
		shasum -a 256
	fi
} | awk '{print substr($1, 1, 12)}')
artifact_name="${name_slug}-${correlation_slug}-${correlation_hash}"

staging_dir="${RUNNER_TEMP}/oci-artifact-action/${artifact_name}"
rm -rf "${staging_dir}"
mkdir -p "${staging_dir}"

destination=${INPUT_DESTINATION}
if [ -z "${destination}" ]; then
	destination="${RUNNER_TEMP}/oci-artifacts/${artifact_name}"
fi

repository=${INPUT_REPOSITORY:-${GITHUB_REPOSITORY:-}}
if [ -n "${INPUT_RUN_ID}" ]; then
	[ -n "${INPUT_GITHUB_TOKEN}" ] || fail "github-token is required when run-id is set"
	[ -n "${repository}" ] || fail "repository is required when run-id is set outside GitHub Actions"
fi

write_output "artifact-name" "${artifact_name}"
write_output "correlation-id" "${correlation_id}"
write_output "destination" "${destination}"
write_output "repository" "${repository}"
write_output "staging-dir" "${staging_dir}"
