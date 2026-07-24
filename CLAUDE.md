# CLAUDE.md

A Claude Code plugin marketplace. Contains a marketplace index and plugins, each with skills (slash commands). No build system, no tests, no CI — all files are JSON or Markdown.

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Guideline

### Structure

```
.claude-plugin/
  marketplace.json          # Marketplace index listing all plugins
plugins/<plugin-name>/
  .claude-plugin/plugin.json  # Plugin metadata (name, version, author)
  skills/<skill-name>/
    SKILL.md                  # Skill definition (frontmatter + instruction body)
  README.md
```

### Adding a plugin

1. Create `plugins/<plugin-name>/.claude-plugin/plugin.json` with `name`, `description`, `version`, `author`.
2. Add skills under `plugins/<plugin-name>/skills/<skill-name>/SKILL.md`.
3. Register the plugin in `.claude-plugin/marketplace.json` under `"plugins"`.

### Marketplace registration

`.claude-plugin/marketplace.json` must list every plugin. The `source` field is a relative path from the marketplace file to the plugin directory.

### Development model

No linting, no tests. Validate by installing the plugin locally:

```
/plugin marketplace add <path-or-url-to-marketplace.json>
/plugin install <plugin-name>@engineering-assembly
```

Then invoke the skill and check its output matches the spec in `SKILL.md`.

## Workflow

- **Version bump on plugin change:** any edit to a published plugin under `plugins/<name>/` must bump
  the `version` in that plugin's `plugins/<name>/.claude-plugin/plugin.json`. One logical change = one
  bump (semver: patch for fixes, minor for new capability, major for breaking layout/manifest change).
- **Commit each unit of work:** when a unit of work is complete, make a git commit. Use the
  `commit-commands:commit` skill (or `commit-commands:commit-push-pr` when a PR is wanted) rather than
  raw `git commit`.
