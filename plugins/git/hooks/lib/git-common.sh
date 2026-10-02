#!/bin/bash

# ============================================================================
# git-common.sh - helpers shared by the git plugin's worker scripts.
#
# Source this file; do not execute it. Callers run under `set -Eeuo pipefail`,
# so nothing here calls `exit`: helpers return a status and the caller decides
# what a failure means. That keeps the "always end success" contract in one
# place - the caller's own `finish`.
# ============================================================================

# The names treated as a repository's default branch, in priority order. Kept
# here rather than in one worker so the sync can never disagree with itself
# about which branch "the default branch" means.
readonly BRANCH_CANDIDATES=(main master)

# Every directory a Claude Code worktree can land in, relative to the repo root.
# BOTH are needed, because these are two different worktree roots a session can
# open in:
#
#   .worktrees/         the root `claude --worktree` uses
#   .claude/worktrees/  Claude Code's own default, used most importantly by
#                       `claude remote-control --spawn worktree`, which builds
#                       its worktree itself under this path
#
# A repo driven by remote sessions therefore accumulates worktrees under
# .claude/worktrees/, and excluding only the other would leave the main checkout
# permanently dirty. See ensure_worktrees_excluded.
readonly WORKTREE_DIRS=(".worktrees" ".claude/worktrees")

# The plugin's two off switches, one per step. Each disables its step when set
# to any non-empty string (including "0").
#
#   GIT_PLUGIN_GIT_FETCH_DISABLED              - skip the fetch step
#   GIT_PLUGIN_WORKTREE_ATTACHED_MODE_DISABLED - skip the worktree/submodule attach step
git_fetch_disabled() {
    [[ -n "${GIT_PLUGIN_GIT_FETCH_DISABLED:-}" ]]
}

worktree_attach_disabled() {
    [[ -n "${GIT_PLUGIN_WORKTREE_ATTACHED_MODE_DISABLED:-}" ]]
}

# The per-session directory, keyed by session id so a session only ever sees its
# own state and old sessions never overwrite it. It holds this session's latest
# launch status (git.status).
#
# Prints the path and creates it. Prints nothing on a missing session id -
# callers treat an empty result as "no session-scoped state this run".
session_dir() {
    local session_id="$1" dir

    [[ -n "$session_id" ]] || return 0
    dir="${TMPDIR:-/tmp}/claude-git/$session_id"
    mkdir -p "$dir" 2>/dev/null || return 0
    echo "$dir"
}

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

