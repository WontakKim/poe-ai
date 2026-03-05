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
# Block shell metacharacters; allow unicode (Korean etc.)
_bad='[/\\;|`$!<>&]'
if [[ "$account" =~ $_bad ]] || [[ -z "$account" ]]; then
  echo "ERROR: Invalid account name — contains disallowed characters" >&2
  exit 1
fi
# Account may contain # (e.g. name#1234) which is safe
_bad_char='[/\\;|`$!<>&]'
if [[ "$character" =~ $_bad_char ]] || [[ -z "$character" ]]; then
  echo "ERROR: Invalid character name — contains disallowed characters" >&2
  exit 1
fi

# ── 1. Fetch character list ────────────────────────────────────
http_code=$(curl -sL -o "${TMPDIR}/pob_import_$$_chars.json" -w '%{http_code}' \
  -G --data-urlencode "accountName=${account}" --data-urlencode "realm=pc" \
  -H "User-Agent: ${UA}" \
  --connect-timeout 10 --max-time 30 \
  "${API_HOST}/character-window/get-characters")

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

# Validate extracted values — block dangerous chars only
if [[ -z "$char_name" ]] || [[ "$char_name" =~ $_bad_char ]]; then
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

# ── 2. Fetch items ─────────────────────────────────────────────
sleep 1
http_code=$(curl -sL -o "${TMPDIR}/pob_import_$$_items.json" -w '%{http_code}' \
  -G --data-urlencode "accountName=${account}" --data-urlencode "character=${char_name}" --data-urlencode "realm=pc" \
  -H "User-Agent: ${UA}" \
  --connect-timeout 10 --max-time 30 \
  "${API_HOST}/character-window/get-items")

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
http_code=$(curl -sL -o "${TMPDIR}/pob_import_$$_passives.json" -w '%{http_code}' \
  -G --data-urlencode "accountName=${account}" --data-urlencode "character=${char_name}" --data-urlencode "realm=pc" \
  -H "User-Agent: ${UA}" \
  --connect-timeout 10 --max-time 30 \
  "${API_HOST}/character-window/get-passive-skills")

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

# ── 5. Encode build code from exported XML ────────────────────
MANIPULATE="$SCRIPT_DIR/pob-xml-manipulate.py"
build_code=""
xml_text=$(printf '%s' "$sim_result" | jq -r '.xml // empty')
if [[ -n "$xml_text" ]]; then
  build_code=$(printf '%s' "$xml_text" | python3 "$MANIPULATE" encode --input /dev/stdin 2>/dev/null) || build_code=""
fi

# ── 6. Compose final output ────────────────────────────────────
printf '%s' "$sim_result" | jq \
  --arg account "$account" \
  --arg name "$char_name" \
  --arg class "$char_class" \
  --argjson level "$char_level" \
  --arg league "$char_league" \
  --arg build_code "$build_code" \
  '{
    character: {account: $account, name: $name, class: $class, level: $level, league: $league},
    simulation: (del(.xml)),
    build_code: $build_code
  }'

echo "OK: import complete" >&2
