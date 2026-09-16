#!/bin/bash
# GIT_PLUGIN_DISABLE - the one global off switch. Any non-empty value turns the
# SessionStart fetch into a no-op: no fetch, no barrier markers.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SANDBOX="$(sandbox gitdisable)"
BASE="${TMPDIR:-/tmp}/claude-git"
trap 'rm -rf "$SANDBOX" "$BASE/gitdis-off-$$" "$BASE/gitdis-on-$$"' EXIT

make_origin "$SANDBOX"
make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"

# The remote moves ahead, so a fetch would have something to do - if one ran.
advance_origin "$SANDBOX" c2
advance_origin "$SANDBOX" c3
TIP="$(git -C "$SANDBOX/seed" rev-parse HEAD)"

echo "--- SessionStart fetch is inert when disabled ---"
out="$(printf '{"cwd":"%s","session_id":"gitdis-off-%s"}' "$CLONE" "$$" | GIT_PLUGIN_DISABLE=1 bash "$HOOKS/session-start.sh" 2>&1)"
check "prints nothing" "" "$out"
check "no fetch ran (origin/main untouched)" "yes" \
      "$([[ "$(git -C "$CLONE" rev-parse origin/main)" != "$TIP" ]] && echo yes || echo no)"
check "no barrier markers written" "no" \
      "$([[ -e "$BASE/gitdis-off-$$/fetch-started" ]] && echo yes || echo no)"
echo

echo "--- enabled by default: the fetch runs and writes markers ---"
printf '{"cwd":"%s","session_id":"gitdis-on-%s"}' "$CLONE" "$$" | bash "$HOOKS/session-start.sh" >/dev/null 2>&1
check "fetch ran (origin/main == remote tip)" "$TIP" "$(git -C "$CLONE" rev-parse origin/main)"
check "both barrier markers written" "yes" \
      "$([[ -e "$BASE/gitdis-on-$$/fetch-started" && -e "$BASE/gitdis-on-$$/fetch-done" ]] && echo yes || echo no)"
echo

report
