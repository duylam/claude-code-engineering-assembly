#!/bin/bash
# Attach-only sync on the superproject. Network-free and fast-forward only:
# a clean branch that is behind fast-forwards, a diverged branch is left exactly
# as it is ("ignore if it can't"), and the hook never fetches.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SANDBOX="$(sandbox merge)"
trap 'rm -rf "$SANDBOX"' EXIT

make_origin "$SANDBOX"
make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"
# Steady state: the worktree excludes are already in place, so the sync's
# one-time housekeeping note does not intrude on the "silent" assertions below.
preexclude_worktrees "$CLONE"

advance_origin "$SANDBOX" c2
advance_origin "$SANDBOX" c3
TIP="$(git -C "$SANDBOX/seed" rev-parse HEAD)"

echo "--- the hook never fetches: it reads only local remote-tracking refs ---"
STALE="$(git -C "$CLONE" rev-parse origin/main)"   # still c1; remote is at c3
out="$(bash "$HOOKS/git-sync.sh" -C "$CLONE" 2>&1)"
check "origin/main was not advanced (no fetch)" "$STALE" "$(git -C "$CLONE" rev-parse origin/main)"
check "HEAD unchanged (already level with the local ref)" "$STALE" "$(git -C "$CLONE" rev-parse HEAD)"
check "and it stayed silent" "" "$out"
echo

# From here on, simulate the git plugin having fetched.
git -C "$CLONE" fetch -q origin

echo "--- fast-forwards a clean branch that is behind ---"
git -C "$CLONE" checkout -q -b feature "origin/main~2"
out="$(bash "$HOOKS/git-sync.sh" -C "$CLONE" 2>&1)"
check "feature is level with the remote-tracking ref" "$TIP" "$(git -C "$CLONE" rev-parse HEAD)"
check "and it said fast-forwarded" "yes" \
      "$([[ "$out" == *"fast-forwarded feature"* ]] && echo yes || echo no)"
echo

echo "--- leaves a diverged branch untouched, keeping its work ---"
git -C "$CLONE" checkout -q -b diverged "origin/main~2"
echo mine > "$CLONE/mine"; git -C "$CLONE" add -A; git -C "$CLONE" commit -qm "local work"
OWN="$(git -C "$CLONE" rev-parse HEAD)"
out="$(bash "$HOOKS/git-sync.sh" -C "$CLONE" 2>&1)"; status=$?
check "exit is success" "0" "$status"
check "HEAD did not move" "$OWN" "$(git -C "$CLONE" rev-parse HEAD)"
check "no merge commit was made" "no" \
      "$(git -C "$CLONE" rev-parse -q --verify 'HEAD^2' >/dev/null 2>&1 && echo yes || echo no)"
check "the remote tip was NOT forced in" "no" \
      "$(git -C "$CLONE" merge-base --is-ancestor "$TIP" HEAD 2>/dev/null && echo yes || echo no)"
check "and the note says it cannot be fast-forwarded" "yes" \
      "$([[ "$out" == *"cannot be fast-forwarded"* ]] && echo yes || echo no)"
echo

echo "--- a dirty tree behind the remote is reported, never moved ---"
git -C "$CLONE" checkout -q -b dirtyb "origin/main~2"
BEFORE="$(git -C "$CLONE" rev-parse HEAD)"
echo scratch > "$CLONE/scratch"
out="$(bash "$HOOKS/git-sync.sh" -C "$CLONE" 2>&1)"; status=$?
check "exit is success" "0" "$status"
check "dirty branch untouched" "$BEFORE" "$(git -C "$CLONE" rev-parse HEAD)"
check "and the warning says why" "yes" \
      "$([[ "$out" == *"uncommitted changes"* ]] && echo yes || echo no)"
rm -f "$CLONE/scratch"
echo

echo "--- the SessionStart hook never fails, even on a dirty repo ---"
echo uncommitted > "$CLONE/scratch"
out="$(printf '{"cwd":"%s"}' "$CLONE" | bash "$HOOKS/session-start.sh" 2>&1)"; status=$?
check "SessionStart exits 0 on a dirty repo" "0" "$status"
rm -f "$CLONE/scratch"
echo

report
