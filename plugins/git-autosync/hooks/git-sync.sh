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
#   fetch fails (offline)                -> warn, exit 0
#   neither main nor master on remote    -> warn, exit 0
#   local branch already == remote       -> silent, exit 0
#   local branch diverged from remote    -> warn, exit 0 (never a merge commit)
#   branch checked out in a dirty tree   -> warn, exit 0
#   branch checked out in a clean tree   -> git merge --ff-only there
#   branch checked out nowhere           -> git fetch <remote> <br>:<br>
#
# The fetch is NOT gated on a clean working tree; only the steps that move a
# tree are. See the note in main() for why that distinction is load-bearing.
#
# It also aligns the session's own `worktree-*` branch when that branch was cut
# from a stale base and carries no work of its own - see align_session_branch.
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

# Fast-forward the session's OWN worktree branch onto the default branch.
#
# on-worktree-create.sh cuts a session branch from an already-synced base, but
# it only gets the chance when Claude Code fires WorktreeCreate. It does not
# always: `claude remote-control --spawn worktree` builds the worktree itself,
# under `.claude/worktrees/<name>`, and cuts `worktree-<name>` straight from
# `<remote>/<default>` - a remote-tracking ref that is only as fresh as the last
# fetch. Nothing the plugin does at WorktreeCreate applies to that worktree,
# because WorktreeCreate never happened.
#
# SessionStart runs inside the finished worktree and is the last moment to
# repair it. So this repairs exactly the case where repairing cannot lose
# anything:
#
#   - a LINKED worktree, never the main checkout
#   - on a `worktree-*` branch - the session namespace, not a human's branch
#   - carrying NO commits of its own beyond <remote>/<default>
#   - with a clean tree
#
# Under those four, the branch is a pristine session base that simply started
# too far back, and `merge --ff-only` moves a ref over an identical tree. Any
# branch with work on it, or any dirty tree, is only reported: reconciling one
# is a rebase or a merge with conflicts to resolve, and that is the human's
# call - the same line the sync already draws for feature branches.
align_session_branch() {
    local branch="$1" remote_sha="$2"
    local tree current ahead behind

    tree="$(git -C "$START_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "$tree" ]] || return 0

    # The main checkout is never touched, whatever branch it is on.
    [[ "$tree" != "$MAIN_REPO" ]] || return 0
    worktree_is_registered "$MAIN_REPO" "$tree" || return 0

    # Detached HEAD yields nothing, and falls out of the prefix test below.
    current="$(git -C "$tree" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    [[ "$current" == "$SESSION_BRANCH_PREFIX"* ]] || return 0
    [[ "$current" != "$branch" ]] || return 0

    behind="$(git -C "$MAIN_REPO" rev-list --count "$current..$remote_sha" 2>/dev/null || echo 0)"
    [[ "$behind" =~ ^[0-9]+$ && "$behind" -gt 0 ]] || return 0

    ahead="$(git -C "$MAIN_REPO" rev-list --count "$remote_sha..$current" 2>/dev/null || echo 0)"
    if [[ ! "$ahead" =~ ^[0-9]+$ ]] || [[ "$ahead" -gt 0 ]]; then
        add_warning "$current carries $ahead commit(s) of its own and is $behind behind $REMOTE/$branch; rebase or merge it by hand in $tree"
        return 0
    fi

    if [[ -n "$(git -C "$tree" status --porcelain)" ]]; then
        add_warning "$current is $behind commit(s) behind $REMOTE/$branch but $tree has uncommitted changes; not fast-forwarding"
        return 0
    fi

    if run_capture git -C "$tree" merge --ff-only "$remote_sha"; then
        add_note "fast-forwarded $current to $REMOTE/$branch (${remote_sha:0:7}); it was cut from a base $behind commit(s) stale"
        return 0
    fi

    add_warning "could not fast-forward $current in $tree ($(capture_reason))"
}

main() {
    local branch remote_sha local_sha worktree

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
    # The tree-mutating step still checks: sync_checked_out refuses to merge
    # into a dirty worktree, and so does align_session_branch. The guard lives
    # where the risk is.
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

    # The tree the session is actually working in comes first, and is checked
    # unconditionally: a session branch cut from a stale base is behind even
    # when the default branch itself is perfectly in sync, so this must not sit
    # behind the early exit below.
    align_session_branch "$branch" "$remote_sha"

    # Already in sync - the common case, and the quiet one. `finish`, not a
    # bare `exit 0`: notes collected above still have to be rendered.
    if [[ "$local_sha" == "$remote_sha" ]]; then
        finish
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
