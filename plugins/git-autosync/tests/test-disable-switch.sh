#!/bin/bash
# GIT_AUTOSYNC_DISABLE - the one global off switch. Every hook becomes a no-op,
# except WorktreeCreate, which must still yield a worktree (its stdout IS the
# worktree) and only skips the sync.
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
BASE="$(git -C "$CLONE" rev-parse main)"   # the clone's stale local main

echo "--- SessionStart sync is inert when disabled ---"
out="$(printf '{"cwd":"%s"}' "$CLONE" | GIT_AUTOSYNC_DISABLE=1 bash "$HOOKS/session-start.sh" 2>&1)"
check "session-start prints nothing" "" "$out"
check "no fetch ran (origin/main untouched)" "yes" \
      "$([[ "$(git -C "$CLONE" rev-parse origin/main)" != "$TIP" ]] && echo yes || echo no)"
echo

echo "--- WorktreeCreate still yields a worktree, but skips the sync ---"
WT="$(printf '{"cwd":"%s","name":"d1"}' "$CLONE" | GIT_AUTOSYNC_DISABLE=1 bash "$HOOKS/on-worktree-create.sh" 2>/dev/null)"
check "worktree is still created" "$CLONE/.worktrees/d1" "$WT"
check "cut from the un-synced local main, not the remote tip" "$BASE" "$(git -C "$WT" rev-parse HEAD)"
check "and that base is behind origin" "yes" "$([[ "$BASE" != "$TIP" ]] && echo yes || echo no)"
excl="$CLONE/.git/info/exclude"
count=0; [[ -f "$excl" ]] && count="$(grep -cE '^/(\.worktrees|\.claude/worktrees)/$' "$excl")"
check "no exclude bookkeeping when disabled" "0" "$count"
echo

echo "--- WorktreeRemove teardown is inert when disabled ---"
rm_out="$(printf '{"reason":"session_end","worktree_path":"%s"}' "$WT" \
    | GIT_AUTOSYNC_DISABLE=1 bash "$HOOKS/on-worktree-remove.sh" 2>&1)"
check "worktree-remove prints nothing" "" "$rm_out"
check "worktree still on disk (teardown skipped)" "yes" "$([[ -d "$WT" ]] && echo yes || echo no)"
echo

echo "--- GIT_AUTOSYNC_DISABLE=0 is treated as enabled ---"
out0="$(printf '{"cwd":"%s"}' "$CLONE" | GIT_AUTOSYNC_DISABLE=0 bash "$HOOKS/session-start.sh" 2>&1)"
check "an explicit 0 does not disable (the fetch ran)" "$TIP" "$(git -C "$CLONE" rev-parse origin/main)"
echo

report
