#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
valid_project='ci-123456789-2-amd64-all'

actual=$(TEST_COMPOSE_PROJECT="${valid_project}" bash -c '
    SCRIPT_DIR=$1
    source "${SCRIPT_DIR}/_helpers.sh"
    printf "%s" "${COMPOSE_PROJECT}"
' _ "${SCRIPT_DIR}")
[[ "${actual}" == "${valid_project}" ]] \
    || { echo "valid CI Compose project name was not preserved" >&2; exit 1; }

if TEST_COMPOSE_PROJECT='ci-123.456-invalid' bash -c '
    SCRIPT_DIR=$1
    source "${SCRIPT_DIR}/_helpers.sh"
' _ "${SCRIPT_DIR}" >/dev/null 2>&1; then
    echo "invalid CI Compose project name was accepted" >&2
    exit 1
fi

echo "Compose project-name validation passed."
