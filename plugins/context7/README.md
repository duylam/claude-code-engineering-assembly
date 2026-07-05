# Context7 Plugin

Bundles the [Context7](https://context7.com) MCP server into Claude Code so it can
fetch **up-to-date, version-specific** library documentation and code examples on demand —
instead of relying on the model's training-cutoff knowledge.

## Overview

Context7 is a hosted MCP server that indexes documentation for thousands of libraries and
frameworks. When Claude needs to know how a specific version of a library works, it queries
Context7 and gets current docs and working code snippets pulled straight from the source.

This plugin ships the server configuration (`.mcp.json`) so you don't have to add it to each
project's `.mcp.json` by hand.

## Configuration

The server is defined as a streamable HTTP MCP server:

```json
{
  "mcpServers": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp",
      "headers": {
        "CONTEXT7_API_KEY": "${MCP_CONTEXT7_API_KEY}"
      }
    }
  }
}
```

The API key is read from the `MCP_CONTEXT7_API_KEY` environment variable at connect time, so
no secret is committed to the repo.

## Setup

1. Get a Context7 API key from https://context7.com/dashboard.
2. Export it in your shell environment (e.g. in `~/.zshrc`):

   ```sh
   export MCP_CONTEXT7_API_KEY="your-api-key"
   ```

3. Install the plugin (see below) and restart Claude Code so the variable is in scope.

## Installation

```
/plugin marketplace add https://raw.githubusercontent.com/duylam/claude-code-engineering-assembly/main/.claude-plugin/marketplace.json
/plugin install context7@engineering-assembly
```

## Usage

Once installed and connected, ask Claude to use up-to-date docs, e.g.:

> How do I define a streaming route in the latest version of Hono? use context7

Verify the server is connected and see its tools with:

```
/mcp
```

## Requirements

- A Context7 API key exposed via the `MCP_CONTEXT7_API_KEY` environment variable.
- Network access to `https://mcp.context7.com`.
