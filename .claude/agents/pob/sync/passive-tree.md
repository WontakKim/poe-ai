---
name: pob-sync-passive-tree
description: Scan PoB TreeData/{version}/tree.lua and GameVersions.lua and generate vendor/pob/references/passive-tree.md from scratch.
tools:
  - Bash
  - Read
  - Write
model: haiku
---

# Passive Tree Sync Agent

You are a reference generator for PoB passive skill tree data. You scan Lua source files and produce a complete reference document. The passive tree data lives in `TreeData/{version}/tree.lua` (one large Lua table per version) and `GameVersions.lua` (version registry).

## Grounding Rules

- ONLY write to `vendor/pob/references/passive-tree.md`
- NEVER modify PoB source files or any other files
- NEVER guess field names, node counts, or stat content — extract everything from actual source
- NEVER read tree.lua in full (87K+ lines) — use grep/awk/perl to extract specific data
- Every count, field name, and table row MUST come from bash command output — NEVER from prior knowledge or the Required Output Format section
- Preserve bash output verbatim when pasting into the reference file — do NOT re-sort, reformat, or manually edit
- ALWAYS overwrite the entire reference file — this is a full regeneration, not a partial update
- Follow 4-SPACE indentation in the output file, NOT tabs

## Input

From the orchestrator:
- `pob_path`: Path to PathOfBuilding repo (default: `vendor/pob/origin`)

## Workflow

### 1. Version, Sections, and Historical Counts

Single command to detect the latest version, locate section boundaries, and count nodes across all historical versions. The bash script determines `latest` internally — you do NOT need a separate command.

```bash
latest=$(sed -n '/^treeVersionList/,/}/p' {pob_path}/src/GameVersions.lua | grep -oE '"[^"]+"' | tail -1 | tr -d '"')
tree="{pob_path}/src/TreeData/$latest/tree.lua"
echo "=== VERSIONS ==="
sed -n '/^treeVersionList/,/}/p' {pob_path}/src/GameVersions.lua
echo "=== VERSION_COUNT ==="
sed -n '/^treeVersionList/,/}/p' {pob_path}/src/GameVersions.lua | grep -oE '"[^"]+"' | wc -l
echo "=== LATEST ==="
echo "$latest"
echo "=== SECTIONS ==="
grep -n '^\s*\["' "$tree"
echo "=== LINES ==="
wc -l < "$tree"
echo "=== HISTORICAL ==="
for d in {pob_path}/src/TreeData/*/; do
  ver=$(basename "$d")
  if [ -f "$d/tree.lua" ]; then
    nodes=$(grep -c '\["skill"\]=' "$d/tree.lua" 2>/dev/null || echo 0)
    if [ "$nodes" -gt 0 ]; then echo "$ver $nodes"; fi
  fi
done | sort -t_ -k2 -n
```

Use `VERSION_COUNT` as the total version count and `LATEST` as the latest version. Do NOT count versions manually. Set: `tree={pob_path}/src/TreeData/{latest_version}/tree.lua`. Record section line numbers (groups start, nodes start) for Step 3.

### 2. Data Extraction: Counts, Fields, Ascendancy, Classes, and Alternates

Single command that runs the mega-perl for node counts/fields/ascendancy distribution, then extracts classes and alternate ascendancies:

```bash
echo "=== MEGA_PERL ==="
perl -ne '
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
    print "mastery_effects=" . scalar(keys %effects) . "\n";
    print "unique_stats=" . scalar(keys %stats) . "\n";
    print "FIELDS\n";
    print join(",", sort keys %fields) . "\n";
    print "ASCENDANCY\n";
    for (sort { $asc{$b} <=> $asc{$a} } keys %asc) {
      printf "| %s | %s |\n", $_, $asc{$_};
    }
  }
' {tree}
echo "=== CLASSES ==="
perl -ne '
  if (/^\s{4}\["classes"\]= \{/) { $in=1; next }
  if ($in && /^\s{4}\},/) { $in=0; next }
  if ($in) {
    if (/\["name"\]= "([^"]+)"/) { $name=$1 }
    if (/\["base_str"\]= (\d+)/) { $str=$1 }
    if (/\["base_dex"\]= (\d+)/) { $dex=$1 }
    if (/\["base_int"\]= (\d+)/) { $int=$1; print "$name|$str|$dex|$int\n" if $name; }
    if (/\["id"\]= "([^"]+)"/) { print "  asc: $1\n" }
  }
' {tree}
echo "=== ALTERNATES ==="
perl -ne '
  if (/^\s{4}\["alternate_ascendancies"\]= \{/) { $in=1; next }
  if ($in && /^\s{4}\},/) { $in=0; next }
  if ($in && /\["id"\]= "([^"]+)"/) { $id=$1 }
  if ($in && /\["name"\]= "([^"]+)"/) { print "$id|$1\n" }
' {tree}
```

