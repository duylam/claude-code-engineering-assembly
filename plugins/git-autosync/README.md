# Git Autosync Plugin

A session should not start on a detached submodule or a branch drifting behind the remote's default.

This plugin puts the working tree into **attached mode** *before the first prompt* of every session,
with no prompting and no configuration:

- the branch you are on is fast-forwarded to the remote's default branch,
- every **top-level** submodule is populated (one level deep),
- each top-level submodule sits on a branch — named after the superproject's branch — level with the
  commit the superproject records for it, so a commit made inside one has somewhere to land.

It runs once, at `SessionStart`, whether `claude` opened in the current directory or in a
`--spawn worktree` worktree, and it acts **only when the root repo is attached** (on a branch). On a
detached HEAD it does nothing.

> ### Network-free: it never fetches
>
> This plugin does not touch the network for the superproject. It reads the remote-tracking refs that
> the companion **`git` plugin** refreshes at `SessionStart`. Install the `git` plugin alongside this
> one so the refs are current; without it, this plugin still runs but reconciles against whatever
> remote-tracking refs already exist locally. (Submodule `update` still clones/fetches submodule
> content on demand — that is populating, not the superproject fetch.)

> ### Built for Claude Code Remote Sessions
>
> This plugin exists for projects driven through the **Claude Code Remote Session** feature — web,
> mobile, or any launch where nobody is sitting at a terminal to run `git submodule update` first.
> `claude remote-control --spawn worktree` builds its own worktree, cutting `worktree-<name>` from
> `<remote>/<default>` and leaving submodules empty or detached. `SessionStart` runs *inside* the
> finished worktree and is the moment the plugin repairs that. Nothing here is remote-specific, so it
> works fine locally too.

## Requirements

- `git`
- `bash` 3.2 or newer — the macOS system `/bin/bash` qualifies
- `jq` — optional. Without it the hook falls back to plain-text output and a `sed`-based payload
  parse, so nothing breaks.
- The **`git` plugin** — recommended, so the remote-tracking refs are fetched and pruned before this
  plugin reads them.

The bundled `recap` skill additionally uses `gh` for its pull-request section (optional).

## Installation

```
/plugin marketplace add duylam/claude-code-engineering-assembly
/plugin install git@engineering-assembly
/plugin install git-autosync@engineering-assembly
```

No settings, no `.local.md`, nothing to configure.

## What runs, and when

| Event | Script | Timeout | What it does |
|---|---|---|---|
| `SessionStart` (`startup`, `resume`) | `session-start.sh` | 300s | Waits for the `git` plugin's fetch, then attaches the branch the session opened on and its submodules |

Every run is fast-forward only, and every run exits 0.

The 300s (5-minute) timeout follows the slowest operation the sync can reach: a first submodule clone
over a slow link, plus a bounded wait for the `git` plugin's fetch. A killed hook is not retried, so
the budget is deliberately generous; a hook that finishes early costs nothing.

### The fetch barrier

The `git` plugin (fetch) and this plugin (attach) run their `SessionStart` hooks in parallel with no
ordering guarantee. To make sure the attach reads freshly-fetched refs, this plugin waits on marker
files the `git` plugin writes in the shared session directory
(`${TMPDIR:-/tmp}/claude-git/<session-id>/`):

- up to **5s** for `fetch-started`. If it never appears (the `git` plugin is not installed or is
  disabled), this plugin proceeds immediately rather than block.
- then up to **4 minutes** for `fetch-done`, which the `git` plugin always writes — even on a failed
  or timed-out fetch — then proceeds regardless.

The wait is bounded and never fails the session. Both bounds are overridable via
`GIT_AUTOSYNC_GRACE_SECS` and `GIT_AUTOSYNC_FETCH_WAIT_SECS` (used by the tests).

### Rule zero: stay out of the way

Nothing is synced, and **nothing is printed**, when the project is:

- not inside a git repository,
- inside one that has **no remote**, or
- on a **detached HEAD** (there is no branch to attach or reconcile).

### Turning the plugin off

Set **`GIT_AUTOSYNC_DISABLE`** to any **non-empty** value and the `SessionStart` hook becomes a
no-op. Unset/empty means enabled (the default). Note: unlike earlier versions, `0` is a non-empty
value and therefore **disables** the plugin.

### Sync — `git-sync.sh`

