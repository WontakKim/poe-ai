#!/usr/bin/env bash
# Usage: bash vendor/pob/scripts/ingest-skill-gem.sh <pob_path> <output_dir> <gameVersion> <pobCommit> <pobVersion>
# Input:  <pob_path>/src/Data/Gems.lua + <pob_path>/src/Data/Skills/{act,sup}_{str,dex,int}.lua
# Output: <output_dir>/{act,sup}-{str,dex,int}.json (6 files)
# Stdout: OK / FILES / ITEMS / PER_FILE summary
# Exit:   0 = success, 1 = error
set -euo pipefail

pob_path="${1:?Usage: $0 <pob_path> <output_dir> <gameVersion> <pobCommit> <pobVersion>}"
output_dir="${2:?Usage: $0 <pob_path> <output_dir> <gameVersion> <pobCommit> <pobVersion>}"
gameVersion="${3:?Usage: $0 <pob_path> <output_dir> <gameVersion> <pobCommit> <pobVersion>}"
pobCommit="${4:?Usage: $0 <pob_path> <output_dir> <gameVersion> <pobCommit> <pobVersion>}"
pobVersion="${5:?Usage: $0 <pob_path> <output_dir> <gameVersion> <pobCommit> <pobVersion>}"

GEMS="$pob_path/src/Data/Gems.lua"
SKILLS="$pob_path/src/Data/Skills"

[[ -f "$GEMS" ]] || { echo "ERROR: $GEMS not found" >&2; exit 1; }
[[ -d "$SKILLS" ]] || { echo "ERROR: $SKILLS not found" >&2; exit 1; }
rm -rf "$output_dir"
mkdir -p "$output_dir"

# Player-visible skill files only (no glove/minion/spectre/other)
SKILL_FILES=("$SKILLS/act_str.lua" "$SKILLS/act_dex.lua" "$SKILLS/act_int.lua" "$SKILLS/sup_str.lua" "$SKILLS/sup_dex.lua" "$SKILLS/sup_int.lua")
for sf in "${SKILL_FILES[@]}"; do
  [[ -f "$sf" ]] || { echo "ERROR: $sf not found" >&2; exit 1; }
done

# ── Pass 1: Parse Gems.lua → TSV lookup ─────────────────────────
# Columns: grantedEffectId \t name \t tags_csv \t reqStr \t reqDex \t reqInt \t naturalMaxLevel \t vaalGem \t is_support

gems_tsv="$output_dir/.gems_lookup.tsv"

perl -e '
use strict;
my $content = do { local $/; <STDIN> };

while ($content =~ /^\t\["Metadata[^"]*"\]\s*=\s*\{(.*?)^\t\},/gms) {
  my $body = $1;

  my ($grantedEffectId, $name, $reqStr, $reqDex, $reqInt, $naturalMaxLevel);
  my ($vaalGem, $has_active, $has_support) = (0, 0, 0);
  my @tags;

  if ($body =~ /grantedEffectId = "([^"]+)"/) { $grantedEffectId = $1; } else { next; }
  if ($body =~ /name = "([^"]+)"/) { $name = $1; } else { next; }
  if ($body =~ /reqStr = (\d+)/) { $reqStr = $1; } else { $reqStr = 0; }
  if ($body =~ /reqDex = (\d+)/) { $reqDex = $1; } else { $reqDex = 0; }
  if ($body =~ /reqInt = (\d+)/) { $reqInt = $1; } else { $reqInt = 0; }
  if ($body =~ /naturalMaxLevel = (\d+)/) { $naturalMaxLevel = $1; } else { $naturalMaxLevel = 20; }
  if ($body =~ /vaalGem = true/) { $vaalGem = 1; }
  if ($body =~ /grants_active_skill = true/) { $has_active = 1; }
  if ($body =~ /support = true/) { $has_support = 1; }

  # Extract tag keys from the tags = { ... } block
  if ($body =~ /tags\s*=\s*\{(.*?)\}/s) {
    my $tag_block = $1;
    while ($tag_block =~ /(\w+)\s*=\s*true/g) {
      push @tags, $1;
    }
  }

  # is_support: has support tag AND NOT grants_active_skill (hybrids → active)
  my $is_support = ($has_support && $has_active == 0) ? 1 : 0;

  my $tags_csv = join(",", @tags);
  print join("\t", $grantedEffectId, $name, $tags_csv, $reqStr, $reqDex, $reqInt, $naturalMaxLevel, $vaalGem, $is_support) . "\n";
}
' < "$GEMS" > "$gems_tsv"

