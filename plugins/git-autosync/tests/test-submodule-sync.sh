#!/bin/bash
# Submodules are synced against the superproject's gitlink, not their own remote tip.
# Reset's preflight covers them before anything moves.
#
# The ordering assertion is the important one. A reset that rewound the
# superproject and only then noticed a dirty submodule would leave a repository
# nobody can put back with one command.
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

echo "--- merge mode: populate, attach, and contain the superproject gitlink ---"
out="$(bash "$HOOKS/ensure-submodules.sh" -C "$CLONE" 2>&1)"
check "tracked is populated" "yes" "$([[ -e "$CLONE/tracked/.git" ]] && echo yes || echo no)"
check "tracked is on a branch, not detached" "main" \
      "$(git -C "$CLONE/tracked" symbolic-ref --short -q HEAD)"
# In merge mode the submodule must CONTAIN the gitlink commit (it may sit ahead of it).
check "tracked contains the superproject gitlink" "yes" \
      "$(git -C "$CLONE/tracked" merge-base --is-ancestor "$TRACKED_GITLINK" HEAD && echo yes || echo no)"
check "vendored contains the superproject gitlink" "yes" \
      "$(git -C "$CLONE/vendored" merge-base --is-ancestor "$VENDORED_GITLINK" HEAD && echo yes || echo no)"
check "and it reported the work" "yes" \
      "$([[ "$out" == *"initialized tracked"* ]] && echo yes || echo no)"
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

echo "--- reset mode refuses over a dirty submodule, before anything moves ---"
advance_origin "$SANDBOX" c2
SUPER_TIP="$(git -C "$SANDBOX/seed" rev-parse HEAD)"
SUPER_BEFORE="$(git -C "$CLONE" rev-parse HEAD)"
TRACKED_BEFORE="$(git -C "$CLONE/tracked" rev-parse HEAD)"
echo uncommitted > "$CLONE/tracked/scratch"

out="$(bash "$HOOKS/git-sync.sh" --mode reset -C "$CLONE" 2>&1)"; status=$?
check "exit is non-zero"              "yes"             "$([[ "$status" -ne 0 ]] && echo yes || echo no)"
check "the superproject did NOT move" "$SUPER_BEFORE"   "$(git -C "$CLONE" rev-parse HEAD)"
check "the submodule did NOT move"    "$TRACKED_BEFORE" "$(git -C "$CLONE/tracked" rev-parse HEAD)"
check "the uncommitted file survived" "uncommitted"     "$(cat "$CLONE/tracked/scratch")"
check "and the warning names the submodule" "yes" \
      "$([[ "$out" == *"submodule tracked has uncommitted changes"* ]] && echo yes || echo no)"
echo

echo "--- reset mode discards commits ahead of the gitlink ---"
rm -f "$CLONE/tracked/scratch"
# Add a committed-but-not-gitlinked local change to the submodule (ahead of NEW_TRACKED_GITLINK).
echo local > "$CLONE/tracked/local-file"
git -C "$CLONE/tracked" add -A
git -C "$CLONE/tracked" commit -qm "local work in submodule"
# Reset: submodule should land exactly on the gitlink, losing the local commit.
# SUPER_TIP has no new gitlink for tracked, so its gitlink is still NEW_TRACKED_GITLINK.
bash "$HOOKS/git-sync.sh" --mode reset -C "$CLONE" >/dev/null 2>&1; status=$?
check "exit is 0"                                    "0"                    "$status"
check "superproject landed on its remote"            "$SUPER_TIP"           "$(git -C "$CLONE" rev-parse HEAD)"
check "submodule reset to gitlink, not local commit" "$NEW_TRACKED_GITLINK" \
      "$(git -C "$CLONE/tracked" rev-parse HEAD)"
echo

report
