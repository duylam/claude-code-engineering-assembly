#!/bin/bash

# ============================================================================
# ensure-submodules.sh - make this superproject's submodules ready to work in
#
# Guarantees, for every TOP-LEVEL submodule listed in .gitmodules:
#   1. it is populated (cloned + checked out), recursively, so nested
#      submodules come along with it
#   2. it sits on a local branch whose name matches the superproject's branch,
#      instead of the detached HEAD `git submodule update` leaves behind
#   3. that branch is reconciled with the submodule's OWN remote, at the branch
#      `.gitmodules` says the submodule tracks
#
# Step 3 obeys the same two modes as git-sync.sh:
#
#   merge (default)  fast-forward, or a merge commit when the submodule branch
#                    has commits of its own. Never destroys anything.
#   reset            discard local commits and land exactly on the remote.
#                    Refuses to touch ANYTHING when any tree is dirty, and says
#                    so with a non-zero exit.
#
# Only a human passes `--mode reset`; the hooks pass no mode at all, so an
# unattended run is always `merge` and always exits 0.
#
# The branch to sync to is resolved the way git itself defines it: the
# `submodule.<name>.branch` key from .gitmodules, the literal `.` meaning
# "whatever the superproject is on", and failing both, the submodule's own
# default branch. See submodule_target_branch in lib/git-common.sh.
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
# In merge mode nothing here is destructive:
#   - `git submodule update` is only run over a top-level submodule that is
#     not populated yet, where there is no local work to rewind. A populated
#     one is only asked to fill in its own nested submodules.
#   - `git checkout -B` is never used, so a submodule branch that already
#     carries local commits is never moved by the attach step.
#   - a conflicted merge is rolled back rather than left in the tree.
#   - any git failure becomes a warning naming the manual command to run, and
#     the script still succeeds.
#
# Reset mode is destructive by definition - that is what it is for. It is
# guarded by a preflight that refuses the whole run over a single dirty tree
# anywhere, so it either does everything or nothing.
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
MODE="$DEFAULT_MODE"

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [--mode ${MODES[0]}|${MODES[1]}] [-C <dir>]

Populates every submodule recursively, attaches each top-level submodule to a
branch named after the superproject's current branch, and reconciles that
branch with the submodule's own remote. Warns and succeeds when it cannot.
Prints nothing when everything is already correct.

Options:
  --mode <${MODES[0]}|${MODES[1]}>
             ${MODES[0]}: keep local commits, fast-forwarding or merging (default)
             ${MODES[1]}: discard local commits; fails when any tree is dirty
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

# Print the report and stop, unsuccessfully. Reachable ONLY from reset mode,
# which no hook can select - so the "a hook never fails" contract survives
# having a failure path in the same file.
fail_fast() {
    render_report
    exit 1
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

# Reconcile a populated, attached submodule with its own remote.
#
# The submodule's remote, not the superproject's: a submodule is a repository,
# and `.gitmodules` names the branch it tracks over there, not here.
sync_submodule() {
    local name="$1" path="$2" sub="$REPO_ROOT/$path"
    local remote target target_sha head_sha behind

    remote="$(first_remote "$sub")" || return 0

    # Ungated on dirtiness, exactly as in git-sync.sh: a fetch writes only to
    # the object store and the remote-tracking refs, so refusing it over a
    # stray untracked file would starve the sync for no safety gained.
    if ! run_capture git -C "$sub" fetch --quiet "$remote"; then
        add_warning "could not fetch $remote in $path ($(capture_reason))"
        return 0
    fi

    target="$(submodule_target_branch "$REPO_ROOT" "$name" "$path" "$BRANCH")"
    if [[ -z "$target" ]]; then
        add_warning "cannot tell which branch $path should track; set 'branch' for submodule $name in .gitmodules"
        return 0
    fi

    target_sha="$(git -C "$sub" rev-parse -q --verify "refs/remotes/$remote/$target" || true)"
    if [[ -z "$target_sha" ]]; then
        add_warning "$remote has no $target branch in $path; leaving it where it is"
        return 0
    fi

    head_sha="$(git -C "$sub" rev-parse HEAD 2>/dev/null || true)"
    [[ -n "$head_sha" ]] || return 0

    if [[ "$MODE" == "reset" ]]; then
        [[ "$head_sha" != "$target_sha" ]] || return 0
        if run_capture git -C "$sub" reset --hard "$target_sha"; then
            add_note "reset $path to $remote/$target (${target_sha:0:7}); the previous tip ${head_sha:0:7} is still reachable from its reflog"
            return 0
        fi
        add_warning "could not reset $path to $remote/$target ($(capture_reason))"
        fail_fast
    fi

    if git -C "$sub" merge-base --is-ancestor "$target_sha" "$head_sha"; then
        return 0
    fi

    behind="$(git -C "$sub" rev-list --count "$head_sha..$target_sha" 2>/dev/null || echo "?")"

    if tree_is_dirty "$sub"; then
        add_warning "$path is $behind commit(s) behind $remote/$target but has uncommitted changes; not merging"
        return 0
    fi

    if run_capture git -C "$sub" merge --no-edit "$target_sha"; then
        if git -C "$sub" merge-base --is-ancestor "$head_sha" "$target_sha"; then
            add_note "fast-forwarded $path to $remote/$target (${target_sha:0:7}); it was $behind commit(s) behind"
        else
            add_note "merged $remote/$target (${target_sha:0:7}) into $BRANCH in $path"
        fi
        return 0
    fi

    # Same reasoning as git-sync.sh: a conflicted index inside a submodule is
    # worse than an unsynced submodule, so put it back and name the command.
    local reason
    reason="$(capture_reason)"
    if run_capture git -C "$sub" merge --abort; then
        add_warning "merging $remote/$target into $path conflicts ($reason); the merge was rolled back - resolve it yourself with: git -C '$sub' merge $remote/$target"
        return 0
    fi

    add_warning "could not merge $remote/$target in $path ($reason), and could not roll the attempt back; check 'git -C \"$sub\" status'"
}

main() {
    local name path

    if ! resolve_context "$START_DIR"; then
        finish
    fi

    # Reset either does everything or nothing, so the whole repository is
    # inspected before the first ref moves. Running this per-submodule instead
    # would leave a half-reset tree the moment the third one turned out dirty.
    if [[ "$MODE" == "reset" ]]; then
        assert_clean_recursive "$REPO_ROOT" || fail_fast
    fi

    while IFS=$'\t' read -r name path; do
        [[ -n "$path" ]] || continue
        ensure_populated "$path" || continue
        [[ -n "$BRANCH" ]] || continue
        ensure_branch "$path" || continue
        sync_submodule "$name" "$path"
    done < <(submodule_entries "$REPO_ROOT")

    finish
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="$(parse_mode "${2:-}")"
            if [[ -z "$MODE" ]]; then
                echo "$SCRIPT_NAME: --mode must be one of: ${MODES[*]}" >&2
                exit 1
            fi
            shift 2
            ;;
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
