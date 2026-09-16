#!/bin/bash
# Feature-branch protection: a push that would update main or master directly on
# the remote is blocked (exit 2); everything else is allowed (exit 0).
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SANDBOX="$(sandbox protect)"
trap 'rm -rf "$SANDBOX"' EXIT

make_origin "$SANDBOX"
make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"
# Work on a feature branch so a bare `git push` does not target a protected one.
git -C "$CLONE" checkout -q -b my-feature

# run_hook <command> [env] -> prints the hook's exit code (2 = blocked, 0 = allow)
run_hook() {
    local cmd="$1" env="${2:-}"
    printf '{"tool_input":{"command":"%s"}}' "$cmd" | \
        ( cd "$CLONE" && eval "$env" bash "$HOOKS/protect-branches.sh" >/dev/null 2>&1 )
    echo $?
}

echo "--- protected destinations are blocked ---"
check "push origin main"            "2" "$(run_hook 'git push origin main')"
check "push origin master"          "2" "$(run_hook 'git push origin master')"
check "push -u origin HEAD:main"    "2" "$(run_hook 'git push -u origin HEAD:main')"
check "push origin feature:main"    "2" "$(run_hook 'git push origin feature:main')"
check "push --force origin main"    "2" "$(run_hook 'git push --force origin main')"
check "push --all (main exists)"    "2" "$(run_hook 'git push --all')"
echo

echo "--- non-protected pushes are allowed ---"
check "push origin my-feature"      "0" "$(run_hook 'git push origin my-feature')"
check "push -u origin HEAD"         "0" "$(run_hook 'git push -u origin HEAD')"
check "push origin main:feature"    "0" "$(run_hook 'git push origin main:feature')"
check "a non-push git command"      "0" "$(run_hook 'git status')"
echo

echo "--- a bare push on a protected branch is blocked ---"
git -C "$CLONE" checkout -q main
check "on main, bare push"          "2" "$(run_hook 'git push')"
git -C "$CLONE" checkout -q my-feature
echo

echo "--- the disable switch turns protection off ---"
check "GIT_PLUGIN_DISABLE=1 allows push origin main" "0" \
      "$(run_hook 'git push origin main' 'GIT_PLUGIN_DISABLE=1')"
echo

report
