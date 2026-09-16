#!/bin/bash
# The fetch barrier: the git plugin always writes fetch-started AND fetch-done,
# so git-autosync's wait always terminates - on success, with no remote, and
# when the fetch itself fails.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SANDBOX="$(sandbox barrier)"
BASE="${TMPDIR:-/tmp}/claude-git"
trap 'rm -rf "$SANDBOX" "$BASE/barrier-ok-$$" "$BASE/barrier-nr-$$" "$BASE/barrier-fail-$$"' EXIT

make_origin "$SANDBOX"
make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"

markers_present() { # markers_present <session-id>
    local d="$BASE/$1"
    [[ -e "$d/fetch-started" && -e "$d/fetch-done" ]] && echo yes || echo no
}

echo "--- a normal fetch writes both markers ---"
printf '{"cwd":"%s","session_id":"barrier-ok-%s"}' "$CLONE" "$$" | bash "$HOOKS/session-start.sh" >/dev/null 2>&1
check "fetch-started and fetch-done both present" "yes" "$(markers_present "barrier-ok-$$")"
echo

echo "--- no remote still writes both markers (git-autosync must not hang) ---"
git init -q "$SANDBOX/noremote" -b main
printf '{"cwd":"%s","session_id":"barrier-nr-%s"}' "$SANDBOX/noremote" "$$" | bash "$HOOKS/session-start.sh" >/dev/null 2>&1
check "both markers present with no remote" "yes" "$(markers_present "barrier-nr-$$")"
echo

echo "--- a failing fetch still writes fetch-done (finally-style) ---"
# Make the remote unreachable so the fetch fails, then confirm the marker lands.
rm -rf "$SANDBOX/origin.git"
out="$(printf '{"cwd":"%s","session_id":"barrier-fail-%s"}' "$CLONE" "$$" | bash "$HOOKS/session-start.sh" 2>&1)"
check "both markers present after a failed fetch" "yes" "$(markers_present "barrier-fail-$$")"
check "and the failure is recorded as a warning" "yes" \
      "$(grep -q 'could not fetch' "$BASE/barrier-fail-$$/git.status" 2>/dev/null && echo yes || echo no)"
echo

report
