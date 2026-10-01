#!/bin/bash
# Fetch-before-attach ordering. The fetch and the attach run in one process, in
# that order, so the attach fast-forwards the branch using refs the SAME run just
# fetched - the guarantee the old cross-process marker barrier used to provide.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SANDBOX="$(sandbox fetchattach)"
BASE="${TMPDIR:-/tmp}/claude-git"
trap 'rm -rf "$SANDBOX" "$BASE"/fa-*-$$' EXIT

make_origin "$SANDBOX"

# Two identical clones, each on `feature` at the remote tip at clone time.
mkclone() {
    local name="$1"
    local clone="$SANDBOX/$name"
    git clone -q "$SANDBOX/origin.git" "$clone" 2>/dev/null
    git -C "$clone" config user.email test@example.invalid
    git -C "$clone" config user.name "test"
    preexclude_worktrees "$clone"
    git -C "$clone" checkout -q -b feature origin/main
    echo "$clone"
}

C1="$(mkclone c1)"
C2="$(mkclone c2)"
TIP0="$(git -C "$C1" rev-parse HEAD)"

# The remote moves ahead. Neither clone has fetched, so their refs are stale.
advance_origin "$SANDBOX" c2commit
advance_origin "$SANDBOX" c3commit
TIP_NEW="$(git -C "$SANDBOX/seed" rev-parse HEAD)"

echo "--- precondition: the clones are stale (no fetch yet) ---"
check "feature is at the old tip" "$TIP0" "$(git -C "$C1" rev-parse HEAD)"
check "origin/main is stale (old tip)" "$TIP0" "$(git -C "$C1" rev-parse origin/main)"
echo

echo "--- both steps on: the fetch runs first, so the attach sees the new tip ---"
printf '{"cwd":"%s","session_id":"fa-on-%s"}' "$C1" "$$" | bash "$HOOKS/session-start.sh" >/dev/null 2>&1
check "origin/main was advanced by the fetch step" "$TIP_NEW" "$(git -C "$C1" rev-parse origin/main)"
check "feature fast-forwarded onto the just-fetched tip" "$TIP_NEW" "$(git -C "$C1" rev-parse HEAD)"
echo

echo "--- control: with the fetch disabled, the attach only sees the stale ref ---"
printf '{"cwd":"%s","session_id":"fa-off-%s"}' "$C2" "$$" | GIT_PLUGIN_GIT_FETCH_DISABLED=1 bash "$HOOKS/session-start.sh" >/dev/null 2>&1
check "origin/main stayed stale (no fetch)" "$TIP0" "$(git -C "$C2" rev-parse origin/main)"
check "feature did NOT reach the new tip" "yes" \
      "$([[ "$(git -C "$C2" rev-parse HEAD)" != "$TIP_NEW" ]] && echo yes || echo no)"
echo

report
