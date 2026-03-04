---
name: sync-ninja-rag
description: Sync poe.ninja market data into the ninja DB. Use when updating currency prices or rebuilding the market database.
---

# Sync Ninja RAG — Market Data Ingest

You are the poe.ninja market data pipeline orchestrator. You resolve the current league, fetch market prices, and ingest them into the ninja database.

## Invocation

```
/sync-ninja-rag [league]
```

Optional `league` parameter overrides auto-detection (e.g., `/sync-ninja-rag Keepers`).

## Grounding Rules

- NEVER modify files outside `db/ninja/` and `vendor/ninja/`
- NEVER run ingest scripts directly — MUST use the Agent tool to delegate (context isolation)
- NEVER retry a failed sub-agent — log the error and report
- Always show cache status to user before proceeding
- Follow the phase order strictly — do NOT skip phases or reorder them

## Target Types

| ninjaType | Directory | Agent |
|-----------|-----------|-------|
| Currency | `currency` | `ninja-ingest-currency` |
| UniqueWeapon | `unique-weapon` | `ninja-ingest-item` |
| UniqueArmour | `unique-armour` | `ninja-ingest-item` |
| UniqueAccessory | `unique-accessory` | `ninja-ingest-item` |
| UniqueFlask | `unique-flask` | `ninja-ingest-item` |
| UniqueJewel | `unique-jewel` | `ninja-ingest-item` |
| SkillGem | `skill-gem` | `ninja-ingest-item` |
| Builds | `builds` | `ninja-ingest-build` |

## Execution Flow

```
Phase 1: Resolve League + Version
    │ 1. resolve-league.sh → leagues.json (always fresh)
    │ 2a. No [league] param → PoB DB source.json → gameVersion → leagues.json → league
    │ 2b. [league] param given → reverse-lookup gameVersion from leagues.json
    │ 3. Confirm with user
    │ fail → STOP (fatal)
    ▼
Phase 2: Check Cache (per-type)
    │ For each of 8 types: db/ninja/{LEAGUE}/{dir}/source.json exists?
    │ Show table: type | status | fetchedAt | items
    │ Ask user: update all / select types / skip
    │ skip → output "up to date" + STOP
    ▼
Phase 3: Ingest (up to 8 agents)
    │ Launch agents for selected types (parallel where possible)
    │ Each agent is independent — one failure does not block others
    ▼
Phase 4: Report (per-type results)
    │
    ▼
Phase 5: History Enrichment (optional)
    │ Ask user: "Enrich with {PREVIOUS_LEAGUE} price history?"
    │ No → STOP
    │ Yes → auto-detect previous league from leagues.json
    │ Launch 7 history agents (parallel)
    │ Report per-type enrichment results
```

## Workflow

### Phase 1: Resolve League and Version

1. Run resolve-league.sh to generate leagues.json:
   ```bash
   bash vendor/ninja/scripts/resolve-league.sh vendor/ninja/leagues.json
   ```
   If it fails → output `{"status": "failed", "error": "Cannot resolve leagues from poedb"}` and stop.

2. **Branch A — no `[league]` parameter (auto-detect):**

   a. Read `db/pob/base-item/source.json` to get the current `gameVersion`:
      ```bash
      GAME_VERSION=$(jq -r '.gameVersion' db/pob/base-item/source.json)
      ```
      If file missing or version empty → output `{"status": "failed", "error": "PoB DB not found — run /sync-pob-rag first"}` and stop.

   b. Look up league name from leagues.json:
      ```bash
      LEAGUE=$(jq -r --arg v "$GAME_VERSION" '.[] | select(.version == $v) | .league' vendor/ninja/leagues.json)
      ```
      If no match → output `{"status": "failed", "error": "No league found for version {GAME_VERSION}"}` and stop.

   c. Confirm with user: **"{LEAGUE} ({GAME_VERSION}) league market data. Proceed?"**

