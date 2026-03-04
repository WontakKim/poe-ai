#!/usr/bin/env bash
# Item upgrade optimizer: simulate unique item replacements and rank by DPS delta.
#
# Usage:
#   bash vendor/pob/scripts/optimize-items.sh <build_xml> <slot> <league> [budget_divine] [--skill "Name"]
#
# Arguments:
#   build_xml      Path to PoB XML file
#   slot           Item slot (e.g. "Body Armour", "Helmet", "Ring 1", "Weapon 1")
#   league         League name for price lookup (e.g. "Keepers")
#   budget_divine  Optional max divine value filter
#   --skill        Optional skill name for DPS measurement
#
# Output: JSON to stdout with baseline stats, candidate rankings, and deltas
# Status: stderr OK:/ERROR: messages
# Exit:   0 = success, 1 = error
set -euo pipefail

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
build_xml="${1:?Usage: $0 <build_xml> <slot> <league> [budget_divine] [--skill \"Name\"]}"
slot="${2:?Missing slot argument}"
league="${3:?Missing league argument}"
shift 3

budget_divine=""
skill_name=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skill) skill_name="${2:?--skill requires a value}"; shift 2 ;;
    *)
      if [[ -z "$budget_divine" ]]; then
        budget_divine="$1"; shift
      else
        echo "ERROR: unexpected argument: $1" >&2; exit 1
      fi
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
RUN_SIM="$SCRIPT_DIR/run-pob-sim.sh"
MANIPULATE="$SCRIPT_DIR/pob-xml-manipulate.py"
DB_POB="$PROJECT_ROOT/db/pob/unique-item"
DB_NINJA="$PROJECT_ROOT/db/ninja"

# Validate inputs
[[ -f "$build_xml" ]] || { echo "ERROR: build XML not found: $build_xml" >&2; exit 1; }
[[ -f "$RUN_SIM" ]] || { echo "ERROR: run-pob-sim.sh not found" >&2; exit 1; }
[[ -f "$MANIPULATE" ]] || { echo "ERROR: pob-xml-manipulate.py not found" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Temp files with cleanup
# ---------------------------------------------------------------------------
TMPDIR="${TMPDIR:-/tmp}"
tmp_prefix="$TMPDIR/pob_opt_$$"
trap 'rm -f "${tmp_prefix}"_*' EXIT

# ---------------------------------------------------------------------------
# Map slot -> DB file(s) and ninja category
# ---------------------------------------------------------------------------
map_slot_to_db() {
  local s="$1"
  case "$s" in
    "Body Armour")  echo "body" ;;
    "Helmet")       echo "helmet" ;;
    "Boots")        echo "boots" ;;
    "Gloves")       echo "gloves" ;;
    "Belt")         echo "belt" ;;
    "Amulet")       echo "amulet" ;;
    "Ring 1"|"Ring 2") echo "ring" ;;
    "Shield")       echo "shield" ;;
    "Weapon 1"|"Weapon 2") echo "ALL_WEAPONS" ;;
    *)              echo "" ;;
  esac
}

map_slot_to_ninja_category() {
  local s="$1"
  case "$s" in
    "Body Armour"|"Helmet"|"Boots"|"Gloves"|"Shield")
      echo "unique-armour" ;;
    "Belt"|"Amulet"|"Ring 1"|"Ring 2")
      echo "unique-accessory" ;;
    "Weapon 1"|"Weapon 2")
      echo "unique-weapon" ;;
    *)
      echo "" ;;
  esac
}

WEAPON_FILES="axe bow claw dagger mace staff sword wand"

db_type=$(map_slot_to_db "$slot")
ninja_category=$(map_slot_to_ninja_category "$slot")

if [[ -z "$db_type" ]]; then
  echo "ERROR: unsupported slot: $slot" >&2
  exit 1
fi

# Build list of DB files to scan
db_files=()
if [[ "$db_type" == "ALL_WEAPONS" ]]; then
  for w in $WEAPON_FILES; do
    f="$DB_POB/${w}.json"
    [[ -f "$f" ]] && db_files+=("$f")
  done
else
  f="$DB_POB/${db_type}.json"
  [[ -f "$f" ]] || { echo "ERROR: DB file not found: $f" >&2; exit 1; }
  db_files+=("$f")
fi

# Ninja price file
ninja_dir="$DB_NINJA/$league/$ninja_category"
ninja_file="$ninja_dir/${ninja_category}.json"
has_prices=false
if [[ -f "$ninja_file" ]]; then
  has_prices=true
fi

# ---------------------------------------------------------------------------
# Skill argument for sim
# ---------------------------------------------------------------------------
sim_skill_args=()
if [[ -n "$skill_name" ]]; then
  sim_skill_args=(--skill "$skill_name")
