#!/bin/bash
# Regression suite for the failure that motivated 0.5.0.
#
# The shape being defended, reproduced exactly:
#
#   `claude remote-control --spawn worktree` creates its worktree under
#   .claude/worktrees/<name> and cuts worktree-<name> from origin/main WITHOUT
#   firing WorktreeCreate. That directory is untracked, so the main checkout is
#   dirty. Before 0.5.0 the sync bailed on that dirtiness BEFORE fetching, so
#   `git fetch` never ran once, origin/main never advanced, and every session
#   after the first opened on a branch cut from an ever-staler base.
#
# The repo below also has `.worktrees/` in .gitignore, which is what made the
# old exclude a no-op and hid the problem.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SANDBOX="$(sandbox stale)"
trap 'rm -rf "$SANDBOX"' EXIT

make_origin "$SANDBOX"
printf '.worktrees/\n' > "$SANDBOX/seed/.gitignore"
git -C "$SANDBOX/seed" add -A
git -C "$SANDBOX/seed" commit -qm "ignore .worktrees"
git -C "$SANDBOX/seed" push -q origin main

make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"

# The bridge spawns its worktree its own way: Claude Code's directory, cut from
# the remote-tracking ref, no hook involved.
mkdir -p "$CLONE/.claude/worktrees"
git -C "$CLONE" worktree add -q "$CLONE/.claude/worktrees/w1" -b worktree-w1 origin/main
W1="$CLONE/.claude/worktrees/w1"

# Other sessions merge their PRs while this worktree sits there.
advance_origin "$SANDBOX" c2
advance_origin "$SANDBOX" c3
TIP="$(git -C "$SANDBOX/seed" rev-parse HEAD)"

echo "--- the untracked worktree root must not starve the fetch ---"
check "precondition: main checkout is dirty" "yes" \
      "$(yesno "$(git -C "$CLONE" status --porcelain)")"
check "precondition: origin/main is stale" "yes" \
      "$([[ "$(git -C "$CLONE" rev-parse origin/main)" != "$TIP" ]] && echo yes || echo no)"

out="$(bash "$HOOKS/git-sync.sh" -C "$W1" 2>&1)"
check "the fetch ran despite the dirty checkout" "$TIP" "$(git -C "$CLONE" rev-parse origin/main)"
check "the default branch was fast-forwarded"    "$TIP" "$(git -C "$CLONE" rev-parse main)"
check "the session branch was aligned"           "$TIP" "$(git -C "$W1" rev-parse HEAD)"
check "no 'skipping the sync' warning"           "no" \
      "$([[ "$out" == *"skipping the sync"* ]] && echo yes || echo no)"
echo

echo "--- the exclude covers Claude Code's own worktree root ---"
check "main checkout is clean again" "" "$(git -C "$CLONE" status --porcelain)"
check "/.claude/worktrees/ excluded" "1" \
      "$(grep -cxF '/.claude/worktrees/' "$CLONE/.git/info/exclude")"
check "/.worktrees/ left to .gitignore, not duplicated" "0" \
      "$(grep -cxF '/.worktrees/' "$CLONE/.git/info/exclude")"
echo

echo "--- idempotent: nothing to say, nothing to change, on a second run ---"
again="$(bash "$HOOKS/git-sync.sh" -C "$W1" 2>&1)"
check "second run is silent" "" "$again"
check "exclude not appended twice" "1" \
      "$(grep -cxF '/.claude/worktrees/' "$CLONE/.git/info/exclude")"
echo

echo "--- a session branch carrying work gets a merge commit, keeping its work ---"
git -C "$CLONE" worktree add -q "$CLONE/.claude/worktrees/w2" -b worktree-w2 "origin/main~1"
W2="$CLONE/.claude/worktrees/w2"
git -C "$W2" config user.email test@example.invalid
git -C "$W2" config user.name "test"
echo mine > "$W2/mine"; git -C "$W2" add -A; git -C "$W2" commit -qm "session work"
BEFORE="$(git -C "$W2" rev-parse HEAD)"
out2="$(bash "$HOOKS/git-sync.sh" -C "$W2" 2>&1)"
check "the branch moved" "no" \
      "$([[ "$(git -C "$W2" rev-parse HEAD)" == "$BEFORE" ]] && echo yes || echo no)"
