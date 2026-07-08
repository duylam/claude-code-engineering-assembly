#!/bin/bash

# ============================================================================
# append-log.sh — append a LOG- (diary) entry to .claude/memory/diary.md
#
# Computes the entry id (LOG-<date>-NN), an ISO 8601 timestamp, and the current
# HEAD short SHA, validates that every referenced DEC- id exists, then appends
# the entry. The body (### Did / ### Why / ### Next) is read from stdin.
# ============================================================================

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
MEMORY_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/memory"
readonly DIARY="$MEMORY_DIR/diary.md"
readonly DECISIONS="$MEMORY_DIR/decisions.md"

TAGS=""
REFS=""

usage() {
    echo "Usage: $SCRIPT_NAME [--tags \"a,b\"] [--refs \"DEC-...,DEC-...\"] < body"
    echo "  Reads the ### Did / ### Why / ### Next block from stdin."
    exit "${1:-0}"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tags) TAGS="${2:-}"; shift 2 ;;
        --refs) REFS="${2:-}"; shift 2 ;;
        -h|--help) usage 0 ;;
        *) echo "Error: unknown option: $1" >&2; usage 1 ;;
    esac
done

# Read the entry body from stdin and reject an effectively empty one.
BODY="$(cat)"
if [[ -z "${BODY//[$'\t\r\n ']/}" ]]; then
    echo "Error: empty entry body on stdin (expected ### Did / ### Why / ### Next)" >&2
    exit 1
fi

mkdir -p "$MEMORY_DIR"
[[ -f "$DIARY" ]] || : > "$DIARY"

# Invariant: every Refs: id must already exist in decisions.md.
if [[ -n "$REFS" ]]; then
    IFS=',' read -ra _refs <<< "$REFS"
    for ref in "${_refs[@]}"; do
        ref="$(echo "$ref" | xargs)"   # trim surrounding whitespace
        [[ -z "$ref" ]] && continue
        if ! grep -q "^## ${ref} " "$DECISIONS" 2>/dev/null; then
            echo "Error: Refs id '$ref' not found in $DECISIONS (every Refs: id must exist)" >&2
            exit 1
        fi
    done
fi

# Compute id / timestamp / commit context.
DATE="$(date +%F)"
COUNT="$(grep -c "^## LOG-${DATE}-" "$DIARY" 2>/dev/null || true)"
NN="$(printf '%02d' "$(( ${COUNT:-0} + 1 ))")"
ID="LOG-${DATE}-${NN}"
TS="$(date -Iseconds)"
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo 'no-commit')"

# Append newest at bottom; the leading blank line keeps entries record-delimited.
{
    printf '\n## %s · %s · commit-id=%s\n' "$ID" "$TS" "$SHA"
    printf 'Tags: %s\n' "$TAGS"
    printf 'Refs: %s\n' "${REFS:--}"
    printf '\n%s\n' "$BODY"
} >> "$DIARY"

# Stage the entry so it ships in the same commit as the code (best-effort).
git add -- "$DIARY" 2>/dev/null || true

echo "$ID"
