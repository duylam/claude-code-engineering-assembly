---
name: launch-status
description: This skill should be used when the operator asks "what did the git plugin do at launch", "show the git launch status", "did the fetch run", "why are my remote refs stale", or wants to see the git plugin's most recent SessionStart result. Reports the latest fetch/prune status and any warnings recorded for this session by the git plugin. Read-only, human-invoked only.
disable-model-invocation: true
allowed-tools: Bash(cat *)
---

# Git plugin launch status

The git plugin fetches every branch and tag and prunes stale refs at
`SessionStart`, then records the result as this session's latest status. This
skill prints that record.

## Latest status

```!
cat "${TMPDIR:-/tmp}/claude-git/${CLAUDE_SESSION_ID}/git.status" 2>/dev/null \
  || echo "git plugin: no status recorded this session (plugin disabled, not a git repo, no remote, or the fetch has not run yet)."
```

Report the block above verbatim. It is the git plugin's latest launch status for
this session: `fetched and pruned ...` on success, or `Warning: ...` lines when a
fetch failed. Empty output means the fetch succeeded silently with nothing to
report. Do not re-run the fetch or take any action — this skill only reports.
