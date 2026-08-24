#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT
zero_oid=0000000000000000000000000000000000000000

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

repo="$test_dir/repo"
mkdir -p "$repo/.githooks" "$repo/bashrc.d" "$repo/scripts" "$repo/test"
cp "$project_dir/.githooks/pre-commit" "$repo/.githooks/pre-commit"
cp "$project_dir/.githooks/pre-push" "$repo/.githooks/pre-push"
cp "$project_dir/scripts/verify.sh" "$repo/scripts/verify.sh"
cp "$project_dir/install-hooks.sh" "$repo/install-hooks.sh"

cat >"$repo/bashrc.d/example.sh" <<'EOF'
#!/usr/bin/env bash
example() {
    printf 'example\n'
}
EOF
cat >"$repo/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
EOF
cp "$repo/install.sh" "$repo/uninstall.sh"
cat >"$repo/test/example_test.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'example tests passed\n'
EOF

git -C "$repo" init -q -b main
git -C "$repo" config user.name 'Hook Test'
git -C "$repo" config user.email 'hook-test@example.com'
git -C "$repo" add .
git -C "$repo" commit -qm base

(cd "$repo" && bash install-hooks.sh) >/dev/null
[[ "$(git -C "$repo" config --local --get core.hooksPath)" == .githooks ]] || fail "hook installer did not configure the repository"

git -C "$repo" config --local core.hooksPath existing-hooks
if (cd "$repo" && bash install-hooks.sh) 2>"$test_dir/install-error"; then
    fail "hook installer replaced an existing hooks path"
fi
grep -Fq 'Refusing to replace existing core.hooksPath' "$test_dir/install-error" || fail "hook installer refusal was unclear"
git -C "$repo" config --local core.hooksPath .githooks

printf '\nbad() {\n    unused=value\n}\n' >>"$repo/bashrc.d/example.sh"
git -C "$repo" add bashrc.d/example.sh
printf '#!/usr/bin/env bash\nexample() {\n    printf '\''example\\n'\''\n}\n' >"$repo/bashrc.d/example.sh"
if (cd "$repo" && .githooks/pre-commit) >"$test_dir/staged-shellcheck-error" 2>&1; then
    fail "pre-commit checked the worktree instead of the staged shell file"
fi
grep -Fq 'unused' "$test_dir/staged-shellcheck-error" || fail "staged ShellCheck failure was not reported"

git -C "$repo" add bashrc.d/example.sh
printf '\nbad() {\n    unused=value\n}\n' >>"$repo/bashrc.d/example.sh"
(cd "$repo" && .githooks/pre-commit) || fail "pre-commit rejected a clean staged shell file because of unstaged work"
git -C "$repo" restore bashrc.d/example.sh

printf 'trailing whitespace  \n' >>"$repo/test/example_test.sh"
git -C "$repo" add test/example_test.sh
if (cd "$repo" && .githooks/pre-commit) >"$test_dir/whitespace-error" 2>&1; then
    fail "pre-commit accepted staged trailing whitespace"
fi
grep -Fq 'trailing whitespace' "$test_dir/whitespace-error" || fail "staged whitespace failure was not reported"
git -C "$repo" restore --staged --worktree test/example_test.sh

clean_oid=$(git -C "$repo" rev-parse HEAD)
printf '\nbad() {\n    unused=value\n}\n' >>"$repo/bashrc.d/example.sh"
printf 'refs/heads/main %s refs/heads/main %s\n' "$clean_oid" "$zero_oid" |
    (cd "$repo" && .githooks/pre-push) >/dev/null || fail "pre-push checked dirty worktree content instead of the pushed revision"
git -C "$repo" restore bashrc.d/example.sh

printf 'exit 1\n' >>"$repo/test/example_test.sh"
git -C "$repo" add test/example_test.sh
git -C "$repo" -c core.hooksPath=/dev/null commit -qm 'add failing test'
failing_oid=$(git -C "$repo" rev-parse HEAD)
if printf 'refs/heads/main %s refs/heads/main %s\n' "$failing_oid" "$clean_oid" |
    (cd "$repo" && .githooks/pre-push) >"$test_dir/pre-push-output" 2>&1; then
    fail "pre-push accepted a revision with a failing test"
fi
grep -Fq "Verifying refs/heads/main at $failing_oid" "$test_dir/pre-push-output" || fail "pre-push did not identify the failing revision"

printf 'hook tests passed\n'
