#!/bin/bash
# The fetch step's local default-branch leveling: after fetching, fast-forward the
# LOCAL default branch (main/master) to its remote-tracking ref so it does not
# drift behind while the session works on another branch. Fast-forward only, and
# only when that branch is checked out in no worktree.
#
# Most cases disable the attach step (GIT_PLUGIN_WORKTREE_ATTACHED_MODE_DISABLED=1)
# so this test isolates step 1: otherwise the attach step would also move branches
# and confound the assertions. Network-free - "origin" is a local bare repo.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SANDBOX="$(sandbox localdefault)"
SID="localdefault-$$"
BASE="${TMPDIR:-/tmp}/claude-git"
trap 'rm -rf "$SANDBOX" "$BASE/$SID"-*' EXIT

make_origin "$SANDBOX"

# Run the SessionStart hook with ONLY step 1 (fetch + local default leveling).
# Prints the hook's stdout (the agent channel), which must stay empty.
run_fetch_step() { # run_fetch_step <repo> <session-suffix>
    printf '{"cwd":"%s","session_id":"%s-%s"}' "$1" "$SID" "$2" \
        | GIT_PLUGIN_WORKTREE_ATTACHED_MODE_DISABLED=1 bash "$HOOKS/session-start.sh" 2>&1
}
status_file() { echo "$BASE/$SID-$1/git.status"; } # status_file <session-suffix>
has_note() { grep -q "$2" "$(status_file "$1")" 2>/dev/null && echo yes || echo no; }
default_note() { # any local-default note (level or diverge) for suffix $1
    grep -E 'fast-forwarded local|has diverged' "$(status_file "$1")" 2>/dev/null
}

echo "--- fast-forwards the local default branch when it is checked out nowhere ---"
make_clone "$SANDBOX" c1
C1="$SANDBOX/c1"; preexclude_worktrees "$C1"
git -C "$C1" checkout -q -b feature          # main now exists but is not checked out
advance_origin "$SANDBOX" ff2                # remote moves ahead of the clone
TIP="$(git -C "$SANDBOX/seed" rev-parse HEAD)"
FEATURE_BEFORE="$(git -C "$C1" rev-parse HEAD)"
out="$(run_fetch_step "$C1" c1)"
check "local main fast-forwarded to the remote tip" "$TIP" "$(git -C "$C1" rev-parse main)"
check "the checked-out feature branch did not move" "$FEATURE_BEFORE" "$(git -C "$C1" rev-parse HEAD)"
check "status records the local default leveling" "yes" "$(has_note c1 'fast-forwarded local main')"
check "nothing is emitted to the agent" "" "$out"
echo

echo "--- leaves the default branch alone when it is the current branch ---"
make_clone "$SANDBOX" c2
C2="$SANDBOX/c2"; preexclude_worktrees "$C2"   # stays on main (the default)
advance_origin "$SANDBOX" cur2                 # remote moves; local main now behind
MAIN_BEFORE="$(git -C "$C2" rev-parse main)"
run_fetch_step "$C2" c2 >/dev/null
check "main not moved by the leveling (it is the checked-out branch)" \
      "$MAIN_BEFORE" "$(git -C "$C2" rev-parse main)"
check "no local-default note recorded" "no" "$(has_note c2 'fast-forwarded local main')"
echo

echo "--- leaves the default branch alone when it is checked out in a linked worktree ---"
make_clone "$SANDBOX" c3
C3="$SANDBOX/c3"; preexclude_worktrees "$C3"
git -C "$C3" checkout -q -b feature
git -C "$C3" worktree add -q "$C3/.claude/worktrees/wmain" main
advance_origin "$SANDBOX" wt2
MAIN_BEFORE="$(git -C "$C3" rev-parse main)"
run_fetch_step "$C3" c3 >/dev/null
check "main not moved (checked out in a linked worktree)" \
      "$MAIN_BEFORE" "$(git -C "$C3" rev-parse main)"
