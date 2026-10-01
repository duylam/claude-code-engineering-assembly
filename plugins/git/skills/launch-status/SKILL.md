---
name: launch-status
description: This skill should be used when the operator asks "what did the git plugin do at launch", "show the git launch status", "did the fetch run", "did the branch attach", "why are my remote refs stale", "why is my submodule detached", or wants to see the git plugin's most recent SessionStart result. Reports the latest fetch/prune and worktree-attach status and any warnings recorded for this session. Read-only, human-invoked only.
disable-model-invocation: true
allowed-tools: Bash(cat *)
---

# Git plugin launch status

At `SessionStart` the git plugin fetches every branch and tag and prunes stale
refs, then fast-forwards the branch this tree is on to the remote default and
attaches every top-level submodule. It records the combined result as this
session's latest status. This skill prints that record.

## Latest status

```!
cat "${TMPDIR:-/tmp}/claude-git/${CLAUDE_SESSION_ID}/git.status" 2>/dev/null \
  || echo "git plugin: no status recorded this session (both steps disabled, not a git repo, no remote, or the hook has not run yet)."
```

Report the block above verbatim. It is the git plugin's latest launch status for
this session: `fetched and pruned ...` for the fetch step, `fast-forwarded ...` /
`initialized ...` notes for the attach step, or `Warning: ...` lines when
something failed or needs a human. Empty output means the hook ran with nothing
to report. Do not re-run the fetch or take any action — this skill only reports.
