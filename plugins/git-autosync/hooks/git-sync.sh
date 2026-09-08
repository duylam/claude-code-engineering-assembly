#!/bin/bash

# ============================================================================
# git-sync.sh - bring this working tree level with its remote
#
# Two things happen, in this order:
#
#   1. the branch the tree is ON is reconciled with <remote>/<default>, where
#      <default> is `main` falling back to `master`   -> sync_current_branch
#   2. every top-level submodule is populated, attached to a branch, and
#      reconciled with the superproject's gitlink     -> ensure-submodules.sh
#
# The reconciliation is always a merge: bring the remote's commits in while
# keeping local ones - a fast-forward when the branch has none of its own, a
# merge commit when it does. Nothing is ever destroyed. Problems are reported as
# `Warning: ...` lines on stdout and the script still exits 0 - a hook that
# failed would cost the user a session or a worktree, and no sync problem is
# worth that.
#
#   not a git repo                        -> silent, exit 0
#   repo has no remote                    -> silent, exit 0
#   fetch fails (offline)                 -> warn, exit 0
#   neither main nor master on remote     -> warn, exit 0
#   current branch already has the remote -> silent
#   current branch behind                 -> fast-forward
#   current branch diverged               -> merge commit
#   merge conflicts                       -> aborted, warn, exit 0
#   dirty tree                            -> warn, skip, exit 0
#
# The fetch is NOT gated on a clean working tree; only the steps that move a
# tree are. See the note in main() for why that distinction is load-bearing.
#
# The DEFAULT BRANCH's ref is maintained separately from all of the above, and
# only when the tree is not standing on it: keeping that ref fresh lets a later
# `git-sync` (or a new branch cut from it) start from an up-to-date base even in
# a session that never checks it out. That path is still strictly fast-forward
# and touches no working tree - see sync_ref_only.
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

# The tree and branch sync_current_branch actually handled, so main() can tell
# whether the default-branch pass below would be a second go at the same ref.
CURRENT_TREE=""
CURRENT_BRANCH=""

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [-C <dir>]

Reconciles the branch this tree is on with <remote>/<default> (one of
${BRANCH_CANDIDATES[*]}), then does the same for every top-level submodule
against its own remote. Merge only, never destructive. Prints nothing when
everything is already in sync.

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
    local worktree="$1" branch="$2" remote_sha="$3"

    if tree_is_dirty "$worktree"; then
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

# Reconcile the branch THIS tree is standing on with <remote>/<default>.
#
# This is the main event, and it applies to whatever branch is checked out -
# the default branch itself, a session `worktree-*` branch, or a human's
# feature branch. A session that starts on a branch cut days ago should not
# have to notice; that is the whole point.
#
# The stale-session-branch case this grew out of is still the one that bites
# most often: `claude remote-control --spawn worktree` builds its worktree
# itself, under `.claude/worktrees/<name>`, and cuts `worktree-<name>` straight
# from `<remote>/<default>` - a remote-tracking ref only as fresh as the last
# fetch. That worktree is built before any session hook runs, so SessionStart
# is the first and only moment the plugin gets to repair it.
#
# Nothing is ever lost: a branch with no commits of its own fast-forwards, one
# with commits gets a merge commit, and a conflicted merge is rolled back rather
# than handed to the session as a conflicted index.
sync_current_branch() {
    local branch="$1" remote_sha="$2"
    local tree current head_sha behind

    tree="$(git -C "$START_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "$tree" ]] || return 0

    current="$(git -C "$tree" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    if [[ -z "$current" ]]; then
        add_warning "$tree is on a detached HEAD; there is no branch to sync (check one out first)"
        return 0
    fi

    head_sha="$(git -C "$tree" rev-parse HEAD 2>/dev/null || true)"
    [[ -n "$head_sha" ]] || return 0

    CURRENT_TREE="$tree"
    CURRENT_BRANCH="$current"

    # Already contains everything the remote has - the common, quiet case.
    if git -C "$tree" merge-base --is-ancestor "$remote_sha" "$head_sha"; then
        return 0
    fi

    behind="$(git -C "$tree" rev-list --count "$head_sha..$remote_sha" 2>/dev/null || echo "?")"

    if tree_is_dirty "$tree"; then
        add_warning "$current is $behind commit(s) behind $REMOTE/$branch but $tree has uncommitted changes; not merging"
        return 0
    fi

    merge_current_branch "$tree" "$current" "$branch" "$head_sha" "$remote_sha" "$behind"
}

