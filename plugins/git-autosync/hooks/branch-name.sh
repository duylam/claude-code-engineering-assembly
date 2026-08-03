#!/bin/bash

# ============================================================================
# branch-name.sh - put this tree and all its submodules on one named branch
#
# A session that started on `worktree-a3f19c` and turned into a piece of real
# work wants a name that says so, in the superproject AND in every submodule it
# touched, so the commits on both sides carry the same label.
#
# For each of the superproject and every populated TOP-LEVEL submodule:
#
#   branch does not exist  -> git checkout -b <name>   (at whatever HEAD is)
#   branch already exists  -> git checkout <name>      (never moved)
#
# `checkout -b` with no start point branches from HEAD, so uncommitted work
# comes along to the new branch untouched - which is the point when a session
# has been running for an hour before anyone thought of a name.
#
# What it deliberately does NOT do:
#   - delete or rename the branch it left; that branch still points at the same
#     commit, and `git checkout -` goes straight back to it
#   - touch the remote: nothing is pushed, nothing is deleted upstream
#   - move an existing branch (`checkout -B` is never used), so a name already
#     in use keeps its commits and is simply switched to
#
# Unlike the sync workers this one is NEVER run from a hook - only from the
# `branch-name` skill, at a human's request. So it reports failure honestly:
# if the SUPERPROJECT cannot be switched, nothing meaningful happened and it
# exits non-zero. A submodule that refuses becomes a warning naming the exact
# command, and the remaining submodules are still done - one stubborn submodule
# should not strand the rest.
#
# Output: plain text on stdout, empty when everything was already on <name>.
# Dependencies: git.
# ============================================================================

# -E propagates the ERR trap into functions, so an unexpected failure inside
# one still reaches on_error instead of exiting silently.
set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/git-common.sh
source "$SCRIPT_DIR/lib/git-common.sh"

START_DIR="$PWD"
REPO_ROOT=""
BRANCH=""

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [-C <dir>] <branch-name>

Checks out <branch-name> in this working tree and in every populated top-level
submodule, creating it at the current HEAD where it does not exist yet. Never
moves an existing branch, never touches the remote.

Options:
  -C <dir>   Start from <dir> instead of the current directory
  -h, --help Show this help
EOF
}

# Print the report and stop.
finish() {
    render_report
    exit "${1:-0}"
}

on_error() {
    local code=$?
    trap - ERR

    # `set -E` propagates this trap into command-substitution subshells too.
    # Reporting from there would splice the warning into the value the caller
    # is capturing. Inside a subshell, just fail; the parent decides what the
    # failure means.
    #
    # BASH_SUBSHELL, not BASHPID: bash 3.2 - still /bin/bash on macOS - has no
    # BASHPID, so reading it under `set -u` killed this handler with an
    # "unbound variable" error on exactly the paths it exists to keep quiet.
    if [[ "${BASH_SUBSHELL:-0}" -ne 0 ]]; then
        exit "$code"
    fi

    add_warning "$SCRIPT_NAME failed unexpectedly (exit $code at line ${BASH_LINENO[0]:-?})"
    finish 1
}

trap on_error ERR

# Check out $2 in the tree at $1, creating it at HEAD when it does not exist.
# $3 names the tree for the report. Returns non-zero when git refused.
attach() {
    local tree="$1" name="$2" label="$3" current head
    local -a cmd
    local what

    current="$(git -C "$tree" symbolic-ref --short -q HEAD || true)"
    if [[ "$current" == "$name" ]]; then
        return 0
    fi

    if git -C "$tree" show-ref --verify --quiet "refs/heads/$name"; then
        # The branch exists and may carry commits; moving it would throw those
        # away, so only switch to it. `checkout -B` is deliberately not used.
        cmd=(checkout "$name")
        what="switched $label to existing branch $name"
    else
        # No start point: branch from wherever this tree already stands, so
        # uncommitted work follows along instead of being left behind.
        head="$(git -C "$tree" rev-parse --short HEAD 2>/dev/null || true)"
        cmd=(checkout -b "$name")
        what="created branch $name in $label at ${head:-HEAD}"
    fi

    if run_capture git -C "$tree" "${cmd[@]}"; then
        add_note "$what"
        return 0
    fi

    add_warning "could not put $label on $name ($(capture_reason)); run: git -C '$tree' ${cmd[*]}"
    return 1
}

main() {
    local name path

    if [[ -z "$BRANCH" ]]; then
        echo "$SCRIPT_NAME: a branch name is required" >&2
        usage >&2
        exit 1
    fi

    # git's own validator, so a name this script accepts is a name git accepts.
    if ! git check-ref-format --branch "$BRANCH" >/dev/null 2>&1; then
        echo "$SCRIPT_NAME: '$BRANCH' is not a valid branch name" >&2
        exit 1
    fi

    # The WORKTREE, not resolve_main_repo: checking out a branch is a working-
    # tree operation, and in a worktree session the worktree is the tree the
    # user means.
    REPO_ROOT="$(git -C "$START_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -z "$REPO_ROOT" ]]; then
        echo "$SCRIPT_NAME: $START_DIR is not inside a git repository" >&2
        exit 1
    fi

    # The superproject first, and its failure is fatal: landing only the
    # submodules on the new name would be worse than landing nothing.
    attach "$REPO_ROOT" "$BRANCH" "the superproject" || finish 1

    while IFS=$'\t' read -r name path; do
        [[ -n "$path" ]] || continue
        # Unpopulated submodules have no HEAD to branch from. ensure-submodules
        # is what fills those in; this script does not clone anything.
        [[ -e "$REPO_ROOT/$path/.git" ]] || continue
        attach "$REPO_ROOT/$path" "$BRANCH" "$path" || continue
    done < <(submodule_entries "$REPO_ROOT")

    finish
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -C)
            START_DIR="${2:-}"
            if [[ -z "$START_DIR" || ! -d "$START_DIR" ]]; then
                echo "$SCRIPT_NAME: -C needs an existing directory" >&2
                exit 1
            fi
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            if [[ -n "$BRANCH" ]]; then
                echo "$SCRIPT_NAME: only one branch name is accepted" >&2
                usage >&2
                exit 1
            fi
            BRANCH="$1"
            shift
            ;;
    esac
done

main
