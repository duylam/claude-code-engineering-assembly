#!/bin/bash

# ============================================================================
# git-sync.sh - attach this working tree to the remote default branch
#
# Network-free. This plugin never fetches: the `git` plugin refreshes the
# remote-tracking refs at SessionStart, and this script reads them. Two things
# happen, in this order:
#
#   1. the branch the tree is ON is fast-forwarded to <remote>/<default>, where
#      <default> is `main` falling back to `master`      -> sync_current_branch
#   2. every top-level submodule is populated (one level), attached to a branch,
#      and reconciled with the superproject's gitlink     -> ensure-submodules.sh
#
# The reconciliation is fast-forward ONLY: it brings the remote's commits in
# when the branch has none of its own, and is left untouched otherwise ("ignore
# if it can't"). Nothing is ever destroyed. Problems are reported as `Warning:`
# or note lines on stdout and the script still exits 0 (or 10 for a clean
# no-op) - a hook that failed would cost the user a session or a worktree.
#
#   not a git repo                            -> silent, exit 10
#   repo has no remote                        -> silent, exit 10
#   no <default> remote-tracking ref locally  -> warn, exit 10 (git plugin fetch
#                                                first)
#   tree on a detached HEAD                    -> do nothing, exit 10
#   current branch already has the remote      -> attached, exit 0
#   current branch behind, clean               -> fast-forward, exit 0
#   current branch diverged / dirty            -> left as is (noted), exit 0
#
# Exit 0 means the tree was attached and the pass ran (the caller may then tell
# the agent the git state is attached). Exit 10 means nothing was done. Both are
# success - the distinction only drives the caller's summary message.
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
# with the first one that exists locally winning.
source "$SCRIPT_DIR/lib/git-common.sh"

START_DIR="$PWD"
MAIN_REPO=""
REMOTE=""

# Set to 1 once the tree is confirmed attached and the sync pass runs. Drives
# the exit code, which tells the caller whether to announce the attached state.
SYNC_RAN=0

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [-C <dir>]

Fast-forwards the branch this tree is on to <remote>/<default> (one of
${BRANCH_CANDIDATES[*]}) using the local remote-tracking refs - no fetch - then
attaches and reconciles every top-level submodule. Fast-forward only, never
destructive. Does nothing on a detached HEAD. Prints nothing when everything is
already in sync.

Options:
  -C <dir>   Start from <dir> instead of the current directory
  -h, --help Show this help
EOF
}

# Render the report and stop, with an exit code that tells the caller whether
# the sync actually ran (0) or was a clean no-op (10). Both are success.
finish_ran() {
    render_report
    exit 0
}

finish_noop() {
    render_report
    exit 10
}

on_error() {
    local code=$?
    trap - ERR

    # `set -E` propagates this trap into command-substitution subshells too.
    # Reporting from there would splice the warning into the value the caller is
    # capturing. Inside a subshell, just fail; the parent decides what it means.
    #
    # BASH_SUBSHELL, not BASHPID: bash 3.2 - still /bin/bash on macOS - has no
    # BASHPID, so reading it under `set -u` killed this handler with an
    # "unbound variable" error on exactly the paths it exists to keep quiet.
    if [[ "${BASH_SUBSHELL:-0}" -ne 0 ]]; then
        exit "$code"
    fi

    add_warning "$SCRIPT_NAME failed unexpectedly (exit $code at line ${BASH_LINENO[0]:-?})"
    # An unexpected failure on the attached path still counts as having run.
    if [[ "$SYNC_RAN" -eq 1 ]]; then
        finish_ran
    fi
    finish_noop
}

trap on_error ERR

