#!/usr/bin/env bash
# Usage: bash vendor/pob/scripts/skill-gem.sh <pob_path> <gameVersion> <pobCommit> <pobVersion>
# Output: vendor/pob/references/skill-gem.md
# Exit: 0 = success, 1 = error
set -euo pipefail

pob_path="${1:?Usage: $0 <pob_path> <gameVersion> <pobCommit> <pobVersion>}"
gameVersion="${2:?}"
pobCommit="${3:?}"
pobVersion="${4:?}"

GEMS="$pob_path/src/Data/Gems.lua"
SKILLS="$pob_path/src/Data/Skills"
OUT="vendor/pob/references/skill-gem.md"

[[ -f "$GEMS" ]] || { echo "ERROR: $GEMS not found" >&2; exit 1; }
[[ -d "$SKILLS" ]] || { echo "ERROR: $SKILLS not found" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"

# ── Step 1: Gems.lua counts and category breakdown ──────────────

gems_total=$(grep -c '^\t\["Metadata' "$GEMS")

category_breakdown=$(perl -ne '
  if (/^\t\["Metadata/) { $in=1; $active=0; $support=0; $vaal=0; $awakened=0; $transfig=0; }
  if ($in && /grants_active_skill = true/) { $active=1; }
  if ($in && /support = true/) { $support=1; }
  if ($in && /vaalGem = true/) { $vaal=1; }
  if ($in && /awakened = true/) { $awakened=1; }
  if ($in && /Alt[XYZ]/) { $transfig=1; }
  if ($in && /^\t\},/) {
    $in=0;
    if ($active && $support) { $both++; }
    elsif ($active) { $act++; }
    elsif ($support) { $sup++; }
    $v++ if $vaal; $aw++ if $awakened; $tr++ if $transfig;
  }
  END {
    print "active_only=$act\n";
    print "support_only=$sup\n";
    print "active_and_support=$both\n";
    print "vaal=$v\n";
    print "awakened=$aw\n";
    print "transfigured=$tr\n";
  }
' "$GEMS")

active_only=$(echo "$category_breakdown" | grep 'active_only=' | cut -d= -f2)
support_only=$(echo "$category_breakdown" | grep 'support_only=' | cut -d= -f2)
active_and_support=$(echo "$category_breakdown" | grep 'active_and_support=' | cut -d= -f2)
vaal=$(echo "$category_breakdown" | grep 'vaal=' | cut -d= -f2)
awakened=$(echo "$category_breakdown" | grep 'awakened=' | cut -d= -f2)
transfigured=$(echo "$category_breakdown" | grep 'transfigured=' | cut -d= -f2)

# ── Step 2: Gems.lua field names ────────────────────────────────

gems_fields=$(grep -oE '^\t\t[a-zA-Z]+' "$GEMS" | sed 's/^		//' | sort -u | awk 'NR>1{printf ", "}{printf "`%s`", $0}')

# ── Step 3: Tag keys and frequencies ────────────────────────────

tag_table=$(grep -oE '^\t\t\t[a-z_]+ = true' "$GEMS" | awk '{print $1}' | sort | uniq -c | sort -rn | awk '{printf "| %s | %s |\n", $2, $1}')
tag_count=$(echo "$tag_table" | wc -l | tr -d ' ')

# ── Step 4: Skills/ definitions per file ────────────────────────

skills_table=$(
  for f in "$SKILLS"/*.lua; do
    name=$(basename "$f" .lua)
    total=$(grep -c '^skills\["' "$f" || true)
    hidden=$(grep -c 'hidden = true' "$f" || true)
    visible=$((total - hidden))
    echo "$total $name $visible $hidden"
  done | sort -rn | awk '{printf "| %s | %s | %s | %s |\n", $2, $1, $3, $4}'
)

skills_totals=$(
  total=0; hidden=0
  for f in "$SKILLS"/*.lua; do
    t=$(grep -c '^skills\["' "$f" || true)
    h=$(grep -c 'hidden = true' "$f" || true)
    total=$((total + t))
    hidden=$((hidden + h))
  done
  echo "$total $hidden $((total - hidden))"
)
skills_total=$(echo "$skills_totals" | awk '{print $1}')
skills_hidden=$(echo "$skills_totals" | awk '{print $2}')
skills_visible=$(echo "$skills_totals" | awk '{print $3}')
skills_file_count=$(ls "$SKILLS"/*.lua | wc -l | tr -d ' ')

# Per-file hidden counts for edge case 5
spectre_total=$(grep -c '^skills\["' "$SKILLS/spectre.lua" || true)
spectre_hidden=$(grep -c 'hidden = true' "$SKILLS/spectre.lua" || true)
other_total=$(grep -c '^skills\["' "$SKILLS/other.lua" || true)
other_hidden=$(grep -c 'hidden = true' "$SKILLS/other.lua" || true)

# ── Step 5: Skills/ top-level field names ───────────────────────

skills_fields=$(
  for f in "$SKILLS"/*.lua; do
    grep -oE '^\t[a-zA-Z]+' "$f"
  done | sed 's/^	//' | sort -u | awk 'NR>1{printf ", "}{printf "`%s`", $0}'
)

# ── Step 6: Level entry fields and cost types ───────────────────

level_fields=$(
  for f in "$SKILLS"/*.lua; do
    grep -oE '\b(levelRequirement|critChance|damageEffectiveness|attackSpeedMultiplier|baseMultiplier|manaMultiplier|PvPDamageMultiplier|vaalStoredUses|soulPreventionDuration|storedUses|cooldown|attackTime|duration|manaReservationPercent|manaReservationFlat|statInterpolation|cost)\b' "$f"
  done | sort -u | paste -sd',' - | sed 's/,/, /g'
)

cost_types=$(
  grep -oE 'cost = \{[^}]+\}' "$SKILLS"/*.lua | grep -oE '[A-Z][A-Za-z]+ =' | awk '{print $1}' | sort -u | paste -sd',' - | sed 's/,/, /g'
)

# ── Step 7: naturalMaxLevel distribution ────────────────────────

max_level_dist=$(grep -oE 'naturalMaxLevel = [0-9]+' "$GEMS" | awk '{print $3}' | sort | uniq -c | sort -rn | awk '{printf "%s: %s", $2, $1; if(NR>0) printf ", "}' | sed 's/, $//')

# ── Step 8: Secondary effect counts ────────────────────────────

secondary_granted=$(grep -c 'secondaryGrantedEffectId' "$GEMS")
secondary_name=$(grep -c 'secondaryEffectName' "$GEMS")

# ── Step 9: SkillType enum count ────────────────────────────────

skilltype_count=$(grep -oE 'SkillType\.[A-Za-z]+' "$SKILLS"/*.lua | awk -F: '{print $NF}' | sort -u | wc -l | tr -d ' ')

# ── Step 10: Sample entries ─────────────────────────────────────

# Active gem (Arc) from Gems.lua
sample_arc_gem=$(awk '/\["Metadata\/Items\/Gems\/SkillGemArc"\]/{found=1} found{print} found && /^\t\}/{print; exit}' "$GEMS" | awk '!seen[$0]++')

# Active skill (Arc) from Skills/ — top-level fields + first 2 levels
sample_arc_skill=$(awk '
/^skills\["Arc"\]/ { found=1 }
found && /^\tlevels/ { inlevel=1; print; next }
found && inlevel && /\[1\] =/ { print; next }
found && inlevel && /\[2\] =/ { print; printf "\t\t...\n\t}\n}\n"; exit }
found && inlevel==0 { print }
' "$SKILLS/act_int.lua")

# Support gem (Added Cold Damage) from Gems.lua
sample_support_gem=$(awk '/\["Metadata\/Items\/Gems\/SkillGemSupportAddedColdDamage"\]/{found=1} found{print} found && /^\t\}/{print; exit}' "$GEMS" | awk '!seen[$0]++')

# Support skill (Added Cold Damage) from Skills/
sample_support_skill=$(awk '
/^skills\["SupportAddedColdDamage"\]/ { found=1 }
found && /^\tlevels/ { inlevel=1; print; next }
found && inlevel && /\[1\] =/ { print; next }
found && inlevel && /\[2\] =/ { print; printf "\t\t...\n\t}\n}\n"; exit }
found && inlevel==0 { print }
' "$SKILLS/sup_dex.lua")

# ── Step 11: Active+Support hybrid gems ─────────────────────────

hybrid_gems=$(perl -ne '
  if (/^\t\["(Metadata[^"]+)"\]/) { $in=1; $active=0; $support=0; $name=""; }
  if ($in && /name = "([^"]+)"/) { $name=$1; }
  if ($in && /grants_active_skill = true/) { $active=1; }
  if ($in && /support = true/) { $support=1; }
  if ($in && /^\t\},/) {
    $in=0;
    if ($active && $support) { print "$name\n"; }
  }
' "$GEMS" | paste -sd',' - | sed 's/,/, /g')

# ── Assemble Reference File ─────────────────────────────────────

{
  echo "<!-- @generated gameVersion=$gameVersion pobCommit=$pobCommit pobVersion=$pobVersion -->"
  echo '# Skill Gems — `src/Data/Gems.lua` + `src/Data/Skills/`'
  echo ""
  echo 'Skill gem data has two sources joined by `grantedEffectId`:'
  echo "- **Gems.lua** — gem item registry (what the player picks up)"
  echo "- **Skills/*.lua** — skill effect definitions (what the gem does)"
  echo ""
  echo "## Gems.lua — Gem Item Registry"
  echo ""
  echo "**Path**: \`src/Data/Gems.lua\` ($gems_total entries)"
  echo ""
  echo "**Category breakdown**:"
  echo "- Active-only: $active_only (includes $vaal vaal, $transfigured transfigured)"
  echo "- Support-only: $support_only (includes $awakened awakened)"
  echo "- Active+Support hybrid: $active_and_support (support gems that also grant an active skill)"
  echo ""
  echo "**Fields**:"
  echo "$gems_fields"
  echo ""
  echo "**Tag keys** ($tag_count unique):"
  echo "| Tag | Count |"
  echo "|-----|-------|"
  printf '%s\n' "$tag_table"
  echo ""
  echo "**naturalMaxLevel distribution**:"
  echo "$max_level_dist"
  echo ""
  echo "**Example — Active gem (Arc)**:"
  echo '```lua'
  printf '%s\n' "$sample_arc_gem"
  echo '```'
  echo ""
  echo "**Example — Support gem (Added Cold Damage)**:"
  echo '```lua'
  printf '%s\n' "$sample_support_gem"
  echo '```'
  echo ""
  echo "## Skills/ — Skill Effect Definitions"
  echo ""
  echo "**Path**: \`src/Data/Skills/\` ($skills_file_count files, $skills_total definitions, $skills_visible player-visible, $skills_hidden hidden)"
  echo ""
  echo "**Definitions per file**:"
  echo "| File | Total | Visible | Hidden |"
  echo "|------|-------|---------|--------|"
  printf '%s\n' "$skills_table"
  echo ""
  echo "**Top-level fields**:"
  echo "$skills_fields"
  echo ""
  echo '**Level entry fields** (named keys inside `levels[N] = { ... }`):'
  echo "$level_fields"
  echo ""
  echo '**Cost types** (inside `cost = { ... }`):'
  echo "$cost_types"
  echo ""
  echo "**SkillType enum**: $skilltype_count unique values (e.g. \`SkillType.Spell\`, \`SkillType.Attack\`, ...)"
  echo ""
  echo "**Example — Active skill (Arc)**:"
  echo '```lua'
  printf '%s\n' "$sample_arc_skill"
  echo '```'
  echo ""
  echo "**Example — Support skill (Added Cold Damage)**:"
  echo '```lua'
  printf '%s\n' "$sample_support_skill"
  echo '```'
  echo ""
  echo "## Join: Gems.lua → Skills/"
  echo ""
  echo '**Primary link**: `Gems.lua[key].grantedEffectId` == `skills["..."]` key in Skills/ files.'
  echo ""
  echo "**Secondary effects**: $secondary_granted gems have \`secondaryGrantedEffectId\` — resolves to another Skills/ key."
  echo "- Vaal gems: points to the companion non-vaal skill (e.g. VaalArc → Arc)"
  echo "- Trigger supports/skills: points to the triggered sub-effect"
  echo ""
  echo "**secondaryEffectName**: $secondary_name gems have this field (display name for the secondary effect)."
  echo ""
  echo "## Edge Cases"
  echo ""
  printf '%s\n' "1. **Transfigured gems** ($transfigured entries): key contains \`AltX\`/\`AltY\`/\`AltZ\`. The \`gameId\` points to the BASE gem (not the variant), while \`grantedEffectId\` is unique per variant."
  echo ""
  printf '%s\n' "2. **Vaal gems** ($vaal entries): have \`vaalGem = true\` and \`secondaryGrantedEffectId\` pointing to the non-vaal companion skill. In Skills/, vaal costs use \`cost = { Soul = N }\` with \`vaalStoredUses\` and \`soulPreventionDuration\`."
  echo ""
  printf '%s\n' "3. **Awakened support gems** ($awakened entries): have \`awakened = true\` tag, \`naturalMaxLevel = 5\`. In Skills/, they have \`plusVersionOf\` pointing to the base support."
  echo ""
  printf '%s\n' "4. **Active+Support hybrid gems** ($active_and_support entries): $hybrid_gems. These are support gems that also grant an active skill effect."
  echo ""
  echo "5. **Hidden skills**: $skills_hidden of $skills_total skill definitions have \`hidden = true\` — these are spectre, minion, item-granted, and tree-granted skills with no corresponding gem entry."
  echo "   - glove.lua: all 60 hidden (enchantment procs)"
  echo "   - minion.lua: all 72 hidden"
  echo "   - spectre.lua: $spectre_hidden of $spectre_total hidden"
  echo "   - other.lua: $other_hidden of $other_total hidden (includes \`fromItem = true\` and \`fromTree = true\`)"
  echo ""
  printf '%s\n' "6. **Support-specific Skills/ fields**: \`support = true\`, \`requireSkillTypes\`, \`addSkillTypes\`, \`excludeSkillTypes\`, \`manaMultiplier\` (in levels instead of \`cost\`), \`plusVersionOf\` (awakened only)."
  echo ""
  printf '%s\n' "7. **Level data structure**: Positional values in \`levels[N] = { val1, val2, ... }\` correspond 1:1 to the \`stats[]\` array. Named keys (levelRequirement, critChance, etc.) follow the positional values."
} > "$OUT"

# ── Self-Check ───────────────────────────────────────────────────

[[ -f "$OUT" ]] || { echo "ERROR: $OUT not created" >&2; exit 1; }
[[ -s "$OUT" ]] || { echo "ERROR: $OUT is empty" >&2; exit 1; }
head -1 "$OUT" | grep -q "@generated" || { echo "ERROR: Missing @generated header" >&2; exit 1; }

echo "OK: $OUT generated"