# Keep every worktree directory out of `git status` in repo $1.
#
# Load-bearing, not cosmetic. An unignored worktree directory makes the main
# checkout permanently dirty from the first worktree onward, and a dirty main
# checkout is what the sync's own guards refuse to act on - so the plugin would
# quietly disable itself for the life of the clone.
#
# Each directory is tested on its own: one of them already being ignored says
# nothing about the other, and a repo whose .gitignore lists `.worktrees/`
# (the plugin's) still goes dirty the moment Claude Code uses `.claude/
# worktrees/` (its own).
#
# The entries are written unconditionally rather than only for directories that
# exist, because the caller is often about to create one. info/exclude is local
# to the clone, so this commits nothing on the user's behalf and appears in no
# diff.
ensure_worktrees_excluded() {
    local repo="$1" common exclude dir

    common="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
    [[ -n "$common" && -d "$common" ]] || return 0

    exclude="$common/info/exclude"

    for dir in "${WORKTREE_DIRS[@]}"; do
        # The trailing slash is required, not cosmetic. `.worktrees/` in a
        # .gitignore is a directory-only pattern, and `check-ignore` asked
        # about the slash-less path cannot tell the path is a directory - so it
        # reports "not ignored" for a directory that plainly is, and the line
        # gets appended again on every single run.
        if git -C "$repo" check-ignore -q "$dir/" 2>/dev/null; then
            continue
        fi

        # Second guard, for the case check-ignore cannot answer: the entry may
        # already be in this very file from an earlier run. Without this the
        # file grows by one duplicate line per session, forever.
        if [[ -f "$exclude" ]] && grep -qxF "/$dir/" "$exclude" 2>/dev/null; then
            continue
        fi

        mkdir -p "$common/info" 2>/dev/null || return 0
        printf '/%s/\n' "$dir" >>"$exclude" 2>/dev/null || return 0
        add_note "excluded /$dir/ in $exclude, so worktrees cannot make $repo dirty"
    done

    return 0
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

# The remote to work with: the first one git lists, which is `origin` in any
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

# Whether branch $2 is checked out in ANY worktree of repo $1 - the current tree
# or any linked worktree (e.g. the primary checkout while a session runs in a
# worktree). `git worktree list --porcelain` prints a `branch refs/heads/<name>`
# line per worktree on a branch, and none for a detached or bare one.
#
# The output is captured, not piped into grep: a piped `grep -q` can close the
# pipe early and hand git a SIGPIPE whose status, under `pipefail`, would read as
# "no match" and let a checked-out branch slip through. The match is whole-line
# and fixed-string so `main` cannot match `main-wip`. If `worktree list` itself
# fails, this FAILS CLOSED (returns success = "checked out") so a ref it could
# not verify is never moved.
branch_checked_out_anywhere() {
    local repo="$1" branch="$2" list
    list="$(git -C "$repo" worktree list --porcelain 2>/dev/null)" || return 0
    grep -qxF "branch refs/heads/$branch" <<<"$list"
}

# Fast-forward the LOCAL default branch (main, falling back to master) of repo $1
# to its remote-tracking ref on remote $2, so it does not drift behind the remote
# while the session works on another branch. The attach step only ever moves the
# branch the tree is ON; this keeps the default branch current even when that is
# not it.
#
# Fast-forward ONLY, and only when it is safe to move the ref without touching a
# working tree:
#   - no main/master remote-tracking ref           -> nothing to do
#   - no local branch of that name                  -> nothing to do (never creates one)
#   - the branch is checked out in ANY worktree     -> left untouched (the current
#     tree is the attach step's job; another worktree must not be desynced)
#   - already at or ahead of the remote ref         -> nothing to do
#   - diverged (local has its own commits)          -> left as is, noted
#   - clean fast-forward, checked out nowhere       -> ref advanced with update-ref
#
# `update-ref <ref> <new> <old>` is a compare-and-swap (it only moves the ref if
# it still points at <old>) and writes a reflog entry, so the move is atomic and
# recoverable. It is NOT fast-forward-aware and does NOT guard checked-out
# branches - the is-ancestor gate and branch_checked_out_anywhere above supply
# both guarantees. Never fails: every outcome is a note or warning, and the
# caller still exits 0.
sync_local_default_branch() {
    local repo="$1" remote="$2" branch remote_sha local_sha behind

    branch="$(resolve_default_branch "$repo" "remotes/$remote")"
    [[ -n "$branch" ]] || return 0
    git -C "$repo" show-ref --verify --quiet "refs/heads/$branch" || return 0
    ! branch_checked_out_anywhere "$repo" "$branch" || return 0

    remote_sha="$(git -C "$repo" rev-parse --verify --quiet "refs/remotes/$remote/$branch")" || return 0
    local_sha="$(git -C "$repo" rev-parse --verify --quiet "refs/heads/$branch")" || return 0
    [[ -n "$remote_sha" && -n "$local_sha" ]] || return 0

    # Already contains the remote-tracking ref -> silent no-op.
    if git -C "$repo" merge-base --is-ancestor "$remote_sha" "$local_sha"; then
        return 0
    fi
    # Diverged: the local branch carries commits the remote ref lacks. Leave it,
    # exactly like the attach step - never force.
    if ! git -C "$repo" merge-base --is-ancestor "$local_sha" "$remote_sha"; then
        add_note "local $branch has diverged from $remote/$branch; leaving it as is"
        return 0
    fi

    behind="$(git -C "$repo" rev-list --count "$local_sha..$remote_sha" 2>/dev/null || echo '?')"
    if run_capture git -C "$repo" update-ref "refs/heads/$branch" "$remote_sha" "$local_sha"; then
        add_note "fast-forwarded local $branch to $remote/$branch (${remote_sha:0:7}); it was $behind commit(s) behind"
    else
        add_warning "could not fast-forward local $branch to $remote/$branch ($(capture_reason))"
    fi
    return 0
}

# Top-level submodules of the tree at $1, one `<name><TAB><path>` line each,
# straight from the committed .gitmodules. Prints nothing when there is no
# .gitmodules at all.
#
# The NAME matters and is not interchangeable with the path: `submodule.<name>.
# branch` is the key that says which branch a submodule tracks, and a name is
# free to differ from the path it checks out to.
submodule_entries() {
    local repo="$1" line key value name

    [[ -f "$repo/.gitmodules" ]] || return 0

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        key="${line%% *}"
        value="${line#* }"
        name="${key#submodule.}"
        name="${name%.path}"
        [[ -n "$name" && -n "$value" ]] || continue
        printf '%s\t%s\n' "$name" "$value"
    done < <(git -C "$repo" config -f "$repo/.gitmodules" \
        --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)
}

# Whether the working tree at $1 has anything uncommitted, staged or untracked.
#
# --ignore-submodules=all is required, not a shortcut. A superproject reports
# ` M <path>` whenever a submodule's HEAD differs from the recorded gitlink.
# After the superproject syncs but before the submodule sync step runs, every
# submodule will appear modified this way. Counting that as "dirty" would make
# the merge dirty-checks skip a tree that has no real local work. Real work
# inside a submodule is not missed: each submodule's own tree is checked
# directly by the submodule sync step.
tree_is_dirty() {
    [[ -n "$(git -C "$1" status --porcelain --ignore-submodules=all 2>/dev/null)" ]]
}
