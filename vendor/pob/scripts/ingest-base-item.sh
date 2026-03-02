#!/usr/bin/env bash
# Usage: bash vendor/pob/scripts/ingest-base-item.sh <pob_path> <output_dir> <gameVersion> <pobCommit> <pobVersion>
# Input:  <pob_path>/src/Data/Bases/{slot}.lua (20 files, fishing/graft excluded)
# Output: <output_dir>/{slot}.json (20 files)
# Stdout: OK / FILES / ITEMS / PER_FILE summary
# Exit:   0 = success, 1 = error
set -euo pipefail

pob_path="${1:?Usage: $0 <pob_path> <output_dir> <gameVersion> <pobCommit> <pobVersion>}"
output_dir="${2:?Usage: $0 <pob_path> <output_dir> <gameVersion> <pobCommit> <pobVersion>}"
gameVersion="${3:?Usage: $0 <pob_path> <output_dir> <gameVersion> <pobCommit> <pobVersion>}"
pobCommit="${4:?Usage: $0 <pob_path> <output_dir> <gameVersion> <pobCommit> <pobVersion>}"
pobVersion="${5:?Usage: $0 <pob_path> <output_dir> <gameVersion> <pobCommit> <pobVersion>}"

BASES="$pob_path/src/Data/Bases"
[[ -d "$BASES" ]] || { echo "ERROR: $BASES not found" >&2; exit 1; }
rm -rf "$output_dir"
mkdir -p "$output_dir"

SLOTS=(amulet axe belt body boots bow claw dagger flask gloves helmet jewel mace quiver ring shield staff sword tincture wand)

total_items=0
per_file=""

for slot in "${SLOTS[@]}"; do
  lua_file="$BASES/$slot.lua"
  json_file="$output_dir/$slot.json"

  [[ -f "$lua_file" ]] || { echo "ERROR: $lua_file not found" >&2; exit 1; }

  perl -e '
use strict;

my $file = $ARGV[0];
my $slot = $ARGV[1];
open(my $fh, "<", $file) or die "Cannot open $file: $!";
my $content = do { local $/; <$fh> };
close($fh);

# Determine which type-specific block this slot has
my %slot_type = (
  sword => "weapon", axe => "weapon", mace => "weapon", dagger => "weapon",
  claw => "weapon", wand => "weapon", staff => "weapon", bow => "weapon",
  body => "armour", boots => "armour", gloves => "armour", helmet => "armour",
  shield => "armour",
  flask => "flask",
  tincture => "tincture",
);
my $spec_type = $slot_type{$slot} // "";

my %weapon_map = (
  PhysicalMin => "physMin", PhysicalMax => "physMax",
  CritChanceBase => "critChance", AttackRateBase => "attackRate", Range => "range",
);
my %armour_map = (
  ArmourBaseMin => "armourMin", ArmourBaseMax => "armourMax",
  EvasionBaseMin => "evasionMin", EvasionBaseMax => "evasionMax",
  EnergyShieldBaseMin => "energyShieldMin", EnergyShieldBaseMax => "energyShieldMax",
  WardBaseMin => "wardMin", WardBaseMax => "wardMax",
  BlockChance => "blockChance", MovementPenalty => "movementPenalty",
);

# Extract all item blocks: itemBases["Name"] = { ... ^}
my @items;
while ($content =~ /itemBases\["([^"]+)"\]\s*=\s*\{(.*?)^\}/gms) {
  my ($name, $body) = ($1, $2);
  my %item;
  $item{name} = $name;

  (my $id = $name) =~ s/\x27//g;
  $id =~ s/ /_/g;
  $item{id} = $id;

  if ($body =~ /\btype\s*=\s*"([^"]+)"/) { $item{type} = $1; }
  if ($body =~ /\bsubType\s*=\s*"([^"]+)"/) { $item{subType} = $1; }

  if ($body =~ /\bimplicit\s*=\s*"((?:[^"\\]|\\.)*)"/) {
    my $imp = $1;
    $imp =~ s/\\n/\n/g;
    $item{implicit} = $imp;
  }

  if ($body =~ /\bsocketLimit\s*=\s*(\d+)/) { $item{socketLimit} = int($1); }

  # tags = { key = true, ... } → sorted string array
  my @tags;
  if ($body =~ /\btags\s*=\s*\{([^}]*)\}/) {
    my $tblock = $1;
    while ($tblock =~ /(\w+)\s*=\s*true/g) {
      push @tags, $1;
    }
    @tags = sort @tags;
  }
  $item{tags} = \@tags;

  my %req;
  if ($body =~ /\breq\s*=\s*\{([^}]*)\}/) {
    my $req_str = $1;
    while ($req_str =~ /(\w+)\s*=\s*(\d+)/g) {
      $req{$1} = int($2);
    }
  }
  $item{req} = \%req;

  # Type-specific block
  if ($spec_type eq "weapon" && $body =~ /\bweapon\s*=\s*\{([^}]*)\}/) {
    my $w = $1;
    my %wdata;
    while ($w =~ /(\w+)\s*=\s*([\d.]+)/g) {
      my $jkey = $weapon_map{$1};
      if (defined $jkey) { $wdata{$jkey} = $2 + 0; }
    }
    $item{weapon} = \%wdata;
  }
  elsif ($spec_type eq "armour" && $body =~ /\barmour\s*=\s*\{([^}]*)\}/) {
    my $a = $1;
    my %adata;
    while ($a =~ /(\w+)\s*=\s*([\d.]+)/g) {
      my $jkey = $armour_map{$1};
      if (defined $jkey) {
        my $val = $2 + 0;
        if ($val != 0) { $adata{$jkey} = $val; }
      }
    }
    $item{armour} = \%adata;
  }
  elsif ($spec_type eq "flask" && $body =~ /\bflask\s*=\s*(\{.+\})\s*,\s*$/m) {
    # Match full line to handle nested buff = { ... } braces
    my $fline = $1;
    my %fdata;
    # Extract numeric fields before any nested brace
    while ($fline =~ /\b(life|mana|duration|chargesUsed|chargesMax)\s*=\s*([\d.]+)/g) {
      $fdata{$1} = $2 + 0;
    }
    # buff array: buff = { "str1", "str2" }
    if ($fline =~ /buff\s*=\s*\{([^}]*)\}/) {
      my $bstr = $1;
      my @buffs;
      while ($bstr =~ /"((?:[^"\\]|\\.)*)"/g) {
        push @buffs, $1;
      }
      $fdata{buff} = \@buffs;
    }
    $item{flask} = \%fdata;
  }
  elsif ($spec_type eq "tincture" && $body =~ /\btincture\s*=\s*\{([^}]*)\}/) {
    my $t = $1;
    my %tdata;
    while ($t =~ /(\w+)\s*=\s*([\d.]+)/g) {
      $tdata{$1} = $2 + 0;
    }
    $item{tincture} = \%tdata;
  }

  push @items, \%item;
}

