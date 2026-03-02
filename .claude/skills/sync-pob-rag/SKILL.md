---
name: sync-pob-rag
description: Sync PoB references and ingest equipment DB in a single pipeline. Use when updating game version data or rebuilding the RAG database.
---

# Sync PoB RAG — Reference Sync + DB Ingest

You are the PoB RAG pipeline orchestrator. You pull the latest PathOfBuilding submodule, regenerate reference files, and ingest the equipment database — all in one invocation.

## Invocation

```
/sync-pob-rag
```

No manual input required. Auto-detects version and skips phases that are already up to date.

## Grounding Rules

- NEVER modify files outside `vendor/pob/` and `db/pob/`
- NEVER run scripts directly — MUST use the Agent tool to delegate to sub-agents (context isolation)
- NEVER retry a failed sub-agent — log the error and continue
- Every sub-agent result MUST be validated before recording its status
- Follow the phase order strictly — do NOT skip phases or reorder them

## Execution Flow

```
Phase 1: Pull Latest PoB
    │ fail → STOP (fatal)
    ▼
Phase 2: Detect Version + Dual Source Check
    │ both up to date → report + STOP
    │ fail → STOP (fatal)
    ▼
Phase 3: Sync References (4 agents parallel)   ← skip if ref up to date
    │ individual fail → log, continue
    ▼
Phase 4: Write vendor/pob/source.json          ← skip if ref skipped or partial fail
    ▼
Phase 5: Ingest Equipment DB (sequential)      ← skip if DB up to date
    │ base-item first, then unique-item
    ▼
Phase 6: Report
    ▼
Output Result JSON
```

**Blocking failures** (stop entire process):
- Phase 1: submodule init/update fails
- Phase 2: version detection fails

**Non-blocking failures** (log and continue):
- Phase 3: individual reference sync agent fails
- Phase 5: individual ingest agent fails (but unique-item depends on base-item)

## Workflow

### Phase 1: Pull Latest PoB

Ensure the PathOfBuilding submodule is initialized and updated to the latest remote commit.

1. Initialize submodule if not present:
   ```bash
   POB_PATH="vendor/pob/origin"
   if [ ! -d "$POB_PATH/src/Data" ]; then
     git submodule update --init --depth 1 vendor/pob/origin
   fi
   ```
2. Pull latest:
   ```bash
   git submodule update --remote vendor/pob/origin
   ```
3. If either command fails → output `{"status": "failed", "error": "Cannot initialize PoB submodule"}` and stop.

### Phase 2: Detect Version and Check Sync Status

Determine the current game version, PoB commit hash, and which phases need to run.

1. Extract game version from `GameVersions.lua`:
   ```bash
   VERSION=$(sed -n '/^treeVersionList/,/}/p' "$POB_PATH/src/GameVersions.lua" \
     | grep -oE '"[0-9]+_[0-9]+"' | tail -1 | tr -d '"' | tr '_' '.')
   ```
   - If VERSION is empty → output `{"status": "failed", "error": "Cannot detect version from PoB"}` and stop.

2. Get current PoB commit and version tag:
   ```bash
   POB_COMMIT=$(git -C "$POB_PATH" rev-parse HEAD)
   POB_VERSION=$(git -C "$POB_PATH" describe --tags --abbrev=0 2>/dev/null || echo "unknown")
   ```

3. **Check ref sync status** (`vendor/pob/source.json`):
   ```bash
   REF_SOURCE="vendor/pob/source.json"
   REF_UP_TO_DATE=false
   if [ -f "$REF_SOURCE" ]; then
     PREV_REF_COMMIT=$(jq -r '.pobCommit' "$REF_SOURCE")
     if [ "$PREV_REF_COMMIT" = "$POB_COMMIT" ]; then
       REF_UP_TO_DATE=true
     fi
   fi
   ```

4. **Check DB ingest status** (both `db/pob/base-item/source.json` AND `db/pob/unique-item/source.json`):
   ```bash
   DB_UP_TO_DATE=true
   for db_source in db/pob/base-item/source.json db/pob/unique-item/source.json; do
     if [ ! -f "$db_source" ]; then
       DB_UP_TO_DATE=false
       break
     fi
     PREV_DB_COMMIT=$(jq -r '.pobCommit' "$db_source")
     if [ "$PREV_DB_COMMIT" != "$POB_COMMIT" ]; then
       DB_UP_TO_DATE=false
       break
     fi
   done
   ```

5. Determine action:
   - Both up to date → output `{"status": "up to date", ...}` and stop
   - Ref needs update → run Phase 3-4, then check DB
   - DB needs update → run Phase 5
   - Both need update → run Phase 3-4-5

6. Print sync status and proceed:
   ```
   VERSION=3.27, POB_COMMIT=fb6cd055, POB_VERSION=v2.60.0
   Ref: up to date | needs sync
   DB:  up to date | needs ingest
   ```

### Phase 3: Sync References (4 Agents in Parallel)

**Skip this phase if `REF_UP_TO_DATE=true`.**

Regenerate `vendor/pob/references/*.md` from PoB source.

```
Orchestrator ──┬─ Agent (haiku) → references/base-item.md
               ├─ Agent (haiku) → references/unique-item.md
               ├─ Agent (haiku) → references/skill-gem.md
               └─ Agent (haiku) → references/passive-tree.md
```

