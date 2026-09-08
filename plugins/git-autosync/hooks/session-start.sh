#!/bin/bash

# ============================================================================
# session-start.sh - SessionStart hook: one sync pass before the first prompt
#
# Runs git-sync.sh, which reconciles the branch this tree is on with the remote
# and then chains ensure-submodules.sh for the submodule pass. Calling that
# second worker here too would only make it fetch every submodule twice.
#
# The sync is always a merge and always exits 0 - the hook must never reach a
# destructive path, and must never fail a session.
#
# This is what makes a session current on start, including a
# `claude remote-control --spawn worktree` session whose worktree was cut from a
# possibly-stale remote-tracking ref. When there is nothing to do it costs one
# cheap `git fetch` and stays silent.
#
# The worker's plain-text output is wrapped in a hook JSON envelope, so the
# session opens with one short status line. Silence when it had nothing to say
# - the normal case.
#
# ALWAYS exits 0. The workers never fail; this wrapper must not either.
#
# Dependencies: git; jq (optional - without it the same text is printed
# plainly, which SessionStart also accepts).
# ============================================================================

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/git-common.sh
# Only for autosync_disabled - the plugin's global off switch.
source "$SCRIPT_DIR/lib/git-common.sh"

# GIT_AUTOSYNC_DISABLE turns every hook into a no-op. Nothing read, nothing run.
if autosync_disabled; then
    exit 0
fi

payload="$(cat || true)"

# The directory Claude Code started in. In a worktree session this is the
# worktree, which is exactly the tree whose submodules must be synced.
cwd=""
if command -v jq >/dev/null 2>&1; then
    cwd="$(jq -r '.cwd // empty' <<<"$payload" 2>/dev/null || true)"
else
    # No jq: pull the field with sed. `cwd` is a plain path string in practice.
    cwd="$(sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$payload" | head -n 1)"
fi
if [[ -z "$cwd" || ! -d "$cwd" ]]; then
    cwd="$PWD"
fi

report="$(bash "$SCRIPT_DIR/git-sync.sh" -C "$cwd" || true)"

if [[ -z "$report" ]]; then
    exit 0
fi

if command -v jq >/dev/null 2>&1; then
    jq -n --arg msg "$report" \
        '{
            systemMessage: $msg,
            hookSpecificOutput: {
                hookEventName: "SessionStart",
                additionalContext: $msg
            }
        }'
else
    echo "$report"
fi

exit 0
