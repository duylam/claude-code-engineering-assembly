#!/bin/bash

# ============================================================================
# ensure-submodules.sh - make this superproject's submodules ready to work in
#
# Guarantees, for every TOP-LEVEL submodule listed in .gitmodules:
#   1. it is populated (cloned + checked out), recursively, so nested
#      submodules come along with it
#   2. it sits on a local branch whose name matches the superproject's branch,
#      instead of the detached HEAD `git submodule update` leaves behind
#   3. that branch is reconciled with the commit the superproject currently records
#      for that submodule (the gitlink in superproject's HEAD)
#
# Step 3 is always a merge: fast-forward, or a merge commit when the submodule
# branch has commits of its own. Never destroys anything, and always exits 0.
#
# The commit to sync to is always the gitlink the superproject currently records
# for this submodule (`git rev-parse "HEAD:<path>"`), which is set by the
# superproject's own sync step before this script runs. If the gitlink commit is
# not yet in the submodule's local object store, it is fetched on demand.
#
# A branch that has to be CREATED always starts at the submodule's own HEAD as
# it stands once populated - the commit genuinely checked out there.
#
# For a submodule this run just populated that IS the commit the superproject
# records, because `git submodule update` checks the gitlink out. The two only
# differ for a submodule that was already populated somewhere else - ahead of
# the gitlink, or on a branch of its own - and there, branching from HEAD is
# what keeps this script from moving the tree out from under whoever put it
# there. Branching from the gitlink instead would silently strand that work on
# a commit nobody is standing on.
#
# Only TOP-LEVEL submodules get a branch, or a sync. Nested submodules are
# populated but left on their gitlink: they are vendored third-party trees, and
# creating a branch named after your feature inside somebody else's repo helps
# no one.
#
# Nothing here is destructive:
#   - `git submodule update` is only run over a top-level submodule that is
#     not populated yet, where there is no local work to rewind. A populated
#     one is only asked to fill in its own nested submodules.
#   - `git checkout -B` is never used, so a submodule branch that already
#     carries local commits is never moved by the attach step.
#   - a conflicted merge is rolled back rather than left in the tree.
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

Populates every submodule recursively, attaches each top-level submodule to a
branch named after the superproject's current branch, and reconciles that
branch with the submodule's own remote (merge only, never destructive). Warns
and succeeds when it cannot. Prints nothing when everything is already correct.

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

# Attach a populated submodule to $BRANCH, creating that branch where the
# submodule already stands when it does not exist yet.
ensure_branch() {
    local path="$1" sub="$REPO_ROOT/$path" current head
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
        # `checkout -b` with no start point branches from HEAD - the commit
        # this submodule is actually on. Naming a start point instead is what
        # would move the tree; not naming one is the whole guarantee here.
        head="$(git -C "$sub" rev-parse --short HEAD 2>/dev/null || true)"
        cmd=(checkout -b "$BRANCH")
        what="created branch $BRANCH in $path at ${head:-HEAD}"
    fi

    if run_capture git -C "$sub" "${cmd[@]}"; then
        add_note "$what"
        return 0
    fi

    add_warning "could not attach $path to $BRANCH ($(capture_reason)); run: git -C '$sub' ${cmd[*]}"
    return 1
}

# Reconcile a populated, attached submodule with the commit the superproject records.
#
# The target is always the gitlink in the superproject's current HEAD for this
# submodule path. The submodule's own remote is only contacted when the gitlink
# commit is not yet in the local object store.
sync_submodule() {
    local path="$1" sub="$REPO_ROOT/$path"
    local gitlink_sha head_sha behind remote

    gitlink_sha="$(git -C "$REPO_ROOT" rev-parse "HEAD:$path" 2>/dev/null || true)"
    if [[ -z "$gitlink_sha" ]]; then
        add_warning "cannot read gitlink for $path from superproject HEAD"
        return 0
    fi

    head_sha="$(git -C "$sub" rev-parse HEAD 2>/dev/null || true)"
    [[ -n "$head_sha" ]] || return 0

    # Fetch only when the gitlink commit is not already in the local object store.
    if ! git -C "$sub" cat-file -e "$gitlink_sha" 2>/dev/null; then
        remote="$(first_remote "$sub")" || {
            add_warning "gitlink ${gitlink_sha:0:7} for $path is not in the local store and the submodule has no remote"
            return 0
        }
        if ! run_capture git -C "$sub" fetch --quiet "$remote"; then
            add_warning "could not fetch $remote in $path to retrieve gitlink ${gitlink_sha:0:7} ($(capture_reason))"
            return 0
        fi
        if ! git -C "$sub" cat-file -e "$gitlink_sha" 2>/dev/null; then
            add_warning "gitlink ${gitlink_sha:0:7} for $path not found after fetching $remote; check the submodule's remote"
            return 0
        fi
    fi

    # Already at or ahead of the gitlink — nothing to do.
    if git -C "$sub" merge-base --is-ancestor "$gitlink_sha" "$head_sha"; then
        return 0
    fi

    behind="$(git -C "$sub" rev-list --count "$head_sha..$gitlink_sha" 2>/dev/null || echo "?")"

    if tree_is_dirty "$sub"; then
        add_warning "$path is $behind commit(s) behind the superproject gitlink but has uncommitted changes; not merging"
        return 0
    fi

    if run_capture git -C "$sub" merge --no-edit "$gitlink_sha"; then
        if git -C "$sub" merge-base --is-ancestor "$head_sha" "$gitlink_sha"; then
            add_note "fast-forwarded $path to superproject gitlink (${gitlink_sha:0:7}); it was $behind commit(s) behind"
        else
            add_note "merged superproject gitlink (${gitlink_sha:0:7}) into $BRANCH in $path"
        fi
        return 0
    fi

    # Same reasoning as git-sync.sh: a conflicted index inside a submodule is
    # worse than an unsynced submodule, so put it back and name the command.
    local reason
    reason="$(capture_reason)"
    if run_capture git -C "$sub" merge --abort; then
        add_warning "merging gitlink into $path conflicts ($reason); the merge was rolled back - resolve it yourself with: git -C '$sub' merge $gitlink_sha"
        return 0
    fi

    add_warning "could not merge gitlink in $path ($reason), and could not roll the attempt back; check 'git -C \"$sub\" status'"
}

main() {
    local name path

    if ! resolve_context "$START_DIR"; then
        finish
    fi

    while IFS=$'\t' read -r name path; do
        [[ -n "$path" ]] || continue
        ensure_populated "$path" || continue
        [[ -n "$BRANCH" ]] || continue
        ensure_branch "$path" || continue
        sync_submodule "$path"
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
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

main
