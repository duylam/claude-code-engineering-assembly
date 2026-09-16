# Git Plugin

Repo-wide git housekeeping at session start, for **any** git repository.

Two jobs, both running the moment `claude` launches:

1. **Fetch and prune.** Before the first prompt, the plugin fetches every branch
   and every tag from the remote and prunes stale branch and tag refs, so the
   local remote-tracking refs are aligned with the remote. This is what a session
   should start from — including a `claude remote-control --spawn worktree`
   worktree cut from a possibly-stale remote-tracking ref.

2. **Feature-branch protection.** A `PreToolUse` hook blocks any `git push` that
   would update `main` or `master` directly on the remote — the same guard a
   GitHub branch-protection rule gives you. The agent sees a clear denial telling
   it to push a non-`main`/`master` branch (same local branch name recommended)
   and open a pull request.

The fetch runs **synchronously** at `SessionStart`, so the agent only starts once
it finishes.

## Guarantees

- **Does nothing outside a git repo**, or in a repo with no remote.
- **Never fails a session.** A fetch error becomes a recorded warning, not a
  failed launch. The hook always exits 0.
- **Opt-out:** set `GIT_PLUGIN_DISABLE` to any non-empty value to turn every hook
  into a no-op. Unset/empty means enabled (the default).
- **No timeout on the work itself.** The `SessionStart` hook is given a 2-minute
  timeout because Claude Code requires one; if the fetch is killed at that limit,
  the session still starts.

## Launch status

Only the **latest** status is kept, per session, under the OS temp directory
(`${TMPDIR:-/tmp}/claude-git/<session-id>/git.status`). It is not shown to the
agent. To read it yourself, run the read-only, human-only skill:

```
/git:launch-status
```

## Coordination with git-autosync

The `git-autosync` plugin does its attach-only sync **without fetching** — it
relies on the refs this plugin refreshes. Because both plugins run their
`SessionStart` hooks in parallel with no ordering guarantee, this plugin writes
`fetch-started`/`fetch-done` marker files in the shared session directory, and
`git-autosync` waits on them before it attaches. `fetch-done` is always written,
even on failure or timeout, so `git-autosync` never waits longer than it must.
