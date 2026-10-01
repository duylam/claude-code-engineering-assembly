#!/bin/bash
# The two off switches, one per step. Each disables ONLY its own step when set
# to any non-empty value (including "0"):
#   GIT_PLUGIN_GIT_FETCH_DISABLED              - skip the fetch step
#   GIT_PLUGIN_WORKTREE_ATTACHED_MODE_DISABLED - skip the worktree attach step
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SANDBOX="$(sandbox disable)"
BASE="${TMPDIR:-/tmp}/claude-git"
trap 'rm -rf "$SANDBOX" "$BASE"/dis-*-$$' EXIT

make_origin "$SANDBOX"

# A clone whose `feature` branch sits at the remote tip at clone time. The caller
# then advances the remote, so a real fetch both moves origin/main and gives
# `feature` a newer commit to fast-forward onto.
new_case() { # new_case <name>  -> echoes the clone path, leaves feature checked out
    local name="$1"
    local clone="$SANDBOX/$name"
    git clone -q "$SANDBOX/origin.git" "$clone" 2>/dev/null
    git -C "$clone" config user.email test@example.invalid
    git -C "$clone" config user.name "test"
    preexclude_worktrees "$clone"
    git -C "$clone" checkout -q -b feature origin/main
    echo "$clone"
}

run_hook() { # run_hook <clone> <session-id> [VAR=val ...]  -> echoes hook stdout
    local clone="$1" sid="$2"; shift 2
    printf '{"cwd":"%s","session_id":"%s"}' "$clone" "$sid" \
        | env "$@" bash "$HOOKS/session-start.sh" 2>&1
}

status_has() { # status_has <session-id> <needle>
    grep -q "$2" "$BASE/$1/git.status" 2>/dev/null && echo yes || echo no
}

has_summary() { [[ "$1" == *"attached mode"* ]] && echo yes || echo no; }

echo "--- fetch disabled: fetch skipped, attach still runs ---"
A="$(new_case cloneA)"
A_STALE="$(git -C "$A" rev-parse origin/main)"
advance_origin "$SANDBOX" fa
outA="$(run_hook "$A" "dis-fetch-$$" GIT_PLUGIN_GIT_FETCH_DISABLED=1)"
check "origin/main NOT advanced (fetch skipped)" "$A_STALE" "$(git -C "$A" rev-parse origin/main)"
check "attach summary emitted (attach ran)" "yes" "$(has_summary "$outA")"
check "status has no fetch line" "no" "$(status_has "dis-fetch-$$" 'fetched and pruned')"
echo

echo "--- attach disabled: fetch runs, attach skipped ---"
B="$(new_case cloneB)"
B_FEATURE_BEFORE="$(git -C "$B" rev-parse HEAD)"
advance_origin "$SANDBOX" fb
B_TIP="$(git -C "$SANDBOX/seed" rev-parse HEAD)"
outB="$(run_hook "$B" "dis-attach-$$" GIT_PLUGIN_WORKTREE_ATTACHED_MODE_DISABLED=1)"
check "origin/main advanced (fetch ran)" "$B_TIP" "$(git -C "$B" rev-parse origin/main)"
check "feature NOT moved (attach skipped)" "$B_FEATURE_BEFORE" "$(git -C "$B" rev-parse HEAD)"
check "no attach summary emitted" "no" "$(has_summary "$outB")"
check "status records the fetch" "yes" "$(status_has "dis-attach-$$" 'fetched and pruned')"
echo

echo "--- both disabled: neither step runs ---"
C="$(new_case cloneC)"
C_STALE="$(git -C "$C" rev-parse origin/main)"
advance_origin "$SANDBOX" fc
outC="$(run_hook "$C" "dis-both-$$" GIT_PLUGIN_GIT_FETCH_DISABLED=1 GIT_PLUGIN_WORKTREE_ATTACHED_MODE_DISABLED=1)"
check "origin/main NOT advanced" "$C_STALE" "$(git -C "$C" rev-parse origin/main)"
check "nothing printed to the agent" "" "$outC"
check "status file written but empty" "yes" \
      "$([[ -f "$BASE/dis-both-$$/git.status" && ! -s "$BASE/dis-both-$$/git.status" ]] && echo yes || echo no)"
echo

echo "--- neither disabled: both steps run ---"
D="$(new_case cloneD)"
advance_origin "$SANDBOX" fd
D_TIP="$(git -C "$SANDBOX/seed" rev-parse HEAD)"
outD="$(run_hook "$D" "dis-none-$$")"
check "origin/main advanced (fetch ran)" "$D_TIP" "$(git -C "$D" rev-parse origin/main)"
check "feature fast-forwarded to the new tip (attach ran)" "$D_TIP" "$(git -C "$D" rev-parse HEAD)"
check "attach summary emitted" "yes" "$(has_summary "$outD")"
check "status records both steps" "yes" \
      "$([[ "$(status_has "dis-none-$$" 'fetched and pruned')" == yes \
          && "$(status_has "dis-none-$$" 'fast-forwarded feature')" == yes ]] && echo yes || echo no)"
echo

report
