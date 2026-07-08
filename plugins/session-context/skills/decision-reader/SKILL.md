---
name: decision-reader
description: Read and slice reasoned decision (DEC) entries from the project decision log without loading the whole log. Use during clock-in to review recent decisions, or to look up entries by id, date, tag, status, or referencing diary entry.
argument-hint: [--last N] [--id DEC-id] [--date YYYY-MM-DD] [--tag T] [--ref LOG-id] [--status S] [--headers]
allowed-tools: Bash
---

# Decision Reader

Slice the project decision log cheaply — never read it in full. Run the script with one
selector (default: the last 20 entries):

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/read-decision.sh --last 15
```

Selectors:
- `--last N` — the most recent N entries (default 20).
- `--headers` — list every entry header line (id · timestamp · status), cheapest overview.
- `--id DEC-YYYY-MM-DD-NN` — one full entry by id.
- `--date YYYY-MM-DD` — all decisions logged on that day.
- `--tag TAG` — entries whose `Tags:` line contains TAG.
- `--ref LOG-id` — entries whose `Refs:` line points at that diary entry.
- `--status S` — entries with that lifecycle status (`proposed | accepted | superseded | rejected`).

If the decision log does not exist yet, the script prints `no entries yet`.