fi

# ---------------------------------------------------------------------------
# Step 1: Baseline simulation
# ---------------------------------------------------------------------------
echo "BASELINE: running simulation..." >&2
baseline_json=$(bash "$RUN_SIM" xml ${sim_skill_args[@]+"${sim_skill_args[@]}"} < "$build_xml" 2>/dev/null) || {
  echo "ERROR: baseline simulation failed" >&2
  exit 1
}

baseline_dps=$(printf '%s' "$baseline_json" | jq -r '.CombinedDPS // .combinedDPS // 0')
baseline_life=$(printf '%s' "$baseline_json" | jq -r '.Life // .life // 0')
baseline_ehp=$(printf '%s' "$baseline_json" | jq -r '.TotalEHP // .totalEHP // 0')

# Extract current item name from the build
current_item_name=$(python3 "$MANIPULATE" list-slots --input "$build_xml" 2>/dev/null \
  | jq -r --arg slot "$slot" '.[] | select(.name == $slot) | .preview' \
  | head -3 | sed -n '2p') || current_item_name="unknown"

echo "BASELINE: DPS=$baseline_dps Life=$baseline_life EHP=$baseline_ehp" >&2

# ---------------------------------------------------------------------------
# Step 2: Collect candidates from DB (limit 30 total)
# ---------------------------------------------------------------------------
candidates_json="${tmp_prefix}_candidates.json"
printf '[]' > "$candidates_json"

total_candidates=0
max_candidates=30

