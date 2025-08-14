#!/usr/bin/env sh
set -e
: "${WORKERS:=4}"
exec "$@" --workers "$WORKERS"
