#!/bin/bash
# Runs every git-autosync test. No arguments, no setup, no network: each test
# builds its own throwaway repositories under $TMPDIR and removes them again.
#
#     bash plugins/git-autosync/tests/run.sh
#
# Exits non-zero if any test fails.
set -uo pipefail

readonly DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

failed=0

echo "### syntax"
for f in "$DIR"/../hooks/*.sh "$DIR"/../hooks/lib/*.sh "$DIR"/*.sh; do
    if bash -n "$f"; then
        echo "  PASS  $(basename "$f")"
    else
        echo "  FAIL  $(basename "$f")"
        failed=1
    fi
done
echo

for t in "$DIR"/test-*.sh; do
    echo "### $(basename "$t")"
    bash "$t" || failed=1
    echo
done

if [[ "$failed" -ne 0 ]]; then
    echo "SUITE FAILED"
    exit 1
fi
echo "SUITE PASSED"
