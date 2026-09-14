# Git Autosync Plugin

A session should not start on a stale branch, an empty submodule, or a detached HEAD.

This plugin puts the repository into a known-good git state *before the first prompt* of every
session, with no prompting and no configuration:

- the branch you are on is level with the remote's default branch,
- every submodule is populated,
- every top-level submodule sits on a branch — named after the superproject's branch — level with
  *its* remote, so a commit made inside one goes somewhere and starts from something current.

This is the plugin's whole job: at `SessionStart`, bring the effective directory of the session
up to date with the remote (superproject **and** every submodule) and leave the git state
**attached** — the same branch name across the superproject and its submodules. That is the
**must-have state**, and reaching it is all the plugin does.

The sync is always a **merge**: it brings the remote's commits in and never destroys anything. It
runs once, at session start, whether `claude` opened in the current directory or in a
`--spawn worktree` worktree.

> ### Built for Claude Code Remote Sessions
>
> This plugin exists for projects driven through the **Claude Code Remote Session** feature — web,
> mobile, or any launch where nobody is sitting at a terminal to run `git pull` and
> `git submodule update` first.
>
> `claude remote-control --spawn worktree` builds its own worktree, cutting `worktree-<name>` from
> `<remote>/<default>` — a remote-tracking ref only as fresh as the last `git fetch` — and no hook
> of this plugin is consulted while it does. The checkout it starts from may be days old, so without
> this plugin the session's branch opens already behind and its submodules are empty or detached, and
> the agent discovers this halfway through a task, if at all. `SessionStart` runs *inside* the
> finished worktree and is the moment the plugin repairs that. Nothing here is remote-specific, so it
> works fine locally too, but that is the case it was designed around.

## Requirements

- `git`
- `bash` 3.2 or newer — the macOS system `/bin/bash` qualifies
- `jq` — optional. Without it the hook falls back to plain-text output and a `sed`-based payload
  parse, so nothing breaks; with it the session-start report arrives as a proper hook JSON envelope.

The bundled `recap` skill additionally uses `gh` for its pull-request section (optional — see below).

## Installation

```
/plugin marketplace add duylam/claude-code-engineering-assembly
/plugin install git-autosync@engineering-assembly
```

No settings, no `.local.md`, nothing to configure.

## What runs, and when

| Event | Script | Timeout | What it does |
|---|---|---|---|
| `SessionStart` (`startup`, `resume`) | `session-start.sh` | 600s | Syncs **the branch the session opened on**, then the submodules |
| `PreToolUse` (`Bash`, any `git push`) | `protect-branches.sh` | 30s | Blocks pushes that would update `main` or `master` on the remote |

Every run is a merge, and every run exits 0.

The timeout follows the slowest git operation the command can reach: **10 minutes**, because a
`SessionStart` sync runs `git fetch` and then `git submodule` — a first submodule clone over a slow
link is the worst case. A killed hook is not retried, so this is deliberately generous; a hook that
finishes early costs nothing.

### Rule zero: stay out of the way

Nothing is synced, and **nothing is printed**, when the project is:

- not inside a git repository, or
- inside one that has **no remote**.

There is nothing to pull from in either case, and a plugin that printed warnings about it would be
noise.

### Turning the plugin off

One switch turns **all plugin hooks** off: set **`GIT_AUTOSYNC_DISABLE`** to any value other than
`0` and **both hooks become no-ops** — no sync, no branch protection.

### Branch protection

The `PreToolUse` hook intercepts every `git push` command before Claude Code executes it and blocks
any that would update `main` or `master` on the remote.

**Blocked**

