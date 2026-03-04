#!/usr/bin/env bash
# Usage: bash vendor/ninja/scripts/ingest-build.sh <league> <output_dir> <gameVersion>
# Input:  poe.ninja builds API (search + dictionary) + build-index-state
# Output: <output_dir>/builds.json, source.json
# Stdout: OK / FILES / ITEMS
# Exit:   0 = success, 1 = error
set -euo pipefail

league="${1:?Usage: $0 <league> <output_dir> <gameVersion>}"
output_dir="${2:?Usage: $0 <league> <output_dir> <gameVersion>}"
gameVersion="${3:?Usage: $0 <league> <output_dir> <gameVersion>}"

# Reject path traversal
case "$output_dir" in
  *..*)
    echo "ERROR: output_dir must not contain '..'" >&2
    exit 1
    ;;
esac

mkdir -p "$output_dir"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DECODER="$SCRIPT_DIR/decode-builds-proto.py"

TMPDIR="${TMPDIR:-/tmp}"
tmp_prefix="$TMPDIR/ninja_build_$$"
trap 'rm -f "${tmp_prefix}"*' EXIT

league_lower=$(echo "$league" | tr '[:upper:]' '[:lower:]')

# ── 1. Fetch index-state → snapshot version ─────────────────
curl -sL "https://poe.ninja/poe1/api/data/index-state" > "${tmp_prefix}_index.json"
[[ -s "${tmp_prefix}_index.json" ]] || { echo "ERROR: Empty response from index-state API" >&2; exit 1; }
jq empty "${tmp_prefix}_index.json" 2>/dev/null || { echo "ERROR: Invalid JSON from index-state API" >&2; exit 1; }

version=$(jq -r --arg league "$league_lower" \
  '[.snapshotVersions[] | select(.url == $league and .type == "exp")] | first | .version // empty' \
  "${tmp_prefix}_index.json")
[[ -n "$version" ]] || { echo "ERROR: No exp index-state found for league '$league_lower'" >&2; exit 1; }

