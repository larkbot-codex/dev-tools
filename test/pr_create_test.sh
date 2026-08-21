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

fake_bin="$test_dir/bin"
fake_gh_log="$test_dir/gh.log"
upstream_work="$test_dir/upstream-work"
upstream_repo="$test_dir/upstream.git"
fork_repo="$test_dir/fork.git"
clone_dir="$test_dir/clone"

mkdir -p "$fake_bin"
cat >"$fake_bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$FAKE_GH_LOG"

if [[ "${1:-} ${2:-}" == "auth status" ]]; then
    exit 0
fi

if [[ "${1:-} ${2:-}" == "repo view" ]]; then
    if [[ "$*" == *"--json url"* ]]; then
        printf 'https://github.com/upstream/project\n'
    elif [[ "$*" == *"--json owner"* ]]; then
        printf 'thelarkbot\n'
    else
        printf 'main\n'
    fi
    exit 0
fi

if [[ "${1:-} ${2:-}" == "pr create" ]]; then
    printf 'https://github.com/upstream/project/pull/1\n'
    exit 0
fi

printf 'unexpected gh invocation: %s\n' "$*" >&2
exit 1
EOF
chmod +x "$fake_bin/gh"

git init -b main "$upstream_work" >/dev/null
git -C "$upstream_work" config user.name Test
git -C "$upstream_work" config user.email test@example.com
printf 'base\n' >"$upstream_work/tracked.txt"
git -C "$upstream_work" add tracked.txt
git -C "$upstream_work" commit -m base >/dev/null
git clone --bare "$upstream_work" "$upstream_repo" >/dev/null 2>&1
git clone --bare "$upstream_work" "$fork_repo" >/dev/null 2>&1
git clone "$fork_repo" "$clone_dir" >/dev/null 2>&1
git -C "$clone_dir" config user.name Test
git -C "$clone_dir" config user.email test@example.com
git -C "$clone_dir" remote add upstream "$upstream_repo"
git -C "$clone_dir" fetch upstream main >/dev/null 2>&1
git -C "$clone_dir" symbolic-ref refs/remotes/upstream/HEAD refs/remotes/upstream/main

export FAKE_GH_LOG="$fake_gh_log"
export PATH="$fake_bin:$PATH"

git -C "$clone_dir" switch -c feature/example >/dev/null
printf 'tracked change\n' >>"$clone_dir/tracked.txt"
printf 'leave untracked\n' >"$clone_dir/untracked.txt"
(
    cd "$clone_dir"
    pr-commit "Update tracked file" >/dev/null
)

git --git-dir="$fork_repo" show-ref --verify --quiet refs/heads/feature/example || fail "feature branch was not pushed"
git -C "$clone_dir" ls-files --error-unmatch untracked.txt >/dev/null 2>&1 && fail "default commit included an untracked file"

(
    cd "$clone_dir"
    pr-commit --all "Add untracked file" >/dev/null
)
git -C "$clone_dir" ls-files --error-unmatch untracked.txt >/dev/null || fail "--all did not include the untracked file"

git -C "$clone_dir" switch main >/dev/null
printf 'do not commit\n' >>"$clone_dir/tracked.txt"
if (
    cd "$clone_dir"
    pr-commit "Unsafe default-branch commit" 2>"$test_dir/default-error"
); then
    fail "pr-commit accepted the default branch"
fi
grep -Fq 'refusing to use the default branch' "$test_dir/default-error" || fail "default-branch error was unclear"
git -C "$clone_dir" restore tracked.txt

git -C "$clone_dir" switch feature/example >/dev/null
printf 'dirty\n' >>"$clone_dir/tracked.txt"
if (
    cd "$clone_dir"
    # shellcheck disable=SC2119
    pr-create 2>"$test_dir/dirty-error"
); then
    fail "pr-create accepted tracked changes"
fi
grep -Fq 'tracked changes are present' "$test_dir/dirty-error" || fail "dirty-worktree error was unclear"
git -C "$clone_dir" restore tracked.txt

(
    cd "$clone_dir"
    # shellcheck disable=SC2119
    pr-create >/dev/null
)
grep -Fq 'pr create --repo github.com/upstream/project --base main --head thelarkbot:feature/example --fill --draft' "$fake_gh_log" || fail "draft upstream pull request was not created correctly"

printf 'commit and PR creation tests passed\n'
