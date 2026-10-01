#!/bin/bash
# The worktree-session shape this plugin exists for, under the attach-only model.
#
#   `claude remote-control --spawn worktree` creates its worktree under
#   .claude/worktrees/<name> and cuts worktree-<name> from origin/main. That
#   directory is untracked, so the main checkout goes dirty. The plugin excludes
#   the worktree roots so the checkout does not stay dirty forever, and - reading
#   the refs the `git` plugin already fetched - fast-forwards the session branch.
#
# The repo below also has `.worktrees/` in .gitignore, which is what made the old
# exclude a no-op and hid the original bug.
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

# Other sessions merge their PRs while this worktree sits there; the `git` plugin
# then refreshes the remote-tracking refs (simulated by this fetch).
advance_origin "$SANDBOX" c2
advance_origin "$SANDBOX" c3
TIP="$(git -C "$SANDBOX/seed" rev-parse HEAD)"
git -C "$CLONE" fetch -q origin

echo "--- the session branch is fast-forwarded to the fetched ref ---"
check "precondition: main checkout is dirty (untracked worktree root)" "yes" \
      "$(yesno "$(git -C "$CLONE" status --porcelain)")"
out="$(bash "$HOOKS/git-sync.sh" -C "$W1" 2>&1)"
check "the session branch was aligned" "$TIP" "$(git -C "$W1" rev-parse HEAD)"
check "and the note says fast-forwarded" "yes" \
      "$([[ "$out" == *"fast-forwarded worktree-w1"* ]] && echo yes || echo no)"
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

echo "--- a session branch carrying work is left untouched (ff-only) ---"
git -C "$CLONE" worktree add -q "$CLONE/.claude/worktrees/w2" -b worktree-w2 "origin/main~1"
W2="$CLONE/.claude/worktrees/w2"
git -C "$W2" config user.email test@example.invalid
git -C "$W2" config user.name "test"
echo mine > "$W2/mine"; git -C "$W2" add -A; git -C "$W2" commit -qm "session work"
BEFORE="$(git -C "$W2" rev-parse HEAD)"
out2="$(bash "$HOOKS/git-sync.sh" -C "$W2" 2>&1)"
check "the branch did not move" "$BEFORE" "$(git -C "$W2" rev-parse HEAD)"
check "no merge commit was made" "no" \
      "$(git -C "$W2" rev-parse -q --verify 'HEAD^2' >/dev/null 2>&1 && echo yes || echo no)"
check "the session's own commit survived" "yes" \
      "$(git -C "$W2" merge-base --is-ancestor "$BEFORE" HEAD && echo yes || echo no)"
check "and the note says it cannot be fast-forwarded" "yes" \
      "$([[ "$out2" == *"cannot be fast-forwarded"* ]] && echo yes || echo no)"
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

echo "--- a human branch is fast-forwarded too ---"
git -C "$CLONE" worktree add -q "$CLONE/.claude/worktrees/w4" -b my-feature "origin/main~1"
W4="$CLONE/.claude/worktrees/w4"
out4="$(bash "$HOOKS/git-sync.sh" -C "$W4" 2>&1)"
check "human branch fast-forwarded" "$TIP" "$(git -C "$W4" rev-parse HEAD)"
check "and it said so" "yes" \
      "$([[ "$out4" == *"fast-forwarded my-feature"* ]] && echo yes || echo no)"
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
