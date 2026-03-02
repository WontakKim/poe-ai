#!/usr/bin/env bash
# Usage: bash vendor/pob/scripts/ingest-passive-tree.sh <pob_path> <output_dir> <gameVersion> <pobCommit> <pobVersion>
# Input:  <pob_path>/src/TreeData/{version}/tree.lua
# Output: <output_dir>/{keystone,notable,mastery,jewel-socket,small,meta}.json (6 files)
# Stdout: OK / FILES / ITEMS / PER_FILE summary
# Exit:   0 = success, 1 = error
set -euo pipefail

pob_path="${1:?Usage: $0 <pob_path> <output_dir> <gameVersion> <pobCommit> <pobVersion>}"
output_dir="${2:?Usage: $0 <pob_path> <output_dir> <gameVersion> <pobCommit> <pobVersion>}"
gameVersion="${3:?Usage: $0 <pob_path> <output_dir> <gameVersion> <pobCommit> <pobVersion>}"
pobCommit="${4:?Usage: $0 <pob_path> <output_dir> <gameVersion> <pobCommit> <pobVersion>}"
pobVersion="${5:?Usage: $0 <pob_path> <output_dir> <gameVersion> <pobCommit> <pobVersion>}"

# ── Section 1: Validate + setup ──────────────────────────────────

GV="$pob_path/src/GameVersions.lua"
[[ -f "$GV" ]] || { echo "ERROR: $GV not found" >&2; exit 1; }
rm -rf "$output_dir"
mkdir -p "$output_dir"

# ── Section 2: Version detection → locate tree.lua ───────────────

latest=$(sed -n '/^treeVersionList/,/}/p' "$GV" | grep -oE '"[0-9]+_[0-9]+"' | tail -1 | tr -d '"')
tree="$pob_path/src/TreeData/$latest/tree.lua"
[[ -f "$tree" ]] || { echo "ERROR: $tree not found" >&2; exit 1; }

# ── Section 3: Mega-perl — parse nodes → classified JSONL ────────

all_jsonl="$output_dir/.all_nodes.jsonl"

perl -e '
use strict;

sub json_str {
  my $s = shift;
  $s =~ s/\\/\\\\/g;
  $s =~ s/"/\\"/g;
  $s =~ s/\n/\\n/g;
  return "\"$s\"";
}

sub json_str_arr {
  my @arr = @{$_[0]};
  return "[" . join(", ", map { json_str($_) } @arr) . "]";
}

open(my $fh, "<", $ARGV[0]) or die "Cannot open $ARGV[0]: $!";

my ($in_nodes, $depth, $buf, $node_id) = (0, 0, "", "");

