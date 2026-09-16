#!/bin/bash
# PreToolUse (Bash) hook: block git push operations that would update main or master
# directly on the remote. Exits 2 with a descriptive message when blocked;
# exits 0 otherwise. Controlled by GIT_PLUGIN_DISABLE like all plugin hooks.
set -uo pipefail

# Honor the plugin-wide disable switch: any non-empty value turns hooks off.
if [[ -n "${GIT_PLUGIN_DISABLE:-}" ]]; then
    exit 0
fi

readonly PROTECTED=(main master)

# Read and parse the PreToolUse (Bash) hook JSON payload from stdin.
INPUT="$(cat)"

if command -v jq &>/dev/null; then
    CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)"
else
    # Fallback: extract the first "command":"..." field (handles simple single-line values).
    CMD="$(printf '%s' "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | \
           sed 's/^"command":"//; s/"$//')"
fi

[[ -z "${CMD:-}" ]] && exit 0

# Only intercept git push commands.
case "$CMD" in
    *git\ push*) ;;
    *) exit 0 ;;
esac

deny() {
    local branch="$1"
    local detail="${2:-}"
    # On exit 2 for a PreToolUse hook, Claude Code surfaces the hook's stderr as
    # the block reason, so send the guidance there rather than to stdout.
    {
        printf '\nBranch protection: "%s" cannot be updated directly on the remote.\n' "$branch"
        [[ -n "$detail" ]] && printf '%s\n' "$detail"
        printf '\nProtected branches must be updated through a pull request:\n'
        printf '  1. Create a feature branch:  git checkout -b my-feature-branch\n'
        printf '  2. Push that branch:         git push origin my-feature-branch\n'
        printf '  3. Open a pull request targeting "%s"\n' "$branch"
        printf '\nTo bring your local pointer up to date without pushing:\n'
        printf '  git fetch origin && git merge origin/%s\n' "$branch"
    } >&2
    exit 2
}

# --- Case 1: --all pushes every local branch, potentially including protected ones ---
if printf '%s' "$CMD" | grep -qE '(^|[[:space:]])--all([[:space:]]|$)'; then
    for branch in "${PROTECTED[@]}"; do
        if git rev-parse --verify "$branch" &>/dev/null 2>&1; then
            deny "$branch" '"--all" pushes every local branch — this includes the protected one.'
        fi
    done
fi

for branch in "${PROTECTED[@]}"; do
    # --- Case 2: explicit destination in a refspec: :branch or :refs/heads/branch ---
    # Catches: HEAD:main, feature:main, :main (deletion via refspec).
    if printf '%s' "$CMD" | grep -qE ":${branch}([[:space:]]|$)" || \
       printf '%s' "$CMD" | grep -qE ":refs/heads/${branch}([[:space:]]|$)"; then
        deny "$branch"
    fi

    # --- Case 3a: standalone short refspec NOT immediately followed by ':' ---
    # Catches: push origin main, push --force origin master, push --delete origin main.
    # Allows:  push origin main:feature  (main is source, not destination).
    if printf '%s' "$CMD" | grep -qE "(^|[[:space:]])${branch}([[:space:]]|$)" && \
       ! printf '%s' "$CMD" | grep -qE "(^|[[:space:]])${branch}:"; then
        deny "$branch"
    fi

    # --- Case 3b: standalone full refspec refs/heads/branch NOT followed by ':' ---
    # Catches: push origin refs/heads/main.
    if printf '%s' "$CMD" | grep -qE "(^|[[:space:]])refs/heads/${branch}([[:space:]]|$)" && \
       ! printf '%s' "$CMD" | grep -qE "(^|[[:space:]])refs/heads/${branch}:"; then
        deny "$branch"
    fi
done

# --- Case 4: HEAD as standalone refspec resolves to the current branch ---
# Catches: push origin HEAD, push -u origin HEAD — when on a protected branch.
# HEAD:dst is already covered by case 2 when dst is a protected branch.
if printf '%s' "$CMD" | grep -qE "(^|[[:space:]])HEAD([[:space:]]|$)" && \
   ! printf '%s' "$CMD" | grep -qE "(^|[[:space:]])HEAD:"; then
    CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
    for branch in "${PROTECTED[@]}"; do
        if [[ "${CURRENT_BRANCH:-}" == "$branch" ]]; then
            deny "$branch" '"HEAD" resolves to the protected branch on the current checkout.'
        fi
    done
fi

# --- Case 5: bare push with no explicit refspec defaults to the current branch ---
# 0 non-flag tokens (git push) or 1 (git push <remote>): no refspec was given,
# so git infers it from the current branch's tracking configuration.
_rest="$(printf '%s' "$CMD" | sed 's/.*git[[:space:]]\{1,\}push//')"
NON_FLAG_TOKENS=0
if [[ -n "$_rest" ]]; then
    for _tok in $_rest; do
        [[ -n "$_tok" && "${_tok:0:1}" != "-" ]] && NON_FLAG_TOKENS=$((NON_FLAG_TOKENS + 1))
    done
fi

if [[ "$NON_FLAG_TOKENS" -le 1 ]]; then
    CURRENT_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
    for branch in "${PROTECTED[@]}"; do
        if [[ "${CURRENT_BRANCH:-}" == "$branch" ]]; then
            deny "$branch" 'No explicit refspec — git would push the current protected branch to its remote tracking name.'
        fi
    done
fi

exit 0
