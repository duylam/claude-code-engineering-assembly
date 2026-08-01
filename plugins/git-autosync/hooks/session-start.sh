#!/bin/bash

# ============================================================================
# session-start.sh - SessionStart hook: one sync pass before the first prompt
#
# Runs the two workers in sequence, in this order and never in parallel (they
# both touch the same repository, and git's index locks are not shareable):
#
#   1. git-sync.sh          fast-forward the default branch from the remote
#   2. ensure-submodules.sh populate submodules, attach them to the branch
#
# Step 1 is what makes a plain, worktree-less session current. In a worktree
# session the WorktreeCreate hook has already synced, and this second pass
# costs one cheap `git fetch` and stays silent.
#
# Their plain-text output is merged into a single hook JSON envelope, so the
# session opens with one short status line instead of two. Silence when both
# workers had nothing to say - the normal case.
#
# ALWAYS exits 0. The workers never fail; this wrapper must not either.
#
# Dependencies: git; jq (optional - without it the same text is printed
# plainly, which SessionStart also accepts).
# ============================================================================

set -Eeuo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

payload="$(cat || true)"

# The directory Claude Code started in. In a worktree session this is the
# worktree, which is exactly the tree whose submodules must be synced.
cwd=""
if command -v jq >/dev/null 2>&1; then
    cwd="$(jq -r '.cwd // empty' <<<"$payload" 2>/dev/null || true)"
else
    # No jq: pull the field with sed. `cwd` is a plain path string in practice.
    cwd="$(sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<<"$payload" | head -n 1)"
fi
if [[ -z "$cwd" || ! -d "$cwd" ]]; then
    cwd="$PWD"
fi

report="$(
    bash "$SCRIPT_DIR/git-sync.sh" -C "$cwd" || true
    bash "$SCRIPT_DIR/ensure-submodules.sh" -C "$cwd" || true
)"

if [[ -z "$report" ]]; then
    exit 0
fi

if command -v jq >/dev/null 2>&1; then
    jq -n --arg msg "$report" \
        '{
            systemMessage: $msg,
            hookSpecificOutput: {
                hookEventName: "SessionStart",
                additionalContext: $msg
            }
        }'
else
    echo "$report"
fi

exit 0
