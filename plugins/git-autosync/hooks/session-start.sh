#!/bin/bash

# ============================================================================
# session-start.sh - SessionStart hook: attach the tree before the first prompt
#
# Waits for the `git` plugin's fetch (the barrier), then runs git-sync.sh, which
# fast-forwards the branch this tree is on to the remote's default branch using
# the already-fetched remote-tracking refs and attaches every top-level
# submodule. This plugin never fetches - it reads what the `git` plugin refreshed.
#
# What this hook produces:
#   - The human status: git-sync.sh's plain-text report (notes and warnings) is
#     persisted as this session's latest git-autosync status, read on demand by
#     the read-only launch-status skill. Only the latest is kept.
#   - The agent context: when the tree was attached and the pass ran, ONE short
#     summary line is injected so the session knows the git state is attached for
#     new commits, in the superproject and its submodules. Nothing is injected on
#     a detached-HEAD / non-git / no-remote no-op.
#
# ALWAYS exits 0. git-sync.sh never fails; this wrapper must not either.
#
# Off switch: GIT_AUTOSYNC_DISABLE non-empty turns this into a no-op.
#
# Dependencies: git; jq (optional - only to read cwd/session_id from the payload,
# with a sed fallback).
# ============================================================================

set -uo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/git-common.sh
source "$SCRIPT_DIR/lib/git-common.sh"

# GIT_AUTOSYNC_DISABLE turns every hook into a no-op. Nothing read, nothing run.
if autosync_disabled; then
    exit 0
fi

payload="$(cat || true)"

# Pull a scalar string field out of the hook payload. jq when available, a
# narrow sed fallback otherwise (cwd and session_id are plain strings).
payload_field() {
    local key="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -r --arg k "$key" '.[$k] // empty' <<<"$payload" 2>/dev/null || true
    else
        sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" <<<"$payload" | head -n 1
    fi
}

# The directory Claude Code started in. In a worktree session this is the
# worktree, which is exactly the tree whose branch and submodules must be synced.
cwd="$(payload_field cwd)"
if [[ -z "$cwd" || ! -d "$cwd" ]]; then
    cwd="$PWD"
fi
session_id="$(payload_field session_id)"

# Barrier: wait for the `git` plugin's fetch to finish (bounded; returns at once
# when the git plugin is not participating) so the attach reads fresh refs.
wait_for_fetch "$session_id"

report="$(bash "$SCRIPT_DIR/git-sync.sh" -C "$cwd" 2>/dev/null)"
rc=$?

# Persist the report as this session's latest human status (empty is fine).
DIR="$(session_dir "$session_id" || true)"
if [[ -n "$DIR" ]]; then
    printf '%s\n' "$report" >"$DIR/git-autosync.status" 2>/dev/null || true
fi

# rc 0 means git-sync.sh attached the tree and ran the pass. Anything else
# (10 = clean no-op: detached HEAD / not a git repo / no remote) means there is
# nothing to tell the agent about.
if [[ "$rc" -ne 0 ]]; then
    exit 0
fi

summary="The git repository is in attached mode for new commits. Each top-level submodule is in attached mode for new commits (inside the submodule)."

# This summary is for the AGENT, not the human. On SessionStart, Claude Code adds
# `hookSpecificOutput.additionalContext` (and plain-text stdout) to the model's
# context - that is the channel that reaches the LLM. `systemMessage` is
# deliberately NOT set: it surfaces only in the human's terminal and would not
# reach the model, so emitting it here would just be human-facing noise.
if command -v jq >/dev/null 2>&1; then
    jq -n --arg msg "$summary" \
        '{
            hookSpecificOutput: {
                hookEventName: "SessionStart",
                additionalContext: $msg
            }
        }'
else
    # No jq: plain stdout is added to the model's context on SessionStart.
    echo "$summary"
fi

exit 0
