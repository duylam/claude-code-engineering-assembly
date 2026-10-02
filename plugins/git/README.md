# Git Plugin

Repo-wide git housekeeping at session start, for **any** git repository. A session
should not start on stale remote-tracking refs, a detached submodule, a local default
branch (`main`/`master`) sitting behind the remote, or the working branch drifting
behind the remote's default. This plugin fixes all of these *before the first prompt*,
with no prompting and no configuration.

At `SessionStart` it runs two steps, **in order, in one process**:

1. **Fetch and prune.** Fetch every branch and every tag from the remote and prune
   stale branch and tag refs, so the local remote-tracking refs are aligned with the
   remote. Then fast-forward the **local default branch** (`main`, falling back to
   `master`) to its remote-tracking ref when it is checked out in no worktree, so it
   does not drift behind while you work on another branch.
2. **Attach the worktree.** Fast-forward the branch this tree is on to the remote's
   default branch (`main`, falling back to `master`) using the refs step 1 just
   fetched, then populate, attach, and fast-forward every **top-level** submodule to
   the commit the superproject records for it.

Because the fetch runs before the attach *in the same process*, the attach always
reads freshly-fetched refs — no cross-process coordination is needed.

The hook runs **synchronously** at `SessionStart`, so the agent only starts once it
finishes, whether `claude` opened in the current directory or in a
`claude remote-control --spawn worktree` worktree.

> ### Built for Claude Code Remote Sessions
>
> The attach step exists for projects driven through the **Claude Code Remote Session**
> feature — web, mobile, or any launch where nobody is sitting at a terminal to run
> `git submodule update` first. `claude remote-control --spawn worktree` builds its own
> worktree, cutting `worktree-<name>` from `<remote>/<default>` and leaving submodules
> empty or detached. `SessionStart` runs *inside* the finished worktree and is the
> moment the plugin repairs that. Nothing here is remote-specific, so it works fine
> locally too.

## Guarantees

- **Does nothing outside a git repo**, or in a repo with no remote.
- **Fast-forward only.** A diverged branch (its own commits) is left exactly as is;
  nothing is ever merged, rebased, or forced. A dirty tree is reported, never moved.
  The local default branch is leveled only when it is checked out in no worktree; one
  checked out elsewhere (e.g. the primary checkout) is left untouched.
- **Attach acts only when the root repo is attached** (on a branch). On a detached
  HEAD the attach step is a silent no-op.
- **Never fails a session.** Every git failure becomes a recorded `Warning: ...`, not
  a failed launch. The hook always exits 0.

## Requirements

- `git`
- `bash` 3.2 or newer — the macOS system `/bin/bash` qualifies
- `jq` — optional. Without it the hook falls back to plain-text output and a `sed`-based
  payload parse, so nothing breaks.

The bundled `recap` skill additionally uses `gh` for its pull-request section (optional).

## Installation

```
/plugin marketplace add duylam/claude-code-engineering-assembly
/plugin install git@engineering-assembly
```

No settings, no `.local.md`, nothing to configure.

## What runs, and when

| Event | Script | Timeout | What it does |
|---|---|---|---|
| `SessionStart` (`startup`, `resume`) | `session-start.sh` | 300s | Fetches + prunes, levels the local default branch, then attaches the branch the session opened on and its submodules |

Every run is fast-forward only, and every run exits 0. The 300s (5-minute) timeout
follows the slowest operation the hook can reach: a first submodule clone over a slow
link. A killed hook is not retried, so the budget is deliberately generous; a hook that
finishes early costs nothing.

### Turning steps off

Each step has its own off switch. Set either to any **non-empty** value (including `0`)
to turn that step into a no-op; unset/empty means enabled (the default):

| Variable | Effect |
|---|---|
| `GIT_PLUGIN_GIT_FETCH_DISABLED` | Skip the fetch step (and the local default-branch leveling); the attach step still runs against whatever remote-tracking refs already exist locally. |
| `GIT_PLUGIN_WORKTREE_ATTACHED_MODE_DISABLED` | Skip the attach step; the fetch/prune still runs. |

Set both to disable the plugin entirely.

### Rule zero: stay out of the way

Nothing is synced, and **nothing is printed**, when the project is not inside a git
repository, or is inside one that has **no remote**. The attach step additionally does
nothing on a **detached HEAD** (there is no branch to attach or reconcile).

### Fetch — step 1

`git fetch --all --tags --prune --prune-tags` on the main checkout's object store.
Brings every branch and tag level with the remote and prunes refs the remote no longer
has, so the attach step and the rest of the session see the true remote state.

