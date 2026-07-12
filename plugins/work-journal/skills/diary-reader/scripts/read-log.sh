#!/bin/bash

# ============================================================================
# read-log.sh — slice LOG- (diary) entries from .claude/memory/diary.md
#
# Cheap, greppable reads that never load the whole file. Entries are delimited
# by their `## ` header line (they contain internal blank lines, so blank-line
# records would split a single entry).
#
# Selectors compose: every one supplied is ANDed, and --last N is applied to
# whatever survives the filter.
#
# --open derives the pending items: every [NEXT-id] bullet ever written, minus
# every id named on a `Closes:` line. That is the "what is still pending"
# answer, computed rather than inferred.
# ============================================================================

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
MEMORY_DIR="${CLAUDE_PROJECT_DIR:-.}/.claude/memory"
readonly FILE="$MEMORY_DIR/diary.md"

MODE="entries"
N="20"
F_ID=""
F_DATE=""
F_SINCE=""
F_TAG=""
F_REF=""
F_WORK=""
F_PHASE=""

usage() {
    echo "Usage: $SCRIPT_NAME [--session-brief] [--open] [--headers] [--last N]"
    echo "         [--work KEY] [--since YYYY-MM-DD] [--date YYYY-MM-DD]"
    echo "         [--phase P] [--tag T] [--ref DEC-id] [--id LOG-id]"
    echo "  Selectors compose (e.g. --work JIRA-123 --since 2026-07-04)."
    echo "  Default: --last 20"
    exit "${1:-0}"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --session-brief) MODE="brief"; shift ;;
        --open) MODE="open"; shift ;;
        --headers) MODE="headers"; shift ;;
        --last) N="${2:-20}"; shift 2 ;;
        --id) F_ID="${2:-}"; shift 2 ;;
        --date) F_DATE="${2:-}"; shift 2 ;;
        --since) F_SINCE="${2:-}"; shift 2 ;;
        --tag) F_TAG="${2:-}"; shift 2 ;;
        --ref) F_REF="${2:-}"; shift 2 ;;
        --work) F_WORK="${2:-}"; shift 2 ;;
        --phase) F_PHASE="${2:-}"; shift 2 ;;
        -h|--help) usage 0 ;;
        *) echo "Error: unknown option: $1" >&2; usage 1 ;;
    esac
done

if [[ ! -s "$FILE" ]]; then
    echo "no entries yet"
    exit 0
fi

# ---------------------------------------------------------------------------
# Open items: created ([NEXT-id] bullets) minus closed (Closes: id lists).
# ---------------------------------------------------------------------------
print_open() {
    awk -v fwork="$F_WORK" '
    /^## LOG-/  { logid = $2; work = "-"; next }
    /^Work: /   { work = substr($0, 7); sub(/[ \t]+$/, "", work); next }
    /^Closes: / {
        list = substr($0, 9)
        n = split(list, a, ",")
        for (i = 1; i <= n; i++) { gsub(/[ \t]/, "", a[i]); if (a[i] != "" && a[i] != "-") closed[a[i]] = 1 }
        next
    }
    /^[-*][ \t]+\[NEXT-/ {
        s = index($0, "["); e = index($0, "]")
        id = substr($0, s + 1, e - s - 1)
        text = substr($0, e + 1); sub(/^[ \t]+/, "", text)
        order[++k] = id; itext[id] = text; iwork[id] = work; ilog[id] = logid
        next
    }
    END {
        for (i = 1; i <= k; i++) {
            id = order[i]
            if (id in closed) continue
            if (fwork != "" && iwork[id] != fwork) continue
            printf "%s · work=%s · opened in %s · %s\n", id, iwork[id], ilog[id], itext[id]
            found++
        }
        if (!found) print "no open items"
    }' "$FILE"
}

# ---------------------------------------------------------------------------
# Entry filter: split at header boundaries, AND every supplied selector,
# then apply --last to the survivors.
# ---------------------------------------------------------------------------
print_entries() {
    local headers_only="$1"
    awk -v n="$N" -v headers="$headers_only" \
        -v fid="$F_ID" -v fdate="$F_DATE" -v fsince="$F_SINCE" \
        -v ftag="$F_TAG" -v fref="$F_REF" -v fwork="$F_WORK" -v fphase="$F_PHASE" '
    function want(e,   h, d) {
        h = e; sub(/\n.*/, "", h)                            # header = first line
        if (fid    != "" && index(h, "## " fid " ") == 0)                  return 0
        if (fdate  != "" && h !~ ("^## LOG-" fdate "-"))                   return 0
        if (fsince != "") { d = substr(h, 8, 10); if (d < fsince)          return 0 }
        if (ftag   != "" && e !~ ("(^|\n)Tags:[^\n]*" ftag))               return 0
        if (fref   != "" && e !~ ("(^|\n)Refs:[^\n]*" fref))               return 0
        if (fwork  != "" && e !~ ("(^|\n)Work:[ \t]*" fwork "[ \t]*(\n|$)")) return 0
        if (fphase != "" && e !~ ("(^|\n)Phase:[ \t]*" fphase "[ \t]*(\n|$)")) return 0
        return 1
    }
    /^## LOG-/ { if (cur != "") ent[++ne] = cur; cur = $0 "\n"; next }
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
}

case "$MODE" in
    open)
        print_open
        ;;
    brief)
        echo "== Open items${F_WORK:+ (work=$F_WORK)} =="
        print_open
        echo
        echo "== Recent entries (last $N) =="
        print_entries 1
        echo
        echo "(follow up: read-log.sh --id LOG-… for a full entry; decision-reader for DEC- entries)"
        ;;
    headers)
        print_entries 1
        ;;
    *)
        print_entries 0
        ;;
esac
