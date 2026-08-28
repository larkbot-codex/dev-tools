#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd -- "$project_dir"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    printf 'Run this installer from a Git checkout of dev-tools.\n' >&2
    exit 1
fi

configured_path=$(git config --local --get core.hooksPath || true)
if [[ -n "$configured_path" && "$configured_path" != ".githooks" ]]; then
    printf 'Refusing to replace existing core.hooksPath: %s\n' "$configured_path" >&2
    exit 1
fi

git config --local core.hooksPath .githooks
printf 'Enabled dev-tools hooks for %s\n' "$project_dir"
