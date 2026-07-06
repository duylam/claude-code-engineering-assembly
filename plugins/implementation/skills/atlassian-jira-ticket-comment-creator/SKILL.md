---
name: atlassian-jira-ticket-comment-creator
description: >
  Posts a comment to a JIRA ticket, optionally uploading file attachments and replacing
  placeholders in the comment with uploaded attachment references. Use when feedback,
  enrichment results, validation output, or any structured content needs to be posted
  as a comment on a JIRA ticket.
arguments: [jira_ticket_url, comment_content, file_paths]
argument-hint: "[JIRA ticket URL] [comment content] [file paths (optional)]"
when_to_use: >
  Invoke when a comment needs to be posted to a JIRA ticket — especially when the comment
  includes file attachments like images or documents that need to be uploaded and referenced.
  Also invoke when the user says "post to JIRA", "comment on this ticket", "send feedback
  to the ticket", or when another skill needs to deliver output as a JIRA comment.
context: fork
agent: general-purpose
---

# JIRA Ticket Comment Creator

You post a comment to a JIRA ticket, handling file uploads and placeholder replacement.

## Input

Extract from `$ARGUMENTS`:

1. **jira_ticket_url** (required) — the JIRA ticket URL to post the comment on. Extract the
   ticket ID from the URL (e.g., `DT-123` from `https://....atlassian.net/browse/DT-123`).
2. **comment_content** (required) — the comment body in markdown format. May contain
   attachment placeholders like `![description](attachment:filename.png)` or
   `[filename](attachment:filename.png)` that reference files to be uploaded.
3. **file_paths** (optional) — one or more local file paths to upload as ticket attachments.
   These may be binary files (images, screenshots, PDFs, etc.) that are intended to appear
   visually inline within the comment, not just as downloadable attachments.

If `jira_ticket_url` or `comment_content` is missing, report a fatal error and stop.

## Procedure

### Step 1 — Upload attachments (if files provided)

If `file_paths` are provided, extract the JIRA site URL from `jira_ticket_url`
(e.g., `https://yourname.atlassian.net/` from `https://yourname.atlassian.net/browse/DT-123`).

For each file path:

1. Verify the file exists locally before attempting upload.
2. **Invoke the upload script** — run:
   ```
   bash ${CLAUDE_SKILL_DIR}/upload-file-to-attachment.sh \
     --jira-site-url <jira-site-url> \
     --file-path <absolute path to the file> \
     --ticket-key <ticket-key>
   ```
   Read the stdout of the invocation for the result. A successful upload prints the JSON
   response from JIRA. Extract the uploaded `filename` with:
   ```bash
   echo '<response>' | jq -r '.[0].filename'
   ```
3. If any upload fails, log a warning with the filename and the error output — continue with
   remaining files.

### Step 2 — Embed uploaded files in the comment body

For each successfully uploaded file, ensure it is referenced in the comment body so that
JIRA renders it inline rather than just listing it as a separate attachment:

- **If the comment body already contains a placeholder** for this file (pattern:
  `attachment:<filename>`) — replace it with the JIRA inline syntax for that file type.
  For images: `!filename.png!` (Jira wiki markup). For non-image files: `[filename|^filename]`.
- **If the comment body does NOT contain a placeholder** for this file — automatically
  append an inline reference at the end of the comment body. For images use `!filename!`;
  for non-image binaries use `[filename|^filename]`. This ensures the file is visible to
  readers without them having to navigate to the attachments tab.

If a placeholder references a file that was not uploaded (due to failure or absence), leave
the placeholder as-is and add a warning note at the end of the comment.

### Step 3 — Format for JIRA

Ensure the comment content renders correctly in JIRA:

- Convert markdown formatting to the format supported by the target JIRA instance
- Preserve code blocks, tables, lists, and headings
- Ensure images and file references use JIRA-compatible syntax
- **User mentions**: When the comment body mentions users (e.g. `@John`, `@john.doe`),
  replace each mention with the JIRA account-ID syntax so that JIRA sends the user an
  in-product and email notification:
  - Look up the account ID using the available JIRA tool `lookupJiraAccountId` (search by
    display name or email).
  - Replace the mention with `[~accountid:ACCOUNT_ID]` in Jira wiki markup.
  - If the account cannot be resolved, leave the original mention text and add a warning
    note at the end of the comment.

### Step 4 — Post the comment

Use the available JIRA tools/integrations to post the formatted comment to the ticket.

## Final Report

Report back to the caller:

- **Success**: "Comment posted successfully to `<TICKET-ID>`" with any notes about attachment
  uploads
- **Failure**: The specific error encountered, with details about what step failed
- **Warnings**: Any attachment upload failures or unresolved placeholders
