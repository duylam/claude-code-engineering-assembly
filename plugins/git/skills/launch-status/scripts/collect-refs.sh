#!/bin/bash
# Read-only report of branch and commit ids for the superproject and each
# top-level submodule. Never fetches, never writes. Always exits 0: one broken
# submodule must cost that line of the report, not the whole run.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/../../../hooks/lib/git-common.sh"

# "<name> (<sha>)" for an attached branch, "detached HEAD at <sha>" otherwise.
head_line() {
    local repo="$1" sha branch

    sha="$(git -C "$repo" rev-parse --short HEAD 2>/dev/null)" || { echo "no commits yet"; return; }
    branch="$(git -C "$repo" symbolic-ref --short -q HEAD 2>/dev/null)"
    if [[ -n "$branch" ]]; then
        echo "$branch ($sha)"
    else
        echo "detached HEAD at $sha"
    fi
}

# "<label><branch> (<sha>)" for the default branch (main, else master) found under
# refs/$2 of repo $1; $3 is the label prefix ("origin/" or ""). "none" when absent.
default_line() {
    local repo="$1" namespace="$2" prefix="$3" name

    name="$(resolve_default_branch "$repo" "$namespace")"
    if [[ -z "$name" ]]; then
        echo "none (no ${prefix}main or ${prefix}master)"
        return
    fi
    echo "${prefix}${name} ($(git -C "$repo" rev-parse --short "refs/$namespace/$name" 2>/dev/null))"
}

root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "git: not inside a git repository."
    exit 0
}

echo "Repository: $root"
echo "  attached branch:    $(head_line "$root")"

remote="$(first_remote "$root" || true)"
if [[ -n "$remote" ]]; then
    echo "  remote default:     $(default_line "$root" "remotes/$remote" "$remote/")"
else
    echo "  remote default:     none (no remote configured)"
fi
echo "  local default:      $(default_line "$root" heads "")"

echo "Submodules:"
found=0
while IFS=$'\t' read -r _name path; do
    [[ -n "$path" ]] || continue
    found=1
    if [[ -e "$root/$path/.git" ]]; then
        echo "  $path: $(head_line "$root/$path")"
    else
        echo "  $path: not initialised"
    fi
done < <(submodule_entries "$root")
[[ "$found" -eq 1 ]] || echo "  (none)"

exit 0