while (<$fh>) {
  if (/^    \["nodes"\]= \{/) { $in_nodes = 1; next; }
  if ($in_nodes && /^    \},?$/) { last; }
  next if $in_nodes == 0;

  # New block start
  if (/^        \["?(\w+)"?\]= \{/) {
    $buf = $_; $depth = 1; $node_id = $1;
    next;
  }

  if ($depth > 0) {
    $buf .= $_;
    my $opens = () = /\{/g;
    my $closes = () = /\}/g;
    $depth += $opens - $closes;

    if ($depth <= 0) {
      $depth = 0;

      # ── Skip non-gameplay nodes ──
      next if $node_id eq "root";
      next if index($buf, "\"isProxy\"") >= 0;
      next if index($buf, "\"isAscendancyStart\"") >= 0;
      next if index($buf, "\"classStartIndex\"") >= 0;

      # ── Classify ──
      my $partition;
      if    (index($buf, "\"isKeystone\"") >= 0)    { $partition = "keystone"; }
      elsif (index($buf, "\"isNotable\"") >= 0)     { $partition = "notable"; }
      elsif (index($buf, "\"isMastery\"") >= 0)     { $partition = "mastery"; }
      elsif (index($buf, "\"isJewelSocket\"") >= 0) { $partition = "jewel-socket"; }
      else                                           { $partition = "small"; }

      # ── Common fields ──
      my $name = "";
      if ($buf =~ /\["name"\]= "([^"]*)"/) { $name = $1; }

      # Anchor to 12-space indent to avoid matching inner masteryEffects stats
      my @stats;
      if ($buf =~ /^ {12}\["stats"\]= \{([^}]*)\}/m) {
        my $block = $1;
        while ($block =~ /"((?:[^"\\]|\\.)*)"/g) {
          my $s = $1;
          $s =~ s/\\n/\n/g;
          push @stats, $s;
        }
      }

      my $ascName = "";
      if ($buf =~ /\["ascendancyName"\]= "([^"]*)"/) { $ascName = $1; }

      my @reminder;
      if ($buf =~ /^ {12}\["reminderText"\]= \{([^}]*)\}/m) {
        my $block = $1;
        while ($block =~ /"((?:[^"\\]|\\.)*)"/g) {
          my $s = $1;
          $s =~ s/\\n/\n/g;
          push @reminder, $s;
        }
      }

      # Graph position
      my ($group, $orbit, $orbitIndex) = (0, 0, 0);
      if ($buf =~ /\["group"\]= (\d+)/) { $group = int($1); }
      if ($buf =~ /\["orbit"\]= (\d+)/) { $orbit = int($1); }
      if ($buf =~ /\["orbitIndex"\]= (\d+)/) { $orbitIndex = int($1); }

      # Connections
      my @out_nodes;
      if ($buf =~ /^ {12}\["out"\]= \{([^}]*)\}/m) {
        my $block = $1;
        while ($block =~ /"(\d+)"/g) { push @out_nodes, $1; }
      }
      my @in_nodes;
      if ($buf =~ /^ {12}\["in"\]= \{([^}]*)\}/m) {
        my $block = $1;
        while ($block =~ /"(\d+)"/g) { push @in_nodes, $1; }
      }

      # Granted attributes (omit if 0)
      my ($gStr, $gDex, $gInt, $gPP) = (0, 0, 0, 0);
      if ($buf =~ /\["grantedStrength"\]= (\d+)/) { $gStr = int($1); }
      if ($buf =~ /\["grantedDexterity"\]= (\d+)/) { $gDex = int($1); }
      if ($buf =~ /\["grantedIntelligence"\]= (\d+)/) { $gInt = int($1); }
      if ($buf =~ /\["grantedPassivePoints"\]= (\d+)/) { $gPP = int($1); }

      # ── Build JSON ──
      my @parts;
      push @parts, "\"id\": " . json_str($node_id);
      push @parts, "\"name\": " . json_str($name);
      push @parts, "\"stats\": " . json_str_arr(\@stats);
      if ($ascName ne "") {
        push @parts, "\"ascendancyName\": " . json_str($ascName);
      }
      if (@reminder) {
        push @parts, "\"reminderText\": " . json_str_arr(\@reminder);
      }

      push @parts, "\"group\": $group";
      push @parts, "\"orbit\": $orbit";
      push @parts, "\"orbitIndex\": $orbitIndex";
      push @parts, "\"out\": " . json_str_arr(\@out_nodes);
      push @parts, "\"in\": " . json_str_arr(\@in_nodes);
      if ($gStr > 0)  { push @parts, "\"grantedStrength\": $gStr"; }
      if ($gDex > 0)  { push @parts, "\"grantedDexterity\": $gDex"; }
      if ($gInt > 0)  { push @parts, "\"grantedIntelligence\": $gInt"; }
      if ($gPP > 0)   { push @parts, "\"grantedPassivePoints\": $gPP"; }

      # ── Type-specific fields ──
      if ($partition eq "keystone") {
        my @flavour;
        if ($buf =~ /^ {12}\["flavourText"\]= \{([^}]*)\}/m) {
          my $block = $1;
          while ($block =~ /"((?:[^"\\]|\\.)*)"/g) {
            my $s = $1;
            $s =~ s/\\n/\n/g;
            push @flavour, $s;
          }
        }
        push @parts, "\"flavourText\": " . json_str(join("\n", @flavour));
      }
      elsif ($partition eq "notable") {
        my $is_blighted = (index($buf, "\"isBlighted\"") >= 0) ? "true" : "false";
        my $is_bloodline = (index($buf, "\"isBloodline\"") >= 0) ? "true" : "false";
        my $is_mco = (index($buf, "\"isMultipleChoiceOption\"") >= 0) ? "true" : "false";
        push @parts, "\"isBlighted\": $is_blighted";
        push @parts, "\"isBloodline\": $is_bloodline";
        push @parts, "\"isMultipleChoiceOption\": $is_mco";
        if ($buf =~ /^ {12}\["recipe"\]= \{([^}]*)\}/m) {
          my $rblock = $1;
          my @recipe;
          while ($rblock =~ /"((?:[^"\\]|\\.)*)"/g) {
            push @recipe, $1;
          }
          if (@recipe) {
            push @parts, "\"recipe\": " . json_str_arr(\@recipe);
          }
        }
      }
      elsif ($partition eq "mastery") {
        # Extract masteryEffects block, then regex for effect/stats pairs
        my @effects;
        if ($buf =~ /^ {12}\["masteryEffects"\]= \{(.+?)^ {12}\}/ms) {
          my $me_block = $1;
          while ($me_block =~ /\["effect"\]= (\d+).*?\["stats"\]= \{([^}]*)\}/gs) {
            my ($eid, $sblock) = ($1, $2);
            my @estats;
            while ($sblock =~ /"((?:[^"\\]|\\.)*)"/g) {
              my $s = $1;
              $s =~ s/\\n/\n/g;
              push @estats, $s;
            }
            push @effects, "{\"effect\": $eid, \"stats\": " . json_str_arr(\@estats) . "}";
          }
        }
        push @parts, "\"masteryEffects\": [" . join(", ", @effects) . "]";
      }
      elsif ($partition eq "jewel-socket") {
        if ($buf =~ /\["expansionJewel"\]= \{(.*?)\}/s) {
          my $ej = $1;
          my ($size, $index, $proxy, $parent) = ("null", "null", "null", "null");
          if ($ej =~ /\["size"\]= (\d+)/) { $size = $1; }
          if ($ej =~ /\["index"\]= (\d+)/) { $index = $1; }
          if ($ej =~ /\["proxy"\]= "([^"]*)"/) { $proxy = json_str($1); }
          if ($ej =~ /\["parent"\]= "([^"]*)"/) { $parent = json_str($1); }
          push @parts, "\"expansionJewel\": {\"size\": $size, \"index\": $index, \"proxy\": $proxy, \"parent\": $parent}";
        }
      }
      # small: common fields only

      print "$partition\t{" . join(", ", @parts) . "}\n";
    }
  }
}
close($fh);
' "$tree" > "$all_jsonl"

