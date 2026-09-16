#!/bin/bash

# ============================================================================
# session-start.sh - SessionStart hook: fetch + prune before the first prompt
#
# Brings the repository's remote-tracking refs level with the remote before the
# agent starts: fetches every branch and every tag from every remote, and prunes
# stale branch and tag refs. This is the state the git-autosync plugin's
# attach-only sync then reads from, without fetching itself.
#
# The two plugins run their SessionStart hooks in parallel with no ordering
# guarantee, so they coordinate through marker files in the shared session dir:
# this hook writes `fetch-started` on entry and ALWAYS writes `fetch-done` on
# exit - via an EXIT/TERM/INT trap, so the marker lands even when the fetch
# fails or the hook is killed at its timeout. git-autosync waits on those
# markers before it attaches.
#
# Never fails a session: does nothing outside a git repo or in a repo with no
# remote, warns instead of failing on a fetch error, and always exits 0. The
# collected report (fetch/prune result and any warnings) is persisted as this
# session's latest status for the read-only launch-status skill; nothing is
# written to the agent's context.
#
# Off switch: GIT_PLUGIN_DISABLE non-empty turns this into a no-op (no markers).
#
# Dependencies: git; jq (optional - only used to read cwd/session_id from the
# hook payload, with a sed fallback).
# ============================================================================

set -uo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/git-common.sh
source "$SCRIPT_DIR/lib/git-common.sh"

# GIT_PLUGIN_DISABLE turns every hook into a no-op. No markers are written, so
# git-autosync's 5s grace sees no fetch-started and proceeds without waiting.
if git_plugin_disabled; then
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

cwd="$(payload_field cwd)"
if [[ -z "$cwd" || ! -d "$cwd" ]]; then
    cwd="$PWD"
fi
session_id="$(payload_field session_id)"

# The barrier. fetch-started announces we are participating; fetch-done is
# written no matter how this hook ends, so git-autosync's wait always terminates.
DIR="$(session_dir "$session_id" || true)"
if [[ -n "$DIR" ]]; then
    trap 'touch "$DIR/fetch-done" 2>/dev/null || true' EXIT TERM INT
    touch "$DIR/fetch-started" 2>/dev/null || true
fi

# Outside a git repo, or a repo with no remote: nothing to fetch. The trap has
# already been armed, so fetch-done is still written on the way out.
MAIN_REPO="$(resolve_main_repo "$cwd")" || exit 0
REMOTE="$(first_remote "$MAIN_REPO")" || exit 0

# Every branch and every tag from every remote, pruning stale branch and tag
# refs so the local remote-tracking refs match the remote exactly.
if run_capture git -C "$MAIN_REPO" fetch --all --tags --prune --prune-tags; then
    add_note "fetched and pruned $REMOTE (branches and tags)"
else
    add_warning "could not fetch $REMOTE ($(capture_reason))"
fi

persist_status "$session_id"

exit 0
