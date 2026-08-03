# Git Autosync Plugin

A session should not start on a stale branch, an empty submodule, or a detached HEAD.

This plugin puts the repository into a known-good git state *before the first prompt* of every
session, with no prompting and no configuration:

- the branch you are on is level with the remote's default branch,
- a new worktree is cut from that freshly synced branch, not from whatever was left behind days ago,
- every submodule is populated,
- every top-level submodule sits on a branch, level with *its* remote, so a commit made inside one
  goes somewhere and starts from something current,

and when the session quits, the worktree it created is removed again, branch and all — so a hundred
sessions leave no trace of themselves in your repository.

Everything above is the **merge** mode, which never destroys anything and is the only mode the hooks
can reach. A second mode, **reset**, is available on demand for the times you want the remote's
state and nothing else — see [sync modes](#sync-modes).

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
| `WorktreeCreate` | `on-worktree-create.sh` | 300s | Syncs the main repo, **then creates the worktree** |
| `SessionStart` (`startup`, `resume`) | `session-start.sh` | 600s | Syncs **the branch the session opened on**, then the submodules |
| `WorktreeRemove` | `on-worktree-remove.sh` | 120s | Removes the worktree and its branch when the session quits |

No hook ever passes a mode, so **every unattended run is `merge`** and every unattended run exits 0.
`reset` exists only behind a slash command a human types.

Timeouts follow the slowest git operation the command can reach: **5 minutes** for a command that
runs `git fetch`, **10 minutes** for one that also runs `git submodule` — a first submodule clone
over a slow link is the worst case either hook has. A killed hook is not retried, so these are
deliberately generous; a hook that finishes early costs nothing. Teardown gets **2 minutes**: it
touches nothing but the local disk.

### Rule zero: stay out of the way

Nothing is synced, and **nothing is printed**, when the project is:

- not inside a git repository, or
- inside one that has **no remote**.

There is nothing to pull from in either case, and a plugin that printed warnings about it would be
noise.

Worktrees are the exception, because they need no remote: one is still created off whatever local
default branch exists, and still removed again when the session ends. Both are purely local
operations.

### Sync modes

One sync operation, two mutually exclusive modes. They apply to the superproject and to every
submodule alike.

| | `merge` (default) | `reset` |
|---|---|---|
| behind the remote | fast-forward | hard reset |
| diverged from it | merge commit | hard reset, local commits discarded |
| dirty tree, anywhere | warns, skips that tree | **refuses the whole run**, changes nothing |
| exit status | always 0 | non-zero when it refused |
| reachable from a hook | yes, always | never |

`reset` is the answer to "just give me what's on the remote". It is deliberately all-or-nothing:
before it moves a single ref it checks the superproject **and every populated submodule** for
uncommitted work, and one dirty tree anywhere aborts the whole operation. A reset that rewound the
superproject and only then noticed a dirty submodule would leave a repository no single command puts
back.

What it discards is still in the reflog, and the note it prints names the commit:

```
reset worktree-foo to origin/main (a1b2c3d) in /repo; the previous tip 9f8e7d6 is
still reachable from the reflog
```

Mode selection lives in the slash commands only — `/git-autosync:git-sync reset`. There is no
setting, no environment variable, and no way for a hook or an agent to reach it.

### Sync — `git-sync.sh`

Reconciles **the branch the tree is standing on** with `<remote>/<default>`, then hands the
submodules to `ensure-submodules.sh`.

- **Remote**: the first one `git remote` lists (`origin` in any ordinary clone).
- **Default branch**: `main`, falling back to `master`. If the remote has neither, it warns that it
  cannot match a known default branch name and succeeds anyway.
- **Scope**: whatever branch is checked out where the sync was invoked — the default branch itself,
  a session `worktree-*` branch, or a feature branch you named. In a worktree session that is the
  worktree; in a plain session it is the checkout you are in.
- **Detached HEAD**: warns and skips. There is no branch to reconcile.
- **Conflicting merge**: **rolled back**, not left behind. A session handed a half-written index it
  never asked for is worse off than one that is merely unsynced, so the merge is aborted and the
  warning names the command to start it again deliberately.

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
branch ref is kept fresh: `on-worktree-create.sh` cuts new worktrees from it, so it has to be current
even in a session that never checks it out.

That path is unchanged from earlier versions and stays strictly conservative — nobody asked for that
branch to be reconciled:

- **checked out somewhere clean** → `git merge --ff-only` in that worktree
- **checked out somewhere dirty** → warns and stops
- **checked out nowhere** → `git fetch <remote> main:main` updates the ref directly, touching no
  working tree
- **diverged** → warns and stops, in both modes

#### Why the branch you are on is in scope at all

`WorktreeCreate` is the plugin's preferred moment to get a session branch right, but **it does not
always fire**. `claude remote-control --spawn worktree` — the launcher behind remote and mobile
sessions — builds its worktree itself, under Claude Code's own `.claude/worktrees/<name>`, and cuts
`worktree-<name>` straight from `<remote>/<default>`: a remote-tracking ref that is only as fresh as
the last `git fetch`. No hook of this plugin is consulted. A session can therefore open on a branch
that is already days behind, which is the one thing the plugin exists to prevent.

`SessionStart` runs *inside* the finished worktree and is the last moment to repair that.

Earlier versions repaired only the narrow case where nothing could be lost: a linked worktree, on a
`worktree-*` branch, with no commits of its own and a clean tree. Everything else was reported and
left alone. That is no longer the line — merge mode reconciles any attached branch, because a merge
commit loses nothing either, and a feature branch drifting behind for a whole session was a real
cost paid to avoid a theoretical one. What survives from the old rule is the part that mattered:
**a dirty tree is still never touched**, in either mode.

### Worktree creation — `on-worktree-create.sh`

Claude Code cuts the worktree's branch **before** any other hook runs: `WorktreeCreate` fires in the
main repo while the worktree does not exist yet, and `SessionStart` already runs inside the finished
worktree. `WorktreeCreate` is therefore the only moment at which the default branch can still be
fast-forwarded *in time for the new branch to be cut from it*.

> `WorktreeCreate` fires for `claude --worktree` and for subagents with `isolation: worktree`. It
> does **not** fire for `claude remote-control --spawn worktree`, which creates its worktree
> outside the hook entirely — see [session-branch alignment](#session-branch-alignment) for how the
> sync repairs that case after the fact.

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

**Both** worktree roots — `.worktrees/` (this plugin's) and `.claude/worktrees/` (Claude Code's) —
are added to `.git/info/exclude`, on every sync, not only when this hook runs. Excluding just the
plugin's own is not enough: a repository driven by remote sessions fills the *other* directory, and
one unignored worktree directory makes the main checkout permanently dirty. `info/exclude` is local
to the clone, so nothing is committed on your behalf and nothing appears in a diff.

Each entry is written at most once, and only when git does not already ignore it — a `.gitignore`
that lists `.worktrees/` is honoured and nothing is added for it.

### Worktree teardown — `worktree-cleanup.sh`

Taking over `WorktreeCreate` means taking over the other end of the lifecycle too. Claude Code stops
running its own `git worktree remove` for a worktree a hook created and fires `WorktreeRemove`
instead — so without this hook, **every worktree session would leave its directory and its branch
behind forever**. The `git worktree lock` above makes that permanent rather than temporary: Claude
Code's periodic sweep never releases a lock it did not set itself.

So when the session ends, the worktree and its `worktree-<name>` branch go away.

> **This is the one destructive script in the plugin, and it does not ask.** The worktree is removed
> whatever state it is in — uncommitted changes, untracked files and unpushed commits all go with
> it. A worktree Claude Code has finished with is disposable by construction; if you want to keep
> what is in one, commit it and push it, or set the escape hatch below.
>
> Set **`GIT_AUTOSYNC_KEEP_WORKTREE=1`** and nothing is removed. The hook reports what it would have
> deleted (visible under `claude --debug`) and stops. Reopening `claude --worktree <same-name>` then
> picks the worktree up exactly where you left it.

It fires for three different reasons, and only two of them mean *the session is over*:

| `reason` | | |
|---|---|---|
| `session_end` | the Claude Code instance quit | cleans up |
| `user_delete` | `claude delete <session>` | cleans up |
| `subagent_end` | a subagent with its own worktree finished | **leaves it alone** |

A subagent with `isolation: worktree` gets a *separate* worktree of its own, and `subagent_end`
fires while the conversation that spawned it is still running. Whatever the subagent left on disk is
worth more than the disk space is, so the plugin does not touch it; Claude Code's own periodic sweep
reclaims the work-free ones on its own schedule.

What it refuses to touch, in every case:

- **anything git does not report as a linked worktree** of the repository. Being registered in
  `git worktree list` is the proof of ownership — a directory that merely looks like a worktree is
  not one, and an already-removed worktree is silently nothing to do.
- **the main checkout**, which is listed by `git worktree list` too and is excluded by name.
- **any branch not named `worktree-*`.** Point Claude Code at a worktree you made yourself and the
  directory goes but your branch stays.
- **anything remote.** No push, no `push --delete`, no fetch. Only local disk.

Submodules need no special handling in practice. Git gives a submodule populated inside a worktree
its own directory under `.git/worktrees/<name>/`, and removing the worktree takes that with it, so
the `worktree-<name>` branch inside each submodule disappears on its own. Where a git version shares
that directory with the main checkout instead, the branch is deleted only if the superproject
already records every commit on it — an unmerged one is left alone and named in the report.

### Submodules — `ensure-submodules.sh`

Runs against the tree the session actually opened in: the worktree in a worktree session, the
repository itself otherwise.

1. **Populate** every submodule, recursively.
2. **Attach** each *top-level* submodule to a local branch **named after the superproject's branch**,
   replacing the detached HEAD that `git submodule update` leaves behind. A branch that has to be
   created starts **where the submodule already stands** — its own HEAD once populated. An existing
   branch of that name is simply checked out.
3. **Sync** that branch with the submodule's **own remote**, in the same mode as the superproject.

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

In merge mode nothing here is destructive:

- `git submodule update` only runs over a top-level submodule that is **not populated yet**, where
  there is no local work to rewind. A populated one is only asked to fill in its own nested
  submodules.
- `git checkout -B` is never used, so a submodule branch that already carries local commits is
  never moved by the *attach* step.
- a conflicting merge inside a submodule is rolled back, exactly as in the superproject.

Reset mode is destructive by definition — see [sync modes](#sync-modes) for the preflight that makes
it all-or-nothing.

## Failure model

Every hook **always exits 0**. A `SessionStart` hook that fails costs the user a session; a
`WorktreeCreate` hook that fails costs them a worktree. Neither is an acceptable price for a git
problem the plugin could simply report.

So every git failure becomes a `Warning: ...` line naming the exact command to run by hand, and the
session continues. When everything is already correct the plugin prints **nothing at all** — no
output, no context spent.

The sync workers do have one failure path: `reset` mode exits non-zero when its preflight finds a
dirty tree. That path is unreachable from a hook — no hook passes `--mode`, and `merge` is the
default — so the contract above is intact. A human who types `/git-autosync:git-sync reset` gets a
real error, which is what they need; a session that never asked for one never sees it.

`branch-name.sh` is the other exception, and for the same reason: it is never run from a hook. It
exits non-zero when the *superproject* cannot be switched, because nothing meaningful happened.

Teardown is the exception to who reads those warnings: Claude Code surfaces `WorktreeRemove` output
in debug mode only, and by then you have left anyway. Run `claude --debug` to see it, or re-run
`worktree-cleanup.sh` by hand — a cleanup that half-finished leaves the worktree registered, and
running it again picks up where it stopped.

## Slash commands

The workers are also available on demand, for re-running a sync mid-session, for reaching `reset`
mode, or for testing the plugin without opening a new session:

| Command | Does |
|---|---|
| `/git-autosync:git-sync [merge\|reset]` | Sync the current branch, then the submodules |
| `/git-autosync:submodules-sync [merge\|reset]` | The submodule half alone, without touching the superproject |
| `/git-autosync:branch-name [name]` | Put the superproject **and every submodule** on one named branch |

All three accept an optional path; all three default to `$CLAUDE_PROJECT_DIR`. The two sync commands
default to `merge` when no mode is named.

`branch-name` is for the moment a session on `worktree-a3f19c` turns into real work that deserves a
name. It creates the branch at the current HEAD — so uncommitted work comes along — or switches to it
when it already exists, never moving it. Called with no argument, the agent infers a short kebab-case
name from the conversation and states it before running.

It is also **how work outlives a session**: teardown deletes the worktree's branch only when that
name starts with `worktree-`, so once the tree is on a real name, the commits stay.

All three are marked `disable-model-invocation: true`: **you** invoke them, the agent cannot. These
commands move git refs and working trees, and the hooks already run the safe half of that at the only
two moments where doing so unprompted is appropriate. An agent reaching for them mid-task — to "fix"
a warning it was just shown, say — is exactly the behaviour to rule out. It matters more now than it
used to: one of these can discard commits.

## Running the scripts directly

Every script is a normal CLI with `-h`, usable outside Claude Code:

```bash
bash hooks/git-sync.sh -C /path/to/repo                     # --mode merge, implied
bash hooks/git-sync.sh --mode reset -C /path/to/repo        # destructive; exits 1 if dirty
bash hooks/ensure-submodules.sh -C /path/to/worktree
bash hooks/branch-name.sh -C /path/to/worktree add-oauth-login
bash hooks/worktree-cleanup.sh -n -C /path/to/repo/.worktrees/name   # -n: report only
```

`worktree-cleanup.sh` is the way to reclaim worktrees a previous session left behind — from before
this plugin handled teardown, or from a `claude -p` run. Try `-n` first: it prints what it would
remove and removes nothing.

## Layout

```
git-autosync/
├── hooks/
│   ├── hooks.json              # SessionStart + WorktreeCreate + WorktreeRemove registration
│   ├── session-start.sh        # entry point: run the sync, one JSON report
│   ├── on-worktree-create.sh   # entry point: sync, then create the worktree
│   ├── on-worktree-remove.sh   # entry point: filter the reason, then tear down
│   ├── git-sync.sh             # worker: sync the current branch, then chain the submodules
│   ├── ensure-submodules.sh    # worker: populate + attach + sync submodules
│   ├── branch-name.sh          # worker: one branch name across superproject + submodules
│   ├── worktree-cleanup.sh     # worker: remove a worktree and its branch
│   └── lib/git-common.sh       # shared helpers (repo/remote resolution, modes, reporting)
├── skills/
│   ├── git-sync/SKILL.md
│   ├── submodules-sync/SKILL.md
│   └── branch-name/SKILL.md
└── tests/
    ├── run.sh                  # every test; no arguments, no network
    ├── lib.sh                  # throwaway-repo scaffolding + assertions
    ├── test-stale-session-branch.sh
    ├── test-sync-modes.sh
    ├── test-submodule-sync.sh
    ├── test-branch-name.sh
    └── test-worktree-lifecycle.sh
```

```bash
bash plugins/git-autosync/tests/run.sh
```

Each test builds its own bare "remote" and clones under `$TMPDIR`, runs the real hook scripts
against them, and deletes everything afterwards. Nothing touches your own repositories and nothing
reaches the network.

The three entry points hold the hook plumbing (payload parsing, JSON envelopes, the worktree stdout
contract, the `reason` filter); the four workers hold the git logic and know nothing about hooks.
That is why the skills can call the workers directly.

`worktree-cleanup.sh` has no skill on purpose. The other workers are safe to re-run at any moment in
their default mode; this one deletes a working tree unconditionally, with no mode to soften it.

## What a session actually sees

Everything above describes one hook at a time. This section is the other view: you open an
interactive session in some project, and this is what the plugin does to it — start to finish.

|  | `claude` | `claude --worktree <name>` |
|---|---|---|
| **not a git repo** | nothing, silently | ⚠️ the session does not start |
| **git repo, no submodules** | the branch you are on pulled level with `origin/main` before your first prompt | you work in `.worktrees/<name>` on `worktree-<name>`, cut from the freshly pulled `main`; both are deleted when you quit |
| **git repo with submodules** | the above, plus every submodule populated, put on a branch, and pulled level with *its* remote | the above, plus submodules populated *inside* the worktree and put on `worktree-<name>` |

One rule cuts across the whole table: **in a repository with no remote, no sync happens and nothing
is printed** — there is nothing to pull from. Worktrees still work there; creating and removing one
never needs a remote.

### Without a worktree

You run `claude` in the project directory and work in the checkout you already have. Only
`SessionStart` fires.

**Not a git repo.** Nothing happens and nothing is printed. The plugin is invisible in projects it
has no business touching — no warning, no "skipping" line, no context spent.

**A git repo, no submodules.** Before your first prompt, **the branch you are on** is brought level
with `origin/main` — a fast-forward when it has no commits of its own, a merge commit when it does.
You are never switched between branches; the branch you were on is the branch you stay on. The local
default branch ref is fast-forwarded separately when you are standing somewhere else, so a worktree
cut later starts from something current.

A dirty tree is the one thing that stops it: uncommitted work is reported and nothing is merged into
it. A diverged default branch you are *not* on, an unreachable remote, and a merge that conflicts
each produce one `Warning:` line naming the command to run by hand. Uncommitted work never stops the
fetch itself — it cannot be harmed by one.

> **This is a change from earlier versions.** Up to 0.5.x a feature branch was never touched;
> only `main`/`master` and the session's own `worktree-*` branch were in scope. It is now merged
> from `origin/main` like any other. If you want the old behaviour for a particular branch, keep the
> tree dirty or work outside the plugin — there is no setting for it.

**A git repo with submodules.** The same sync, and then every submodule is populated recursively —
so no empty directories to discover mid-task — and each top-level one is brought level with its own
remote.

Each *top-level* submodule is then put on a real branch, replacing the detached HEAD that
`git submodule update` leaves behind, so a commit you make inside one has somewhere to land:

- **the branch is named after the superproject's branch.** On `main` you get `main` inside each
  submodule; on `feature-x` you get `feature-x`. One name describes the whole tree.
- **it starts where the submodule already stands** — its own HEAD, right after populating. For a
  submodule that was just cloned in, that is the commit the superproject records for it. For one
  that was already checked out somewhere else, it is wherever you left it, so nothing moves.
- **an existing branch of that name is checked out, never moved.** It may carry work from an earlier
  session, and `checkout -B` is never used.
- **then it is brought level with the submodule's own remote**, at the branch `.gitmodules` says it
  tracks — so a submodule can sit ahead of the gitlink the superproject records. That is the point:
  the submodule is as current as everything else you are working with.

Nested submodules are populated but deliberately left detached, and nothing already populated is
ever rewound in merge mode.

### With a worktree

`claude --worktree <name>` runs the full set: `WorktreeCreate` before the session exists,
`SessionStart` inside it, `WorktreeRemove` when you quit.

**Not a git repo.** ⚠️ **The session fails to start.** `WorktreeCreate` has no repository to make a
worktree in, `git worktree add` fails, and a failed `WorktreeCreate` aborts the launch with git's own
error. Worktrees require a git repository whether or not this plugin is installed — but with it
installed the message you get is git's, not Claude Code's. Run `claude` without `--worktree` there.

**A git repo, no submodules.** Before the branch is cut, `main` is fast-forwarded from the remote —
`WorktreeCreate` is the only moment where that is still in time to matter. You then land in
`.worktrees/<name>` on a new `worktree-<name>` branch cut from that just-updated `main`, rather than
from whatever branch the checkout happened to be sitting on. `.worktrees/` is added to
`.git/info/exclude` on first use so it never shows up as untracked in your main checkout.

The sync then runs a second time from `SessionStart`, now inside the worktree. That one is one cheap
`git fetch` that finds nothing to do and stays silent.

When you quit, the worktree directory and its `worktree-<name>` branch are both deleted — including
anything you had not committed. Your main checkout is untouched and nothing is pushed or deleted on
the remote. Set `GIT_AUTOSYNC_KEEP_WORKTREE=1` to keep everything instead; reopening
`claude --worktree <same-name>` then resumes exactly where you left off, because an existing
`worktree-<name>` branch is always reused where it stands and never moved onto a newer base.

**A git repo with submodules.** A worktree is a fresh checkout, so its submodule directories start
out **empty** — this is the case where `SessionStart` populating them matters most.

The same rule then applies as above, and the superproject's branch here is `worktree-<name>`:

- **the branch inside each top-level submodule is also named `worktree-<name>`**, matching the
  superproject, so a commit you make inside a submodule lands on a branch belonging to this session
  rather than on a detached HEAD.
- **it starts at the submodule's HEAD right after populating**, which in a fresh worktree is the
  commit the superproject records for it — a worktree's submodules have nowhere else to have been.
- **an existing `worktree-<name>` branch is checked out as-is**, which is how a reopened worktree
  picks its submodules back up exactly where the last session left them.

Teardown handles them without you noticing: git keeps a worktree's submodules under
`.git/worktrees/<name>/`, so removing the worktree removes their branches too, and nothing is left
in your main checkout's submodules.

### Two things worth knowing

**`claude -p` is different.** Non-interactive runs have no exit prompt, and Claude Code does not
clean up their worktrees. If teardown does not run for one, remove it with
`bash hooks/worktree-cleanup.sh -C <path>` or `git worktree remove --force --force <path>` —
plain `--force` is not enough, because these worktrees are locked.

**Subagent worktrees are left behind on purpose.** A subagent with `isolation: worktree` gets its own
worktree from the same `WorktreeCreate` hook, but the plugin does not remove it when the subagent
finishes — the conversation is still going and its output may still be wanted.

Claude Code has a periodic sweep for exactly these, governed by `cleanupPeriodDays`, and it skips any
worktree still holding work. Whether it reaches the plugin's is not something to rely on: these
worktrees are locked, and the sweep releases only locks Claude Code set itself. If they accumulate,
clear them yourself — `-n` first to see what would go:

```bash
bash hooks/worktree-cleanup.sh -n -C <repo>/.worktrees/<name>
```
