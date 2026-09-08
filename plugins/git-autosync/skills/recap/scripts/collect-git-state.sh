#!/usr/bin/env bash
#
# Collect branch, tracking, and pull-request state for the superproject and
# every initialised top-level submodule, and print it as a flat text report.
# The local branch and its tracking remote are each printed WITH their commit
# id, so a recap names exactly which commit each side stands on.
#
# Deliberately NOT `set -e`. One uninitialised submodule, one repo without a
# GitHub remote, or one `gh` failure must cost exactly that section of the
# report -- not the whole run. Every failure is printed with a named cause.
set -uo pipefail

GIT_BIN=${GIT_BIN:-git}
GH_BIN=${GH_BIN:-gh}
RECAP_FETCH=${RECAP_FETCH:-0}

have() { command -v "$1" >/dev/null 2>&1; }

if ! have "$GIT_BIN"; then
  echo "fatal: '$GIT_BIN' not found on PATH (override with GIT_BIN=/path/to/git)" >&2
  exit 127
fi

if ! "$GIT_BIN" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "fatal: not inside a git work tree" >&2
  exit 2
fi

GH_AVAILABLE=1
GH_REASON=""
if ! have "$GH_BIN"; then
  GH_AVAILABLE=0
  GH_REASON="'$GH_BIN' not found on PATH (override with GH_BIN=/path/to/gh)"
fi

# ---------------------------------------------------------------------------
# report_repo <dir> <label>
# ---------------------------------------------------------------------------
report_repo() {
  local dir=$1 label=$2
  local name branch head_sha upstream up_sha counts behind ahead state
  local porcelain staged unstaged untracked worktree

  name=$(basename "$("$GIT_BIN" -C "$dir" rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null)
  echo "== $label =="
  echo "path:     $dir"
  echo "repo:     ${name:-unknown}"

  # --- branch (with commit id) ----------------------------------------------
  branch=$("$GIT_BIN" -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null)
  if [ -z "$branch" ]; then
    local sha
    sha=$("$GIT_BIN" -C "$dir" rev-parse --short HEAD 2>/dev/null)
    echo "branch:   (detached HEAD at ${sha:-unknown})"
    echo "upstream: n/a (detached)"
    echo "state:    n/a (detached)"
  else
    head_sha=$("$GIT_BIN" -C "$dir" rev-parse --short HEAD 2>/dev/null)
    echo "branch:   $branch (${head_sha:-unknown})"

    if [ "$RECAP_FETCH" = "1" ]; then
      "$GIT_BIN" -C "$dir" fetch --quiet 2>/dev/null \
        || echo "note:     fetch failed; counts below are against the last successful fetch"
    fi

    # --- tracking remote (with commit id) -----------------------------------
    upstream=$("$GIT_BIN" -C "$dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)
    if [ -z "$upstream" ]; then
      echo "upstream: NONE (no tracking branch set)"
      echo "state:    unpublished -- 'git push -u origin HEAD' to set tracking"
    else
      up_sha=$("$GIT_BIN" -C "$dir" rev-parse --short "$upstream" 2>/dev/null)
      if [ -n "$up_sha" ]; then
        echo "upstream: $upstream ($up_sha)"
      else
        echo "upstream: $upstream (ref missing locally; try RECAP_FETCH=1)"
      fi
      # left  = commits only on upstream  -> behind
      # right = commits only on HEAD      -> ahead
      counts=$("$GIT_BIN" -C "$dir" rev-list --left-right --count "$upstream"...HEAD 2>/dev/null)
      if [ -z "$counts" ]; then
        echo "state:    unknown (upstream ref '$upstream' missing locally; try RECAP_FETCH=1)"
      else
        behind=${counts%%[[:space:]]*}
        ahead=${counts##*[[:space:]]}
        if [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
          state="up to date with $upstream"
        elif [ "$behind" -eq 0 ]; then
          state="ahead $ahead (unpushed)"
        elif [ "$ahead" -eq 0 ]; then
          state="behind $behind (needs pull)"
        else
          state="diverged: ahead $ahead, behind $behind"
        fi
        echo "state:    $state"
      fi
    fi
  fi

  # --- working tree ---------------------------------------------------------
  porcelain=$("$GIT_BIN" -C "$dir" status --porcelain=v1 2>/dev/null)
  if [ -z "$porcelain" ]; then
    worktree="clean"
  else
    staged=$(printf '%s\n' "$porcelain" | grep -c '^[MADRC]' || true)
    unstaged=$(printf '%s\n' "$porcelain" | grep -c '^.[MD]' || true)
    untracked=$(printf '%s\n' "$porcelain" | grep -c '^??' || true)
    worktree="dirty -- staged $staged, unstaged $unstaged, untracked $untracked"
  fi
  echo "worktree: $worktree"

  # --- pull requests for this branch ---------------------------------------
  if [ -z "$branch" ]; then
    echo "prs:      n/a (detached HEAD, no branch to match)"
  elif [ "$GH_AVAILABLE" -eq 0 ]; then
    echo "prs:      unavailable -- $GH_REASON"
  else
    local prs err
    err=$(mktemp)
    prs=$("$GH_BIN" pr list \
            --head "$branch" \
            --state all \
            --limit 10 \
            --json number,title,state,isDraft,url,mergedAt \
            --jq '.[] | "#\(.number) [\(
                    if .state == "OPEN"   then (if .isDraft then "draft" else "ready" end)
                    elif .state == "MERGED" then "merged"
                    else "closed" end
                  )] \(.title) -- \(.url)"' \
            2>"$err")
    if [ $? -ne 0 ]; then
      echo "prs:      unavailable -- $(head -n1 "$err")"
    elif [ -z "$prs" ]; then
      echo "prs:      none for branch '$branch'"
    else
      echo "prs:"
      printf '%s\n' "$prs" | sed 's/^/  /'
    fi
    rm -f "$err"
  fi

  echo
}

# ---------------------------------------------------------------------------
# Superproject
# ---------------------------------------------------------------------------
ROOT=$("$GIT_BIN" rev-parse --show-superproject-working-tree 2>/dev/null)
[ -n "$ROOT" ] || ROOT=$("$GIT_BIN" rev-parse --show-toplevel)

if [ "$RECAP_FETCH" != "1" ]; then
  echo "note: ahead/behind counts are measured against the last fetch."
  echo "      re-run with RECAP_FETCH=1 to fetch each repo first."
  echo
fi

report_repo "$ROOT" "Superproject"

# ---------------------------------------------------------------------------
# Top-level submodules (not recursive -- direct children only)
# ---------------------------------------------------------------------------
if [ ! -f "$ROOT/.gitmodules" ]; then
  echo "== Submodules =="
  echo "(none -- no .gitmodules in the superproject)"
  exit 0
fi

paths=$("$GIT_BIN" -C "$ROOT" config --file .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk '{print $2}')

if [ -z "$paths" ]; then
  echo "== Submodules =="
  echo "(none declared in .gitmodules)"
  exit 0
fi

while IFS= read -r sub; do
  [ -n "$sub" ] || continue
  if [ ! -e "$ROOT/$sub/.git" ]; then
    echo "== Submodule: $sub =="
    echo "path:     $ROOT/$sub"
    echo "state:    not initialised -- run 'git submodule update --init $sub'"
    echo
    continue
  fi
  report_repo "$ROOT/$sub" "Submodule: $sub"
done <<< "$paths"