# ── 2. Fetch build-index-state → topBuilds (non-fatal) ──────
top_builds="[]"
if curl -sL "https://poe.ninja/poe1/api/data/build-index-state" > "${tmp_prefix}_buildindex.json" 2>/dev/null \
   && [[ -s "${tmp_prefix}_buildindex.json" ]] \
   && jq empty "${tmp_prefix}_buildindex.json" 2>/dev/null; then
  top_builds=$(jq -r --arg league "$league_lower" '
    [.leagueBuilds[] | select(.leagueUrl == $league)] | first |
    if . == null then []
    else
      [.statistics[] | {
        class: .class,
        skill: .skill,
        share: ((.percentage // 0) * 100 | round / 100),
        trend: (.trend // 0)
      }]
    end
  ' "${tmp_prefix}_buildindex.json" 2>/dev/null) || top_builds="[]"
fi

# ── 3. Fetch search protobuf → decode → search.json ─────────
curl -sL "https://poe.ninja/poe1/api/builds/${version}/search?overview=${league_lower}&type=exp" \
  > "${tmp_prefix}_search.pb"
[[ -s "${tmp_prefix}_search.pb" ]] || { echo "ERROR: Empty response from search API" >&2; exit 1; }

python3 "$DECODER" search < "${tmp_prefix}_search.pb" > "${tmp_prefix}_search.json"
jq empty "${tmp_prefix}_search.json" 2>/dev/null || { echo "ERROR: Invalid JSON from protobuf decoder" >&2; exit 1; }

# Total > 0 guard
total=$(jq '.total' "${tmp_prefix}_search.json")
if [[ "$total" -le 0 ]]; then
  echo "ERROR: empty snapshot (total=$total)" >&2
  exit 1
fi

# ── 4. Fetch dictionaries (dedup by hash) ───────────────────
# Use a temp file to track fetched hashes (bash 3 compat, no associative arrays)
hash_map="${tmp_prefix}_hashmap"
: > "$hash_map"

while IFS=$'\t' read -r dict_id dict_hash; do
  existing=$(grep "^${dict_hash}	" "$hash_map" | cut -f2 || true)
  if [[ -n "$existing" ]]; then
    # Already fetched this hash — copy the result
    cp "${tmp_prefix}_dict-${existing}.json" "${tmp_prefix}_dict-${dict_id}.json"
    continue
  fi
  curl -sL "https://poe.ninja/poe1/api/builds/dictionary/${dict_hash}" \
    > "${tmp_prefix}_dict-${dict_id}.pb"
  [[ -s "${tmp_prefix}_dict-${dict_id}.pb" ]] || { echo "ERROR: Empty response for dictionary '${dict_id}'" >&2; exit 1; }
  python3 "$DECODER" dictionary < "${tmp_prefix}_dict-${dict_id}.pb" > "${tmp_prefix}_dict-${dict_id}.json"
  printf '%s\t%s\n' "$dict_hash" "$dict_id" >> "$hash_map"
done < <(jq -r '.dictionaries[] | [.id, .hash] | @tsv' "${tmp_prefix}_search.json")

# ── 5. Join dimensions + dictionaries → builds.json ─────────
# Build jq arguments: --slurpfile dict_<id> for each dictionary
jq_args=()
jq_args+=(--argjson topBuilds "$top_builds")
jq_args+=(--arg version "$version")

dict_ids=()
while IFS= read -r dict_id; do
  dict_ids+=("$dict_id")
  jq_args+=(--slurpfile "dict_${dict_id}" "${tmp_prefix}_dict-${dict_id}.json")
done < <(jq -r '.dictionaries[].id' "${tmp_prefix}_search.json")

# Build the jq filter dynamically: create a lookup object from all dictionaries
jq_dict_init=""
for dict_id in "${dict_ids[@]}"; do
  if [[ -n "$jq_dict_init" ]]; then
    jq_dict_init="$jq_dict_init + "
  fi
  jq_dict_init="${jq_dict_init}{(\$dict_${dict_id}[0].id): \$dict_${dict_id}[0].values}"
done
[[ -n "$jq_dict_init" ]] || jq_dict_init="{}"

# Rename map: keypassives -> keystones
jq -n "${jq_args[@]}" --slurpfile search "${tmp_prefix}_search.json" "
  ($jq_dict_init) as \$dicts |
  {\"keypassives\": \"keystones\"} as \$rename |
  \$search[0].total as \$total |
  {
    total: \$total,
    snapshotVersion: \$version,
    topBuilds: \$topBuilds
  } + (
    [\$search[0].dimensions[] |
      .id as \$dim_id |
      .dictionaryId as \$dict_id |
      (\$rename[\$dim_id] // \$dim_id) as \$output_key |
      {
        key: \$output_key,
        value: [
          .counts[] |
          (\$dicts[\$dict_id][.number] // null) as \$name |
          select(\$name != null) |
          {
            name: \$name,
            count: .count,
            share: (if \$total > 0 then ((.count / \$total * 10000 | round) / 100) else 0 end)
          }
        ] | sort_by(-.count)
      }
    ] | from_entries
  )
" > "$output_dir/builds.json"

# Null-name warnings (items filtered out by select above)
null_count=$(jq -n "${jq_args[@]}" --slurpfile search "${tmp_prefix}_search.json" "
  ($jq_dict_init) as \$dicts |
  [\$search[0].dimensions[] |
    .dictionaryId as \$dict_id |
    .counts[] |
    select((\$dicts[\$dict_id][.number] // null) == null)
  ] | length
")
if [[ "$null_count" -gt 0 ]]; then
  echo "WARNING: $null_count entries with null name filtered out" >&2
fi

# ── 6. Validation ───────────────────────────────────────────
if ! jq empty "$output_dir/builds.json" 2>/dev/null; then
  echo "ERROR: Invalid JSON in builds.json" >&2
  exit 1
fi

result_total=$(jq '.total' "$output_dir/builds.json")
if [[ "$result_total" -le 0 ]]; then
  echo "ERROR: builds.json total is $result_total" >&2
  exit 1
fi

# ── 7. Source marker ────────────────────────────────────────
cat > "$output_dir/source.json" <<EOF
{
  "league": "$league",
  "gameVersion": "$gameVersion",
  "fetchedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "itemCount": $result_total
}
EOF

# ── 8. Summary ──────────────────────────────────────────────
echo "OK: $output_dir"
echo "FILES: 1"
echo "ITEMS: $result_total"
