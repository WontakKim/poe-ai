#!/usr/bin/env bash
# Usage: bash vendor/pob/scripts/unique-item.sh <pob_path> <gameVersion> <pobCommit> <pobVersion>
# Output: vendor/pob/references/unique-item.md
# Exit: 0 = success, 1 = error
set -euo pipefail

pob_path="${1:?Usage: $0 <pob_path> <gameVersion> <pobCommit> <pobVersion>}"
gameVersion="${2:?}"
pobCommit="${3:?}"
pobVersion="${4:?}"

UNIQUES="$pob_path/src/Data/Uniques"
OUT="vendor/pob/references/unique-item.md"

[[ -d "$UNIQUES" ]] || { echo "ERROR: $UNIQUES not found" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"

# ── Data Collection ──────────────────────────────────────────────

# All main file names (alphabetical, including fishing/graft)
all_files=$(for f in "$UNIQUES"/*.lua; do basename "$f" .lua; done | sort | paste -sd',' - | sed 's/,/, /g')
main_count=$(ls "$UNIQUES"/*.lua | wc -l | tr -d ' ')
usable_count=$((main_count - 2))

# Item counts table (two-column, usable files only)
item_table=$(
  for f in "$UNIQUES"/*.lua; do
    slot=$(basename "$f" .lua)
    [[ "$slot" == "fishing" || "$slot" == "graft" ]] && continue
    count=$(perl -ne '$n++ if /^\[\[/ || /\]\],\[\[/; END{print $n // 0}' "$f")
    echo "$count $slot"
  done | sort -rn | awk '
    NR<=10 { left[NR]=$2; lc[NR]=$1 }
    NR>10  { right[NR-10]=$2; rc[NR-10]=$1 }
    { sum+=$1 }
    END {
      for(i=1;i<=10;i++) printf "| %s | %s | %s | %s |\n", left[i], lc[i], right[i], rc[i]
      printf "| **Total (usable)** | **%s** | | |\n", sum
    }
  '
)

# Special/ file counts
special_info=$(
  for f in "$UNIQUES"/Special/*.lua; do
    name=$(basename "$f")
    count=$(perl -ne '$n++ if /^\[\[/ || /\]\],\[\[/; END{print $n // 0}' "$f")
    echo "$name ($count)"
  done | sort | paste -sd',' - | sed 's/,/, /g'
)

# Metadata patterns — colon-terminated
colon_patterns=$(
  { grep -ohE '^[A-Z][a-z]+( [A-Z][a-z]+)*:' "$UNIQUES"/*.lua
    grep -ohE '^(Limited to|LevelReq):' "$UNIQUES"/*.lua
  } | sort -u
)
colon_list=$(echo "$colon_patterns" | awk '{printf "  - `%s`\n", $0}')

# Metadata patterns — non-colon standalone markers
non_colon_patterns=$(
  grep -ohE '^(Shaper Item|Elder Item|Crusader Item|Hunter Item|Redeemer Item|Warlord Item|Corrupted|Mirrored)$' \
    "$UNIQUES"/*.lua | sort -u
)
non_colon_list=$(echo "$non_colon_patterns" | awk '{printf "  - `%s`\n", $0}')

# Level requirement format counts
levelreq_count=$(grep -rc '^LevelReq:' "$UNIQUES"/*.lua | awk -F: '{s+=$2}END{print s}')
requires_level_count=$(grep -rc '^Requires Level' "$UNIQUES"/*.lua | awk -F: '{s+=$2}END{print s}')

# Items without Implicits line
without_impl_result=$(
  total=0; no_impl=0
  for f in "$UNIQUES"/*.lua; do
    slot=$(basename "$f" .lua)
    [[ "$slot" == "fishing" || "$slot" == "graft" ]] && continue
    items=$(perl -ne '$n++ if /^\[\[/ || /\]\],\[\[/; END{print $n // 0}' "$f")
    impl=$(grep -c '^Implicits:' "$f" || true)
    total=$((total + items))
    no_impl=$((no_impl + items - impl))
  done
  echo "$no_impl $total"
)
without_implicits=$(echo "$without_impl_result" | awk '{print $1}')
total_items=$(echo "$without_impl_result" | awk '{print $2}')

# Sample block from sword.lua
sample_block=$(awk '/^\[\[/{found=1} /^\]\]/{if(found) exit} found{print}' "$UNIQUES/sword.lua")

# Parsing note 2: variant on base type line
variant_result=""
for f in "$UNIQUES"/*.lua; do
  slot=$(basename "$f" .lua)
  [[ "$slot" == "fishing" || "$slot" == "graft" ]] && continue
  count=$(perl -ne '
    if (/^\[\[/ || /\]\],\[\[/) { $n = 0; next }
    $n++;
    if ($n == 2 && /\{variant:/) { $c++ }
    END { print $c // 0 }
  ' "$f")
  if [ "$count" -gt 0 ]; then variant_result="$variant_result, $slot ($count)"; fi
done
variant_result="${variant_result#, }"

# Special/New.lua format
new_lua_format=$(head -1 "$UNIQUES/Special/New.lua" | grep -oE '^[^{]+{' || echo "unknown")

# ── Assemble Reference File ─────────────────────────────────────

{
  echo "<!-- @generated gameVersion=$gameVersion pobCommit=$pobCommit pobVersion=$pobVersion -->"
  echo '# Unique Items — `src/Data/Uniques/`'
  echo ""
  echo "**Main files ($main_count)**: $all_files"
  echo ""
  echo "**Usable ($usable_count)**: Exclude fishing and graft."
  echo ""
  echo "**Special/ folder**: $special_info"
  echo ""
  echo "**Item counts**:"
  echo "| File | Count | File | Count |"
  echo "|------|-------|------|-------|"
  printf '%s\n' "$item_table"
  echo ""
  echo '**Block format** (items separated by `]],[[`, first starts with `[[`, last ends with `]]`):'
  echo '```lua'
  printf '%s\n' "$sample_block"
  echo '```'
  echo ""
  echo "Block structure:"
  echo '- Line 1: `[[` (block start marker)'
  echo "- Line 2: Item name"
  echo "- Line 3: Base type name"
  echo "- Lines 4-N: Metadata lines and implicit/explicit mods"
  echo "  - Metadata lines match the patterns listed below"
  echo '  - After `Implicits: N`, the next N lines are implicit mods'
  echo "  - Remaining lines are explicit mods"
  echo ""
  echo "**Metadata patterns** (extracted from source):"
  echo ""
  echo "- **Colon-terminated**:"
  printf '%s\n' "$colon_list"
  echo ""
  echo "- **Non-colon markers** (standalone lines):"
  printf '%s\n' "$non_colon_list"
  echo ""
  echo "Lines matching these patterns are metadata — everything else after the Implicits section is a mod line."
  echo ""
  echo "**Level requirement formats**:"
  echo "- \`LevelReq: N\` — $levelreq_count occurrences"
  echo "- \`Requires Level N, X Str, Y Dex\` — $requires_level_count occurrences"
  echo "- If neither present, fall back to the base item's level requirement."
  echo ""
  echo "**Parsing notes**:"
  echo "1. $without_implicits of $total_items items lack an \`Implicits:\` line — treat as 0 implicits (all non-metadata lines are explicit mods)."
  printf '%s\n' "2. Variant prefix \`{variant:N}\` on the base type line (line 3): $variant_result. Parser must select the correct base type for the current variant."
  echo "3. Variant filtering: find \"Current\" variant index (or last variant if none labeled \"Current\"), keep only mods matching that index or with no variant prefix."
  printf '%s\n' "4. Strip \`{variant:N}\`, \`{variant:N,M}\`, and \`{tags:...}\` prefixes from kept lines."
  printf '%s\n' "5. Special/New.lua uses \`data.uniques.new = {\` format (NOT \`return {\`)."
  echo "6. Special/WatchersEye.lua and BoundByDestiny.lua contain dynamically-generated items (0 parseable entries). Generated.lua has static entries that ARE parseable."
} > "$OUT"

# ── Self-Check ───────────────────────────────────────────────────

[[ -f "$OUT" ]] || { echo "ERROR: $OUT not created" >&2; exit 1; }
[[ -s "$OUT" ]] || { echo "ERROR: $OUT is empty" >&2; exit 1; }
head -1 "$OUT" | grep -q "@generated" || { echo "ERROR: Missing @generated header" >&2; exit 1; }

echo "OK: $OUT generated"
