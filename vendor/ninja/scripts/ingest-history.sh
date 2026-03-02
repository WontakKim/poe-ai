#!/usr/bin/env bash
# Usage: bash vendor/ninja/scripts/ingest-history.sh <current_league> <previous_league> <data_dir> <type> <gameVersion>
# Input:  existing db/ninja/<current_league>/<type>/<type>.json + poe.ninja History API
# Output: vendor/ninja/<previous_league>/histories/<type>.json (standalone cache)
#         vendor/ninja/<previous_league>/histories/<type>.idmap.json (overview API cache)
# Stdout: OK / TOTAL / CACHED / FETCHED / NULL / DURATION
# Exit:   0 = success, 1 = error
#
# Fetches daily price history from the previous league.
# - skill-gem: fixed list of high-value gems (Awakened, Empower, Enlighten, Enhance)
#   sourced from previous league overview (no current league dependency)
# - other types: volume > 10 from current league data
# Converts daysAgo -> day (league-relative), compresses day 15+ into weekly averages.
# Results are cached per item -- subsequent runs only fetch missing items.
# Items with no API data are cached as null to prevent re-fetching.
#
# NOTE: poe.ninja history API has a ~135-day rolling window from today.
# For best coverage, run this soon after a new league starts (previous league data
# is still within the window). For leagues that ended 100+ days ago, only late-league
# data will be available.
set -euo pipefail

current_league="${1:?Usage: $0 <current_league> <previous_league> <data_dir> <type> <gameVersion>}"
previous_league="${2:?Usage: $0 <current_league> <previous_league> <data_dir> <type> <gameVersion>}"
data_dir="${3:?Usage: $0 <current_league> <previous_league> <data_dir> <type> <gameVersion>}"
type="${4:?Usage: $0 <current_league> <previous_league> <data_dir> <type> <gameVersion>}"
gameVersion="${5:?Usage: $0 <current_league> <previous_league> <data_dir> <type> <gameVersion>}"

is_currency=false
[[ "$type" == "currency" ]] && is_currency=true

ua="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

data_file="$data_dir/$type/$type.json"

# Resolve ninjaType for API calls
if [[ "$is_currency" == "true" ]]; then
  ninja_type="Currency"
elif [[ "$type" == "skill-gem" ]]; then
  ninja_type="SkillGem"
else
  ninja_type=$(jq -r '.ninjaType' "$data_dir/$type/source.json")
  [[ -n "$ninja_type" && "$ninja_type" != "null" ]] || { echo "ERROR: Cannot read ninjaType from source.json" >&2; exit 1; }
fi

# skill-gem uses previous league overview directly; others require current league data
if [[ "$type" != "skill-gem" ]]; then
  [[ -f "$data_file" ]] || { echo "ERROR: Data file not found: $data_file" >&2; exit 1; }
fi

# Cache paths
cache_dir="vendor/ninja/${previous_league}/histories"
cache_file="$cache_dir/${type}.json"
idmap_cache="$cache_dir/${type}.idmap.json"
mkdir -p "$cache_dir"

# Resolve actual league duration from Divine Orb history (cached)
duration_file="$cache_dir/duration"
if [[ -f "$duration_file" ]]; then
  league_duration=$(<"$duration_file")
else
  echo "Resolving league duration from Divine Orb history..." >&2
  divine_overview=$(curl -sL -H "User-Agent: $ua" \
    "https://poe.ninja/api/data/CurrencyOverview?league=${previous_league}&type=Currency")
  divine_id=$(printf '%s' "$divine_overview" | jq '.currencyDetails[] | select(.tradeId == "divine") | .id')
  if [[ -n "$divine_id" && "$divine_id" != "null" ]]; then
    divine_hist=$(curl -sL -H "User-Agent: $ua" \
      "https://poe.ninja/poe1/api/economy/stash/current/currency/history?league=${previous_league}&type=Currency&id=${divine_id}")
    max_days_ago=$(printf '%s' "$divine_hist" | jq '[.receiveCurrencyGraphData[].daysAgo] | max')
  fi
  if [[ -n "$max_days_ago" && "$max_days_ago" != "null" ]]; then
    league_duration=$((max_days_ago + 1))
  else
    # Fallback: weeks from leagues.json
    prev_entry=$(jq -c --arg l "$previous_league" '.[] | select(.league == $l)' vendor/ninja/leagues.json)
    league_weeks=$(echo "$prev_entry" | jq -r '.weeks')
    league_duration=$((league_weeks * 7))
    echo "WARNING: Divine Orb history unavailable, using ${league_duration} days (${league_weeks} weeks)" >&2
  fi
  echo "$league_duration" > "$duration_file"
