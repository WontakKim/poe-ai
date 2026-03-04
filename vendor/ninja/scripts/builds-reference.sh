#!/usr/bin/env bash
# Usage: bash vendor/ninja/scripts/builds-reference.sh <builds_json> <output_file>
# Input:  builds.json (from ingest-build.sh) + source.json (same directory)
# Output: compact markdown reference for build advisor context
# Stdout: OK summary
# Exit:   0 = success, 1 = error
set -euo pipefail

builds_json="${1:?Usage: $0 <builds_json> <output_file>}"
output_file="${2:?Usage: $0 <builds_json> <output_file>}"

# Validate input exists
[[ -f "$builds_json" ]] || { echo "ERROR: builds.json not found: $builds_json" >&2; exit 1; }

# Derive source.json from same directory as builds_json
source_json="$(dirname "$builds_json")/source.json"
[[ -f "$source_json" ]] || { echo "ERROR: source.json not found: $source_json" >&2; exit 1; }

# Read metadata
league=$(jq -r '.league' "$source_json")
gameVersion=$(jq -r '.gameVersion' "$source_json")
total=$(jq '.total' "$builds_json")
snapshotVersion=$(jq -r '.snapshotVersion' "$builds_json")

# Ensure output directory exists
mkdir -p "$(dirname "$output_file")"

# ── Generate markdown reference ──────────────────────────────────
jq -r --arg league "$league" \
       --arg gameVersion "$gameVersion" \
       --arg total "$total" \
       --arg snapshotVersion "$snapshotVersion" '
# Trend: -1→"down", 1→"up", 0→"—"
def trend_label: if . == -1 then "down" elif . == 1 then "up" else "—" end;

# Header
"# Builds Meta — \($league) (v\($gameVersion))",
"",
"> Source: poe.ninja | \($total) characters | \($snapshotVersion)",
"",

# Top Builds (top 20)
"## Top Builds (top 20)",
"| # | Class | Skill | Share | Trend |",
"|---|-------|-------|-------|-------|",
(.topBuilds[:20] | to_entries[] |
  "| \(.key + 1) | \(.value.class) | \(.value.skill) | \(.value.share)% | \(.value.trend | trend_label) |"),
"",

# Class Distribution
"## Class Distribution",
"| Class | Count | Share |",
"|-------|-------|-------|",
(.class[] | "| \(.name) | \(.count) | \(.share)% |"),
"",

# Main Skills (top 30)
"## Main Skills (top 30)",
"| Skill | Count | Share |",
"|-------|-------|-------|",
(.skills[:30][] | "| \(.name) | \(.count) | \(.share)% |"),
"",

# Items (top 50)
"## Items (top 50)",
"| Item | Count | Share |",
"|------|-------|-------|",
(.items[:50][] | "| \(.name) | \(.count) | \(.share)% |"),
"",

# Keystones (top 30)
"## Keystones (top 30)",
"| Keystone | Count | Share |",
"|----------|-------|-------|",
(.keystones[:30][] | "| \(.name) | \(.count) | \(.share)% |"),
"",

# Support Gems (top 30, filter names ending in " Support")
"## Support Gems (top 30)",
"| Gem | Count | Share |",
"|-----|-------|-------|",
([.allgems[] | select(.name | endswith(" Support"))][:30][] |
  "| \(.name) | \(.count) | \(.share)% |"),
"",

# Weapon Config (top 15)
"## Weapon Config (top 15)",
"| Config | Count | Share |",
"|--------|-------|-------|",
(.weaponmode[:15][] | "| \(.name) | \(.count) | \(.share)% |"),
"",

# Masteries (top 20)
"## Masteries (top 20)",
"| Mastery | Count | Share |",
"|---------|-------|-------|",
(.masteries[:20][] | "| \(.name) | \(.count) | \(.share)% |")
' "$builds_json" > "$output_file"

# Summary
file_size=$(wc -c < "$output_file" | tr -d ' ')
echo "OK builds-reference | ${file_size} bytes | ${output_file}"
