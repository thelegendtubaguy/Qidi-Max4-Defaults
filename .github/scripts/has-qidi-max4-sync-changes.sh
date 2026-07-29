#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_ROOT=${1:-.}

cd "$REPOSITORY_ROOT"

[ -n "$(git status --short -- config klipper/klippy firmware-package.json)" ]
