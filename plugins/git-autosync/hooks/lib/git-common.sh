#!/bin/bash

# ============================================================================
# git-common.sh - helpers shared by the git-autosync worker scripts.
#
# Source this file; do not execute it. Callers run under `set -Eeuo pipefail`,
# so nothing here calls `exit`: helpers return a status and the caller decides
# what a failure means. That keeps the "always end success" contract in one
# place - the caller's own `finish`.
# ============================================================================

# The names treated as a repository's default branch, in priority order. Kept
# here rather than in one worker so the sync and the worktree hook can never
# disagree about which branch "the default branch" means - a disagreement
# would silently cut new branches from the wrong place.
readonly BRANCH_CANDIDATES=(main master)

# Collected output. Notes are things that were changed, warnings are things a
# human has to deal with. Both are rendered together, warnings last.
NOTES=()
WARNINGS=()

add_note() {
    NOTES+=("$1")
}

add_warning() {
    WARNINGS+=("$1")
}

# Print everything collected, one line each. Prints nothing at all when there
# is nothing to say, so a repo that is already correct costs the user no
# output and no context.
render_report() {
    local line

    for line in ${NOTES[@]+"${NOTES[@]}"}; do
        echo "$line"
    done
    for line in ${WARNINGS[@]+"${WARNINGS[@]}"}; do
        echo "Warning: $line"
    done
}

# Run a command, capturing its combined output in $CMD_OUTPUT and returning
# its exit status. The ERR trap is cleared inside the capture subshell: `set
# -E` propagates it there, where it would otherwise replace the command's own
# error text with the trap's message.
CMD_OUTPUT=""
run_capture() {
    local status=0

    CMD_OUTPUT="$(trap - ERR; "$@" 2>&1)" || status=$?
    return "$status"
}

# First line of the last captured output - git puts the actionable part there.
capture_reason() {
    echo "${CMD_OUTPUT%%$'\n'*}"
}

# Absolute path of the repository that owns the object store: the main
# checkout, even when called from inside a linked worktree. Returns non-zero
# when $1 is not inside a git repository at all - the signal to do nothing.
resolve_main_repo() {
    local start="$1" common_dir

    common_dir="$(git -C "$start" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
    if [[ -z "$common_dir" ]]; then
        # git < 2.31 has no --path-format, and returns a path relative to the
        # directory git was run in; resolve it by hand.
        common_dir="$(git -C "$start" rev-parse --git-common-dir 2>/dev/null || true)"
        [[ -n "$common_dir" ]] || return 1
        common_dir="$(cd "$start" 2>/dev/null && cd "$common_dir" 2>/dev/null && pwd)" || return 1
    fi

    dirname "$common_dir"
}

# The remote to sync from: the first one git lists, which is `origin` in any
# ordinary clone. Returns non-zero when the repo has no remote - the other
# signal to do nothing.
first_remote() {
    local remote

    remote="$(git -C "$1" remote 2>/dev/null | head -n 1)"
    [[ -n "$remote" ]] || return 1
    echo "$remote"
}

# The first BRANCH_CANDIDATES entry that exists in repo $1 under refs/$2, or
# nothing when none does. $2 selects the namespace to look in: `heads` for
# local branches, `remotes/<remote>` for remote-tracking ones.
resolve_default_branch() {
    local repo="$1" namespace="$2" candidate

    for candidate in "${BRANCH_CANDIDATES[@]}"; do
        if git -C "$repo" show-ref --verify --quiet "refs/$namespace/$candidate"; then
            echo "$candidate"
            return 0
        fi
    done

    # "No default branch here" is an answer, not a failure - callers test the
    # output, and returning non-zero would trip the caller's `set -e`.
    return 0
}

# Absolute path of the worktree that currently has branch $2 checked out, or
# nothing when no worktree does.
worktree_holding_branch() {
    local repo="$1" branch="$2" line path=""

    while IFS= read -r line; do
        case "$line" in
            "worktree "*)
                path="${line#worktree }"
                ;;
            "branch refs/heads/$branch")
                echo "$path"
                return 0
                ;;
        esac
    done < <(git -C "$repo" worktree list --porcelain 2>/dev/null)
}

# The reverse lookup: the branch checked out in worktree $2 of repo $1, or
# nothing when that worktree is detached or unknown. Not the same thing as
# `symbolic-ref` run inside the worktree - this reads the repository's own
# registry, so it still answers for a worktree whose directory has already been
# deleted from disk, which is exactly the case teardown has to handle.
branch_in_worktree() {
    local repo="$1" target="$2" line path=""

    while IFS= read -r line; do
        case "$line" in
            "worktree "*)
                path="${line#worktree }"
                ;;
            "branch refs/heads/"*)
                if [[ "$path" == "$target" ]]; then
                    echo "${line#branch refs/heads/}"
                    return 0
                fi
                ;;
        esac
    done < <(git -C "$repo" worktree list --porcelain 2>/dev/null)
}

# Whether $2 is a LINKED worktree of repo $1. The main checkout is listed too,
# so callers that must not touch it have to exclude it themselves. Registration
# is the only trustworthy proof that a directory is a worktree git owns; a path
# that merely looks like one is not.
worktree_is_registered() {
    local repo="$1" target="$2" line

    while IFS= read -r line; do
        if [[ "$line" == "worktree $target" ]]; then
            return 0
        fi
    done < <(git -C "$repo" worktree list --porcelain 2>/dev/null)

    return 1
}
