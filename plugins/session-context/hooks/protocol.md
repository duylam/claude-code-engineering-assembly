# Session Protocol: Diary & Decisions — MANDATORY

Hard procedure, not advisory. These logs are the memory across sessions: they exist to catch up on
prior progress and hand off state to the next run. They are **not** a human report — do not narrate
the protocol or its output to the user.

Two append-only logs, driven **only** through the `session-context` skills (never touch the logs by
hand): a progress **diary** (`LOG-` entries) and a **decision log** (`DEC-` entries). The skills own
storage, ids, timestamps, commit SHA, ref validation, staging, and formatting.

Work is grouped by **work item** (`--work KEY`, e.g. `JIRA-123`) so one task can span many sessions
and days. Each `Next` bullet is an addressable open item (`NEXT-…`) that stays pending until some
later entry closes it.

## Clock-in — at session start, before the first non-trivial action

1. `session-context:diary-reader --session-brief` — open items grouped by work item, plus the recent
   entry headers. This is where the last session left off.
2. `session-context:decision-reader --last 10` — the recent reasoning.
3. Narrow as needed: `--work KEY` to scope to one work item, `--id LOG-…` / `--id DEC-…` for the full
   text of anything the brief surfaced.

Then you are caught up — start work. Skip only for trivial one-shot queries.

## Clock-out — before every `git commit`, to hand off to the next run

1. `session-context:diary-writer` with `Did / Why / Next`, always passing:
   - `--work KEY` — the work item. If it is unclear which item the work belongs to, **ask the user**;
     do not guess.
   - `--closes NEXT-…` — every open item this session actually finished. **Closing is not optional**:
     an item that is done but not closed stays pending forever and corrupts the next clock-in.
   - `--phase explore|plan|implement|review|uat|other`, `--session ${CLAUDE_SESSION_ID}`, plus
     `--tags` / `--refs` as applicable.
   Write `Next` bullets as plain text — the script assigns their `NEXT-` ids.
2. If the work embodied a decision (tech choice, changed scope, reversed plan, non-obvious
   trade-off), `session-context:decision-writer` with `Consideration / Decision / Rationale`
   (+ `--work`, + `--refs` the new `LOG-` id).
3. `git commit` — the writers stage each entry, so it ships with the code.

If `Why` or `Rationale` cannot be filled honestly, stop — that gap is a signal, not a formatting
issue.

## Invariants

- Append only. Correct a past entry by appending a new one (`DEC-` with `--supersedes`, or a `LOG-`
  note), never by editing.
- Every `Refs:` id must exist — the writers enforce this.
- Open items are derived (`opened − closed`), so the pending list is only as honest as the `--closes`
  discipline at clock-out.
