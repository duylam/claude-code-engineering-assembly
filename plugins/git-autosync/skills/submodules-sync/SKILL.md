---
name: submodules-sync
description: Populate every submodule recursively, attach each top-level submodule to a branch named after the superproject's branch, and reconcile that branch with the submodule's own remote. Two modes - merge (default, keeps local commits) and reset (discards them). The submodule half of the sync, without touching the superproject.
argument-hint: "[merge|reset] [path-to-repo-or-worktree]"
allowed-tools: Bash
disable-model-invocation: true
---

# Submodules Sync

The submodule pass on its own, without syncing the superproject. For each **top-level** submodule:
populate it, attach it to a branch named after the superproject's current branch, then reconcile
that branch with the submodule's own remote.

Use `/git-autosync:git-sync` instead when the superproject should be synced too — it runs this
same worker as its second step.

## Modes

Two mutually exclusive modes. **`merge` is the default**; use it unless the user asked for `reset`.

| Mode | What it does | Destructive |
|---|---|---|
| `merge` | Fast-forwards, or makes a merge commit when the submodule branch has commits of its own. | No |
| `reset` | Hard-resets each submodule to its remote branch. Refuses to touch anything at all when the superproject or **any** submodule is dirty. | **Yes** |

## Run it

Read the first argument: `merge` or `reset` selects the mode, anything else is a path. When no
mode is named, use `merge`.

```bash
bash "${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR}/../..}/hooks/ensure-submodules.sh" \
    --mode merge -C "${CLAUDE_PROJECT_DIR:-$PWD}"
```

Substitute `reset` for `merge` when the user asked for it, and the user's path for
`$CLAUDE_PROJECT_DIR` when they named one.

**Before running `reset`, tell the user it will discard local commits in every submodule.**

## Which branch a submodule syncs to

Resolved in this order, which is git's own:

1. `submodule.<name>.branch` in `.gitmodules` — the branch that submodule declares it tracks.
2. The literal value `.`, which git defines as "the same branch the superproject is on".
3. Neither is set → the submodule's own default branch (`main`, falling back to `master`).

It is always `<the submodule's own remote>/<that branch>` — **not** the commit the superproject
records for the submodule. A submodule can therefore end up ahead of the superproject's gitlink,
which is the intended behavior.

## Reporting the result

The script prints one line per submodule it changed, `Warning: ...` for anything a human has to
resolve, and **nothing at all when every submodule was already populated, attached and level**.

- Exit 0 with empty output → the submodules were already correct.
- **Exit non-zero** → only in `reset` mode, and always means the preflight refused: something was
  dirty, so **nothing anywhere was changed**. Name the dirty path and offer to commit or stash it,
  or to re-run in `merge` mode.

## What it will not do

Explain these when a warning names one — each is a deliberate refusal, not a bug:

- **A populated submodule is never rewound by the populate step.** `git submodule update` is only
  run over a top-level submodule that is not populated yet. A populated one is only asked to fill
  in its own nested submodules. (The *sync* step does move it — that is the point — but only
  forward in `merge` mode.)
- **An existing submodule branch is never re-pointed by the attach step.** If the branch already
  exists it is checked out where it stands, never moved (`checkout -B` is not used).
- **Merge conflicts inside a submodule** → the merge is **rolled back**, not left half-resolved.
  The warning names the exact command; offer it rather than resolving unprompted.
- **Nested submodules get no branch and no sync.** They are populated and left on their gitlink —
  they are vendored third-party trees.
- **Superproject on a detached HEAD** → submodules are populated but not attached or synced; there
  is no branch name to mirror.
- **No `.gitmodules`, no remote, or not a git repository** → silent no-op by design.

## Notes

- Every warning names the exact `git -C ... ` command to run by hand. Offer it; do not run a
  destructive variant of it unprompted.
- Hooks never pass a mode, so an unattended run is always `merge` and always succeeds.