3. **Branch B — `[league]` parameter given (manual override):**

   a. Set `LEAGUE` to the user-provided value.

   b. Reverse-lookup gameVersion from leagues.json:
      ```bash
      GAME_VERSION=$(jq -r --arg l "$LEAGUE" '.[] | select(.league == $l) | .version' vendor/ninja/leagues.json)
      ```
      If no match → output `{"status": "failed", "error": "Unknown league: {LEAGUE}"}` and stop.

   c. Confirm with user: **"{LEAGUE} ({GAME_VERSION}) league market data. Proceed?"**

### Phase 2: Check Cache (Per-Type)

1. For each type in the Target Types table, check if `db/ninja/{LEAGUE}/{dir}/source.json` exists.

2. Build a status table and show to user:

   ```
   Type             | Status    | Last Updated           | Items
   -----------------+-----------+------------------------+------
   currency         | cached    | 2026-03-02T14:30:00Z   | 115
   unique-weapon    | no data   | -                      | -
   unique-armour    | no data   | -                      | -
   unique-accessory | no data   | -                      | -
   unique-flask     | no data   | -                      | -
   unique-jewel     | no data   | -                      | -
   skill-gem        | no data   | -                      | -
   builds           | no data   | -                      | -
   ```

3. Ask user what to do:
   - **"Update all"** — ingest all 8 types
   - **"Update missing only"** — ingest only types with "no data" status
   - **"Skip"** — output "up to date" and stop
   - User can also specify individual types to update

### Phase 3: Ingest

Launch agents for selected types. Use the Agent tool for each type:

**For Currency:**

| `subagent_type` | Output |
|-----------------|--------|
| `ninja-ingest-currency` | `db/ninja/{LEAGUE}/currency/*.json` |

Agent `prompt`:
```
INPUT:
- league: {LEAGUE}
- output_dir: db/ninja/{LEAGUE}/currency
- gameVersion: {GAME_VERSION}

Execute the workflow.
```

**For Item Types (UniqueWeapon, UniqueArmour, UniqueAccessory, UniqueFlask, UniqueJewel, SkillGem):**

| `subagent_type` | Output |
|-----------------|--------|
| `ninja-ingest-item` | `db/ninja/{LEAGUE}/{dir}/*.json` |

Agent `prompt`:
```
INPUT:
- league: {LEAGUE}
- output_dir: db/ninja/{LEAGUE}/{dir}
- gameVersion: {GAME_VERSION}
- ninjaType: {ninjaType}

Execute the workflow.
```

**For Builds:**

| `subagent_type` | Output |
|-----------------|--------|
| `ninja-ingest-build` | `db/ninja/{LEAGUE}/builds/*.json` |

Agent `prompt`:
```
INPUT:
- league: {LEAGUE}
- output_dir: db/ninja/{LEAGUE}/builds
- gameVersion: {GAME_VERSION}

Execute the workflow.
```

**Parallelism:** Launch as many agents in parallel as possible. Each agent is independent — if one fails, others continue.

Validate each agent result:
- Agent completed with `"status": "completed"` → `"success"`
- Agent failed → `"failed"`, log error

### Phase 4: Report

Produce the final result showing per-type status.

### Phase 4.5: Builds Reference Generation

If the builds ingest succeeded in Phase 3, generate the builds reference file:

```bash
bash vendor/ninja/scripts/builds-reference.sh \
  db/ninja/{LEAGUE}/builds/builds.json \
  vendor/ninja/references/builds.md
```

If builds ingest failed or was skipped, skip this step.

### Phase 5: History Enrichment (Optional)

After Phase 4 report, offer to enrich data with previous league price history.

1. **Detect previous league** from leagues.json:
   ```bash
   PREV_LEAGUE=$(jq -r --arg v "$GAME_VERSION" '
     [.[].version] as $versions |
     ($versions | to_entries | .[] | select(.value == $v) | .key) as $idx |
     if $idx + 1 < ($versions | length) then .[$idx + 1].league else null end
   ' vendor/ninja/leagues.json)
   ```
   If no previous league found → skip Phase 5 (first league in list).

2. **Ask user:** "Enrich with **{PREV_LEAGUE}** ({PREV_VERSION}) price history? (cached in `vendor/ninja/{PREV_LEAGUE}/histories/`, fast on 2nd run)"
   - **Yes** → proceed
   - **No** → skip, output report from Phase 4

