#!/bin/bash

# ============================================================================
# ensure-submodules.sh - make this superproject's submodules ready to work in
#
# Guarantees, for every TOP-LEVEL submodule listed in .gitmodules:
#   1. it is populated (cloned + checked out), recursively, so nested
#      submodules come along with it
#   2. it sits on a local branch whose name matches the superproject's branch,
#      instead of the detached HEAD `git submodule update` leaves behind
#
# A branch that has to be created is always based on the commit the
# superproject records for that submodule (its gitlink), not on wherever the
# submodule's own HEAD happens to sit - the gitlink is the commit this
# superproject checkout actually means.
#
# Only TOP-LEVEL submodules get a branch. Nested submodules are populated but
# left on their gitlink: they are vendored third-party trees, and creating a
# branch named after your feature inside somebody else's repo helps no one.
#
# Nothing here is destructive:
#   - `git submodule update` is only run over a top-level submodule that is
#     not populated yet, where there is no local work to rewind. A populated
#     one is only asked to fill in its own nested submodules.
#   - `git checkout -B` is never used, so a submodule branch that already
#     carries local commits is never moved.
#   - any git failure becomes a warning naming the manual command to run, and
#     the script still succeeds.
#
# Runs against the WORKTREE it is invoked from (`git rev-parse --show-toplevel`
# from the starting directory), which is what a worktree session should sync;
# in a plain checkout that is simply the repository itself.
#
# Output: plain text on stdout, empty when there was nothing to do.
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
Usage: $SCRIPT_NAME [-C <dir>]

Populates every submodule recursively and attaches each top-level submodule to
a branch named after the superproject's current branch. Warns and succeeds when
it cannot. Prints nothing when everything is already correct.

Options:
  -C <dir>   Start from <dir> instead of the current directory
  -h, --help Show this help
EOF
}

# Print the report and stop. Always a success: a hook that fails would cost the
# user a session, and no submodule problem is worth that.
finish() {
    render_report
    exit 0
}

on_error() {
    local code=$?
    trap - ERR

    # `set -E` propagates this trap into command-substitution subshells too.
    # Reporting from there would splice the warning into the value the caller
    # is capturing - e.g. BRANCH="$(...)" would come back holding a warning.
    # Inside a subshell, just fail; the parent decides what the failure means.
    #
    # BASH_SUBSHELL, not BASHPID: bash 3.2 - still /bin/bash on macOS - has no
    # BASHPID, so reading it under `set -u` killed this handler with an
    # "unbound variable" error on exactly the paths it exists to keep quiet.
    if [[ "${BASH_SUBSHELL:-0}" -ne 0 ]]; then
        exit "$code"
    fi

    add_warning "$SCRIPT_NAME failed unexpectedly (exit $code at line ${BASH_LINENO[0]:-?})"
    finish
}

trap on_error ERR

# Resolve the tree to work in and the branch every submodule should mirror.
# Returns non-zero when there is nothing to do at all.
resolve_context() {
    local start="$1" main_repo

    REPO_ROOT="$(git -C "$start" rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "$REPO_ROOT" ]] || return 1

    # Rule one, same as git-sync.sh: no remote means this plugin stays out of
    # the way. Cloning submodules needs the network anyway.
    main_repo="$(resolve_main_repo "$start")" || return 1
    first_remote "$main_repo" >/dev/null || return 1

    [[ -f "$REPO_ROOT/.gitmodules" ]] || return 1

    BRANCH="$(git -C "$REPO_ROOT" symbolic-ref --short -q HEAD || true)"
    if [[ -z "$BRANCH" ]]; then
        add_warning "the superproject is on a detached HEAD; submodules will be populated but not attached to a branch"
    fi
}

# Top-level submodule paths, straight from the committed .gitmodules.
submodule_paths() {
    git -C "$REPO_ROOT" config -f "$REPO_ROOT/.gitmodules" \
        --get-regexp '^submodule\..*\.path$' 2>/dev/null \
        | sed 's/^[^ ]* //' || true
}

# Populate a top-level submodule and everything underneath it.
ensure_populated() {
    local path="$1"

    if [[ -e "$REPO_ROOT/$path/.git" ]]; then
        # Already populated: never run `submodule update` over it, that would
        # rewind any local work to the gitlink. Only fill in nested modules,
        # which is a no-op when it has none.
        if ! run_capture git -C "$REPO_ROOT/$path" submodule update --init --recursive; then
            add_warning "could not initialize nested submodules under $path ($(capture_reason)); run: git -C '$REPO_ROOT/$path' submodule update --init --recursive"
        fi
        return 0
    fi

    if run_capture git -C "$REPO_ROOT" submodule update --init --recursive -- "$path"; then
        add_note "initialized $path"
        return 0
    fi

    add_warning "could not initialize $path ($(capture_reason)); run: git -C '$REPO_ROOT' submodule update --init --recursive -- '$path'"
    return 1
}

# The commit the superproject's HEAD records for a submodule (its gitlink).
gitlink_commit() {
    git -C "$REPO_ROOT" rev-parse -q --verify "HEAD:$1" 2>/dev/null || true
}

# Attach a populated submodule to $BRANCH, creating that branch at the gitlink
# commit when it does not exist yet.
ensure_branch() {
    local path="$1" sub="$REPO_ROOT/$path" current base
    local -a cmd
    local what

    current="$(git -C "$sub" symbolic-ref --short -q HEAD || true)"
    if [[ "$current" == "$BRANCH" ]]; then
        return 0
    fi

    if git -C "$sub" show-ref --verify --quiet "refs/heads/$BRANCH"; then
        # The branch already exists and may carry local commits; moving it
        # would throw those away, so only check it out.
        cmd=(checkout "$BRANCH")
        what="switched $path to existing branch $BRANCH"
    else
        base="$(gitlink_commit "$path")"
        if [[ -n "$base" ]] && git -C "$sub" cat-file -e "${base}^{commit}" 2>/dev/null; then
            cmd=(checkout -b "$BRANCH" "$base")
            what="created branch $BRANCH in $path at ${base:0:7}"
        else
            # No usable gitlink (detached superproject tree, unfetched commit):
            # fall back to the submodule's own HEAD.
            cmd=(checkout -b "$BRANCH")
            what="created branch $BRANCH in $path"
        fi
    fi

    if run_capture git -C "$sub" "${cmd[@]}"; then
        add_note "$what"
        return 0
    fi

    add_warning "could not attach $path to $BRANCH ($(capture_reason)); run: git -C '$sub' ${cmd[*]}"
    return 1
}

main() {
    local path

    if ! resolve_context "$START_DIR"; then
        finish
    fi

    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        ensure_populated "$path" || continue
        [[ -n "$BRANCH" ]] || continue
        ensure_branch "$path" || continue
    done < <(submodule_paths)

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
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

main
