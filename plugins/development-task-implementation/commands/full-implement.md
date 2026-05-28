---
name: full-implement
description: >
  Runs the full validate → plan → implement pipeline for a development task requirement end-to-end.
  Use when the user wants to take a raw task requirement (inline text or remote URL such as a JIRA
  ticket, GitHub Issue, or Linear item) all the way through validation, planning, and implementation
  in one shot. Invoke when the user says "full implement", "end-to-end implement", "validate and
  implement", or provides a requirement and wants the complete pipeline run without manual steps
  in between.
arguments: [task_requirement, output_location]
---

# Full Implement

You are orchestrating the full development lifecycle for a task: validate → plan → implement. Each stage feeds the next. If any stage reports a fatal blocker, stop and surface it to the user — do not continue downstream.

## Arguments

Extract from `$ARGUMENTS`:
- `task_requirement` (required) — the task requirement or description to process. Can be inline text (bug report, user story, task description) or a remote URL (JIRA ticket, GitHub Issue, etc.).
- `output_location` (optional) — where to deliver intermediate and final outputs. Can be a local file path, directory path, or remote URL. Passed through to each stage that supports it.

## Stage 1 — Validate

Invoke the `development-task-implementation:validate` skill with:
- `task_requirement`: the value from `$ARGUMENTS`
- `output_location`: the value from `$ARGUMENTS` (if provided)

**Blocker check**: if the validate result is `Validation Result: FAILED`, stop here. Surface the full validation output to the user and explain that the requirement must be fixed before planning can proceed. Do not continue to Stage 2.

## Stage 2 — Plan

Take the enriched requirement produced by the `validate` stage (the content under "Enriched Requirement") and use it as `task_requirement` for the `development-task-implementation:plan` skill. Pass `output_location` if provided.

**Blocker check**: if the plan result reports fatal blockers (e.g., missing scope, contradictory constraints, unresolvable ambiguity that prevents a reliable plan), stop here. Surface the full plan output and explain what must be resolved before implementation can begin. Do not continue to Stage 3.

## Stage 3 — Implement

Take the full plan output from Stage 2 and use it as `task_requirement` for the `development-task-implementation:implement` skill.

Report the implementation result inline to the user when complete.