@items = sort { lc($a->{name}) cmp lc($b->{name}) } @items;

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
  return $n;
}

print "[\n";
for my $i (0 .. $#items) {
  my $it = $items[$i];
  print "  {\n";
  print "    \"id\": " . json_str($it->{id}) . ",\n";
  print "    \"name\": " . json_str($it->{name}) . ",\n";
  print "    \"type\": " . json_str($it->{type}) . ",\n";

  if (defined $it->{subType}) {
    print "    \"subType\": " . json_str($it->{subType}) . ",\n";
  } else {
    print "    \"subType\": null,\n";
  }

  if (defined $it->{implicit}) {
    print "    \"implicit\": " . json_str($it->{implicit}) . ",\n";
  } else {
    print "    \"implicit\": null,\n";
  }

  my $r = $it->{req};
  my @rparts;
  for my $k (qw(level str dex int)) {
    if (defined $r->{$k}) {
      push @rparts, "\"$k\": " . json_num($r->{$k});
    } else {
      push @rparts, "\"$k\": null";
    }
  }
  print "    \"req\": { " . join(", ", @rparts) . " },\n";

  if (defined $it->{socketLimit}) {
    print "    \"socketLimit\": " . json_num($it->{socketLimit}) . ",\n";
  } else {
    print "    \"socketLimit\": null,\n";
  }

  # tags array
  my @t = @{$it->{tags}};
  print "    \"tags\": [";
  if (scalar(@t) > 0) {
    print join(", ", map { json_str($_) } @t);
  }
  print "]";

  if (defined $it->{weapon}) {
    print ",\n";
    my $w = $it->{weapon};
    my @wparts;
    for my $k (qw(physMin physMax critChance attackRate range)) {
      if (defined $w->{$k}) {
        push @wparts, "\"$k\": " . json_num($w->{$k});
      }
    }
    print "    \"weapon\": { " . join(", ", @wparts) . " }";
  }
  elsif (defined $it->{armour}) {
    print ",\n";
    my $a = $it->{armour};
    my @aparts;
    for my $k (qw(armourMin armourMax evasionMin evasionMax energyShieldMin energyShieldMax wardMin wardMax blockChance movementPenalty)) {
      if (defined $a->{$k}) {
        push @aparts, "\"$k\": " . json_num($a->{$k});
      }
    }
    print "    \"armour\": { " . join(", ", @aparts) . " }";
  }
  elsif (defined $it->{flask}) {
    print ",\n";
    my $f = $it->{flask};
    my @fparts;
    for my $k (qw(life mana duration chargesUsed chargesMax)) {
      if (defined $f->{$k}) {
        push @fparts, "\"$k\": " . json_num($f->{$k});
      }
    }
    if (defined $f->{buff}) {
      my @bstrs = map { json_str($_) } @{$f->{buff}};
      push @fparts, "\"buff\": [" . join(", ", @bstrs) . "]";
    }
    print "    \"flask\": { " . join(", ", @fparts) . " }";
  }
  elsif (defined $it->{tincture}) {
    print ",\n";
    my $t = $it->{tincture};
    my @tparts;
    for my $k (qw(manaBurn cooldown)) {
      if (defined $t->{$k}) {
        push @tparts, "\"$k\": " . json_num($t->{$k});
      }
    }
    print "    \"tincture\": { " . join(", ", @tparts) . " }";
  }

  print "\n  }";
  if ($i < $#items) { print ","; }
  print "\n";
}
print "]\n";
' "$lua_file" "$slot" > "$json_file"

  item_count=$(jq length "$json_file")
  total_items=$((total_items + item_count))

  if [[ -n "$per_file" ]]; then per_file="$per_file "; fi
  per_file="${per_file}${slot}=${item_count}"
done

# ── Self-validation ─────────────────────────────────────────────

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
