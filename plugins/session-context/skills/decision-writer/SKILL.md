---
name: decision-writer
description: Append a reasoned decision (DEC) entry to the project decision log. Use during clock-out when work embodied a real choice — a tech choice, changed scope, reversed plan, or non-obvious trade-off. Automatically computes the entry id and ISO timestamp, and stages the entry for commit.
argument-hint: <title> <consideration> <decision> <rationale> [alternatives] [tags] [refs: LOG-ids] [supersedes: DEC-id] [status]
allowed-tools: Bash, Read
---

# Decision Writer

Append one `DEC-` entry to the project decision log (created on first use). The caller
supplies the content; the script computes the id (`DEC-<date>-NN`) and the ISO 8601
timestamp, and validates that every referenced `LOG-` id exists.

From `$ARGUMENTS`, pull the title and the Consideration / Decision / Rationale (and optional
Alternatives) content, then pipe the body into the script over stdin:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/append-decision.sh \
  --title "Diary/decision file schema" \
  --tags "schema, process" \
  --refs "LOG-2026-07-06-01" \
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

Rules:
- Mirror the constitution's **Reasoned Decisions**: make Consideration / Decision / Rationale
  explicit. If `Rationale` cannot be filled honestly, stop and ask the user.
- `--status` is one of `proposed | accepted | superseded | rejected` (default `accepted`).
- `--refs` lists the `LOG-` ids that triggered or executed this decision (decisions → diary).
  The script fails if a ref does not exist.
- `--supersedes DEC-id` records that this entry replaces an earlier decision. Entries are
  append-only — to reverse a past decision, write a new one with `--supersedes`; optionally
  append a short correcting `LOG-`/`DEC-` note pointing back to the superseded id.
- The script appends and stages the entry, then prints the new id — report it back so it
  ships in the same commit as the related code.
