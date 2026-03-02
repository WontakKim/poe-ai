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
    │ For each of 7 types: db/ninja/{LEAGUE}/{dir}/source.json exists?
    │ Show table: type | status | fetchedAt | items
    │ Ask user: update all / select types / skip
    │ skip → output "up to date" + STOP
    ▼
Phase 3: Ingest (up to 7 agents)
    │ Launch agents for selected types (parallel where possible)
    │ Each agent is independent — one failure does not block others
    ▼
Phase 4: Report (per-type results)
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
   ```

3. Ask user what to do:
   - **"Update all"** — ingest all 7 types
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

**Parallelism:** Launch as many agents in parallel as possible. Each agent is independent — if one fails, others continue.

Validate each agent result:
- Agent completed with `"status": "completed"` → `"success"`
- Agent failed → `"failed"`, log error

### Phase 4: Report

Produce the final result showing per-type status.

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
    "skill-gem": { "status": "success | failed | skipped", "items": 5942, "fetchedAt": "..." }
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

## Important Notes

- This skill runs interactively — confirm league and cache status with the user before proceeding
- resolve-league.sh always regenerates leagues.json fresh (no caching)
- gameVersion comes from PoB DB, linking the two databases via version key
- Currency uses a different agent (`ninja-ingest-currency`) because it needs Exchange API + Legacy API merge
- Item types all use the same agent (`ninja-ingest-item`) with different `ninjaType` parameter
