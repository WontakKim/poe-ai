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

# Detect platform and set native module path
LUA_NATIVE_DIR=""
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)  LUA_NATIVE_DIR="$LUA_MODULES/lib/lua/5.1/darwin-arm64" ;;
  Darwin-x86_64) LUA_NATIVE_DIR="$LUA_MODULES/lib/lua/5.1/darwin-arm64" ;; # Rosetta
  MINGW*|MSYS*|CYGWIN*|Windows*) LUA_NATIVE_DIR="$LUA_MODULES/lib/lua/5.1/win64" ;;
  Linux-x86_64)  LUA_NATIVE_DIR="$LUA_MODULES/lib/lua/5.1/linux-x64" ;;
esac

# Fallback: legacy flat layout
if [[ -z "$LUA_NATIVE_DIR" ]] || [[ ! -d "$LUA_NATIVE_DIR" ]]; then
  LUA_NATIVE_DIR="$LUA_MODULES/lib/lua/5.1"
fi

# Verify luautf8 exists (check both .so and .dll)
if ! ls "$LUA_NATIVE_DIR"/lua-utf8.* >/dev/null 2>&1; then
  echo "ERROR: luautf8 not found in $LUA_NATIVE_DIR" >&2
  exit 1
fi

# Setup Lua paths — include both .so and .dll patterns for cross-platform
export LUA_PATH="$POB_SRC/../runtime/lua/?.lua;$POB_SRC/../runtime/lua/?/init.lua;;"
export LUA_CPATH="$LUA_NATIVE_DIR/?.so;$LUA_NATIVE_DIR/?.dll;;"

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
