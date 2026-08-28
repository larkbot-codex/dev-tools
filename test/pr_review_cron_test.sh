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
grep -Fq 'PR_REVIEW_CODEX_MODEL=gpt-5.6-sol PR_REVIEW_CODEX_EFFORT=high' \
    "$project_dir/cron/codex.crontab" || fail "Codex crontab does not pin its model"
grep -Fq 'PR_REVIEW_CLAUDE_MODEL=claude-opus-5 PR_REVIEW_CLAUDE_EFFORT=high' \
    "$project_dir/cron/claude.crontab" || fail "Claude crontab does not pin its model"
grep -Fq 'PR_REVIEW_ANTIGRAVITY_MODEL=gemini-3.7-flash-high PR_REVIEW_ANTIGRAVITY_EFFORT=high' \
    "$project_dir/cron/gemini.crontab" || fail "Antigravity crontab does not pin its model"

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
printf '%s\n' "$@" >"$PROVIDER_ARGS"
touch "$REVIEW_SUBMITTED"
printf 'submitted test review\n'
EOF
chmod +x "$fake_bin/codex"

review_marker="$test_dir/review-submitted"
provider_args="$test_dir/provider-args"
HOME="$home_dir" \
PATH="$fake_bin:/usr/local/bin:/usr/bin:/bin" \
PR_REVIEW_PROVIDER=codex \
PR_REVIEW_CODEX_BIN="$fake_bin/codex" \
PR_REVIEW_TIMEOUT=5s \
PR_WATCH_ITEM=owner/repository#7 \
REVIEW_SUBMITTED="$review_marker" \
PROVIDER_ARGS="$provider_args" \
    "$project_dir/bin/pr-review-cron"

[[ -e "$review_marker" ]] || fail "provider was not invoked"
grep -Fqx 'owner/repository#7 conversation head thread 42' \
    "$home_dir/.local/state/pr-review/pr-watch.seen" || fail "confirmed watcher state was not committed"
grep -Fq 'confirmed review 102 for owner/repository#7 at head-sha' \
    "$home_dir/.local/state/pr-review/cron.log" || fail "review was not confirmed in the log"
grep -Fqx -- '--model' "$provider_args" || fail "Codex model flag was not passed"
grep -Fqx -- 'gpt-5.6-sol' "$provider_args" || fail "Codex model was not pinned"
grep -Fqx -- '--config' "$provider_args" || fail "Codex config flag was not passed"
grep -Fqx -- 'model_reasoning_effort="high"' "$provider_args" || \
    fail "Codex reasoning effort was not pinned"

cat >"$fake_bin/claude" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$PROVIDER_ARGS"
touch "$REVIEW_SUBMITTED"
printf 'submitted test review\n'
EOF
chmod +x "$fake_bin/claude"

rm -- "$review_marker"
HOME="$home_dir" \
PATH="$fake_bin:/usr/local/bin:/usr/bin:/bin" \
PR_REVIEW_PROVIDER=claude \
PR_REVIEW_CLAUDE_BIN="$fake_bin/claude" \
PR_REVIEW_TIMEOUT=5s \
PR_WATCH_ITEM=owner/claude#8 \
REVIEW_SUBMITTED="$review_marker" \
PROVIDER_ARGS="$provider_args" \
    "$project_dir/bin/pr-review-cron"
grep -Fqx -- '--model' "$provider_args" || fail "Claude model flag was not passed"
grep -Fqx -- 'claude-opus-5' "$provider_args" || fail "Claude model was not pinned"
grep -Fqx -- '--effort' "$provider_args" || fail "Claude effort flag was not passed"
grep -Fqx -- 'high' "$provider_args" || fail "Claude effort was not pinned"

cat >"$fake_bin/agy" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >"$PROVIDER_ARGS"
touch "$REVIEW_SUBMITTED"
printf 'submitted test review\n'
EOF
chmod +x "$fake_bin/agy"

rm -- "$review_marker"
HOME="$home_dir" \
PATH="$fake_bin:/usr/local/bin:/usr/bin:/bin" \
PR_REVIEW_PROVIDER=gemini \
PR_REVIEW_GEMINI_DRIVER=agy \
PR_REVIEW_GEMINI_BIN="$fake_bin/agy" \
PR_REVIEW_TIMEOUT=5s \
PR_WATCH_ITEM=owner/gemini#9 \
REVIEW_SUBMITTED="$review_marker" \
PROVIDER_ARGS="$provider_args" \
    "$project_dir/bin/pr-review-cron"
grep -Fqx -- '--model' "$provider_args" || fail "Antigravity model flag was not passed"
grep -Fqx -- 'gemini-3.7-flash-high' "$provider_args" || fail "Antigravity model was not pinned"
grep -Fqx -- '--effort' "$provider_args" || fail "Antigravity effort flag was not passed"
grep -Fqx -- 'high' "$provider_args" || fail "Antigravity effort was not pinned"

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