3. **Launch 7 history agents** in parallel. For each type:

   | `subagent_type` | Timeout |
   |-----------------|---------|
   | `ninja-ingest-history` | 600s (10 min) |

   Agent `prompt`:
   ```
   INPUT:
   - current_league: {LEAGUE}
   - previous_league: {PREV_LEAGUE}
   - data_dir: db/ninja/{LEAGUE}
   - type: {dir}
   - gameVersion: {GAME_VERSION}

   Execute the workflow. Note: this script takes several minutes due to rate-limited API calls (200ms per item).
   ```

4. **Report enrichment results:**
   ```
   Type             | Total | Cached | Fetched | Null
   -----------------+-------+--------+---------+-----
   currency         | 100   | 95     | 5       | 15
   unique-weapon    | 500   | 490    | 10      | 50
   unique-armour    | 600   | 600    | 0       | 80
   unique-accessory | 250   | 250    | 0       | 30
   unique-flask     | 35    | 35     | 0       | 5
   unique-jewel     | 100   | 100    | 0       | 10
   skill-gem        | 1500  | 1500   | 0       | 200
   ```

## Required Output Format

**When up to date (user chose to skip):**
```json
{
  "status": "up to date",
  "league": "Keepers",
  "gameVersion": "3.27"
}
```

**When ingest executed:**
```json
{
  "status": "success | partial | failed",
  "league": "Keepers",
  "gameVersion": "3.27",
  "types": {
    "currency": { "status": "success | failed | skipped", "items": 115, "fetchedAt": "..." },
    "unique-weapon": { "status": "success | failed | skipped", "items": 636, "fetchedAt": "..." },
    "unique-armour": { "status": "success | failed | skipped", "items": 851, "fetchedAt": "..." },
    "unique-accessory": { "status": "success | failed | skipped", "items": 309, "fetchedAt": "..." },
    "unique-flask": { "status": "success | failed | skipped", "items": 38, "fetchedAt": "..." },
    "unique-jewel": { "status": "success | failed | skipped", "items": 125, "fetchedAt": "..." },
    "skill-gem": { "status": "success | failed | skipped", "items": 5942, "fetchedAt": "..." },
    "builds": { "status": "success | failed | skipped", "items": 124512, "fetchedAt": "..." }
  },
  "history": {
    "previousLeague": "Mercenaries",
    "status": "success | partial | failed | skipped",
    "types": {
      "currency": { "total": 100, "cached": 95, "fetched": 5, "null": 15 },
      "unique-weapon": { "total": 500, "cached": 490, "fetched": 10, "null": 50 }
    }
  },
  "error": null
}
```

- `"success"` — all selected types succeeded
- `"partial"` — some succeeded, some failed
- `"failed"` — all selected types failed

## Error Handling

| Error | Behavior |
|-------|----------|
| resolve-league.sh fails | **Blocking.** Stop with error. |
| PoB DB source.json missing (auto-detect) | **Blocking.** Stop — user must run /sync-pob-rag first. |
| No league match for version (auto-detect) | **Blocking.** Stop with error. |
| Unknown league name (manual override) | **Blocking.** Stop with error. |
| Individual ingest agent fails | Report failure for that type, continue others. |
| No previous league found | Skip Phase 5 (not an error). |
| History agent fails | Report failure for that type, continue others. |

## Important Notes

- This skill runs interactively — confirm league and cache status with the user before proceeding
- resolve-league.sh always regenerates leagues.json fresh (no caching)
- gameVersion comes from PoB DB, linking the two databases via version key
- Currency uses a different agent (`ninja-ingest-currency`) because it needs Exchange API + Legacy API merge
- Item types all use the same agent (`ninja-ingest-item`) with different `ninjaType` parameter
- Builds uses a dedicated agent (`ninja-ingest-build`) like currency — no ninjaType parameter
- Builds reference is auto-generated after successful builds ingest (Phase 4.5)
- History enrichment is optional and only offered after successful ingest (does NOT apply to builds)
- History agents have long timeouts (600s) due to rate-limited API calls (200ms per item)
- History is cached in `vendor/ninja/{prev_league}/histories/` — second run skips already-fetched items
