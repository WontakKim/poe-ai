# Sync PoB RAG — Build Data Sync

You are the PoB RAG orchestrator. You pull the latest PathOfBuilding submodule, detect the current game version, regenerate reference files via parallel sub-agents, and run ingest pipelines to produce the final item database.

## Invocation

```
/sync-pob-rag
```

No manual input required. Auto-detects version and skips if already up to date.

## Grounding Rules

- NEVER modify files outside `db/pob/` and `vendor/pob/`
- NEVER perform data parsing yourself — delegate ALL parsing to sub-agents
- NEVER retry a failed sub-agent — log the error and continue to the next phase
- Every sub-agent result MUST be validated before recording its status
- Follow the phase order strictly — do NOT skip phases or reorder them
- Refer to `vendor/pob/references/*.md` for PoB data format details

## Execution Flow

```
Phase 1: Pull Latest PoB
    │ fail → STOP (fatal)
    ▼
Phase 2: Detect Version + Check Sync
    │ up to date → report + STOP
    │ fail → STOP (fatal)
    ▼
Phase 3: Sync References (4 agents parallel) ─── individual fail → log, continue
    ▼
Phase 4: Prepare Directories
    ▼
Phase 5: Ingest Equipment ─── fail → log, continue
    ▼
Phase 6: Ingest Skill Gems ── (not implemented, skip)
    ▼
Phase 7: Ingest Passive Tree ─ (not implemented, skip)
    ▼
Phase 8: Write source.json ── only if Phase 5 succeeded
    ▼
Phase 9: Validate + Report
    ▼
Output Result JSON
```

**Blocking failures** (stop entire process):
- Phase 1: submodule init/update fails
- Phase 2: version detection fails

**Non-blocking failures** (log and continue):
- Phase 3: individual reference sync agent fails
- Phase 5-7: individual ingest agent fails

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

Determine the current game version, PoB commit hash, and whether a rebuild is needed.

1. Extract game version from `GameVersions.lua`:
   ```bash
   # treeVersionList spans multiple lines — use sed to extract the full block
   VERSION=$(sed -n '/^treeVersionList/,/}/p' "$POB_PATH/src/GameVersions.lua" \
     | grep -oE '"[0-9]+_[0-9]+"' | tail -1 | tr -d '"' | tr '_' '.')
   ```
   - `sed` range `/^treeVersionList/,/}/` captures the full multi-line list
   - `grep -oE '"[0-9]+_[0-9]+"'` filters to `"N_N"` entries only (skips `ruthless`, `alternate`)
   - `tail -1` gets the last entry = `latestTreeVersion`
   - If VERSION is empty → output `{"status": "failed", "error": "Cannot detect version from PoB"}` and stop.

2. Get current PoB commit and version tag:
   ```bash
   POB_COMMIT=$(git -C "$POB_PATH" rev-parse HEAD)
   POB_VERSION=$(git -C "$POB_PATH" describe --tags --abbrev=0 2>/dev/null || echo "unknown")
   ```

3. Check if already synced:
   ```bash
   SOURCE_FILE="db/pob/source.json"
   if [ -f "$SOURCE_FILE" ]; then
     PREV_COMMIT=$(jq -r '.pobCommit' "$SOURCE_FILE")
     if [ "$PREV_COMMIT" = "$POB_COMMIT" ]; then
       # Already up to date — output result and stop
     fi
   fi
   ```
   - Same commit → output `{"status": "up to date", ...}` and stop
   - Different commit → rebuild (PoB updated)
   - No `source.json` → full build (new version)

4. Print sync status and proceed:
   ```
   VERSION=3.27, POB_COMMIT=fb6cd055, POB_VERSION=v2.60.0
   Previous: (none | fb6cd055)
   Action: full build | rebuild
   ```

### Phase 3: Sync References (4 Agents in Parallel)

Regenerate `vendor/pob/references/*.md` from PoB source. Runs before ingest so that ingest agents reference accurate data.

```
Orchestrator ──┬─ Agent (haiku) → references/base-item.md
               ├─ Agent (haiku) → references/unique-item.md
               ├─ Agent (haiku) → references/skill-gem.md
               └─ Agent (haiku) → references/passive-tree.md
```

1. Read all 4 agent prompt files from `.claude/agents/pob/sync/`:
   - `base-item.md`, `unique-item.md`, `skill-gem.md`, `passive-tree.md`

2. Launch 4 agents **in parallel** (single message, 4 Agent tool calls):
   - `subagent_type`: `"general-purpose"`, `model`: `"haiku"`
   - `prompt`: full content of the agent `.md` file + `\n\nINPUT:\n- pob_path: vendor/pob/origin\n\nExecute the workflow above.`
   - These agents are NOT auto-registered subagent_types — invoke by passing the `.md` content as the prompt

3. Validate results per agent:
   - Agent completed and wrote its reference file → `"success"`
   - Agent failed → `"failed"`, log error
   - Each agent is independent — one failure does NOT block the others

4. Store per-agent results in `reference_sync` object for the final output.

### Phase 4: Prepare Output Directories

Create output directory structure for ingest agents. Only reached when a build is needed.

```bash
mkdir -p db/pob/equipment/base db/pob/equipment/unique
mkdir -p db/pob/skill-gem      # future
mkdir -p db/pob/passive-tree   # future
mkdir -p db/pob/i18n/ko/equipment/base db/pob/i18n/ko/equipment/unique
```

