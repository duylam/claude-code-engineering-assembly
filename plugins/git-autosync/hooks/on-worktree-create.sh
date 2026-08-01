#!/bin/bash

# ============================================================================
# on-worktree-create.sh - sync the default branch BEFORE the working branch is
# cut, then create the worktree
#
# Claude Code creates a worktree and its branch before any other hook runs:
# WorktreeCreate fires in the main repo while the worktree does not exist yet,
# and SessionStart already runs inside the finished worktree. So WorktreeCreate
# is the only point at which the default branch can still be fast-forwarded in
# time for the new branch to be cut from it.
#
# WorktreeCreate REPLACES Claude Code's own `git worktree add`, so this hook
# has to create the worktree itself:
#
#     dir    <repo>/.worktrees/<name>
#     branch worktree-<name>
#     locked (as Claude Code's own worktrees are, so `git worktree prune`
#             cannot collect a live session's worktree)
#
# Contract: ONLY the worktree's absolute path goes to stdout; everything else
# goes to stderr. A non-zero exit aborts worktree creation, so the sync is
# advisory here - a failed or skipped sync must never cost the user a worktree.
#
# Dependencies: git; jq (optional, see payload_field).
# ============================================================================

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SYNC_SCRIPT="$SCRIPT_DIR/git-sync.sh"
readonly WORKTREE_SUBDIR=".worktrees"

PAYLOAD=""

# Pull a string field out of the hook payload. jq when available; otherwise
# sed, which is enough for the two fields used here (`cwd` and `name` are
# plain strings with no escapes in practice) and keeps a missing jq from
# costing the user a worktree.
payload_field() {
    local key="$1"

    if command -v jq >/dev/null 2>&1; then
        jq -r --arg k "$key" '.[$k] // empty' <<<"$PAYLOAD" 2>/dev/null || true
    else
        sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" <<<"$PAYLOAD" | head -n 1
    fi
}

# Keep the worktree directory out of `git status`. Without this the first
# worktree makes the main repo permanently dirty, and every later sync would
# skip itself on the dirty check. info/exclude is local to the clone, so this
# commits nothing on the user's behalf and shows up in no diff.
ensure_excluded() {
    local repo="$1" common exclude

    if git -C "$repo" check-ignore -q "$WORKTREE_SUBDIR" 2>/dev/null; then
        return 0
    fi

    common="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
    [[ -n "$common" && -d "$common" ]] || return 0

    exclude="$common/info/exclude"
    mkdir -p "$common/info" 2>/dev/null || return 0
    if ! printf '/%s/\n' "$WORKTREE_SUBDIR" >>"$exclude" 2>/dev/null; then
        return 0
    fi
    echo "$SCRIPT_NAME: added /$WORKTREE_SUBDIR/ to $exclude" >&2
}

PAYLOAD="$(cat || true)"
repo="$(payload_field cwd)"
name="$(payload_field name)"

if [[ -z "$repo" || -z "$name" ]]; then
    echo "$SCRIPT_NAME: missing cwd/name in the hook payload" >&2
    exit 1
fi

# Prefer git's own root in case cwd is a subdirectory of the repo.
if toplevel="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" && [[ -n "$toplevel" ]]; then
    repo="$toplevel"
fi

ensure_excluded "$repo"

# Bring the default branch up to date first - the whole point of hooking this
# event. Its stdout is redirected to stderr so it cannot pollute the path
# contract. git-sync.sh already warns for itself, does nothing in a repo with
# no remote, and always exits 0.
if [[ -f "$SYNC_SCRIPT" ]]; then
    bash "$SYNC_SCRIPT" -C "$repo" >&2 || true
fi

readonly BRANCH="worktree-$name"
worktree_dir="$repo/$WORKTREE_SUBDIR/$name"

if [[ -e "$worktree_dir/.git" ]]; then
    echo "Reusing existing worktree at $worktree_dir" >&2
elif git -C "$repo" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    echo "Branch $BRANCH already exists; creating worktree at $worktree_dir on it..." >&2
    git -C "$repo" worktree add "$worktree_dir" "$BRANCH" >&2
else
    echo "Creating worktree at $worktree_dir on new branch $BRANCH..." >&2
    git -C "$repo" worktree add -b "$BRANCH" "$worktree_dir" >&2
fi

# Match Claude Code's own worktrees; locking an already-locked one just errors.
git -C "$repo" worktree lock "$worktree_dir" 2>/dev/null || true

echo "$worktree_dir"
