---
name: launch-status
description: This skill should be used when the operator asks "what did git-autosync do at launch", "show the git-autosync launch status", "did the branch attach", "why is my submodule detached", or wants to see git-autosync's most recent SessionStart result. Reports the latest attach/submodule status and any warnings recorded for this session. Read-only, human-invoked only.
disable-model-invocation: true
allowed-tools: Bash(cat *)
---

# git-autosync launch status

At `SessionStart`, git-autosync fast-forwards the branch this tree is on to the
remote default branch and attaches every top-level submodule, then records the
result as this session's latest status. This skill prints that record.

## Latest status

```!
cat "${TMPDIR:-/tmp}/claude-git/${CLAUDE_SESSION_ID}/git-autosync.status" 2>/dev/null \
  || echo "git-autosync: no status recorded this session (plugin disabled, not a git repo, no remote, detached HEAD, or the hook has not run yet)."
```

Report the block above verbatim. It is git-autosync's latest launch status for
this session: `fast-forwarded ...` / `initialized ...` notes on success, or
`Warning: ...` lines when something needed a human. Empty output means the sync
ran with nothing to report. Do not run any git commands — this skill only reports.