for db_file in "${db_files[@]}"; do
  [[ $total_candidates -ge $max_candidates ]] && break

  remaining=$((max_candidates - total_candidates))

  # Extract candidates: only "Current" variant items (filter out legacy variants)
  # Take items where variants is null or contains "Current"
  batch=$(jq -c --argjson limit "$remaining" '
    [.[] |
      select(
        (.variants == null) or
        (.variants | length == 0) or
        (.variants[-1] | test("Current"))
      ) |
      {
        name: .name,
        baseType: .baseType,
        implicit: (.implicit // []),
        mods: (.mods // [])
      }
    ] | .[:$limit]
  ' "$db_file")

  count=$(printf '%s' "$batch" | jq 'length')
  total_candidates=$((total_candidates + count))

  # Merge into candidates
  jq -s '.[0] + .[1]' "$candidates_json" <(printf '%s' "$batch") > "${tmp_prefix}_merged.json"
  mv "${tmp_prefix}_merged.json" "$candidates_json"
done

total_candidates=$(jq 'length' "$candidates_json")
echo "CANDIDATES: $total_candidates" >&2

if [[ "$total_candidates" -eq 0 ]]; then
  echo "ERROR: no candidates found for slot $slot" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 3: Load price lookup
# ---------------------------------------------------------------------------
price_file="${tmp_prefix}_prices.json"
if [[ "$has_prices" == true ]]; then
  # Build name->price map (lowercase key for fuzzy matching)
  jq '[.[] | {
    key: (.name | ascii_downcase),
    value: {chaosValue: .chaosValue, divineValue: .divineValue}
  }] | from_entries' "$ninja_file" > "$price_file"
else
  printf '{}' > "$price_file"
fi

# ---------------------------------------------------------------------------
# Step 4: Simulate each candidate
# ---------------------------------------------------------------------------
results_file="${tmp_prefix}_results.json"
printf '[]' > "$results_file"

tested=0
skipped=0

for i in $(seq 0 $((total_candidates - 1))); do
  candidate=$(jq -c ".[$i]" "$candidates_json")
  c_name=$(printf '%s' "$candidate" | jq -r '.name')

  # Price lookup
  c_lower=$(printf '%s' "$c_name" | tr '[:upper:]' '[:lower:]')
  price_info=$(jq -c --arg n "$c_lower" '.[$n] // null' "$price_file")

  c_chaos=0
  c_divine=0
  if [[ "$price_info" != "null" ]]; then
    c_chaos=$(printf '%s' "$price_info" | jq -r '.chaosValue // 0')
    c_divine=$(printf '%s' "$price_info" | jq -r '.divineValue // 0')
  fi

  # Budget filter
  if [[ -n "$budget_divine" ]] && [[ "$price_info" != "null" ]]; then
    over_budget=$(printf '%s' "$c_divine" | awk -v b="$budget_divine" '{print ($1 > b) ? 1 : 0}')
    if [[ "$over_budget" == "1" ]]; then
      skipped=$((skipped + 1))
      continue
    fi
  fi

  # Generate item text for PoB
  implicit_count=$(printf '%s' "$candidate" | jq '.implicit | length')
  implicit_lines=$(printf '%s' "$candidate" | jq -r '.implicit[]' 2>/dev/null || true)
  mod_lines=$(printf '%s' "$candidate" | jq -r '.mods[]' 2>/dev/null || true)
  c_base=$(printf '%s' "$candidate" | jq -r '.baseType')

  item_text="Rarity: UNIQUE\n${c_name}\n${c_base}\nImplicits: ${implicit_count}"
  if [[ "$implicit_count" -gt 0 ]] && [[ -n "$implicit_lines" ]]; then
    item_text="${item_text}\n${implicit_lines}"
  fi
  if [[ -n "$mod_lines" ]]; then
    item_text="${item_text}\n${mod_lines}"
  fi

  # Swap item in build XML
  tmp_modified="${tmp_prefix}_mod_${i}.xml"
  if ! python3 "$MANIPULATE" swap-item \
      --input "$build_xml" \
      --slot "$slot" \
      --item-text "$item_text" > "$tmp_modified" 2>/dev/null; then
    echo "SKIP: swap-item failed for $c_name" >&2
    skipped=$((skipped + 1))
    rm -f "$tmp_modified"
    continue
  fi

  # Simulate
  sim_json=$(bash "$RUN_SIM" xml ${sim_skill_args[@]+"${sim_skill_args[@]}"} < "$tmp_modified" 2>/dev/null) || {
    echo "SKIP: simulation failed for $c_name" >&2
    skipped=$((skipped + 1))
    rm -f "$tmp_modified"
    continue
  }
  rm -f "$tmp_modified"

  c_dps=$(printf '%s' "$sim_json" | jq -r '.CombinedDPS // .combinedDPS // 0')
  c_life=$(printf '%s' "$sim_json" | jq -r '.Life // .life // 0')
  c_ehp=$(printf '%s' "$sim_json" | jq -r '.TotalEHP // .totalEHP // 0')

  # Calculate deltas
  delta_dps=$(awk "BEGIN {printf \"%.1f\", $c_dps - $baseline_dps}")
  delta_life=$(awk "BEGIN {printf \"%.0f\", $c_life - $baseline_life}")
  delta_ehp=$(awk "BEGIN {printf \"%.0f\", $c_ehp - $baseline_ehp}")

  # Efficiency: ΔDPS per divine (0 if free or no price)
  efficiency=0
  if [[ "$c_divine" != "0" ]] && [[ "$price_info" != "null" ]]; then
    efficiency=$(awk "BEGIN {d=$c_divine; if(d>0) printf \"%.1f\", ($c_dps - $baseline_dps)/d; else print 0}")
  fi

  # Append result
  entry=$(jq -n \
    --arg name "$c_name" \
    --argjson chaos "$c_chaos" \
    --argjson divine "$c_divine" \
    --argjson ddps "$delta_dps" \
    --argjson dlife "$delta_life" \
    --argjson dehp "$delta_ehp" \
    --argjson eff "$efficiency" \
    '{name: $name, chaosValue: $chaos, divineValue: $divine, delta: {combinedDPS: $ddps, life: $dlife, totalEHP: $dehp}, efficiency: $eff}')

  jq --argjson e "$entry" '. += [$e]' "$results_file" > "${tmp_prefix}_r2.json"
  mv "${tmp_prefix}_r2.json" "$results_file"
  tested=$((tested + 1))

  echo "  [$tested/$total_candidates] $c_name: ΔDPS=$delta_dps" >&2
done

echo "TESTED: $tested, SKIPPED: $skipped" >&2

# ---------------------------------------------------------------------------
# Step 5: Sort by ΔDPS descending, output final JSON
# ---------------------------------------------------------------------------
sorted=$(jq '[.[] | .] | sort_by(-.delta.combinedDPS)' "$results_file")

best_name="(none)"
best_delta="0"
if [[ $(printf '%s' "$sorted" | jq 'length') -gt 0 ]]; then
  best_name=$(printf '%s' "$sorted" | jq -r '.[0].name')
  best_delta=$(printf '%s' "$sorted" | jq -r '.[0].delta.combinedDPS')
fi
echo "BEST: $best_name (ΔDPS: $best_delta)" >&2

# Final output
jq -n \
  --arg slot "$slot" \
  --arg skill "${skill_name:-all}" \
  --arg current "$current_item_name" \
  --argjson b_dps "$baseline_dps" \
  --argjson b_life "$baseline_life" \
  --argjson b_ehp "$baseline_ehp" \
  --argjson candidates "$sorted" \
  '{
    slot: $slot,
    skill: $skill,
    baseline: {item: $current, combinedDPS: $b_dps, life: $b_life, totalEHP: $b_ehp},
    candidates: $candidates
  }'

echo "OK: optimization complete" >&2
