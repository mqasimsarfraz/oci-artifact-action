#!/usr/bin/env bash

set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ -n "${DESTINATION}" ] || fail "DESTINATION is required"
[ -n "${STAGING_DIR}" ] || fail "STAGING_DIR is required"

for file in format-version payload-name payload-sha256 payload-type payload.tar; do
	[ -f "${STAGING_DIR}/${file}" ] || fail "artifact is missing ${file}"
done

[ "$(cat "${STAGING_DIR}/format-version")" = 1 ] || fail "unsupported artifact format version"

payload_name=$(cat "${STAGING_DIR}/payload-name")
payload_type=$(cat "${STAGING_DIR}/payload-type")
expected_sha256=$(cat "${STAGING_DIR}/payload-sha256")

case "${payload_name}" in
"" | "." | ".." | */* | *$'\n'*) fail "artifact contains an invalid payload name" ;;
esac
case "${payload_type}" in
file | directory) ;;
*) fail "artifact contains an invalid payload type" ;;
esac
[[ "${expected_sha256}" =~ ^[0-9a-fA-F]{64}$ ]] || fail "artifact contains an invalid SHA-256 digest"

actual_sha256=$(sha256_file "${STAGING_DIR}/payload.tar")
[ "${actual_sha256}" = "${expected_sha256}" ] ||
	fail "payload checksum mismatch: expected ${expected_sha256}, got ${actual_sha256}"

while IFS= read -r entry; do
	case "${entry}" in
	"${payload_name}" | "${payload_name}/" | "${payload_name}/"*) ;;
	*) fail "archive entry escapes the payload root: ${entry}" ;;
	esac

	case "/${entry}/" in
	*/../* | */./*) fail "archive entry contains an unsafe path component: ${entry}" ;;
	esac
done < <(tar -tf "${STAGING_DIR}/payload.tar")

mkdir -p "${DESTINATION}"
destination=$(cd "${DESTINATION}" && pwd -P)
payload_path="${destination}/${payload_name}"
rm -rf "${payload_path}"
tar -xf "${STAGING_DIR}/payload.tar" -C "${destination}"

case "${payload_type}" in
file) [ -f "${payload_path}" ] || fail "downloaded payload is not a file" ;;
directory) [ -d "${payload_path}" ] || fail "downloaded payload is not a directory" ;;
esac

write_output "path" "${payload_path}"
write_output "payload-name" "${payload_name}"
write_output "payload-type" "${payload_type}"