check "no local-default note recorded" "no" "$(has_note c3 'fast-forwarded local main')"
echo

echo "--- leaves a diverged local default branch exactly as it is ---"
make_clone "$SANDBOX" c4
C4="$SANDBOX/c4"; preexclude_worktrees "$C4"
echo localwork > "$C4/localwork"; git -C "$C4" add -A; git -C "$C4" commit -qm "local work on main"
DIVERGED="$(git -C "$C4" rev-parse main)"
git -C "$C4" checkout -q -b feature          # leave the diverged main, not checked out
advance_origin "$SANDBOX" dv2
run_fetch_step "$C4" c4 >/dev/null
check "diverged local main left untouched" "$DIVERGED" "$(git -C "$C4" rev-parse main)"
check "status notes the divergence" "yes" "$(has_note c4 'has diverged')"
echo

echo "--- default branch is not main/master: silent no-op ---"
TR="$SANDBOX/trunkland"; mkdir -p "$TR"
git init -q --bare "$TR/origin.git" -b trunk
git clone -q "$TR/origin.git" "$TR/seed" 2>/dev/null
git -C "$TR/seed" config user.email test@example.invalid
git -C "$TR/seed" config user.name test
echo t1 > "$TR/seed/f"; git -C "$TR/seed" add -A; git -C "$TR/seed" commit -qm t1
git -C "$TR/seed" push -q origin trunk
git clone -q "$TR/origin.git" "$TR/clone"
git -C "$TR/clone" config user.email test@example.invalid
git -C "$TR/clone" config user.name test
C5="$TR/clone"; preexclude_worktrees "$C5"
git -C "$C5" checkout -q -b feature
echo t2 > "$TR/seed/f"; git -C "$TR/seed" commit -qam t2; git -C "$TR/seed" push -q origin trunk
out="$(run_fetch_step "$C5" c5)"
check "no local-default note (default is neither main nor master)" "" "$(default_note c5)"
check "nothing is emitted to the agent" "" "$out"
echo

echo "--- never creates a local default branch that does not exist ---"
make_clone "$SANDBOX" c6
C6="$SANDBOX/c6"; preexclude_worktrees "$C6"
git -C "$C6" checkout -q -b feature
git -C "$C6" branch -D main                   # no local main; origin/main still fetched
advance_origin "$SANDBOX" nb2
run_fetch_step "$C6" c6 >/dev/null
check "local main is not created" "no" \
      "$(git -C "$C6" show-ref --verify --quiet refs/heads/main && echo yes || echo no)"
check "no local-default note recorded" "" "$(default_note c6)"
echo

echo "--- an already-level default branch stays silent ---"
make_clone "$SANDBOX" c7
C7="$SANDBOX/c7"; preexclude_worktrees "$C7"
git -C "$C7" checkout -q -b feature           # local main == origin/main (no advance)
run_fetch_step "$C7" c7 >/dev/null
check "up-to-date main is left silent" "" "$(default_note c7)"
echo

echo "--- both steps on: the local default AND the current branch reach the remote ---"
make_clone "$SANDBOX" c8
C8="$SANDBOX/c8"; preexclude_worktrees "$C8"
git -C "$C8" checkout -q -b feature
advance_origin "$SANDBOX" full2
TIP8="$(git -C "$SANDBOX/seed" rev-parse HEAD)"
printf '{"cwd":"%s","session_id":"%s-c8"}' "$C8" "$SID" | bash "$HOOKS/session-start.sh" >/dev/null 2>&1
check "local main leveled (fetch step)" "$TIP8" "$(git -C "$C8" rev-parse main)"
check "current feature branch attached (attach step)" "$TIP8" "$(git -C "$C8" rev-parse HEAD)"
check "the combined run recorded no warning" "no" "$(has_note c8 'Warning:')"
# A second leveling pass has nothing left to do.
run_fetch_step "$C8" c8b >/dev/null
check "a second leveling run makes no local-default note" "" "$(default_note c8b)"
echo

report
