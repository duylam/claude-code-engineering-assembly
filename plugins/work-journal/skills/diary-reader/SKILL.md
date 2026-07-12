---
name: diary-reader
description: This skill should be used at clock-in, or when the user asks "where did I leave off", "catch me up", "what are the pending items", "what are the pending plan items", "what's still open on JIRA-123", "what changed on <ticket>", "what did I do since last week", or "what have I been working on". Reads and slices progress (LOG) entries from the project diary — including the derived list of still-open NEXT items — without ever loading the whole log.
argument-hint: [--session-brief] [--open] [--work KEY] [--since YYYY-MM-DD] [--last N] [--headers] [--id LOG-id] [--phase P] [--tag T] [--ref DEC-id]
allowed-tools: Bash
---

# Diary Reader

Slice the project diary cheaply — never read the log in full. All selectors compose (they are
ANDed), and `--last N` applies to whatever survives the filter.

## Start here: the clock-in brief

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/read-log.sh --session-brief
```

Prints the open items grouped by work item, plus the recent entry headers. This is the default
answer to *"where did I leave off"* and *"catch me up"*. Scope it to one workstream with
`--session-brief --work JIRA-123`.

## Pending items

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/read-log.sh --open --work JIRA-123
```

Answers *"what are the pending items"*. Open items are **derived**, not guessed: every `[NEXT-…]`
bullet ever written, minus every id named on a `Closes:` line. Report exactly what this prints —
never infer pending work by reading `### Next` sections directly, because entries whose items were
long since completed still carry them.

## Selectors

- `--work KEY` — one work item (`JIRA-123`, `RFC-7`, any slug). The main axis for *"what changed on
  <ticket>"*.
- `--since YYYY-MM-DD` — entries on or after that date. **Relative ranges are converted first**: for
  *"since last week"*, compute the calendar date and pass it (`--since 2026-07-04`).
- `--last N` — the most recent N matching entries (default 20).
- `--headers` — header lines only (id · timestamp · commit-id); the cheapest overview.
- `--id LOG-YYYY-MM-DD-NN` — one full entry.
- `--date YYYY-MM-DD` — entries from exactly that day.
- `--phase explore|plan|implement|review|uat|other` — entries from one stage of the work.
- `--tag TAG` — entries whose `Tags:` line contains TAG.
- `--ref DEC-id` — entries whose `Refs:` line points at that decision.

Compose them: *"what changed on JIRA-123 since last week"* is

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/read-log.sh --work JIRA-123 --since 2026-07-04
```

## Follow-ups

- For any `DEC-` id surfaced in an entry's `Refs:`, read the full reasoning with the
  `decision-reader` skill (`--id DEC-…`).
- If the diary does not exist yet, the script prints `no entries yet`; if filters match nothing, it
  prints `no matching entries`. Both are safe, expected outputs — say so plainly rather than
  speculating about prior work.
