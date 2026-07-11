# Session Context Plugin

Memory for work that outlives a single Claude Code session.

A real task — a JIRA ticket, an RFC — is not one session. It is an explore session on Monday
morning, a planning session that afternoon, an implementation session that runs into Tuesday, a
review session, a UAT session. Each new session starts with an empty head. This plugin gives the
project a durable, work-item-aware memory so that on any later day the agent can answer, without
being told anything:

- *what are the pending items?*
- *what changed on JIRA-123?*
- *what did I do since last week?*

## How it works

Two append-only logs under `.claude/memory/` (resolved from `$CLAUDE_PROJECT_DIR`, so the memory
versions in git alongside the code it describes):

- **Diary** (`diary.md`) — `LOG-` entries: what was done, why, and what comes next.
- **Decisions** (`decisions.md`) — `DEC-` entries: Consideration / Decision / Rationale, with a
  lifecycle status.

Three ideas make them answer the questions above.

**Work items.** Every entry carries `Work: JIRA-123` (any slug works — `RFC-7`, `migration`). It is
the axis that turns a flat chronological journal into a set of workstreams you can query
independently.

**Open items are derived, not remembered.** Each bullet under `### Next` is assigned an addressable
id when it is written:

```
### Next
- [NEXT-2026-07-10-01] wire up the UAT environment
```

A later entry closes it by naming it:

```
## LOG-2026-07-11-02 · 2026-07-11T14:03:11+07:00 · commit-id=049d4c3
Work: JIRA-123
Phase: uat
Closes: NEXT-2026-07-10-01
```

So *pending* = every `NEXT-` ever opened, minus every one ever closed. That is arithmetic a script
performs, not a judgement the model makes by re-reading old prose — which is the difference between
a reliable answer and a plausible one. It also preserves the append-only invariant: nothing is ever
edited, items simply acquire a closing event.

**The protocol ships with the plugin.** A `UserPromptSubmit` hook injects the clock-in/clock-out
procedure into the session, so an installed plugin is self-sufficient — projects no longer need to
paste a "Session Protocol" section into their `CLAUDE.md`. The injection is tiered: the full protocol
on the first prompt of a context, then a one-line standing reminder on each turn after (cheap, and it
survives compaction — unlike a single up-front injection, which is the first thing dropped in exactly
the long sessions where a clock-out reminder matters most).

A companion `SessionStart` hook (matching `clear|compact`) resets that tiering. `/clear` wipes the
conversation but **keeps the session id**, so without the reset the "already briefed" marker would
outlive the context it was tracking and the protocol would never come back. The reset drops the
marker silently, and the next prompt gets the full protocol again — as if the session had just
started.

## Skills

| Skill | Purpose |
|-------|---------|
| `diary-reader` | Clock-in brief (`--session-brief`), pending items (`--open`), and sliced reads by `--work`, `--since`, `--phase`, `--last`, `--id`, `--date`, `--tag`, `--ref`, `--headers`. Never reads the full diary. |
| `diary-writer` | Append one `LOG-` entry (Did / Why / Next). Computes id, timestamp, and HEAD SHA; assigns `NEXT-` ids; closes finished items via `--closes`; stages the entry. |
| `decision-reader` | Slice `DEC-` entries by `--work`, `--since`, `--status`, `--last`, `--id`, `--date`, `--tag`, `--ref`, `--headers`. |
| `decision-writer` | Append one `DEC-` entry (Consideration / Decision / Rationale). Computes id and timestamp, validates refs, stages the entry. |

Selectors **compose** — every one supplied is ANDed:

```bash
# what changed on JIRA-123 since last week
read-log.sh --work JIRA-123 --since 2026-07-04

# what is still pending on JIRA-123
read-log.sh --open --work JIRA-123
```

## A worked example

**Day 1, morning (explore).** Read the ticket, learn the codebase. Clock out:
`diary-writer --work JIRA-123 --phase explore` with `Next: confirm the auth flow with the API team`.
The script assigns it `NEXT-2026-07-10-01`.

**Day 1, afternoon (plan).** New session. Clock in: `diary-reader --session-brief` shows
`NEXT-2026-07-10-01` still open. Plan the implementation, record the tech choice with
`decision-writer --work JIRA-123`, clock out closing the item that got answered.

**Day 2 (implement), Day 3 (review), Day 4 (UAT).** Each new session opens with the brief and knows
exactly which items survive. Ask *"what are the pending plan items"* and the answer comes from the
log, not from a guess.

## Installation

```
/plugin marketplace add <path-or-url-to-marketplace.json>
/plugin install session-context@engineering-assembly
```

## Notes

- Logs are **append-only**: never edit past entries. Reverse a decision by writing a new `DEC-` with
  `--supersedes DEC-id`.
- The pending list is only as honest as the `--closes` discipline at clock-out. An item finished but
  not closed stays pending forever — the writer skill makes closing a required step for this reason.
- Reader scripts print `no entries yet` on a fresh project and `no matching entries` when filters
  match nothing, so they are always safe to run.
- Scripts resolve paths from `${CLAUDE_SKILL_DIR}` and `${CLAUDE_PROJECT_DIR}`; the hook uses
  `${CLAUDE_PLUGIN_ROOT}`. The plugin is fully portable.