| Push form | Reason |
|---|---|
| `git push origin main` | standalone refspec — source and destination are the same |
| `git push origin HEAD:main` | `main` is the explicit destination of the refspec |
| `git push origin feature:main` | `main` is the explicit destination of the refspec |
| `git push origin :main` | deletion form of a refspec — still an update to the remote |
| `git push origin --delete main` | deletion |
| `git push --force origin master` | standalone refspec |
| `git push origin refs/heads/main` | full-ref standalone refspec |
| `git push --all` (when `main` exists locally) | pushes every local branch, including the protected one |
| `git push` or `git push origin` (on `main`) | no explicit refspec — git infers it from the current branch |
| `git push -u origin HEAD` (on `main`) | `HEAD` resolves to the protected branch |

**Allowed**

| Push form | Reason |
|---|---|
| `git push origin feature` | non-protected destination |
| `git push origin main:feature` | `main` is the *source*; `feature` is the remote destination |
| `git push origin feature-main` | substring match only — not a standalone branch name |
| `git push` or `git push origin` (not on `main`/`master`) | current branch is not protected |
| `git push -u origin HEAD` (not on `main`/`master`) | `HEAD` does not resolve to a protected branch |

When blocked, the hook prints a message naming the branch and describing the pull-request workflow,
then exits with status 2. Claude Code surfaces that message to the user and does not run the
original command.

### Sync — `git-sync.sh`

Reconciles **the branch the tree is standing on** with `<remote>/<default>`, then hands the
submodules to `ensure-submodules.sh`.

- **Remote**: the first one `git remote` lists (`origin` in any ordinary clone).
- **Default branch**: `main`, falling back to `master`. If the remote has neither, it warns that it
  cannot match a known default branch name and succeeds anyway.
- **Scope**: whatever branch is checked out where the sync was invoked — the default branch itself,
  a session `worktree-*` branch, or a feature branch you named. In a worktree session that is the
  worktree; in a plain session it is the checkout you are in.
- **Behind the remote** → fast-forward. **Diverged from it** → a merge commit, keeping local work.
- **Detached HEAD**: warns and skips. There is no branch to reconcile.
- **Conflicting merge**: **rolled back**, not left behind. A session handed a half-written index it
  never asked for is worse off than one that is merely unsynced, so the merge is aborted and the
  warning names the command to start it again deliberately.
- **Dirty tree**: the fast-forward or merge is skipped for that tree and reported; nothing is
  merged into uncommitted work.

**The fetch is never gated on a clean working tree.** `git fetch` writes to the object store and the
remote-tracking refs only — it cannot touch a working tree and cannot collide with uncommitted work,
so refusing to run it in a dirty repository buys nothing and costs everything: `origin/main` goes
stale, and every branch later cut from it starts behind. The dirty check lives on the steps that
actually move a tree, and nowhere else.

**A submodule ahead of its gitlink is not a dirty superproject.** Every dirty check ignores submodule
state (`--ignore-submodules=all`) and asks each submodule directly instead. Without that, a
superproject would count as dirty the moment a submodule moved — which is a thing this plugin does on
purpose, on every run — and would never sync again.

#### The default branch's ref

Separately from all of the above, and only when the tree is **not** standing on it, the local default
branch ref is kept fresh, so a later sync — or a branch cut from it — starts from an up-to-date base
even in a session that never checks it out.

That path stays strictly conservative — nobody asked for that branch to be reconciled:

- **checked out somewhere clean** → `git merge --ff-only` in that worktree
- **checked out somewhere dirty** → warns and stops
- **checked out nowhere** → `git fetch <remote> main:main` updates the ref directly, touching no
  working tree
- **diverged** → warns and stops

#### Why the branch you are on is in scope at all

`claude remote-control --spawn worktree` — the launcher behind remote and mobile sessions — builds
its worktree itself, under Claude Code's own `.claude/worktrees/<name>`, and cuts `worktree-<name>`
straight from `<remote>/<default>`: a remote-tracking ref that is only as fresh as the last
`git fetch`. No hook of this plugin is consulted. A session can therefore open on a branch that is
already days behind, which is the one thing the plugin exists to prevent.

`SessionStart` runs *inside* the finished worktree and is the moment to repair that. The merge
reconciles any attached branch — a merge commit loses nothing, and a feature branch drifting behind
for a whole session is a real cost paid to avoid a theoretical one. The one thing it will not do is
touch a **dirty tree**.

