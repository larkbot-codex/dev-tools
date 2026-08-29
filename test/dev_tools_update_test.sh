#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

unset DEV_TOOLS_UPDATE_UPSTREAM DEV_TOOLS_UPDATE_BRANCH DEV_TOOLS_UPDATE_SOURCE \
    DEV_TOOLS_UPDATE_LOCK DEV_TOOLS_UPDATE_LOG DEV_TOOLS_UPDATE_DEPLOYED_STATE \
    XDG_STATE_HOME XDG_CACHE_HOME UPDATE_TRACE UPDATE_VERIFY_FAIL

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

home_dir="$test_dir/home"
state_dir="$test_dir/state"
cache_dir="$test_dir/cache"
source_dir="$test_dir/source"
upstream_work="$test_dir/upstream-work"
upstream_repo="$test_dir/upstream.git"
trace_file="$test_dir/trace"
verify_fail="$test_dir/verify-fail"
mkdir -p "$home_dir" "$upstream_work/scripts" "$upstream_work/bin"

cp "$project_dir/bin/dev-tools-update" "$upstream_work/bin/dev-tools-update"
cat >"$upstream_work/scripts/verify.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ! -e "$UPDATE_VERIFY_FAIL" ]] || exit 42
printf 'verify\n' >>"$UPDATE_TRACE"
EOF
cat >"$upstream_work/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
printf 'install\n' >>"$UPDATE_TRACE"
mkdir -p "$HOME/.local/bin"
install -m 0755 "$script_dir/bin/dev-tools-update" "$HOME/.local/bin/dev-tools-update"
EOF
chmod 0755 "$upstream_work/scripts/verify.sh" "$upstream_work/install.sh" \
    "$upstream_work/bin/dev-tools-update"

git -C "$upstream_work" init --initial-branch=main >/dev/null
git -C "$upstream_work" config user.name updater-test
git -C "$upstream_work" config user.email updater-test@example.com
git -C "$upstream_work" add .
git -C "$upstream_work" commit -m initial >/dev/null
initial_commit=$(git -C "$upstream_work" rev-parse HEAD)
git clone --bare "$upstream_work" "$upstream_repo" >/dev/null
git -C "$upstream_work" remote add publish "$upstream_repo"

run_update() {
    HOME="$home_dir" \
    XDG_STATE_HOME="$state_dir" \
    XDG_CACHE_HOME="$cache_dir" \
    DEV_TOOLS_UPDATE_SOURCE="$source_dir" \
    DEV_TOOLS_UPDATE_UPSTREAM="$upstream_repo" \
    DEV_TOOLS_UPDATE_BRANCH=main \
    UPDATE_TRACE="$trace_file" \
    UPDATE_VERIFY_FAIL="$verify_fail" \
        "$project_dir/bin/dev-tools-update"
}

run_update
[[ "$(git -C "$source_dir" rev-parse HEAD)" == "$initial_commit" ]] || \
    fail "initial clone did not select canonical main"
[[ "$(cat "$state_dir/dev-tools-update/deployed")" == "$initial_commit" ]] || \
    fail "deployed state did not record the verified commit"
[[ "$(grep -Fc verify "$trace_file")" == 1 ]] || fail "verification did not run"
[[ "$(grep -Fc install "$trace_file")" == 1 ]] || fail "installation did not run"
[[ -x "$home_dir/.local/bin/dev-tools-update" ]] || fail "updater was not installed"

lock_file="$cache_dir/pr-review/cron.lock"
exec 9>"$lock_file"
flock -n 9 || fail "test could not acquire the shared lock"
run_update
flock -u 9
exec 9>&-
[[ "$(grep -Fc verify "$trace_file")" == 1 ]] || fail "busy updater ran verification"
[[ "$(grep -Fc install "$trace_file")" == 1 ]] || fail "busy updater ran installation"

printf 'dirty\n' >"$source_dir/local-change"
if run_update; then
    fail "dirty source checkout was accepted"
fi
rm -- "$source_dir/local-change"

git -C "$source_dir" remote set-url upstream "$test_dir/wrong.git"
if run_update; then
    fail "wrong upstream remote was accepted"
fi
git -C "$source_dir" remote set-url upstream "$upstream_repo"

touch "$verify_fail"
if run_update; then
    fail "failed verification was accepted"
fi
rm -- "$verify_fail"
[[ "$(grep -Fc install "$trace_file")" == 1 ]] || \
    fail "installation ran after failed verification"
[[ "$(cat "$state_dir/dev-tools-update/deployed")" == "$initial_commit" ]] || \
    fail "failed verification changed deployed state"

printf 'next\n' >"$upstream_work/release.txt"
git -C "$upstream_work" add release.txt
git -C "$upstream_work" commit -m next >/dev/null
next_commit=$(git -C "$upstream_work" rev-parse HEAD)
git -C "$upstream_work" push publish main >/dev/null
run_update
[[ "$(git -C "$source_dir" rev-parse HEAD)" == "$next_commit" ]] || \
    fail "source checkout did not fast-forward"
[[ "$(cat "$state_dir/dev-tools-update/deployed")" == "$next_commit" ]] || \
    fail "fast-forwarded commit was not recorded"
[[ "$(grep -Fc install "$trace_file")" == 2 ]] || \
    fail "verified fast-forward was not installed"

empty_tree=$(git -C "$upstream_work" mktree </dev/null)
rewritten_commit=$(printf 'rewritten history\n' | git -C "$upstream_work" commit-tree "$empty_tree")
git -C "$upstream_work" push --force publish \
    "$rewritten_commit:refs/heads/main" >/dev/null
if run_update; then
    fail "non-fast-forward canonical history was accepted"
fi
[[ "$(git -C "$source_dir" rev-parse HEAD)" == "$next_commit" ]] || \
    fail "non-fast-forward attempt changed the source checkout"
[[ "$(grep -Fc install "$trace_file")" == 2 ]] || \
    fail "non-fast-forward attempt ran installation"

grep -Fq 'shared review lock is busy; update skipped' \
    "$state_dir/dev-tools-update/cron.log" || fail "busy update was not logged"
grep -Fq 'source checkout has local changes' \
    "$state_dir/dev-tools-update/cron.log" || fail "dirty checkout refusal was not logged"
grep -Fq 'is not a fast-forward' \
    "$state_dir/dev-tools-update/cron.log" || fail "history rewrite refusal was not logged"

grep -Fq 'DEV_TOOLS_UPDATE_UPSTREAM=https://github.com/thelarklan/dev-tools.git' \
    "$project_dir/cron/dev-tools-update.crontab" || fail "updater cron does not pin canonical upstream"

printf 'dev-tools update tests passed\n'
