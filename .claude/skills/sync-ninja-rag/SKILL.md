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

## Execution Flow

```
Phase 1: Resolve League + Version
    │ 1. resolve-league.sh → leagues.json (always fresh)
    │ 2a. No [league] param → PoB DB source.json → gameVersion → leagues.json → league
    │ 2b. [league] param given → reverse-lookup gameVersion from leagues.json
    │ 3. Confirm with user
    │ fail → STOP (fatal)
    ▼
Phase 2: Check Cache
    │ db/ninja/{league}/currency/source.json exists?
    │ no  → "No data found, starting ingest"
    │ yes → Show fetchedAt + elapsed time, ask update/skip
    │ skip → output "up to date" + STOP
    ▼
Phase 3: Ingest (1 agent)
    ▼
Phase 4: Report
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

### Phase 2: Check Cache

1. Check if `db/ninja/{LEAGUE}/currency/source.json` exists.

2. If it exists:
   - Read `fetchedAt` timestamp
   - Calculate elapsed time since last fetch
   - Show to user: **"Last updated: {fetchedAt} ({elapsed} ago). Update or keep?"**
   - If user chooses to keep → output `{"status": "up to date", ...}` and stop

3. If it does not exist:
   - Inform user: **"No existing data. Starting ingest."**

### Phase 3: Ingest Currency

Launch **1 agent** via the Agent tool:

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

Validate agent result:
- Agent completed with `"status": "completed"` → `"success"`
- Agent failed → `"failed"`, log error

### Phase 4: Report

Produce the final result.

## Required Output Format

**When up to date (user chose to keep):**
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
  "status": "success | failed",
  "league": "Keepers",
  "gameVersion": "3.27",
  "currency": {
    "status": "success | failed",
    "items": 115,
    "fetchedAt": "2026-03-02T14:30:00Z"
  },
  "error": null
}
```

## Error Handling

| Error | Behavior |
|-------|----------|
| resolve-league.sh fails | **Blocking.** Stop with error. |
| PoB DB source.json missing (auto-detect) | **Blocking.** Stop — user must run /sync-pob-rag first. |
| No league match for version (auto-detect) | **Blocking.** Stop with error. |
| Unknown league name (manual override) | **Blocking.** Stop with error. |
| Ingest agent fails | Report failure in result JSON. |

## Important Notes

- This skill runs interactively — confirm league and cache status with the user before proceeding
- resolve-league.sh always regenerates leagues.json fresh (no caching)
- gameVersion comes from PoB DB, linking the two databases via version key
- Only currency type is supported currently — more types will be added later
