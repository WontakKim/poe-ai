#!/usr/bin/env bash
# Support gem optimizer: test alternative support gems and rank by DPS delta.
#
# Usage:
#   bash vendor/pob/scripts/optimize-gems.sh <build_xml> <skill_name> <league>
#
# Arguments:
#   build_xml    Path to PoB XML file
#   skill_name   Skill name to optimize supports for (e.g. "Fire Trap")
#   league       League name for price lookup (e.g. "Keepers")
#
# Output: JSON to stdout with baseline DPS, current supports, and ranked replacements
# Status: stderr OK:/ERROR: messages
# Exit:   0 = success, 1 = error
set -euo pipefail

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
build_xml="${1:?Usage: $0 <build_xml> <skill_name> <league>}"
skill_name="${2:?Missing skill_name argument}"
league="${3:?Missing league argument}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RUN_SIM="$SCRIPT_DIR/run-pob-sim.sh"
MANIPULATE="$SCRIPT_DIR/pob-xml-manipulate.py"
DB_GEMS="$PROJECT_ROOT/db/pob/skill-gem"
DB_NINJA="$PROJECT_ROOT/db/ninja"

# Validate inputs
[[ -f "$build_xml" ]] || { echo "ERROR: build XML not found: $build_xml" >&2; exit 1; }
[[ -f "$RUN_SIM" ]] || { echo "ERROR: run-pob-sim.sh not found" >&2; exit 1; }
[[ -f "$MANIPULATE" ]] || { echo "ERROR: pob-xml-manipulate.py not found" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Temp files with cleanup
# ---------------------------------------------------------------------------
TMPDIR="${TMPDIR:-/tmp}"
tmp_prefix="$TMPDIR/pob_gemopt_$$"
trap 'rm -f "${tmp_prefix}"_*' EXIT

# ---------------------------------------------------------------------------
# Step 1: Baseline simulation
# ---------------------------------------------------------------------------
echo "BASELINE: running simulation for skill '$skill_name'..." >&2
baseline_json=$(bash "$RUN_SIM" xml --skill "$skill_name" < "$build_xml" 2>/dev/null) || {
  echo "ERROR: baseline simulation failed" >&2
  exit 1
}

baseline_dps=$(printf '%s' "$baseline_json" | jq -r '.CombinedDPS // .combinedDPS // 0')
echo "BASELINE: DPS=$baseline_dps" >&2

# ---------------------------------------------------------------------------
# Step 2: Find current supports in the skill group
# ---------------------------------------------------------------------------
gems_json=$(python3 "$MANIPULATE" list-gems --input "$build_xml" 2>/dev/null) || {
  echo "ERROR: list-gems failed" >&2
  exit 1
}

# Find the group that contains the skill
group_info=$(printf '%s' "$gems_json" | jq -c --arg skill "$skill_name" '
  [.[] | select(.gems | any(.nameSpec == $skill))] | .[0] // null
')

if [[ "$group_info" == "null" ]]; then
  echo "ERROR: skill '$skill_name' not found in any gem group" >&2
  exit 1
fi

group_idx=$(printf '%s' "$group_info" | jq -r '.group')
echo "GROUP: $group_idx" >&2

# Extract current support gems (nameSpec containing "Support")
current_supports=$(printf '%s' "$group_info" | jq -c '[
  .gems[] |
  select(.nameSpec != "'"$skill_name"'") |
  select(.nameSpec | test("Support"; "i")) |
  .nameSpec
]')

support_count=$(printf '%s' "$current_supports" | jq 'length')
echo "CURRENT SUPPORTS ($support_count): $(printf '%s' "$current_supports" | jq -r 'join(", ")')" >&2

if [[ "$support_count" -eq 0 ]]; then
  echo "ERROR: no support gems found in the skill group" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 3: Collect all candidate support gem names
# ---------------------------------------------------------------------------
candidate_supports="${tmp_prefix}_candidates.json"
printf '[]' > "$candidate_supports"

for sup_file in "$DB_GEMS"/sup-*.json; do
  [[ -f "$sup_file" ]] || continue
  # Extract unique support gem names
  batch=$(jq -c '[.[].name] | unique' "$sup_file")
  jq -s '.[0] + .[1] | unique' "$candidate_supports" <(printf '%s' "$batch") > "${tmp_prefix}_gem_merged.json"
  mv "${tmp_prefix}_gem_merged.json" "$candidate_supports"
done

# Remove current supports from candidates (no point testing what's already there)
jq -c --argjson current "$current_supports" '[.[] | select(. as $n | $current | index($n) | not)]' \
  "$candidate_supports" > "${tmp_prefix}_filtered.json"
mv "${tmp_prefix}_filtered.json" "$candidate_supports"

total_candidates=$(jq 'length' "$candidate_supports")
# Limit to 30 for performance
if [[ "$total_candidates" -gt 30 ]]; then
  jq -c '.[:30]' "$candidate_supports" > "${tmp_prefix}_limited.json"
  mv "${tmp_prefix}_limited.json" "$candidate_supports"
  total_candidates=30
fi

echo "CANDIDATE SUPPORTS: $total_candidates" >&2

# ---------------------------------------------------------------------------
# Step 4: Load gem price lookup
# ---------------------------------------------------------------------------
ninja_gem_file="$DB_NINJA/$league/skill-gem/skill-gem.json"
price_file="${tmp_prefix}_gem_prices.json"
if [[ -f "$ninja_gem_file" ]]; then
  # Build name->price map for level 1 gems (cheapest entry per name)
  jq '[
    group_by(.name)[] |
    sort_by(.chaosValue) |
    .[0] |
    {key: (.name | ascii_downcase), value: .chaosValue}
  ] | from_entries' "$ninja_gem_file" > "$price_file"
else
  printf '{}' > "$price_file"
fi

# ---------------------------------------------------------------------------
# Step 5: For each current support, try replacing with each candidate
# ---------------------------------------------------------------------------
results_file="${tmp_prefix}_results.json"
printf '[]' > "$results_file"

tested=0
skipped=0

for s_idx in $(seq 0 $((support_count - 1))); do
  old_gem=$(printf '%s' "$current_supports" | jq -r ".[$s_idx]")

  for c_idx in $(seq 0 $((total_candidates - 1))); do
    new_gem=$(jq -r ".[$c_idx]" "$candidate_supports")

    # Swap gem in build XML
    tmp_modified="${tmp_prefix}_mod.xml"
    if ! python3 "$MANIPULATE" swap-gem \
        --input "$build_xml" \
        --group "$group_idx" \
        --old "$old_gem" \
        --new "$new_gem" > "$tmp_modified" 2>/dev/null; then
      skipped=$((skipped + 1))
      rm -f "$tmp_modified"
      continue
    fi

    # Simulate
    sim_json=$(bash "$RUN_SIM" xml --skill "$skill_name" < "$tmp_modified" 2>/dev/null) || {
      skipped=$((skipped + 1))
      rm -f "$tmp_modified"
      continue
    }
    rm -f "$tmp_modified"

    c_dps=$(printf '%s' "$sim_json" | jq -r '.CombinedDPS // .combinedDPS // 0')
    delta_dps=$(awk "BEGIN {printf \"%.1f\", $c_dps - $baseline_dps}")

    # Price lookup
    gem_lower=$(printf '%s' "$new_gem" | tr '[:upper:]' '[:lower:]')
    gem_price=$(jq -r --arg n "$gem_lower" '.[$n] // 0' "$price_file")

    # Efficiency: ΔDPS per chaos
    efficiency=0
    if awk "BEGIN {exit ($gem_price > 0) ? 0 : 1}" 2>/dev/null; then
      efficiency=$(awk "BEGIN {if($gem_price>0) printf \"%.1f\", ($c_dps - $baseline_dps)/$gem_price; else print 0}")
    fi

    entry=$(jq -n \
      --arg replace "$old_gem" \
      --arg with_gem "$new_gem" \
      --argjson ddps "$delta_dps" \
      --arg price "${gem_price}c" \
      --argjson eff "$efficiency" \
      '{replace: $replace, with: $with_gem, delta_dps: $ddps, gem_price: $price, efficiency: $eff}')

    jq --argjson e "$entry" '. += [$e]' "$results_file" > "${tmp_prefix}_r2.json"
    mv "${tmp_prefix}_r2.json" "$results_file"
    tested=$((tested + 1))

    echo "  [$tested] $old_gem -> $new_gem: ΔDPS=$delta_dps" >&2
  done
done

echo "TESTED: $tested, SKIPPED: $skipped" >&2

# ---------------------------------------------------------------------------
# Step 6: Sort by ΔDPS descending, output final JSON
# ---------------------------------------------------------------------------
sorted=$(jq '[.[] | .] | sort_by(-.delta_dps)' "$results_file")

# Final output
jq -n \
  --arg skill "$skill_name" \
  --argjson b_dps "$baseline_dps" \
  --argjson supports "$current_supports" \
  --argjson recommendations "$sorted" \
  '{
    skill: $skill,
    baseline_dps: $b_dps,
    current_supports: $supports,
    recommendations: $recommendations
  }'

echo "OK: gem optimization complete" >&2
