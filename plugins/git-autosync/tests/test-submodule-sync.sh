#!/bin/bash
# Submodules are synced against the superproject's gitlink, not their own remote
# tip: a submodule fast-forwards only when the superproject records a new gitlink
# for it, and a submodule already at or ahead of the gitlink is left alone.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# Since git 2.38 a submodule may not be cloned over file://, and the repo-level
# `protocol.file.allow` is deliberately ignored for exactly that case. Only the
# environment gets through - which is what is wanted here anyway, because the
# permission has to reach the plugin's own `git submodule update`, not just the
# commands this test runs directly. Real remotes are not file://, so nothing in
# the plugin depends on this.
export GIT_ALLOW_PROTOCOL=file

SANDBOX="$(sandbox submodules)"
trap 'rm -rf "$SANDBOX"' EXIT

make_origin "$SANDBOX"
make_sub_origin "$SANDBOX" tracked   # .gitmodules will declare `branch = main`
make_sub_origin "$SANDBOX" vendored  # no branch key

# A nested submodule inside `tracked`, to prove the sync stays ONE level deep:
# after populate, tracked/nested must remain empty (never initialized).
git -C "$SANDBOX/tracked-seed" -c protocol.file.allow=always \
    submodule add -q "$SANDBOX/vendored.git" nested 2>/dev/null
git -C "$SANDBOX/tracked-seed" commit -qm "add nested submodule"
git -C "$SANDBOX/tracked-seed" push -q origin main

attach_submodule "$SANDBOX" tracked main
attach_submodule "$SANDBOX" vendored

make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"

# The gitlinks the superproject records right after the clone.
TRACKED_GITLINK="$(git -C "$SANDBOX/seed" rev-parse "HEAD:tracked")"
VENDORED_GITLINK="$(git -C "$SANDBOX/seed" rev-parse "HEAD:vendored")"

# Advance the submodule remotes. The superproject does NOT record new gitlinks yet.
advance_sub_origin "$SANDBOX" tracked s2
advance_sub_origin "$SANDBOX" vendored v2

echo "--- populate, attach, and contain the superproject gitlink ---"
out="$(bash "$HOOKS/ensure-submodules.sh" -C "$CLONE" 2>&1)"
check "tracked is populated" "yes" "$([[ -e "$CLONE/tracked/.git" ]] && echo yes || echo no)"
check "tracked is on a branch, not detached" "main" \
      "$(git -C "$CLONE/tracked" symbolic-ref --short -q HEAD)"
# The submodule must CONTAIN the gitlink commit (it may sit ahead of it).
check "tracked contains the superproject gitlink" "yes" \
      "$(git -C "$CLONE/tracked" merge-base --is-ancestor "$TRACKED_GITLINK" HEAD && echo yes || echo no)"
check "vendored contains the superproject gitlink" "yes" \
      "$(git -C "$CLONE/vendored" merge-base --is-ancestor "$VENDORED_GITLINK" HEAD && echo yes || echo no)"
check "and it reported the work" "yes" \
      "$([[ "$out" == *"initialized tracked"* ]] && echo yes || echo no)"
check "nested submodule left empty (one level only)" "no" \
      "$([[ -e "$CLONE/tracked/nested/.git" ]] && echo yes || echo no)"
echo

echo "--- advancing the remote without changing the gitlink does not move the submodule ---"
TRACKED_AFTER_FIRST="$(git -C "$CLONE/tracked" rev-parse HEAD)"
VENDORED_AFTER_FIRST="$(git -C "$CLONE/vendored" rev-parse HEAD)"
# Remote advances to s3, but the superproject gitlink stays at s1.
advance_sub_origin "$SANDBOX" tracked s3
check "second run is silent" "" "$(bash "$HOOKS/ensure-submodules.sh" -C "$CLONE" 2>&1)"
check "tracked did not follow the remote past the gitlink" "$TRACKED_AFTER_FIRST" \
      "$(git -C "$CLONE/tracked" rev-parse HEAD)"
echo

echo "--- when the superproject gitlink advances, the submodule fast-forwards ---"
# Record the s3 gitlink in the superproject (s3 is already at remote tip) and push.
git -C "$SANDBOX/seed" -c protocol.file.allow=always submodule update --remote tracked 2>/dev/null
git -C "$SANDBOX/seed" add tracked
git -C "$SANDBOX/seed" commit -qm "advance tracked gitlink to s3"
git -C "$SANDBOX/seed" push -q origin main
NEW_TRACKED_GITLINK="$(git -C "$SANDBOX/seed" rev-parse "HEAD:tracked")"
# Bring the clone's superproject to the new commit (new gitlink now in HEAD).
git -C "$CLONE" fetch -q origin
git -C "$CLONE" merge --ff-only -q origin/main
out="$(bash "$HOOKS/ensure-submodules.sh" -C "$CLONE" 2>&1)"
check "tracked moved to the new superproject gitlink" "$NEW_TRACKED_GITLINK" \
      "$(git -C "$CLONE/tracked" rev-parse HEAD)"
check "and it said fast-forwarded" "yes" \
      "$([[ "$out" == *"fast-forwarded tracked"* ]] && echo yes || echo no)"
check "vendored was left alone" "$VENDORED_AFTER_FIRST" \
      "$(git -C "$CLONE/vendored" rev-parse HEAD)"
echo

report
