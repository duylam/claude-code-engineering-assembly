#!/bin/bash
# Branch protection hook tests — verify that protect-branches.sh blocks all
# forms of push to main/master and allows pushes to other branches.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SANDBOX="$(sandbox protect)"
trap 'rm -rf "$SANDBOX"' EXIT

# Ensure the plugin-wide disable switch is off for these tests.
unset GIT_AUTOSYNC_DISABLE 2>/dev/null || true

make_origin "$SANDBOX"
make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"

HOOK="$HOOKS/protect-branches.sh"

# Simulate a PreToolUse (Bash) hook invocation by piping a synthetic JSON payload to the
# hook from inside the clone directory (so git commands see the real repo).
# Outputs the hook's exit code as a plain string.
invoke() {
    local cmd="$1"
    (cd "$CLONE" && printf '{"tool_input":{"command":"%s"}}' "$cmd" | bash "$HOOK") \
        > /dev/null 2>&1
    echo $?
}

blocked() { [[ "$(invoke "$1")" -ne 0 ]] && echo yes || echo no; }
allowed() { [[ "$(invoke "$1")" -eq 0 ]] && echo yes || echo no; }

echo "--- blocked: standalone refspec to main ---"
check "git push origin main"                      "yes" "$(blocked 'git push origin main')"
check "git push --force origin main"              "yes" "$(blocked 'git push --force origin main')"
check "git push -f origin main"                   "yes" "$(blocked 'git push -f origin main')"
echo

echo "--- blocked: standalone refspec to master ---"
check "git push origin master"                    "yes" "$(blocked 'git push origin master')"
check "git push --force-with-lease origin master" "yes" "$(blocked 'git push --force-with-lease origin master')"
echo

echo "--- blocked: destination side of a refspec ---"
check "git push origin HEAD:main"                 "yes" "$(blocked 'git push origin HEAD:main')"
check "git push origin feature:main"              "yes" "$(blocked 'git push origin feature:main')"
check "git push origin HEAD:master"               "yes" "$(blocked 'git push origin HEAD:master')"
echo

echo "--- blocked: deletion ---"
check "git push origin :main"                     "yes" "$(blocked 'git push origin :main')"
check "git push origin :master"                   "yes" "$(blocked 'git push origin :master')"
check "git push origin --delete main"             "yes" "$(blocked 'git push origin --delete main')"
check "git push origin -d master"                 "yes" "$(blocked 'git push origin -d master')"
echo

echo "--- blocked: full refs/heads refspec ---"
check "git push origin refs/heads/main"           "yes" "$(blocked 'git push origin refs/heads/main')"
check "git push origin refs/heads/master"         "yes" "$(blocked 'git push origin refs/heads/master')"
echo

echo "--- blocked: HEAD resolves to main (clone is on main after make_clone) ---"
check "git push origin HEAD (on main)"            "yes" "$(blocked 'git push origin HEAD')"
check "git push -u origin HEAD (on main)"         "yes" "$(blocked 'git push -u origin HEAD')"
echo

echo "--- blocked: bare push while on main ---"
check "git push (on main)"                        "yes" "$(blocked 'git push')"
check "git push origin (on main)"                 "yes" "$(blocked 'git push origin')"
echo

echo "--- blocked: --all when main exists locally ---"
check "git push --all (main exists locally)"      "yes" "$(blocked 'git push --all')"
check "git push --all origin (main exists)"       "yes" "$(blocked 'git push --all origin')"
echo

# Switch to a feature branch so the remaining tests are not on a protected branch.
git -C "$CLONE" checkout -q -b feature origin/main

echo "--- allowed: push to non-protected destination ---"
check "git push origin feature"                   "yes" "$(allowed 'git push origin feature')"
check "git push -u origin feature"                "yes" "$(allowed 'git push -u origin feature')"
check "git push origin my-branch"                 "yes" "$(allowed 'git push origin my-branch')"
echo

echo "--- allowed: main as source refspec (remote destination is not protected) ---"
check "git push origin main:feature"              "yes" "$(allowed 'git push origin main:feature')"
check "git push origin main:staging"              "yes" "$(allowed 'git push origin main:staging')"
echo

echo "--- allowed: branch names that contain main/master as a substring ---"
check "git push origin feature-main"              "yes" "$(allowed 'git push origin feature-main')"
check "git push origin main-feature"              "yes" "$(allowed 'git push origin main-feature')"
check "git push origin maintain"                  "yes" "$(allowed 'git push origin maintain')"
check "git push origin masterplan"                "yes" "$(allowed 'git push origin masterplan')"
echo

echo "--- allowed: HEAD on a non-protected branch ---"
check "git push origin HEAD (on feature)"         "yes" "$(allowed 'git push origin HEAD')"
check "git push -u origin HEAD (on feature)"      "yes" "$(allowed 'git push -u origin HEAD')"
echo

echo "--- allowed: bare push while not on a protected branch ---"
check "git push (on feature)"                     "yes" "$(allowed 'git push')"
check "git push origin (on feature)"              "yes" "$(allowed 'git push origin')"
echo

echo "--- allowed: non-push git commands pass through ---"
check "git fetch origin"                          "yes" "$(allowed 'git fetch origin')"
check "git pull origin main"                      "yes" "$(allowed 'git pull origin main')"
check "git branch -D main"                        "yes" "$(allowed 'git branch -D main')"
check "git reset --hard origin/main"              "yes" "$(allowed 'git reset --hard origin/main')"
echo

echo "--- denial message is descriptive ---"
# The hook writes its block reason to stderr, since Claude Code surfaces a
# PreToolUse hook's stderr as the denial reason on exit 2; capture it via 2>&1.
MSG="$(cd "$CLONE" && printf '{"tool_input":{"command":"git push origin main"}}' | bash "$HOOK" 2>&1 || true)"
check "mentions the branch name" "yes" "$([[ "$MSG" == *'"main"'* ]] && echo yes || echo no)"
check "mentions pull request"    "yes" "$([[ "$MSG" == *"pull request"* ]] && echo yes || echo no)"
check "mentions feature branch"  "yes" "$([[ "$MSG" == *"feature"* ]] && echo yes || echo no)"
echo

echo "--- GIT_AUTOSYNC_DISABLE bypasses the hook ---"
( export GIT_AUTOSYNC_DISABLE=1
  cd "$CLONE"
  printf '{"tool_input":{"command":"git push origin main"}}' | bash "$HOOK" > /dev/null 2>&1 ); DISABLED_STATUS=$?
check "disabled: push to main passes through" "yes" "$([[ "$DISABLED_STATUS" -eq 0 ]] && echo yes || echo no)"
echo

report
