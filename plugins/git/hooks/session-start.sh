#!/bin/bash

# ============================================================================
# session-start.sh - SessionStart hook: fetch, then attach, before the first prompt
#
# Two steps run in order, in this one process:
#   1. Fetch: bring the repository's remote-tracking refs level with the remote -
#      fetch every branch and every tag from every remote, prune stale branch and
#      tag refs.                     (skip with GIT_PLUGIN_GIT_FETCH_DISABLED)
#   2. Attach: fast-forward the branch this tree is on to the remote's default
#      branch using those just-fetched refs, and attach every top-level
#      submodule.          (skip with GIT_PLUGIN_WORKTREE_ATTACHED_MODE_DISABLED)
#
# The fetch runs before the attach in the SAME process, so the attach always
# reads fresh refs. That ordering is why no cross-process barrier is needed.
#
# What this hook produces:
#   - The human status: the fetch/prune result and the attach report (notes and
#     warnings) are persisted together as this session's latest status, read on
#     demand by the read-only launch-status skill. Only the latest is kept.
#   - The agent context: when the attach step ran (the tree was attached), ONE
#     short summary line is injected so the session knows the git state is
#     attached for new commits, in the superproject and its submodules. Nothing
#     is injected on a detached-HEAD / non-git / no-remote no-op.
#
# Never fails a session: does nothing outside a git repo or in a repo with no
# remote, warns instead of failing on a fetch error, and ALWAYS exits 0.
#
# Off switches (each non-empty value disables that step):
#   GIT_PLUGIN_GIT_FETCH_DISABLED              - skip the fetch step
#   GIT_PLUGIN_WORKTREE_ATTACHED_MODE_DISABLED - skip the attach step
#
# Dependencies: git; jq (optional - only used to read cwd/session_id from the
# hook payload, with a sed fallback).
# ============================================================================

set -uo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/git-common.sh
source "$SCRIPT_DIR/lib/git-common.sh"

payload="$(cat || true)"

# Pull a scalar string field out of the hook payload. jq when available, a
# narrow sed fallback otherwise (cwd and session_id are plain strings).
payload_field() {
    local key="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -r --arg k "$key" '.[$k] // empty' <<<"$payload" 2>/dev/null || true
    else
        sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" <<<"$payload" | head -n 1
    fi
}

# The directory Claude Code started in. In a worktree session this is the
# worktree, which is exactly the tree whose branch and submodules must be synced.
cwd="$(payload_field cwd)"
if [[ -z "$cwd" || ! -d "$cwd" ]]; then
    cwd="$PWD"
fi
session_id="$(payload_field session_id)"

# Outside a git repo, or a repo with no remote: nothing to fetch and nothing to
# attach. Stay out of the way, silently.
MAIN_REPO="$(resolve_main_repo "$cwd")" || exit 0
REMOTE="$(first_remote "$MAIN_REPO")" || exit 0

# --- Step 1: fetch + prune (unless disabled) --------------------------------
# Every branch and every tag from every remote, pruning stale branch and tag
# refs so the local remote-tracking refs match the remote exactly.
if ! git_fetch_disabled; then
    if run_capture git -C "$MAIN_REPO" fetch --all --tags --prune --prune-tags; then
        add_note "fetched and pruned $REMOTE (branches and tags)"
    else
        add_warning "could not fetch $REMOTE ($(capture_reason))"
    fi
fi

# --- Step 2: attach the tree (unless disabled) ------------------------------
# git-sync.sh fast-forwards the branch this tree is on to <remote>/<default>
# using the refs step 1 just refreshed, then attaches top-level submodules. It
# exits 0 when the pass ran, 10 for a clean no-op (detached HEAD / not a git
# repo / no remote). Its plain-text report comes back on stdout.
attach_report=""
attach_ran=0
if ! worktree_attach_disabled; then
    attach_report="$(bash "$SCRIPT_DIR/git-sync.sh" -C "$cwd" 2>/dev/null)"
    attach_rc=$?
    # git-sync.sh exits 0 (pass ran) or 10 (clean no-op). Anything else is an
    # abnormal exit - e.g. a broken plugin install failing before git-sync.sh
    # arms its own ERR trap, which would leave no note at all. Record it so
    # launch-status shows a signal instead of silence.
    if [[ "$attach_rc" -eq 0 ]]; then
        attach_ran=1
    elif [[ "$attach_rc" -ne 10 ]]; then
        add_warning "the attach step exited abnormally (rc $attach_rc)"
    fi
fi

# --- Persist the combined human status --------------------------------------
# The fetch notes/warnings (this process) followed by the attach report
# (git-sync.sh). Empty is fine: an already-correct repo writes an empty file.
DIR="$(session_dir "$session_id" || true)"
if [[ -n "$DIR" ]]; then
    { render_report; [[ -n "$attach_report" ]] && printf '%s\n' "$attach_report"; } \
        >"$DIR/git.status" 2>/dev/null || true
fi

# --- Agent context ----------------------------------------------------------
# The attached-mode summary is for the AGENT, not the human. On SessionStart,
# Claude Code adds `hookSpecificOutput.additionalContext` (and plain-text stdout)
# to the model's context - that is the channel that reaches the LLM. It is
# emitted only when the attach step actually ran (rc 0); a detached / non-git /
# no-remote no-op, or a disabled attach step, injects nothing. `systemMessage` is
# deliberately NOT set: it surfaces only in the human's terminal and would not
# reach the model.
if [[ "$attach_ran" -eq 1 ]]; then
    summary="The git repository is in attached mode for new commits. Each top-level submodule is in attached mode for new commits (inside the submodule)."
    if command -v jq >/dev/null 2>&1; then
        jq -n --arg msg "$summary" \
            '{
                hookSpecificOutput: {
                    hookEventName: "SessionStart",
                    additionalContext: $msg
                }
            }'
    else
        # No jq: plain stdout is added to the model's context on SessionStart.
        echo "$summary"
    fi
fi

exit 0
