#!/usr/bin/env bash
# Usage: bash vendor/pob/scripts/import-character.sh <accountName> <characterName>
#        bash vendor/pob/scripts/import-character.sh "https://poe.ninja/poe1/builds/.../character/Account-1234/CharName"
# Input:  PoE public character API (no auth required)
# Output: JSON to stdout with character metadata + simulation results
# Stderr: OK/ERROR/CHARACTER/LEVEL status messages
# Exit:   0 = success, 1 = error
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_SIM="$SCRIPT_DIR/run-pob-sim.sh"
TMPDIR="${TMPDIR:-/tmp}"
UA="Mozilla/5.0 (compatible; poe-ai-importer/1.0)"
API_HOST="https://www.pathofexile.com"

# Cleanup temp files on exit
trap 'rm -f "${TMPDIR}/pob_import_$$"*' EXIT

# ── Parse arguments ─────────────────────────────────────────────
if [[ $# -eq 1 ]]; then
  url="$1"
  # poe.ninja URL: /poe1/builds/{league}/character/{account}/{character}
  if [[ "$url" =~ poe\.ninja/poe1/builds/[^/]+/character/([^/]+)/([^/]+) ]]; then
    account="${BASH_REMATCH[1]}"
    character="${BASH_REMATCH[2]}"
  else
    echo "ERROR: Unrecognized URL format. Expected: poe.ninja/poe1/builds/{league}/character/{account}/{character}" >&2
    exit 1
  fi
elif [[ $# -eq 2 ]]; then
  account="$1"
  character="$2"
else
  echo "ERROR: Usage: $0 <accountName> <characterName>" >&2
  echo "ERROR: Usage: $0 <poe.ninja-character-URL>" >&2
  exit 1
fi

# ── Validate inputs ─────────────────────────────────────────────
# Reject path traversal and shell metacharacters
if [[ "$account" =~ \.\. ]] || [[ "$character" =~ \.\. ]]; then
  echo "ERROR: Invalid input — path traversal detected" >&2
  exit 1
fi
if [[ ! "$account" =~ ^[A-Za-z0-9_.#%-]+$ ]]; then
  echo "ERROR: Invalid account name — contains disallowed characters" >&2
  exit 1
fi
if [[ ! "$character" =~ ^[A-Za-z0-9_%-]+$ ]]; then
  echo "ERROR: Invalid character name — contains disallowed characters" >&2
  exit 1
fi

# URL-encode # as %23 for API calls
account_encoded="${account//#/%23}"

# ── 1. Fetch character list ────────────────────────────────────
chars_url="${API_HOST}/character-window/get-characters?accountName=${account_encoded}&realm=pc"
http_code=$(curl -sL -o "${TMPDIR}/pob_import_$$_chars.json" -w '%{http_code}' \
  -H "User-Agent: ${UA}" \
  --connect-timeout 10 --max-time 30 \
  "$chars_url")

if [[ "$http_code" == "403" ]]; then
  echo "ERROR: Account profile is private (403)" >&2
  exit 1
fi
if [[ "$http_code" == "404" ]]; then
  echo "ERROR: Account not found (404)" >&2
  exit 1
fi
if [[ "$http_code" != "200" ]]; then
  echo "ERROR: Unexpected HTTP status ${http_code} from get-characters" >&2
  exit 1
fi

# Validate JSON response
if ! jq empty "${TMPDIR}/pob_import_$$_chars.json" 2>/dev/null; then
  echo "ERROR: Invalid JSON from get-characters" >&2
  exit 1
fi

# Find the character in the list (case-insensitive match on character name)
char_json=$(jq -r --arg name "$character" \
  '[.[] | select(.name == $name)] | if length == 0 then empty else .[0] end' \
  "${TMPDIR}/pob_import_$$_chars.json" 2>/dev/null) || true

if [[ -z "$char_json" ]]; then
  echo "ERROR: Character '${character}' not found in account '${account}'" >&2
  exit 1
fi

# Extract character metadata — validate before shell interpolation
char_name=$(printf '%s' "$char_json" | jq -r '.name')
char_class=$(printf '%s' "$char_json" | jq -r '.class')
char_level=$(printf '%s' "$char_json" | jq -r '.level')
char_league=$(printf '%s' "$char_json" | jq -r '.league')

# Validate extracted values (alphanumeric + space + hyphen only)
if [[ ! "$char_name" =~ ^[A-Za-z0-9_%-]+$ ]]; then
  echo "ERROR: Character name from API contains unexpected characters" >&2
  exit 1
fi
if [[ ! "$char_class" =~ ^[A-Za-z]+$ ]]; then
  echo "ERROR: Character class from API contains unexpected characters" >&2
  exit 1
fi
if [[ ! "$char_level" =~ ^[0-9]+$ ]]; then
  echo "ERROR: Character level from API is not a number" >&2
  exit 1
fi
if [[ ! "$char_league" =~ ^[A-Za-z0-9\ %-]+$ ]]; then
  echo "ERROR: Character league from API contains unexpected characters" >&2
  exit 1
fi

echo "CHARACTER: ${char_name} (${char_class})" >&2
echo "LEVEL: ${char_level}" >&2

# URL-encode character name for subsequent API calls
# Pass via stdin to avoid shell interpolation of API-sourced values
char_name_encoded=$(printf '%s' "$char_name" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read()))")

# ── 2. Fetch items ─────────────────────────────────────────────
sleep 1
items_url="${API_HOST}/character-window/get-items?accountName=${account_encoded}&character=${char_name_encoded}&realm=pc"
http_code=$(curl -sL -o "${TMPDIR}/pob_import_$$_items.json" -w '%{http_code}' \
  -H "User-Agent: ${UA}" \
  --connect-timeout 10 --max-time 30 \
  "$items_url")

if [[ "$http_code" != "200" ]]; then
  echo "ERROR: Failed to fetch items (HTTP ${http_code})" >&2
  exit 1
fi
if ! jq empty "${TMPDIR}/pob_import_$$_items.json" 2>/dev/null; then
  echo "ERROR: Invalid JSON from get-items" >&2
  exit 1
fi

# ── 3. Fetch passive skills ────────────────────────────────────
sleep 1
passives_url="${API_HOST}/character-window/get-passive-skills?accountName=${account_encoded}&character=${char_name_encoded}&realm=pc"
http_code=$(curl -sL -o "${TMPDIR}/pob_import_$$_passives.json" -w '%{http_code}' \
  -H "User-Agent: ${UA}" \
  --connect-timeout 10 --max-time 30 \
  "$passives_url")

if [[ "$http_code" != "200" ]]; then
  echo "ERROR: Failed to fetch passives (HTTP ${http_code})" >&2
  exit 1
fi
if ! jq empty "${TMPDIR}/pob_import_$$_passives.json" 2>/dev/null; then
  echo "ERROR: Invalid JSON from get-passive-skills" >&2
  exit 1
fi

# ── 4. Run simulation ──────────────────────────────────────────
sim_result=$(bash "$RUN_SIM" json \
  "${TMPDIR}/pob_import_$$_items.json" \
  "${TMPDIR}/pob_import_$$_passives.json" 2>/dev/null) || {
  echo "ERROR: Simulation failed" >&2
  # Still output what we have — simulation is optional for the import
  jq -n \
    --arg account "$account" \
    --arg name "$char_name" \
    --arg class "$char_class" \
    --argjson level "$char_level" \
    --arg league "$char_league" \
    '{
      character: {account: $account, name: $name, class: $class, level: $level, league: $league},
      simulation: null,
      error: "Simulation failed — character data imported successfully"
    }'
  exit 0
}

# ── 5. Compose final output ────────────────────────────────────
printf '%s' "$sim_result" | jq \
  --arg account "$account" \
  --arg name "$char_name" \
  --arg class "$char_class" \
  --argjson level "$char_level" \
  --arg league "$char_league" \
  '{
    character: {account: $account, name: $name, class: $class, level: $level, league: $league},
    simulation: .
  }'

echo "OK: import complete" >&2
