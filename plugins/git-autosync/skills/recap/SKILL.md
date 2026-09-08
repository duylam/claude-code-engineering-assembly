---
name: recap
description: This skill should be used when the operator asks to "recap", "give me a recap", "where are we", "status of this session", "what's the state of my branches and PRs", or "catch me up on this conversation". Reports branch and tracking-remote state (each with its commit id) for the superproject and each top-level submodule, the pull requests for those branches with their status, and a recap of the current conversation reconciled against the work journal's open items.
disable-model-invocation: true
argument-hint: [--fetch]
allowed-tools: Bash(bash *collect-git-state.sh), Bash(RECAP_FETCH=1 bash *collect-git-state.sh)
---

# Recap

Answer one question: **where does this session stand right now?** Three sections,
produced in this order — repository state, pull requests, then the conversation
itself. The first two are collected by a script so they are facts, not recollection;
the third is written from session context and cross-checked against the work journal.

## 1. Collect repository and pull-request state

Run the bundled collector from the project directory:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/collect-git-state.sh
```

It prints one block per repository — the superproject first, then each **top-level**
submodule declared in `.gitmodules` (not recursive):

| Field | Meaning |
|---|---|
| `branch` | Current branch **with its commit id** — `<name> (<sha>)`, or `(detached HEAD at <sha>)` |
| `upstream` | The tracking branch **with its commit id** — `<name> (<sha>)`, or `NONE` when the branch was never pushed |
| `state` | `up to date` / `ahead N (unpushed)` / `behind N (needs pull)` / `diverged: ahead N, behind M` |
| `worktree` | `clean`, or staged/unstaged/untracked counts |
| `prs` | Pull requests whose head is this branch, each tagged `[ready]`, `[draft]`, `[merged]`, or `[closed]` |

Counts are measured against the **last fetch**, and the script says so. When the
answer must reflect the true remote — before deciding whether to push, or when the
operator asks "am I behind?" — re-run with a fetch first:

```bash
RECAP_FETCH=1 bash ${CLAUDE_SKILL_DIR}/scripts/collect-git-state.sh
```

Use that form whenever the invocation mentions fetching or freshness — `/recap and fetch first`,
`/recap --fetch`, "am I behind?" — and otherwise keep the default, which touches no network.

Report degraded fields exactly as printed rather than working around them. Each one
names its own cause and its own fix:

- `upstream: NONE` — the branch has no tracking ref. Ahead/behind is undefined, and
  `git status -sb` would look identical to "nothing to push". The fix is
  `git push -u origin HEAD`.
- `state: unknown (upstream ref … missing locally)` — the remote-tracking ref is
  stale or pruned; re-run with `RECAP_FETCH=1`.
- `prs: unavailable -- …` — `gh` is missing, unauthenticated, or the repo has no
  GitHub remote. State the cause; do not substitute a guess.
- `not initialised` — the submodule is declared but has no checkout.

## 2. Pull the open items from the work journal

Invoke the `work-journal:diary-reader` skill with `--open` for the still-pending
items, scoping to one work item with `--work KEY` when the session had a single
focus.

Report what that skill prints, verbatim. Open items are **derived** — every
`[NEXT-…]` bullet ever written, minus every id named on a `Closes:` line — so they
cannot be obtained by reading `### Next` sections out of `.claude/memory/diary.md`
by hand. Entries whose items were long since finished still carry those bullets.

If the `work-journal` plugin is not installed, say the journal was unavailable and
produce section 3 from session context alone. Do not hand-parse the log as a
fallback.

## 3. Write the conversation recap

From the current session's context, in this order:

1. **Asked** — what the operator set out to do this session, in one line.
2. **Done** — what actually changed, as concrete artifacts: files written, commands
   run and their result, commits made. Name paths.
3. **In flight** — work started and not finished, with what remains.
4. **Blocked / needs a decision** — anything waiting on the operator.
5. **Still open (journal)** — the `--open` items from section 2, marking any that
   this session finished but has **not** yet closed via `--closes`.

Reconcile rather than concatenate: when session work closes a `NEXT-` item, say so
explicitly — that gap is the single thing most likely to corrupt the next clock-in.

After a context compaction, the earlier part of the session may be unavailable.
State that plainly and mark the recap as covering only the retained window; never
reconstruct events from the git log and present them as conversation memory.

## Output shape

Lead with a two-or-three-line summary — branch, its state, and the headline of what
happened — then the detail under `Repository`, `Pull requests`, `Conversation`.
Facts from the script go through unaltered, including the "measured against the last
fetch" caveat when no fetch was run.

## Requirements

- `git` on `PATH`. Override with `GIT_BIN=/path/to/git`.
- `gh` on `PATH` and authenticated, for the pull-request section only; everything
  else works without it. Override with `GH_BIN=/path/to/gh`.

Under a systemd user unit `PATH` is bare and does not include `~/.local/bin`, which
is where both binaries commonly live — the overrides exist for that case. The script
sets `set -uo pipefail` and deliberately **not** `-e`: one broken submodule or one
`gh` failure must cost that section of the report, not the whole run.

## Scope

This skill reports; it does not act. It never fetches unless `RECAP_FETCH=1` is set,
and it never pushes, pulls, commits, or writes a journal entry. Clocking out is the
`work-journal:diary-writer` skill's job, and a recap is not a substitute for it.
