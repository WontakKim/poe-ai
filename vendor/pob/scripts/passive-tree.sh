#!/usr/bin/env bash
# Usage: bash vendor/pob/scripts/passive-tree.sh <pob_path> <gameVersion> <pobCommit> <pobVersion>
# Output: vendor/pob/references/passive-tree.md
# Exit: 0 = success, 1 = error
set -euo pipefail

pob_path="${1:?Usage: $0 <pob_path> <gameVersion> <pobCommit> <pobVersion>}"
gameVersion="${2:?}"
pobCommit="${3:?}"
pobVersion="${4:?}"

OUT="vendor/pob/references/passive-tree.md"

[[ -f "$pob_path/src/GameVersions.lua" ]] || { echo "ERROR: GameVersions.lua not found" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"

# ── Step 1: Version detection, sections, historical counts ──────

# Detect latest version from GameVersions.lua
latest=$(sed -n '/^treeVersionList/,/}/p' "$pob_path/src/GameVersions.lua" | grep -oE '"[^"]+"' | tail -1 | tr -d '"')
tree="$pob_path/src/TreeData/$latest/tree.lua"
[[ -f "$tree" ]] || { echo "ERROR: $tree not found" >&2; exit 1; }

# Version list and count
version_list_block=$(sed -n '/^treeVersionList/,/}/p' "$pob_path/src/GameVersions.lua")
version_count=$(echo "$version_list_block" | grep -oE '"[^"]+"' | wc -l | tr -d ' ')
version_display=$(echo "$latest" | tr '_' '.')

# All version names for display
all_versions=$(echo "$version_list_block" | grep -oE '"[^"]+"' | tr -d '"')
first_ver=$(echo "$all_versions" | head -1)
last_ver=$(echo "$all_versions" | tail -1)

# Sections (top-level keys have exactly 4-space indent)
sections_raw=$(grep -n '^    \["' "$tree")

# Line count
line_count=$(wc -l < "$tree" | tr -d ' ')

# Section line numbers for later use
groups_start=$(echo "$sections_raw" | grep '\["groups"\]' | head -1 | cut -d: -f1)
nodes_start=$(echo "$sections_raw" | grep '\["nodes"\]' | head -1 | cut -d: -f1)

# Build sections table (only named sections, skip min_x/min_y/max_x/max_y)
sections_table=$(echo "$sections_raw" | awk -F: '{
  key=$2; gsub(/^[[:space:]]*\["/, "", key); gsub(/"\].*/, "", key)
  line=$1
  purposes["tree"]="Version identifier"
  purposes["classes"]="Character class definitions with ascendancies"
  purposes["alternate_ascendancies"]="Bloodline alternate ascendancy trees"
  purposes["groups"]="Node group spatial coordinates and orbits"
  purposes["nodes"]="All passive skill node definitions"
  purposes["jewelSlots"]="Jewel socket node IDs"
  purposes["constants"]="Game constants (orbit radii, skills per orbit)"
  purposes["points"]="Total and ascendancy passive points"
  desc = purposes[key]
  if (desc == "") next
  printf "| %s | %s | %s |\n", key, line, desc
}')

# Historical node counts
historical=$(
  for d in "$pob_path"/src/TreeData/*/; do
    ver=$(basename "$d")
    if [ -f "$d/tree.lua" ]; then
      nodes=$(grep -c '\["skill"\]=' "$d/tree.lua" || true)
      if [ "$nodes" -gt 0 ]; then echo "$ver $nodes"; fi
    fi
  done | sort -t_ -k2 -n
)
historical_table=$(echo "$historical" | awk '{printf "| %s | %s |\n", $1, $2}')

# ── Step 2: Mega-perl — counts, fields, ascendancy ─────────────

mega_output=$(perl -ne '
  $total++ if /\["skill"\]=/;
  $keystone++ if /\["isKeystone"\]= true/;
  $notable++ if /\["isNotable"\]= true/;
  $mastery++ if /\["isMastery"\]= true/;
  $jewel++ if /\["isJewelSocket"\]= true/;
  $asc_start++ if /\["isAscendancyStart"\]= true/;
  $proxy++ if /\["isProxy"\]= true/;
  $blighted++ if /\["isBlighted"\]= true/;
  $bloodline++ if /\["isBloodline"\]= true/;
  $multi_choice++ if /\["isMultipleChoice"\]= true/;
  $multi_opt++ if /\["isMultipleChoiceOption"\]= true/;
  $class_start++ if /\["classStartIndex"\]/;
  if (/^\s{12}\["([a-zA-Z_]+)"\]=/) { $fields{$1}=1 }
  if (/\["ascendancyName"\]= "([^"]+)"/) { $asc{$1}++ }
  if (/\["effect"\]= (\d+)/) { $effects{$1}=1 }
  if (/\["stats"\]= \{/) { $in_stats=1; next }
  if ($in_stats && /^\s+\}/) { $in_stats=0; next }
  if ($in_stats && /^\s+"(.+)"/) { $stats{$1}=1 }
  END {
    print "COUNTS\n";
    print "total=$total\n";
    print "keystone=$keystone\n";
    print "notable=$notable\n";
    print "mastery=$mastery\n";
    print "jewel_socket=$jewel\n";
    print "ascendancy_start=$asc_start\n";
    print "proxy=$proxy\n";
    print "blighted=$blighted\n";
    print "bloodline=$bloodline\n";
    print "multiple_choice=$multi_choice\n";
    print "multiple_choice_option=$multi_opt\n";
    print "class_start_index=$class_start\n";
    print "mastery_effects=" . scalar(keys %effects) . "\n";
    print "unique_stats=" . scalar(keys %stats) . "\n";
    print "FIELDS\n";
    print join(",", sort keys %fields) . "\n";
    print "ASCENDANCY\n";
    for (sort { $asc{$b} <=> $asc{$a} } keys %asc) {
      printf "| %s | %s |\n", $_, $asc{$_};
    }
  }
' "$tree")

# Parse mega-perl output
get_count() { echo "$mega_output" | grep "^$1=" | cut -d= -f2; }
total_nodes=$(get_count total)
keystone=$(get_count keystone)
notable=$(get_count notable)
mastery_count=$(get_count mastery)
jewel_socket=$(get_count jewel_socket)
asc_start=$(get_count ascendancy_start)
proxy=$(get_count proxy)
blighted=$(get_count blighted)
bloodline=$(get_count bloodline)
multi_choice=$(get_count multiple_choice)
multi_opt=$(get_count multiple_choice_option)
class_start_index=$(get_count class_start_index)
mastery_effects=$(get_count mastery_effects)
unique_stats=$(get_count unique_stats)

# Fields
node_fields=$(echo "$mega_output" | awk '/^FIELDS$/{getline; print}' | tr ',' ', ')

# Ascendancy table
asc_table=$(echo "$mega_output" | awk '/^ASCENDANCY$/{found=1; next} found{print}')

# ── Classes and alternates ──────────────────────────────────────

classes_raw=$(perl -ne '
  if (/^\s{4}\["classes"\]= \{/) { $in=1; next }
  if ($in && /^\s{4}\},/) { $in=0; next }
  if ($in) {
    if (/\["name"\]= "([^"]+)"/) { $name=$1 }
    if (/\["base_str"\]= (\d+)/) { $str=$1 }
    if (/\["base_dex"\]= (\d+)/) { $dex=$1 }
    if (/\["base_int"\]= (\d+)/) { $int=$1; print "$name|$str|$dex|$int\n" if $name; }
    if (/\["id"\]= "([^"]+)"/) { print "  asc: $1\n" }
  }
' "$tree")

# Build class table with ascendancy names
class_table=""
class_count=0
current_class=""
current_str=""
current_dex=""
current_int=""
current_ascs=""
while IFS= read -r line; do
  if [[ "$line" == "  asc: "* ]]; then
    asc_name="${line#  asc: }"
    if [ -n "$current_ascs" ]; then
      current_ascs="$current_ascs, $asc_name"
    else
      current_ascs="$asc_name"
    fi
  else
    # Emit previous class if any
    if [ -n "$current_class" ]; then
      class_table="$class_table| $current_class | $current_str | $current_dex | $current_int | $current_ascs |
"
    fi
    IFS='|' read -r cname cstr cdex cint <<< "$line"
    current_class="$cname"
    current_str="$cstr"
    current_dex="$cdex"
    current_int="$cint"
    current_ascs=""
    class_count=$((class_count + 1))
  fi
done <<< "$classes_raw"
# Emit last class
if [ -n "$current_class" ]; then
  class_table="$class_table| $current_class | $current_str | $current_dex | $current_int | $current_ascs |"
fi

# Alternate ascendancies
alternates_raw=$(perl -ne '
  if (/^\s{4}\["alternate_ascendancies"\]= \{/) { $in=1; next }
  if ($in && /^\s{4}\},/) { $in=0; next }
  if ($in && /\["id"\]= "([^"]+)"/) { $id=$1 }
  if ($in && /\["name"\]= "([^"]+)"/) { print "$id|$1\n" }
' "$tree")
alt_count=$(echo "$alternates_raw" | grep -c '|' || true)
alt_table=$(echo "$alternates_raw" | awk -F'|' '{printf "| %s | %s |\n", $1, $2}')

# ── Step 3: Groups, constants, points, jewel slots, samples ────

# Group count
group_count=$(awk "NR>=$groups_start && NR<$nodes_start"' && /^        \[[0-9]+\]=/' "$tree" | wc -l | tr -d ' ')

# Points
points_raw=$(grep -A3 '^\s*\["points"\]=' "$tree")
total_points=$(echo "$points_raw" | grep 'totalPoints' | grep -oE '[0-9]+')
asc_points=$(echo "$points_raw" | grep 'ascendancyPoints' | grep -oE '[0-9]+')

# Constants
constants_block=$(awk '/\["constants"\]= \{/{found=1} found{print} found && /^    \}/{exit}' "$tree")

# PSSCentreInnerRadius value
pss_radius=$(echo "$constants_block" | grep 'PSSCentreInnerRadius' | grep -oE '[0-9]+')

# Jewel slots count
jewel_slot_count=$(awk '/\["jewelSlots"\]= \{/{found=1; next} found && /^    \}/{exit} found && /[0-9]/{count++} END{print count}' "$tree")

# Sample nodes — classify at end of each block so ascendancyName is always in buffer
samples=$(perl -e '
open(my $fh, "<", "'"$tree"'") or die;
my (%samples, $buf, $in, $is_mastery, $efcount, $truncated);
my $need = 5;
while (<$fh>) {
  if (/^\s{8}\[\d+\]=/) { $buf=""; $in=1; $is_mastery=0; $efcount=0; $truncated=0 }
  if ($in) {
    $is_mastery = 1 if /\["isMastery"\]= true/;
    if ($is_mastery) {
      $efcount++ if /\["effect"\]/;
      if ($efcount <= 2) { $buf .= $_ }
      elsif ($efcount == 3 && $truncated == 0) { $buf .= "                ...\n            }\n        },\n"; $truncated=1 }
    } else {
      $buf .= $_;
    }
  }
  if ($in && /^\s{8}\},/) {
    $in=0;
    my $has_asc = (index($buf, "ascendancyName") >= 0);
    my $type = "";
    if    (index($buf, "isKeystone") >= 0)     { $type = "keystone" }
    elsif (index($buf, "isMastery") >= 0)      { $type = "mastery" }
    elsif (index($buf, "isJewelSocket") >= 0)  { $type = "jewel" }
    elsif (index($buf, "isNotable") >= 0 && $has_asc == 0 && index($buf, "isBlighted") < 0 && index($buf, "isBloodline") < 0) { $type = "notable" }
    elsif (index($buf, "isProxy") >= 0)        { $type = "skip" }
    elsif (index($buf, "isBlighted") >= 0)     { $type = "skip" }
    elsif (index($buf, "isBloodline") >= 0)    { $type = "skip" }
    elsif (index($buf, "isAscendancyStart") >= 0)   { $type = "skip" }
    elsif (index($buf, "isMultipleChoice") >= 0)     { $type = "skip" }
    elsif (index($buf, "\"stats\"") >= 0 && $has_asc == 0) { $type = "small" }
    if ($type ne "" && $type ne "skip" && !$samples{$type}) { $samples{$type} = $buf }
    last if scalar(keys %samples) >= $need;
  }
}
for my $type (qw(keystone notable mastery jewel small)) {
  print "=== $type ===\n";
  print $samples{$type};
  print "\n";
}
')

# Extract individual samples
extract_sample() {
  echo "$samples" | awk -v type="$1" '
    $0 == "=== " type " ===" { found=1; next }
    /^=== .* ===/ { if(found) exit }
    found { print }
  '
}
sample_keystone=$(extract_sample keystone)
sample_notable=$(extract_sample notable)
sample_mastery=$(extract_sample mastery)
sample_jewel=$(extract_sample jewel)
sample_small=$(extract_sample small)

# ── Assemble Reference File ─────────────────────────────────────

{
  echo "<!-- @generated gameVersion=$gameVersion pobCommit=$pobCommit pobVersion=$pobVersion -->"
  echo "# Passive Tree — \`src/TreeData/$latest/tree.lua\`"
  echo ""
  echo "Passive skill tree data for each game version. One \`tree.lua\` file per version containing all node definitions, group coordinates, class/ascendancy info, and constants."
  echo ""
  echo "## Version Registry"
  echo ""
  echo "**Source**: \`src/GameVersions.lua\`"
  echo ""
  echo "- **Latest version**: $latest (display: $version_display)"
  echo "- **Total versions**: $version_count ($first_ver, ..., $last_ver)"
  echo "- **Variants**: base, ruthless (3.22+), alternate (3.25+), ruthless_alternate (3.25+)"
  echo ""
  echo "## tree.lua Structure ($latest)"
  echo ""
  echo "**Path**: \`src/TreeData/$latest/tree.lua\` ($line_count lines)"
  echo ""
  echo "**Top-level sections**:"
  echo "| Section | Line | Purpose |"
  echo "|---------|------|---------|"
  printf '%s\n' "$sections_table"
  echo ""
  echo "## Nodes"
  echo ""
  echo "**Total**: $total_nodes nodes in $group_count groups"
  echo ""
  echo "### Node Type Breakdown"
  echo ""
  echo "| Flag | Count | Description |"
  echo "|------|-------|-------------|"
  echo "| isKeystone | $keystone | Powerful nodes with unique mechanics |"
  echo "| isNotable | $notable | Mid-power named passives |"
  echo "| isMastery | $mastery_count | Selectable mastery effect nodes (3.19+) |"
  echo "| isJewelSocket | $jewel_socket | Jewel insertion points |"
  echo "| isAscendancyStart | $asc_start | Entry points to ascendancy subtrees |"
  echo "| isProxy | $proxy | Internal positioning markers (not displayed) |"
  echo "| isBlighted | $blighted | Oil-recipe passives |"
  echo "| isBloodline | $bloodline | Alternate tree passives (3.25+) |"
  echo "| isMultipleChoice | $multi_choice | Multiple-choice parent nodes |"
  echo "| isMultipleChoiceOption | $multi_opt | Options within multiple-choice sets |"
  echo ""
  printf '%s\n' "Note: Flags overlap — a node can have multiple flags (e.g. \`isBloodline\` + \`isAscendancyStart\`)."
  echo ""
  echo "### Node Fields"
  echo ""
  echo "All fields found on node entries:"
  echo "$node_fields"
  echo ""
  echo "**Common fields** (present on most nodes): skill, name, icon, stats, group, orbit, orbitIndex, out, in"
  echo ""
  echo "**Type flags**: isKeystone, isNotable, isMastery, isJewelSocket, isAscendancyStart, isProxy, isBlighted, isBloodline, isMultipleChoice, isMultipleChoiceOption"
  echo ""
  echo "**Attribute grants**: grantedStrength, grantedDexterity, grantedIntelligence, grantedPassivePoints"
  echo ""
  echo "**Mastery-specific**: inactiveIcon, activeIcon, activeEffectImage, masteryEffects"
  echo ""
  echo "**Jewel socket**: expansionJewel (with size, index, proxy, parent sub-fields)"
  echo ""
  echo "**Other**: ascendancyName, classStartIndex, flavourText, reminderText, recipe, root"
  echo ""
  echo "### Mastery Effects"
  echo ""
  echo "- **$mastery_count** mastery nodes with **$mastery_effects** unique selectable effects"
  echo "- Each mastery has an array of \`masteryEffects\`, each with \`effect\` (ID) and \`stats\` (array of stat lines)"
  echo ""
  echo "### Stats"
  echo ""
  echo "- **$unique_stats** unique stat line strings across all nodes"
  echo ""
  echo "## Classes and Ascendancies"
  echo ""
  echo "**$class_count** base classes, each with ascendancy subclasses:"
  echo ""
  echo "| Class | Str | Dex | Int | Ascendancies |"
  echo "|-------|-----|-----|-----|--------------|"
  printf '%s\n' "$class_table"
  echo ""
  echo "### Nodes Per Ascendancy"
  echo ""
  echo "| Ascendancy | Nodes |"
  echo "|------------|-------|"
  printf '%s\n' "$asc_table"
  echo ""
  echo "### Alternate Ascendancies"
  echo ""
  printf '%s\n' "$alt_count alternate ascendancy definitions in \`[\"alternate_ascendancies\"]\`:"
  echo ""
  echo "| ID | Name |"
  echo "|---------|------|"
  printf '%s\n' "$alt_table"
  echo ""
  printf '%s\n' "These are bloodline-based alternate ascendancy trees (3.25+). Nodes belonging to alternate ascendancies have \`isBloodline = true\`."
  echo ""
  echo "## Groups"
  echo ""
  echo "**$group_count** node groups defining spatial layout."
  echo ""
  echo "Each group has:"
  echo "- \`x\`, \`y\` — coordinates"
  echo "- \`orbits\` — available orbit radius indices"
  echo "- \`nodes\` — array of node IDs in this group"
  echo "- \`background\` (optional) — \`image\`, \`isHalfImage\`"
  echo ""
  echo "## Constants"
  echo ""
  echo '```lua'
  printf '%s\n' "$constants_block"
  echo '```'
  echo ""
  echo "- \`skillsPerOrbit\`: max nodes per orbit ring [1, 6, 16, 16, 40, 72, 72]"
  echo "- \`orbitRadii\`: pixel distances [0, 82, 162, 335, 493, 662, 846]"
  echo "- \`PSSCentreInnerRadius\`: $pss_radius"
  echo ""
  echo "## Points"
  echo ""
  echo "- \`totalPoints\`: $total_points (passive skill points available)"
  echo "- \`ascendancyPoints\`: $asc_points"
  echo ""
  echo "## Jewel Slots"
  echo ""
  echo "**$jewel_slot_count** jewel socket node IDs listed in top-level \`jewelSlots\` array."
  echo ""
  echo "## Historical Node Counts"
  echo ""
  echo "| Version | Nodes |"
  echo "|---------|-------|"
  printf '%s\n' "$historical_table"
  echo ""
  echo "## Examples"
  echo ""
  echo "### Keystone"
  echo ""
  echo '```lua'
  printf '%s\n' "$sample_keystone"
  echo '```'
  echo ""
  echo "### Notable (non-ascendancy)"
  echo ""
  echo '```lua'
  printf '%s\n' "$sample_notable"
  echo '```'
  echo ""
  echo "### Mastery (first 2 effects shown)"
  echo ""
  echo '```lua'
  printf '%s\n' "$sample_mastery"
  echo '```'
  echo ""
  echo "### Jewel Socket"
  echo ""
  echo '```lua'
  printf '%s\n' "$sample_jewel"
  echo '```'
  echo ""
  echo "### Small (regular) Node"
  echo ""
  echo '```lua'
  printf '%s\n' "$sample_small"
  echo '```'
  echo ""
  echo "## Edge Cases"
  echo ""
  printf '%s\n' "1. **Old format versions (2_6, 3_6-3_9)**: Compact/minified Lua — field names are abbreviated (\`[\"oo\"]\`, \`[\"n\"]\`). No \`[\"skill\"]=\` field, so grep-based counting returns 0. Only versions 3.10+ use the expanded readable format."
  echo ""
  printf '%s\n' "2. **Alternate tree variants**: \`{version}_alternate\` directories contain the alternate ascendancy tree. These have additional bloodline nodes. See Historical Node Counts table for per-version comparison."
  echo ""
  printf '%s\n' "3. **Ruthless variants**: \`{version}_ruthless\` directories. Same base tree structure, may have different node values."
  echo ""
  echo "4. **Proxy nodes** ($proxy): Internal positioning markers with \`isProxy = true\` and \`name = \"Position Proxy\"\`. Not displayed to players."
  echo ""
  echo "5. **Multiple choice sets**: Parent node has \`isMultipleChoice = true\`, children have \`isMultipleChoiceOption = true\`. Player must pick exactly one option. Used by Ascendant class and bloodline ascendancies."
  echo ""
  echo "6. **Blighted passives** ($blighted): Have \`recipe\` field with 3 oil names for anointing."
  echo ""
  printf '%s\n' "7. **Stats with newlines**: Some stat strings contain \`\\n\` for multi-line display (especially keystones)."
  echo ""
  echo "8. **classStartIndex**: $class_start_index nodes have this field — these are the starting nodes for each class on the tree."
} > "$OUT"

# ── Self-Check ───────────────────────────────────────────────────

[[ -f "$OUT" ]] || { echo "ERROR: $OUT not created" >&2; exit 1; }
[[ -s "$OUT" ]] || { echo "ERROR: $OUT is empty" >&2; exit 1; }
head -1 "$OUT" | grep -q "@generated" || { echo "ERROR: Missing @generated header" >&2; exit 1; }

echo "OK: $OUT generated"