# ── Section 4: Partition + sort + format as JSON arrays ──────────

PARTITIONS=(keystone notable mastery jewel-socket small)

total_items=0
per_file=""
counts_args=""

for part in "${PARTITIONS[@]}"; do
  json_file="$output_dir/$part.json"

  # Sort by name: splitting by ", field 8 = name value
  grep "^${part}	" "$all_jsonl" | cut -f2- | sort -t'"' -k8,8f | awk '
    BEGIN { print "[" }
    NR > 1 { printf ",\n" }
    { printf "  %s", $0 }
    END { printf "\n]\n" }
  ' > "$json_file"

  item_count=$(jq length "$json_file")
  total_items=$((total_items + item_count))

  if [[ -n "$per_file" ]]; then per_file="$per_file "; fi
  per_file="${per_file}${part}=${item_count}"
  counts_args="${counts_args} ${part}=${item_count}"
done

# Cleanup temp
rm -f "$all_jsonl"

# ── Section 5: Meta-perl → meta.json ────────────────────────────

perl -e '
use strict;

sub json_str {
  my $s = shift;
  $s =~ s/\\/\\\\/g;
  $s =~ s/"/\\"/g;
  return "\"$s\"";
}

my $file = $ARGV[0];
shift @ARGV;

# Parse node counts from args: keystone=54 notable=975 ...
my %node_counts;
for my $arg (@ARGV) {
  if ($arg =~ /^(\S+)=(\d+)$/) {
    $node_counts{$1} = int($2);
  }
}

open(my $fh, "<", $file) or die "Cannot open $file: $!";
my $content = do { local $/; <$fh> };
close($fh);

# ── Classes ──
my @classes;
if ($content =~ /^    \["classes"\]= \{(.+?)^    \},/ms) {
  my $cblock = $1;
  # Each class is a { ... } block at depth 2
  while ($cblock =~ /\{(.*?\["name"\]\s*=\s*"([^"]+)".*?)\n        \},?/gs) {
    my ($body, $cname) = ($1, $2);
    my ($base_str, $base_dex, $base_int) = (0, 0, 0);
    if ($body =~ /base_str.*?=\s*(\d+)/) { $base_str = int($1); }
    if ($body =~ /base_dex.*?=\s*(\d+)/) { $base_dex = int($1); }
    if ($body =~ /base_int.*?=\s*(\d+)/) { $base_int = int($1); }

    # Ascendancy IDs
    my @asc_ids;
    while ($body =~ /\["id"\]= "([^"]+)"/g) {
      push @asc_ids, $1;
    }

    my $asc_json = "[" . join(", ", map { json_str($_) } @asc_ids) . "]";
    push @classes, "{\"name\": " . json_str($cname) . ", \"base_str\": $base_str, \"base_dex\": $base_dex, \"base_int\": $base_int, \"ascendancies\": $asc_json}";
  }
}

# ── Alternate Ascendancies ──
my @alt_asc;
if ($content =~ /^    \["alternate_ascendancies"\]= \{(.+?)^    \},/ms) {
  my $ablock = $1;
  while ($ablock =~ /\["id"\]= "([^"]+)".*?\["name"\]= "([^"]+)"/gs) {
    push @alt_asc, "{\"id\": " . json_str($1) . ", \"name\": " . json_str($2) . "}";
  }
}

