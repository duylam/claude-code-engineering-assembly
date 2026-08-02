#!/bin/bash
# The WorktreeCreate -> session -> teardown path, end to end.
#
# Guards the refactor that moved the worktree root and the branch prefix out of
# on-worktree-create.sh and worktree-cleanup.sh into git-common.sh: if those two
# ever disagree again, cleanup silently stops recognising what creation makes.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SANDBOX="${TMPDIR:-/tmp}/git-autosync-test-lifecycle.$$"
trap 'rm -rf "$SANDBOX"' EXIT
rm -rf "$SANDBOX"; mkdir -p "$SANDBOX"

make_origin "$SANDBOX"
make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"

# The remote moves ahead of the clone, as it does between sessions.
advance_origin "$SANDBOX" c2
TIP="$(git -C "$SANDBOX/seed" rev-parse HEAD)"

echo "--- WorktreeCreate ---"
WT="$(printf '{"cwd":"%s","name":"alpha"}' "$CLONE" | bash "$HOOKS/on-worktree-create.sh" 2>/dev/null)"
check "stdout is the worktree path, and nothing else" "$CLONE/.worktrees/alpha" "$WT"
check "branch is worktree-<name>" "worktree-alpha" "$(git -C "$WT" symbolic-ref --short HEAD)"
check "cut from the freshly synced default branch" "$TIP" "$(git -C "$WT" rev-parse HEAD)"
check "worktree is locked" "yes" \
      "$(yesno "$(git -C "$CLONE" worktree list --porcelain | grep '^locked')")"
check "main checkout stays clean" "" "$(git -C "$CLONE" status --porcelain)"
check "both worktree roots are excluded" "2" \
      "$(grep -cE '^/(\.worktrees|\.claude/worktrees)/$' "$CLONE/.git/info/exclude")"
echo

echo "--- a reopened worktree keeps its work ---"
git -C "$WT" config user.email test@example.invalid
git -C "$WT" config user.name "test"
echo work > "$WT/mine"; git -C "$WT" add -A; git -C "$WT" commit -qm "session work"
KEEP="$(git -C "$WT" rev-parse HEAD)"
advance_origin "$SANDBOX" c3
out="$(bash "$HOOKS/git-sync.sh" -C "$WT" 2>&1)"
check "committed session work is never rebased away" "$KEEP" "$(git -C "$WT" rev-parse HEAD)"
check "and the sync says why" "yes" \
      "$([[ "$out" == *"commit(s) of its own"* ]] && echo yes || echo no)"
echo

echo "--- teardown, dry run ---"
bash "$HOOKS/worktree-cleanup.sh" -n -C "$WT" >/dev/null 2>&1
check "worktree still on disk" "yes" "$([[ -d "$WT" ]] && echo yes || echo no)"
check "branch still present"   "yes" \
      "$(git -C "$CLONE" show-ref --verify --quiet refs/heads/worktree-alpha && echo yes || echo no)"
echo

echo "--- teardown, for real ---"
bash "$HOOKS/worktree-cleanup.sh" -C "$WT" >/dev/null 2>&1
check "worktree directory removed" "no" "$([[ -d "$WT" ]] && echo yes || echo no)"
check "worktree-alpha branch removed" "no" \
      "$(git -C "$CLONE" show-ref --verify --quiet refs/heads/worktree-alpha && echo yes || echo no)"
check "main checkout still clean" "" "$(git -C "$CLONE" status --porcelain)"
echo

echo "--- worktrees still work in a repo with no remote ---"
git init -q "$SANDBOX/local" -b main
git -C "$SANDBOX/local" config user.email test@example.invalid
git -C "$SANDBOX/local" config user.name "test"
echo x > "$SANDBOX/local/f"
git -C "$SANDBOX/local" add -A
git -C "$SANDBOX/local" commit -qm x
WT2="$(printf '{"cwd":"%s","name":"beta"}' "$SANDBOX/local" | bash "$HOOKS/on-worktree-create.sh" 2>/dev/null)"
check "worktree created without a remote" "$SANDBOX/local/.worktrees/beta" "$WT2"
check "exclude written without a remote" "2" \
      "$(grep -cE '^/(\.worktrees|\.claude/worktrees)/$' "$SANDBOX/local/.git/info/exclude")"
echo

report
