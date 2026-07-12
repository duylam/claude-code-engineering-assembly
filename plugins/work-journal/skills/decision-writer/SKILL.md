---
name: decision-writer
description: This skill should be used at clock-out, when the session's work embodied a real choice — a tech choice, changed scope, reversed plan, or non-obvious trade-off — or when the user says "record this decision", "log why we chose this", or "write an ADR". Appends a reasoned decision (DEC) entry with Consideration / Decision / Rationale, computes the entry id and ISO timestamp, validates refs, and stages the entry for commit.
argument-hint: <title> <consideration> <decision> <rationale> [alternatives] [--work KEY] [--refs LOG-ids] [--supersedes DEC-id] [--status S] [--tags list]
allowed-tools: Bash, Read
---

# Decision Writer

Append one `DEC-` entry to the project decision log (created on first use). Supply the content; the
script computes the id (`DEC-<date>-NN`) and the ISO 8601 timestamp, and validates that every
referenced `LOG-` id exists.

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/append-decision.sh \
  --title "Derive open items instead of storing them" \
  --work "JIRA-123" \
  --session "${CLAUDE_SESSION_ID}" \
  --tags "schema, process" \
  --refs "LOG-2026-07-11-02" \
  --status accepted <<'BODY'
### Consideration
- <what forces the choice>

### Decision
- <what was chosen>

### Rationale
- <why this over the alternatives>

### Alternatives
- <option rejected> — <why>
BODY
```

## Rules

- Make **Consideration / Decision / Rationale** explicit. If `Rationale` cannot be filled honestly,
  stop and ask the user — that gap is a signal, not a formatting issue.
- **`--work KEY`** ties the decision to the same work item as the diary entries it came from, so
  *"what did we decide on JIRA-123"* resolves. Ask the user if the work item is unclear.
- `--refs` lists the `LOG-` ids that triggered or executed this decision. Write the diary entry
  **first**, then reference its id here — the script fails if a ref does not exist.
- `--status` is one of `proposed | accepted | superseded | rejected` (default `accepted`).
- `--supersedes DEC-id` records that this entry replaces an earlier decision. Entries are
  append-only — to reverse a past decision, write a new one with `--supersedes`, never edit the old
  one.
- The script appends and stages the entry, then prints the new id — carry it forward so it ships in
  the same commit as the related code.
