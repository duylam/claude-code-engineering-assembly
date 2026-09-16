#!/bin/bash
# The git plugin's SessionStart fetch: bring every branch and tag level with the
# remote, and prune branch and tag refs the remote no longer has.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SANDBOX="$(sandbox fetchprune)"
SID="fetchprune-$$"
trap 'rm -rf "$SANDBOX" "${TMPDIR:-/tmp}/claude-git/$SID"' EXIT

make_origin "$SANDBOX"

# A branch and a tag that exist at clone time, so the clone gets remote-tracking
# refs for them - later deleted on the remote, to prove pruning.
git -C "$SANDBOX/seed" branch stale-branch
git -C "$SANDBOX/seed" push -q origin stale-branch
git -C "$SANDBOX/seed" tag stale-tag
git -C "$SANDBOX/seed" push -q origin stale-tag

make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"

check "precondition: origin/stale-branch present in clone" "yes" \
      "$(git -C "$CLONE" rev-parse --verify --quiet refs/remotes/origin/stale-branch >/dev/null && echo yes || echo no)"
check "precondition: stale-tag present in clone" "yes" \
      "$(git -C "$CLONE" rev-parse --verify --quiet refs/tags/stale-tag >/dev/null && echo yes || echo no)"

# The remote moves on: the stale branch and tag are deleted, a new branch and a
# new tag appear.
git -C "$SANDBOX/seed" push -q origin --delete stale-branch
git -C "$SANDBOX/seed" push -q origin --delete stale-tag
git -C "$SANDBOX/seed" branch feature-x
git -C "$SANDBOX/seed" push -q origin feature-x
git -C "$SANDBOX/seed" tag v1.0
git -C "$SANDBOX/seed" push -q origin v1.0

echo "--- fetch brings new refs in and prunes deleted ones ---"
out="$(printf '{"cwd":"%s","session_id":"%s"}' "$CLONE" "$SID" | bash "$HOOKS/session-start.sh" 2>&1)"
check "new branch fetched" "yes" \
      "$(git -C "$CLONE" rev-parse --verify --quiet refs/remotes/origin/feature-x >/dev/null && echo yes || echo no)"
check "new tag fetched" "yes" \
      "$(git -C "$CLONE" rev-parse --verify --quiet refs/tags/v1.0 >/dev/null && echo yes || echo no)"
check "stale branch pruned" "no" \
      "$(git -C "$CLONE" rev-parse --verify --quiet refs/remotes/origin/stale-branch >/dev/null && echo yes || echo no)"
check "stale tag pruned" "no" \
      "$(git -C "$CLONE" rev-parse --verify --quiet refs/tags/stale-tag >/dev/null && echo yes || echo no)"
echo

echo "--- the hook stays silent to the agent and records human status ---"
check "no additionalContext emitted (agent sees nothing)" "" "$out"
check "status file records the fetch" "yes" \
      "$(grep -q 'fetched and pruned' "${TMPDIR:-/tmp}/claude-git/$SID/git.status" 2>/dev/null && echo yes || echo no)"
echo

echo "--- rule zero: nothing outside a git repo, or with no remote ---"
git init -q "$SANDBOX/noremote" -b main
check "not a git repo: exit 0, silent" "0" \
      "$(printf '{"cwd":"%s","session_id":"nr-%s"}' "$SANDBOX" "$$" | bash "$HOOKS/session-start.sh" >/dev/null 2>&1; echo $?)"
check "no remote: exit 0, silent" "" \
      "$(printf '{"cwd":"%s","session_id":"nr2-%s"}' "$SANDBOX/noremote" "$$" | bash "$HOOKS/session-start.sh" 2>&1)"
rm -rf "${TMPDIR:-/tmp}/claude-git/nr-$$" "${TMPDIR:-/tmp}/claude-git/nr2-$$"
echo

report
