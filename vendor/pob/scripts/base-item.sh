#!/usr/bin/env bash
# Usage: bash vendor/pob/scripts/base-item.sh <pob_path> <gameVersion> <pobCommit> <pobVersion>
# Output: vendor/pob/references/base-item.md
# Exit: 0 = success, 1 = error
set -euo pipefail

pob_path="${1:?Usage: $0 <pob_path> <gameVersion> <pobCommit> <pobVersion>}"
gameVersion="${2:?}"
pobCommit="${3:?}"
pobVersion="${4:?}"

BASES="$pob_path/src/Data/Bases"
OUT="vendor/pob/references/base-item.md"

[[ -d "$BASES" ]] || { echo "ERROR: $BASES not found" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"

# ── Data Collection ──────────────────────────────────────────────

# All file names (alphabetical, comma-separated)
all_files=$(for f in "$BASES"/*.lua; do basename "$f" .lua; done | sort | paste -sd',' - | sed 's/,/, /g')
total_files=$(ls "$BASES"/*.lua | wc -l | tr -d ' ')
usable_files=$((total_files - 2))

# Item counts table (two-column, sorted by count desc)
item_table=$(
  for f in "$BASES"/*.lua; do
    slot=$(basename "$f" .lua)
    [[ "$slot" == "fishing" || "$slot" == "graft" ]] && continue
    count=$(grep -c 'itemBases\[' "$f")
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

# Top-level fields (backtick-formatted)
top_fields=$(
  for f in "$BASES"/*.lua; do
    grep -oE '^\t[a-zA-Z]+' "$f"
  done | sed 's/^	//' | sort -u | awk 'NR>1{printf ", "}{printf "`%s`", $0}'
)

# Type-specific stat sub-fields
weapon_fields=$(
  for f in sword.lua axe.lua mace.lua dagger.lua claw.lua wand.lua staff.lua bow.lua; do
    perl -ne 'print "$1\n" if /weapon = \{([^}]+)\}/' "$BASES/$f"
  done | grep -oE '[a-zA-Z]+ =' | awk '{print $1}' | sort -u | paste -sd',' - | sed 's/,/, /g'
)
armour_fields=$(
  for f in body.lua boots.lua gloves.lua helmet.lua shield.lua; do
    perl -ne 'print "$1\n" if /armour = \{([^}]+)\}/' "$BASES/$f"
  done | grep -oE '[a-zA-Z]+ =' | awk '{print $1}' | sort -u | paste -sd',' - | sed 's/,/, /g'
)
flask_fields=$(
  perl -ne 'print "$1\n" if /flask = \{([^}]+)\}/' "$BASES/flask.lua" \
    | grep -oE '[a-zA-Z]+ =' | awk '{print $1}' | sort -u | paste -sd',' - | sed 's/,/, /g'
)
tincture_fields=$(
  perl -ne 'print "$1\n" if /tincture = \{([^}]+)\}/' "$BASES/tincture.lua" \
    | grep -oE '[a-zA-Z]+ =' | awk '{print $1}' | sort -u | paste -sd',' - | sed 's/,/, /g'
)

# Sample entry from sword.lua (annotated)
sample=$(awk '/^itemBases\[/{found=1} found{print} found && /^\}/{exit}' "$BASES/sword.lua")
sample_annotated=$(printf '%s\n' "$sample" | sed \
  -e '/^\ttype = /s/$/  -- Item type string/' \
  -e '/^\tsocketLimit = /s/$/  -- Max sockets (omitted if 0)/' \
  -e '/^\ttags = /s/$/  -- Classification tags/' \
  -e '/^\tinfluenceTags = /s/$/  -- Influence variant IDs (weapons only)/' \
  -e '/^\timplicit = /s/$/  -- Implicit mod text (may contain \\n for multiline)/' \
  -e '/^\timplicitModTypes = /s/$/  -- Implicit mod tags (array of arrays)/' \
  -e '/^\tweapon = /s/$/  -- Type-specific stats (weapons, armour, flask, tincture)/' \
  -e '/^\treq = /s/$/  -- Minimum requirements (str, dex, int, level)/')

# Caveats data
multiline_files=$(grep -l '\\n' "$BASES"/*.lua | xargs -I{} basename {} .lua | sort | paste -sd',' - | sed 's/,/, /g')
hidden_files=$(grep -l 'hidden = true' "$BASES"/*.lua | xargs -I{} basename {} .lua | sort | paste -sd',' - | sed 's/,/, /g')
flavour_files=$(grep -l 'flavourText' "$BASES"/*.lua | xargs -I{} basename {} .lua | sort | paste -sd',' - | sed 's/,/, /g')

armour_dist=""
for f in body.lua boots.lua gloves.lua helmet.lua shield.lua; do
  sf=$(perl -ne 'print "$1\n" if /armour = \{([^}]+)\}/' "$BASES/$f" \
    | grep -oE '[a-zA-Z]+ =' | awk '{print $1}' | sort -u | paste -sd',' - | sed 's/,/, /g')
  armour_dist="$armour_dist  $f: $sf
"
done

# ── Assemble Reference File ─────────────────────────────────────

{
  echo "<!-- @generated gameVersion=$gameVersion pobCommit=$pobCommit pobVersion=$pobVersion -->"
  echo '# Base Items — `src/Data/Bases/`'
  echo ""
  echo "**Files ($total_files)**: $all_files"
  echo ""
  echo "**Usable ($usable_files)**: Exclude fishing (joke item) and graft (Sanctum-internal)."
  echo ""
  echo "**Item counts**:"
  echo "| File | Count | File | Count |"
  echo "|------|-------|------|-------|"
  printf '%s\n' "$item_table"
  echo ""
  echo '**Lua format** (example from `sword.lua`):'
  echo '```lua'
  printf '%s\n' "$sample_annotated"
  echo '```'
  echo ""
  echo "**Top-level fields**:"
  echo "$top_fields"
  echo ""
  echo "**Type-specific stat fields** (exactly one per item, or none):"
  echo "- **weapon** (axe, bow, claw, dagger, mace, staff, sword, wand): \`{ $weapon_fields }\`"
  echo "- **armour** (body, boots, gloves, helmet, shield): \`{ $armour_fields }\`"
  echo "- **flask** (flask): \`{ $flask_fields }\`"
  echo "- **tincture** (tincture): \`{ $tincture_fields }\`"
  echo "- **jewel/amulet/ring/belt/quiver**: No type-specific stat fields."
  echo ""
  echo "**Caveats**:"
  printf '%s\n' "- **Multiline implicits**: Files with literal \`\\n\` in implicit strings: $multiline_files. Require unescaping when parsing."
  echo "- **Hidden items**: Files containing \`hidden = true\`: $hidden_files. Quest items, divination card bases, etc."
  echo "- **Flavour text**: Files with optional \`flavourText\` field: $flavour_files."
  echo "- **Sparse armour sub-fields** (per-file distribution):"
  printf '%s' "$armour_dist"
  printf '%s\n' "- **Sparse flask sub-fields**: \`life\`/\`mana\` on Life/Mana flasks. \`buff\`/\`duration\` on Utility flasks. All flasks have \`chargesUsed\`/\`chargesMax\`."
} > "$OUT"

# ── Self-Check ───────────────────────────────────────────────────

[[ -f "$OUT" ]] || { echo "ERROR: $OUT not created" >&2; exit 1; }
[[ -s "$OUT" ]] || { echo "ERROR: $OUT is empty" >&2; exit 1; }
head -1 "$OUT" | grep -q "@generated" || { echo "ERROR: Missing @generated header" >&2; exit 1; }

echo "OK: $OUT generated"
