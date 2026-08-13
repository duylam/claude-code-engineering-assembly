#!/bin/bash
# bootstrap-plugins.sh - the SessionStart plugin/marketplace bootstrap. Reads the
# PROJECT's settings only, never ~/.claude/settings.json, and shells out to a
# stubbed `claude` so nothing touches the machine's real install.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BOOT="$HOOKS/bootstrap-plugins.sh"

SANDBOX="$(sandbox bootstrap)"
trap 'rm -rf "$SANDBOX"' EXIT

# A stub `claude` on PATH that logs its arguments, one call per line.
BIN="$SANDBOX/bin"
mkdir -p "$BIN"
cat > "$BIN/claude" <<'SH'
#!/bin/bash
echo "$*" >> "$CLAUDE_LOG"
SH
chmod +x "$BIN/claude"
export PATH="$BIN:$PATH"
export CLAUDE_LOG="$SANDBOX/calls.log"

calls() { [[ -f "$CLAUDE_LOG" ]] && cat "$CLAUDE_LOG" || true; }
reset_log() { : > "$CLAUDE_LOG"; }

# A project directory declaring one marketplace and one enabled + one disabled
# plugin, split across settings.json and settings.local.json.
PROJ="$SANDBOX/project"
mkdir -p "$PROJ/.claude"
cat > "$PROJ/.claude/settings.json" <<'EOF'
{
  "extraKnownMarketplaces": { "mkt": { "source": { "repo": "acme/plugins" } } },
  "enabledPlugins": { "wanted@mkt": true, "unwanted@mkt": false }
}
EOF
cat > "$PROJ/.claude/settings.local.json" <<'EOF'
{ "enabledPlugins": { "local-plugin@mkt": true } }
EOF

# An empty project - declares nothing.
EMPTY="$SANDBOX/empty"
mkdir -p "$EMPTY/.claude"
echo '{}' > "$EMPTY/.claude/settings.json"

if ! command -v jq >/dev/null 2>&1; then
    echo "  SKIP  bootstrap call assertions (jq not installed)"
else
    echo "--- a project's marketplaces and enabled plugins are installed at user scope ---"
    reset_log
    bash "$BOOT" -C "$PROJ" >/dev/null 2>&1
    log="$(calls)"
    check "marketplace added --scope user" "yes" \
          "$([[ "$log" == *"plugin marketplace add acme/plugins --scope user"* ]] && echo yes || echo no)"
    check "marketplaces refreshed" "yes" \
          "$([[ "$log" == *"plugin marketplace update"* ]] && echo yes || echo no)"
    check "enabled plugin installed --scope user" "yes" \
          "$([[ "$log" == *"plugin install wanted@mkt --scope user"* ]] && echo yes || echo no)"
    check "settings.local plugin installed too" "yes" \
          "$([[ "$log" == *"plugin install local-plugin@mkt --scope user"* ]] && echo yes || echo no)"
    check "the disabled plugin is skipped" "no" \
          "$([[ "$log" == *"unwanted@mkt"* ]] && echo yes || echo no)"
    echo

    echo "--- dry-run runs no claude commands ---"
    reset_log
    plan="$(bash "$BOOT" -n -C "$PROJ" 2>&1)"
    check "stub was never called" "" "$(calls)"
    check "and it reported what it would run" "yes" \
          "$([[ "$plan" == *"would run: claude plugin install wanted@mkt --scope user"* ]] && echo yes || echo no)"
    echo

    echo "--- a project declaring nothing is a silent no-op ---"
    reset_log
    out="$(bash "$BOOT" -C "$EMPTY" 2>&1)"
    check "no output" "" "$out"
    check "no claude calls" "" "$(calls)"
    echo

    echo "--- the disable switch no-ops the bootstrap ---"
    reset_log
    GIT_AUTOSYNC_DISABLE=1 bash "$BOOT" -C "$PROJ" >/dev/null 2>&1
    check "no claude calls when disabled" "" "$(calls)"
    echo

    echo "--- ~/.claude/settings.json is NOT a source ---"
    FAKEHOME="$SANDBOX/home"
    mkdir -p "$FAKEHOME/.claude"
    cat > "$FAKEHOME/.claude/settings.json" <<'EOF'
{ "extraKnownMarketplaces": { "homeonly": { "source": { "repo": "home/only" } } } }
EOF
    reset_log
    HOME="$FAKEHOME" bash "$BOOT" -C "$EMPTY" >/dev/null 2>&1
    check "a marketplace only in \$HOME is never read" "no" \
          "$([[ "$(calls)" == *"home/only"* ]] && echo yes || echo no)"
    echo
fi

report