# Fast-forward the branch THIS tree is standing on to <remote>/<default>.
#
# Applies to whatever branch is checked out - the default branch itself, a
# session `worktree-*` branch, or a human's feature branch. A `claude
# remote-control --spawn worktree` worktree is cut from <remote>/<default> and
# lands on `worktree-<name>`; this brings that branch level with the remote's
# refreshed ref without a fetch of its own.
#
# Detached HEAD -> nothing at all: the root repo must be attached for this
# plugin to act. Diverged or dirty -> left untouched ("ignore if it can't").
sync_current_branch() {
    local branch="$1" remote_sha="$2"
    local tree current head_sha behind

    tree="$(git -C "$START_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "$tree" ]] || return 0

    current="$(git -C "$tree" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    if [[ -z "$current" ]]; then
        # Detached HEAD: act only when the root repo is attached. There is no
        # branch to reconcile, so this is a deliberate no-op.
        return 0
    fi

    head_sha="$(git -C "$tree" rev-parse HEAD 2>/dev/null || true)"
    [[ -n "$head_sha" ]] || return 0

    # The tree is attached; the sync pass is running from here on.
    SYNC_RAN=1

    # Already contains everything the remote-tracking ref has - the quiet case.
    if git -C "$tree" merge-base --is-ancestor "$remote_sha" "$head_sha"; then
        return 0
    fi

    behind="$(git -C "$tree" rev-list --count "$head_sha..$remote_sha" 2>/dev/null || echo "?")"

    if tree_is_dirty "$tree"; then
        add_warning "$current is $behind commit(s) behind $REMOTE/$branch but $tree has uncommitted changes; not fast-forwarding"
        return 0
    fi

    if run_capture git -C "$tree" merge --ff-only "$remote_sha"; then
        add_note "fast-forwarded $current to $REMOTE/$branch (${remote_sha:0:7}) in $tree; it was $behind commit(s) behind"
        return 0
    fi

    # Cannot fast-forward: the branch carries commits of its own. This is the
    # normal state of a session branch with work on it - leave it as is.
    add_note "$current has local commits and cannot be fast-forwarded to $REMOTE/$branch (${remote_sha:0:7}); leaving it as is"
}

# Hand the submodules to their own worker.
#
# The report collected so far is flushed first, and the buffer emptied, so the
# child can write straight to stdout in the right order and the caller's final
# render has nothing left to print.
sync_submodules() {
    local status=0

    [[ -f "$SCRIPT_DIR/ensure-submodules.sh" ]] || return 0

    render_report
    NOTES=()
    WARNINGS=()

    bash "$SCRIPT_DIR/ensure-submodules.sh" -C "$START_DIR" || status=$?
    return "$status"
}

main() {
    local branch remote_sha sub_status=0

    # Rule one: outside a git repo, or in a repo with no remote, this plugin does
    # nothing at all - silently.
    MAIN_REPO="$(resolve_main_repo "$START_DIR")" || exit 10
    REMOTE="$(first_remote "$MAIN_REPO")" || exit 10

    # A worktree directory that is not ignored makes the main checkout dirty
    # forever, and the dirty-tree guard below would then refuse every
    # fast-forward for the life of the clone.
    ensure_worktrees_excluded "$MAIN_REPO"

    # No fetch. Read the default branch from the EXISTING local remote-tracking
    # refs, which the `git` plugin keeps fresh.
    branch="$(resolve_default_branch "$MAIN_REPO" "remotes/$REMOTE")"
    if [[ -z "$branch" ]]; then
        add_warning "$REMOTE has no ${BRANCH_CANDIDATES[*]} remote-tracking branch locally; the git plugin's fetch has not run"
        finish_noop
    fi

    remote_sha="$(git -C "$MAIN_REPO" rev-parse "refs/remotes/$REMOTE/$branch")"

    # The branch the session is on. Attaches it; a detached HEAD is a no-op.
    sync_current_branch "$branch" "$remote_sha"

    # Detached (or no tree): nothing was done, and there is no branch for the
    # submodules to mirror either. Report the clean no-op and stop.
    if [[ "$SYNC_RAN" -ne 1 ]]; then
        finish_noop
    fi

    # Submodules last: they are the slow part.
    sync_submodules || sub_status=$?

    render_report
    # The pass ran (attached), regardless of a submodule sub-status - the
    # submodule worker never fails the session either.
    exit 0
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
