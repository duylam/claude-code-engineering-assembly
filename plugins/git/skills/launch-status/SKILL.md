---
name: launch-status
description: This skill should be used when the operator asks "what did the git plugin do at launch", "show the git launch status", "did the fetch run", "did the branch attach", "why are my remote refs stale", "why is my submodule detached", "which branch am I on", "what commit is main / origin/main", or wants to see the git plugin's most recent SessionStart result. Reports the attached branch and commit ids (superproject, origin/main or origin/master, local main or master, and each top-level submodule), plus the latest fetch/prune and worktree-attach status and any warnings recorded for this session. Read-only, human-invoked only.
disable-model-invocation: true
allowed-tools: Bash(cat *) Bash(bash *collect-refs.sh)
---

# Git plugin launch status

At `SessionStart` the git plugin fetches every branch and tag and prunes stale
refs, levels the local default branch (main/master) to the remote when it is
checked out nowhere, then fast-forwards the branch this tree is on to the remote
default and attaches every top-level submodule. It records the combined result as
this session's latest status. This skill prints that record.

## Current refs

```!
bash "${CLAUDE_SKILL_DIR}/scripts/collect-refs.sh"
```

Report the block above verbatim. It is read live when the skill runs, with no
fetch: the superproject's attached branch and commit id, the commit id of the
remote default branch (`origin/main`, falling back to `origin/master`), the commit
id of the local default branch (`main`, falling back to `master`), and the attached
branch and commit id of each top-level submodule. The remote id is as of the last
fetch, which the git plugin runs at `SessionStart`. Report `detached HEAD`, `none`
and `not initialised` as printed.

## Latest status

```!
cat "${TMPDIR:-/tmp}/claude-git/${CLAUDE_SESSION_ID}/git.status" 2>/dev/null \
  || echo "git plugin: no status recorded this session (both steps disabled, not a git repo, no remote, or the hook has not run yet)."
```

Report the block above verbatim. It is the git plugin's latest launch status for
this session: `fetched and pruned ...` for the fetch step, `fast-forwarded local
<branch> ...` for the local default-branch leveling, `fast-forwarded ...` /
`initialized ...` notes for the attach step, or `Warning: ...` lines when
something failed or needs a human. Empty output means the hook ran with nothing
to report. Do not re-run the fetch or take any action — this skill only reports.
