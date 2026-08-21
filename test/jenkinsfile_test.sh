#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
jenkinsfile="$project_dir/Jenkinsfile"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

grep -Fq 'pipeline {' "$jenkinsfile" || fail "Declarative pipeline is missing"
grep -Fq 'agent none' "$jenkinsfile" || fail "pipeline should not reserve an agent globally"
grep -Fq "agent { label 'linux' }" "$jenkinsfile" || fail "Validate stage does not target a linux agent"
grep -Fq 'checkout scm' "$jenkinsfile" || fail "source checkout is missing"
shellcheck_step=$(grep -E "sh ['\"]shellcheck " "$jenkinsfile" || true)
[[ "$shellcheck_step" == *'bashrc.d/*.sh'* ]] || fail "ShellCheck does not cover every bashrc helper"
[[ "$shellcheck_step" == *'install.sh'* ]] || fail "ShellCheck does not cover the installer"
[[ "$shellcheck_step" == *'uninstall.sh'* ]] || fail "ShellCheck does not cover the uninstaller"
[[ "$shellcheck_step" == *'test/*.sh'* ]] || fail "ShellCheck does not cover every shell test"
grep -Fq 'for test_script in test/*.sh; do' "$jenkinsfile" || fail "pipeline does not discover every shell test"
# shellcheck disable=SC2016
grep -Fq 'bash "$test_script"' "$jenkinsfile" || fail "pipeline does not execute discovered shell tests"

if grep -Eiq 'podman\.sock|docker\.sock|credentials' "$jenkinsfile" ||
    grep -Eiq "sh[[:space:]]+['\"]+[[:space:]]*just([[:space:]]|['\"])" "$jenkinsfile" ||
    grep -Eiq '^[[:space:]]*just([[:space:]]|$)' "$jenkinsfile"; then
    fail "Jenkinsfile requests a forbidden local-CI dependency"
fi

printf 'Jenkinsfile contract tests passed\n'
