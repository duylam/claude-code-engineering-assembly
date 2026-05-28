# Development Task Implementation Plugin

A structured workflow for taking a software development task from raw requirement to committed code — validate completeness, decompose into a plan, then coordinate implementation via subagents.

## Overview

Development tasks fail most often not because the code is wrong, but because teams skip steps: they implement before the requirement is clear, plan before they know what "done" means, or ship a giant diff that's impossible to review. This plugin enforces a sequence:

```
validate → plan → implement
```

`/validate` checks whether a requirement is ready to act on and enriches it. `/plan` decomposes the requirement into an ordered, dependency-aware task list. `/implement` coordinates execution via subagents and keeps the history clean with frequent commits. Each step can be invoked independently — run all three in sequence or jump straight to the one you need.

All three skills accept inline text or remote URLs (JIRA tickets, GitHub Issues, Linear items, etc.).

## Skills

### `/validate [task_requirement] [output_location?]`

Classifies a requirement as `bug`, `story`, or `general_task`, then checks it against the relevant completeness criteria.

- **On failure**: reports exactly which required elements are missing (e.g., "Steps to reproduce are absent", "Acceptance Criteria not stated") so the author knows what to fix.
- **On success**: produces an enriched version of the requirement with ambiguities resolved, plus a Consideration/Decision/Rationale section. For bugs, also appends a Severity assessment.

| Argument | Required | Description |
|---|---|---|
| `task_requirement` | yes | Inline text or remote URL (JIRA, GitHub Issue, etc.) |
| `output_location` | no | File path, directory, or remote URL. Defaults to inline if omitted. |

Completeness criteria by type:
- **bug** — steps to reproduce (environment, actions, credentials, test file) + expected vs. actual result
- **story** — change description + acceptance criteria + scope
- **general_task** — mission/objective + acceptance criteria + scope

### `/plan [task_requirement] [output_location?]`

Reads a requirement and produces an ordered, dependency-aware task list ready for implementation.

- **On success**: a markdown table of tasks (id `NN-slug`, description, `blocked_by`) plus a Consideration/Decision/Rationale section covering key planning choices.
- **On failure**: a `Plan: BLOCKED` report with the fatal blockers listed — no partial plan is produced.

| Argument | Required | Description |
|---|---|---|
| `task_requirement` | yes | Inline text or remote URL |
| `output_location` | no | Remote URL only (JIRA, GitHub Issue, etc.). Defaults to inline if omitted. |

Runs in a dedicated Plan subagent (`fork: true`, `agent: Plan`).

### `/implement [task_requirement]`

Coordinates full implementation of a task. Acts as a coordinator: spawns investigator, builder, and reviewer subagents for focused units of work; integrates their output; commits after each meaningful change; and produces a Decision Log at the end.

- Only creates a Pull Request if the task **explicitly requests one**.
- If `task_requirement` is a remote URL, appends the Decision Log back to that item as a comment.

| Argument | Required | Description |
|---|---|---|
| `task_requirement` | yes | Inline text or remote URL |

## Installation

```
/plugin install development-task-implementation@engineering-assembly
```

## Recommended workflow

```
/validate "https://jira.example.com/browse/PROJ-123"
/plan "https://jira.example.com/browse/PROJ-123"
/implement "https://jira.example.com/browse/PROJ-123"
```

Or pass inline text directly:

```
/validate "Users report 500 errors when uploading files over 10MB on Safari. Expected: upload succeeds. Actual: server returns 500."
```
