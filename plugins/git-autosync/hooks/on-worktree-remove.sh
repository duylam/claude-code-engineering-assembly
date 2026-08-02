#!/bin/bash

# ============================================================================
# on-worktree-remove.sh - WorktreeRemove hook: tear down what WorktreeCreate
# built
#
# Claude Code fires WorktreeRemove for a worktree whose creation a hook took
# over, because a WorktreeCreate hook replaces the built-in `git worktree add`
# and so owns the other end of the lifecycle too. Without this the plugin's
# worktrees and their branches accumulate forever.
#
# The event fires for three different reasons, and only two of them mean "the
# session is over":
#
#   session_end   the Claude Code instance quit          -> clean up
#   user_delete   `claude delete <session>`              -> clean up
#   subagent_end  a subagent with its own worktree ended -> LEAVE IT ALONE
#
# subagent_end is deliberately ignored. That worktree is the subagent's own,
# not the session's, and the conversation it belongs to is still running: its
# results are worth more on disk than the disk space is worth back. Claude
# Code's periodic sweep reclaims the work-free ones on its own schedule.
# WorktreeRemove supports no `matcher`, so the filter has to live here.
#
# Set GIT_AUTOSYNC_KEEP_WORKTREE=1 to report what would be removed and remove
# nothing.
#
# ALWAYS exits 0. Claude Code logs a WorktreeRemove failure in debug mode only,
# so there is no one to fail at; the report goes to stderr for `claude --debug`.
#
# Dependencies: git; jq (optional, see payload_field).
# ============================================================================

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CLEANUP_SCRIPT="$SCRIPT_DIR/worktree-cleanup.sh"

PAYLOAD=""

# Pull a string field out of the hook payload. jq when available; otherwise
# sed, which is enough for the two fields used here (`reason` and
# `worktree_path` are plain strings with no escapes in practice).
payload_field() {
    local key="$1"

    if command -v jq >/dev/null 2>&1; then
        jq -r --arg k "$key" '.[$k] // empty' <<<"$PAYLOAD" 2>/dev/null || true
    else
        sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" <<<"$PAYLOAD" | head -n 1
    fi
}

PAYLOAD="$(cat || true)"
reason="$(payload_field reason)"
worktree_path="$(payload_field worktree_path)"

case "$reason" in
    session_end|user_delete)
        ;;
    *)
        # subagent_end, or a reason added after this was written. Doing nothing
        # is the safe answer to an event whose meaning is not known here.
        exit 0
        ;;
esac

if [[ -z "$worktree_path" ]]; then
    echo "$SCRIPT_NAME: no worktree_path in the hook payload" >&2
    exit 0
fi

if [[ ! -f "$CLEANUP_SCRIPT" ]]; then
    echo "$SCRIPT_NAME: $CLEANUP_SCRIPT is missing" >&2
    exit 0
fi

args=(-C "$worktree_path")
if [[ -n "${GIT_AUTOSYNC_KEEP_WORKTREE:-}" && "${GIT_AUTOSYNC_KEEP_WORKTREE}" != "0" ]]; then
    args+=(-n)
fi

# The worker already reports its own failures and always exits 0; `|| true`
# covers only the case where it cannot start at all.
report="$(bash "$CLEANUP_SCRIPT" "${args[@]}" 2>&1 || true)"

if [[ -n "$report" ]]; then
    echo "$report" >&2
fi

exit 0