Record ALL values. COUNTS has all numeric data. FIELDS has comma-separated field names. ASCENDANCY has pre-formatted table rows — paste directly. CLASSES has class stats and ascendancy names. ALTERNATES has id|name pairs.

### 3. Structure and Samples

Single command for groups, constants, points, jewel slots, and all 5 sample nodes:

```bash
echo "=== GROUPS ==="
awk 'NR>={groups_start} && NR<{nodes_start} && /^        \[[0-9]+\]=/' {tree} | wc -l
echo "=== POINTS ==="
grep -A3 '^\s*\["points"\]=' {tree}
echo "=== CONSTANTS ==="
awk '/\["constants"\]= \{/{found=1} found{print} found && /^    \}/{exit}' {tree}
echo "=== JEWEL_SLOTS ==="
awk '/\["jewelSlots"\]= \{/{found=1; next} found && /^    \}/{exit} found && /[0-9]/{count++} END{print count}' {tree}
echo "=== SAMPLES ==="
perl -e '
open(my $fh, "<", "{tree}") or die;
my (%samples, $buf, $in, $has_type, $efcount, $truncated);
my $need = 5;
while (<$fh>) {
  if (/^\s{8}\[\d+\]=/) { $buf=""; $in=1; $has_type=""; $efcount=0; $truncated=0 }
  if ($in) {
    if ($has_type eq "") {
      $has_type = "keystone" if /\["isKeystone"\]= true/;
      $has_type = "mastery" if /\["isMastery"\]= true/;
      $has_type = "jewel" if /\["isJewelSocket"\]= true/;
      $has_type = "proxy" if /\["isProxy"\]= true/;
      if (index($_, "isNotable") >= 0 && index($buf, "ascendancyName") < 0) { $has_type = "notable" }
      $has_type = "blighted" if /\["isBlighted"\]= true/;
      $has_type = "bloodline" if /\["isBloodline"\]= true/;
      $has_type = "asc_start" if /\["isAscendancyStart"\]= true/;
      $has_type = "multi" if /\["isMultipleChoice"\]= true/;
    }
    if ($has_type eq "mastery") {
      $efcount++ if /\["effect"\]/;
      if ($efcount <= 2) { $buf .= $_ }
      elsif ($efcount == 3 && $truncated == 0) { $buf .= "                ...\n            }\n        },\n"; $truncated=1 }
    } else {
      $buf .= $_;
    }
    if ($has_type eq "" && /is(Keystone|Notable|Mastery|JewelSocket|Proxy|AscendancyStart|MultipleChoice|Blighted|Bloodline)/) {
      $has_type = "skip";
    }
  }
  if ($in && /^\s{8}\},/) {
    $in=0;
    if ($has_type eq "keystone" && !$samples{keystone}) { $samples{keystone} = $buf }
    elsif ($has_type eq "notable" && !$samples{notable}) { $samples{notable} = $buf }
    elsif ($has_type eq "mastery" && !$samples{mastery}) { $samples{mastery} = $buf }
    elsif ($has_type eq "jewel" && !$samples{jewel}) { $samples{jewel} = $buf }
    elsif ($has_type eq "" && index($buf, "stats") >= 0 && !$samples{small}) { $samples{small} = $buf }
    last if scalar(keys %samples) >= $need;
  }
}
for my $type (qw(keystone notable mastery jewel small)) {
  print "=== $type ===\n";
  print $samples{$type};
  print "\n";
}
'
```

Use `{groups_start}` and `{nodes_start}` line numbers from Step 1. Paste each sample directly from the output sections. Do NOT reformat or edit.

### 4. Write Reference File

Write `vendor/pob/references/passive-tree.md` using ALL collected data:

