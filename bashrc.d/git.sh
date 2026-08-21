#!/usr/bin/env bash

_dev_git_error() {
    printf 'ERROR: %s\n' "$*" >&2
}

_dev_git_require_repo() {
    git rev-parse --git-dir >/dev/null 2>&1 || {
        _dev_git_error "not in a Git repository"
        return 1
    }
}

_dev_git_require_gh() {
    command -v gh >/dev/null 2>&1 || {
        _dev_git_error "GitHub CLI (gh) is not installed"
        return 1
    }
    gh auth status >/dev/null 2>&1 || {
        _dev_git_error "GitHub CLI is not authenticated; run: gh auth login"
        return 1
    }
}

_dev_git_require_topology() {
    _dev_git_require_repo || return 1
    git remote get-url origin >/dev/null 2>&1 || {
        _dev_git_error "missing 'origin' remote (expected personal fork)"
        return 1
    }
    git remote get-url upstream >/dev/null 2>&1 || {
        _dev_git_error "missing 'upstream' remote (expected canonical repository)"
        return 1
    }
}

_dev_git_require_clean() {
    if ! git diff --quiet || ! git diff --cached --quiet; then
        _dev_git_error "tracked changes are present; commit or stash them first"
        git status --short >&2
        return 1
    fi
}

_dev_git_current_branch() {
    local branch
    branch=$(git branch --show-current) || return 1
    if [[ -z "$branch" ]]; then
        _dev_git_error "detached HEAD is not supported"
        return 1
    fi
    printf '%s\n' "$branch"
}

_dev_git_default_branch() {
    local branch
    branch=$(git symbolic-ref --quiet --short refs/remotes/upstream/HEAD 2>/dev/null) || true
    if [[ -n "$branch" ]]; then
        printf '%s\n' "${branch#upstream/}"
        return 0
    fi

    branch=$(gh repo view "$(git remote get-url upstream)" --json defaultBranchRef --jq '.defaultBranchRef.name') || return 1
    if [[ -z "$branch" ]]; then
        _dev_git_error "could not determine the upstream default branch"
        return 1
    fi
    printf '%s\n' "$branch"
}

pr-help() {
    cat <<'EOF'
dev-tools commands:

  fork-clone [HOST/]OWNER/REPOSITORY [DIRECTORY]
      Fork, clone, configure origin/upstream, and fetch upstream.

  fork-sync
      Fast-forward the local default branch from upstream and push to origin.

  pr-help
      Show this command reference.
EOF
}

fork-clone() {
    if [[ $# -lt 1 || $# -gt 2 ]]; then
        printf 'usage: fork-clone [HOST/]OWNER/REPOSITORY [DIRECTORY]\n' >&2
        return 2
    fi
    _dev_git_require_gh || return 1

    local input="$1" directory="${2:-}" host path owner repository login clone_target
    if [[ "$input" == */*/* ]]; then
        host="${input%%/*}"
        path="${input#*/}"
    else
        host="github.com"
        path="$input"
    fi
    owner="${path%%/*}"
    repository="${path#*/}"
    if [[ -z "$owner" || -z "$repository" || "$repository" == */* ]]; then
        _dev_git_error "repository must be [HOST/]OWNER/REPOSITORY"
        return 2
    fi

    gh auth status --hostname "$host" >/dev/null 2>&1 || {
        _dev_git_error "not authenticated to $host; run: gh auth login --hostname $host"
        return 1
    }
    login=$(gh api --hostname "$host" user --jq '.login') || return 1
    gh repo fork "$host/$owner/$repository" --clone=false || return 1

    clone_target="$host/$login/$repository"
    if [[ -n "$directory" ]]; then
        gh repo clone "$clone_target" "$directory" --upstream-remote-name upstream || return 1
        directory=${directory%/}
    else
        gh repo clone "$clone_target" --upstream-remote-name upstream || return 1
        directory="$repository"
    fi

    git -C "$directory" remote get-url upstream >/dev/null 2>&1 || {
        _dev_git_error "the cloned fork has no upstream remote"
        return 1
    }
    git -C "$directory" fetch upstream || return 1
    git -C "$directory" remote set-head upstream --auto >/dev/null 2>&1 || true
    printf 'Fork clone ready: %s (origin=%s/%s, upstream=%s/%s)\n' \
        "$directory" "$login" "$repository" "$owner" "$repository"
}

fork-sync() {
    _dev_git_require_topology || return 1
    _dev_git_require_clean || return 1
    _dev_git_require_gh || return 1

    local base current
    base=$(_dev_git_default_branch) || return 1
    current=$(_dev_git_current_branch) || return 1
    if [[ "$current" != "$base" ]]; then
        git switch "$base" || return 1
    fi
    git fetch upstream "$base" || return 1
    git merge --ff-only "upstream/$base" || return 1
    git push origin "HEAD:$base"
}