fi
echo "League: $previous_league ($league_duration days)" >&2

TMPDIR="${TMPDIR:-/tmp}"
tmp_dir="$TMPDIR/ninja_history_$$"
mkdir -p "$tmp_dir/raw"
trap 'rm -rf "$tmp_dir"' EXIT

# -- 1. Fetch previous league overview -> build ID mapping (with cache) --
if [[ -f "$idmap_cache" ]]; then
  echo "Using cached idmap: $idmap_cache" >&2
  jq -r 'to_entries[] | "\(.key)\t\(.value)"' "$idmap_cache" > "$tmp_dir/id_map.tsv"
else
  echo "Fetching $previous_league $ninja_type overview..." >&2
  if [[ "$is_currency" == "true" ]]; then
    curl -sL -H "User-Agent: $ua" "https://poe.ninja/api/data/CurrencyOverview?league=${previous_league}&type=Currency" > "$tmp_dir/prev_overview.json"
    [[ -s "$tmp_dir/prev_overview.json" ]] || { echo "ERROR: Empty response from previous league CurrencyOverview" >&2; exit 1; }
    jq -r '.currencyDetails[] | select(.tradeId != null) | "\(.tradeId)\t\(.id)"' "$tmp_dir/prev_overview.json" > "$tmp_dir/id_map.tsv"
    jq '.currencyDetails | [.[] | select(.tradeId != null) | {key: .tradeId, value: .id}] | from_entries' "$tmp_dir/prev_overview.json" > "$idmap_cache"
  else
    curl -sL -H "User-Agent: $ua" "https://poe.ninja/api/data/ItemOverview?league=${previous_league}&type=${ninja_type}" > "$tmp_dir/prev_overview.json"
    [[ -s "$tmp_dir/prev_overview.json" ]] || { echo "ERROR: Empty response from previous league ItemOverview" >&2; exit 1; }
    jq -r '.lines[] | "\(.detailsId)\t\(.id)"' "$tmp_dir/prev_overview.json" > "$tmp_dir/id_map.tsv"
    jq '[.lines[] | {key: .detailsId, value: .id}] | from_entries' "$tmp_dir/prev_overview.json" > "$idmap_cache"
  fi
fi

map_count=$(wc -l < "$tmp_dir/id_map.tsv" | tr -d ' ')
echo "Previous league ID map: $map_count entries" >&2

# -- 2. Build fetch list -------------------------------------------------------
if [[ "$type" == "skill-gem" ]]; then
  # skill-gem: fixed high-value patterns from previous league overview
  # No dependency on current league data (works at league start)
  grep -E '^(awakened-|empower-support|enlighten-support|enhance-support)' \
    "$tmp_dir/id_map.tsv" > "$tmp_dir/fetch_list.tsv" || true
  eligible_count=$(wc -l < "$tmp_dir/fetch_list.tsv" | tr -d ' ')
  total_items=$map_count
else
  # Other types: volume > 10 from current league AND exists in previous league
  jq -r '.[] | "\(.id)\t\(.volume // 0)"' "$data_file" > "$tmp_dir/current_items.tsv"

  # Match + deduplicate (macOS awk: use ==0 instead of !)
  awk -F'\t' '
    NR==FNR { map[$1] = $2; next }
    $2+0 > 10 && ($1 in map) && seen[$1]==0 { seen[$1]=1; print $1 "\t" map[$1] }
  ' "$tmp_dir/id_map.tsv" "$tmp_dir/current_items.tsv" > "$tmp_dir/fetch_list.tsv"
  eligible_count=$(wc -l < "$tmp_dir/fetch_list.tsv" | tr -d ' ')
  total_items=$(jq length "$data_file")
