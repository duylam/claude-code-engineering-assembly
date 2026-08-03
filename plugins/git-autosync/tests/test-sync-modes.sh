#!/bin/bash
# The two sync modes on the superproject, and the line between them.
#
# merge must never lose a commit; reset must never lose a commit WITHOUT saying
# so first, which in practice means refusing outright the moment any tree is
# dirty. The refusal has to be total: a reset that moved the superproject and
# then noticed a dirty submodule would be the worst of both.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SANDBOX="$(sandbox modes)"
trap 'rm -rf "$SANDBOX"' EXIT

make_origin "$SANDBOX"
make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"

advance_origin "$SANDBOX" c2
advance_origin "$SANDBOX" c3
TIP="$(git -C "$SANDBOX/seed" rev-parse HEAD)"

# Every branch below is cut from `origin/main~2`, so the clone has to know
# about those commits first. Without this the checkouts fail, HEAD stays on
# main, and the assertions below quietly measure the wrong branch.
git -C "$CLONE" fetch -q origin

echo "--- merge mode is the default, and fast-forwards a branch with no work ---"
git -C "$CLONE" checkout -q -b feature "origin/main~2"
out="$(bash "$HOOKS/git-sync.sh" -C "$CLONE" 2>&1)"
check "feature is level with the remote" "$TIP" "$(git -C "$CLONE" rev-parse HEAD)"
check "and it said fast-forwarded" "yes" \
      "$([[ "$out" == *"fast-forwarded feature"* ]] && echo yes || echo no)"
echo

echo "--- merge mode makes a merge commit on a diverged branch ---"
git -C "$CLONE" checkout -q -b diverged "origin/main~2"
echo mine > "$CLONE/mine"; git -C "$CLONE" add -A; git -C "$CLONE" commit -qm "local work"
OWN="$(git -C "$CLONE" rev-parse HEAD)"
bash "$HOOKS/git-sync.sh" -C "$CLONE" >/dev/null 2>&1
check "it is a merge commit" "yes" \
      "$(git -C "$CLONE" rev-parse -q --verify 'HEAD^2' >/dev/null && echo yes || echo no)"
check "the local commit survived" "yes" \
      "$(git -C "$CLONE" merge-base --is-ancestor "$OWN" HEAD && echo yes || echo no)"
check "the remote tip is in"      "yes" \
      "$(git -C "$CLONE" merge-base --is-ancestor "$TIP" HEAD && echo yes || echo no)"
echo

echo "--- merge mode rolls a conflicting merge back instead of leaving it ---"
git -C "$CLONE" checkout -q -b conflicting "origin/main~2"
# `f` is the file every advance_origin commit rewrites, so touching it here is
# guaranteed to collide with what the remote did to it.
echo "mine, conflicting" > "$CLONE/f"
git -C "$CLONE" commit -qam "conflicting work"
BEFORE="$(git -C "$CLONE" rev-parse HEAD)"
out="$(bash "$HOOKS/git-sync.sh" -C "$CLONE" 2>&1)"
status=$?
check "exit is still 0" "0" "$status"
check "HEAD is back where it was" "$BEFORE" "$(git -C "$CLONE" rev-parse HEAD)"
check "no merge left in progress"  "no" \
      "$([[ -f "$CLONE/.git/MERGE_HEAD" ]] && echo yes || echo no)"
check "the tree is not conflicted" "" "$(git -C "$CLONE" status --porcelain)"
check "and the warning says rolled back" "yes" \
      "$([[ "$out" == *"rolled back"* ]] && echo yes || echo no)"
echo

echo "--- reset mode discards local commits on a clean tree ---"
git -C "$CLONE" checkout -q -b resettable "origin/main~2"
echo throwaway > "$CLONE/throwaway"; git -C "$CLONE" add -A
git -C "$CLONE" commit -qm "work that reset is meant to discard"
GONE="$(git -C "$CLONE" rev-parse HEAD)"
out="$(bash "$HOOKS/git-sync.sh" --mode reset -C "$CLONE" 2>&1)"
check "landed exactly on the remote" "$TIP" "$(git -C "$CLONE" rev-parse HEAD)"
check "the discarded file is gone"   "no" \
      "$([[ -f "$CLONE/throwaway" ]] && echo yes || echo no)"
check "the discarded commit is still in the reflog" "yes" \
      "$([[ "$(git -C "$CLONE" reflog --format=%H)" == *"$GONE"* ]] && echo yes || echo no)"
check "and the note names the old tip" "yes" \
      "$([[ "$out" == *"${GONE:0:7}"* ]] && echo yes || echo no)"
echo

echo "--- reset mode refuses a dirty tree, and changes nothing ---"
git -C "$CLONE" checkout -q -b dirty "origin/main~2"
echo uncommitted > "$CLONE/scratch"
BEFORE="$(git -C "$CLONE" rev-parse HEAD)"
out="$(bash "$HOOKS/git-sync.sh" --mode reset -C "$CLONE" 2>&1)"; status=$?
check "exit is non-zero" "yes" "$([[ "$status" -ne 0 ]] && echo yes || echo no)"
check "HEAD unmoved"     "$BEFORE" "$(git -C "$CLONE" rev-parse HEAD)"
check "the file is untouched" "uncommitted" "$(cat "$CLONE/scratch")"
check "and the warning says refusing" "yes" \
      "$([[ "$out" == *"refusing to reset"* ]] && echo yes || echo no)"
rm -f "$CLONE/scratch"
echo

echo "--- an unknown mode is rejected, not silently ignored ---"
bash "$HOOKS/git-sync.sh" --mode wipe -C "$CLONE" >/dev/null 2>&1; status=$?
check "exit is non-zero" "yes" "$([[ "$status" -ne 0 ]] && echo yes || echo no)"
echo

echo "--- hooks get merge mode, and never fail ---"
echo uncommitted > "$CLONE/scratch"
out="$(printf '{"cwd":"%s"}' "$CLONE" | bash "$HOOKS/session-start.sh" 2>&1)"; status=$?
check "SessionStart exits 0 on a dirty repo" "0" "$status"
rm -f "$CLONE/scratch"
echo

report