gems_count=$(wc -l < "$gems_tsv" | tr -d ' ')
if [[ "$gems_count" -eq 0 ]]; then
  echo "ERROR: No gems parsed from $GEMS" >&2
  exit 1
fi

# ── Pass 2: Parse Skills/*.lua + join with gems TSV → JSON ──────
# Process all 6 skill files, output one combined JSON stream per gem

all_json="$output_dir/.all_gems.jsonl"

perl -e '
use strict;

my $tsv_file = $ARGV[0];
shift @ARGV;
# Remaining args are skill files

# Load gems lookup: grantedEffectId → record
my %gems;
open(my $tf, "<", $tsv_file) or die "Cannot open $tsv_file: $!";
while (<$tf>) {
  chomp;
  my @f = split /\t/, $_, -1;
  next if scalar(@f) < 9;
  $gems{$f[0]} = {
    name          => $f[1],
    tags_csv      => $f[2],
    reqStr        => int($f[3]),
    reqDex        => int($f[4]),
    reqInt        => int($f[5]),
    naturalMaxLevel => int($f[6]),
    vaalGem       => int($f[7]),
    is_support    => int($f[8]),
  };
}
close($tf);

sub json_str {
  my $s = shift;
  $s =~ s/\\/\\\\/g;
  $s =~ s/"/\\"/g;
  $s =~ s/\n/\\n/g;
  return "\"$s\"";
}

sub json_num {
  my $n = shift;
  if ($n == int($n)) { return int($n); }
  return $n + 0;
}

