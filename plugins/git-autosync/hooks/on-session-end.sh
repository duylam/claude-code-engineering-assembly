#!/bin/bash

# ============================================================================
# on-session-end.sh - SessionEnd hook: reap the session's remote branch
#
# This is the teardown path for the sessions the plugin was built for.
# `claude remote-control --spawn worktree` makes and later removes its OWN
# worktree, so WorktreeRemove never fires - on-worktree-remove.sh, and every
# remote-branch cleanup it now drives, never runs for those sessions. SessionEnd
# DOES fire, so it is where a remote-control session's `worktree-*` branch gets
# deleted on origin (superproject and every submodule that has it). Without this
# those branches accumulate on the remote forever.
#
# It reaps the REMOTE branch only. The local worktree here is Claude Code's own,
# not one this plugin created; Claude Code's periodic sweep reclaims it, and the
# plugin leaves local teardown of its own worktrees to WorktreeRemove.
#
# The event fires for several reasons; two of them do NOT mean the session is
# gone:
#
#   resume   the session was paused, not deleted -> LEAVE IT ALONE
#   clear    `/clear`; the session continues      -> LEAVE IT ALONE
#   logout | prompt_input_exit | bypass_permissions_disabled | other -> reap
#
# There is no delete-specific reason, so this reaps on every "the session is
# over" reason and skips the two that plainly are not. The branch is derived
# from the tree's own HEAD and must be a `worktree-*` branch, so a session that
# somehow ends on a human branch is never reaped (the shared helper enforces it).
#
# ALWAYS exits 0. Claude Code surfaces SessionEnd output in debug mode only, so
# the report goes to stderr for `claude --debug`.
#
# Dependencies: git; jq (optional, see payload_field).
# ============================================================================

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/git-common.sh
# For autosync_disabled, resolve_main_repo and reap_remote_session_branch.
source "$SCRIPT_DIR/lib/git-common.sh"

# GIT_AUTOSYNC_DISABLE turns every hook into a no-op.
if autosync_disabled; then
    exit 0
fi

PAYLOAD=""

# Pull a string field out of the hook payload. jq when available; otherwise
# sed, which is enough for the two fields used here (`reason` and `cwd` are
# plain strings with no escapes in practice).
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
cwd="$(payload_field cwd)"

case "$reason" in
    resume|clear)
        # Paused or cleared: the session and its branch are not gone.
        exit 0
        ;;
esac

if [[ -z "$cwd" || ! -d "$cwd" ]]; then
    cwd="$PWD"
fi

# Rule zero: outside a git repository there is nothing to reap and nothing to
# say. resolve_main_repo is only the gate here - it succeeds exactly when cwd is
# inside a repo.
resolve_main_repo "$cwd" >/dev/null || exit 0

# The branch from the tree's own HEAD, not an env-var guess. The shared helper
# only acts on a `worktree-*` name, so a session that ended on anything else is
# a no-op here.
branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"

# Reap from cwd, the session's own (still-present) worktree: its submodules are
# populated there, so each one's `worktree-*` branch is reachable to delete. The
# remote is shared across a repo's worktrees, so the superproject delete works
# from here just as well as from the main checkout.
reap_remote_session_branch "$cwd" "$branch"

report="$(render_report)"
if [[ -n "$report" ]]; then
    echo "$report" >&2
fi

exit 0
