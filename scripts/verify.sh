#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd -- "$project_dir"

shellcheck bashrc.d/*.sh install.sh uninstall.sh install-hooks.sh .githooks/* scripts/*.sh test/*.sh

for test_script in test/*.sh; do
    bash "$test_script"
done
