#!/bin/bash

# ============================================================================
# git-sync.sh - fast-forward the repo's default branch from its first remote
#
# Runs unattended, so it is deliberately timid: it repairs only what it can do
# safely, warns otherwise, and ALWAYS exits 0. Problems are reported as
# `Warning: ...` lines on stdout, never as a non-zero status - a hook that
# fails would cost the user a session or a worktree, and no sync problem is
# worth that.
#
# The target is always the MAIN repository, even when this script runs from
# inside a linked worktree: the object store and the branch refs live there.
#
#   not a git repo                       -> silent, exit 0
#   repo has no remote                   -> silent, exit 0
#   main repo has uncommitted changes    -> warn, exit 0
#   fetch fails (offline)                -> warn, exit 0
#   neither main nor master on remote    -> warn, exit 0
#   local branch already == remote       -> silent, exit 0
#   local branch diverged from remote    -> warn, exit 0 (never a merge commit)
#   branch checked out in a dirty tree   -> warn, exit 0
#   branch checked out in a clean tree   -> git merge --ff-only there
#   branch checked out nowhere           -> git fetch <remote> <br>:<br>
#
# It never runs `git checkout`: an automatic hook must not move a repository
# off whatever branch a human left it on. When the default branch is not
# checked out anywhere, its ref is fast-forwarded directly, which touches no
# working tree at all.
#
# Scope is the superproject's default branch only - submodules are handled by
# ensure-submodules.sh.
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
# Also supplies BRANCH_CANDIDATES - the default branch names, tried in order,
# with the first one that exists on the remote winning.
source "$SCRIPT_DIR/lib/git-common.sh"

START_DIR="$PWD"
MAIN_REPO=""
REMOTE=""

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [-C <dir>]

Fast-forwards the local default branch (${BRANCH_CANDIDATES[*]}) from the
repository's first remote, without ever switching branches. Warns and succeeds
when it cannot. Prints nothing when the repository is already in sync.

Options:
  -C <dir>   Start from <dir> instead of the current directory
  -h, --help Show this help
EOF
}

# Print the report and stop. Always a success: see the header.
finish() {
    render_report
    exit 0
}

on_error() {
    local code=$?
    trap - ERR

    # `set -E` propagates this trap into command-substitution subshells too.
    # Reporting from there would splice the warning into the value the caller
    # is capturing - e.g. MAIN_REPO="$(resolve_main_repo ...)" would come back
    # holding "Warning: ...". Inside a subshell, just fail; the parent decides
    # what the failure means.
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

# Fast-forward the branch inside the worktree that has it checked out.
sync_checked_out() {
    local worktree="$1" branch="$2" remote_sha="$3" dirty

    dirty="$(git -C "$worktree" status --porcelain)"
    if [[ -n "$dirty" ]]; then
        add_warning "$worktree has $branch checked out with uncommitted changes; skipping the fast-forward (it is $(behind_count "$branch" "$remote_sha") commit(s) behind $REMOTE/$branch)"
        return 0
    fi

    if run_capture git -C "$worktree" merge --ff-only "$remote_sha"; then
        add_note "fast-forwarded $branch to $REMOTE/$branch (${remote_sha:0:7}) in $worktree"
        return 0
    fi

    add_warning "could not fast-forward $branch in $worktree ($(capture_reason))"
}

# Update the branch ref directly. No worktree has it checked out, so nothing
# is switched and no working tree is touched. `git fetch <src>:<dst>` refuses
# a non-fast-forward update unless forced, which is exactly the guarantee we
# want here.
sync_ref_only() {
    local branch="$1" remote_sha="$2" verb="updated"

    if ! git -C "$MAIN_REPO" show-ref --verify --quiet "refs/heads/$branch"; then
        verb="created"
    fi

    if run_capture git -C "$MAIN_REPO" fetch "$REMOTE" "$branch:$branch"; then
        add_note "$verb the local $branch ref at $REMOTE/$branch (${remote_sha:0:7})"
        return 0
    fi

    add_warning "could not update the local $branch ref ($(capture_reason))"
}

# How far the local branch trails the fetched commit.
behind_count() {
    git -C "$MAIN_REPO" rev-list --count "refs/heads/$1..$2" 2>/dev/null || echo "?"
}

main() {
    local branch remote_sha local_sha worktree dirty

    # Rule one: outside a git repo, or in a repo with no remote, this plugin
    # does nothing at all - silently, so it stays invisible in projects it has
    # no business touching.
    MAIN_REPO="$(resolve_main_repo "$START_DIR")" || exit 0
    REMOTE="$(first_remote "$MAIN_REPO")" || exit 0

    # A dirty main checkout is a human's unfinished business. Bail before the
    # fetch: there is nothing this script would be allowed to do afterwards.
    dirty="$(git -C "$MAIN_REPO" status --porcelain)"
    if [[ -n "$dirty" ]]; then
        add_warning "$MAIN_REPO has uncommitted changes; skipping the sync from $REMOTE"
        finish
    fi

    if ! run_capture git -C "$MAIN_REPO" fetch --quiet "$REMOTE"; then
        add_warning "could not fetch $REMOTE ($(capture_reason))"
        finish
    fi

    # Read from the remote-tracking refs, so this must run after the fetch.
    branch="$(resolve_default_branch "$MAIN_REPO" "remotes/$REMOTE")"
    if [[ -z "$branch" ]]; then
        add_warning "$REMOTE has no ${BRANCH_CANDIDATES[*]} branch; cannot merge a known default branch name"
        finish
    fi

    remote_sha="$(git -C "$MAIN_REPO" rev-parse "refs/remotes/$REMOTE/$branch")"
    local_sha="$(git -C "$MAIN_REPO" rev-parse -q --verify "refs/heads/$branch" || true)"

    # Already in sync - the common case, and the quiet one.
    if [[ "$local_sha" == "$remote_sha" ]]; then
        exit 0
    fi

    # A local branch that is not an ancestor of the remote carries commits of
    # its own; fast-forwarding is impossible and merging is the human's call.
    if [[ -n "$local_sha" ]] && ! git -C "$MAIN_REPO" merge-base --is-ancestor "$local_sha" "$remote_sha"; then
        add_warning "local $branch has diverged from $REMOTE/$branch; resolve it by hand in $MAIN_REPO"
        finish
    fi

    worktree="$(worktree_holding_branch "$MAIN_REPO" "$branch")"
    if [[ -n "$worktree" ]]; then
        sync_checked_out "$worktree" "$branch" "$remote_sha"
    else
        sync_ref_only "$branch" "$remote_sha"
    fi

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