### Submodules — `ensure-submodules.sh`

Runs against the tree the session actually opened in: the worktree in a worktree session, the
repository itself otherwise.

1. **Populate** every submodule, recursively.
2. **Attach** each *top-level* submodule to a local branch **named after the superproject's branch**,
   replacing the detached HEAD that `git submodule update` leaves behind. A branch that has to be
   created starts **where the submodule already stands** — its own HEAD once populated. An existing
   branch of that name is simply checked out.
3. **Sync** that branch with the submodule's **own remote**, as a merge.

For a submodule this run just populated, that start point is the commit the superproject records for
it: `git submodule update` checks the gitlink out, so HEAD *is* the gitlink. The two only come apart
for a submodule that was already populated somewhere else — ahead of the gitlink, or on a branch of
its own — and there, branching from HEAD is what stops this from moving the tree out from under
whoever put it there.

#### Which branch a submodule syncs to

A submodule is a repository, so the branch is resolved over *there*, the way git itself defines it:

| in `.gitmodules` | target |
|---|---|
| `branch = release-2` | `<the submodule's remote>/release-2` |
| `branch = .` | git's own shorthand for "whatever the superproject is on" |
| no `branch` key | the submodule's own default branch (`main`, then `master`) |

It is **not** the commit the superproject records for the submodule. A submodule can therefore end up
ahead of the gitlink — that is intended, and it is what makes a session's submodules as current as
its superproject. Committing the new gitlink is your call, not the plugin's.

Nested submodules are populated but deliberately left on their gitlink, with no branch and no sync:
they are vendored third-party trees, and a branch named after your feature does not belong inside
one.

Nothing here is destructive:

- `git submodule update` only runs over a top-level submodule that is **not populated yet**, where
  there is no local work to rewind. A populated one is only asked to fill in its own nested
  submodules.
- `git checkout -B` is never used, so a submodule branch that already carries local commits is
  never moved by the *attach* step.
- a conflicting merge inside a submodule is rolled back, exactly as in the superproject.

## Failure model

The hook **always exits 0**. A `SessionStart` hook that fails costs the user a session, which is not
an acceptable price for a git problem the plugin could simply report.

So every git failure becomes a `Warning: ...` line naming the exact command to run by hand, and the
session continues. When everything is already correct the plugin prints **nothing at all** — no
output, no context spent.

## The `recap` skill

A read-only slash command for the other question a session asks: **where do I stand right now?**
`/git-autosync:recap` reports, for the superproject and each top-level submodule:

- the current local branch **with its commit id**,
- the tracking remote branch **with its commit id** (or `NONE` when the branch was never pushed),
- the working-tree state and the ahead/behind count against the last fetch,
- the pull request(s) whose head is that branch, each tagged `[ready]`, `[draft]`, `[merged]`, or
  `[closed]`.

It also folds in the still-open items from the `work-journal` plugin (when installed) and a recap of
the current conversation. It **only reports** — it never fetches (unless `RECAP_FETCH=1` is set),
pushes, pulls, or commits.

The branch/PR facts come from a bundled collector, usable outside Claude Code too:

```bash
bash skills/recap/scripts/collect-git-state.sh                 # counts against the last fetch
RECAP_FETCH=1 bash skills/recap/scripts/collect-git-state.sh   # fetch each repo first
```

The pull-request section needs `gh` on `PATH` and authenticated; everything else works without it.
Override the binaries with `GIT_BIN=` / `GH_BIN=` when they live outside a bare `PATH`.

## Running the scripts directly

The sync workers are normal CLIs with `-h`, usable outside Claude Code:

```bash
bash hooks/git-sync.sh -C /path/to/repo
bash hooks/ensure-submodules.sh -C /path/to/worktree
```

## Layout

