#!/bin/bash
# reap_remote_session_branch - the plugin's one remote-touching operation, and
# the teardown that now drives it. A remote-control session pushes worktree-*
# branches to origin (superproject and submodules) that no local cleanup used to
# reach; this reaps them, and only them.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# The shared helper under test, exercised directly.
source "$HOOKS/lib/git-common.sh"

SANDBOX="$(sandbox reap)"
trap 'rm -rf "$SANDBOX"' EXIT

make_origin "$SANDBOX"
make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"

origin_has() { # origin_has <branch>
    git -C "$CLONE" ls-remote --exit-code --heads origin "$1" >/dev/null 2>&1 && echo yes || echo no
}

echo "--- a pushed worktree-* branch is deleted on origin ---"
git -C "$CLONE" branch -q worktree-x origin/main
git -C "$CLONE" push -q origin worktree-x
check "precondition: origin has worktree-x" "yes" "$(origin_has worktree-x)"
NOTES=(); WARNINGS=()
reap_remote_session_branch "$CLONE" "worktree-x"
check "origin no longer has worktree-x" "no" "$(origin_has worktree-x)"
check "a note names the deletion" "yes" \
      "$([[ "${NOTES[*]}" == *"deleted remote branch worktree-x"* ]] && echo yes || echo no)"
check "no warnings" "0" "${#WARNINGS[@]}"
echo

echo "--- a branch outside the worktree-* namespace is never reaped ---"
git -C "$CLONE" branch -q my-feature origin/main
git -C "$CLONE" push -q origin my-feature
NOTES=(); WARNINGS=()
reap_remote_session_branch "$CLONE" "my-feature"
check "origin still has my-feature" "yes" "$(origin_has my-feature)"
check "and nothing was reported" "0" "$(( ${#NOTES[@]} + ${#WARNINGS[@]} ))"
echo

echo "--- reaping a branch the remote does not have is a silent no-op ---"
NOTES=(); WARNINGS=()
reap_remote_session_branch "$CLONE" "worktree-absent"
check "no notes"    "0" "${#NOTES[@]}"
check "no warnings" "0" "${#WARNINGS[@]}"
echo

echo "--- double reap is idempotent ---"
git -C "$CLONE" branch -q worktree-y origin/main
git -C "$CLONE" push -q origin worktree-y
NOTES=(); WARNINGS=()
reap_remote_session_branch "$CLONE" "worktree-y"   # deletes it
NOTES=(); WARNINGS=()
reap_remote_session_branch "$CLONE" "worktree-y"   # nothing left
check "second reap deletes nothing new" "0" "${#NOTES[@]}"
check "and warns about nothing"         "0" "${#WARNINGS[@]}"
echo

echo "--- teardown reaps the remote branch it removes locally ---"
WT="$(printf '{"cwd":"%s","name":"gamma"}' "$CLONE" | bash "$HOOKS/on-worktree-create.sh" 2>/dev/null)"
git -C "$WT" push -q origin worktree-gamma
check "precondition: origin has worktree-gamma" "yes" "$(origin_has worktree-gamma)"
bash "$HOOKS/worktree-cleanup.sh" -C "$WT" >/dev/null 2>&1
check "worktree removed locally"                "no"  "$([[ -d "$WT" ]] && echo yes || echo no)"
check "local worktree-gamma branch removed"     "no" \
      "$(git -C "$CLONE" show-ref --verify --quiet refs/heads/worktree-gamma && echo yes || echo no)"
check "and origin's worktree-gamma is reaped"   "no"  "$(origin_has worktree-gamma)"
echo

echo "--- dry-run teardown reports the remote reap but deletes nothing ---"
git -C "$CLONE" branch -q worktree-delta origin/main
git -C "$CLONE" push -q origin worktree-delta
WT2="$(printf '{"cwd":"%s","name":"delta"}' "$CLONE" | bash "$HOOKS/on-worktree-create.sh" 2>/dev/null)"
plan="$(bash "$HOOKS/worktree-cleanup.sh" -n -C "$WT2" 2>&1)"
check "dry-run kept the remote branch" "yes" "$(origin_has worktree-delta)"
check "and said it would delete it"    "yes" \
      "$([[ "$plan" == *"would delete remote branch worktree-delta"* ]] && echo yes || echo no)"
bash "$HOOKS/worktree-cleanup.sh" -C "$WT2" >/dev/null 2>&1   # clean up for real
echo

echo "--- submodules: reaped where present, skipped where absent ---"
make_sub_origin "$SANDBOX" sub
attach_submodule "$SANDBOX" sub
git -C "$CLONE" -c protocol.file.allow=always pull -q >/dev/null 2>&1
git -C "$CLONE" -c protocol.file.allow=always submodule update --init -q >/dev/null 2>&1
SUB="$CLONE/sub"
sub_origin_has() { # sub_origin_has <branch>
    git -C "$SUB" ls-remote --exit-code --heads origin "$1" >/dev/null 2>&1 && echo yes || echo no
}
git -C "$SUB" branch -q worktree-z
git -C "$SUB" push -q origin worktree-z
check "precondition: submodule origin has worktree-z" "yes" "$(sub_origin_has worktree-z)"
check "precondition: superproject origin lacks it"    "no"  "$(origin_has worktree-z)"
NOTES=(); WARNINGS=()
reap_remote_session_branch "$CLONE" "worktree-z"
check "submodule origin no longer has worktree-z" "no" "$(sub_origin_has worktree-z)"
check "a note names the submodule deletion" "yes" \
      "$([[ "${NOTES[*]}" == *"submodule sub"* ]] && echo yes || echo no)"
check "the superproject (lacking it) produced no warning" "0" "${#WARNINGS[@]}"
echo

report
