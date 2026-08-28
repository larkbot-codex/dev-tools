#!/usr/bin/env bash
set -euo pipefail

target_dir="${HOME}/.bashrc.d"
target_file="${target_dir}/dev-tools-git.sh"
cron_runner="${HOME}/.local/bin/pr-review-cron"
bashrc_file="${HOME}/.bashrc"
quorum_file="${HOME}/.local/bin/pr-review-quorum"

if [[ -f "$target_file" ]]; then
    rm -- "$target_file"
    printf 'Removed %s\n' "$target_file"
else
    printf 'Already absent: %s\n' "$target_file"
fi

if [[ -f "$cron_runner" ]]; then
    rm -- "$cron_runner"
    printf 'Removed %s\n' "$cron_runner"
else
    printf 'Already absent: %s\n' "$cron_runner"
fi

if [[ -f "$quorum_file" ]]; then
    rm -- "$quorum_file"
    printf 'Removed %s\n' "$quorum_file"
else
    printf 'Already absent: %s\n' "$quorum_file"
fi

# Preserve the shared loader whenever another shell extension still uses it.
if [[ -d "$target_dir" ]] && ! find "$target_dir" -mindepth 1 -print -quit | grep -q .; then
    rmdir -- "$target_dir"

    if [[ -f "$bashrc_file" ]] && grep -Fq '# dev-tools bashrc.d loader' "$bashrc_file"; then
        temporary_file=$(mktemp "${bashrc_file}.dev-tools.XXXXXX")
        awk '
            $0 == "# dev-tools bashrc.d loader" { removing = 1; next }
            $0 == "# end dev-tools bashrc.d loader" { removing = 0; next }
            !removing { print }
        ' "$bashrc_file" >"$temporary_file"
        chmod --reference="$bashrc_file" "$temporary_file" 2>/dev/null || true
        mv -- "$temporary_file" "$bashrc_file"
        printf 'Removed the dev-tools loader from %s\n' "$bashrc_file"
    fi
fi

printf 'dev-tools Git and quorum helpers uninstalled\n'
