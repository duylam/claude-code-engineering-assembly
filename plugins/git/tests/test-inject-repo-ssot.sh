#!/bin/bash
# The git plugin's SessionStart instruction injector: cat the bundled
# repo-ssot.md to stdout so the harness adds it to the agent's context.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "--- emits the instruction and exits 0, from any directory ---"
out="$(cd "${TMPDIR:-/tmp}" && bash "$HOOKS/inject-repo-ssot.sh" 2>/dev/null)"
rc=$?
check "exit 0" "0" "$rc"
check "injects the SSOT heading" "yes" \
      "$(printf '%s' "$out" | grep -q '^# The Repository Is the Single Source of Truth' && echo yes || echo no)"
check "states the repo wins on conflict" "yes" \
      "$(printf '%s' "$out" | grep -q 'win' && echo yes || echo no)"
check "carries the commit-rationale rule" "yes" \
      "$(printf '%s' "$out" | grep -q 'rationale' && echo yes || echo no)"
echo

echo "--- missing instruction file: silent, exit 0 ---"
TMP="$(sandbox injectssot)"
trap 'rm -rf "$TMP"' EXIT
cp "$HOOKS/inject-repo-ssot.sh" "$TMP/inject-repo-ssot.sh"
check "no repo-ssot.md: exit 0" "0" \
      "$(bash "$TMP/inject-repo-ssot.sh" >/dev/null 2>&1; echo $?)"
check "no repo-ssot.md: silent" "" \
      "$(bash "$TMP/inject-repo-ssot.sh" 2>/dev/null)"
echo

report
