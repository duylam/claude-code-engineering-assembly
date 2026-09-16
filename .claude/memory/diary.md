
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

## LOG-2026-09-16-01 · 2026-09-16T14:23:17+07:00 · commit-id=69b4b55
Work: git-plugin-split
Phase: implement
Session: c77bd111-c06b-46d2-918f-92551f2db204
Tags: git, plugins, hooks, engineering-assembly
Refs: -
Closes: -

### Did
- Created new `git` plugin (plugins/git/, v0.1.0): SessionStart hook fetches every branch+tag and prunes stale branch/tag refs (`git fetch --all --tags --prune --prune-tags`), always writes fetch-started/fetch-done barrier markers (EXIT/TERM/INT trap) under `${TMPDIR}/claude-git/<session_id>/`, persists latest status, silent to agent. Moved protect-branches.sh (main/master push block) here, opt-out `GIT_PLUGIN_DISABLE` (non-empty disables). Added read-only `launch-status` skill, README, and tests (fetch-prune, barrier, protect-branches, disable).
- Slimmed `git-autosync` (v0.10.1 -> 0.11.0): removed superproject fetch + branch protection; now network-free attach-only. ff-only reconcile of current branch to remote default (diverged left as is), gated on attached HEAD (detached = silent no-op); submodules populated one level (dropped --recursive) + ff-only to gitlink. session-start waits on git plugin's fetch barrier (5s grace / 4min bound, env-overridable), persists per-session status, injects one attached-mode summary line only when the pass runs. Opt-out now non-empty (dropped "0=enabled"). Hook timeout 300s, removed PreToolUse. Added `launch-status` skill; rewrote README; updated marketplace.json (+git entry, rewrote git-autosync desc).
- Rewrote/added tests for both plugins; both suites pass (git: 31 checks, git-autosync: 59 checks). Full run: SUITE PASSED for both.
### Why
- User asked to split git-autosync: repo-wide fetch/prune + push protection belong in a general `git` plugin (any repo), while worktree/submodule attach stays in git-autosync. No plugin hook runs before SessionStart, so cross-plugin ordering (fetch before attach) is enforced via a marker-file barrier rather than hook scheduling.
### Next
- [NEXT-2026-09-16-01] Open PR in the claude-code-engineering-assembly submodule repo; after merge, bump the superproject submodule pointer directly (no superproject PR).
- [NEXT-2026-09-16-02] Manual smoke test in a real submodule-bearing clone: verify fetch+prune, main-push denial, attached-mode summary, both /launch-status skills, and barrier markers.

## LOG-2026-09-16-02 · 2026-09-16T14:40:40+07:00 · commit-id=01496f7
Work: git-plugin-split
Phase: implement
Session: c77bd111-c06b-46d2-918f-92551f2db204
Tags: git, hooks
Refs: DEC-2026-09-16-01
Closes: -

### Did
- git-autosync session-start.sh: dropped the `systemMessage` field from the SessionStart JSON so the attached-mode git-state summary reaches the LLM only via `hookSpecificOutput.additionalContext` (the model-visible channel), not the human terminal. Confirmed via docs: additionalContext/plain stdout is added to model context on SessionStart; systemMessage is human-terminal only. Suite still passes; emitted JSON now carries only additionalContext.
### Why
- Agreed design is AI-only (not human) for that summary; systemMessage duplicated it into the human terminal, contradicting that.
### Next
- [NEXT-2026-09-16-03] (tracked already) superproject pointer bump after PR #9 merge; manual smoke test in a real clone.
