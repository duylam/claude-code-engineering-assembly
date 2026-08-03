#!/bin/bash
# Submodules are synced against their OWN remote, not the superproject's
# gitlink - and reset's preflight covers them before anything moves.
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
make_sub_origin "$SANDBOX" vendored  # no branch key: falls back to its own main
attach_submodule "$SANDBOX" tracked main
attach_submodule "$SANDBOX" vendored

make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"

# Both submodule remotes move on, as another team's merges would leave them.
advance_sub_origin "$SANDBOX" tracked s2
advance_sub_origin "$SANDBOX" vendored v2
TRACKED_TIP="$(git -C "$SANDBOX/tracked-seed" rev-parse HEAD)"
VENDORED_TIP="$(git -C "$SANDBOX/vendored-seed" rev-parse HEAD)"

echo "--- merge mode: populate, attach, then advance to the submodule's remote ---"
out="$(bash "$HOOKS/ensure-submodules.sh" -C "$CLONE" 2>&1)"
check "tracked is populated" "yes" "$([[ -e "$CLONE/tracked/.git" ]] && echo yes || echo no)"
check "tracked is on a branch, not detached" "main" \
      "$(git -C "$CLONE/tracked" symbolic-ref --short -q HEAD)"
check "tracked advanced to its own remote tip" "$TRACKED_TIP" \
      "$(git -C "$CLONE/tracked" rev-parse HEAD)"
check "vendored fell back to its own default branch" "$VENDORED_TIP" \
      "$(git -C "$CLONE/vendored" rev-parse HEAD)"
check "and it reported the work" "yes" \
      "$([[ "$out" == *"initialized tracked"* ]] && echo yes || echo no)"
echo

echo "--- a submodule ahead of the gitlink does not count as a dirty superproject ---"
check "superproject is clean by the plugin's measure" "" \
      "$(git -C "$CLONE" status --porcelain --ignore-submodules=all)"
check "second run is silent" "" "$(bash "$HOOKS/ensure-submodules.sh" -C "$CLONE" 2>&1)"
echo

echo "--- an already-attached submodule fast-forwards on the next run ---"
advance_sub_origin "$SANDBOX" tracked s3
TRACKED_TIP="$(git -C "$SANDBOX/tracked-seed" rev-parse HEAD)"
out="$(bash "$HOOKS/ensure-submodules.sh" -C "$CLONE" 2>&1)"
check "tracked followed its remote" "$TRACKED_TIP" "$(git -C "$CLONE/tracked" rev-parse HEAD)"
check "and it said fast-forwarded"  "yes" \
      "$([[ "$out" == *"fast-forwarded tracked"* ]] && echo yes || echo no)"
check "vendored was left alone"     "$VENDORED_TIP" \
      "$(git -C "$CLONE/vendored" rev-parse HEAD)"
echo

echo "--- reset mode refuses over a dirty submodule, before anything moves ---"
advance_origin "$SANDBOX" c2
SUPER_TIP="$(git -C "$SANDBOX/seed" rev-parse HEAD)"
SUPER_BEFORE="$(git -C "$CLONE" rev-parse HEAD)"
TRACKED_BEFORE="$(git -C "$CLONE/tracked" rev-parse HEAD)"
echo uncommitted > "$CLONE/tracked/scratch"

out="$(bash "$HOOKS/git-sync.sh" --mode reset -C "$CLONE" 2>&1)"; status=$?
check "exit is non-zero" "yes" "$([[ "$status" -ne 0 ]] && echo yes || echo no)"
check "the superproject did NOT move" "$SUPER_BEFORE" "$(git -C "$CLONE" rev-parse HEAD)"
check "the submodule did NOT move"    "$TRACKED_BEFORE" \
      "$(git -C "$CLONE/tracked" rev-parse HEAD)"
check "the uncommitted file survived" "uncommitted" "$(cat "$CLONE/tracked/scratch")"
check "and the warning names the submodule" "yes" \
      "$([[ "$out" == *"submodule tracked has uncommitted changes"* ]] && echo yes || echo no)"
echo

echo "--- reset mode goes through once that submodule is clean ---"
rm -f "$CLONE/tracked/scratch"
advance_sub_origin "$SANDBOX" tracked s3
TRACKED_TIP="$(git -C "$SANDBOX/tracked-seed" rev-parse HEAD)"
bash "$HOOKS/git-sync.sh" --mode reset -C "$CLONE" >/dev/null 2>&1; status=$?
check "exit is 0" "0" "$status"
check "superproject landed on its remote" "$SUPER_TIP" "$(git -C "$CLONE" rev-parse HEAD)"
check "submodule landed on its own remote" "$TRACKED_TIP" \
      "$(git -C "$CLONE/tracked" rev-parse HEAD)"
echo

report