# Parse each skill file
for my $skill_file (@ARGV) {
  open(my $sf, "<", $skill_file) or die "Cannot open $skill_file: $!";
  my $content = do { local $/; <$sf> };
  close($sf);

  # Extract skill blocks: skills["Key"] = { ... ^}
  while ($content =~ /^skills\["([^"]+)"\]\s*=\s*\{(.*?)^\}/gms) {
    my ($skill_id, $body) = ($1, $2);

    # Skip hidden skills
    next if $body =~ /hidden\s*=\s*true/;

    # Must have a matching gem entry
    my $gem = $gems{$skill_id};
    next unless defined $gem;

    # ── Extract top-level fields ───────────────────────────
    my $description = "";
    if ($body =~ /description\s*=\s*"((?:[^"\\]|\\.)*)"/) {
      $description = $1;
      $description =~ s/\\n/\n/g;
    }

    my $castTime = "null";
    if ($body =~ /\bcastTime\s*=\s*([\d.]+)/) { $castTime = $1 + 0; }

    my $baseEffectiveness = "null";
    if ($body =~ /\bbaseEffectiveness\s*=\s*([\d.]+)/) { $baseEffectiveness = $1 + 0; }

    my $incrementalEffectiveness = "null";
    if ($body =~ /\bincrementalEffectiveness\s*=\s*([\d.]+)/) { $incrementalEffectiveness = $1 + 0; }

    # skillTypes: [SkillType.Xxx] = true → extract Xxx
    my @skillTypes;
    if ($body =~ /skillTypes\s*=\s*\{([^}]*)\}/s) {
      my $st_block = $1;
      while ($st_block =~ /SkillType\.(\w+)/g) {
        push @skillTypes, $1;
      }
    }

    # Support-specific fields
    my $is_support = $gem->{is_support};
    my (@requireSkillTypes, @addSkillTypes, @excludeSkillTypes);

    if ($is_support) {
      if ($body =~ /requireSkillTypes\s*=\s*\{([^}]*)\}/s) {
        my $block = $1;
        while ($block =~ /SkillType\.(\w+)/g) {
          push @requireSkillTypes, $1;
        }
      }
      if ($body =~ /addSkillTypes\s*=\s*\{([^}]*)\}/s) {
        my $block = $1;
        while ($block =~ /SkillType\.(\w+)/g) {
          push @addSkillTypes, $1;
        }
      }
      if ($body =~ /excludeSkillTypes\s*=\s*\{([^}]*)\}/s) {
        my $block = $1;
        while ($block =~ /SkillType\.(\w+)/g) {
          push @excludeSkillTypes, $1;
        }
      }
    }

    # ── Extract level[1] data ──────────────────────────────
    # Level data is always on a single line, so extract the full line to handle nested braces
    my ($levelRequirement, $critChance, $damageEffectiveness, $manaMultiplier) = ("null", "null", "null", "null");
    my @costTypes;

    if ($body =~ /\[1\]\s*=\s*\{(.+)\},?\s*$/m) {
      my $lv1 = $1;
      if ($lv1 =~ /levelRequirement\s*=\s*(\d+)/) { $levelRequirement = int($1); }
      if ($lv1 =~ /critChance\s*=\s*([\d.]+)/) { $critChance = $1 + 0; }
      if ($lv1 =~ /damageEffectiveness\s*=\s*([\d.]+)/) { $damageEffectiveness = $1 + 0; }
      if ($lv1 =~ /manaMultiplier\s*=\s*([\d.-]+)/) { $manaMultiplier = $1 + 0; }

      # cost = { Mana = 8, } → extract cost type names
      if ($lv1 =~ /cost\s*=\s*\{([^}]*)\}/) {
        my $cost_block = $1;
        while ($cost_block =~ /([A-Z][A-Za-z]+)\s*=/g) {
          push @costTypes, $1;
        }
      }
    }

    # ── Determine partition ────────────────────────────────
    # Type: support if is_support, else active
    my $type_prefix = $is_support ? "sup" : "act";

    # Primary attribute: max(str, dex, int). Tie: int > dex > str.
    my ($rs, $rd, $ri) = ($gem->{reqStr}, $gem->{reqDex}, $gem->{reqInt});
    my $attr;
    if ($ri >= $rd && $ri >= $rs) { $attr = "int"; }
    elsif ($rd >= $rs) { $attr = "dex"; }
    else { $attr = "str"; }

    my $partition = "$type_prefix-$attr";

    # ── Build ID ───────────────────────────────────────────
    (my $id = $skill_id) =~ s/\x27//g;
    $id =~ s/ /_/g;

    # ── Output JSONL (one line per gem, partition prefix) ──
    my @parts;
    push @parts, "\"id\": " . json_str($id);
    push @parts, "\"name\": " . json_str($gem->{name});

    # Tags array
    my @tag_list = split /,/, $gem->{tags_csv};
    my $tags_json = "[" . join(", ", map { json_str($_) } @tag_list) . "]";
    push @parts, "\"tags\": $tags_json";

    # Req
    push @parts, "\"req\": { \"str\": $rs, \"dex\": $rd, \"int\": $ri }";

    push @parts, "\"naturalMaxLevel\": " . json_num($gem->{naturalMaxLevel});
    push @parts, "\"vaalGem\": " . ($gem->{vaalGem} ? "true" : "false");
    push @parts, "\"description\": " . json_str($description);

    # castTime: null for supports
    if ($castTime eq "null") {
      push @parts, "\"castTime\": null";
    } else {
      push @parts, "\"castTime\": " . json_num($castTime);
    }

    if ($baseEffectiveness eq "null") {
      push @parts, "\"baseEffectiveness\": null";
    } else {
      push @parts, "\"baseEffectiveness\": " . json_num($baseEffectiveness);
    }

    if ($incrementalEffectiveness eq "null") {
      push @parts, "\"incrementalEffectiveness\": null";
    } else {
      push @parts, "\"incrementalEffectiveness\": " . json_num($incrementalEffectiveness);
    }

    # Level 1 data
    if ($levelRequirement eq "null") {
      push @parts, "\"levelRequirement\": null";
    } else {
      push @parts, "\"levelRequirement\": " . json_num($levelRequirement);
    }

    my $cost_json = "[" . join(", ", map { json_str($_) } @costTypes) . "]";
    push @parts, "\"costTypes\": $cost_json";

    if ($critChance eq "null") {
      push @parts, "\"critChance\": null";
    } else {
      push @parts, "\"critChance\": " . json_num($critChance);
    }

    if ($damageEffectiveness eq "null") {
      push @parts, "\"damageEffectiveness\": null";
    } else {
      push @parts, "\"damageEffectiveness\": " . json_num($damageEffectiveness);
    }

    # Support-specific fields
    if ($is_support) {
      if ($manaMultiplier eq "null") {
        push @parts, "\"manaMultiplier\": null";
      } else {
        push @parts, "\"manaMultiplier\": " . json_num($manaMultiplier);
      }

      my $req_st = "[" . join(", ", map { json_str($_) } @requireSkillTypes) . "]";
      my $add_st = "[" . join(", ", map { json_str($_) } @addSkillTypes) . "]";
      my $exc_st = "[" . join(", ", map { json_str($_) } @excludeSkillTypes) . "]";
      push @parts, "\"requireSkillTypes\": $req_st";
      push @parts, "\"addSkillTypes\": $add_st";
      push @parts, "\"excludeSkillTypes\": $exc_st";
    }

    my $st_json = "[" . join(", ", map { json_str($_) } @skillTypes) . "]";
    push @parts, "\"skillTypes\": $st_json";

    # Output: partition \t json_object
    print "$partition\t{" . join(", ", @parts) . "}\n";
  }
}
' "$gems_tsv" "${SKILL_FILES[@]}" > "$all_json"

