#!/bin/bash

# ============================================================================
# worktree-cleanup.sh - remove a worktree this plugin created, and its branch
#
# The counterpart to on-worktree-create.sh. Because a WorktreeCreate hook
# REPLACES Claude Code's own `git worktree add`, Claude Code hands teardown
# back too: without this, every worktree session leaves a `.worktrees/<name>`
# directory and a `worktree-<name>` branch behind forever. The lock that
# on-worktree-create.sh sets makes the leak permanent - Claude Code's periodic
# sweep never releases a lock it did not set itself.
#
# This is the one DESTRUCTIVE script in the plugin. It removes the worktree
# whatever state it is in: uncommitted changes, untracked files and unpushed
# commits all go with it. That is deliberate - a worktree Claude Code has
# finished with is disposable by construction - but it is why every guard below
# is a refusal rather than a warning.
#
# It will only ever touch:
#   - a directory git itself reports as a LINKED worktree of the resolved repo
#     (registration, not a path that merely looks right, is the proof)
#   - a branch named `worktree-*`, the prefix on-worktree-create.sh uses
#   - a `worktree-*` branch inside a submodule, and only when the superproject
#     already records every commit on it
#
# It never touches the main checkout, any other branch, or anything remote:
# no push, no `push --delete`, no fetch.
#
#   not a git repo                        -> silent, exit 0
#   not a registered worktree             -> silent, exit 0 (already gone)
#   the main checkout                     -> refuse, warn, exit 0
#   anything else                         -> unlock, remove, delete the branch
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
# For resolve_main_repo, branch_in_worktree and worktree_is_registered.
source "$SCRIPT_DIR/lib/git-common.sh"

readonly WORKTREE_SUBDIR=".worktrees"
readonly BRANCH_PREFIX="worktree-"

WORKTREE=""
DRY_RUN=0
MAIN_REPO=""
BRANCH=""

# One "<path>\t<gitdir>\t<gitlink-sha>" entry per populated top-level submodule,
# captured while the worktree still exists because none of it is readable
# afterwards. See cleanup_submodule_branches for what it is for.
SUBMODULES=()

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME -C <worktree-path> [-n]

Removes a worktree created by this plugin's WorktreeCreate hook, together with
its ${BRANCH_PREFIX}* branch. Refuses to touch the main checkout or any
directory git does not report as a linked worktree. Prints nothing when there
is nothing to remove.

This deletes uncommitted changes, untracked files and unpushed commits in that
worktree.

Options:
  -C <dir>   The worktree to remove (required)
  -n         Dry run: report what would be removed, remove nothing
  -h, --help Show this help
EOF
}

# Print the report and stop. Always a success: a teardown hook that fails is
# noise at a moment when the user has already left.
finish() {
    render_report
    exit 0
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
    finish
}

trap on_error ERR

# Absolute, symlink-resolved form of $1, which may not exist: git records
# worktree paths with symlinks resolved (/private/tmp, not /tmp, on macOS) and
# the registry lookups below are exact string matches. Only the parent has to
# exist, which stays true after the worktree directory itself is deleted.
normalize_path() {
    local path="$1" parent base

    parent="$(dirname "$path")"
    base="$(basename "$path")"

    if [[ -d "$parent" ]]; then
        printf '%s/%s\n' "$(cd "$parent" && pwd -P)" "$base"
    else
        printf '%s\n' "$path"
    fi
}

# The closest existing ancestor of $1, or nothing. The repository has to be
# resolved from somewhere, and by the time this runs the worktree directory may
# already be gone - removed by hand, or by a previous run of this script.
nearest_existing_dir() {
    local path="$1"

    while [[ ! -d "$path" ]]; do
        case "$path" in
            /|.|"") return 1 ;;
        esac
        path="$(dirname "$path")"
    done

    printf '%s\n' "$path"
}

# Whether $1 sits under the plugin's own .worktrees/ directory. Only used to
# gate the `rm -rf` fallback, which deserves a stricter test than the git
# operations do.
is_plugin_worktree_path() {
    [[ "$1" == "$MAIN_REPO/$WORKTREE_SUBDIR/"* ]]
}

