#!/usr/bin/env bash
# Usage: bash vendor/ninja/scripts/ingest-currency.sh <league> <output_dir> <gameVersion>
# Input:  poe.ninja exchange API (overview) + legacy API (name lookup)
# Output: <output_dir>/currency.json, source.json
# Stdout: OK / FILES / ITEMS
# Exit:   0 = success, 1 = error
set -euo pipefail

league="${1:?Usage: $0 <league> <output_dir> <gameVersion>}"
output_dir="${2:?Usage: $0 <league> <output_dir> <gameVersion>}"
gameVersion="${3:?Usage: $0 <league> <output_dir> <gameVersion>}"

mkdir -p "$output_dir"

TMPDIR="${TMPDIR:-/tmp}"
tmp_overview="$TMPDIR/ninja_overview_$$.json"
tmp_names="$TMPDIR/ninja_names_$$.json"
trap 'rm -f "$tmp_overview" "$tmp_names"' EXIT

# ── 1. Fetch exchange overview ─────────────────────────────────
curl -sL "https://poe.ninja/poe1/api/economy/exchange/current/overview?league=${league}&type=Currency" > "$tmp_overview"
[[ -s "$tmp_overview" ]] || { echo "ERROR: Empty response from exchange overview API" >&2; exit 1; }
jq empty "$tmp_overview" 2>/dev/null || { echo "ERROR: Invalid JSON from exchange overview API" >&2; exit 1; }

# ── 2. Fetch legacy API for name mapping (tradeId → name) ─────
curl -sL "https://poe.ninja/api/data/CurrencyOverview?league=${league}&type=Currency" > "$tmp_names"
[[ -s "$tmp_names" ]] || { echo "ERROR: Empty response from legacy currency API" >&2; exit 1; }
jq empty "$tmp_names" 2>/dev/null || { echo "ERROR: Invalid JSON from legacy currency API" >&2; exit 1; }

# ── 3. Merge: id + name + chaosValue + volume + trend ─────────
jq -n \
  --slurpfile overview "$tmp_overview" \
  --slurpfile names "$tmp_names" \
  '
  # Build tradeId → name lookup (filter out entries with null tradeId)
  ($names[0].currencyDetails | [.[] | select(.tradeId != null) | {(.tradeId): .name}] | add) as $nameMap |
  [
    $overview[0].lines[] |
    {
      id: .id,
      name: ($nameMap[.id] // .id),
      chaosValue: .primaryValue,
      volume: .volumePrimaryValue,
      trend: .sparkline.totalChange,
      sparkline: .sparkline.data
    }
  ] | sort_by(.id)
  ' > "$output_dir/currency.json"

# ── 4. Self-validation ────────────────────────────────────────
if ! jq empty "$output_dir/currency.json" 2>/dev/null; then
  echo "ERROR: Invalid JSON in currency.json" >&2
  exit 1
fi

item_count=$(jq length "$output_dir/currency.json")
if [[ "$item_count" -eq 0 ]]; then
  echo "ERROR: No items in currency.json" >&2
  exit 1
fi

# Spot-check: chaos should always exist
if ! jq -e '.[] | select(.id == "chaos")' "$output_dir/currency.json" > /dev/null 2>&1; then
  echo "ERROR: Missing 'chaos' entry — data integrity check failed" >&2
  exit 1
fi

# ── 5. Source marker ──────────────────────────────────────────
cat > "$output_dir/source.json" <<EOF
{
  "league": "$league",
  "gameVersion": "$gameVersion",
  "fetchedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "itemCount": $item_count
}
EOF

# ── 6. Summary ────────────────────────────────────────────────
echo "OK: $output_dir"
echo "FILES: 1"
echo "ITEMS: $item_count"
