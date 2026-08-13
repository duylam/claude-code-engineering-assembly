
## LOG-2026-08-13-01 · 2026-08-13T16:54:39+07:00 · commit-id=4fa8901
Work: git-autosync-strip
Phase: implement
Session: unknown
Tags: git-autosync, plugin, cleanup
Refs: -
Closes: -

### Did
- Stripped git-autosync down to a single SessionStart merge-sync for the `claude remote-control` worktree path.
- Deleted five hook scripts (on-worktree-create.sh, on-worktree-remove.sh, worktree-cleanup.sh, bootstrap-plugins.sh, on-session-end.sh) and four tests (worktree-lifecycle, bootstrap-plugins, reap-remote-branch, session-end-reason).
- Pruned hooks.json to the lone SessionStart entry; removed dead helpers from lib/git-common.sh (reap_remote_session_branch, worktree_is_registered, branch_in_worktree, SESSION_BRANCH_PREFIX).
- Scrubbed stale references in git-sync.sh, session-start.sh, both SKILL.md files, and README.md; removed all GIT_AUTOSYNC_KEEP_WORKTREE mentions.
- Bumped plugin.json version 0.8.0 → 0.9.0 and rewrote its description.

### Why
- The plugin only needs to keep a remote-control worktree current with upstream on session start; worktree lifecycle, user-scope provisioning, and remote-branch reaping were all out of scope and unused for that path.

### Next
- [NEXT-2026-08-13-01] Merge the branch after review.