It then levels the **local default branch** (`main`, falling back to `master`) to its
refreshed remote-tracking ref, so that branch stays current even while the session works
on another one. This is **fast-forward only** and acts only when the branch is safe to
move without touching a working tree: a local default branch checked out in any worktree
(the current tree — that is the attach step's job — or the primary checkout) is left
untouched, a diverged one is left as is, and a missing one is never created. The ref is
advanced with an atomic compare-and-swap, so it is never forced or rewound. It runs
whether or not the fetch itself succeeded (it is safe against a stale ref) and is
disabled together with the fetch via `GIT_PLUGIN_GIT_FETCH_DISABLED`.

### Attach — `git-sync.sh`

Fast-forwards **the branch the tree is standing on** to `<remote>/<default>` using the
local remote-tracking refs (no fetch of its own — step 1 did that), then hands the
submodules to `ensure-submodules.sh`.

- **Remote**: the first one `git remote` lists (`origin` in any ordinary clone).
- **Default branch**: `main`, falling back to `master`, read from the local
  `refs/remotes/<remote>/*`.
- **Scope**: whatever branch is checked out where the session opened — the default
  branch itself, a session `worktree-*` branch, or a feature branch you named.
- **Behind the remote, clean** → fast-forward. **Diverged** → left exactly as is.
  **Dirty tree** → skipped and reported. **Detached HEAD** → silent no-op.

**A submodule ahead of its gitlink is not a dirty superproject.** Every dirty check
ignores submodule state (`--ignore-submodules=all`) and asks each submodule directly.

### Submodules — `ensure-submodules.sh`

Runs against the tree the session actually opened in.

1. **Populate** every top-level submodule, **one level deep** — nested submodules are
   left alone.
2. **Attach** each top-level submodule to a local branch **named after the
   superproject's branch**, replacing the detached HEAD `git submodule update` leaves
   behind. A branch that has to be created starts where the submodule already stands; an
   existing branch of that name is checked out, never moved.
3. **Fast-forward** that branch to the commit the superproject records for the submodule
   (the gitlink). If it can't fast-forward, it is left as is.

Nothing here is destructive: `git submodule update` runs only over a not-yet-populated
submodule, `git checkout -B` is never used, and the reconcile is fast-forward only.

### The attached-mode summary

When the attach step runs (the repo was attached), the hook injects **one** short line
into the agent's context: that the repository and each top-level submodule are in
attached mode for new commits. Nothing is injected on a no-op or when the attach step
is disabled.

## Launch status

Only the **latest** status is kept, per session, under the OS temp directory
(`${TMPDIR:-/tmp}/claude-git/<session-id>/git.status`). It combines the fetch/prune
result and the attach report, and is not shown to the agent. To read it yourself:

```
/git:launch-status
```

## The `recap` skill

`/git:recap` reports, for the superproject and each top-level submodule, the current
branch and tracking remote (each with its commit id), the working-tree state, and the
matching pull requests. It only reports — it never fetches (unless `RECAP_FETCH=1`),
pushes, pulls, or commits. The pull-request section needs `gh` on `PATH` and
authenticated; everything else works without it.

## Running the scripts directly

```bash
bash hooks/git-sync.sh -C /path/to/repo
bash hooks/ensure-submodules.sh -C /path/to/worktree
```

## Layout

```
git/
├── hooks/
│   ├── hooks.json              # SessionStart only
│   ├── session-start.sh        # entry: fetch + prune, then attach, persist status, one summary line
│   ├── git-sync.sh             # worker: fast-forward the current branch, then chain the submodules
│   ├── ensure-submodules.sh    # worker: populate (one level) + attach + fast-forward submodules
│   └── lib/git-common.sh       # shared helpers (repo/remote resolution, status, reporting)
├── skills/
│   ├── launch-status/SKILL.md  # read-only: this session's latest fetch + attach status
│   └── recap/
│       ├── SKILL.md
│       └── scripts/collect-git-state.sh
└── tests/
    ├── run.sh                  # every test; no arguments, no network
    ├── lib.sh                  # throwaway-repo scaffolding + assertions
    ├── test-fetch-prune.sh
    ├── test-fetch-before-attach.sh
    ├── test-local-default-sync.sh
    ├── test-merge-sync.sh
    ├── test-submodule-sync.sh
    ├── test-stale-session-branch.sh
    ├── test-detached-noop.sh
    └── test-disable-switch.sh
```

```bash
bash plugins/git/tests/run.sh
```

Each test builds its own bare "remote" and clones under `$TMPDIR`, runs the real hook
scripts against them, and deletes everything afterwards. Nothing touches your own
repositories and nothing reaches the network.

## Migration from the `git-autosync` plugin

The attach-only sync, the `launch-status` for it, and the `recap` skill used to live in a
separate **`git-autosync`** plugin that waited on a fetch barrier this plugin wrote. They
are now folded in here, so there is one plugin and no barrier. To migrate:

- Enable **`git@engineering-assembly`** (it now does both the fetch and the attach) and
  **remove `git-autosync@engineering-assembly`** — that plugin no longer exists.
- The skills moved: `/git-autosync:launch-status` → `/git:launch-status` (now covering
  fetch *and* attach) and `/git-autosync:recap` → `/git:recap`.
- The off switches were renamed (hard rename, no aliases):
  `GIT_PLUGIN_DISABLE` → `GIT_PLUGIN_GIT_FETCH_DISABLED`, and
  `GIT_AUTOSYNC_DISABLE` → `GIT_PLUGIN_WORKTREE_ATTACHED_MODE_DISABLED`.
