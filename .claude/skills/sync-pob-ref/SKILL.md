---
name: sync-pob-ref
description: Sync PoB reference files from PathOfBuilding submodule. Use when updating game version data or regenerating vendor/pob/references/.
---

# Sync PoB Ref — Reference Sync

You are the PoB reference sync orchestrator. You pull the latest PathOfBuilding submodule, detect the current game version, and regenerate reference files under `vendor/pob/references/` via parallel sub-agents.

## Invocation

```
/sync-pob-ref
```

No manual input required. Auto-detects version and skips if already up to date.

## Grounding Rules

- NEVER modify files outside `vendor/pob/`
- NEVER perform data parsing yourself — delegate ALL parsing to sub-agents
- NEVER retry a failed sub-agent — log the error and continue
- Every sub-agent result MUST be validated before recording its status
- Follow the phase order strictly — do NOT skip phases or reorder them

## Execution Flow

```
Phase 1: Pull Latest PoB
    │ fail → STOP (fatal)
    ▼
Phase 2: Detect Version + Check Sync
    │ up to date → report + STOP
    │ fail → STOP (fatal)
    ▼
Phase 3: Sync References (4 agents parallel)
    │ individual fail → log, continue
    ▼
Phase 4: Write source.json + Report
    ▼
Output Result JSON
```

**Blocking failures** (stop entire process):
- Phase 1: submodule init/update fails
- Phase 2: version detection fails

**Non-blocking failures** (log and continue):
- Phase 3: individual reference sync agent fails

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
   SOURCE_FILE="vendor/pob/source.json"
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

Regenerate `vendor/pob/references/*.md` from PoB source.

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

### Phase 4: Write source.json and Report

Record the sync marker and produce the final result.

1. Write sync marker **only if all 4 agents succeeded**. If any agent failed, do NOT write — this ensures the next run retries.
   ```json
   // vendor/pob/source.json
   {
     "gameVersion": "{VERSION}",
     "pobCommit": "{POB_COMMIT}",
     "pobVersion": "{POB_VERSION}",
     "builtAt": "{ISO 8601 timestamp}"
   }
   ```

2. Verify reference files exist:
   ```bash
   for f in vendor/pob/references/base-item.md \
            vendor/pob/references/unique-item.md \
            vendor/pob/references/skill-gem.md \
            vendor/pob/references/passive-tree.md; do
     [ -f "$f" ] || echo "MISSING: $f"
   done
   ```

3. Determine final status:
   - All 4 agents succeeded → `"success"`
   - 1–3 agents succeeded → `"partial"`
   - All 4 agents failed → `"failed"`

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
  "references": {
    "base_item": "success | failed",
    "unique_item": "success | failed",
    "skill_gem": "success | failed",
    "passive_tree": "success | failed"
  },
  "source_json_written": true,
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
| All 4 reference sync agents fail | Do NOT write source.json. Output: `{"status": "failed"}` |

## Important Notes

- This skill runs interactively — confirm sync status with the user in Phase 2 before proceeding
- source.json is the sync marker: only written when all 4 agents succeed, so partial failures are retried on next run
- Always output the final JSON regardless of success or failure
