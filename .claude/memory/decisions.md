
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
