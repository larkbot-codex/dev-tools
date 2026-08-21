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
default_clone_parent="$test_dir/default-clone-parent"
enterprise_clone_dir="$test_dir/enterprise-clone"

mkdir -p "$fake_bin"
cat >"$fake_bin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$FAKE_GH_LOG"

if [[ "${1:-} ${2:-}" == "auth status" ]]; then
    exit 0
fi

if [[ "${1:-}" == "api" ]]; then
    printf '%s\n' "$FAKE_GH_LOGIN"
    exit 0
fi

if [[ "${1:-} ${2:-}" == "repo fork" ]]; then
    exit 0
fi

if [[ "${1:-} ${2:-}" == "repo clone" ]]; then
    clone_target="$3"
    shift 3
    directory=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --upstream-remote-name)
                shift 2
                ;;
            --*)
                shift
                ;;
            *)
                directory="$1"
                shift
                ;;
        esac
    done
    directory="${directory:-${clone_target##*/}}"
    git clone "$FAKE_FORK_REPO" "$directory" >/dev/null 2>&1
    git -C "$directory" remote add upstream "$FAKE_UPSTREAM_REPO"
    exit 0
fi

if [[ "${1:-} ${2:-}" == "repo view" ]]; then
    printf 'main\n'
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

export FAKE_GH_LOG="$fake_gh_log"
export FAKE_GH_LOGIN=thelarkbot
export FAKE_FORK_REPO="$fork_repo"
export FAKE_UPSTREAM_REPO="$upstream_repo"
export PATH="$fake_bin:$PATH"

fork-clone upstream/project "$clone_dir" >/dev/null
[[ "$(git -C "$clone_dir" remote get-url origin)" == "$fork_repo" ]] || fail "origin is not the fork"
[[ "$(git -C "$clone_dir" remote get-url upstream)" == "$upstream_repo" ]] || fail "upstream is not canonical"
grep -Fq 'auth status --hostname github.com' "$fake_gh_log" || fail "GitHub.com authentication was not checked"
grep -Fq 'repo fork github.com/upstream/project --clone=false' "$fake_gh_log" || fail "canonical repository was not forked"
grep -Fq "repo clone github.com/thelarkbot/project $clone_dir --upstream-remote-name upstream" "$fake_gh_log" || fail "personal fork was not cloned"

mkdir -p "$default_clone_parent"
(
    cd "$default_clone_parent"
    fork-clone upstream/default-project >/dev/null
)
[[ -d "$default_clone_parent/default-project/.git" ]] || fail "default clone directory was not created"

fork-clone github.example.com/upstream/project "$enterprise_clone_dir" >/dev/null
grep -Fq 'auth status --hostname github.example.com' "$fake_gh_log" || fail "Enterprise authentication was not checked"
grep -Fq 'repo fork github.example.com/upstream/project --clone=false' "$fake_gh_log" || fail "Enterprise repository was not forked"

printf 'upstream change\n' >>"$upstream_work/tracked.txt"
git -C "$upstream_work" commit -am 'upstream change' >/dev/null
git -C "$upstream_work" push "$upstream_repo" main >/dev/null 2>&1
upstream_head=$(git -C "$upstream_work" rev-parse HEAD)

git -C "$clone_dir" switch -c feature/local >/dev/null
git -C "$clone_dir" remote set-head upstream --delete
: >"$fake_gh_log"
(
    cd "$clone_dir"
    fork-sync >/dev/null
)

[[ "$(git -C "$clone_dir" branch --show-current)" == main ]] || fail "fork-sync did not switch to main"
[[ "$(git -C "$clone_dir" rev-parse HEAD)" == "$upstream_head" ]] || fail "local main did not fast-forward"
[[ "$(git --git-dir="$fork_repo" rev-parse refs/heads/main)" == "$upstream_head" ]] || fail "fork main was not updated"
[[ "$(git -C "$clone_dir" symbolic-ref --short refs/remotes/upstream/HEAD)" == upstream/main ]] || fail "remote default branch was not cached locally"
[[ ! -s "$fake_gh_log" ]] || fail "fork-sync invoked GitHub CLI"

printf 'dirty\n' >>"$clone_dir/tracked.txt"
if (
    cd "$clone_dir"
    fork-sync 2>"$test_dir/dirty-error"
); then
    fail "fork-sync accepted tracked changes"
fi
grep -Fq 'tracked changes are present' "$test_dir/dirty-error" || fail "dirty-worktree error was unclear"

printf 'fork clone and sync tests passed\n'