check "it is a merge commit" "yes" \
      "$(git -C "$W2" rev-parse -q --verify 'HEAD^2' >/dev/null && echo yes || echo no)"
check "the remote tip is now an ancestor" "yes" \
      "$(git -C "$W2" merge-base --is-ancestor "$TIP" HEAD && echo yes || echo no)"
check "the session's own commit survived" "yes" \
      "$(git -C "$W2" merge-base --is-ancestor "$BEFORE" HEAD && echo yes || echo no)"
check "and the note says merged" "yes" \
      "$([[ "$out2" == *"merged origin/main"* ]] && echo yes || echo no)"
echo

echo "--- a dirty session worktree is reported, never moved ---"
git -C "$CLONE" worktree add -q "$CLONE/.claude/worktrees/w3" -b worktree-w3 "origin/main~1"
W3="$CLONE/.claude/worktrees/w3"
echo scratch > "$W3/uncommitted"
BEFORE="$(git -C "$W3" rev-parse HEAD)"
out3="$(bash "$HOOKS/git-sync.sh" -C "$W3" 2>&1)"
check "dirty worktree untouched" "$BEFORE" "$(git -C "$W3" rev-parse HEAD)"
check "and the warning says why" "yes" \
      "$([[ "$out3" == *"uncommitted changes"* ]] && echo yes || echo no)"
echo

echo "--- a branch outside the session namespace is synced too, now ---"
git -C "$CLONE" worktree add -q "$CLONE/.claude/worktrees/w4" -b my-feature "origin/main~1"
W4="$CLONE/.claude/worktrees/w4"
out4="$(bash "$HOOKS/git-sync.sh" -C "$W4" 2>&1)"
check "human branch fast-forwarded" "$TIP" "$(git -C "$W4" rev-parse HEAD)"
check "and it said so"              "yes" \
      "$([[ "$out4" == *"fast-forwarded my-feature"* ]] && echo yes || echo no)"
echo

echo "--- the main checkout is synced too, on whatever branch it is on ---"
git -C "$CLONE" checkout -q -b main-side "origin/main~1"
bash "$HOOKS/git-sync.sh" -C "$CLONE" >/dev/null 2>&1
check "main checkout fast-forwarded" "$TIP" "$(git -C "$CLONE" rev-parse HEAD)"
git -C "$CLONE" checkout -q main
echo

echo "--- a detached HEAD has no branch to sync ---"
git -C "$CLONE" worktree add -q --detach "$CLONE/.claude/worktrees/w5" "origin/main~1"
W5="$CLONE/.claude/worktrees/w5"
BEFORE="$(git -C "$W5" rev-parse HEAD)"
out5="$(bash "$HOOKS/git-sync.sh" -C "$W5" 2>&1)"
check "detached HEAD untouched" "$BEFORE" "$(git -C "$W5" rev-parse HEAD)"
check "and the warning says why" "yes" \
      "$([[ "$out5" == *"detached HEAD"* ]] && echo yes || echo no)"
echo

echo "--- rule zero still holds ---"
git init -q "$SANDBOX/noremote" -b main
git -C "$SANDBOX/noremote" config user.email test@example.invalid
git -C "$SANDBOX/noremote" config user.name "test"
echo x > "$SANDBOX/noremote/f"
git -C "$SANDBOX/noremote" add -A
git -C "$SANDBOX/noremote" commit -qm x
check "repo with no remote: silent" "" "$(bash "$HOOKS/git-sync.sh" -C "$SANDBOX/noremote" 2>&1)"
check "not a git repo: silent"      "" "$(bash "$HOOKS/git-sync.sh" -C "$SANDBOX" 2>&1)"
echo

report
