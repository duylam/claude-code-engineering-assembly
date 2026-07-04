#!/bin/bash

# ============================================================================
# WorktreeCreate hook
#
# This hook REPLACES Claude Code's default `git worktree add` behavior
# (see docs: WorktreeCreate "Replaces default git behavior"). It receives
# JSON on stdin with fields: session_id, transcript_path, cwd (repo root),
# hook_event_name, name (generated worktree/branch name).
#
# Contract: must print ONLY the created worktree's absolute path on stdout
# (all other output must go to stderr), and exit 0. Any non-zero exit
# aborts worktree creation.
# ============================================================================

set -euo pipefail

input="$(cat)"
repo_dir="$(jq -r '.cwd' <<<"$input")"
name="$(jq -r '.name' <<<"$input")"

if [[ -z "$repo_dir" || "$repo_dir" == "null" || -z "$name" || "$name" == "null" ]]; then
    echo "on-worktree-create: missing cwd/name in hook input" >&2
    exit 1
fi

worktree_dir="$repo_dir/.worktrees/$name"

echo "Creating worktree at $worktree_dir..." >&2
git -C "$repo_dir" worktree add -b "$name" "$worktree_dir" >&2

if [[ -f "$worktree_dir/.gitmodules" ]]; then
    echo "Populating submodules..." >&2
    git -C "$worktree_dir" submodule update --init --recursive >&2

    # submodule update leaves each submodule on a detached HEAD; check each
    # one out onto a local branch matching the worktree name so submodule
    # work stays on the same branch as the parent worktree.
    echo "Checking out submodules onto branch $name..." >&2
    git -C "$worktree_dir" submodule foreach --recursive "git checkout -B '$name'" >&2
fi

# Only the path goes to stdout — Claude Code uses this as the worktree cwd.
echo "$worktree_dir"