# Top-level submodule paths, straight from the committed .gitmodules - the same
# enumeration ensure-submodules.sh uses, so the two agree on what "top-level"
# means.
submodule_paths() {
    git -C "$WORKTREE" config -f "$WORKTREE/.gitmodules" \
        --get-regexp '^submodule\..*\.path$' 2>/dev/null \
        | sed 's/^[^ ]* //' || true
}

# Record where each populated submodule keeps its refs, and which commit the
# superproject records for it, BEFORE the worktree goes away. Both become
# unreadable the moment it does.
record_submodules() {
    local path sub gitdir gitlink

    [[ -d "$WORKTREE" && -f "$WORKTREE/.gitmodules" ]] || return 0

    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        sub="$WORKTREE/$path"
        [[ -e "$sub/.git" ]] || continue

        gitdir="$(git -C "$sub" rev-parse --absolute-git-dir 2>/dev/null || true)"
        [[ -n "$gitdir" ]] || continue
        gitlink="$(git -C "$WORKTREE" rev-parse -q --verify "HEAD:$path" 2>/dev/null || true)"

        SUBMODULES+=("$path"$'\t'"$gitdir"$'\t'"$gitlink")
    done < <(submodule_paths)
}

# Delete each submodule's `worktree-<name>` branch - the one ensure-submodules.sh
# created - but only where it still exists and only when it is fully merged.
#
# Usually there is nothing to do. Git gives a submodule populated inside a
# linked worktree its own gitdir under `.git/worktrees/<name>/modules/<path>`,
# and `git worktree remove` deletes that whole directory, so the branch goes
# with it. Some git versions share `.git/modules/<path>` with the main checkout
# instead, and there the ref would outlive the worktree.
#
# Rather than assume a layout, this checks: a gitdir that still exists after
# the removal is a shared one, and only then is there a ref to clean up.
cleanup_submodule_branches() {
    local entry path rest gitdir gitlink head_ref

    for entry in ${SUBMODULES[@]+"${SUBMODULES[@]}"}; do
        path="${entry%%$'\t'*}"
        rest="${entry#*$'\t'}"
        gitdir="${rest%%$'\t'*}"
        gitlink="${rest##*$'\t'}"

        [[ -d "$gitdir" ]] || continue
        git --git-dir="$gitdir" show-ref --verify --quiet "refs/heads/$BRANCH" || continue

        # A gitdir shared with the main checkout has one HEAD between them, so
        # the branch can still be the checked-out one there. Deleting it would
        # mean rewriting a HEAD this worktree does not own, which is a worse
        # outcome than an unused ref.
        head_ref="$(git --git-dir="$gitdir" symbolic-ref -q HEAD 2>/dev/null || true)"
        if [[ "$head_ref" == "refs/heads/$BRANCH" ]]; then
            add_note "kept $BRANCH in submodule $path: another checkout still has it out"
            continue
        fi

        # Merged against the GITLINK - the commit the superproject records -
        # and never against HEAD. `git branch -d` measures mergedness against
        # HEAD, so detaching onto the branch tip first would make every branch
        # look merged and delete work this test exists to protect.
        if [[ -z "$gitlink" ]] \
            || ! git --git-dir="$gitdir" merge-base --is-ancestor "refs/heads/$BRANCH" "$gitlink" 2>/dev/null; then
            add_note "kept $BRANCH in submodule $path: it has commits the superproject does not record"
            continue
        fi

        if run_capture git --git-dir="$gitdir" branch -D "$BRANCH"; then
            add_note "deleted the merged branch $BRANCH in submodule $path"
        else
            add_warning "could not delete $BRANCH in submodule $path ($(capture_reason))"
        fi
    done
}

