#!/bin/bash

# ============================================================================
# git-common.sh - helpers shared by the git-autosync worker scripts.
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

# The plugin's single global off switch. When GIT_AUTOSYNC_DISABLE is set to any
# non-empty string, the SessionStart hook turns itself into a no-op.
autosync_disabled() {
    [[ -n "${GIT_AUTOSYNC_DISABLE:-}" ]]
}

# The shared session directory both the `git` and `git-autosync` plugins agree
# on. It holds the fetch barrier markers (fetch-started/fetch-done, written by
# the `git` plugin) and each plugin's latest launch status. Keyed by session id.
#
# Prints the path and creates it. Prints nothing on a missing session id.
session_dir() {
    local session_id="$1" dir

    [[ -n "$session_id" ]] || return 0
    dir="${TMPDIR:-/tmp}/claude-git/$session_id"
    mkdir -p "$dir" 2>/dev/null || return 0
    echo "$dir"
}

# The fetch barrier. This plugin never fetches; it reads the remote-tracking
# refs the `git` plugin refreshes. The two run their SessionStart hooks in
# parallel with no ordering guarantee, so wait for the `git` plugin's fetch to
# finish before attaching:
#
#   - up to GIT_AUTOSYNC_GRACE_SECS (default 5) for `fetch-started`. Absent means
#     the `git` plugin is not participating (not installed / disabled) - proceed
#     immediately rather than block a session that will never see a fetch.
#   - then up to GIT_AUTOSYNC_FETCH_WAIT_SECS (default 240) for `fetch-done`,
#     which the `git` plugin always writes, even on failure or timeout.
#
# Bounded and best-effort: it returns in every case and never fails the session.
# The bounds are env-overridable so tests can run it in milliseconds.
wait_for_fetch() {
    local dir grace wait_done waited
    dir="$(session_dir "$1")" || return 0
    [[ -n "$dir" ]] || return 0

    grace="${GIT_AUTOSYNC_GRACE_SECS:-5}"
    wait_done="${GIT_AUTOSYNC_FETCH_WAIT_SECS:-240}"

    waited=0
    while [[ ! -e "$dir/fetch-started" ]]; do
        if awk "BEGIN{exit !($waited >= $grace)}"; then
            return 0  # no fetch-started within the grace window: not participating
        fi
        sleep 0.2
        waited="$(awk "BEGIN{print $waited + 0.2}")"
    done

    waited=0
    while [[ ! -e "$dir/fetch-done" ]]; do
        if awk "BEGIN{exit !($waited >= $wait_done)}"; then
            return 0  # bound reached: proceed regardless
        fi
        sleep 0.5
        waited="$(awk "BEGIN{print $waited + 0.5}")"
    done
    return 0
}

# Write the collected report to <session_dir>/git-autosync.status, latest only.
# The read-only launch-status skill reads exactly this file. Best-effort.
persist_status() {
    local dir

    dir="$(session_dir "$1")" || return 0
    [[ -n "$dir" ]] || return 0
    render_report >"$dir/git-autosync.status" 2>/dev/null || true
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

# The remote to sync from: the first one git lists, which is `origin` in any
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
