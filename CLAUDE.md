# CLAUDE.md

A Claude Code plugin marketplace. Contains a marketplace index and plugins, each with skills (slash commands). No build system, no tests, no CI — all files are JSON or Markdown.

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Constitution

<!--

Note for the AI: this is for human, don't touch, and keep this HTML comment block when updating this file

-->

### Change Integrity

- Treat every durable change — to local files or remote state — as touching a web of dependent content, never as an isolated edit.
- Before planning or making such a change, identify everything that depends on or relates to the changed content.
- Propagate the change to all affected artifacts so they stay aligned; documentation that describes code changes when the code does.
- Never leave a change half-applied: a change is complete only when nothing dependent on it is left stale or contradictory.

### Grounded Advice

- Ground every research or advisory result in identifiable sources.
- Always cite those sources, giving real, working references (such as actual document URLs) the user can open and verify.
- Never present a claim as sourced when it is inference; keep what was found and what was concluded distinguishable.

## Structure

```
.claude-plugin/
  marketplace.json          # Marketplace index listing all plugins
plugins/<plugin-name>/
  .claude-plugin/plugin.json  # Plugin metadata (name, version, author)
  skills/<skill-name>/
    SKILL.md                  # Skill definition (frontmatter + instruction body)
  README.md
```

## Adding a plugin

1. Create `plugins/<plugin-name>/.claude-plugin/plugin.json` with `name`, `description`, `version`, `author`.
2. Add skills under `plugins/<plugin-name>/skills/<skill-name>/SKILL.md`.
3. Register the plugin in `.claude-plugin/marketplace.json` under `"plugins"`.

## Adding a skill to an existing plugin

Create `plugins/<plugin-name>/skills/<skill-name>/SKILL.md`. The frontmatter `description` field is critical — it controls when Claude auto-triggers the skill, so write it as a precise trigger sentence (what the user says or intends).

## Marketplace registration

`.claude-plugin/marketplace.json` must list every plugin. The `source` field is a relative path from the marketplace file to the plugin directory.

## Development model

No linting, no tests. Validate by installing the plugin locally:

```
/plugin marketplace add <path-or-url-to-marketplace.json>
/plugin install <plugin-name>@engineering-assembly
```

Then invoke the skill and check its output matches the spec in `SKILL.md`.
