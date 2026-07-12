#!/bin/bash

# ============================================================================
# append-log.sh — append a LOG- (diary) entry to .claude/memory/diary.md
#
# Computes the entry id (LOG-<date>-NN), an ISO 8601 timestamp, and the current
# HEAD short SHA. Allocates an id for every bullet under `### Next` so it
# becomes an addressable open item ([NEXT-<date>-NN]), and closes the items
# listed in --closes. Validates that every referenced DEC- id exists.
#
# The body (### Did / ### Why / ### Next) is read from stdin.
# ============================================================================

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
MEMORY_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/memory"
readonly DIARY="$MEMORY_DIR/diary.md"
readonly DECISIONS="$MEMORY_DIR/decisions.md"

WORK="-"
PHASE="-"
SESSION="-"
TAGS=""
REFS=""
CLOSES=""

usage() {
    echo "Usage: $SCRIPT_NAME [--work KEY] [--phase P] [--session ID] [--tags \"a,b\"]"
    echo "         [--refs \"DEC-...,DEC-...\"] [--closes \"NEXT-...,NEXT-...\"] < body"
    echo "  --phase one of: explore|plan|implement|review|uat|other"
    echo "  Reads the ### Did / ### Why / ### Next block from stdin."
    echo "  Bullets under ### Next are assigned [NEXT-<date>-NN] ids automatically."
    exit "${1:-0}"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --work) WORK="${2:-}"; shift 2 ;;
        --phase) PHASE="${2:-}"; shift 2 ;;
        --session) SESSION="${2:-}"; shift 2 ;;
        --tags) TAGS="${2:-}"; shift 2 ;;
        --refs) REFS="${2:-}"; shift 2 ;;
        --closes) CLOSES="${2:-}"; shift 2 ;;
        -h|--help) usage 0 ;;
        *) echo "Error: unknown option: $1" >&2; usage 1 ;;
    esac
done

case "$PHASE" in
    explore|plan|implement|review|uat|other|-) ;;
    *) echo "Error: --phase must be one of explore|plan|implement|review|uat|other" >&2; exit 1 ;;
esac

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

# Invariant: every --closes id must exist as an open item. An id that is already
# closed is dropped with a notice rather than failing — re-closing is harmless.
CLOSES_OK=""
if [[ -n "$CLOSES" ]]; then
    IFS=',' read -ra _closes <<< "$CLOSES"
    for cid in "${_closes[@]}"; do
        cid="$(echo "$cid" | xargs)"
        [[ -z "$cid" || "$cid" == "-" ]] && continue
        if ! grep -q "\[${cid}\]" "$DIARY" 2>/dev/null; then
            echo "Error: Closes id '$cid' not found in $DIARY (it was never opened)" >&2
            exit 1
        fi
        if grep -qE "^Closes:.*(^|[ ,])${cid}([ ,]|$)" "$DIARY" 2>/dev/null; then
            echo "Notice: '$cid' is already closed — dropping it from Closes:" >&2
            continue
        fi
        CLOSES_OK="${CLOSES_OK:+$CLOSES_OK, }$cid"
    done
fi

# Compute id / timestamp / commit context.
DATE="$(date +%F)"
COUNT="$(grep -c "^## LOG-${DATE}-" "$DIARY" 2>/dev/null || true)"
NN="$(printf '%02d' "$(( ${COUNT:-0} + 1 ))")"
ID="LOG-${DATE}-${NN}"
TS="$(date -Iseconds)"
SHA="$(git rev-parse --short HEAD 2>/dev/null || echo 'no-commit')"

# Continue today's NEXT- sequence wherever the diary left it.
LAST_NEXT="$(grep -o "\[NEXT-${DATE}-[0-9][0-9]\]" "$DIARY" 2>/dev/null \
    | sed 's/.*-\([0-9][0-9]\)\]/\1/' | sort -n | tail -1 || true)"
START="$(( 10#${LAST_NEXT:-0} + 1 ))"

# Assign an id to each un-idded bullet under `### Next` so it becomes trackable.
BODY="$(printf '%s\n' "$BODY" | awk -v date="$DATE" -v start="$START" '
/^### / { section = $0 }
{
    if (section ~ /^### Next/ && $0 ~ /^[-*][ \t]+/ && $0 !~ /\[NEXT-/) {
        sub(/^[-*][ \t]+/, "")
        if ($0 == "") { print; next }
        printf "- [NEXT-%s-%02d] %s\n", date, start++, $0
        next
    }
    print
}')"

# Append newest at bottom; the leading blank line keeps entries record-delimited.
{
    printf '\n## %s · %s · commit-id=%s\n' "$ID" "$TS" "$SHA"
    printf 'Work: %s\n' "${WORK:--}"
    printf 'Phase: %s\n' "${PHASE:--}"
    printf 'Session: %s\n' "${SESSION:--}"
    printf 'Tags: %s\n' "$TAGS"
    printf 'Refs: %s\n' "${REFS:--}"
    printf 'Closes: %s\n' "${CLOSES_OK:--}"
    printf '\n%s\n' "$BODY"
} >> "$DIARY"

# Stage the entry so it ships in the same commit as the code (best-effort).
git add -- "$DIARY" 2>/dev/null || true

echo "$ID"
printf '%s\n' "$BODY" | grep -o "\[NEXT-${DATE}-[0-9][0-9]\]" | tr -d '[]' | sed 's/^/opened /' || true
[[ -n "$CLOSES_OK" ]] && echo "closed $CLOSES_OK"
exit 0
