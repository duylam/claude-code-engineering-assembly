# Claude Code Engineering Assembly

A Claude Code marketplace of plugins for software engineering workflows.

> **Important:** Make sure you trust a plugin before installing or using it. Review each plugin's homepage for details on what it does and what tools it uses.

## Plugins

### [implementation](plugins/implementation)

A structured validation workflow for software development tasks, plus QA test automation and JIRA integration. Validates requirement completeness, runs manual test cases on web (playwright-cli) or Android (adb) via the automation-expert agent, and retrieves/posts results to JIRA tickets.

### [worktree-setup](plugins/worktree-setup)

Packages a `WorktreeCreate` hook so `claude --worktree <name>` creates a branch, places the worktree under `.worktrees/<name>`, and initializes submodules — no per-repo setup.

## Installation

Add this marketplace to Claude Code:

```
/plugin marketplace add https://raw.githubusercontent.com/duylam/claude-code-engineering-assembly/main/.claude-plugin/marketplace.json
```

Then install individual plugins:

```
/plugin install implementation@engineering-assembly
```

Or browse via `/plugin > Discover`.

## Structure

```
claude-code-engineering-assembly/
├── .claude-plugin/
│   └── marketplace.json     # Marketplace index
└── plugins/
    └── <plugin-name>/
        ├── .claude-plugin/
        │   └── plugin.json  # Plugin metadata
        ├── skills/          # Skill definitions
        └── README.md        # Plugin documentation
```

## Contributing

Open an issue or pull request at [github.com/duylam/claude-code-engineering-assembly](https://github.com/duylam/claude-code-engineering-assembly).

## License

See individual plugins for their respective LICENSE files.
