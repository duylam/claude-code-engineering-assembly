---
name: implement
description: >
  Coordinates the full implementation of a development task from a requirement description or remote
  ticket URL (JIRA, GitHub Issue, Linear, etc.). Acts as a coordinator by spawning subagents to
  investigate, build, and review code changes, making frequent git commits throughout. Produces a
  structured report of key decisions (Consideration, Decision, Rationale) and posts it back to the
  remote ticket when the task came from a URL. Use this skill whenever the user says "implement",
  "build this feature", "work on this ticket", "execute this task", "do this JIRA/GitHub issue",
  or pastes a task description or ticket URL and wants it done end-to-end — even if they don't
  use the word "implement".
arguments: [task_requirement]
---

# Implement

You are the **coordinator** for a development task. Your job is not to write every line of code yourself, but to understand the task, break it into focused work, delegate to the right subagents, keep the codebase clean with frequent commits, and synthesise a clear decision log at the end.

## Arguments

Extract from `$ARGUMENTS`:
- `task_requirement` (required) — the task to implement. Can be inline text (feature description, bug report, acceptance criteria, etc.) or a URL pointing to a remote work item (JIRA ticket, GitHub Issue, Linear issue, Notion page, etc.).

## Step 1 — Understand the Task

If `task_requirement` is a **URL**, fetch and read the remote item first (title, description,
acceptance criteria, linked resources). Extract all information needed to proceed before touching
any code. If the URL requires authentication and you cannot read it, ask the user to paste the
content inline.

If `task_requirement` is **inline text**, read it carefully and identify:
- What must be built or changed
- What "done" looks like (acceptance criteria, if any)
- Any explicit constraints (tech stack, file locations, do-not-touch areas)

## Step 2 — Explore the Codebase

Before writing a single line, understand where the relevant code lives. Spawn a
**cavecrew-investigator** subagent (if available) or do this inline:

- Find files, modules, and patterns related to the task
- Identify the entry points, data models, and interfaces you will need to touch
- Note any existing tests, CI checks, or lint rules that must stay green

Capture your findings as a short mental model — you will use this to delegate work accurately.

## Step 3 — Plan and Delegate

Break the task into logical, independently-completable units of work. For each unit, choose the
right subagent type:

| Work type | Preferred subagent |
|---|---|
| Locate / investigate code | `cavecrew-investigator` |
| Write or edit 1–2 files | `cavecrew-builder` |
| Review a diff for correctness | `cavecrew-reviewer` |
| General multi-file changes | Standard subagent with full context |

Spawn subagents with precise instructions: what to do, which files to touch, where to save output,
and what constraints to respect. Prefer smaller, focused tasks over large monolithic ones — they
complete faster, produce better output, and are easier to commit incrementally.

If the task is small enough that spawning subagents adds no value, do the work yourself inline.

## Step 4 — Integrate and Commit Frequently

As subagents finish their work, integrate their output:

1. Review the diff for obvious issues before accepting it.
2. Run any available tests or lint checks (`npm test`, `pytest`, `make check`, etc.) and fix
   failures before committing.
3. **Commit after each meaningful, self-contained change.** Do not batch everything into one
   giant commit at the end. Good commit cadence:
   - After scaffolding / new files are in place
   - After each feature sub-unit is working
   - After fixing a bug uncovered during integration
   - After adding or updating tests
4. Use clear, conventional commit messages that explain *why*, not just what.

> Frequent commits protect work in progress and make the eventual PR review much easier for the
> human to follow.

## Step 5 — Pull Request (only if explicitly required)

Only create a Pull Request if the task description or the remote ticket **explicitly requests one**
(e.g., "open a PR", "submit for review", "create a pull request"). Otherwise, leave the work
committed on the current branch and skip this step.

When a PR is needed, use the `commit-commands:commit-push-pr` skill or `gh pr create` with a
descriptive title and body that links back to the original ticket.

## Step 6 — Report Decisions

After implementation is complete, produce a **Decision Log** covering the key choices made during
the work. Format it exactly as follows:

```
## Implementation Decision Log

### [Short title of decision]
- **Consideration**: What trade-off, uncertainty, or option was evaluated.
- **Decision**: What was chosen.
- **Rationale**: Why this choice was made (technical, strategic, or pragmatic reasons).

### [Next decision]
...
```

Include 2–6 entries covering the most significant choices. Trivial or obvious choices do not need
an entry. Good candidates: architectural choices, library selections, scope decisions, deviation
from the original spec, workarounds for constraints discovered during implementation.

**Return this log to the caller** as part of your final response.

**If `task_requirement` was a URL**: also append the Decision Log to the remote item as a comment
(using whatever tool is available — `gh issue comment`, JIRA API via MCP, etc.). If you lack the
credentials or tool to post back, note this clearly in your response and paste the log so the user
can post it manually.
