#!/bin/bash

# ============================================================================
# inject-repo-ssot.sh — carry the "repository is the Single Source of Truth"
# instruction with the plugin instead of hand-pasting it into each project's
# CLAUDE.md.
#
# Driven by hooks.json on SessionStart (startup|resume|clear|compact): stdout is
# added to the session context. A static doc needs no tiering or marker — every
# fresh or wiped context simply gets the full instruction once via `cat`.
# ============================================================================

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTRUCTION="$SCRIPT_DIR/repo-ssot.md"

[[ -f "$INSTRUCTION" ]] || exit 0
cat "$INSTRUCTION"
exit 0
