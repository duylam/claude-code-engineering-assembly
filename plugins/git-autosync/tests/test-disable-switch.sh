#!/bin/bash
# GIT_AUTOSYNC_DISABLE - the one global off switch. The SessionStart sync becomes
# a no-op when it is set, and an explicit "0" is treated as enabled.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SANDBOX="$(sandbox disable)"
trap 'rm -rf "$SANDBOX"' EXIT

make_origin "$SANDBOX"
make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"

# The remote moves ahead, so a sync would have something to do - if one ran.
advance_origin "$SANDBOX" c2
advance_origin "$SANDBOX" c3
TIP="$(git -C "$SANDBOX/seed" rev-parse HEAD)"

echo "--- SessionStart sync is inert when disabled ---"
out="$(printf '{"cwd":"%s"}' "$CLONE" | GIT_AUTOSYNC_DISABLE=1 bash "$HOOKS/session-start.sh" 2>&1)"
check "session-start prints nothing" "" "$out"
check "no fetch ran (origin/main untouched)" "yes" \
      "$([[ "$(git -C "$CLONE" rev-parse origin/main)" != "$TIP" ]] && echo yes || echo no)"
echo

echo "--- GIT_AUTOSYNC_DISABLE=0 is treated as enabled ---"
out0="$(printf '{"cwd":"%s"}' "$CLONE" | GIT_AUTOSYNC_DISABLE=0 bash "$HOOKS/session-start.sh" 2>&1)"
check "an explicit 0 does not disable (the fetch ran)" "$TIP" "$(git -C "$CLONE" rev-parse origin/main)"
echo

report
