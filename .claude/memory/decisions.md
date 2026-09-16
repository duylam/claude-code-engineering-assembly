
## DEC-2026-08-13-01 · 2026-08-13T16:55:00+07:00 · status=accepted
Title: Strip git-autosync to SessionStart merge-sync only
Work: git-autosync-strip
Session: unknown
Tags: git-autosync, plugin, scope
Refs: LOG-2026-08-13-01
Supersedes: -

### Consideration
- git-autosync carried machinery for the `claude --worktree` path, worktree teardown, user-scope plugin provisioning, and remote `worktree-*` branch reaping. The stated need is only to keep a `claude remote-control` worktree current with upstream on session start. `claude remote-control --spawn worktree` builds and removes its own worktree and never fires WorktreeCreate/WorktreeRemove, so SessionStart is the only hook that runs for that path.

### Decision
- Reduce the plugin to a single SessionStart (startup|resume) hook that runs a non-destructive merge sync (branch level with remote default, submodules populated and attached). Delete the WorktreeCreate, WorktreeRemove, and SessionEnd hooks plus the bootstrap SessionStart entry, their five scripts, four tests, and dead shared helpers. Keep the git-sync (merge/reset, human-only) and branch-name skills and the GIT_AUTOSYNC_DISABLE off switch. Bump version 0.8.0 → 0.9.0.

### Rationale
- The removed features were unused on the only supported path and added surface area, dead code, and docs to maintain. Merge stays the sole hook-reachable mode so an unattended session never hits a destructive path; reset remains available on demand through the skill.

### Alternatives
- Keep the WorktreeCreate hook for the `claude --worktree` path — rejected; that path still syncs via its own SessionStart, so the extra hook was redundant.
- Keep worktree teardown and remote-branch reaping — rejected; remote-control manages its own worktree lifecycle, and the user accepted that pushed `worktree-*` branches accumulate on origin.

## DEC-2026-09-08-01 · 2026-09-08T10:50:24+07:00 · status=accepted
Title: git-autosync becomes merge-only; reset mode removed
Work: git-autosync-recap
Session: unknown
Tags: git-autosync, plugin
Refs: LOG-2026-09-08-01
Supersedes: -

### Consideration
- The three slash commands are being removed. The destructive `reset` sync mode was only reachable through those commands (and raw CLI), and is not part of the must-have session-start state (merge + attach). Keeping it would leave a documented destructive path with no Claude-facing entry point.

### Decision
- Remove `reset` mode entirely. The plugin (hook + both workers) now only ever merges. Reset code, `--mode` parsing, the reset preflight (`assert_clean_recursive`), and reset-focused tests are deleted.

### Rationale
- Operator explicitly chose merge-only. It makes the plugin's surface exactly the must-have state, removes dead/unreachable destructive code, and simplifies the workers and tests. Direct-CLI reset was the only thing lost, and was not requested.

### Alternatives
- Keep reset as a direct-CLI-only capability — rejected by the operator; would preserve a larger, partly-dead surface for a power-user path nobody asked to retain.

## DEC-2026-09-16-01 · 2026-09-16T14:23:33+07:00 · status=accepted
Title: Enforce fetch-before-attach with a marker barrier, not hook ordering
Work: git-plugin-split
Session: c77bd111-c06b-46d2-918f-92551f2db204
Tags: git, hooks, concurrency
Refs: LOG-2026-09-16-01
Supersedes: -

### Consideration
- git-autosync must attach using freshly-fetched refs, but the fetch now lives in a separate `git` plugin. Both hooks fire at SessionStart.

### Decision
- The `git` plugin writes `fetch-started` on entry and always writes `fetch-done` on exit (EXIT/TERM/INT trap). git-autosync waits up to 5s for `fetch-started` (absent => git plugin not participating, proceed at once), then up to 4min for `fetch-done`, then proceeds regardless. Markers live in a shared per-session OS-temp dir.

### Rationale
- Per official docs, no plugin hook fires before SessionStart on a normal launch (only `Setup`, gated behind --init/--init-only/--maintenance), and same-event hooks across plugins run in parallel with no ordering guarantee. A marker barrier is the only way to guarantee ordering. Always-write-done + a bounded wait guarantee git-autosync never hangs, even if the fetch fails or is killed at its 120s timeout.

### Alternatives
- Rely on hook ordering / a pre-SessionStart hook — rejected: no such hook exists on normal launches.
- No barrier, accept the race — rejected: git-autosync could attach against stale refs on a fresh launch.
- Merge both plugins so fetch and attach share one hook — rejected: user explicitly wants them separate (git plugin applies to any repo; autosync is worktree/submodule-specific).
