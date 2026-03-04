#!/usr/bin/env bash
# Usage: bash vendor/pob/scripts/run-pob-sim.sh <xml|json> [args...]
# XML:   echo '<build_xml>' | bash run-pob-sim.sh xml [--skill "Name"]
# JSON:  bash run-pob-sim.sh json items.json passives.json
# Stdout: JSON result (on success) or JSON error
# Stderr: OK/ERROR status messages
# Exit:   0 = success, 1 = error
set -euo pipefail

mode="${1:?Usage: $0 <xml|json> [args...]}"
shift

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POB_SRC="$SCRIPT_DIR/../origin/src"
RUNNER="$SCRIPT_DIR/pob-runner.lua"
LUA_MODULES="$SCRIPT_DIR/../lua_modules"

# Validate mode
case "$mode" in
  xml|json) ;;
  *) echo "ERROR: Invalid mode '$mode'. Use: xml, json" >&2; exit 1 ;;
esac

# Verify dependencies
[[ -f "$RUNNER" ]] || { echo "ERROR: pob-runner.lua not found at $RUNNER" >&2; exit 1; }
[[ -d "$POB_SRC" ]] || { echo "ERROR: PoB src directory not found at $POB_SRC" >&2; exit 1; }
command -v luajit >/dev/null 2>&1 || { echo "ERROR: luajit not found in PATH" >&2; exit 1; }
[[ -f "$LUA_MODULES/lib/lua/5.1/lua-utf8.so" ]] || { echo "ERROR: luautf8 not installed at $LUA_MODULES" >&2; exit 1; }

# Setup Lua paths
export LUA_PATH="$POB_SRC/../runtime/lua/?.lua;$POB_SRC/../runtime/lua/?/init.lua;;"
export LUA_CPATH="$LUA_MODULES/lib/lua/5.1/?.so;;"

# Run simulation
cd "$POB_SRC"
result=$(luajit "$RUNNER" "$mode" "$@" 2>/dev/null) || {
  # If luajit failed, check if result contains JSON error
  if [[ -n "$result" ]] && printf '%s' "$result" | jq empty 2>/dev/null; then
    printf '%s\n' "$result"
    echo "ERROR: simulation failed" >&2
    exit 1
  fi
  echo "ERROR: luajit exited with non-zero status" >&2
  exit 1
}

# Validate output is valid JSON
if ! printf '%s' "$result" | jq empty 2>/dev/null; then
  echo "ERROR: Invalid JSON output from pob-runner" >&2
  exit 1
fi

# Check for error in JSON result
if printf '%s' "$result" | jq -e '.error' >/dev/null 2>&1; then
  echo "ERROR: $(printf '%s' "$result" | jq -r '.error')" >&2
  printf '%s\n' "$result"
  exit 1
fi

echo "OK: simulation complete" >&2
printf '%s\n' "$result"
