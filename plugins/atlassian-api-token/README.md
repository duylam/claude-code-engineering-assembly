# Atlassian API Token Plugin

Bundles the [Atlassian Remote MCP Server](https://www.atlassian.com/platform/remote-mcp-server)
(Rovo) into Claude Code so it can work with **Jira, Confluence, Jira Service Management,
Bitbucket, and Compass** directly — reading issues, searching pages, creating tickets, and
more — with every action respecting your existing Atlassian access controls.

Authentication uses a **personal API token** (HTTP Basic auth) instead of an interactive
browser SSO flow. This is the right choice for headless environments, CI, or shared machines
where a browser login is impractical. If you'd rather use interactive OAuth 2.1 SSO, use the
companion **`atlassian-sso`** plugin.

## Overview

Atlassian hosts a remote MCP server that exposes your Atlassian Cloud products as MCP tools.
This plugin authenticates by sending an `Authorization: Basic <base64>` header, where the
base64 value encodes `email:api_token`. The credential is read from the
`MCP_ATLASSIAN_BASE64_ENCODED_EMAIL_AND_API_TOKEN` environment variable, so no secret is stored
in this repo.

This plugin ships the server configuration (`.mcp.json`) so you don't have to add it to each
project's `.mcp.json` by hand.

## Configuration

The server is defined as a streamable HTTP MCP server with a Basic auth header:

```json
{
  "mcpServers": {
    "atlassian-api-token": {
      "type": "http",
      "url": "https://mcp.atlassian.com/v1/mcp",
      "headers": {
        "Authorization": "Basic ${MCP_ATLASSIAN_BASE64_ENCODED_EMAIL_AND_API_TOKEN}"
      }
    }
  }
}
```

> The API-token endpoint is `https://mcp.atlassian.com/v1/mcp` (note: **not** the `/authv2`
> path used by the SSO plugin). Claude Code expands `${MCP_ATLASSIAN_BASE64_ENCODED_EMAIL_AND_API_TOKEN}`
> from your environment at connect time.

## Setup

1. **Create an Atlassian API token.** Go to
   <https://id.atlassian.com/manage-profile/security/api-tokens>, click **Create API token**,
   give it a label, and copy the generated token. Note the email address of the account that
   owns the token.

2. **Base64-encode `email:api_token`.** Encode the email and token joined by a single colon —
   do not add a trailing newline (`-n`):

   ```bash
   echo -n "your.email@example.com:YOUR_API_TOKEN_HERE" | base64
   ```

3. **Export the encoded value** as the environment variable this plugin reads. Add it to your
   shell profile (e.g. `~/.zshrc`) so it persists:

   ```bash
   export MCP_ATLASSIAN_BASE64_ENCODED_EMAIL_AND_API_TOKEN="<paste base64 output here>"
   ```

   The resulting request header becomes
   `Authorization: Basic <base64 of email:api_token>`.

4. Install the plugin (see below), then confirm the server is connected and authorized:

   ```
   /mcp
   ```

You need an Atlassian Cloud account with access to the products you want to use. Your admin may
need to enable the Remote MCP Server / Rovo for your site.

> **Security:** Treat the base64 value as a secret — it is only encoded, **not** encrypted, and
> anyone with it can act as you. Keep it out of version control and shell history where
> possible.

## Installation

```
/plugin marketplace add https://raw.githubusercontent.com/duylam/claude-code-engineering-assembly/main/.claude-plugin/marketplace.json
/plugin install atlassian-api-token@engineering-assembly
```

## Usage

Once connected, ask Claude to work with your Atlassian data, e.g.:

> Summarize the open bugs assigned to me in the PLATFORM Jira project.

> Find the Confluence page describing our on-call rotation and give me the escalation steps.

## Requirements

- An Atlassian Cloud account (Jira / Confluence / etc.) with the Remote MCP Server enabled.
- A personal Atlassian API token, base64-encoded as `email:api_token` and exported as
  `MCP_ATLASSIAN_BASE64_ENCODED_EMAIL_AND_API_TOKEN`.
- Network access to `https://mcp.atlassian.com`.

## References

- [Configuring authentication via API token](https://support.atlassian.com/atlassian-rovo-mcp-server/docs/configuring-authentication-via-api-token/)
- [Getting started with the Atlassian Rovo MCP Server](https://support.atlassian.com/atlassian-rovo-mcp-server/docs/getting-started-with-the-atlassian-remote-mcp-server/)
- [Manage API tokens for your Atlassian account](https://support.atlassian.com/atlassian-account/docs/manage-api-tokens-for-your-atlassian-account/)
- [Official atlassian/atlassian-mcp-server repo](https://github.com/atlassian/atlassian-mcp-server)
