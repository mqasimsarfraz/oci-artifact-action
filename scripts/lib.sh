#!/usr/bin/env bash

set -euo pipefail

fail() {
	echo "error: $*" >&2
	exit 1
}

sha256_file() {
	local file=$1

	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "${file}" | awk '{print $1}'
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "${file}" | awk '{print $1}'
	else
		fail "sha256sum or shasum is required"
	fi
}

write_output() {
	local name=$1
	local value=$2

	if [[ "${value}" == *$'\n'* ]]; then
		fail "output ${name} contains a newline"
	fi

	printf '%s=%s\n' "${name}" "${value}" >> "${GITHUB_OUTPUT}"
}
