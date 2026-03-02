#!/usr/bin/env bash
# Usage: bash vendor/pob/scripts/ingest-unique-item.sh <pob_path> <output_dir> <base_dir> <gameVersion> <pobCommit> <pobVersion>
# Input:  <pob_path>/src/Data/Uniques/{slot}.lua (20 files) + Special/New.lua
# Reads:  <base_dir>/{slot}.json (type/levelReq lookup)
# Output: <output_dir>/{slot}.json (20 files)
# Exclude: Special/Generated.lua, Special/race.lua, fishing, graft
# Stdout: OK / FILES / ITEMS / PER_FILE summary
# Exit:   0 = success, 1 = error
set -euo pipefail

pob_path="${1:?Usage: $0 <pob_path> <output_dir> <base_dir> <gameVersion> <pobCommit> <pobVersion>}"
output_dir="${2:?Usage: $0 <pob_path> <output_dir> <base_dir> <gameVersion> <pobCommit> <pobVersion>}"
base_dir="${3:?Usage: $0 <pob_path> <output_dir> <base_dir> <gameVersion> <pobCommit> <pobVersion>}"
gameVersion="${4:?Usage: $0 <pob_path> <output_dir> <base_dir> <gameVersion> <pobCommit> <pobVersion>}"
pobCommit="${5:?Usage: $0 <pob_path> <output_dir> <base_dir> <gameVersion> <pobCommit> <pobVersion>}"
pobVersion="${6:?Usage: $0 <pob_path> <output_dir> <base_dir> <gameVersion> <pobCommit> <pobVersion>}"

UNIQUES="$pob_path/src/Data/Uniques"
NEW_FILE="$UNIQUES/Special/New.lua"

[[ -d "$UNIQUES" ]] || { echo "ERROR: $UNIQUES not found" >&2; exit 1; }
[[ -d "$base_dir" ]] || { echo "ERROR: $base_dir not found" >&2; exit 1; }
rm -rf "$output_dir"
mkdir -p "$output_dir"

SLOTS=(amulet axe belt body boots bow claw dagger flask gloves helmet jewel mace quiver ring shield staff sword tincture wand)

# ── Build base-type lookup TSV: name\ttype\tlevel\tslot ─────────

lookup_file="$output_dir/.base_lookup.tsv"
for slot in "${SLOTS[@]}"; do
  [[ -f "$base_dir/$slot.json" ]] || { echo "ERROR: $base_dir/$slot.json not found" >&2; exit 1; }
  jq -r --arg slot "$slot" '.[] | [.name, .type, (.req.level // ""), $slot] | @tsv' "$base_dir/$slot.json"
done > "$lookup_file"

# ── Parse each slot ─────────────────────────────────────────────

total_items=0
per_file=""

for slot in "${SLOTS[@]}"; do
  lua_file="$UNIQUES/$slot.lua"
  json_file="$output_dir/$slot.json"

  [[ -f "$lua_file" ]] || { echo "ERROR: $lua_file not found" >&2; exit 1; }

  perl -e '
use strict;

my $slot_file    = $ARGV[0];
my $new_file     = $ARGV[1];
my $lookup_file  = $ARGV[2];
my $current_slot = $ARGV[3];

# ── Load base-item lookup ───────────────────────────────────
my %base_lookup;
open(my $lf, "<", $lookup_file) or die "Cannot open $lookup_file: $!";
while (<$lf>) {
  chomp;
  my ($bname, $btype, $blevel, $bslot) = split /\t/;
  $base_lookup{$bname} = { type => $btype, level => $blevel, slot => $bslot };
}
close($lf);

# ── Patterns ────────────────────────────────────────────────
my $META_RE = qr/^(?:\{variant:[^}]+\})?\s*(?:Variant:|League:|Source:|LevelReq:|Requires Level|Limited to:|Sockets:|Radius:|Has Alt Variant:|Upgrade:|Implicits:)/;
my $STANDALONE_RE = qr/^(Corrupted|Shaper Item|Elder Item|Crusader Item|Redeemer Item|Hunter Item|Warlord Item|Synthesised)$/;

# Normalize Unicode diacritics for base-item lookup (Maelström → Maelstrom)
sub normalize_name {
  my $s = shift;
  $s =~ s/\xc3\xb6/o/g;
  $s =~ s/\xc3\xa4/a/g;
  $s =~ s/\xc3\xbc/u/g;
  return $s;
}