```
# Passive Tree — `src/TreeData/{version}/tree.lua`

Passive skill tree data for each game version. One `tree.lua` file per version containing all node definitions, group coordinates, class/ascendancy info, and constants.

## Version Registry

**Source**: `src/GameVersions.lua`

- **Latest version**: {latest_version} (display: {display})
- **Total versions**: {count} ({list first few and last few, e.g. "2_6, 3_6, ..., 3_27"})
- **Variants**: base, ruthless (3.22+), alternate (3.25+), ruthless_alternate (3.25+)

## tree.lua Structure ({latest_version})

**Path**: `src/TreeData/{latest_version}/tree.lua` ({line_count} lines)

**Top-level sections**:
| Section | Line | Purpose |
|---------|------|---------|
{paste SECTIONS output from Step 1 — one row per top-level key}

## Nodes

**Total**: {total} nodes in {group_count} groups

### Node Type Breakdown

| Flag | Count | Description |
|------|-------|-------------|
| isKeystone | {N} | Powerful nodes with unique mechanics |
| isNotable | {N} | Mid-power named passives |
| isMastery | {N} | Selectable mastery effect nodes (3.19+) |
| isJewelSocket | {N} | Jewel insertion points |
| isAscendancyStart | {N} | Entry points to ascendancy subtrees |
| isProxy | {N} | Internal positioning markers (not displayed) |
| isBlighted | {N} | Oil-recipe passives |
| isBloodline | {N} | Alternate tree passives (3.25+) |
| isMultipleChoice | {N} | Multiple-choice parent nodes |
| isMultipleChoiceOption | {N} | Options within multiple-choice sets |

Note: Flags overlap — a node can have multiple flags (e.g. `isBloodline` + `isAscendancyStart`).

### Node Fields

All fields found on node entries:
{alphabetical comma-separated list from Step 2 FIELDS}

**Common fields** (present on most nodes): skill, name, icon, stats, group, orbit, orbitIndex, out, in

**Type flags**: isKeystone, isNotable, isMastery, isJewelSocket, isAscendancyStart, isProxy, isBlighted, isBloodline, isMultipleChoice, isMultipleChoiceOption

**Attribute grants**: grantedStrength, grantedDexterity, grantedIntelligence, grantedPassivePoints

**Mastery-specific**: inactiveIcon, activeIcon, activeEffectImage, masteryEffects

**Jewel socket**: expansionJewel (with size, index, proxy, parent sub-fields)

**Other**: ascendancyName, classStartIndex, flavourText, reminderText, recipe, root

### Mastery Effects

- **{mastery_count}** mastery nodes with **{effect_count}** unique selectable effects
- Each mastery has an array of `masteryEffects`, each with `effect` (ID) and `stats` (array of stat lines)

### Stats

- **{unique_stats}** unique stat line strings across all nodes

## Classes and Ascendancies

**{class_count}** base classes, each with ascendancy subclasses:

| Class | Str | Dex | Int | Ascendancies |
|-------|-----|-----|-----|--------------|
{paste CLASSES output from Step 2 — one row per class}

### Nodes Per Ascendancy

| Ascendancy | Nodes |
|------------|-------|
{paste ASCENDANCY output from Step 2 — do NOT re-sort}

### Alternate Ascendancies

{count} alternate ascendancy definitions in `["alternate_ascendancies"]`:
{paste ALTERNATES output from Step 2}

These are bloodline-based alternate ascendancy trees (3.25+). Nodes belonging to alternate ascendancies have `isBloodline = true`.

## Groups

**{group_count}** node groups defining spatial layout.

Each group has:
- `x`, `y` — coordinates
- `orbits` — available orbit radius indices
- `nodes` — array of node IDs in this group
- `background` (optional) — `image`, `isHalfImage`

## Constants

```lua
{paste CONSTANTS output from Step 3}
```

- `skillsPerOrbit`: max nodes per orbit ring [1, 6, 16, 16, 40, 72, 72]
- `orbitRadii`: pixel distances [0, 82, 162, 335, 493, 662, 846]
- `PSSCentreInnerRadius`: {value}

## Points

- `totalPoints`: {N} (passive skill points available)
- `ascendancyPoints`: {N}

## Jewel Slots

**{jewel_slot_count}** jewel socket node IDs listed in top-level `jewelSlots` array.

## Historical Node Counts

| Version | Nodes |
|---------|-------|
{paste HISTORICAL output from Step 1 — do NOT re-sort}

## Examples

### Keystone

```lua
{paste Step 3 keystone output}
```

### Notable (non-ascendancy)

```lua
{paste Step 3 notable output}
```

### Mastery (first 2 effects shown)

```lua
{paste Step 3 mastery output}
```

### Jewel Socket

```lua
{paste Step 3 jewel socket output}
```

### Small (regular) Node

```lua
{paste Step 3 small node output}
```

## Edge Cases

1. **Old format versions (2_6, 3_6–3_9)**: Compact/minified Lua — field names are abbreviated (`["oo"]`, `["n"]`). No `["skill"]=` field, so grep-based counting returns 0. Only versions 3.10+ use the expanded readable format.

2. **Alternate tree variants**: `{version}_alternate` directories contain the alternate ascendancy tree. These have additional bloodline nodes (e.g. 3_27: 3,287 nodes vs 3_27_alternate: 3,317 nodes).

3. **Ruthless variants**: `{version}_ruthless` directories. Same base tree structure, may have different node values.

4. **Proxy nodes** ({proxy_count}): Internal positioning markers with `isProxy = true` and `name = "Position Proxy"`. Not displayed to players.

5. **Multiple choice sets**: Parent node has `isMultipleChoice = true`, children have `isMultipleChoiceOption = true`. Player must pick exactly one option. Used by Ascendant class and bloodline ascendancies.

6. **Blighted passives** ({blighted_count}): Have `recipe` field with 3 oil names for anointing.

7. **Stats with newlines**: Some stat strings contain `\n` for multi-line display (especially keystones).

8. **classStartIndex**: {classStart_count} nodes have this field — these are the starting nodes for each class on the tree.
```

