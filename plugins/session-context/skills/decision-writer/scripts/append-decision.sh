#!/bin/bash

# ============================================================================
# append-decision.sh — append a DEC- (decision) entry to
# .claude/memory/decisions.md
#
# Computes the entry id (DEC-<date>-NN) and an ISO 8601 timestamp, validates
# that every referenced LOG- id exists, then appends the entry. The body
# (### Consideration / ### Decision / ### Rationale / ### Alternatives) is read
# from stdin.
# ============================================================================

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
MEMORY_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/memory"
readonly DIARY="$MEMORY_DIR/diary.md"
readonly DECISIONS="$MEMORY_DIR/decisions.md"

TITLE=""
TAGS=""
REFS=""
SUPERSEDES="-"
STATUS="accepted"

usage() {
    echo "Usage: $SCRIPT_NAME --title \"...\" [--tags \"a,b\"] [--refs \"LOG-...\"] \\"
    echo "         [--supersedes DEC-id] [--status proposed|accepted|superseded|rejected] < body"
    echo "  Reads the ### Consideration / ### Decision / ### Rationale [/ ### Alternatives] block from stdin."
    exit "${1:-0}"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --title) TITLE="${2:-}"; shift 2 ;;
        --tags) TAGS="${2:-}"; shift 2 ;;
        --refs) REFS="${2:-}"; shift 2 ;;
        --supersedes) SUPERSEDES="${2:-}"; shift 2 ;;
        --status) STATUS="${2:-}"; shift 2 ;;
        -h|--help) usage 0 ;;
        *) echo "Error: unknown option: $1" >&2; usage 1 ;;
    esac
done

# Validate required / constrained inputs.
if [[ -z "$TITLE" ]]; then
    echo "Error: --title is required" >&2
    usage 1
fi
case "$STATUS" in
    proposed|accepted|superseded|rejected) ;;
    *) echo "Error: --status must be one of proposed|accepted|superseded|rejected" >&2; exit 1 ;;
esac

# Read the entry body from stdin and reject an effectively empty one.
BODY="$(cat)"
if [[ -z "${BODY//[$'\t\r\n ']/}" ]]; then
    echo "Error: empty entry body on stdin (expected ### Consideration / ### Decision / ### Rationale)" >&2
    exit 1
fi

mkdir -p "$MEMORY_DIR"
[[ -f "$DECISIONS" ]] || : > "$DECISIONS"

# Invariant: every Refs: id must already exist in diary.md.
if [[ -n "$REFS" ]]; then
    IFS=',' read -ra _refs <<< "$REFS"
    for ref in "${_refs[@]}"; do
        ref="$(echo "$ref" | xargs)"   # trim surrounding whitespace
        [[ -z "$ref" ]] && continue
        if ! grep -q "^## ${ref} " "$DIARY" 2>/dev/null; then
            echo "Error: Refs id '$ref' not found in $DIARY (every Refs: id must exist)" >&2
            exit 1
        fi
    done
fi

# Compute id / timestamp.
DATE="$(date +%F)"
COUNT="$(grep -c "^## DEC-${DATE}-" "$DECISIONS" 2>/dev/null || true)"
NN="$(printf '%02d' "$(( ${COUNT:-0} + 1 ))")"
ID="DEC-${DATE}-${NN}"
TS="$(date -Iseconds)"

# Append newest at bottom; the leading blank line keeps entries record-delimited.
{
    printf '\n## %s · %s · status=%s\n' "$ID" "$TS" "$STATUS"
    printf 'Title: %s\n' "$TITLE"
    printf 'Tags: %s\n' "$TAGS"
    printf 'Refs: %s\n' "${REFS:--}"
    printf 'Supersedes: %s\n' "${SUPERSEDES:--}"
    printf '\n%s\n' "$BODY"
} >> "$DECISIONS"

# Stage the entry so it ships in the same commit as the code (best-effort).
git add -- "$DECISIONS" 2>/dev/null || true

echo "$ID"
