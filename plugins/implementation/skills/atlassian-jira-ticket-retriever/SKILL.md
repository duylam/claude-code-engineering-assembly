---
name: atlassian-jira-ticket-retriever
description: >
  Fetches one or more JIRA tickets by URL and saves structured content (title, body, comments,
  attachments) to a local temp directory. Use when ticket content needs to be retrieved for
  validation, enrichment, or planning workflows. Invoke this skill whenever JIRA ticket URLs
  appear in the input and their content must be fetched for downstream processing.
arguments: [jira_ticket_urls]
argument-hint: "[one or more JIRA ticket URLs]"
when_to_use: >
  Invoke when JIRA ticket URLs need to be fetched and their content extracted for downstream
  processing — validation, enrichment, or planning. Also invoke when the user says "fetch these
  tickets", "get ticket details", "pull JIRA content", or when another skill needs ticket data
  as input.
context: fork
agent: general-purpose
---

# JIRA Ticket Retriever

You fetch JIRA tickets and save their content to a structured local directory.

## Input

From `$ARGUMENTS`, extract one or more JIRA ticket URLs (required). Each URL follows the pattern
`https://<domain>.atlassian.net/browse/<TICKET-ID>` or similar JIRA URL formats. If no valid
JIRA ticket URLs are found, report a fatal error and stop.

## Output Directory Structure

Unless an explicit artifact storage location is provided in the instructions, use the
**launching directory** (the working directory from which this skill was invoked) as the
base. Create a parent directory under the base using this format:

```
<base>/${CLAUDE_SESSION_ID}-<timestamp>/
```

Where `<timestamp>` is the current Unix epoch in seconds. Under this parent, create one
subdirectory per ticket:

```
<base>/${CLAUDE_SESSION_ID}-<timestamp>/
  |- <TICKET-ID-1>/
  |   |- content.md
  |   |- <attachment-file-1>
  |   |- <attachment-file-2>
  |- <TICKET-ID-2>/
  |   |- content.md
  |   |- ...
```

Determine the launching directory by running `pwd` before creating any files.

## Fetching Procedure

For each JIRA ticket URL:

### Step 1 — Extract ticket ID

Parse the ticket ID from the URL (e.g., `DT-123` from `https://....atlassian.net/browse/DT-123`).

### Step 2 — Fetch ticket data

Use the available JIRA tools/integrations to retrieve the ticket. Fetch these fields:

- **ID** — the ticket key (e.g., `DT-123`)
- **Title** — the summary field
- **Body** — the full description
- **Type** — issue type (bug, task, story, epic, etc.)
- **Status** — current status (e.g., To Do, In Progress, Done)
- **Reporter** — display name of the reporter
- **Assignee** — display name of the assignee (or "Unassigned")
- **Parent** — parent issue name/key if it exists (or "None")
- **Active Sprint** — name of the active sprint the ticket belongs to (or "None")

### Step 3 — Fetch comments

Retrieve all comments on the ticket. Comments may be nested or threaded — flatten them into
a single list and sort by created time in **descending** order (latest comment at top).

For each comment, capture:
- **Creator** — display name of the person who posted the comment
- **Created** — the timestamp when the comment was created
- **Body** — the full comment content

### Step 4 — Write content.md

Write a `content.md` file in the ticket's subdirectory with this structure:

```markdown
# <TICKET-ID>: <Title>

| Field         | Value              |
|---------------|--------------------|
| **ID**        | <ticket-id>        |
| **Type**      | <issue-type>       |
| **Status**    | <status>           |
| **Reporter**  | <reporter-name>    |
| **Assignee**  | <assignee-name>    |
| **Parent**    | <parent-key-name>  |
| **Sprint**    | <sprint-name>      |

## Description

<full description body>

## Comments

### Comment by <Creator> — <Created timestamp>

<comment body>

---

### Comment by <Creator> — <Created timestamp>

<comment body>

---

(repeat for all comments, sorted latest first)
```

If there are no comments, write `_No comments._` under the Comments heading.

### Step 5 — Fetch attachments

Download all attachment files for the ticket into the ticket's subdirectory alongside
`content.md`, preserving the original filename. There are two sources of attachments — collect
both, then deduplicate by filename before downloading:

1. **Ticket attachments list** — retrieve the full list of attachments from the ticket's
   `fields.attachment` array (returned by the JIRA API). Each entry includes the filename and
   a direct download URL (`content` field).
2. **Inline references in description and comments** — identify any files embedded inline in
   the description or comments (e.g. `!filename.png!`, `[filename|^filename]`, or media nodes)
   that may not appear in the attachments list. Resolve their direct download URL from the
   ticket data.

For each unique attachment, follow this two-step procedure:

1. **Determine the download URL** — resolve the direct download URL for the attachment from
   the ticket data (the URL that points to the raw file, not the Jira viewer page).

2. **Invoke the download script** — run:
   ```
   bash ${CLAUDE_SKILL_DIR}/download-attachment-file.sh \
     --out-file-path <absolute path under the ticket dir to save the file> \
     --in-attachment-download-url <download URL from step 1>
   ```
   Read the stdout of the invocation for the result. A successful download prints
   confirmation text; an error prints the failure reason.

If an attachment cannot be downloaded, log the error output as a warning and continue
processing the remaining attachments.

## Final Report

After processing all tickets, report back to the caller:

1. **The list of absolute paths** to each `content.md` file created
2. **A note** about any attachments saved in each ticket's directory
3. **Warnings or failures** for any tickets that could not be fetched or attachments that
   could not be downloaded

If all tickets fail to fetch, report a fatal error.
