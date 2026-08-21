#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=bashrc.d/git.sh
source "$project_dir/bashrc.d/git.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

real_git=$(command -v git)
real_sleep=$(command -v sleep)
fake_bin="$test_dir/bin"
fake_git_log="$test_dir/git.log"
fake_gh_log="$test_dir/gh.log"
upstream_work="$test_dir/upstream-work"
upstream_repo="$test_dir/upstream.git"
fork_repo="$test_dir/fork.git"
clone_dir="$test_dir/clone"
other_clone="$test_dir/other-clone"

git init -b main "$upstream_work" >/dev/null
git -C "$upstream_work" config user.name Test
git -C "$upstream_work" config user.email test@example.com
printf 'base\n' >"$upstream_work/tracked.txt"
printf 'base\n' >"$upstream_work/conflict.txt"
git -C "$upstream_work" add tracked.txt conflict.txt
git -C "$upstream_work" commit -m base >/dev/null
git clone --bare "$upstream_work" "$upstream_repo" >/dev/null 2>&1
git clone --bare "$upstream_work" "$fork_repo" >/dev/null 2>&1
git clone "$fork_repo" "$clone_dir" >/dev/null 2>&1
git -C "$clone_dir" config user.name Test
git -C "$clone_dir" config user.email test@example.com
git -C "$clone_dir" remote add upstream "$upstream_repo"
git -C "$clone_dir" fetch upstream main >/dev/null 2>&1
git -C "$clone_dir" symbolic-ref refs/remotes/upstream/HEAD refs/remotes/upstream/main

origin_url=https://github.com/thelarkbot/project.git
upstream_url=git@github.com:upstream/project.git
git -C "$clone_dir" remote set-url origin "$origin_url"
git -C "$clone_dir" remote set-url --push origin "$fork_repo"
git -C "$clone_dir" remote set-url upstream "$upstream_url"
git -C "$clone_dir" switch -c feature/rewrite >/dev/null
printf 'feature\n' >"$clone_dir/feature.txt"
git -C "$clone_dir" add feature.txt
git -C "$clone_dir" commit -m 'feature work' >/dev/null
git -C "$clone_dir" push --set-upstream origin feature/rewrite >/dev/null 2>&1

