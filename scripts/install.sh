#!/usr/bin/env bash
# Thin wrapper around `make install` so the build logic lives in one place.
set -euo pipefail
cd "$(dirname "$0")/.."
exec make install
