
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

## LOG-2026-09-08-01 · 2026-09-08T10:50:10+07:00 · commit-id=dea31d8
Work: git-autosync-recap
Phase: implement
Session: unknown
Tags: git-autosync, plugin, recap
Refs: -
Closes: -

### Did
- Removed the git-autosync slash commands (git-sync, branch-name; submodules-sync was already absent) and the branch-name.sh worker with its test.
- Made the plugin merge-only: stripped reset mode from git-sync.sh, ensure-submodules.sh, lib/git-common.sh (MODES/DEFAULT_MODE/parse_mode/assert_clean_recursive/fail_fast/--mode) and their reset-focused tests; renamed test-sync-modes.sh -> test-merge-sync.sh.
- Added the recap skill under plugins/git-autosync/skills/recap/ copied from the remote-control template; enhanced collect-git-state.sh to print local branch and tracking-remote commit ids.
- Updated README.md, plugin.json (0.9.0 -> 0.10.0), and the marketplace.json entry.
- Verified: test suite SUITE PASSED, JSON valid, disable switch no-op, recap collector shows commit ids across superproject + submodules.

### Why
- Requirement: plugin should do exactly the must-have session-start state (up to date with remote + attached branch across superproject and submodules), drop the three slash commands, remove anything no longer aligned, and ship a recap skill reporting branch/tracking/PR state with commit ids. Operator chose merge-only, so reset (only reachable via the removed slash commands) became dead and was removed.

### Next
- [NEXT-2026-09-08-01] Open PR in the claude-code-engineering-assembly submodule (base main); then push the superproject gitlink bump directly.
