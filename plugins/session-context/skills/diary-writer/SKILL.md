---
name: diary-writer
description: This skill should be used at clock-out — before every git commit, or when the user says "clock out", "log this session", "record what we did", or "wrap up" — to append a progress (LOG) entry recording what was done, why, what comes next, and which pending items are now finished. Automatically computes the entry id, ISO timestamp, and HEAD commit SHA, assigns a trackable NEXT- id to each follow-up, closes completed items, and stages the entry for commit.
argument-hint: <did bullets> <why bullets> <next bullets> [--work KEY] [--phase P] [--closes NEXT-ids] [--tags list] [--refs DEC-ids]
allowed-tools: Bash, Read
---

# Diary Writer

Append one `LOG-` entry to the project diary (created on first use). Supply the content; the script
computes the id (`LOG-<date>-NN`), the ISO 8601 timestamp, and the HEAD short SHA, assigns a
`NEXT-` id to every follow-up bullet, and validates all refs.

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/append-log.sh \
  --work "JIRA-123" \
  --phase implement \
  --session "${CLAUDE_SESSION_ID}" \
  --closes "NEXT-2026-07-10-01, NEXT-2026-07-10-02" \
  --tags "auth, schema" \
  --refs "DEC-2026-07-06-01" <<'BODY'
### Did
- <what changed, terse bullets>

### Why
- <reason or trigger for the work>

### Next
- <concrete follow-up>
BODY
```

## Rules

- **`--work` is the grouping key** (`JIRA-123`, `RFC-7`, any slug) that lets one task span many
  sessions and days. Always pass it. If it is unclear which work item the session belongs to, **ask
  the user** — do not guess, and do not silently fall back to unassigned.
- **Close what was finished.** Before writing the entry, check the open items
  (`diary-reader --open --work KEY`) and pass every one this session actually completed to
  `--closes`. This is not optional bookkeeping: open items are derived as `opened − closed`, so an
  item that is done but not closed stays pending forever and misleads the next clock-in.
- **Write `### Next` bullets as plain text.** The script assigns each one a `[NEXT-<date>-NN]` id and
  prints the ids back; do not invent ids by hand.
- Always include all three subheaders (`### Did`, `### Why`, `### Next`), each with terse bullets.
- `--phase` is one of `explore | plan | implement | review | uat | other` — the stage this session
  occupied. `--session ${CLAUDE_SESSION_ID}` attributes the entry to this session.
- `--tags` is a free comma list. `--refs` lists `DEC-` ids this work relates to; the script fails if
  a ref does not exist, so only reference decisions already logged.
- If `Why` cannot be filled honestly, stop and ask the user — that gap is a signal, not a formatting
  issue. Do not invent one.
- Entries are append-only; never edit past ones. The script appends and stages the entry, then prints
  the new id plus the ids opened and closed — carry that forward so it ships in the same commit as
  the code it describes.