remove_worktree() {
    # Unlock first. `git worktree remove` refuses a locked worktree outright,
    # and every worktree on-worktree-create.sh makes is locked. `-f -f` would
    # also override the lock, but unlocking says what is meant and does not
    # depend on that flag keeping its second meaning.
    git -C "$MAIN_REPO" worktree unlock "$WORKTREE" >/dev/null 2>&1 || true

    # --force twice: the first covers a dirty tree, untracked files and
    # populated submodules; the second covers the lock, in case the unlock
    # above did not take. Succeeds too when the directory is already gone,
    # unregistering it.
    if run_capture git -C "$MAIN_REPO" worktree remove --force --force "$WORKTREE"; then
        add_note "removed the worktree at $WORKTREE"
    else
        add_warning "could not remove the worktree at $WORKTREE ($(capture_reason))"
    fi

    # git 2.50 leaves nothing behind even for a dirty tree with a modified
    # submodule in it. This is for the versions and filesystems where it does -
    # gated on the plugin's own directory, because `rm -rf` deserves a stricter
    # test than a git command that has its own refusals.
    if [[ -e "$WORKTREE" ]] && is_plugin_worktree_path "$WORKTREE"; then
        if rm -rf "$WORKTREE" 2>/dev/null; then
            add_warning "git left $WORKTREE behind; removed the directory directly"
        else
            add_warning "could not remove $WORKTREE; run: rm -rf '$WORKTREE'"
        fi
    fi

    # Idempotent, and it repairs the registry when the steps above only got
    # part of the way.
    git -C "$MAIN_REPO" worktree prune >/dev/null 2>&1 || true
}

remove_branch() {
    [[ -n "$BRANCH" ]] || return 0

    # The prefix is the plugin's signature. A worktree Claude Code was pointed
    # at manually may sit on a branch that predates it and outlives it.
    if [[ "$BRANCH" != "$BRANCH_PREFIX"* ]]; then
        add_note "left branch $BRANCH alone: not a branch this plugin creates"
        return 0
    fi

    git -C "$MAIN_REPO" show-ref --verify --quiet "refs/heads/$BRANCH" || return 0

    if run_capture git -C "$MAIN_REPO" branch -D "$BRANCH"; then
        add_note "deleted branch $BRANCH"
    else
        add_warning "could not delete branch $BRANCH ($(capture_reason)); run: git -C '$MAIN_REPO' branch -D '$BRANCH'"
    fi
}

report_plan() {
    local entry path

    add_note "would remove the worktree at $WORKTREE"
    if [[ -n "$BRANCH" && "$BRANCH" == "$BRANCH_PREFIX"* ]]; then
        add_note "would delete branch $BRANCH"
    fi
    for entry in ${SUBMODULES[@]+"${SUBMODULES[@]}"}; do
        path="${entry%%$'\t'*}"
        add_note "would drop submodule $path with it"
    done
}

main() {
    local start

    if [[ -z "$WORKTREE" ]]; then
        echo "$SCRIPT_NAME: -C <worktree-path> is required" >&2
        usage >&2
        exit 1
    fi

    WORKTREE="$(normalize_path "$WORKTREE")"

    # Rule zero, as everywhere else in this plugin: outside a git repository
    # there is nothing to do and nothing to say.
    start="$(nearest_existing_dir "$WORKTREE")" || exit 0
    MAIN_REPO="$(resolve_main_repo "$start")" || exit 0
    MAIN_REPO="$(normalize_path "$MAIN_REPO")"

    if [[ "$WORKTREE" == "$MAIN_REPO" ]]; then
        add_warning "$WORKTREE is the main checkout, not a worktree; refusing to remove it"
        finish
    fi

    # Not registered means git does not consider this a worktree of this repo:
    # either it was cleaned up already, or it never belonged to this plugin.
    # Either way there is nothing to do, and silence is the right answer.
    if ! worktree_is_registered "$MAIN_REPO" "$WORKTREE"; then
        exit 0
    fi

    # From the registry, not from `symbolic-ref` inside the worktree: the
    # directory may already be gone, and this still answers.
    BRANCH="$(branch_in_worktree "$MAIN_REPO" "$WORKTREE")"

    record_submodules

    if [[ "$DRY_RUN" -eq 1 ]]; then
        report_plan
        finish
    fi

    remove_worktree
    cleanup_submodule_branches
    remove_branch

    finish
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -C)
            WORKTREE="${2:-}"
            if [[ -z "$WORKTREE" ]]; then
                echo "$SCRIPT_NAME: -C needs a path" >&2
                exit 1
            fi
            shift 2
            ;;
        -n)
            DRY_RUN=1
            shift
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
