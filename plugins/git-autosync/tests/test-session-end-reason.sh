#!/bin/bash
# on-session-end.sh - the SessionEnd reap and its reason filter. This is the
# teardown path for remote-control sessions, where WorktreeRemove never fires.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SANDBOX="$(sandbox sessionend)"
trap 'rm -rf "$SANDBOX"' EXIT

make_origin "$SANDBOX"
make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"

origin_has() { # origin_has <branch>
    git -C "$CLONE" ls-remote --exit-code --heads origin "$1" >/dev/null 2>&1 && echo yes || echo no
}

# The session's tree stands on a worktree-* branch, as a remote-control session's
# does, and that branch is pushed - the thing that needs reaping.
git -C "$CLONE" checkout -q -b worktree-s
git -C "$CLONE" push -q origin worktree-s

# Fire on-session-end with the given reason; branch comes from the tree's HEAD.
end_with() { # end_with <reason> [env...]
    local reason="$1"; shift
    printf '{"reason":"%s","cwd":"%s"}' "$reason" "$CLONE" \
        | env "$@" bash "$HOOKS/on-session-end.sh" >/dev/null 2>&1
}

repush() { git -C "$CLONE" push -q origin worktree-s 2>/dev/null; }

echo "--- reasons that do NOT mean the session is gone leave the branch ---"
end_with resume
check "resume: origin still has worktree-s" "yes" "$(origin_has worktree-s)"
end_with clear
check "clear: origin still has worktree-s"  "yes" "$(origin_has worktree-s)"
echo

echo "--- the global disable switch no-ops regardless of reason ---"
end_with other GIT_AUTOSYNC_DISABLE=1
check "disabled: origin still has worktree-s" "yes" "$(origin_has worktree-s)"
echo

echo "--- a genuine end reaps the branch ---"
end_with prompt_input_exit
check "prompt_input_exit reaps worktree-s" "no" "$(origin_has worktree-s)"
repush
check "re-pushed for the next case" "yes" "$(origin_has worktree-s)"
end_with other
check "other reaps worktree-s too" "no" "$(origin_has worktree-s)"
echo

echo "--- a session that ended on a human branch is never reaped ---"
git -C "$CLONE" checkout -q -b keep-me
git -C "$CLONE" push -q origin keep-me
end_with other
check "keep-me survives (outside worktree-* namespace)" "yes" "$(origin_has keep-me)"
echo

echo "--- rule zero: outside a git repo, nothing happens ---"
out="$(printf '{"reason":"other","cwd":"%s"}' "$SANDBOX" | bash "$HOOKS/on-session-end.sh" 2>&1)"
check "not a git repo: silent" "" "$out"
echo

report