# ── Pass 3: Partition into 6 files ──────────────────────────────

PARTITIONS=(act-str act-dex act-int sup-str sup-dex sup-int)

total_items=0
per_file=""

for part in "${PARTITIONS[@]}"; do
  json_file="$output_dir/$part.json"

  # Extract lines for this partition, sort by name (field 2 in JSON), wrap in array
  grep "^${part}	" "$all_json" | cut -f2- | sort -t'"' -k4,4f | awk '
    BEGIN { print "[" }
    NR > 1 { printf ",\n" }
    { printf "  %s", $0 }
    END { printf "\n]\n" }
  ' > "$json_file"

  item_count=$(jq length "$json_file")
  total_items=$((total_items + item_count))

  if [[ -n "$per_file" ]]; then per_file="$per_file "; fi
  per_file="${per_file}${part}=${item_count}"
done

# Cleanup temp files
rm -f "$gems_tsv" "$all_json"

# ── Self-validation ─────────────────────────────────────────────

file_count=0
errors=""

for part in "${PARTITIONS[@]}"; do
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

if [[ "$total_items" -eq 0 ]]; then
  echo "ERROR: total items is 0" >&2
  exit 1
fi

# ── Source marker ────────────────────────────────────────────────

cat > "$output_dir/source.json" <<EOF
{
  "gameVersion": "$gameVersion",
  "pobCommit": "$pobCommit",
  "pobVersion": "$pobVersion",
  "builtAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# ── Summary ─────────────────────────────────────────────────────

echo "OK: $output_dir"
echo "FILES: $file_count"
echo "ITEMS: $total_items"
echo "PER_FILE: $per_file"