# `git merge`, with a conflict rolled back rather than left behind.
#
# --no-edit so an unattended run never waits on an editor it does not have.
merge_current_branch() {
    local tree="$1" current="$2" branch="$3" head_sha="$4" remote_sha="$5" behind="$6"

    if run_capture git -C "$tree" merge --no-edit "$remote_sha"; then
        if git -C "$tree" merge-base --is-ancestor "$head_sha" "$remote_sha"; then
            add_note "fast-forwarded $current to $REMOTE/$branch (${remote_sha:0:7}) in $tree; it was $behind commit(s) behind"
        else
            add_note "merged $REMOTE/$branch (${remote_sha:0:7}) into $current in $tree"
        fi
        return 0
    fi

    # A conflicted merge leaves a half-written index behind. Handing that to a
    # session that never asked for a merge is worse than not merging at all, so
    # put the tree back and let the human start it deliberately.
    local reason
    reason="$(capture_reason)"
    if run_capture git -C "$tree" merge --abort; then
        add_warning "merging $REMOTE/$branch into $current conflicts ($reason); the merge was rolled back - resolve it yourself with: git -C '$tree' merge $REMOTE/$branch"
        return 0
    fi

    add_warning "could not merge $REMOTE/$branch into $current in $tree ($reason), and could not roll the attempt back; check 'git -C \"$tree\" status'"
}

# Hand the submodules to their own worker.
#
# The report collected so far is flushed first, and the buffer emptied, so the
# child can write straight to stdout in the right order and the caller's final
# `finish` has nothing left to print.
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
    local branch remote_sha local_sha worktree sub_status=0

    # Rule one: outside a git repo, or in a repo with no remote, this plugin
    # does nothing at all - silently, so it stays invisible in projects it has
    # no business touching.
    MAIN_REPO="$(resolve_main_repo "$START_DIR")" || exit 0
    REMOTE="$(first_remote "$MAIN_REPO")" || exit 0

    # Before anything reads `git status`: a worktree directory that is not
    # ignored makes the main checkout dirty forever, and the dirty-tree guards
    # below would then refuse every fast-forward for the life of the clone.
    ensure_worktrees_excluded "$MAIN_REPO"

    # NOTE: there is deliberately NO dirty check on the main checkout here.
    # `git fetch` writes only to the object store and the remote-tracking refs;
    # it cannot touch a working tree, cannot conflict with uncommitted work,
    # and is safe in any repository state. Gating it on a clean tree is what
    # let a single stray untracked directory - `.claude/worktrees/`, which the
    # plugin itself did not create - starve the fetch permanently, leaving
    # every `<remote>/<default>` ref stale and every branch cut from one behind.
    #
    # The tree-mutating steps still check: sync_current_branch refuses to merge
    # into a dirty tree, and sync_checked_out refuses to merge into a dirty
    # worktree. The guard lives where the risk is.
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

    # The tree the session is actually working in comes first, whatever branch
    # it is on. This is the step the session can feel; everything below it is
    # housekeeping for the default branch's ref.
    sync_current_branch "$branch" "$remote_sha"

    # Keep the default branch's ref fresh even in a session that never checks
    # it out, so a later sync or a branch cut from it starts current. Skipped
    # when the pass above already handled that very branch, since a branch can
    # only be checked out in one tree.
    if [[ "$CURRENT_BRANCH" != "$branch" ]]; then
        local_sha="$(git -C "$MAIN_REPO" rev-parse -q --verify "refs/heads/$branch" || true)"

        if [[ "$local_sha" != "$remote_sha" ]]; then
            # A local branch that is not an ancestor of the remote carries
            # commits of its own. This ref is not the one the session is
            # standing on, so nobody asked for it to be reconciled - fast-
            # forwarding is impossible and the rest is the human's call.
            if [[ -n "$local_sha" ]] && ! git -C "$MAIN_REPO" merge-base --is-ancestor "$local_sha" "$remote_sha"; then
                add_warning "local $branch has diverged from $REMOTE/$branch; resolve it by hand in $MAIN_REPO"
            else
                worktree="$(worktree_holding_branch "$MAIN_REPO" "$branch")"
                if [[ -n "$worktree" ]]; then
                    sync_checked_out "$worktree" "$branch" "$remote_sha"
                else
                    sync_ref_only "$branch" "$remote_sha"
                fi
            fi
        fi
    fi

    # Submodules last: they are the slow part, and a superproject that failed
    # to sync is not a repository worth pulling submodule updates into.
    sync_submodules || sub_status=$?

    render_report
    exit "$sub_status"
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