1. Launch **exactly 4** agents **in parallel** (single message, 4 Agent tool calls). Verify all 4 are present before sending.

   | # | `subagent_type` | Output |
   |---|-----------------|--------|
   | 1 | `pob-sync-base-item` | `references/base-item.md` |
   | 2 | `pob-sync-unique-item` | `references/unique-item.md` |
   | 3 | `pob-sync-skill-gem` | `references/skill-gem.md` |
   | 4 | `pob-sync-passive-tree` | `references/passive-tree.md` |

   Each agent `prompt`:
   ```
   INPUT:
   - pob_path: vendor/pob/origin
   - gameVersion: {VERSION}
   - pobCommit: {POB_COMMIT (short)}
   - pobVersion: {POB_VERSION}

   Execute the workflow.
   ```

2. Validate results per agent:
   - Agent completed and wrote its reference file → `"success"`
   - Agent failed → `"failed"`, log error
   - Each agent is independent — one failure does NOT block the others

### Phase 4: Write vendor/pob/source.json

**Skip if Phase 3 was skipped (ref already up to date).**

Write sync marker **only if all 4 agents succeeded**. If any agent failed, do NOT write — this ensures the next run retries.

```json
// vendor/pob/source.json
{
  "gameVersion": "{VERSION}",
  "pobCommit": "{POB_COMMIT}",
  "pobVersion": "{POB_VERSION}",
  "builtAt": "{ISO 8601 timestamp}"
}
```

### Phase 5: Ingest Equipment DB

**Skip this phase if `DB_UP_TO_DATE=true`.**

Run ingest agents **sequentially** via the Agent tool (unique-item depends on base-item output). Do NOT run scripts directly — raw stdout pollutes the orchestrator context and degrades downstream quality.

```
Orchestrator ── Agent (haiku) → db/pob/base-item/*.json
                    │ success
                    ▼
               Agent (haiku) → db/pob/unique-item/*.json
```

**Important**: Use the `VERSION`, `POB_COMMIT`, `POB_VERSION` variables from Phase 2 directly. Do NOT re-read `vendor/pob/source.json` — it may not exist if Phase 3-4 were skipped or failed.

1. **Base item ingest** — launch 1 agent via the Agent tool (MUST use `subagent_type`, not Bash):

   | `subagent_type` | Output |
   |-----------------|--------|
   | `pob-ingest-base-item` | `db/pob/base-item/*.json` |

   Agent `prompt`:
   ```
   INPUT:
   - pob_path: vendor/pob/origin
   - output_dir: db/pob/base-item
   - gameVersion: {VERSION}
   - pobCommit: {POB_COMMIT}
   - pobVersion: {POB_VERSION}

   Execute the workflow.
   ```

2. Validate base-item result:
   - If failed → log error, skip unique-item ingest, proceed to Phase 6

3. **Unique item ingest** — launch 1 agent via the Agent tool (only if base-item succeeded):

   | `subagent_type` | Output |
   |-----------------|--------|
   | `pob-ingest-unique-item` | `db/pob/unique-item/*.json` |

   Agent `prompt`:
   ```
   INPUT:
   - pob_path: vendor/pob/origin
   - output_dir: db/pob/unique-item
   - base_dir: db/pob/base-item
   - gameVersion: {VERSION}
   - pobCommit: {POB_COMMIT}
   - pobVersion: {POB_VERSION}

   Execute the workflow.
   ```

4. Validate unique-item result.

### Phase 6: Report

Produce the final result summarizing all phases.

1. Determine final status:
   - All executed phases succeeded → `"success"`
   - Some phases succeeded, some failed → `"partial"`
   - All executed phases failed → `"failed"`

## Required Output Format

**When fully up to date (no work needed):**
```json
{
  "status": "up to date",
  "version": "3.27",
  "pobCommit": "fb6cd055...",
  "pobVersion": "v2.60.0"
}
```

**When work executed:**
```json
{
  "status": "success | partial | failed",
  "version": "3.27",
  "pobCommit": "fb6cd055...",
  "pobVersion": "v2.60.0",
  "references": {
    "skipped": false,
    "base_item": "success | failed",
    "unique_item": "success | failed",
    "skill_gem": "success | failed",
    "passive_tree": "success | failed",
    "source_json_written": true
  },
  "ingest": {
    "skipped": false,
    "base_item": "success | failed",
    "unique_item": "success | failed | skipped"
  },
  "error": null
}
```

**When one pipeline skipped:**
```json
{
  "status": "success",
  "version": "3.27",
  "pobCommit": "fb6cd055...",
  "pobVersion": "v2.60.0",
  "references": {
    "skipped": true
  },
  "ingest": {
    "skipped": false,
    "base_item": "success",
    "unique_item": "success"
  },
  "error": null
}
```

## Error Handling

| Error | Behavior |
|-------|----------|
| PoB submodule init/update fails | **Blocking.** Output: `{"status": "failed", "error": "Cannot initialize PoB submodule"}` |
| GameVersions.lua not found or VERSION empty | **Blocking.** Output: `{"status": "failed", "error": "Cannot detect version from PoB"}` |
| Both ref and DB already synced (same commit) | Output: `{"status": "up to date", ...}` and stop |
| Any reference sync agent fails | **Non-blocking.** Log error per agent, continue. Do NOT write vendor/pob/source.json. |
| Base-item ingest fails | **Non-blocking.** Log error, skip unique-item ingest, proceed to Phase 6. |
| Unique-item ingest fails | **Non-blocking.** Log error, proceed to Phase 6. |

## Important Notes

- This skill runs interactively — confirm sync status with the user in Phase 2 before proceeding
- vendor/pob/source.json is the ref sync marker: only written when all 4 ref agents succeed
- db/pob/{type}/source.json is written by each ingest script automatically
- Dual source.json check ensures partial failures are retried: if base-item succeeded but unique-item failed, the next run re-ingests both
- Phase 5 uses Phase 2 variables directly — never re-reads vendor/pob/source.json
- Sequential script execution only — no background `&` jobs (sandbox limitation)
- Always output the final JSON regardless of success or failure
