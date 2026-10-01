#!/bin/bash
# A failed fetch must never block the session. The hook exits 0, records the
# failure as a Warning in git.status, and the attach step still runs on the
# local remote-tracking refs. This path used to be covered by the removed
# cross-process barrier test; the single-process design must still guarantee it.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SANDBOX="$(sandbox fetchfail)"
BASE="${TMPDIR:-/tmp}/claude-git"
SID="fetchfail-$$"
trap 'rm -rf "$SANDBOX" "$BASE/$SID"' EXIT

make_origin "$SANDBOX"
make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"
# Steady state: worktree excludes already in place, so the attach pass does not
# emit its one-time housekeeping note on top of the fetch warning.
preexclude_worktrees "$CLONE"

# Make the remote unreachable so the fetch step fails. The clone keeps its
# origin config and its local remote-tracking refs, so the attach can still run.
rm -rf "$SANDBOX/origin.git"

echo "--- a failed fetch is recorded but blocks neither the attach nor the session ---"
out="$(printf '{"cwd":"%s","session_id":"%s"}' "$CLONE" "$SID" | bash "$HOOKS/session-start.sh" 2>&1)"; rc=$?
check "hook exits 0 despite the fetch failure" "0" "$rc"
check "fetch failure recorded as a warning" "yes" \
      "$(grep -q 'could not fetch' "$BASE/$SID/git.status" 2>/dev/null && echo yes || echo no)"
check "the attach step still ran (summary emitted)" "yes" \
      "$([[ "$out" == *"attached mode"* ]] && echo yes || echo no)"
echo

report