# ── Constants ──
my ($skills_per_orbit, $orbit_radii, $pss_radius) = ("[]", "[]", "null");
if ($content =~ /^    \["constants"\]= \{(.+?)^    \},?/ms) {
  my $cblock = $1;
  if ($cblock =~ /\["skillsPerOrbit"\]= \{([^}]+)\}/s) {
    my $spo = $1;
    my @vals;
    while ($spo =~ /(\d+)/g) { push @vals, int($1); }
    $skills_per_orbit = "[" . join(", ", @vals) . "]";
  }
  if ($cblock =~ /\["orbitRadii"\]= \{([^}]+)\}/s) {
    my $or = $1;
    my @vals;
    while ($or =~ /(\d+)/g) { push @vals, int($1); }
    $orbit_radii = "[" . join(", ", @vals) . "]";
  }
  if ($cblock =~ /PSSCentreInnerRadius.*?=\s*(\d+)/) { $pss_radius = int($1); }
}

# ── Points ──
my ($total_points, $asc_points) = ("null", "null");
if ($content =~ /\["points"\]= \{(.+?)\}/s) {
  my $pblock = $1;
  if ($pblock =~ /totalPoints.*?=\s*(\d+)/) { $total_points = int($1); }
  if ($pblock =~ /ascendancyPoints.*?=\s*(\d+)/) { $asc_points = int($1); }
}

# ── Jewel Slots ──
my @jewel_slots;
if ($content =~ /^    \["jewelSlots"\]= \{(.+?)^    \},/ms) {
  my $jblock = $1;
  while ($jblock =~ /(\d+)/g) { push @jewel_slots, int($1); }
}

# ── Assemble meta.json ──
my @nc_parts;
for my $k (sort keys %node_counts) {
  (my $jk = $k) =~ s/-/_/g;
  push @nc_parts, "\"$jk\": $node_counts{$k}";
}

print "{\n";
print "  \"classes\": [\n";
for my $i (0 .. $#classes) {
  print "    $classes[$i]";
  print "," if $i < $#classes;
  print "\n";
}
print "  ],\n";
print "  \"alternate_ascendancies\": [\n";
for my $i (0 .. $#alt_asc) {
  print "    $alt_asc[$i]";
  print "," if $i < $#alt_asc;
  print "\n";
}
print "  ],\n";
print "  \"constants\": {\n";
print "    \"skillsPerOrbit\": $skills_per_orbit,\n";
print "    \"orbitRadii\": $orbit_radii,\n";
print "    \"PSSCentreInnerRadius\": $pss_radius\n";
print "  },\n";
print "  \"points\": {\n";
print "    \"totalPoints\": $total_points,\n";
print "    \"ascendancyPoints\": $asc_points\n";
print "  },\n";
print "  \"jewelSlots\": [" . join(", ", @jewel_slots) . "],\n";
print "  \"nodeCounts\": {" . join(", ", @nc_parts) . "}\n";
print "}\n";
' "$tree" $counts_args > "$output_dir/meta.json"

total_items=$((total_items + 1))
per_file="${per_file} meta=1"

# ── Section 6: Self-validation ───────────────────────────────────

ALL_FILES=(keystone notable mastery jewel-socket small meta)

file_count=0
errors=""

for part in "${ALL_FILES[@]}"; do
  json_file="$output_dir/$part.json"
  if [[ ! -f "$json_file" ]]; then
    errors="${errors}MISSING: $json_file\n"
    continue
  fi
  if [[ ! -s "$json_file" ]]; then
    errors="${errors}EMPTY: $json_file\n"
    continue
  fi
  if ! jq empty "$json_file" 2>/dev/null; then
    errors="${errors}INVALID_JSON: $json_file\n"
    continue
  fi
  file_count=$((file_count + 1))
done

if [[ -n "$errors" ]]; then
  printf '%b' "$errors" >&2
  echo "ERROR: validation failed" >&2
  exit 1
fi

if [[ "$file_count" -ne 6 ]]; then
  echo "ERROR: expected 6 files, got $file_count" >&2
  exit 1
fi

# ── Section 7: Source marker ─────────────────────────────────────

cat > "$output_dir/source.json" <<EOF
{
  "gameVersion": "$gameVersion",
  "pobCommit": "$pobCommit",
  "pobVersion": "$pobVersion",
  "builtAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# ── Section 8: Summary ───────────────────────────────────────────

echo "OK: $output_dir"
echo "FILES: $file_count"
echo "ITEMS: $total_items"
echo "PER_FILE: $per_file"
