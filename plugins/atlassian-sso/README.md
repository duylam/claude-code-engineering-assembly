# Atlassian SSO Plugin

Bundles the [Atlassian Remote MCP Server](https://www.atlassian.com/platform/remote-mcp-server)
(Rovo) into Claude Code so it can work with **Jira, Confluence, Jira Service Management,
Bitbucket, and Compass** directly — reading issues, searching pages, creating tickets, and
more — with every action respecting your existing Atlassian access controls.

Authentication uses **OAuth 2.1 SSO** (browser login). If you'd rather authenticate with a
personal API token or service-account API key instead of an interactive browser flow, use the
companion **`atlassian-api-token`** plugin.

## Overview

Atlassian hosts a remote MCP server that exposes your Atlassian Cloud products as MCP tools.
Authentication uses **OAuth 2.1 SSO** — the first time Claude Code connects, it opens your
browser to complete the Atlassian login/authorization flow. No API key or secret is stored in
this repo.

This plugin ships the server configuration (`.mcp.json`) so you don't have to add it to each
project's `.mcp.json` by hand.

## Configuration

The server is defined as a streamable HTTP MCP server:

```json
{
  "mcpServers": {
    "atlassian-sso": {
      "type": "http",
      "url": "https://mcp.atlassian.com/v1/mcp/authv2"
    }
  }
}
```

> The endpoint `https://mcp.atlassian.com/v1/mcp/authv2` is Atlassian's current recommended
> URL. The legacy SSE endpoint (`https://mcp.atlassian.com/v1/sse`) is deprecated and stops
> working after June 30, 2026.

## Setup

1. Install the plugin (see below).
2. On first use, Claude Code triggers the OAuth flow — a browser window opens for you to sign
   in to Atlassian and authorize access. A modern browser is required to complete it.
3. Confirm the server is connected and authorized:

   ```
   /mcp
   ```

You need an Atlassian Cloud account with access to the products you want to use. Your admin may
need to enable the Remote MCP Server / Rovo for your site.

## Installation

```
/plugin marketplace add https://raw.githubusercontent.com/duylam/claude-code-engineering-assembly/main/.claude-plugin/marketplace.json
/plugin install atlassian-sso@engineering-assembly
```

## Usage

Once connected, ask Claude to work with your Atlassian data, e.g.:

> Summarize the open bugs assigned to me in the PLATFORM Jira project.

> Find the Confluence page describing our on-call rotation and give me the escalation steps.

## Requirements

- An Atlassian Cloud account (Jira / Confluence / etc.) with the Remote MCP Server enabled.
- A modern browser to complete the OAuth 2.1 SSO login.
- Network access to `https://mcp.atlassian.com`.

## References

- [Getting started with the Atlassian Rovo MCP Server](https://support.atlassian.com/atlassian-rovo-mcp-server/docs/getting-started-with-the-atlassian-remote-mcp-server/)
- [Official atlassian/atlassian-mcp-server repo](https://github.com/atlassian/atlassian-mcp-server)
