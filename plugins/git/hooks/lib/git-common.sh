#!/bin/bash

# ============================================================================
# git-common.sh - helpers shared by the git plugin's worker scripts.
#
# Source this file; do not execute it. Callers run under `set -Eeuo pipefail`,
# so nothing here calls `exit`: helpers return a status and the caller decides
# what a failure means. That keeps the "always end success" contract in one
# place - the caller's own `finish`.
# ============================================================================

# The plugin's single global off switch. When GIT_PLUGIN_DISABLE is set to any
# non-empty string, every hook turns itself into a no-op.
git_plugin_disabled() {
    [[ -n "${GIT_PLUGIN_DISABLE:-}" ]]
}

# The shared session directory both the `git` and `git-autosync` plugins agree
# on. It holds the fetch barrier markers (fetch-started/fetch-done, written by
# this plugin) and each plugin's latest launch status. Keyed by session id so a
# session only ever sees its own state, and old sessions never overwrite it.
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
# is nothing to say.
render_report() {
    local line

    for line in ${NOTES[@]+"${NOTES[@]}"}; do
        echo "$line"
    done
    for line in ${WARNINGS[@]+"${WARNINGS[@]}"}; do
        echo "Warning: $line"
    done
}

# Write the collected report to <session_dir>/git.status, latest only. The
# read-only launch-status skill reads exactly this file. Best-effort: a failure
# to persist status must never fail the session.
persist_status() {
    local dir

    dir="$(session_dir "$1")" || return 0
    [[ -n "$dir" ]] || return 0
    render_report >"$dir/git.status" 2>/dev/null || true
}

# Run a command, capturing its combined output in $CMD_OUTPUT and returning its
# exit status. The ERR trap is cleared inside the capture subshell: `set -E`
# propagates it there, where it would otherwise replace the command's own error
# text with the trap's message.
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

# Absolute path of the repository that owns the object store: the main checkout,
# even when called from inside a linked worktree. Returns non-zero when $1 is not
# inside a git repository at all - the signal to do nothing.
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

# The remote to fetch from: the first one git lists, which is `origin` in any
# ordinary clone. Returns non-zero when the repo has no remote - the other
# signal to do nothing.
first_remote() {
    local remote

    remote="$(git -C "$1" remote 2>/dev/null | head -n 1)"
    [[ -n "$remote" ]] || return 1
    echo "$remote"
}
