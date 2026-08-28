#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
target_dir="${HOME}/.bashrc.d"
target_file="${target_dir}/dev-tools-git.sh"
bin_dir="${HOME}/.local/bin"
cron_runner="${bin_dir}/pr-review-cron"
bashrc_file="${HOME}/.bashrc"

mkdir -p "$target_dir" "$bin_dir"
install -m 0644 "$script_dir/bashrc.d/git.sh" "$target_file"
install -m 0755 "$script_dir/bin/pr-review-cron" "$cron_runner"
touch "$bashrc_file"

if ! grep -Fq '# dev-tools bashrc.d loader' "$bashrc_file"; then
    cat >>"$bashrc_file" <<'EOF'

# dev-tools bashrc.d loader
if [ -d "$HOME/.bashrc.d" ]; then
    for rc in "$HOME"/.bashrc.d/*.sh; do
        [ -f "$rc" ] && . "$rc"
    done
    unset rc
fi
# end dev-tools bashrc.d loader
EOF
fi

printf 'Installed %s\nInstalled %s\nReload with: source %s\n\n' \
    "$target_file" "$cron_runner" "$bashrc_file"

# Use the installed helper's own output so install instructions cannot drift.
# shellcheck source=bashrc.d/git.sh
source "$target_file"
pr-help
