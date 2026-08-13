#!/bin/bash

# ============================================================================
# bootstrap-plugins.sh - SessionStart worker: keep this project's marketplaces
# and plugins installed at user scope
#
# Plugins load BEFORE any SessionStart hook fires, and Claude Code has no
# mid-session plugin loading ("restart required to apply"). So this cannot make
# a plugin appear in the session it runs in; what it does is converge the
# user-scoped install set from the PROJECT's own settings, so a marketplace or
# plugin the project declares is present from the next session on. A plugin a
# prior session already installed at user scope is found by this session's
# plugin-load and is active now - only a newly declared one lags one session.
#
# Source of truth is the PROJECT settings only:
#   <project>/.claude/settings.json
#   <project>/.claude/settings.local.json
# The user file ~/.claude/settings.json is deliberately NOT read - a project's
# hook should provision from the project's declaration, not from whatever the
# machine happens to have configured globally.
#
# Every command is idempotent and best-effort: `marketplace add` on an existing
# marketplace, `install` of an installed plugin, both no-op. Nothing here fails
# the session; the worker ALWAYS exits 0. It prints nothing when the project
# declares nothing - the ordinary case, so an ordinary project pays no cost.
#
# Dependencies: jq and the `claude` CLI. When either is missing the worker warns
# once and exits 0 - the bootstrap is a convenience, never a gate on the session.
# ============================================================================

set -Eeuo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/git-common.sh
# For autosync_disabled and the add_note / add_warning / render_report reporting.
source "$SCRIPT_DIR/lib/git-common.sh"

PROJECT_DIR=""
DRY_RUN=0

usage() {
    cat <<EOF
Usage: $SCRIPT_NAME [-C <project-dir>] [-n]

Adds the marketplaces and installs the plugins declared in a project's
.claude/settings.json (and settings.local.json) at USER scope, so they persist
across sessions. Idempotent; prints nothing when the project declares neither.

Options:
  -C <dir>   Project directory to read settings from (default: \$CLAUDE_PROJECT_DIR, then \$PWD)
  -n         Dry run: print the claude commands that would run, run none
  -h, --help Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -C)
            PROJECT_DIR="${2:-}"
            if [[ -z "$PROJECT_DIR" ]]; then
                echo "$SCRIPT_NAME: -C needs a path" >&2
                exit 1
            fi
            shift 2
            ;;
        -n)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

# GIT_AUTOSYNC_DISABLE turns every hook into a no-op.
if autosync_disabled; then
    exit 0
fi

if [[ -z "$PROJECT_DIR" ]]; then
    PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
fi

# The two project settings files, whichever exist. Order does not matter: the
# jq below unions the marketplace maps and takes the enabled-plugin keys across
# both.
SETTINGS=()
for f in "$PROJECT_DIR/.claude/settings.json" "$PROJECT_DIR/.claude/settings.local.json"; do
    [[ -f "$f" ]] && SETTINGS+=("$f")
done

# Nothing declared here at all: rule zero. No files, nothing to say.
if [[ "${#SETTINGS[@]}" -eq 0 ]]; then
    exit 0
fi

if ! command -v jq >/dev/null 2>&1 || ! command -v claude >/dev/null 2>&1; then
    # Only speak up if the project actually declares something we could not act
    # on; a project with empty settings should still stay silent.
    if grep -qE '"(extraKnownMarketplaces|enabledPlugins)"' "${SETTINGS[@]}" 2>/dev/null; then
        add_warning "$SCRIPT_NAME needs jq and the claude CLI to bootstrap plugins; skipped"
        render_report >&2
    fi
    exit 0
fi

# Run a claude command, or - in dry-run - just report it. Never fails the run.
run_claude() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        add_note "would run: claude $*"
        return 0
    fi
    claude "$@" >/dev/null 2>&1 || true
}

# Collect the whole desired set BEFORE acting, so a project that declares nothing
# stays completely silent - not even a `marketplace update`. `-s` slurps the
# files into an array so a later file's keys override an earlier one's, matching
# how settings layer; `// empty` keeps a missing map from becoming a null row.
# Arrays are filled with a read loop, not mapfile, which bash 3.2 lacks.
SRCS=()
while IFS= read -r src; do
    [[ -n "$src" ]] && SRCS+=("$src")
done < <(jq -rs '
    reduce .[] as $s ({}; . * ($s.extraKnownMarketplaces // {}))
    | to_entries[] | (.value.source.repo // .value.source.path // empty)
' "${SETTINGS[@]}" 2>/dev/null || true)

PLUGINS=()
while IFS= read -r plugin; do
    [[ -n "$plugin" ]] && PLUGINS+=("$plugin")
done < <(jq -rs '
    reduce .[] as $s ({}; . * ($s.enabledPlugins // {}))
    | to_entries[] | select(.value == true) | .key
' "${SETTINGS[@]}" 2>/dev/null || true)

if [[ "${#SRCS[@]}" -eq 0 && "${#PLUGINS[@]}" -eq 0 ]]; then
    exit 0
fi

# Marketplaces first, each at user scope.
for src in ${SRCS[@]+"${SRCS[@]}"}; do
    run_claude plugin marketplace add "$src" --scope user
done

# Refresh every marketplace from its source, so a newly added one - and any that
# moved on - is current before the installs below resolve against it.
run_claude plugin marketplace update

# Then the plugins.
for plugin in ${PLUGINS[@]+"${PLUGINS[@]}"}; do
    run_claude plugin install "$plugin" --scope user
done

render_report >&2
exit 0
