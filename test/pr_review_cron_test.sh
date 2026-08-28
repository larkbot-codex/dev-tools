#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

home_dir="$test_dir/home"
fake_bin="$home_dir/.local/bin"
mkdir -p "$home_dir/.bashrc.d" "$fake_bin"

for template in "$project_dir"/cron/*.crontab; do
    grep -Fq 'PR_REVIEW_REVIEWER=CHANGE_ME' "$template" || \
        fail "$(basename "$template") does not require an explicit reviewer"
done

cat >"$home_dir/.bashrc.d/dev-tools-git.sh" <<'EOF'
pr-watch() {
    printf '%s conversation head thread 42\n' "$PR_WATCH_ITEM" >>"$DEV_TOOLS_PR_WATCH_STATE"
    printf '%s\n' "$PR_WATCH_ITEM"
}
EOF

cat >"$fake_bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "api" && "$2" == "user" ]]; then
    printf 'review-bot\n'
elif [[ "$1" == "api" && ( "$2" == */reviews* || "${3:-}" == */reviews* ) ]]; then
    if [[ -e "$REVIEW_SUBMITTED" ]]; then
        printf '102\thead-sha\n'
    else
        printf '101\thead-sha\n'
    fi
elif [[ "$1" == "pr" && "$2" == "view" ]]; then
    printf 'head-sha\n'
else
    printf 'unexpected gh call: %s\n' "$*" >&2
    exit 1
fi
EOF
chmod +x "$fake_bin/gh"

cat >"$fake_bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
touch "$REVIEW_SUBMITTED"
printf 'submitted test review\n'
EOF
chmod +x "$fake_bin/codex"

review_marker="$test_dir/review-submitted"
HOME="$home_dir" \
PATH="$fake_bin:/usr/local/bin:/usr/bin:/bin" \
PR_REVIEW_PROVIDER=codex \
PR_REVIEW_CODEX_BIN="$fake_bin/codex" \
PR_REVIEW_TIMEOUT=5s \
PR_WATCH_ITEM=owner/repository#7 \
REVIEW_SUBMITTED="$review_marker" \
    "$project_dir/bin/pr-review-cron"

[[ -e "$review_marker" ]] || fail "provider was not invoked"
grep -Fqx 'owner/repository#7 conversation head thread 42' \
    "$home_dir/.local/state/pr-review/pr-watch.seen" || fail "confirmed watcher state was not committed"
grep -Fq 'confirmed review 102 for owner/repository#7 at head-sha' \
    "$home_dir/.local/state/pr-review/cron.log" || fail "review was not confirmed in the log"

rm -- "$review_marker"
cat >"$fake_bin/codex" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$fake_bin/codex"

if HOME="$home_dir" \
    PATH="$fake_bin:/usr/local/bin:/usr/bin:/bin" \
    PR_REVIEW_PROVIDER=codex \
    PR_REVIEW_CODEX_BIN="$fake_bin/codex" \
    PR_REVIEW_TIMEOUT=5s \
    PR_WATCH_ITEM=owner/another#8 \
    REVIEW_SUBMITTED="$review_marker" \
        "$project_dir/bin/pr-review-cron"; then
    fail "unconfirmed provider run succeeded"
fi
if grep -Fq 'owner/another#8 ' "$home_dir/.local/state/pr-review/pr-watch.seen"; then
    fail "failed provider state was committed"
fi

if HOME="$home_dir" PR_REVIEW_PROVIDER=unknown "$project_dir/bin/pr-review-cron" 2>/dev/null; then
    fail "unknown provider succeeded"
fi

printf 'pull request review cron tests passed\n'
