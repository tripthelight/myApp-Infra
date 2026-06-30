#!/usr/bin/env bash

set -Eeuo pipefail

MYAPP_HOME="${MYAPP_HOME:-$HOME}"
FETCH_REMOTE="${FETCH_REMOTE:-true}"
REPOS=(
    "myApp-Infra"
    "myApp-Board"
    "myApp-Member"
    "myApp-Front"
)

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Required command not found: $1" >&2
        exit 1
    fi
}

check_repo() {
    repo_name="$1"
    repo_dir="$MYAPP_HOME/$repo_name"

    echo
    echo "[$repo_name]"

    if [ ! -d "$repo_dir/.git" ]; then
        echo "Git repository does not exist: $repo_dir" >&2
        return 1
    fi

    if [ "$FETCH_REMOTE" = true ]; then
        git -C "$repo_dir" fetch --quiet origin
    fi

    branch="$(git -C "$repo_dir" branch --show-current)"
    status="$(git -C "$repo_dir" status --short)"

    echo "Path: $repo_dir"
    echo "Branch: ${branch:-detached}"
    echo "HEAD: $(git -C "$repo_dir" rev-parse --short HEAD)"

    if [ -n "$branch" ] && git -C "$repo_dir" rev-parse --verify "origin/$branch" >/dev/null 2>&1; then
        read -r behind ahead < <(git -C "$repo_dir" rev-list --left-right --count "HEAD...origin/$branch")
        echo "Remote: origin/$branch"
        echo "Behind remote: $behind"
        echo "Ahead of remote: $ahead"

        if [ "$behind" -eq 0 ] && [ "$ahead" -eq 0 ]; then
            echo "Sync: OK"
        else
            echo "Sync: CHECK"
        fi
    else
        echo "Remote: not found"
        echo "Sync: CHECK"
    fi

    if [ -z "$status" ]; then
        echo "Local changes: none"
    else
        echo "Local changes:"
        printf '%s\n' "$status"
    fi
}

require_command git

failed=false

for repo_name in "${REPOS[@]}"; do
    if ! check_repo "$repo_name"; then
        failed=true
    fi
done

echo
if [ "$failed" = true ]; then
    echo "Server repository check failed." >&2
    exit 1
fi

echo "Server repository check complete."