sub lookup_base {
  my $bt = shift;
  return $base_lookup{$bt} if exists $base_lookup{$bt};
  my $n = normalize_name($bt);
  return $base_lookup{$n} if exists $base_lookup{$n};
  return undef;
}

sub variant_ok {
  my ($line, $cidx) = @_;
  return 1 if $cidx == 0;
  if ($line =~ /^\{variant:([^}]+)\}/) {
    my @nums = split /,/, $1;
    return scalar(grep { $_ == $cidx } @nums);
  }
  return 1;
}

sub strip_prefixes {
  my $line = shift;
  $line =~ s/^\{variant:[^}]+\}//;
  $line =~ s/^\{tags:[^}]+\}//;
  return $line;
}

sub json_str {
  my $s = shift;
  $s =~ s/\\/\\\\/g;
  $s =~ s/"/\\"/g;
  return "\"$s\"";
}

sub parse_item {
  my ($block, $is_new) = @_;
  my @lines = grep { $_ ne "" } map { my $l = $_; $l =~ s/^\s+//; $l =~ s/\s+$//; $l } split(/\n/, $block);
  return undef if scalar(@lines) < 2;

  my $name = $lines[0];

  # ── Collect metadata from all lines ─────────────────────
  my @variant_names;
  my $league;
  my $level_req_override;
  my $requires_level;
  my $implicits_n;
  my $implicits_line_idx;
  my ($req_str, $req_dex, $req_int) = (0, 0, 0);
  my $sockets;
  my $source;
  my $limited_to;

  for my $i (0 .. $#lines) {
    if ($lines[$i] =~ /^Variant:\s*(.+)/)    { push @variant_names, $1; }
    if ($lines[$i] =~ /^League:\s*(.+)/)     { $league = $1; }
    if ($lines[$i] =~ /^LevelReq:\s*(\d+)/)  { $level_req_override = int($1); }
    if ($lines[$i] =~ /^Requires Level:?\s*(\d+)/) {
      $requires_level = int($1);
      if ($lines[$i] =~ /(\d+)\s+Str/) { $req_str = int($1); }
      if ($lines[$i] =~ /(\d+)\s+Dex/) { $req_dex = int($1); }
      if ($lines[$i] =~ /(\d+)\s+Int/) { $req_int = int($1); }
    }
    if ($lines[$i] =~ /^Limited to:\s*(\d+)/) { $limited_to = int($1); }
    if ($lines[$i] =~ /^Sockets:\s*(.+)/)   { $sockets = $1; }
    if ($lines[$i] =~ /^(?:\{variant:[^}]+\})?\s*Source:\s*(.+)/) { $source = $1; }
    if ($lines[$i] =~ /^Implicits:\s*(\d+)/) { $implicits_n = int($1); $implicits_line_idx = $i; }
  }

  # ── Determine current variant index (1-based; 0 = no variants) ─
  my $cidx;
  if (scalar(@variant_names) == 0) {
    $cidx = 0;
  } else {
    $cidx = scalar(@variant_names);
    for my $i (0 .. $#variant_names) {
      if ($variant_names[$i] eq "Current") {
        $cidx = $i + 1;
        last;
      }
    }
  }

  # ── Collect influence flags ────────────────────────────────
  my %influence_map = (
    "Shaper Item" => "shaper", "Elder Item" => "elder",
    "Crusader Item" => "crusader", "Redeemer Item" => "redeemer",
    "Hunter Item" => "hunter", "Warlord Item" => "warlord",
    "Synthesised" => "synthesised",
  );
  my @influences;
  for my $i (1 .. $#lines) {
    if ($lines[$i] =~ /$STANDALONE_RE/) {
      my $kw = $1;
      if (exists $influence_map{$kw}) {
        push @influences, $influence_map{$kw};
      }
    }
  }

  # ── Extract base type lines (after name) ───────────────────
  # Skip standalone keywords (Shaper Item, etc.) that may precede base type
  # If first real line has {variant:} prefix → collect consecutive {variant:} lines
  # Otherwise → single base type line only
  my @base_lines;
  my $base_start = 1;
  while ($base_start <= $#lines && $lines[$base_start] =~ /$STANDALONE_RE/) {
    $base_start++;
  }
  if ($base_start <= $#lines) {
    if ($lines[$base_start] =~ /^\{variant:/) {
      for my $i ($base_start .. $#lines) {
        if ($lines[$i] =~ /^\{variant:/) {
          push @base_lines, $lines[$i];
        } else {
          last;
        }
      }
    } else {
      push @base_lines, $lines[$base_start];
    }
  }

  # Pick base type for current variant
  my $base_type;
  my $last_base;
  for my $bl (@base_lines) {
    if ($bl =~ /^\{variant:([^}]+)\}(.+)/) {
      my @nums = split /,/, $1;
      $last_base = $2;
      if ($cidx > 0 && grep { $_ == $cidx } @nums) {
        $base_type = $2;
        last;
      }
    } else {
      $base_type = $bl;
    }
  }
  # Fallback: if no variant matched, use the last base type line
  $base_type //= $last_base;
  return undef unless defined $base_type;

  # For New.lua: filter to current slot
  if ($is_new) {
    my $bl = lookup_base($base_type);
    return undef unless defined $bl && $bl->{slot} eq $current_slot;
  }

  # ── Lookup type from base item ────────────────────────────
  my $type;
  my $bl_ref = lookup_base($base_type);
  if (defined $bl_ref) {
    $type = $bl_ref->{type};
  }

  # ── LevelReq: LevelReq: > Requires Level > base lookup ───
  my $level_req;
  if (defined $level_req_override) {
    $level_req = $level_req_override;
  } elsif (defined $requires_level) {
    $level_req = $requires_level;
  } elsif (defined $bl_ref && $bl_ref->{level} ne "") {
    $level_req = int($bl_ref->{level});
  }

  # ── Extract implicits and mods ────────────────────────────
  my @implicits;
  my @mods;

  if (defined $implicits_line_idx) {
    # Implicits: next N lines
    for my $i (1 .. $implicits_n) {
      my $idx = $implicits_line_idx + $i;
      last if $idx > $#lines;
      my $line = $lines[$idx];
      if (variant_ok($line, $cidx)) {
        push @implicits, strip_prefixes($line);
      }
    }
    # Mods: everything after implicits
    my $mod_start = $implicits_line_idx + $implicits_n + 1;
    for my $i ($mod_start .. $#lines) {
      my $line = $lines[$i];
      next if $line =~ /$STANDALONE_RE/;
      next unless variant_ok($line, $cidx);
      push @mods, strip_prefixes($line);
    }
  } else {
    # No Implicits: → 0 implicits, remaining non-meta lines are mods
    my $start = $base_start + scalar(@base_lines);
    for my $i ($start .. $#lines) {
      my $line = $lines[$i];
      next if $line =~ /$META_RE/;
      next if $line =~ /$STANDALONE_RE/;
      next unless variant_ok($line, $cidx);
      push @mods, strip_prefixes($line);
    }
  }

  # Build req hash only if Requires Level line was present
  my $req_hash;
  if (defined $requires_level) {
    $req_hash = { str => $req_str, dex => $req_dex, int => $req_int };
  }

  return {
    name       => $name,
    baseType   => $base_type,
    type       => $type,
    levelReq   => $level_req,
    league     => $league,
    implicits  => \@implicits,
    mods       => \@mods,
    req        => $req_hash,
    sockets    => $sockets,
    influences => \@influences,
    source     => $source,
    variants   => \@variant_names,
    limitedTo  => $limited_to,
  };
}

# ── Parse blocks from file content ──────────────────────────
sub parse_blocks {
  my ($content) = @_;
  my @blocks;
  while ($content =~ /\[\[(.*?)\]\]/gs) {
    push @blocks, $1;
  }
  return @blocks;
}

# ── Read and parse main slot file ───────────────────────────
open(my $sf, "<", $slot_file) or die "Cannot open $slot_file: $!";
my $slot_content = do { local $/; <$sf> };
close($sf);

my @all_items;
for my $block (parse_blocks($slot_content)) {
  my $item = parse_item($block, 0);
  push @all_items, $item if defined $item;
}

# ── Read and parse New.lua (filter to current slot) ─────────
if (-f $new_file) {
  open(my $nf, "<", $new_file) or die "Cannot open $new_file: $!";
  my $new_content = do { local $/; <$nf> };
  close($nf);

  for my $block (parse_blocks($new_content)) {
    my $item = parse_item($block, 1);
    push @all_items, $item if defined $item;
  }
}

# ── Sort by name (case-insensitive) ─────────────────────────
@all_items = sort { lc($a->{name}) cmp lc($b->{name}) } @all_items;

# ── Output JSON ─────────────────────────────────────────────
print "[\n";
for my $i (0 .. $#all_items) {
  my $it = $all_items[$i];

  (my $id = $it->{name}) =~ s/\x27//g;
  $id =~ s/ /_/g;

  print "  {\n";
  print "    \"id\": " . json_str($id) . ",\n";
  print "    \"name\": " . json_str($it->{name}) . ",\n";
  print "    \"baseType\": " . json_str($it->{baseType}) . ",\n";

  if (defined $it->{type}) {
    print "    \"type\": " . json_str($it->{type}) . ",\n";
  } else {
    print "    \"type\": null,\n";
  }

  if (defined $it->{levelReq}) {
    print "    \"levelReq\": " . int($it->{levelReq}) . ",\n";
  } else {
    print "    \"levelReq\": null,\n";
  }

  if (defined $it->{league}) {
    print "    \"league\": " . json_str($it->{league}) . ",\n";
  } else {
    print "    \"league\": null,\n";
  }

  # req (attribute requirements)
  if (defined $it->{req}) {
    my $r = $it->{req};
    print "    \"req\": { \"str\": $r->{str}, \"dex\": $r->{dex}, \"int\": $r->{int} },\n";
  } else {
    print "    \"req\": null,\n";
  }

  # sockets
  if (defined $it->{sockets}) {
    print "    \"sockets\": " . json_str($it->{sockets}) . ",\n";
  } else {
    print "    \"sockets\": null,\n";
  }

  # influences
  my @inf = @{$it->{influences}};
  if (scalar(@inf) > 0) {
    print "    \"influences\": [" . join(", ", map { json_str($_) } @inf) . "],\n";
  }

  # source
  if (defined $it->{source}) {
    print "    \"source\": " . json_str($it->{source}) . ",\n";
  }

  # variants (sparse)
  my @vars = @{$it->{variants}};
  if (scalar(@vars) > 0) {
    print "    \"variants\": [" . join(", ", map { json_str($_) } @vars) . "],\n";
  }

  # limitedTo (sparse)
  if (defined $it->{limitedTo}) {
    print "    \"limitedTo\": " . int($it->{limitedTo}) . ",\n";
  }

  # implicit array
  my @imp = @{$it->{implicits}};
  print "    \"implicit\": [";
  if (scalar(@imp) > 0) {
    print join(", ", map { json_str($_) } @imp);
  }
  print "],\n";

  # mods array
  my @m = @{$it->{mods}};
  print "    \"mods\": [";
  if (scalar(@m) > 0) {
    print "\n";
    for my $j (0 .. $#m) {
      print "      " . json_str($m[$j]);
      print "," if $j < $#m;
      print "\n";
    }
    print "    ";
  }
  print "]\n";

  print "  }";
  print "," if $i < $#all_items;
  print "\n";
}
print "]\n";
' "$lua_file" "$NEW_FILE" "$lookup_file" "$slot" > "$json_file"

  item_count=$(jq length "$json_file")
  total_items=$((total_items + item_count))

  if [[ -n "$per_file" ]]; then per_file="$per_file "; fi
  per_file="${per_file}${slot}=${item_count}"
done

# Cleanup
rm -f "$lookup_file"

# ── Self-validation ─────────────────────────────────────────

file_count=0
errors=""

for slot in "${SLOTS[@]}"; do
  json_file="$output_dir/$slot.json"
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
  # Check for type=null items
  null_count=$(jq '[.[] | select(.type == null)] | length' "$json_file")
  if [[ "$null_count" -ne 0 ]]; then
    errors="${errors}TYPE_NULL: $json_file has $null_count items with type=null\n"
  fi
  file_count=$((file_count + 1))
done

if [[ -n "$errors" ]]; then
  printf '%b' "$errors" >&2
  echo "ERROR: validation failed" >&2
  exit 1
fi

if [[ "$file_count" -ne 20 ]]; then
  echo "ERROR: expected 20 files, got $file_count" >&2
  exit 1
fi

# ── Source marker ────────────────────────────────────────────

cat > "$output_dir/source.json" <<EOF
{
  "gameVersion": "$gameVersion",
  "pobCommit": "$pobCommit",
  "pobVersion": "$pobVersion",
  "builtAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# ── Summary ─────────────────────────────────────────────────

echo "OK: $output_dir"
echo "FILES: $file_count"
echo "ITEMS: $total_items"
echo "PER_FILE: $per_file"