fi

# -- 3. Filter out already-cached items ------------------------------------
if [[ -f "$cache_file" ]]; then
  # Extract all cached keys (including null values = already attempted)
  jq -r 'keys[]' "$cache_file" > "$tmp_dir/cached_keys.txt"

  # Remove cached items from fetch list
  awk -F'\t' '
    NR==FNR { cached[$1]=1; next }
    cached[$1]==0 { print }
  ' "$tmp_dir/cached_keys.txt" "$tmp_dir/fetch_list.tsv" > "$tmp_dir/fetch_filtered.tsv"
  mv "$tmp_dir/fetch_filtered.tsv" "$tmp_dir/fetch_list.tsv"
fi

fetch_count=$(wc -l < "$tmp_dir/fetch_list.tsv" | tr -d ' ')
cache_hit=$((eligible_count - fetch_count))
if [[ "$type" == "skill-gem" ]]; then
  echo "Items eligible: $eligible_count / $total_items (Awakened/Empower/Enlighten/Enhance)" >&2
else
  echo "Items eligible: $eligible_count / $total_items (volume > 10, in previous league)" >&2
fi
echo "Cache hit: $cache_hit, remaining to fetch: $fetch_count" >&2

# -- 4. Fetch history for each uncached item --------------------------------
fetched=0
skipped=0
errors=0

if [[ "$is_currency" == "true" ]]; then
  history_base="https://poe.ninja/poe1/api/economy/stash/current/currency/history"
  history_params="league=${previous_league}&type=Currency"
else
  history_base="https://poe.ninja/poe1/api/economy/stash/current/item/history"
  history_params="league=${previous_league}&type=${ninja_type}"
fi

# -- 4a. Parallel fetch (xargs -P 10) --
# Persistent resp dir: already-fetched responses survive script restarts
resp_dir="$cache_dir/${type}_resp"
mkdir -p "$resp_dir"

cat > "$tmp_dir/fetch_one.sh" << 'WORKER'
#!/usr/bin/env bash
# xargs -I converts tab to space on macOS; split on default IFS
read -r item_id numeric_id <<< "$1"
[[ -f "${RESP_DIR}/${item_id}.resp" ]] && exit 0
curl -sL -H "User-Agent: ${CURL_UA}" "${HIST_URL}&id=${numeric_id}" \
  > "${RESP_DIR}/${item_id}.resp" 2>/dev/null || true
WORKER
chmod +x "$tmp_dir/fetch_one.sh"

export HIST_URL="${history_base}?${history_params}"
export RESP_DIR="$resp_dir"
export CURL_UA="$ua"

if [[ "$fetch_count" -gt 0 ]]; then
  # Count already-fetched resp files
  existing_resp=$(find "$resp_dir" -name '*.resp' 2>/dev/null | wc -l | tr -d ' ')
  echo "Fetching $fetch_count items (10 parallel, $existing_resp already downloaded)..." >&2
  < "$tmp_dir/fetch_list.tsv" xargs -P 10 -I {} bash "$tmp_dir/fetch_one.sh" {}
  echo "Fetch complete, processing responses..." >&2
fi