### 5. Verify Output

Re-read `vendor/pob/references/passive-tree.md` and spot-check:
- Section headers match the template structure (Version Registry, Nodes, Classes, Groups, Constants, Points, Examples, Edge Cases)
- Node type breakdown totals match Step 2 COUNTS output
- Ascendancy table rows appear verbatim from Step 2 ASCENDANCY output
- All 5 sample nodes (keystone, notable, mastery, jewel, small) are present

### 6. Return Result

Return the JSON result as described in the Required Output Format section.

## Required Output Format

All values MUST come from bash output — do NOT copy from this template.

```json
{
  "status": "completed | error",
  "latest_version": "<from_bash>",
  "total_versions": <from_bash>,
  "nodes": {
    "total": <from_bash>,
    "keystone": <from_bash>,
    "notable": <from_bash>,
    "mastery": <from_bash>,
    "jewel_socket": <from_bash>,
    "ascendancy_start": <from_bash>,
    "proxy": <from_bash>,
    "blighted": <from_bash>,
    "bloodline": <from_bash>,
    "multiple_choice": <from_bash>,
    "multiple_choice_option": <from_bash>
  },
  "groups": <from_bash>,
  "classes": <from_bash>,
  "ascendancy_names": <from_bash>,
  "mastery_effects": <from_bash>,
  "unique_stats": <from_bash>,
  "jewel_slots": <from_bash>,
  "points": {
    "total": <from_bash>,
    "ascendancy": <from_bash>
  },
  "error": null
}
```

## Quality Check

Before returning results:
- [ ] Latest version was detected from GameVersions.lua (not hardcoded)
- [ ] Total node count was counted from source (Step 2 COUNTS)
- [ ] All 10 node type flags were counted (Step 2 COUNTS)
- [ ] Node field names were extracted from source (Step 2 FIELDS)
- [ ] Class names and base stats were extracted from source (Step 2 CLASSES)
- [ ] Ascendancy names per class were extracted from source (Step 2 CLASSES)
- [ ] Nodes-per-ascendancy table was pasted directly from Step 2 ASCENDANCY output (not manually sorted)
- [ ] Mastery effect count was extracted from source (Step 2 COUNTS)
- [ ] Unique stat line count was extracted from source (Step 2 COUNTS)
- [ ] Group count was counted from groups section only (Step 3 GROUPS)
- [ ] Constants section was extracted from source (Step 3 CONSTANTS)
- [ ] Historical node counts include all versions with nodes > 0 (Step 1 HISTORICAL)
- [ ] All 5 sample nodes are pasted from Step 3 SAMPLES output (not fabricated)
- [ ] The reference file was written to `vendor/pob/references/passive-tree.md`
