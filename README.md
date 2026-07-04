# Claude Code Engineering Assembly

A Claude Code marketplace of plugins for software engineering workflows.

> **Important:** Make sure you trust a plugin before installing or using it. Review each plugin's homepage for details on what it does and what tools it uses.

## Plugins

### [development-task-implementation](plugins/development-task-implementation)

A structured validate → plan → implement workflow for software development tasks. Validates requirement completeness, decomposes into dependency-aware task lists, and coordinates implementation via subagents with frequent commits. Supports inline text and remote URLs (JIRA, GitHub, Linear).

### [worktree-setup](plugins/worktree-setup)

Packages a `WorktreeCreate` hook so `claude --worktree <name>` creates a branch, places the worktree under `.worktrees/<name>`, and initializes submodules — no per-repo setup.

## Installation

Add this marketplace to Claude Code:

```
/plugin marketplace add https://raw.githubusercontent.com/duylam/claude-code-engineering-assembly/main/.claude-plugin/marketplace.json
```

Then install individual plugins:

```
/plugin install development-task-implementation@engineering-assembly
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
