# Worktree Setup Plugin

Packages a `WorktreeCreate` hook so `claude --worktree <name>` gives every repo
a consistent worktree layout — no per-repo hook setup required.

## Overview

Claude Code's `--worktree <name>` flag fires a `WorktreeCreate` hook to decide how the
worktree is created. Without a hook, Claude Code falls back to its default behavior. This
plugin installs a hook that **replaces** the default with:

1. Create branch `<name>` and a worktree at `.worktrees/<name>` under the repo root.
2. Initialize and update git submodules inside the new worktree (`git submodule update
   --init --recursive`).
3. Report the new worktree's absolute path back to Claude Code, which then uses it as the
   working directory for the session.

## How it works

The hook lives at `hooks/on-worktree-create.sh` and is wired via `hooks/hooks.json` using
`${CLAUDE_PLUGIN_ROOT}`, so it works from any repo the plugin is installed into — the script
itself reads the target repo's root (`cwd`) and desired branch/worktree `name` from the JSON
Claude Code sends on stdin.

Per the `WorktreeCreate` contract: the script must print **only** the created worktree's
absolute path to stdout (everything else goes to stderr) and exit `0`. A non-zero exit
aborts worktree creation.

## Usage

```
claude --worktree my-feature
```

This creates:

```
<repo-root>/
└── .worktrees/
    └── my-feature/    # new worktree, branch `my-feature`, submodules initialized
```

Claude Code then runs the session with `.worktrees/my-feature` as the working directory.

## Installation

```
/plugin marketplace add https://raw.githubusercontent.com/duylam/claude-code-engineering-assembly/main/.claude-plugin/marketplace.json
/plugin install worktree-setup@engineering-assembly
```

## Requirements

- `git` (with worktree and submodule support)
- `jq` (used to parse the hook's stdin JSON)

## Notes

- Worktrees are created under `.worktrees/` in the repo root. Consider adding `.worktrees/`
  to your repo's `.gitignore`.
- If a branch or worktree with the same `name` already exists, `git worktree add -b` will
  fail — pick a fresh name or clean up the old worktree/branch first.
- If your repo has no submodules, the submodule step is a harmless no-op.
