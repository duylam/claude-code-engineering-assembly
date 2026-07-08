#!/bin/bash

# ============================================================================
# read-decision.sh — slice DEC- (decision) entries from
# .claude/memory/decisions.md
#
# Cheap, greppable reads that never load the whole file. Entries are delimited
# by their `## ` header line (they contain internal blank lines, so blank-line
# records would split a single entry).
# ============================================================================

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
MEMORY_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/memory"
readonly FILE="$MEMORY_DIR/decisions.md"
readonly PREFIX="DEC"

MODE="last"
N="20"
ARG=""

usage() {
    echo "Usage: $SCRIPT_NAME [--last N | --headers | --id DEC-id | --date YYYY-MM-DD | --tag T | --ref LOG-id | --status S]"
    echo "  --status one of: proposed|accepted|superseded|rejected"
    echo "  Default: --last 20"
    exit "${1:-0}"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --last) MODE="last"; N="${2:-20}"; shift 2 ;;
        --headers) MODE="headers"; shift ;;
        --id) MODE="id"; ARG="${2:-}"; shift 2 ;;
        --date) MODE="date"; ARG="${2:-}"; shift 2 ;;
        --tag) MODE="tag"; ARG="${2:-}"; shift 2 ;;
        --ref) MODE="ref"; ARG="${2:-}"; shift 2 ;;
        --status) MODE="status"; ARG="${2:-}"; shift 2 ;;
        -h|--help) usage 0 ;;
        *) echo "Error: unknown option: $1" >&2; usage 1 ;;
    esac
done

if [[ ! -s "$FILE" ]]; then
    echo "no entries yet"
    exit 0
fi

if [[ "$MODE" == "headers" ]]; then
    grep -nE "^## ${PREFIX}-" "$FILE" || echo "no entries yet"
    exit 0
fi

# Split into whole entries at header boundaries, filter by mode, then print.
awk -v mode="$MODE" -v arg="$ARG" -v n="$N" -v p="$PREFIX" '
function want(e,   h) {
    h = e; sub(/\n.*/, "", h)                       # header = first line
    if (mode=="id")     return (index(h, "## " arg " ")>0 || h=="## " arg)
    if (mode=="date")   return (h ~ ("^## " p "-" arg "-"))
    if (mode=="status") return (h ~ ("status=" arg "([^a-z]|$)"))
    if (mode=="tag")    return (e ~ ("(^|\n)Tags:[^\n]*" arg))
    if (mode=="ref")    return (e ~ ("(^|\n)Refs:[^\n]*" arg))
    return 1                                         # last / default
}
/^## (LOG|DEC)-/ { if (cur!="") ent[++ne]=cur; cur=$0 "\n"; next }
{ if (cur!="") cur=cur $0 "\n" }
END {
    if (cur!="") ent[++ne]=cur
    m=0
    for (i=1;i<=ne;i++) if (want(ent[i])) match_[++m]=ent[i]
    s = (mode=="last") ? m-n+1 : 1
    if (s<1) s=1
    for (i=s;i<=m;i++) printf "%s\n", match_[i]
}' "$FILE"
