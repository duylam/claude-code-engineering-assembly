#!/bin/bash

# ============================================================================
# read-decision.sh — slice DEC- (decision) entries from
# .claude/memory/decisions.md
#
# Cheap, greppable reads that never load the whole file. Entries are delimited
# by their `## ` header line (they contain internal blank lines, so blank-line
# records would split a single entry).
#
# Selectors compose: every one supplied is ANDed, and --last N is applied to
# whatever survives the filter.
# ============================================================================

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
MEMORY_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/memory"
readonly FILE="$MEMORY_DIR/decisions.md"

HEADERS_ONLY="0"
N="20"
F_ID=""
F_DATE=""
F_SINCE=""
F_TAG=""
F_REF=""
F_WORK=""
F_STATUS=""

usage() {
    echo "Usage: $SCRIPT_NAME [--headers] [--last N] [--work KEY] [--since YYYY-MM-DD]"
    echo "         [--date YYYY-MM-DD] [--tag T] [--ref LOG-id] [--status S] [--id DEC-id]"
    echo "  --status one of: proposed|accepted|superseded|rejected"
    echo "  Selectors compose (e.g. --work JIRA-123 --since 2026-07-04)."
    echo "  Default: --last 20"
    exit "${1:-0}"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --headers) HEADERS_ONLY="1"; shift ;;
        --last) N="${2:-20}"; shift 2 ;;
        --id) F_ID="${2:-}"; shift 2 ;;
        --date) F_DATE="${2:-}"; shift 2 ;;
        --since) F_SINCE="${2:-}"; shift 2 ;;
        --tag) F_TAG="${2:-}"; shift 2 ;;
        --ref) F_REF="${2:-}"; shift 2 ;;
        --work) F_WORK="${2:-}"; shift 2 ;;
        --status) F_STATUS="${2:-}"; shift 2 ;;
        -h|--help) usage 0 ;;
        *) echo "Error: unknown option: $1" >&2; usage 1 ;;
    esac
done

if [[ ! -s "$FILE" ]]; then
    echo "no entries yet"
    exit 0
fi

# Split into whole entries at header boundaries, AND every supplied selector,
# then apply --last to the survivors.
awk -v n="$N" -v headers="$HEADERS_ONLY" \
    -v fid="$F_ID" -v fdate="$F_DATE" -v fsince="$F_SINCE" -v ftag="$F_TAG" \
    -v fref="$F_REF" -v fwork="$F_WORK" -v fstatus="$F_STATUS" '
function want(e,   h, d) {
    h = e; sub(/\n.*/, "", h)                                # header = first line
    if (fid     != "" && index(h, "## " fid " ") == 0)                     return 0
    if (fdate   != "" && h !~ ("^## DEC-" fdate "-"))                      return 0
    if (fsince  != "") { d = substr(h, 8, 10); if (d < fsince)             return 0 }
    if (fstatus != "" && h !~ ("status=" fstatus "([^a-z]|$)"))            return 0
    if (ftag    != "" && e !~ ("(^|\n)Tags:[^\n]*" ftag))                  return 0
    if (fref    != "" && e !~ ("(^|\n)Refs:[^\n]*" fref))                  return 0
    if (fwork   != "" && e !~ ("(^|\n)Work:[ \t]*" fwork "[ \t]*(\n|$)"))  return 0
    return 1
}
/^## DEC-/ { if (cur != "") ent[++ne] = cur; cur = $0 "\n"; next }
{ if (cur != "") cur = cur $0 "\n" }
END {
    if (cur != "") ent[++ne] = cur
    m = 0
    for (i = 1; i <= ne; i++) if (want(ent[i])) match_[++m] = ent[i]
    if (m == 0) { print "no matching entries"; exit }
    s = m - n + 1; if (s < 1) s = 1
    for (i = s; i <= m; i++) {
        if (headers == "1") { h = match_[i]; sub(/\n.*/, "", h); print h }
        else                  printf "%s\n", match_[i]
    }
}' "$FILE"
