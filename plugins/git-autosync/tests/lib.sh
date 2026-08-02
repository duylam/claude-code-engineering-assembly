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

report() {
    echo "=========================================="
    echo "passed: $PASS   failed: $FAIL"
    [[ "$FAIL" -eq 0 ]]
}
