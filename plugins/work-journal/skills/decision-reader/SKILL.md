---
name: decision-reader
description: This skill should be used at clock-in, or when the user asks "why did we choose X", "what did we decide", "what decisions were made on JIRA-123", "what was the rationale", or "what decisions changed since last week". Reads and slices reasoned decision (DEC) entries from the project decision log by work item, date range, id, tag, status, or referencing diary entry — without loading the whole log.
argument-hint: [--work KEY] [--since YYYY-MM-DD] [--last N] [--headers] [--id DEC-id] [--status S] [--tag T] [--ref LOG-id]
allowed-tools: Bash
---

# Decision Reader

Slice the project decision log cheaply — never read it in full. All selectors compose (they are
ANDed), and `--last N` applies to whatever survives the filter.

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/read-decision.sh --last 10
```

## Selectors

- `--work KEY` — decisions belonging to one work item (`JIRA-123`, `RFC-7`, any slug).
- `--since YYYY-MM-DD` — decisions on or after that date. **Convert relative ranges first**: for
  *"since last week"*, compute the calendar date and pass it.
- `--last N` — the most recent N matching decisions (default 20).
- `--headers` — header lines only (id · timestamp · status); the cheapest overview.
- `--id DEC-YYYY-MM-DD-NN` — one full decision, with its Consideration / Decision / Rationale.
- `--date YYYY-MM-DD` — decisions from exactly that day.
- `--status proposed|accepted|superseded|rejected` — decisions at one point in their lifecycle.
- `--tag TAG` — entries whose `Tags:` line contains TAG.
- `--ref LOG-id` — entries whose `Refs:` line points at that diary entry.

Compose them: *"what did we decide on JIRA-123, and does any of it still stand"* is

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/read-decision.sh --work JIRA-123 --status accepted
```

## Notes

- A decision is reversed by a **newer** entry carrying `Supersedes: DEC-…`, not by editing the old
  one. When reporting a decision, check whether a later entry supersedes it before presenting it as
  current.
- If the decision log does not exist yet, the script prints `no entries yet`; if filters match
  nothing, it prints `no matching entries`.