mkdir -p "$fake_bin"
cat >"$fake_bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_GIT_LOG"
if [[ "${1:-}" == fetch && "${2:-}" == upstream && $# -eq 3 ]]; then
    exec "$REAL_GIT" fetch "$UPSTREAM_REPO" "$3:refs/remotes/upstream/$3"
fi
exec "$REAL_GIT" "$@"
EOF
chmod +x "$fake_bin/git"

cat >"$fake_bin/sleep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_SLEEP_LOG"
if [[ "${FAKE_SLEEP_INTERRUPT:-0}" == 1 ]]; then
    exit 130
fi
exec "$REAL_SLEEP" "$@"
EOF
chmod +x "$fake_bin/sleep"

cat >"$fake_bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$FAKE_GH_LOG"
if [[ "${1:-} ${2:-}" == "auth status" ]]; then
    exit 0
fi
if [[ "${1:-} ${2:-}" == "pr list" ]]; then
    if [[ "${FAKE_GH_EMPTY_PR:-0}" == 1 ]]; then
        exit 0
    fi
    if [[ "${FAKE_GH_MULTIPLE_PRS:-0}" == 1 ]]; then
        printf '17\n18\n'
        exit 0
    fi
    printf '17\n'
    exit 0
fi
if [[ "${1:-} ${2:-}" == "pr comment" ]]; then
    printf 'https://github.com/upstream/project/pull/1#issuecomment-1\n'
    exit 0
fi
printf 'unexpected gh invocation: %s\n' "$*" >&2
exit 1
EOF
chmod +x "$fake_bin/gh"

export REAL_GIT="$real_git"
export REAL_SLEEP="$real_sleep"
export UPSTREAM_REPO="$upstream_repo"
export FAKE_GIT_LOG="$fake_git_log"
export FAKE_GH_LOG="$fake_gh_log"
export FAKE_SLEEP_LOG="$test_dir/sleep.log"
export DEV_TOOLS_FORCE_PUSH_DELAY=0
export PATH="$fake_bin:$PATH"

if (
    cd "$test_dir"
    pr-amend extra 2>"$test_dir/amend-usage-error"
); then
    fail "pr-amend accepted an extra argument"
fi
grep -Fxq 'usage: pr-amend [--all]' "$test_dir/amend-usage-error" || fail "pr-amend usage was unclear"

if (
    cd "$test_dir"
    pr-rebase main extra 2>"$test_dir/rebase-usage-error"
); then
    fail "pr-rebase accepted too many arguments"
fi
grep -Fxq 'usage: pr-rebase [BASE]' "$test_dir/rebase-usage-error" || fail "pr-rebase usage was unclear"

if (
    cd "$test_dir"
    pr-comment "message" extra 2>"$test_dir/comment-usage-error"
); then
    fail "pr-comment accepted too many arguments"
fi
grep -Fxq 'usage: pr-comment MESSAGE' "$test_dir/comment-usage-error" || fail "pr-comment usage was unclear"

commit_count=$(git -C "$clone_dir" rev-list --count HEAD)
commit_subject=$(git -C "$clone_dir" log -1 --format=%s)
printf 'amended tracked change\n' >>"$clone_dir/tracked.txt"
printf 'leave untracked\n' >"$clone_dir/untracked.txt"
: >"$fake_git_log"
(
    cd "$clone_dir"
    pr-amend 2>"$test_dir/amend-warning"
)
[[ "$(git -C "$clone_dir" rev-list --count HEAD)" == "$commit_count" ]] || fail "pr-amend added a commit"
[[ "$(git -C "$clone_dir" log -1 --format=%s)" == "$commit_subject" ]] || fail "pr-amend changed the commit message"
git -C "$clone_dir" ls-files --error-unmatch untracked.txt >/dev/null 2>&1 && fail "tracked-only amend included an untracked file"
[[ "$(git --git-dir="$fork_repo" rev-parse refs/heads/feature/rewrite)" == "$(git -C "$clone_dir" rev-parse HEAD)" ]] || fail "amended commit was not pushed"
grep -Fq 'push --force-with-lease --set-upstream origin HEAD' "$fake_git_log" || fail "pr-amend did not use force-with-lease"
if grep -Eq '(^|[[:space:]])--force([[:space:]]|$)' "$fake_git_log"; then
    fail "pr-amend used an unguarded force-push"
fi
grep -Fq 'Press Ctrl-C to cancel' "$test_dir/amend-warning" || fail "force-push warning omitted the cancellation window"

previous_head=$(git -C "$clone_dir" rev-parse HEAD)
: >"$fake_git_log"
if (
    cd "$clone_dir"
    pr-amend 2>"$test_dir/nothing-amend-error"
); then
    fail "pr-amend accepted no staged changes"
fi
[[ "$(git -C "$clone_dir" rev-parse HEAD)" == "$previous_head" ]] || fail "empty amend rewrote history"
grep -Fq 'nothing is staged to amend' "$test_dir/nothing-amend-error" || fail "empty-amend error was unclear"
if grep -Fq 'push ' "$fake_git_log"; then
    fail "empty amend attempted a push"
fi

(
    cd "$clone_dir"
    pr-amend --all >/dev/null 2>"$test_dir/amend-all-warning"
)
git -C "$clone_dir" ls-files --error-unmatch untracked.txt >/dev/null || fail "pr-amend --all omitted an untracked file"

remote_before_cancel=$(git --git-dir="$fork_repo" rev-parse refs/heads/feature/rewrite)
printf 'cancelled push\n' >>"$clone_dir/tracked.txt"
: >"$fake_git_log"
export FAKE_SLEEP_INTERRUPT=1
if (
    cd "$clone_dir"
    pr-amend 2>"$test_dir/cancel-warning"
); then
    fail "pr-amend ignored cancellation during the force-push window"
fi
unset FAKE_SLEEP_INTERRUPT
[[ "$(git --git-dir="$fork_repo" rev-parse refs/heads/feature/rewrite)" == "$remote_before_cancel" ]] || fail "cancelled amend changed the remote branch"
if grep -Fq 'push ' "$fake_git_log"; then
    fail "cancelled amend reached the push step"
fi
grep -Fq 'history rewritten locally but push cancelled; retry with: git push --force-with-lease --set-upstream origin HEAD' "$test_dir/cancel-warning" || fail "cancelled amend omitted the guarded retry command"

printf 'invalid delay\n' >>"$clone_dir/tracked.txt"
previous_head=$(git -C "$clone_dir" rev-parse HEAD)
export DEV_TOOLS_FORCE_PUSH_DELAY=invalid
if (
    cd "$clone_dir"
    pr-amend 2>"$test_dir/delay-error"
); then
    fail "pr-amend accepted an invalid force-push delay"
fi
[[ "$(git -C "$clone_dir" rev-parse HEAD)" == "$previous_head" ]] || fail "invalid delay rewrote history"
git -C "$clone_dir" diff --cached --quiet || fail "invalid delay staged changes"
grep -Fq 'DEV_TOOLS_FORCE_PUSH_DELAY must be a non-negative number' "$test_dir/delay-error" || fail "invalid-delay error was unclear"
git -C "$clone_dir" restore tracked.txt
export DEV_TOOLS_FORCE_PUSH_DELAY=0

git -C "$clone_dir" switch main >/dev/null
printf 'unsafe amend\n' >>"$clone_dir/tracked.txt"
if (
    cd "$clone_dir"
    pr-amend 2>"$test_dir/default-amend-error"
); then
    fail "pr-amend accepted the default branch"
fi
grep -Fq 'refusing to use the default branch' "$test_dir/default-amend-error" || fail "default-branch amend error was unclear"
git -C "$clone_dir" diff --cached --quiet || fail "default-branch amend staged changes"
git -C "$clone_dir" restore tracked.txt

if (
    cd "$clone_dir"
    pr-rebase release 2>"$test_dir/default-rebase-error"
); then
    fail "pr-rebase accepted the default branch with an explicit base"
fi
grep -Fq 'refusing to rebase the default branch' "$test_dir/default-rebase-error" || fail "default-branch rebase error was unclear"
git -C "$clone_dir" switch feature/rewrite >/dev/null

printf 'upstream addition\n' >"$upstream_work/upstream.txt"
git -C "$upstream_work" add upstream.txt
git -C "$upstream_work" commit -m 'upstream addition' >/dev/null
git -C "$upstream_work" push "$upstream_repo" main >/dev/null 2>&1
upstream_head=$(git -C "$upstream_work" rev-parse HEAD)
: >"$fake_git_log"
(
    cd "$clone_dir"
    pr-rebase 2>"$test_dir/rebase-warning"
)
git -C "$clone_dir" merge-base --is-ancestor "$upstream_head" HEAD || fail "pr-rebase did not include the upstream base"
[[ "$(git --git-dir="$fork_repo" rev-parse refs/heads/feature/rewrite)" == "$(git -C "$clone_dir" rev-parse HEAD)" ]] || fail "rebased branch was not pushed"
grep -Fq 'push --force-with-lease --set-upstream origin HEAD' "$fake_git_log" || fail "pr-rebase did not use force-with-lease"
if grep -Eq '(^|[[:space:]])--force([[:space:]]|$)' "$fake_git_log"; then
    fail "pr-rebase used an unguarded force-push"
fi
grep -Fq 'Press Ctrl-C to cancel' "$test_dir/rebase-warning" || fail "rebase force-push warning was missing"

git -C "$upstream_work" switch -c release >/dev/null
printf 'release base\n' >"$upstream_work/release.txt"
git -C "$upstream_work" add release.txt
git -C "$upstream_work" commit -m 'release base' >/dev/null
git -C "$upstream_work" push "$upstream_repo" release >/dev/null 2>&1
release_head=$(git -C "$upstream_work" rev-parse HEAD)
git -C "$upstream_work" switch main >/dev/null
: >"$fake_git_log"
(
    cd "$clone_dir"
    pr-rebase release 2>"$test_dir/rebase-release-warning"
)
git -C "$clone_dir" merge-base --is-ancestor "$release_head" HEAD || fail "pr-rebase ignored the explicit upstream base"
[[ "$(git --git-dir="$fork_repo" rev-parse refs/heads/feature/rewrite)" == "$(git -C "$clone_dir" rev-parse HEAD)" ]] || fail "explicit-base rebase was not pushed"
grep -Fq 'fetch upstream release' "$fake_git_log" || fail "pr-rebase did not fetch the explicit upstream base"
grep -Fq 'push --force-with-lease --set-upstream origin HEAD' "$fake_git_log" || fail "explicit-base rebase did not use force-with-lease"

printf 'dirty\n' >>"$clone_dir/tracked.txt"
if (
    cd "$clone_dir"
    pr-rebase 2>"$test_dir/dirty-rebase-error"
); then
    fail "pr-rebase accepted tracked changes"
fi
grep -Fq 'tracked changes are present' "$test_dir/dirty-rebase-error" || fail "dirty-rebase error was unclear"
git -C "$clone_dir" restore tracked.txt

if (
    cd "$clone_dir"
    pr-rebase '../invalid' 2>"$test_dir/invalid-base-error"
); then
    fail "pr-rebase accepted an invalid base name"
fi
grep -Fq 'invalid branch name' "$test_dir/invalid-base-error" || fail "invalid-base error was unclear"

: >"$fake_gh_log"
(
    cd "$clone_dir"
    pr-comment "Ready after guarded rewrite" >/dev/null
)
grep -Fq 'auth status' "$fake_gh_log" || fail "pr-comment did not check GitHub CLI authentication"
grep -Fq 'pr list --repo github.com/upstream/project --head feature/rewrite --state open --limit 100 --json number,headRepositoryOwner' "$fake_gh_log" || fail "pr-comment did not look up the current fork branch"
grep -Fq 'headRepositoryOwner.login | ascii_downcase' "$fake_gh_log" || fail "pr-comment did not filter matches by fork owner"
grep -Fq '"thelarkbot" | ascii_downcase' "$fake_gh_log" || fail "pr-comment did not use the current fork owner in its match"
grep -Fq 'pr comment 17 --repo github.com/upstream/project --body Ready after guarded rewrite' "$fake_gh_log" || fail "pr-comment did not target the matched upstream pull request"
if grep -Fq 'repo view' "$fake_gh_log"; then
    fail "pr-comment used GitHub API calls for local remote metadata"
fi

: >"$fake_gh_log"
export FAKE_GH_EMPTY_PR=1
if (
    cd "$clone_dir"
    pr-comment "Do not guess" 2>"$test_dir/no-pr-error"
); then
    fail "pr-comment accepted a branch without an open pull request"
fi
unset FAKE_GH_EMPTY_PR
grep -Fq 'no open pull request found for thelarkbot:feature/rewrite in github.com/upstream/project' "$test_dir/no-pr-error" || fail "missing-PR error was unclear"
if grep -Fq 'pr comment ' "$fake_gh_log"; then
    fail "pr-comment posted without a matching pull request"
fi

: >"$fake_gh_log"
export FAKE_GH_MULTIPLE_PRS=1
if (
    cd "$clone_dir"
    pr-comment "Do not guess" 2>"$test_dir/multiple-pr-error"
); then
    fail "pr-comment guessed between multiple open pull requests"
fi
unset FAKE_GH_MULTIPLE_PRS
grep -Fq 'multiple open pull requests found for thelarkbot:feature/rewrite in github.com/upstream/project' "$test_dir/multiple-pr-error" || fail "multiple-PR error was unclear"
if grep -Fq 'pr comment ' "$fake_gh_log"; then
    fail "pr-comment posted when multiple pull requests matched"
fi

printf 'feature conflict\n' >"$clone_dir/conflict.txt"
git -C "$clone_dir" add conflict.txt
git -C "$clone_dir" commit -m 'feature conflict' >/dev/null
git -C "$clone_dir" push origin feature/rewrite >/dev/null 2>&1
printf 'upstream conflict\n' >"$upstream_work/conflict.txt"
git -C "$upstream_work" add conflict.txt
git -C "$upstream_work" commit -m 'upstream conflict' >/dev/null
git -C "$upstream_work" push "$upstream_repo" main >/dev/null 2>&1
if (
    cd "$clone_dir"
    pr-rebase 2>"$test_dir/conflict-error"
); then
    fail "pr-rebase reported success for a conflict"
fi
grep -Fq "git rebase --continue" "$test_dir/conflict-error" || fail "rebase conflict instructions were missing"
grep -Fq "git rebase --abort" "$test_dir/conflict-error" || fail "rebase abort instructions were missing"
git -C "$clone_dir" rebase --abort

git clone "$fork_repo" "$other_clone" >/dev/null 2>&1
git -C "$other_clone" config user.name Other
git -C "$other_clone" config user.email other@example.com
git -C "$other_clone" switch feature/rewrite >/dev/null
printf 'concurrent update\n' >"$other_clone/other.txt"
git -C "$other_clone" add other.txt
git -C "$other_clone" commit -m 'concurrent update' >/dev/null
git -C "$other_clone" push origin feature/rewrite >/dev/null 2>&1
concurrent_head=$(git --git-dir="$fork_repo" rev-parse refs/heads/feature/rewrite)
printf 'stale local amend\n' >>"$clone_dir/feature.txt"
if (
    cd "$clone_dir"
    pr-amend 2>"$test_dir/lease-error"
); then
    fail "force-with-lease overwrote a concurrent remote update"
fi
[[ "$(git --git-dir="$fork_repo" rev-parse refs/heads/feature/rewrite)" == "$concurrent_head" ]] || fail "concurrent remote update was overwritten"
grep -Fq 'history rewritten locally but push failed; inspect the remote before retrying with: git push --force-with-lease --set-upstream origin HEAD' "$test_dir/lease-error" || fail "lease rejection omitted the guarded retry command"

git -C "$clone_dir" switch main >/dev/null
: >"$fake_gh_log"
if (
    cd "$clone_dir"
    pr-comment "Do not comment" 2>"$test_dir/default-comment-error"
); then
    fail "pr-comment accepted the default branch"
fi
grep -Fq 'refusing to use the default branch' "$test_dir/default-comment-error" || fail "default-branch comment error was unclear"
if grep -Fq 'pr comment ' "$fake_gh_log"; then
    fail "default-branch comment reached GitHub"
fi

printf 'rewrite and comment tests passed\n'
