---
name: submodules-sync
description: Populate every submodule recursively and attach each top-level submodule to a branch named after the superproject's branch. Manual run of the submodule pass the SessionStart hook already performs.
argument-hint: "[path-to-repo-or-worktree]"
allowed-tools: Bash
disable-model-invocation: true
---

# Submodules Sync

Populate every submodule recursively and attach each **top-level** submodule to a branch named
after the superproject's current branch, so commits made inside a submodule land on a branch
instead of a detached HEAD.

Run it:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR}/../..}/hooks/ensure-submodules.sh" -C "${CLAUDE_PROJECT_DIR:-$PWD}"
```

When the user named a path in the arguments, pass that instead of `$CLAUDE_PROJECT_DIR`.

## Reporting the result

The script prints one line per submodule it changed, `Warning: ...` for anything a human has to
resolve, and **nothing at all when every submodule was already populated and attached**. It always
exits 0 — an empty output is success.

Relay what it printed. On empty output, say the submodules were already correct.

## What it will not do

Explain these when a warning names one — each is a deliberate refusal, not a bug:

- **A populated submodule is never rewound.** `git submodule update` is only run over a top-level
  submodule that is not populated yet. A populated one is only asked to fill in its own nested
  submodules, so local commits inside it survive.
- **An existing submodule branch is never moved.** If the branch already exists it is checked out,
  never reset to the gitlink (`checkout -B` is not used).
- **Nested submodules get no branch.** They are populated and left on their gitlink commit — they
  are vendored third-party trees.
- **Superproject on a detached HEAD** → submodules are populated but not attached; there is no
  branch name to mirror.
- **No `.gitmodules`, no remote, or not a git repository** → silent no-op by design.

## Notes

- A branch that has to be created is based on the **gitlink** — the commit the superproject records
  for that submodule — not on wherever the submodule's own HEAD happens to sit.
- Every warning names the exact `git -C ... ` command to run by hand. Offer it; do not run a
  destructive variant of it unprompted.