```
git-autosync/
├── hooks/
│   ├── hooks.json              # SessionStart, PreToolUse
│   ├── session-start.sh        # entry point: run the sync, one JSON report
│   ├── protect-branches.sh     # PreToolUse hook: block direct pushes to main/master
│   ├── git-sync.sh             # worker: merge the current branch, then chain the submodules
│   ├── ensure-submodules.sh    # worker: populate + attach + merge submodules
│   └── lib/git-common.sh       # shared helpers (repo/remote resolution, reporting)
├── skills/
│   └── recap/
│       ├── SKILL.md
│       └── scripts/collect-git-state.sh
└── tests/
    ├── run.sh                  # every test; no arguments, no network
    ├── lib.sh                  # throwaway-repo scaffolding + assertions
    ├── test-stale-session-branch.sh
    ├── test-merge-sync.sh
    ├── test-submodule-sync.sh
    ├── test-disable-switch.sh
    └── test-protect-branches.sh
```

```bash
bash plugins/git-autosync/tests/run.sh
```

Each test builds its own bare "remote" and clones under `$TMPDIR`, runs the real hook scripts
against them, and deletes everything afterwards. Nothing touches your own repositories and nothing
reaches the network.

The entry point holds the hook plumbing (payload parsing, JSON envelopes, the `GIT_AUTOSYNC_DISABLE`
guard); the workers hold the git logic and know nothing about hooks.

## What a session actually sees

Everything above describes the hook one guarantee at a time. This section is the other view: you open
an interactive session in some project, and this is what the plugin does to it — start to finish.

| project state | what happens before your first prompt |
|---|---|
| **not a git repo** | nothing, silently |
| **git repo, no remote** | nothing, silently — there is nothing to pull from |
| **git repo, no submodules** | the branch you are on pulled level with `origin/main` |
| **git repo with submodules** | the above, plus every submodule populated, put on a branch, and pulled level with *its* remote |

Only `SessionStart` fires, whether you launched `claude` in a checkout you already have or landed in
a `claude remote-control` worktree cut from a possibly-stale remote-tracking ref. The sync is the
same in both.

**Not a git repo.** Nothing happens and nothing is printed. The plugin is invisible in projects it
has no business touching — no warning, no "skipping" line, no context spent.

**A git repo, no submodules.** Before your first prompt, **the branch you are on** is brought level
with `origin/main` — a fast-forward when it has no commits of its own, a merge commit when it does.
You are never switched between branches; the branch you were on is the branch you stay on. The local
default branch ref is fast-forwarded separately when you are standing somewhere else, so a later sync
or a branch cut from it starts from something current.

A dirty tree is the one thing that stops it: uncommitted work is reported and nothing is merged into
it. A diverged default branch you are *not* on, an unreachable remote, and a merge that conflicts
each produce one `Warning:` line naming the command to run by hand. Uncommitted work never stops the
fetch itself — it cannot be harmed by one.

**A git repo with submodules.** The same sync, and then every submodule is populated recursively —
so no empty directories to discover mid-task — and each top-level one is brought level with its own
remote.

Each *top-level* submodule is then put on a real branch, replacing the detached HEAD that
`git submodule update` leaves behind, so a commit you make inside one has somewhere to land:

- **the branch is named after the superproject's branch.** On `main` you get `main` inside each
  submodule; on `worktree-<name>` you get `worktree-<name>`. One name describes the whole tree.
- **it starts where the submodule already stands** — its own HEAD, right after populating. For a
  submodule that was just cloned in, that is the commit the superproject records for it. For one
  that was already checked out somewhere else, it is wherever you left it, so nothing moves.
- **an existing branch of that name is checked out, never moved.** It may carry work from an earlier
  session, and `checkout -B` is never used.
- **then it is brought level with the submodule's own remote**, at the branch `.gitmodules` says it
  tracks — so a submodule can sit ahead of the gitlink the superproject records. That is the point:
  the submodule is as current as everything else you are working with.

Nested submodules are populated but deliberately left detached, and nothing already populated is
ever rewound.
