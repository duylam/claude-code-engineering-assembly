#!/bin/bash
# Shared scaffolding for the git-autosync tests.
#
# Every test builds throwaway repositories under $SANDBOX and runs the real
# hook scripts against them. Nothing here touches the machine's own repos, and
# no test needs network access - "origin" is a local bare repo.

HOOKS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)"

PASS=0
FAIL=0

check() { # check <description> <expected> <actual>
    if [[ "$2" == "$3" ]]; then
        echo "  PASS  $1"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $1"
        echo "          expected: [$2]"
        echo "          actual:   [$3]"
        FAIL=$((FAIL + 1))
    fi
}

yesno() { [[ -n "$1" ]] && echo yes || echo no; }

# A fresh, empty sandbox directory named after test $1.
#
# `pwd -P` is required, not tidiness: on macOS $TMPDIR is /var/folders/..., a
# symlink to /private/var/folders/..., and git reports the resolved path. A test
# comparing a git-reported path against $SANDBOX fails on the prefix alone.
sandbox() {
    local dir="${TMPDIR:-/tmp}/git-autosync-test-$1.$$"

    rm -rf "$dir"
    mkdir -p "$dir"
    (cd "$dir" && pwd -P)
}

# A bare "remote" plus a seed clone to push from, both under $1.
make_origin() {
    local root="$1"

    git init -q --bare "$root/origin.git" -b main
    git clone -q "$root/origin.git" "$root/seed" 2>/dev/null
    git -C "$root/seed" config user.email test@example.invalid
    git -C "$root/seed" config user.name "test"
    echo c1 > "$root/seed/f"
    git -C "$root/seed" add -A
    git -C "$root/seed" commit -qm c1
    git -C "$root/seed" push -q origin main
}

# One more commit on the remote, as another session's merged PR would leave it.
advance_origin() {
    local root="$1" msg="$2"

    echo "$msg" > "$root/seed/f"
    git -C "$root/seed" commit -qam "$msg"
    git -C "$root/seed" push -q origin main
}

# A developer clone of that remote.
make_clone() {
    local root="$1" name="$2"

    git clone -q "$root/origin.git" "$root/$name"
    git -C "$root/$name" config user.email test@example.invalid
    git -C "$root/$name" config user.name "test"
}

# A second bare remote plus a seed clone, for use as a submodule. Named $2
# under $1, on branch main with one commit.
make_sub_origin() {
    local root="$1" name="$2"

    git init -q --bare "$root/$name.git" -b main
    git clone -q "$root/$name.git" "$root/$name-seed" 2>/dev/null
    git -C "$root/$name-seed" config user.email test@example.invalid
    git -C "$root/$name-seed" config user.name "test"
    echo s1 > "$root/$name-seed/s"
    git -C "$root/$name-seed" add -A
    git -C "$root/$name-seed" commit -qm s1
    git -C "$root/$name-seed" push -q origin main
}

# One more commit on a submodule's remote.
advance_sub_origin() {
    local root="$1" name="$2" msg="$3"

    echo "$msg" > "$root/$name-seed/s"
    git -C "$root/$name-seed" commit -qam "$msg"
    git -C "$root/$name-seed" push -q origin main
}

# Add submodule $2 to the superproject seed and push, declaring `branch = $3`
# in .gitmodules when $3 is given.
attach_submodule() {
    local root="$1" name="$2" branch="${3:-}"

    git -C "$root/seed" -c protocol.file.allow=always \
        submodule add -q "$root/$name.git" "$name" 2>/dev/null
    if [[ -n "$branch" ]]; then
        git -C "$root/seed" config -f .gitmodules "submodule.$name.branch" "$branch"
        git -C "$root/seed" add .gitmodules
    fi
    git -C "$root/seed" commit -qm "add submodule $name"
    git -C "$root/seed" push -q origin main
}

report() {
    echo "=========================================="
    echo "passed: $PASS   failed: $FAIL"
    [[ "$FAIL" -eq 0 ]]
}
