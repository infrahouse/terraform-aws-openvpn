#!/usr/bin/env bash

# Error handling
error_handler() {
    echo "Error occurred in script at line: ${1}" >&2
    exit 1
}
trap 'error_handler ${LINENO}' ERR
set -e

: "${WORKERS:=4}"
exec "$@" --workers "$WORKERS"