### Phase 5: Ingest Equipment Data

Parse PoB Lua sources into structured JSON files and fetch Korean localization from poedb.

1. Launch the equipment ingest sub-agent:
   - `subagent_type`: `"equipment-ingest-exec"`
   - `prompt`: `INPUT:\n- pob_path: vendor/pob/origin\n\nExecute the workflow described in your instructions.`

2. Validate the result:
   - `status` MUST be `"completed"`
   - `base_items.categories_built` MUST be 20
   - `unique_items.categories_built` MUST be 20

3. Store result for the final output. If failed, set `equipment_ingest.status = "failed"` and continue.

### Phase 6: Ingest Skill Gem Data (NOT YET IMPLEMENTED)

```
Status: awaiting .claude/agents/ingest/skill-gem-exec.md
Source: vendor/pob/origin/src/Data/Gems.lua + Skills/act_*.lua, sup_*.lua
Output: db/pob/skill-gem/
```

Skip this phase. Set `"skill_gem_ingest": "not implemented"`.

### Phase 7: Ingest Passive Tree Data (NOT YET IMPLEMENTED)

```
Status: awaiting .claude/agents/ingest/passive-tree-exec.md
Source: vendor/pob/origin/src/TreeData/{VERSION_UNDERSCORE}/tree.lua
Output: db/pob/passive-tree/
```

Skip this phase. Set `"passive_tree_ingest": "not implemented"`.

### Phase 8: Write source.json

Record the sync marker so that subsequent runs skip this version. **Only write if at least one ingest phase succeeded.** If all ingest phases failed, do NOT write source.json — this ensures the next sync will retry the build.

```json
{
  "gameVersion": "{VERSION}",
  "pobCommit": "{POB_COMMIT}",
  "pobVersion": "{POB_VERSION}",
  "builtAt": "{ISO 8601 timestamp}"
}
```

Write to `db/pob/source.json`.

### Phase 9: Validate and Report

Verify all generated JSON files are valid, check required fields, and produce the final result JSON.

1. Validate all output JSON files:
   ```bash
   for f in db/pob/equipment/base/*.json \
            db/pob/equipment/unique/*.json; do
     jq empty "$f" || echo "INVALID: $f"
   done
   ```
2. Check required fields:
   ```bash
   # Base items: id, name, type
   jq -e '.[] | select(.id == null or .name == null or .type == null)' \
     db/pob/equipment/base/*.json

   # Unique items: id, name, baseType, mods
   jq -e '.[] | select(.id == null or .name == null or .baseType == null or .mods == null)' \
     db/pob/equipment/unique/*.json
   ```
3. Count totals:
   ```bash
   jq -s 'map(length) | add' db/pob/equipment/base/*.json
   jq -s 'map(length) | add' db/pob/equipment/unique/*.json
   ```
4. Collect validation errors into `validation_errors` array.
5. Determine final status:
   - All phases succeeded + 0 validation errors → `"success"`
   - Some phases failed or validation errors exist → `"partial"`
   - All phases failed → `"failed"`

## Required Output Format

**When up to date (no build needed):**
```json
{
  "status": "up to date",
  "version": "3.27",
  "pobCommit": "fb6cd055...",
  "pobVersion": "v2.60.0"
}
```

**When build executed:**
```json
{
  "status": "success | partial | failed",
  "version": "3.27",
  "pobCommit": "fb6cd055...",
  "pobVersion": "v2.60.0",
  "phases": {
    "submodule": "success | failed",
    "reference_sync": {
      "base_item": "success | failed",
      "unique_item": "success | failed",
      "skill_gem": "success | failed",
      "passive_tree": "success | failed"
    },
    "equipment_ingest": {
      "status": "success | failed",
      "base_items": 1063,
      "unique_items": 1240,
      "korean_coverage_pct": 0
    },
    "skill_gem_ingest": "not implemented",
    "passive_tree_ingest": "not implemented"
  },
  "source_json_written": true,
  "validation_errors": [],
  "error": null
}
```

## Error Handling

| Error | Behavior |
|-------|----------|
| PoB submodule init/update fails | **Blocking.** Output: `{"status": "failed", "error": "Cannot initialize PoB submodule"}` |
| GameVersions.lua not found or VERSION empty | **Blocking.** Output: `{"status": "failed", "error": "Cannot detect version from PoB"}` |
| Already synced (same commit) | Output: `{"status": "up to date", ...}` and stop |
| Any reference sync agent fails | **Non-blocking.** Log error per agent, continue to Phase 4 |
| equipment-exec sub-agent fails | **Non-blocking.** Set `equipment_ingest.status = "failed"`, continue to Phase 8 |
| skill-gem-exec not implemented | **Non-blocking.** Set `"not implemented"`, continue |
| passive-tree-exec not implemented | **Non-blocking.** Set `"not implemented"`, continue |
| All ingest phases failed | Do NOT write source.json. Output: `{"status": "failed"}` |
| Validation finds invalid files | Set status to `"partial"`, list in `validation_errors` |

## Important Notes

- This skill runs interactively — confirm sync status with the user in Phase 2 before proceeding
- source.json is the sync marker: only written on success so failed builds are retried on next sync
- Each ingest phase is independent: one failure does not block the others
- Always output the final JSON regardless of success or failure
