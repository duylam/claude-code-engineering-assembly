#!/bin/bash

# ============================================================================
# inject-protocol.sh — carry the clock-in / clock-out protocol with the plugin
# instead of hand-copying it into each project's CLAUDE.md.
#
# Two roles, both driven from hooks.json:
#
#   (default)  UserPromptSubmit — stdout is added to the model's context for
#              this turn. Injection is tiered so a per-turn reminder does not
#              become a per-turn token bill:
#
#                  first prompt of a context -> the full protocol (protocol.md)
#                  every later prompt        -> a one-line standing reminder
#
#              The one-liner is re-emitted each turn on purpose: a single
#              up-front injection is the first thing dropped by compaction, in
#              exactly the long sessions where a clock-out reminder matters most.
#
#   --reset    SessionStart (source=clear|compact) — drop the marker and print
#              nothing, so the next prompt gets the full protocol again.
#              `/clear` wipes the conversation but KEEPS the session id, so
#              without this the marker would survive the wipe and the protocol
#              would never be re-injected for the rest of the session.
# ============================================================================

set -euo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROTOCOL="$HOOK_DIR/protocol.md"

RESET=0
[[ "${1:-}" == "--reset" ]] && RESET=1

# The hook payload arrives as JSON on stdin; pull session_id without needing jq.
PAYLOAD="$(cat || true)"
SESSION_ID="$(printf '%s' "$PAYLOAD" \
    | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1)"

MARKER_DIR="${TMPDIR:-/tmp}/claude-work-journal"
MARKER="$MARKER_DIR/${SESSION_ID:-unknown}.injected"

# The context was wiped (/clear) or summarized (compact): forget that this
# session was ever briefed, and stay silent.
if [[ "$RESET" == "1" ]]; then
    rm -f "$MARKER" 2>/dev/null || true
    exit 0
fi

if [[ -n "$SESSION_ID" && -f "$MARKER" ]]; then
    echo "Session protocol active: clock-out with work-journal:diary-writer (--work, --closes) before any git commit."
    exit 0
fi

mkdir -p "$MARKER_DIR" 2>/dev/null || true
: > "$MARKER" 2>/dev/null || true

if [[ -f "$PROTOCOL" ]]; then
    cat "$PROTOCOL"
fi
exit 0
