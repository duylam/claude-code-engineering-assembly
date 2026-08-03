#!/bin/bash
# branch-name.sh: one name across the superproject and every submodule.
#
# The two properties worth defending are that uncommitted work follows the
# checkout to the new branch (a session names its branch AFTER doing the work,
# not before), and that a name already in use is switched to rather than moved
# on top of - moving it would discard whatever was already there.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# See test-submodule-sync.sh for why this is needed and why it is harmless.
export GIT_ALLOW_PROTOCOL=file

SANDBOX="$(sandbox branchname)"
trap 'rm -rf "$SANDBOX"' EXIT

make_origin "$SANDBOX"
make_sub_origin "$SANDBOX" lib
attach_submodule "$SANDBOX" lib main

make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"
bash "$HOOKS/ensure-submodules.sh" -C "$CLONE" >/dev/null 2>&1

# The shape this exists for: a session on an auto-generated branch, with work
# in it that has not been committed yet.
git -C "$CLONE" checkout -q -b worktree-a3f19c
echo scratch > "$CLONE/uncommitted"

echo "--- one name, everywhere ---"
out="$(bash "$HOOKS/branch-name.sh" -C "$CLONE" add-oauth-login 2>&1)"; status=$?
check "exit is 0" "0" "$status"
check "superproject is on the new name" "add-oauth-login" \
      "$(git -C "$CLONE" symbolic-ref --short HEAD)"
check "the submodule is too"            "add-oauth-login" \
      "$(git -C "$CLONE/lib" symbolic-ref --short HEAD)"
check "uncommitted work came along"     "scratch" "$(cat "$CLONE/uncommitted")"
check "and it named both trees"         "yes" \
      "$([[ "$out" == *"the superproject"* && "$out" == *"in lib"* ]] && echo yes || echo no)"
echo

echo "--- the branch it left is still there, still pointing at the same commit ---"
check "worktree-a3f19c survives" "yes" \
      "$(git -C "$CLONE" show-ref --verify --quiet refs/heads/worktree-a3f19c && echo yes || echo no)"
check "at the same commit" "$(git -C "$CLONE" rev-parse add-oauth-login)" \
      "$(git -C "$CLONE" rev-parse worktree-a3f19c)"
echo

echo "--- running it again is silent ---"
check "no output when already there" "" "$(bash "$HOOKS/branch-name.sh" -C "$CLONE" add-oauth-login 2>&1)"
echo

echo "--- an existing branch is switched to, never moved ---"
git -C "$CLONE" checkout -q -b other
echo committed > "$CLONE/other-work"
git -C "$CLONE" add -A; git -C "$CLONE" commit -qm "work on other"
OTHER="$(git -C "$CLONE" rev-parse HEAD)"
git -C "$CLONE" checkout -q add-oauth-login
bash "$HOOKS/branch-name.sh" -C "$CLONE" other >/dev/null 2>&1
check "switched to it"        "other" "$(git -C "$CLONE" symbolic-ref --short HEAD)"
check "and it did not move"   "$OTHER" "$(git -C "$CLONE" rev-parse other)"
git -C "$CLONE" checkout -q add-oauth-login
echo

echo "--- bad input is refused ---"
bash "$HOOKS/branch-name.sh" -C "$CLONE" 'not a branch' >/dev/null 2>&1; status=$?
check "invalid name: non-zero" "yes" "$([[ "$status" -ne 0 ]] && echo yes || echo no)"
bash "$HOOKS/branch-name.sh" -C "$CLONE" >/dev/null 2>&1; status=$?
check "no name at all: non-zero" "yes" "$([[ "$status" -ne 0 ]] && echo yes || echo no)"
bash "$HOOKS/branch-name.sh" -C "$SANDBOX" some-name >/dev/null 2>&1; status=$?
check "not a git repo: non-zero" "yes" "$([[ "$status" -ne 0 ]] && echo yes || echo no)"
check "nothing was switched by any of that" "add-oauth-login" \
      "$(git -C "$CLONE" symbolic-ref --short HEAD)"
echo

report
