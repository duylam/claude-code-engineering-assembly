#!/bin/bash
# The ATTACH step requires the root repo to be attached. On a detached HEAD the
# attach step does nothing at all - no fast-forward of the current ref, no
# warning, and no attached-mode summary injected into the agent's context.
#
# The fetch step's local default-branch leveling is independent of HEAD: `main`
# is not the checked-out branch on a detached HEAD, so it is still fast-forwarded
# to the remote. This test pins both the attach no-op and that leveling.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SANDBOX="$(sandbox detached)"
BASE="${TMPDIR:-/tmp}/claude-git"
trap 'rm -rf "$SANDBOX" "$BASE/det-$$"' EXIT

make_origin "$SANDBOX"
make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"
# Steady state: worktree excludes already in place, so the no-op is truly silent.
preexclude_worktrees "$CLONE"

# The remote is ahead and fetched, so an attached repo would have work to do.
advance_origin "$SANDBOX" c2
git -C "$CLONE" fetch -q origin

# Detach the checkout.
git -C "$CLONE" checkout -q --detach HEAD
BEFORE="$(git -C "$CLONE" rev-parse HEAD)"

echo "--- git-sync does nothing on a detached HEAD ---"
out="$(bash "$HOOKS/git-sync.sh" -C "$CLONE" 2>&1)"; rc=$?
check "HEAD untouched" "$BEFORE" "$(git -C "$CLONE" rev-parse HEAD)"
check "silent (not even a warning)" "" "$out"
check "exit code signals a clean no-op" "10" "$rc"
echo

echo "--- SessionStart injects no summary on a detached HEAD ---"
# The authoritative remote tip, read from the origin seed so the assertion does
# not depend on the clone's remote-tracking ref being fetched at any point.
REMOTE_MAIN="$(git -C "$SANDBOX/seed" rev-parse HEAD)"
out2="$(printf '{"cwd":"%s","session_id":"det-%s"}' "$CLONE" "$$" | bash "$HOOKS/session-start.sh" 2>&1)"; rc2=$?
check "SessionStart exits 0" "0" "$rc2"
check "no attached-mode summary emitted" "no" \
      "$([[ "$out2" == *"attached mode"* ]] && echo yes || echo no)"
# The attach step is a no-op on detached HEAD, but the fetch step's leveling is
# not: local `main` is not checked out, so it is fast-forwarded to the remote.
check "local main leveled to origin/main (fetch step, not attach)" \
      "$REMOTE_MAIN" "$(git -C "$CLONE" rev-parse main)"
echo

report
