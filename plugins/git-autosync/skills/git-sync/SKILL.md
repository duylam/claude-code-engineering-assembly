---
name: git-sync
description: Reconcile the branch this tree is on with its remote's default branch (main, falling back to master), then do the same for every submodule against its own remote. Two modes - merge (default, keeps local commits) and reset (discards them). Manual run of the sync the SessionStart and WorktreeCreate hooks already perform.
argument-hint: "[merge|reset] [path-to-repo]"
allowed-tools: Bash
disable-model-invocation: true
---

# Git Sync

Bring the working tree level with its remote — the branch it is standing on, and then every
top-level submodule against that submodule's own remote.

## Modes

Two mutually exclusive modes. **`merge` is the default**; use it unless the user asked for `reset`.

| Mode | What it does | Destructive |
|---|---|---|
| `merge` | Brings the remote's commits in and keeps local ones — a fast-forward when the branch has none of its own, a merge commit when it does. | No |
| `reset` | Hard-resets the branch to the remote, discarding local commits. Refuses to touch anything at all when the superproject or **any** submodule is dirty. | **Yes** |

## Run it

Arguments: `$ARGUMENTS`

Parse the arguments in order:
1. If the first token is `merge` or `reset` — that is the mode; consume it.
2. If no valid mode token was found — default to `merge`.
3. Any remaining token is treated as the repository path.

```bash
bash "${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR}/../..}/hooks/git-sync.sh" \
    --mode merge -C "${CLAUDE_PROJECT_DIR:-$PWD}"
```

Replace `merge` with the resolved mode and `${CLAUDE_PROJECT_DIR:-$PWD}` with the user's path when
one was provided.

**Before running `reset`, tell the user it will discard local commits on the current branch and in
every submodule.** They asked for it, so run it — but say what it does first, in one line.

## Reporting the result

The script prints one line per thing it did, `Warning: ...` for anything a human has to resolve,
and **nothing at all when everything was already in sync**.

- Exit 0 with empty output → everything was already level with the remote. Say so.
- Exit 0 with warnings → the sync did what it could; relay the warnings.
- **Exit non-zero** → only ever happens in `reset` mode, and always means the preflight refused:
  something was dirty, so **nothing anywhere was changed**. Name the dirty path from the warning
  and offer to commit or stash it, or to re-run in `merge` mode.

## What it will not do

Explain these when a warning names one — each is a deliberate refusal, not a bug:

- **Dirty tree in merge mode** → the branch is behind but has uncommitted changes, so the merge is
  skipped for that tree. Commit or stash, then re-run.
- **Merge conflicts** → the merge is **rolled back**, not left half-resolved. The warning names the
  exact `git -C ... merge ...` command; offer it and let the user drive the resolution. Do not
  re-run it and start resolving conflicts unprompted.
- **Detached HEAD** → there is no branch to reconcile. Offer `/git-autosync:branch-name` or a
  plain checkout.
- **The default branch itself has diverged** and the session is not standing on it → that ref is
  only maintained as a base for new worktrees, so it is reported and never merged. Resolving it is
  the user's call.
- **No `main` and no `master` on the remote** → the repo uses another default branch name. The
  plugin only syncs those two.
- **No remote, or not a git repository** → silent no-op by design.

## Notes

- Submodules are synced to the commit the superproject currently records for them (the gitlink in
  `HEAD:<path>`). If that commit is not in the submodule's local object store, the script fetches
  from the submodule's own remote to retrieve it.
- `reset` puts the pre-reset commit in the reflog. If a user resets by mistake, `git reflog` in the
  affected tree recovers it — the note the script printed names the short SHA.
- The default branch's local ref is kept fresh separately, because `on-worktree-create.sh` cuts new
  worktrees from it. That path is always fast-forward-only and touches no working tree.
- Hooks never pass a mode, so an unattended `SessionStart` sync is always `merge` and always
  succeeds. `reset` is only reachable from this skill.
