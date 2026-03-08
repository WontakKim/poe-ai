#!/usr/bin/env bash
# Usage: bash vendor/ninja/scripts/resolve-league.sh <output_path>
# Input:  poedb.tw/us/League HTML table
# Output: <output_path> (leagues.json)
# Stdout: OK / LEAGUES summary
# Exit:   0 = success, 1 = error
set -euo pipefail

output_path="${1:?Usage: $0 <output_path>}"
mkdir -p "$(dirname "$output_path")"

# Fetch league table from poedb
html=$(curl -sL 'https://poedb.tw/us/League')
[[ -n "$html" ]] || { echo "ERROR: Failed to fetch poedb league page" >&2; exit 1; }

# Parse table rows:
#   <tr><td>3.27</td><td><a href='...'>Keepers</a>...</td><td>18</td><td>2025-11-01</td><td>...</td></tr>
# Extract: version, league name (from <a> tag text), weeks, start date
echo "$html" | perl -e '
use strict;
my $input = do { local $/; <STDIN> };
my @rows;
while ($input =~ /<tr><td>([\d.]+)<\/td><td><a[^>]*>([^<]+)<\/a>[^<]*<\/td><td>(\d*)<\/td><td>([\d-]+)<\/td>/g) {
  my ($ver, $name, $weeks, $start) = ($1, $2, $3 eq "" ? 0 : $3, $4);
  push @rows, "  {\"version\": \"$ver\", \"league\": \"$name\", \"weeks\": $weeks, \"startDate\": \"$start\"}";
}
print "[\n" . join(",\n", @rows) . "\n]\n";
' > "$output_path"

# Validate
if ! jq empty "$output_path" 2>/dev/null; then
  echo "ERROR: Invalid JSON in $output_path" >&2
  exit 1
fi

count=$(jq length "$output_path")
if [[ "$count" -eq 0 ]]; then
  echo "ERROR: No leagues found" >&2
  exit 1
fi

echo "OK: $output_path"
echo "LEAGUES: $count"
