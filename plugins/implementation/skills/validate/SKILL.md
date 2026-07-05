---
name: validate
description: >
  Checks whether a task requirement (bug, story, or general task) has enough information to move
  forward with planning. Use this skill whenever a task requirement, user story, bug report, or
  work item needs to be reviewed for completeness and clarity before planning or implementation.
  Invoke validate when the user says "validate this requirement", "check this requirement", "is
  this ready to implement", "review this story", "validate this bug", or provides a task
  description and wants to know if it's ready to hand off. Requires the task requirement text
  itself — it does not fetch tickets from Jira or any other tracker.
arguments: [task_requirement, output_location]
argument-hint: "[task requirement text] [output location (optional)]"
when_to_use: >
  Also invoke when a requirement seems vague or under-specified before investing time to plan or
  implement it, when the user is unsure a requirement is complete enough to hand off, or when
  they ask "does this have enough detail", "is this ready", or "what's missing here".
context: fork
agent: general-purpose
---

# Validate Skill

You are checking whether a task requirement has enough information to move forward with planning. Your job is to classify the requirement, check it against the relevant completeness criteria, and report the result — either exactly what is missing (if it fails) or confirmation that it's ready (if it succeeds).

## Arguments

Extract from `$ARGUMENTS`:
- `task_requirement` (required) — the task requirement text to validate (bug report, user story, task description). This must be the requirement content itself, not a reference to fetch elsewhere.
- `output_location` (optional) — where to deliver the result: a local file path or directory path. If not provided, report results inline.

## Step 1: Confirm the requirement is present

If `task_requirement` is missing, empty, or too sparse to classify (e.g., a single word or fragment with no discernible subject), this is a **fatal error** — do not guess at intent or invent a requirement to validate. Stop and report:

```
## Validation Result: FATAL ERROR

> AI-generated content.

The task requirement is missing or too unclear to evaluate. Provide the requirement text describing what needs to happen (a bug report, user story, or task description).
```

Otherwise, continue to Step 2.

## Step 2: Classify the requirement

Determine which type best describes the requirement:

- **`bug`** — A report of unintended software behavior; something is broken or not working as expected.
- **`story`** — A functional or non-functional change request; a new capability, improvement, or behavioral change.
- **`general_task`** — Anything else: research tasks, configuration work, documentation, tooling, etc.

Use the content and framing of the requirement to decide. When in doubt, prefer the classification that sets the clearest success criteria.

## Step 3: Apply completeness criteria

### For `bug`

A bug report is only actionable once someone else can put themselves in the same situation and see the same problem. Validation **SUCCEEDS** when all three of the following categories are present with sufficient detail:

1. **Pre-condition** — What state the system/tester must be in before starting: environment (OS, browser, version, deployment, tenant), login credentials or test account, and the under-test project, data, or configuration needed to reproduce.
2. **Steps to reproduce (STR)** — The ordered, step-by-step actions that reliably trigger the defect, starting from the pre-condition above.
3. **Assertion** — Both sides of the observed vs. intended behavior:
   - **Expected result**: what should happen (the intended behavior)
   - **Actual result**: what actually happens (the observed behavior)

If any of these three categories is missing or too vague to act on, validation **FAILS**.

### For `story`

Validation **SUCCEEDS** when all of the following are present:

1. **Change description** — The core story, scenario, goal, or user experience being targeted. This may include references to images, videos, design files, or external documents.
2. **Definition of done** — Both of:
   - **Acceptance Criteria**: specific, verifiable conditions that must be met
   - **Scope**: what is in scope and (if relevant) what is explicitly out of scope

If either of these is missing or too vague to evaluate, validation **FAILS**.

### For `general_task`

Validation **SUCCEEDS** when all of the following are present:

1. **Mission / objective** — What the task is trying to achieve and why it matters.
2. **Definition of done** — Both of:
   - **Acceptance Criteria**: how success will be verified
   - **Scope**: what is in scope and (if relevant) what is explicitly out of scope

If either of these is missing or too vague to evaluate, validation **FAILS**.

## Step 4: Produce the output

### If validation FAILS

Report clearly and concisely what is missing or insufficiently specified. Name the missing element(s) using the terminology above (e.g., "Pre-condition is missing — no environment or test account specified", "Steps to reproduce are absent", "Actual result is not stated", "Acceptance Criteria are absent"). Do not attempt to infer or fill in missing information — the goal is to surface the gap so the author can address it.

Format:

```
## Validation Result: FAILED

> AI-generated content.

**Type**: <bug | story | general_task>

**Missing or insufficient information:**
- [Element 1]: <brief explanation of what is missing or why it is insufficient>
- [Element 2]: ...
```

### If validation SUCCEEDS

Report the result — there is no enrichment step. The requirement is already complete enough to hand off as-is.

Format:

```
## Validation Result: PASSED

> AI-generated content.

**Type**: <bug | story | general_task>
```

## Step 5: Deliver the output

- If `output_location` is provided (a local file or directory path): write the output to that location using available file tools, and also give the caller a brief summary confirming what was done and where the result was saved.
- If `output_location` is not provided: report the full output inline to the caller.
