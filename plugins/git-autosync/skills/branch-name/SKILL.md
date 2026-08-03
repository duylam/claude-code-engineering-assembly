---
name: branch-name
description: Put the superproject and every top-level submodule on one named branch, creating it at the current HEAD or switching to it when it already exists. Infers a short name from the conversation when none is given. Use to give a session's `worktree-*` branch a real name before committing.
argument-hint: "[branch-name]"
allowed-tools: Bash
disable-model-invocation: true
---

# Branch Name

Put this working tree **and every populated top-level submodule** on a single named branch, so
commits on both sides carry the same label.

The usual moment for this: a session started on an auto-generated `worktree-a3f19c` branch, turned
into real work, and now wants a name that says what the work is.

## Getting the name

**When the user passed an argument, use it verbatim.** Do not tidy it, expand it, or "improve" it.

**When no argument was passed, infer one** from what this session has been doing:

- 2–4 words, kebab-case, lowercase (`add-oauth-login`, `fix-stale-worktree-sync`)
- describe the change, not the file touched
- no ticket numbers unless the user mentioned one

**State the name you chose in your reply before running the command**, in one short line — the
user gets no other chance to correct it.

## Run it

```bash
bash "${CLAUDE_PLUGIN_ROOT:-${CLAUDE_SKILL_DIR}/../..}/hooks/branch-name.sh" \
    -C "${CLAUDE_PROJECT_DIR:-$PWD}" "<the-name>"
```

## What it does

Per tree — the superproject first, then each populated top-level submodule:

- the branch does not exist → `git checkout -b <name>` at whatever HEAD is, so **uncommitted work
  comes along untouched**
- the branch already exists → `git checkout <name>`, never moved (`checkout -B` is not used)

## Reporting the result

One line per tree it changed, `Warning: ...` for anything a human has to resolve, and **nothing at
all when everything was already on that name**.

- **Exit non-zero** means the *superproject* could not be switched — so nothing meaningful
  happened. The usual cause is a local change that would be overwritten by the checkout; relay the
  warning and offer to commit or stash it.
- A **submodule** that refuses is a warning, not a failure: the remaining submodules are still
  done. The warning names the exact `git -C ... checkout` command.

## What it will not do

- **Does not delete or rename the branch it left.** That branch still points at the same commit,
  and `git checkout -` goes straight back to it.
- **Does not touch the remote.** Nothing is pushed, nothing is deleted upstream. Offer to push
  separately if the user wants the branch published.
- **Does not move an existing branch.** A name already in use keeps its commits.
- **Does not clone anything.** An unpopulated submodule is skipped; `/git-autosync:submodules-sync`
  is what fills those in.

## Notes

- **This is how work outlives the session.** Session teardown (`worktree-cleanup.sh`) deletes the
  branch the worktree is on only when that name starts with `worktree-`. Once this skill has moved
  the tree onto a real name, teardown reports `left branch <name> alone` and the commits survive.
  Naming a branch is therefore also the way to keep it.
- The old `worktree-*` branch stays behind, pointing at the commit the new branch was cut from.
  Teardown no longer sees it (it looks only at the branch the worktree is *currently* on), so it
  is not deleted either. Mention it if the user cares about tidiness: `git branch -D worktree-...`.

