---
name: diary-writer
description: Append a progress (LOG) entry to the project diary. Use during clock-out, before a git commit, to record what was done, why, and what comes next. Automatically computes the entry id, ISO timestamp, and HEAD commit SHA, and stages the entry for commit.
argument-hint: <did bullets> <why bullets> <next bullets> [tags: comma list] [refs: DEC-ids]
allowed-tools: Bash, Read
---

# Diary Writer

Append one `LOG-` entry to the project diary (created on first use). The caller supplies the
content; the script computes the id (`LOG-<date>-NN`), the ISO 8601 timestamp, and the
current HEAD short SHA, and validates that every referenced `DEC-` id exists.

From `$ARGUMENTS`, pull the Did / Why / Next content plus any tags and decision refs, then
pipe the body into the script over stdin:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/append-log.sh --tags "schema, bootstrap" --refs "DEC-2026-07-06-01" <<'BODY'
### Did
- <what changed, terse bullets>

### Why
- <reason or trigger for the work>

### Next
- <concrete follow-ups>
BODY
```

Rules:
- Always include all three subheaders (`### Did`, `### Why`, `### Next`); fill each with terse bullets.
- `--tags` is a free comma list — omit the flag if there are none.
- `--refs` lists `DEC-` ids this work relates to (diary → decisions). Omit if none. The
  script fails if a ref does not exist, so only reference decisions already logged.
- If `Why` cannot be filled honestly, stop and ask the user — that gap is a signal, not a
  formatting issue. Do not invent one.
- The entry is append-only; never edit past entries. The script appends and stages the
  entry, then prints the new id — report it back so it ships in the same commit as the code.