# -- 4b. Sequential process --
for resp_file in "$resp_dir"/*.resp; do
  [[ -f "$resp_file" ]] || continue
  item_id=$(basename "$resp_file" .resp)
  resp=$(<"$resp_file")

  # Empty or invalid response -> mark as null (prevents re-fetch)
  if [[ -z "$resp" || "$resp" == "null" ]]; then
    echo "null" > "$tmp_dir/raw/${item_id}.json"
    skipped=$((skipped + 1))
    continue
  fi
  if ! printf '%s' "$resp" | jq empty 2>/dev/null; then
    rm -f "$resp_file"  # delete invalid resp so next run re-fetches
    errors=$((errors + 1))
    continue
  fi

  # Extract data array (currency wraps in receiveCurrencyGraphData)
  if [[ "$is_currency" == "true" ]]; then
    printf '%s' "$resp" | jq '.receiveCurrencyGraphData // []' > "$tmp_dir/raw/${item_id}.json"
  else
    printf '%s' "$resp" | jq 'if type == "array" then . else [] end' > "$tmp_dir/raw/${item_id}.json"
  fi

  # Check non-empty
  data_len=$(jq length "$tmp_dir/raw/${item_id}.json")
  if [[ "$data_len" -eq 0 ]]; then
    echo "null" > "$tmp_dir/raw/${item_id}.json"
    skipped=$((skipped + 1))
    continue
  fi

  fetched=$((fetched + 1))

  # Progress every 100 items
  if (( (fetched + skipped + errors) % 100 == 0 )); then
    echo "  Progress: $((fetched + skipped + errors)) / $fetch_count" >&2
  fi
done

echo "Fetched: $fetched enriched, $skipped empty, $errors errors" >&2

# -- 5. Compress new items + merge into cache --------------------------------

# Build raw map from new fetches
(
  echo "{"
  first=true
  for f in "$tmp_dir/raw/"*.json; do
    [[ -f "$f" ]] || continue
    item_id=$(basename "$f" .json)
    if [[ "$first" == "true" ]]; then
      first=false
    else
      echo ","
    fi
    printf '%s:' "$(printf '%s' "$item_id" | jq -Rs '.')"
    cat "$f"
  done
  echo "}"
) > "$tmp_dir/raw_map.json"

jq empty "$tmp_dir/raw_map.json" 2>/dev/null || { echo "ERROR: Invalid raw_map.json" >&2; exit 1; }

# Compress all entries in a single jq pass (null entries pass through)
jq --argjson leagueDuration "$league_duration" '
  def compress:
    [.[] | {day: ($leagueDuration - .daysAgo), chaosValue: .value, volume: .count}]
    | [.[] | select(.day >= 1 and .day <= $leagueDuration)]
    | sort_by(.day)
    | if length == 0 then null
      else (
        [.[] | select(.day <= 14) | {day, chaosValue, volume}]
        +
        ([.[] | select(.day > 14) | . + {week: (((.day - 1) / 7 | floor) + 1)}]
         | group_by(.week)
         | [.[] | {
             week: .[0].week,
             chaosValue: ([.[].chaosValue] | add / length | . * 100 | round / 100),
             volume: ([.[].volume] | add / length | round),
             dataPoints: length
           }]
        )
      ) end;

  with_entries(
    if .value == null then .
    else .value |= compress
    end
  )
' "$tmp_dir/raw_map.json" > "$tmp_dir/new_entries.json"

# Load existing cache (or start empty)
if [[ -f "$cache_file" ]]; then
  cp "$cache_file" "$tmp_dir/existing_cache.json"
else
  echo '{}' > "$tmp_dir/existing_cache.json"
fi

# Merge: existing + new (new overwrites for same keys)
jq -s '.[0] * .[1]' "$tmp_dir/existing_cache.json" "$tmp_dir/new_entries.json" > "$tmp_dir/merged_cache.json"

# -- 6. Validate + save -----------------------------------------------------
if ! jq empty "$tmp_dir/merged_cache.json" 2>/dev/null; then
  echo "ERROR: Invalid merged cache JSON" >&2
  exit 1
fi

mv "$tmp_dir/merged_cache.json" "$cache_file"

# Keep resp dir for reuse (raw API responses persist across runs)

# -- 7. Summary --------------------------------------------------------------
cache_total=$(jq 'length' "$cache_file")
null_count=$(jq '[to_entries[] | select(.value == null)] | length' "$cache_file")

echo "OK: $cache_file"
echo "TOTAL: $cache_total"
echo "CACHED: $cache_hit"
echo "FETCHED: $fetched"
echo "NULL: $null_count"
echo "DURATION: ${league_duration}"
