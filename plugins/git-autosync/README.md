# Git Autosync Plugin

A session should not start on a stale branch, an empty submodule, or a detached HEAD.

This plugin puts the repository into a known-good git state *before the first prompt* of every
session, with no prompting and no configuration:

- the default branch is level with the remote,
- a new worktree is cut from that freshly synced branch, not from whatever was left behind days ago,
- every submodule is populated,
- every top-level submodule sits on a branch, so a commit made inside one goes somewhere.

> ### Built for Claude Code Remote Sessions
>
> This plugin exists for projects driven through the **Claude Code Remote Session** feature — web,
> mobile, or any launch where nobody is sitting at a terminal to run `git pull` and
> `git submodule update` first.
>
> A remote session opens on a machine whose checkout may be days old, and it typically opens in a
> **fresh worktree**. Without this plugin the session's branch is cut from a stale default branch
> and its submodules are empty or detached — and the agent discovers this halfway through a task,
> if at all. Nothing here is remote-specific, so it works fine locally too, but that is the case it
> was designed around.

## Requirements

- `git`
- `bash` 3.2 or newer — the macOS system `/bin/bash` qualifies
- `jq` — optional. Without it the hooks fall back to plain-text output and a `sed`-based payload
  parse, so nothing breaks; with it the session-start report arrives as a proper hook JSON envelope.

## Installation

```
/plugin marketplace add duylam/claude-code-engineering-assembly
/plugin install git-autosync@engineering-assembly
```

No settings, no `.local.md`, nothing to configure.

## What runs, and when

| Event | Script | Timeout | What it does |
|---|---|---|---|
| `WorktreeCreate` | `on-worktree-create.sh` | 300s | Syncs the default branch, **then creates the worktree** |
| `SessionStart` (`startup`, `resume`) | `session-start.sh` | 600s | Syncs the default branch, then the submodules |

Timeouts follow the slowest git operation the command can reach: **5 minutes** for a command that
runs `git fetch`, **10 minutes** for one that also runs `git submodule` — a first submodule clone
over a slow link is the worst case either hook has. A killed hook is not retried, so these are
deliberately generous; a hook that finishes early costs nothing.

### Rule zero: stay out of the way

Every hook does **nothing at all**, silently, when the project is:

- not inside a git repository, or
- inside one that has **no remote**.

There is nothing to sync in either case, and a plugin that prints warnings about it would be noise.

### Sync — `git-sync.sh`

Fast-forwards the local default branch from the repository's remote. It targets the **main**
repository even when invoked from a worktree, since that is where the branch refs live.

- **Remote**: the first one `git remote` lists (`origin` in any ordinary clone).
- **Branch**: `main`, falling back to `master`. If the remote has neither, it warns that it cannot
  match a known default branch name and succeeds anyway.
- **Dirty main repo**: warns and stops. Uncommitted work is a human's business.
- **Diverged branch**: warns and stops. It fast-forwards or it does nothing — never a merge commit.
- **Branch checked out somewhere clean**: `git merge --ff-only` in that worktree.
- **Branch checked out nowhere**: `git fetch <remote> main:main` updates the ref directly, touching
  no working tree.

It never runs `git checkout`. An unattended hook must not move a repository off the branch a human
left it on.

It also never touches a branch other than the default one. A feature branch that has fallen behind
`origin/main` stays behind: reconciling it is a merge or a rebase, with conflicts to resolve, and
that is a decision for you rather than for a hook. What the plugin guarantees instead is that a
branch it creates *starts* level with the remote — see the worktree section below.

### Worktree creation — `on-worktree-create.sh`

Claude Code cuts the worktree's branch **before** any other hook runs: `WorktreeCreate` fires in the
main repo while the worktree does not exist yet, and `SessionStart` already runs inside the finished
worktree. `WorktreeCreate` is therefore the only moment at which the default branch can still be
fast-forwarded *in time for the new branch to be cut from it*.

