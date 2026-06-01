---
name: validate
description: >
  Validates and enriches a task requirement (bug, story, or general task) before implementation begins.
  Use this skill whenever a task requirement, ticket description, user story, bug report, or work item
  needs to be reviewed for completeness and clarity — whether provided as inline text or as a remote URL
  (JIRA ticket, GitHub Issue, etc.). Invoke validate when the user says "validate this ticket",
  "check this requirement", "is this ready to implement", "review this story", "validate this bug",
  or when a task description is provided before planning or implementation. If the requirement is
  sufficiently complete, the skill enriches it with clarifying context, decisions, and rationale.
  If it is fatally incomplete, it reports exactly what is missing so the user knows what to fix.
arguments: [task_requirement, output_location]
argument-hint: "[task description or ticket URL] [output location (optional)]"
when_to_use: >
  Also invoke when a ticket seems vague or under-specified before investing time to plan or
  implement it, when the user is unsure a requirement is complete enough to hand off, or when
  they ask "does this have enough detail", "is this ticket ready", or "what's missing here".
context: fork
agent: general-purpose
---

# Validate Skill

You are validating a task requirement to determine whether it has enough information to move forward with planning and implementation. Your job is to classify the requirement, check it against the relevant completeness criteria, and either report what is missing (if it fails) or enrich it with clarifying context (if it succeeds).

## Arguments

Extract from `$ARGUMENTS`:
- `task_requirement` (required) — the task requirement or description to validate. Can be inline text (bug report, user story, task description) or a remote URL (JIRA ticket, GitHub Issue, etc.).
- `output_location` (optional) — where to deliver the result. Can be a local file path, directory path, or remote URL (e.g., JIRA ticket URL to post as a comment). If not provided, report results inline.

## Step 1: Fetch the requirement

If `task_requirement` is a URL (JIRA ticket, GitHub Issue, or similar), fetch its contents using available tools (e.g., WebFetch, MCP integrations). Extract the full description, acceptance criteria, comments, and any attached media references. If it is inline text, use it as-is.

## Step 2: Classify the requirement

Determine which type best describes the requirement:

- **`bug`** — A report of unintended software behavior; something is broken or not working as expected.
- **`story`** — A functional or non-functional change request; a new capability, improvement, or behavioral change.
- **`general_task`** — Anything else: research tasks, configuration work, documentation, tooling, etc.

Use the content and framing of the requirement to decide. When in doubt, prefer the classification that sets the clearest success criteria.

## Step 3: Apply completeness criteria

### For `bug`

Validation **SUCCEEDS** when all of the following are present with sufficient detail:

1. **Steps to reproduce (STR)** — A flow that reliably causes the defect, including:
   - Environment (OS, browser, version, deployment, tenant, etc.)
   - Step-by-step actions to trigger the issue
   - Any login credentials, test accounts, or access context needed
   - Any under-test project file, data, or configuration needed to reproduce
2. **Clear problem description** — Both sides of the observed vs. intended behavior:
   - **Expected result**: what should happen
   - **Actual result**: what actually happens

If either of these is missing or too vague to act on, validation **FAILS**.

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

Report clearly and concisely what is missing or insufficiently specified. Name the missing element(s) using the terminology above (e.g., "Steps to reproduce are missing", "Expected result is not stated", "Acceptance Criteria are absent"). Do not attempt to infer or fill in missing information — the goal is to surface the gap so the author can address it.

Format:

```
## Validation Result: FAILED

> AI-generated content.

**Type**: <bug | story | general_task>

**Missing or insufficient information:**
- [Element 1]: <brief explanation of what is missing or why it is insufficient>
- [Element 2]: ...
```

### If validation SUCCEEDS (fully or partially)

Produce an enriched version of the requirement that makes it clearer and less ambiguous for whoever will plan and implement it. Preserve all original intent — your role is to clarify and extend, not to rewrite or contradict.

The enriched output must include:

1. **Revised / Enriched Requirement** — The original requirement restated with any ambiguities resolved, implicit assumptions made explicit, and relevant context surfaced. Keep it readable; do not pad unnecessarily.

2. **Consideration, Decision and Rationale** — A section that captures:
   - Key considerations or trade-offs relevant to this task (technical, UX, scope, risk, etc.)
   - Any decisions implied or required by the requirement (e.g., which approach to take, what to prioritize)
   - The rationale behind those decisions

3. **Severity** (for `bug` type only) — Append a severity assessment using this scale:
   - **Critical**: System unusable, data loss, security breach, or complete feature failure with no workaround
   - **High**: Major functionality broken, significant user impact, workaround exists but is painful
   - **Medium**: Partial functionality affected, moderate user impact, reasonable workaround available
   - **Low**: Minor visual or UX issue, minimal user impact, easy workaround

   If the original requirement already includes a severity value, retain it (note it as "original") and only suggest a revised value if you have a strong reason to differ.

Format:

```
## Validation Result: PASSED

> AI-generated content.

**Type**: <bug | story | general_task>

---

## Enriched Requirement

<Revised, clear, and complete version of the requirement>

---

## Consideration, Decision and Rationale

<Bullet points or short paragraphs covering key considerations, implied decisions, and reasoning>

---

## Severity  ← (bug type only)

**Suggested**: <Critical | High | Medium | Low>
**Reason**: <Brief justification>
[**Original** (if present): <original value>]
```

## Step 5: Deliver the output

- If `output_location` is provided:
  - If it is a **local file or directory path**: write the output to that location using available file tools.
  - If it is a **remote URL** (e.g., JIRA ticket): post the output there using available integrations (e.g., add as a comment or update the description field).
  - In both cases, also provide a brief summary to the caller confirming what was done and where the result was sent.
- If `output_location` is not provided: report the full output inline to the caller.
