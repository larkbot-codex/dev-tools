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

_dev_git_default_branch_local() {
    local branch
    branch=$(git symbolic-ref --quiet --short refs/remotes/upstream/HEAD 2>/dev/null) || true
    if [[ -n "$branch" ]]; then
        printf '%s\n' "${branch#upstream/}"
        return 0
    fi
    return 1
}

_dev_git_default_branch() {
    local branch remote_head
    branch=$(_dev_git_default_branch_local) && {
        printf '%s\n' "$branch"
        return 0
    }

    remote_head=$(git ls-remote --symref upstream HEAD 2>/dev/null) || true
    branch=$(awk '$1 == "ref:" && $3 == "HEAD" {
        sub("^refs/heads/", "", $2)
        print $2
        exit
    }' <<<"$remote_head")
    if [[ -z "$branch" ]]; then
        _dev_git_error "could not determine the upstream default branch"
        return 1
    fi
    printf '%s\n' "$branch"
}

_dev_git_parse_remote() {
    if [[ $# -ne 1 || -z "$1" ]]; then
        _dev_git_error "remote URL must identify HOST/OWNER/REPOSITORY"
        return 1
    fi

    local input="$1" host path owner repository
    case "$input" in
        *://*)
            input="${input#*://}"
            input="${input#*@}"
            host="${input%%/*}"
            path="${input#*/}"
            if [[ "$host" =~ ^(.+):[0-9]+$ ]]; then
                host="${BASH_REMATCH[1]}"
            fi
            ;;
        *@*:*/*)
            input="${input#*@}"
            host="${input%%:*}"
            path="${input#*:}"
            ;;
        */*/*)
            host="${input%%/*}"
            path="${input#*/}"
            ;;
        *)
            _dev_git_error "remote URL must identify HOST/OWNER/REPOSITORY"
            return 1
            ;;
    esac

    owner="${path%%/*}"
    repository="${path#*/}"
    repository="${repository%.git}"
    if [[ ! "$host" =~ ^[A-Za-z0-9.-]+$ ||
        ! "$owner" =~ ^[A-Za-z0-9_.-]+$ ||
        ! "$repository" =~ ^[A-Za-z0-9_.-]+$ ]]; then
        _dev_git_error "remote URL must identify HOST/OWNER/REPOSITORY"
        return 1
    fi

    printf '%s/%s/%s\n' "$host" "$owner" "$repository"
}

_dev_git_upstream_repo() {
    local remote parsed
    remote=$(git remote get-url upstream) || return 1
    parsed=$(_dev_git_parse_remote "$remote") || {
        _dev_git_error "could not determine the upstream repository"
        return 1
    }
    printf '%s\n' "$parsed"
}

_dev_git_origin_owner() {
    local remote parsed path
    remote=$(git remote get-url origin) || return 1
    parsed=$(_dev_git_parse_remote "$remote") || {
        _dev_git_error "could not determine the origin repository owner"
        return 1
    }
    path="${parsed#*/}"
    printf '%s\n' "${path%%/*}"
}

_dev_git_require_branch_other_than() {
    local base="$1" branch
    branch=$(_dev_git_current_branch) || return 1
    if [[ "$branch" == "$base" ]]; then
        _dev_git_error "refusing to use the default branch; create or switch to a feature branch"
        return 1
    fi
}

_dev_git_require_feature_branch() {
    local base
    base=$(_dev_git_default_branch) || return 1
    _dev_git_require_branch_other_than "$base"
}

_dev_git_require_feature_branch_local() {
    local base
    base=$(_dev_git_default_branch_local) || {
        _dev_git_error "upstream/HEAD is not set; run: git remote set-head upstream --auto"
        return 1
    }
    _dev_git_require_branch_other_than "$base"
}

_dev_git_stage() {
    if [[ "${1:-}" == "--all" ]]; then
        git add --all
    else
        git add --update
    fi
}

pr-help() {
    cat <<'EOF'
dev-tools commands:

  fork-clone [HOST/]OWNER/REPOSITORY [DIRECTORY]
      Fork, clone, configure origin/upstream, and fetch upstream.

  fork-sync
      Fast-forward the local default branch from upstream and push to origin.

  pr-commit [--all] MESSAGE
      Commit tracked changes, then try to push. --all includes untracked files.

  pr-create [BASE]
      Push and open a draft pull request from the fork to upstream.

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

    git -C "$directory" config --get remote.upstream.url >/dev/null 2>&1 || {
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

    local base current
    base=$(_dev_git_default_branch) || return 1
    current=$(_dev_git_current_branch) || return 1
    if [[ "$current" != "$base" ]]; then
        git switch "$base" || return 1
    fi
    git fetch upstream "$base" || return 1
    git remote set-head upstream "$base" >/dev/null 2>&1 || true
    git merge --ff-only "upstream/$base" || return 1
    git push origin "HEAD:$base"
}

pr-commit() {
    local stage_mode="--tracked"
    if [[ "${1:-}" == "--all" ]]; then
        stage_mode="--all"
        shift
    fi
    if [[ $# -ne 1 ]]; then
        printf 'usage: pr-commit [--all] MESSAGE\n' >&2
        return 2
    fi
    _dev_git_require_topology || return 1
    _dev_git_require_feature_branch_local || return 1
    _dev_git_stage "$stage_mode" || return 1
    if git diff --cached --quiet; then
        _dev_git_error "nothing is staged to commit"
        return 1
    fi
    git commit -m "$1" || return 1
    if ! git push --set-upstream origin HEAD; then
        _dev_git_error "commit created locally but push failed; retry with: git push --set-upstream origin HEAD"
        return 1
    fi
}

pr-create() {
    if [[ $# -gt 1 ]]; then
        printf 'usage: pr-create [BASE]\n' >&2
        return 2
    fi
    _dev_git_require_topology || return 1
    _dev_git_require_clean || return 1
    _dev_git_require_gh || return 1
    _dev_git_require_feature_branch || return 1

    local base branch repository owner
    base="${1:-$(_dev_git_default_branch)}" || return 1
    branch=$(_dev_git_current_branch) || return 1
    repository=$(_dev_git_upstream_repo) || return 1
    owner=$(_dev_git_origin_owner) || return 1
    git push --set-upstream origin HEAD || return 1
    gh pr create --repo "$repository" --base "$base" --head "$owner:$branch" --fill --draft
}
