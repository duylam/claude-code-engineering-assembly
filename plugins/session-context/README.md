# Session Context Plugin

Give Claude Code a durable, project-local memory that survives across sessions. The plugin
maintains two append-only logs under `.claude/memory/` and provides cheap, sliced reads so
you can resume context at the start of a session ("clock-in") and record progress and
decisions at the end ("clock-out") without ever loading a whole log into context.

## The two logs

- **Diary** (`.claude/memory/diary.md`) — `LOG-` entries recording *what was done, why, and
  what comes next*, each stamped with an id, ISO 8601 timestamp, and the HEAD commit SHA.
- **Decisions** (`.claude/memory/decisions.md`) — `DEC-` entries recording *reasoned
  choices*: Consideration / Decision / Rationale (and optional Alternatives), each stamped
  with an id, timestamp, and lifecycle status.

Diary and decision entries cross-reference each other via `Refs:` lines (`LOG- → DEC-` and
`DEC- → LOG-`); writers validate that every referenced id already exists.

Both files live in the working repository under `.claude/memory/` (resolved from
`$CLAUDE_PROJECT_DIR`), so the memory travels with the project and versions in git alongside
the code it describes.

## Skills

| Skill | Purpose |
|-------|---------|
| `diary-reader` | Slice `LOG-` entries by `--last N`, `--headers`, `--id`, `--date`, `--tag`, or `--ref` — never reads the full diary. |
| `diary-writer` | Append one `LOG-` entry (Did / Why / Next); computes id, timestamp, and HEAD SHA, and stages it for commit. |
| `decision-reader` | Slice `DEC-` entries by `--last N`, `--headers`, `--id`, `--date`, `--tag`, `--ref`, or `--status`. |
| `decision-writer` | Append one `DEC-` entry (Consideration / Decision / Rationale); computes id and timestamp, validates refs, and stages it. |

## Typical flow

**Clock-in** (resume): run `diary-reader --last N` to review recent progress, then follow any
`DEC-` ids surfaced there with `decision-reader --id DEC-…` to read the full reasoning.

**Clock-out** (wrap up, before a commit): run `diary-writer` to record what changed and why,
and `decision-writer` whenever the work embodied a real choice. Both stage their entry so it
ships in the same commit as the code it describes.

## Installation

```
/plugin marketplace add <path-or-url-to-marketplace.json>
/plugin install session-context@engineering-assembly
```

## Notes

- Logs are **append-only**: never edit past entries. To reverse a decision, write a new
  `DEC-` entry with `--supersedes DEC-id`.
- The reader scripts print `no entries yet` when a log does not exist, so they are safe to
  run on a fresh project.
- Skill scripts resolve paths from `${CLAUDE_SKILL_DIR}` (script location) and
  `${CLAUDE_PROJECT_DIR}` (project root), so the plugin is fully portable.
