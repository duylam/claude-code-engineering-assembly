#!/bin/bash
# The fetch barrier, from git-autosync's side: it waits for the `git` plugin's
# fetch-done marker before attaching, but the wait is always bounded - it
# proceeds whether the marker arrives, the bound is reached, or the `git` plugin
# never announces itself at all. It never hangs.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SANDBOX="$(sandbox aubarrier)"
BASE="${TMPDIR:-/tmp}/claude-git"
trap 'rm -rf "$SANDBOX" "$BASE/bar-both-$$" "$BASE/bar-wait-$$" "$BASE/bar-none-$$"' EXIT

make_origin "$SANDBOX"
make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"

advance_origin "$SANDBOX" c2
advance_origin "$SANDBOX" c3
TIP="$(git -C "$SANDBOX/seed" rev-parse HEAD)"
git -C "$CLONE" fetch -q origin

# A fresh branch two commits behind, so a successful attach fast-forwards to TIP.
fresh_behind() { git -C "$CLONE" checkout -q -B "$1" "origin/main~2"; }

# run_ss <session-id> <env assignments...> - drive SessionStart with given bounds.
run_ss() {
    local sid="$1"; shift
    printf '{"cwd":"%s","session_id":"%s"}' "$CLONE" "$sid" | \
        env "$@" bash "$HOOKS/session-start.sh" >/dev/null 2>&1
}

echo "--- proceeds promptly when fetch-done is already present ---"
D="$BASE/bar-both-$$"; mkdir -p "$D"; touch "$D/fetch-started" "$D/fetch-done"
fresh_behind fb1
run_ss "bar-both-$$" GIT_AUTOSYNC_GRACE_SECS=60 GIT_AUTOSYNC_FETCH_WAIT_SECS=60
check "attached when fetch-done is present" "$TIP" "$(git -C "$CLONE" rev-parse HEAD)"
echo

echo "--- waits for fetch-done, then proceeds when the bound is reached ---"
D="$BASE/bar-wait-$$"; mkdir -p "$D"; touch "$D/fetch-started"   # started, never done
fresh_behind fb2
start="$SECONDS"
run_ss "bar-wait-$$" GIT_AUTOSYNC_GRACE_SECS=60 GIT_AUTOSYNC_FETCH_WAIT_SECS=2
elapsed=$((SECONDS - start))
check "attached after the bounded wait (never hangs)" "$TIP" "$(git -C "$CLONE" rev-parse HEAD)"
check "the wait actually engaged (>= 1s)" "yes" "$([[ "$elapsed" -ge 1 ]] && echo yes || echo no)"
echo

echo "--- proceeds within the grace window when the git plugin is absent ---"
fresh_behind fb3   # no markers created: git plugin not participating
run_ss "bar-none-$$" GIT_AUTOSYNC_GRACE_SECS=1 GIT_AUTOSYNC_FETCH_WAIT_SECS=60
check "attached without a git plugin present" "$TIP" "$(git -C "$CLONE" rev-parse HEAD)"
echo

report
