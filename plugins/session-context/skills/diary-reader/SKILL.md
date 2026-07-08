---
name: diary-reader
description: Read and slice progress (LOG) entries from the project diary without loading the whole log. Use during clock-in to resume recent progress, or to look up entries by id, date, tag, or referenced decision.
argument-hint: [--last N] [--id LOG-id] [--date YYYY-MM-DD] [--tag T] [--ref DEC-id] [--headers]
allowed-tools: Bash
---

# Diary Reader

Slice the project diary cheaply — never read the log in full. Run the script with one
selector (default: the last 20 entries):

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/read-log.sh --last 15
```

Selectors:
- `--last N` — the most recent N entries (default 20).
- `--headers` — list every entry header line (id · timestamp · commit-id), cheapest overview.
- `--id LOG-YYYY-MM-DD-NN` — one full entry by id.
- `--date YYYY-MM-DD` — all entries logged on that day.
- `--tag TAG` — entries whose `Tags:` line contains TAG.
- `--ref DEC-id` — entries whose `Refs:` line points at that decision.

If the diary does not exist yet, the script prints `no entries yet`. For any `DEC-` id
surfaced in the recent diary, follow up with the `decision-reader` skill to read the full
decision.
