# Claude Code Engineering Assembly

A Claude Code marketplace of plugins for software engineering workflows.

> **Important:** Make sure you trust a plugin before installing or using it. Review each plugin's homepage for details on what it does and what tools it uses.

## Plugins

### [implementation](plugins/implementation)

A structured validation workflow for software development tasks, plus QA test automation and JIRA integration. Validates requirement completeness, runs manual test cases on web (`playwright-cli`) or Android (`adb`) via the `automation-expert` agent, and retrieves/posts results to JIRA tickets.

### [work-journal](plugins/work-journal)

Cross-session memory for long-running work: append-only diary (LOG) and decision (DEC) logs under `.claude/memory`, grouped by work item (JIRA-123, RFC-7, …), with derived open-item tracking so any later session can answer what is still pending, what changed on a ticket, and what was done since a date. Ships its own clock-in/clock-out protocol via a `UserPromptSubmit` hook.

### [context7](plugins/context7)

Bundles the [Context7](https://mcp.context7.com/mcp) MCP server so Claude Code can pull up-to-date, version-specific library documentation and code examples on demand.

### [atlassian-sso](plugins/atlassian-sso)

Bundles the Atlassian Remote MCP Server (Rovo) so Claude Code can access Jira, Confluence, Jira Service Management, Bitbucket, and Compass via OAuth 2.1 SSO login.

### [atlassian-api-token](plugins/atlassian-api-token)

Bundles the Atlassian Remote MCP Server (Rovo) so Claude Code can access Jira, Confluence, Jira Service Management, Bitbucket, and Compass using a personal API token (Basic auth) instead of interactive SSO login.

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
│   └── marketplace.json     # Marketplace index (lists every plugin)
└── plugins/
    └── <plugin-name>/
        ├── .claude-plugin/
        │   └── plugin.json  # Plugin metadata
        ├── .mcp.json        # MCP server definitions (optional)
        ├── skills/          # Skill definitions (optional)
        ├── agents/          # Subagent definitions (optional)
        ├── hooks/           # Event hooks (optional)
        └── README.md        # Plugin documentation
```

A plugin ships whichever of those components it needs — `implementation` provides skills and an agent, `work-journal` provides skills and a hook, and the `context7` / `atlassian-*` plugins are thin wrappers around an MCP server.

## Contributing

Open an issue or pull request at [github.com/duylam/claude-code-engineering-assembly](https://github.com/duylam/claude-code-engineering-assembly).

## License

See individual plugins for their respective LICENSE files.
