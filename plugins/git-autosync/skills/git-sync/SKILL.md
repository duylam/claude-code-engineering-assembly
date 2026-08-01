---
name: git-sync
description: This skill should be used when the user asks to "sync with the remote", "update main", "fast-forward main", "pull the latest main", "is my main up to date", or wants the repository's default branch brought level with its remote without switching branches. Runs the same sync the git-autosync SessionStart and WorktreeCreate hooks run, on demand, mid-session.
argument-hint: "[path-to-repo]"
allowed-tools: Bash
---

# Git Sync

Fast-forward the repository's default branch (`main`, falling back to `master`) from its first
remote. Never switches branches, never creates a merge commit, never fails.

Run it:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR}/../..}/hooks/git-sync.sh" -C "${CLAUDE_PROJECT_DIR:-$PWD}"
```

When the user named a path in the arguments, pass that instead of `$CLAUDE_PROJECT_DIR`.

## Reporting the result

The script prints one line per thing it did, `Warning: ...` for anything a human has to resolve,
and **nothing at all when the branch was already in sync**. It always exits 0 — an empty output is
success, not a silent failure.

Relay what it printed. On empty output, say the default branch is already level with the remote.

## What it will not do

Explain these when a warning names one — each is a deliberate refusal, not a bug:

- **Main repo has uncommitted changes** → nothing is touched. Ask the user to commit or stash.
- **Local branch diverged from the remote** → the branch has commits of its own, so a
  fast-forward is impossible. Merging or rebasing is the user's call; do not do it unprompted.
- **The branch is checked out in a dirty worktree** → same reasoning, scoped to that worktree.
- **No `main` and no `master` on the remote** → the repo uses another default branch name. The
  plugin only syncs those two; a differently named branch has to be updated by hand.
- **No remote, or not a git repository** → silent no-op by design.

## Notes

- The target is always the **main** repository, even when this runs from inside a worktree: that is
  where the branch refs live.
- When the default branch is not checked out anywhere, its ref is fast-forwarded directly
  (`git fetch <remote> main:main`), so no working tree is touched at all.
