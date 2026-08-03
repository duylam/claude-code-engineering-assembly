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
#     branch worktree-<name>, cut from the local default branch the sync just
#            updated (falling back to HEAD when the repo has neither main nor
#            master), NOT from whatever branch the clone was left on
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

# shellcheck source=lib/git-common.sh
# For BRANCH_CANDIDATES and resolve_default_branch: the new branch has to start
# from the same branch git-sync.sh just updated. Also for WORKTREE_DIRS and
# SESSION_BRANCH_PREFIX below - the directory this hook writes to and the branch
# prefix it stamps have to be the same ones the sync excludes and the cleanup
# recognises, so all three read them from one place.
source "$SCRIPT_DIR/lib/git-common.sh"

# The plugin's own worktree root: the first entry, the one it chooses when it
# is in charge. The rest of WORKTREE_DIRS are locations Claude Code may use
# instead, which this hook never writes to but the exclude still has to cover.
readonly WORKTREE_SUBDIR="${WORKTREE_DIRS[0]}"

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

# Keep every worktree directory out of `git status` before anything reads it.
# git-sync.sh does this too, but it returns early in a repo with no remote -
# and a remote-less repo still gets worktrees, so it still needs the exclude.
# Its notes go to stderr here, where they cannot pollute the path contract.
ensure_worktrees_excluded "$repo"
render_report >&2
NOTES=()
WARNINGS=()

# Bring the repository up to date first - the whole point of hooking this
# event, since resolve_base below cuts the new branch from the LOCAL default
# branch ref and this is the last moment to make that ref current.
#
# Note the reach: the sync runs against the MAIN checkout, so it also merges
# <remote>/<default> into whatever branch that checkout is standing on, and
# syncs its submodules. No mode is passed, so this is always the non-destructive
# `merge` - a dirty main checkout is reported and left alone.
#
# Its stdout is redirected to stderr so it cannot pollute the path contract.
# git-sync.sh already warns for itself, does nothing in a repo with no remote,
# and always exits 0 in merge mode.
if [[ -f "$SYNC_SCRIPT" ]]; then
    bash "$SYNC_SCRIPT" -C "$repo" >&2 || true
fi

readonly BRANCH="$SESSION_BRANCH_PREFIX$name"
worktree_dir="$repo/$WORKTREE_SUBDIR/$name"

# Where a NEW branch starts. `git worktree add -b <branch> <dir>` with no
# commit-ish defaults to HEAD - whatever branch this clone was left on, which
# is exactly the stale starting point the sync above exists to avoid. Naming
# the default branch explicitly is what makes that sync count.
#
# The LOCAL ref, not <remote>/<branch>: when the sync had to stop (dirty repo,
# diverged branch) the local one still carries commits the human made and has
# not pushed, and a base that silently drops those is worse than one that is
# merely behind. git-sync.sh has already warned about that case by here.
resolve_base() {
    local base

    base="$(resolve_default_branch "$repo" heads)"
    if [[ -z "$base" ]]; then
        # Some other default branch name, or a repo with no commits yet. Fall
        # back to the old behaviour rather than cost the user a worktree.
        echo "$SCRIPT_NAME: no local ${BRANCH_CANDIDATES[*]} branch; cutting $BRANCH from HEAD" >&2
        base="HEAD"
    fi

    echo "$base"
}

if [[ -e "$worktree_dir/.git" ]]; then
    echo "Reusing existing worktree at $worktree_dir" >&2
elif git -C "$repo" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    # An existing branch may carry work from an earlier session, so it is used
    # where it stands and never moved onto the default branch.
    echo "Branch $BRANCH already exists; creating worktree at $worktree_dir on it..." >&2
    git -C "$repo" worktree add "$worktree_dir" "$BRANCH" >&2
else
    base="$(resolve_base)"
    echo "Creating worktree at $worktree_dir on new branch $BRANCH from $base..." >&2
    git -C "$repo" worktree add -b "$BRANCH" "$worktree_dir" "$base" >&2
fi

# Match Claude Code's own worktrees; locking an already-locked one just errors.
git -C "$repo" worktree lock "$worktree_dir" 2>/dev/null || true

echo "$worktree_dir"
