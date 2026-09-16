#!/bin/bash
# GIT_AUTOSYNC_DISABLE - the one global off switch. Any non-empty value (now
# including "0") turns the SessionStart attach into a no-op: no fast-forward,
# no status file.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SANDBOX="$(sandbox disable)"
BASE="${TMPDIR:-/tmp}/claude-git"
trap 'rm -rf "$SANDBOX" "$BASE/ad-off-$$" "$BASE/ad-zero-$$" "$BASE/ad-on-$$"' EXIT

make_origin "$SANDBOX"
make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"

advance_origin "$SANDBOX" c2
advance_origin "$SANDBOX" c3
TIP="$(git -C "$SANDBOX/seed" rev-parse HEAD)"
# The `git` plugin has fetched; the clone is on a branch that is behind and would
# fast-forward if the attach ran.
git -C "$CLONE" fetch -q origin
git -C "$CLONE" checkout -q -b feature "origin/main~2"

behind() { [[ "$(git -C "$CLONE" rev-parse HEAD)" != "$TIP" ]] && echo yes || echo no; }

echo "--- disabled with =1: inert ---"
out="$(printf '{"cwd":"%s","session_id":"ad-off-%s"}' "$CLONE" "$$" | GIT_AUTOSYNC_DISABLE=1 bash "$HOOKS/session-start.sh" 2>&1)"
check "prints nothing" "" "$out"
check "branch NOT fast-forwarded" "yes" "$(behind)"
check "no status file written" "no" \
      "$([[ -e "$BASE/ad-off-$$/git-autosync.status" ]] && echo yes || echo no)"
echo

echo "--- disabled with =0: now also inert (non-empty disables) ---"
out="$(printf '{"cwd":"%s","session_id":"ad-zero-%s"}' "$CLONE" "$$" | GIT_AUTOSYNC_DISABLE=0 bash "$HOOKS/session-start.sh" 2>&1)"
check "prints nothing" "" "$out"
check "branch still NOT fast-forwarded" "yes" "$(behind)"
echo

echo "--- enabled by default: the attach runs ---"
printf '{"cwd":"%s","session_id":"ad-on-%s"}' "$CLONE" "$$" | bash "$HOOKS/session-start.sh" >/dev/null 2>&1
check "branch fast-forwarded to the remote tip" "$TIP" "$(git -C "$CLONE" rev-parse HEAD)"
check "status file records the attach" "yes" \
      "$(grep -q 'fast-forwarded feature' "$BASE/ad-on-$$/git-autosync.status" 2>/dev/null && echo yes || echo no)"
echo

report
