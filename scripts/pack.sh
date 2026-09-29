#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ -n "${SOURCE_PATH}" ] || fail "SOURCE_PATH is required"
[ -n "${STAGING_DIR}" ] || fail "STAGING_DIR is required"
[ -e "${SOURCE_PATH}" ] || [ -L "${SOURCE_PATH}" ] || fail "source path does not exist: ${SOURCE_PATH}"
[ ! -L "${SOURCE_PATH}" ] || fail "the top-level source path must not be a symbolic link"

source_path=${SOURCE_PATH%/}
[ -n "${source_path}" ] || fail "refusing to package the filesystem root"

source_parent=$(cd "$(dirname "${source_path}")" && pwd -P)
source_name=$(basename "${source_path}")
source_path="${source_parent}/${source_name}"

case "${source_name}" in
"" | "." | ".." | */* | *$'\n'*) fail "unsupported source name: ${source_name}" ;;
esac

mkdir -p "${STAGING_DIR}"
rm -f \
	"${STAGING_DIR}/format-version" \
	"${STAGING_DIR}/payload-name" \
	"${STAGING_DIR}/payload-sha256" \
	"${STAGING_DIR}/payload-type" \
	"${STAGING_DIR}/payload.tar"

tar -cf "${STAGING_DIR}/payload.tar" -C "${source_parent}" -- "${source_name}"

if [ -d "${source_path}" ]; then
	payload_type="directory"
else
	payload_type="file"
fi

printf '1\n' > "${STAGING_DIR}/format-version"
printf '%s\n' "${source_name}" > "${STAGING_DIR}/payload-name"
printf '%s\n' "${payload_type}" > "${STAGING_DIR}/payload-type"
sha256_file "${STAGING_DIR}/payload.tar" > "${STAGING_DIR}/payload-sha256"

write_output "path" "${source_path}"
write_output "payload-name" "${source_name}"
write_output "payload-type" "${payload_type}"
