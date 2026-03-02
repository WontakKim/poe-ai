#!/usr/bin/env bash
# Usage: bash vendor/ninja/scripts/ingest-item.sh <league> <output_dir> <gameVersion> <ninjaType>
# Input:  poe.ninja ItemOverview API
# Output: <output_dir>/<type>.json, source.json
# Stdout: OK / FILES / ITEMS
# Exit:   0 = success, 1 = error
#
# ninjaType: UniqueWeapon | UniqueArmour | UniqueAccessory | UniqueFlask | UniqueJewel | SkillGem
set -euo pipefail

league="${1:?Usage: $0 <league> <output_dir> <gameVersion> <ninjaType>}"
output_dir="${2:?Usage: $0 <league> <output_dir> <gameVersion> <ninjaType>}"
gameVersion="${3:?Usage: $0 <league> <output_dir> <gameVersion> <ninjaType>}"
ninjaType="${4:?Usage: $0 <league> <output_dir> <gameVersion> <ninjaType>}"

# ── 0. CamelCase → kebab-case for output filename ────────────
type_kebab=$(echo "$ninjaType" | sed 's/\([A-Z]\)/-\1/g' | sed 's/^-//' | tr '[:upper:]' '[:lower:]')

mkdir -p "$output_dir"

TMPDIR="${TMPDIR:-/tmp}"
tmp_raw="$TMPDIR/ninja_item_$$.json"
trap 'rm -f "$tmp_raw"' EXIT

# ── 1. Fetch ItemOverview ────────────────────────────────────
curl -sL "https://poe.ninja/api/data/ItemOverview?league=${league}&type=${ninjaType}" > "$tmp_raw"
[[ -s "$tmp_raw" ]] || { echo "ERROR: Empty response from ItemOverview API (type=${ninjaType})" >&2; exit 1; }
jq empty "$tmp_raw" 2>/dev/null || { echo "ERROR: Invalid JSON from ItemOverview API (type=${ninjaType})" >&2; exit 1; }

# ── 2. Transform: extract fields + conditional optionals ─────
jq '
[
  .lines[] |
  {
    id: .detailsId,
    name: .name,
    baseType: .baseType,
    chaosValue: .chaosValue,
    divineValue: .divineValue,
    volume: .count,
    listingCount: .listingCount,
    trend: .sparkLine.totalChange,
    sparkline: .sparkLine.data
  }
  + (if .variant then {variant: .variant} else {} end)
  + (if .links then {links: .links} else {} end)
  + (if .gemLevel then {gemLevel: .gemLevel} else {} end)
  + (if .gemQuality then {gemQuality: .gemQuality} else {} end)
  + (if .corrupted then {corrupted: .corrupted} else {} end)
] | sort_by(.id)
' "$tmp_raw" > "$output_dir/${type_kebab}.json"

# ── 3. Self-validation ──────────────────────────────────────
if ! jq empty "$output_dir/${type_kebab}.json" 2>/dev/null; then
  echo "ERROR: Invalid JSON in ${type_kebab}.json" >&2
  exit 1
fi

item_count=$(jq length "$output_dir/${type_kebab}.json")
if [[ "$item_count" -eq 0 ]]; then
  echo "ERROR: No items in ${type_kebab}.json" >&2
  exit 1
fi

# Spot-check: first item must have required fields
if ! jq -e '.[0] | has("id", "name", "chaosValue")' "$output_dir/${type_kebab}.json" > /dev/null 2>&1; then
  echo "ERROR: First item missing required fields — data integrity check failed" >&2
  exit 1
fi

# ── 4. Source marker ────────────────────────────────────────
cat > "$output_dir/source.json" <<EOF
{
  "league": "$league",
  "gameVersion": "$gameVersion",
  "ninjaType": "$ninjaType",
  "fetchedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "itemCount": $item_count
}
EOF

# ── 5. Summary ──────────────────────────────────────────────
echo "OK: $output_dir"
echo "FILES: 1"
echo "ITEMS: $item_count"
