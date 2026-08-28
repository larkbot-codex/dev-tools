#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
target_dir="${HOME}/.bashrc.d"
target_file="${target_dir}/dev-tools-git.sh"
bin_dir="${HOME}/.local/bin"
cron_runner="${bin_dir}/pr-review-cron"
cron_lock_dir="${HOME}/.cache/pr-review"
bashrc_file="${HOME}/.bashrc"
quorum_file="${bin_dir}/pr-review-quorum"
update_file="${bin_dir}/dev-tools-update"

install_atomic() {
    local source="$1" destination="$2" mode="$3" temporary
    temporary=$(mktemp "${destination}.dev-tools.XXXXXXXX")
    if ! install -m "$mode" "$source" "$temporary"; then
        rm -f -- "$temporary"
        return 1
    fi
    if ! mv -f -- "$temporary" "$destination"; then
        rm -f -- "$temporary"
        return 1
    fi
}

mkdir -p "$target_dir" "$bin_dir" "$cron_lock_dir"
mkdir -p "${HOME}/.cache/pr-review-quorum" "${HOME}/.local/state/pr-review-quorum" \
    "${HOME}/.local/state/dev-tools-update" "${HOME}/.local/share/dev-tools"
install_atomic "$script_dir/bashrc.d/git.sh" "$target_file" 0644
install_atomic "$script_dir/bin/pr-review-cron" "$cron_runner" 0755
install_atomic "$script_dir/bin/pr-review-quorum" "$quorum_file" 0755
install_atomic "$script_dir/bin/dev-tools-update" "$update_file" 0755
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

printf 'Installed %s\nInstalled %s\nInstalled %s\nInstalled %s\nReload with: source %s\n\n' \
    "$target_file" "$cron_runner" "$quorum_file" "$update_file" "$bashrc_file"

# Use the installed helper's own output so install instructions cannot drift.
# shellcheck source=bashrc.d/git.sh
source "$target_file"
pr-help