> **This hook replaces Claude Code's built-in `git worktree add`.** `WorktreeCreate` is not an
> observer — whatever the hook prints on stdout *is* the worktree. The hook therefore creates the
> worktree itself:
>
> | | |
> |---|---|
> | directory | `<repo>/.worktrees/<name>` |
> | branch | `worktree-<name>` |
> | cut from | the local default branch the sync just updated — **not** the main repo's `HEAD` |
> | locked | yes, so `git worktree prune` cannot collect a live session's worktree |
>
> The start point is named explicitly, because `git worktree add -b` defaults to `HEAD` — whatever
> branch the clone happened to be left on. That default is what makes a session open on a branch
> already behind `origin/main`, which is the whole thing this hook exists to prevent.
>
> It is the **local** `main`, not `<remote>/main`. When the sync had to stop — dirty repo, diverged
> branch — the local ref still carries commits you made and have not pushed, and a base that
> silently drops them would be worse than one that is merely behind. The sync warns in that case.
> A repo with neither `main` nor `master` falls back to `HEAD`, so an unusual default branch name
> still gets a worktree rather than an error.
>
> An existing `worktree-<name>` branch is reused where it stands and never moved onto the new base:
> it may carry work from an earlier session.
>
> If you already rely on Claude Code's default worktree location (`.claude/worktrees/<name>`),
> note the change of path.

`.worktrees/` is added to `.git/info/exclude` on first use. Without that, the first worktree would
make the main repo permanently dirty — and every later sync would then skip itself on the dirty
check. `info/exclude` is local to the clone, so nothing is committed on your behalf and nothing
appears in a diff.

### Submodules — `ensure-submodules.sh`

Runs against the tree the session actually opened in: the worktree in a worktree session, the
repository itself otherwise.

1. **Populate** every submodule, recursively.
2. **Attach** each *top-level* submodule to a local branch named after the superproject's branch,
   replacing the detached HEAD that `git submodule update` leaves behind. A branch that has to be
   created is based on the **gitlink** — the commit the superproject records for that submodule —
   not on wherever the submodule's own HEAD happens to sit.

Nested submodules are populated but deliberately left on their gitlink: they are vendored
third-party trees, and a branch named after your feature does not belong inside one.

Nothing here is destructive:

- `git submodule update` only runs over a top-level submodule that is **not populated yet**, where
  there is no local work to rewind. A populated one is only asked to fill in its own nested
  submodules.
- `git checkout -B` is never used, so a submodule branch that already carries local commits is
  never moved.

## Failure model

Every hook **always exits 0**. A `SessionStart` hook that fails costs the user a session; a
`WorktreeCreate` hook that fails costs them a worktree. Neither is an acceptable price for a git
problem the plugin could simply report.

So every git failure becomes a `Warning: ...` line naming the exact command to run by hand, and the
session continues. When everything is already correct the plugin prints **nothing at all** — no
output, no context spent.

## Slash commands

Both workers are also available on demand, for re-running a sync mid-session or for testing the
plugin without opening a new one:

| Command | Does |
|---|---|
| `/git-autosync:git-sync` | Fast-forward the default branch from the remote |
| `/git-autosync:submodules-sync` | Populate submodules and attach them to the current branch |

Both accept an optional path; both default to `$CLAUDE_PROJECT_DIR`.

Both are marked `disable-model-invocation: true`: **you** invoke them, the agent cannot. These
commands move git refs and working trees, and the hooks already run them at the only two moments
where doing so unprompted is appropriate. An agent reaching for them mid-task — to "fix" a warning
it was just shown, say — is exactly the behaviour to rule out.

## Running the scripts directly

Every script is a normal CLI with `-h`, usable outside Claude Code:

```bash
bash hooks/git-sync.sh -C /path/to/repo
bash hooks/ensure-submodules.sh -C /path/to/worktree
```

## Layout

```
git-autosync/
├── hooks/
│   ├── hooks.json              # SessionStart + WorktreeCreate registration
│   ├── session-start.sh        # entry point: sync, then submodules, one JSON report
│   ├── on-worktree-create.sh   # entry point: sync, then create the worktree
│   ├── git-sync.sh             # worker: fast-forward the default branch
│   ├── ensure-submodules.sh    # worker: populate + attach submodules
│   └── lib/git-common.sh       # shared helpers (repo/remote resolution, reporting)
└── skills/
    ├── git-sync/SKILL.md
    └── submodules-sync/SKILL.md
```

The two entry points hold the hook plumbing (payload parsing, JSON envelopes, the worktree stdout
contract); the two workers hold the git logic and know nothing about hooks. That is why the skills
can call the workers directly.
