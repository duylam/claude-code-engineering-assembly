#!/bin/bash
# launch-status prints branch and commit ids: attached branch, remote default
# (origin/main, else origin/master), local default (main, else master), and each
# top-level submodule. Read-only: it never fetches.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

export GIT_ALLOW_PROTOCOL=file

COLLECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../skills/launch-status/scripts" && pwd)/collect-refs.sh"

SANDBOX="$(sandbox refs)"
trap 'rm -rf "$SANDBOX"' EXIT

make_origin "$SANDBOX"
make_sub_origin "$SANDBOX" tracked
attach_submodule "$SANDBOX" tracked main
make_clone "$SANDBOX" clone
CLONE="$SANDBOX/clone"
git -C "$CLONE" submodule update -q --init tracked 2>/dev/null

run() { (cd "$1" && bash "$COLLECT" 2>&1); }
sha() { git -C "$1" rev-parse --short "$2"; }

echo "--- attached on main, in sync ---"
out="$(run "$CLONE")"
MAIN="$(sha "$CLONE" HEAD)"
check "attached branch with commit id" "  attached branch:    main ($MAIN)" "$(grep 'attached branch' <<<"$out")"
check "remote default is origin/main" "  remote default:     origin/main ($MAIN)" "$(grep 'remote default' <<<"$out")"
check "local default is main" "  local default:      main ($MAIN)" "$(grep 'local default' <<<"$out")"
echo

echo "--- feature branch, local main behind origin/main (no fetch is run) ---"
git -C "$CLONE" checkout -q -b feature
echo f > "$CLONE/g"; git -C "$CLONE" add g; git -C "$CLONE" commit -qm feat
advance_origin "$SANDBOX" c2
git -C "$CLONE" fetch -q origin
out="$(run "$CLONE")"
check "attached branch is feature" "  attached branch:    feature ($(sha "$CLONE" HEAD))" "$(grep 'attached branch' <<<"$out")"
check "remote default moved" "  remote default:     origin/main ($(sha "$CLONE" origin/main))" "$(grep 'remote default' <<<"$out")"
check "local default stayed" "  local default:      main ($MAIN)" "$(grep 'local default' <<<"$out")"
echo

echo "--- submodules ---"
git -C "$CLONE/tracked" checkout -q main
out="$(run "$CLONE")"
check "submodule line" "  tracked: main ($(sha "$CLONE/tracked" HEAD))" "$(grep '^  tracked:' <<<"$out")"
git -C "$CLONE/tracked" checkout -q --detach
out="$(run "$CLONE")"
check "detached submodule" "  tracked: detached HEAD at $(sha "$CLONE/tracked" HEAD)" "$(grep '^  tracked:' <<<"$out")"
git -C "$CLONE" submodule deinit -q -f tracked 2>/dev/null
rm -rf "$CLONE/tracked/.git" "$CLONE/.git/modules/tracked"
out="$(run "$CLONE")"
check "uninitialised submodule" "  tracked: not initialised" "$(grep '^  tracked:' <<<"$out")"
echo

echo "--- detached superproject HEAD ---"
git -C "$CLONE" checkout -q --detach
out="$(run "$CLONE")"
check "detached HEAD reported" "  attached branch:    detached HEAD at $(sha "$CLONE" HEAD)" "$(grep 'attached branch' <<<"$out")"
echo

echo "--- master fallback ---"
git -C "$CLONE" checkout -q main
git -C "$CLONE" branch -q -m main master
git -C "$CLONE" update-ref -d refs/remotes/origin/main
git -C "$CLONE" update-ref refs/remotes/origin/master "$(git -C "$CLONE" rev-parse master)"
out="$(run "$CLONE")"
check "remote falls back to origin/master" "  remote default:     origin/master ($(sha "$CLONE" master))" "$(grep 'remote default' <<<"$out")"
check "local falls back to master" "  local default:      master ($(sha "$CLONE" master))" "$(grep 'local default' <<<"$out")"
echo

echo "--- no remote, no submodules ---"
git init -q -b work "$SANDBOX/plain"
git -C "$SANDBOX/plain" -c user.email=t@e.invalid -c user.name=t commit -q --allow-empty -m c
out="$(run "$SANDBOX/plain")"
check "no remote" "  remote default:     none (no remote configured)" "$(grep 'remote default' <<<"$out")"
check "no local default" "  local default:      none (no main or master)" "$(grep 'local default' <<<"$out")"
check "no submodules" "  (none)" "$(grep '(none)' <<<"$out")"
echo

echo "--- outside a repository ---"
mkdir "$SANDBOX/empty"
check "not a repo" "git: not inside a git repository." "$(run "$SANDBOX/empty")"

report