Fast-forwards **the branch the tree is standing on** to `<remote>/<default>` using the local
remote-tracking refs, then hands the submodules to `ensure-submodules.sh`.

- **Remote**: the first one `git remote` lists (`origin` in any ordinary clone).
- **Default branch**: `main`, falling back to `master`, read from the local `refs/remotes/<remote>/*`.
  If neither exists locally, it warns (the `git` plugin's fetch has not run) and does nothing.
- **Scope**: whatever branch is checked out where the sync was invoked — the default branch itself, a
  session `worktree-*` branch, or a feature branch you named.
- **Behind the remote, clean** → fast-forward. **Diverged** (has its own commits) → left exactly as
  is; nothing is merged, rebased, or forced. **Dirty tree** → skipped and reported.
- **Detached HEAD** → the whole pass is a silent no-op.

**A submodule ahead of its gitlink is not a dirty superproject.** Every dirty check ignores submodule
state (`--ignore-submodules=all`) and asks each submodule directly instead.

### Submodules — `ensure-submodules.sh`

Runs against the tree the session actually opened in.

1. **Populate** every top-level submodule, **one level deep** — nested submodules are left alone.
2. **Attach** each top-level submodule to a local branch **named after the superproject's branch**,
   replacing the detached HEAD that `git submodule update` leaves behind. A branch that has to be
   created starts where the submodule already stands; an existing branch of that name is checked out,
   never moved.
3. **Fast-forward** that branch to the commit the superproject records for the submodule (the
   gitlink). If it can't fast-forward, it is left as is.

Nothing here is destructive: `git submodule update` runs only over a not-yet-populated submodule,
`git checkout -B` is never used, and the reconcile is fast-forward only.

### The attached-mode summary

When the pass runs (the repo was attached), the hook injects **one** short line into the agent's
context: that the repository and each top-level submodule are in attached mode for new commits.
Nothing is injected on a no-op.

## Failure model

The hook **always exits 0**. Every git failure becomes a `Warning: ...` line, and the session
continues. Only the **latest** run's report is kept — persisted per session under the OS temp
directory — and surfaced on demand by the read-only `launch-status` skill.

## The `launch-status` skill

`/git-autosync:launch-status` prints this session's latest attach result (fast-forward and submodule
notes, or warnings). Read-only, human-invoked only; it takes no action. The companion `git` plugin
has its own `/git:launch-status` for the fetch/prune result.

## The `recap` skill

`/git-autosync:recap` reports, for the superproject and each top-level submodule, the current branch
and tracking remote (each with its commit id), the working-tree state, and the matching pull
requests. It only reports — it never fetches (unless `RECAP_FETCH=1`), pushes, pulls, or commits.

The pull-request section needs `gh` on `PATH` and authenticated; everything else works without it.

## Running the scripts directly

```bash
bash hooks/git-sync.sh -C /path/to/repo
bash hooks/ensure-submodules.sh -C /path/to/worktree
```

## Layout

```
git-autosync/
├── hooks/
│   ├── hooks.json              # SessionStart only
│   ├── session-start.sh        # entry: barrier wait, run the sync, persist status, one summary line
│   ├── git-sync.sh             # worker: fast-forward the current branch, then chain the submodules
│   ├── ensure-submodules.sh    # worker: populate (one level) + attach + fast-forward submodules
│   └── lib/git-common.sh       # shared helpers (repo/remote resolution, barrier, status, reporting)
├── skills/
│   ├── launch-status/SKILL.md  # read-only: this session's latest attach status
│   └── recap/
│       ├── SKILL.md
│       └── scripts/collect-git-state.sh
└── tests/
    ├── run.sh                  # every test; no arguments, no network
    ├── lib.sh                  # throwaway-repo scaffolding + assertions
    ├── test-stale-session-branch.sh
    ├── test-merge-sync.sh
    ├── test-submodule-sync.sh
    ├── test-barrier.sh
    ├── test-detached-noop.sh
    └── test-disable-switch.sh
```

```bash
bash plugins/git-autosync/tests/run.sh
```

Each test builds its own bare "remote" and clones under `$TMPDIR`, runs the real hook scripts against
them, and deletes everything afterwards. Nothing touches your own repositories and nothing reaches the
network.

## Relationship to the `git` plugin

Branch-push protection (blocking direct pushes to `main`/`master`) and the repo-wide fetch/prune used
to live here; they now live in the **`git` plugin**. Install both: `git` fetches and protects,
`git-autosync` attaches.
