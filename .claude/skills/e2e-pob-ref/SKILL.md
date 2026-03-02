---
name: e2e-pob-ref
description: E2E test for PoB reference sync pipeline. Cleans state, runs scripts, verifies output, and tests idempotency. Use at season start to confirm scripts work with new PoB data.
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
---

# Verify PoB Ref — E2E Pipeline Test

Run the 4 bash scripts from clean state, verify all output, and confirm idempotency. Valid output is kept after verification.

## Usage

```
/verify-pob-ref
```

No arguments required. All checks are version-independent — counts are extracted dynamically, never hardcoded.

## Execution Phases

```
Phase 1: Setup (submodule + detect version)
    │ fail → STOP (fatal)
    ▼
Phase 2: Clean + Run Scripts (sequential, timed)
    │ script fail → log, continue
    ▼
Phase 3: Verify Output (5 checks, never stop on failure)
    ▼
Phase 4: Idempotency Test
    ▼
Report (pass/fail table + JSON)
```

### Phase 1: Setup

Ensure the submodule is initialized and detect the current game version.

1. Initialize and update submodule:
   ```bash
   POB_PATH="vendor/pob/origin"
   if [ ! -d "$POB_PATH/src/Data" ]; then
     git submodule update --init --depth 1 vendor/pob/origin
   fi
   git submodule update --remote vendor/pob/origin
   ```
2. Detect version, commit, and tag:
   ```bash
   VERSION=$(sed -n '/^treeVersionList/,/}/p' "$POB_PATH/src/GameVersions.lua" \
     | grep -oE '"[0-9]+_[0-9]+"' | tail -1 | tr -d '"' | tr '_' '.')
   POB_COMMIT=$(git -C "$POB_PATH" rev-parse HEAD)
   POB_VERSION=$(git -C "$POB_PATH" describe --tags --abbrev=0 2>/dev/null || echo "unknown")
   POB_COMMIT_SHORT=${POB_COMMIT:0:8}
   ```
3. If VERSION is empty → output `{"status": "failed", "error": "Cannot detect version from PoB"}` and stop.
4. Display: `Testing: VERSION={VERSION}, POB_COMMIT={POB_COMMIT_SHORT}, POB_VERSION={POB_VERSION}`

### Phase 2: Clean + Run Scripts

Remove existing output and regenerate from scratch.

1. Remove existing output:
   ```bash
   rm -rf vendor/pob/references/ vendor/pob/source.json
   ```

2. Run all 4 scripts sequentially with timing. Do NOT use background `&` jobs — sandbox restrictions prevent them.
   ```bash
   START=$(python3 -c 'import time; print(time.time())')

   bash vendor/pob/scripts/base-item.sh "$POB_PATH" "$VERSION" "$POB_COMMIT_SHORT" "$POB_VERSION"; E1=$?
   bash vendor/pob/scripts/unique-item.sh "$POB_PATH" "$VERSION" "$POB_COMMIT_SHORT" "$POB_VERSION"; E2=$?
   bash vendor/pob/scripts/skill-gem.sh "$POB_PATH" "$VERSION" "$POB_COMMIT_SHORT" "$POB_VERSION"; E3=$?
   bash vendor/pob/scripts/passive-tree.sh "$POB_PATH" "$VERSION" "$POB_COMMIT_SHORT" "$POB_VERSION"; E4=$?

   END=$(python3 -c 'import time; print(time.time())')
   ELAPSED=$(python3 -c "print(round($END - $START, 2))")
   echo "base-item=$E1 unique-item=$E2 skill-gem=$E3 passive-tree=$E4 time=${ELAPSED}s"
   ```

3. Record exit code per script (0 = success). Continue even if a script fails.

### Phase 3: Verify Output

Run all 5 checks in a single bash block. Record each as PASS or FAIL. Do NOT stop on first failure — collect full results.

**Check 1 — File inventory:**

Verify exactly 4 expected files exist with non-zero size. No extra files.

```bash
C1=PASS
for f in vendor/pob/references/{base-item,unique-item,skill-gem,passive-tree}.md; do
  if [ -s "$f" ]; then echo "OK: $f ($(wc -c < "$f" | tr -d ' ') bytes)"
  else echo "FAIL: $f missing or empty"; C1=FAIL
  fi
done

EXPECTED_FILES="base-item.md passive-tree.md skill-gem.md unique-item.md"
ACTUAL_FILES=$(ls vendor/pob/references/ | sort | tr '\n' ' ' | sed 's/ $//')
if [ "$ACTUAL_FILES" = "$EXPECTED_FILES" ]; then echo "OK: exactly 4 files"
else echo "FAIL: unexpected files: $ACTUAL_FILES"; C1=FAIL
fi
```

**Check 2 — `@generated` headers:**

Each file's first line must contain the `@generated` marker with the detected version info.

> **zsh caveat**: `<!--` contains `!` which triggers zsh history expansion. Use `grep -qF` with only the `@generated ...` payload to avoid this.

```bash
C2=PASS
for f in vendor/pob/references/{base-item,unique-item,skill-gem,passive-tree}.md; do
  if head -1 "$f" | grep -qF "@generated gameVersion=$VERSION pobCommit=$POB_COMMIT_SHORT pobVersion=$POB_VERSION"; then
    echo "OK: $(basename $f)"
  else
    echo "FAIL: $(basename $f) header mismatch"
    echo "  got: $(head -1 "$f")"
    C2=FAIL
  fi
done
```

**Check 3 — Count extraction (all > 0):**

Extract totals from each file using the patterns the scripts produce. Verify each is a positive integer.

```bash
C3=PASS

# base-item: "| **Total (usable)** | **{N}** |"
BASE_COUNT=$(grep -oE '\*\*Total \(usable\)\*\* \| \*\*[0-9]+\*\*' vendor/pob/references/base-item.md | grep -oE '[0-9]+')

# unique-item: "| **Total (usable)** | **{N}** |"
UNIQUE_COUNT=$(grep -oE '\*\*Total \(usable\)\*\* \| \*\*[0-9]+\*\*' vendor/pob/references/unique-item.md | grep -oE '[0-9]+')

# skill-gem: "({N} entries)" on the Gems.lua **Path** line
GEM_COUNT=$(grep 'Gems.lua' vendor/pob/references/skill-gem.md | grep -oE '[0-9]+ entries' | head -1 | grep -oE '[0-9]+')

# skill-gem: "({N} definitions," on the Skills/ **Path** line
SKILL_COUNT=$(grep -oE '[0-9]+ definitions' vendor/pob/references/skill-gem.md | head -1 | grep -oE '[0-9]+')

# passive-tree: "**Total**: {N} nodes"
NODE_COUNT=$(grep -oE '\*\*Total\*\*: [0-9]+ nodes' vendor/pob/references/passive-tree.md | grep -oE '[0-9]+' | head -1)

# passive-tree: "**Total versions**: {N}"
VERSION_COUNT=$(grep -oE 'Total versions\*\*: [0-9]+' vendor/pob/references/passive-tree.md | grep -oE '[0-9]+')

for name_val in "base_items=$BASE_COUNT" "unique_items=$UNIQUE_COUNT" "gems=$GEM_COUNT" "skills=$SKILL_COUNT" "nodes=$NODE_COUNT" "versions=$VERSION_COUNT"; do
  name=${name_val%%=*}; val=${name_val#*=}
  if [ -n "$val" ] && [ "$val" -gt 0 ] 2>/dev/null; then
    echo "OK: $name = $val"
  else
    echo "FAIL: $name = '${val:-empty}'"; C3=FAIL
  fi
done
```

**Check 4 — Independent cross-check:**

Count base items independently from source Lua files and compare against the file-reported total. Uses `itemBases[` pattern — matching the script's own counting method.

```bash
C4=PASS
INDEPENDENT_BASE=0
for f in "$POB_PATH"/src/Data/Bases/*.lua; do
  fname=$(basename "$f")
  case "$fname" in fishing.lua|graft.lua) continue;; esac
  count=$(grep -c 'itemBases\[' "$f" || true)
  INDEPENDENT_BASE=$((INDEPENDENT_BASE + count))
done

echo "File reports: $BASE_COUNT, Independent count: $INDEPENDENT_BASE"
if [ "$BASE_COUNT" = "$INDEPENDENT_BASE" ] && [ "$INDEPENDENT_BASE" -gt 0 ]; then
  echo "OK: base-item cross-check"
else
  echo "FAIL: base-item mismatch (file=$BASE_COUNT, source=$INDEPENDENT_BASE)"; C4=FAIL
fi
```

### Phase 4: Idempotency Test

Write source.json, then verify the sync-skip logic detects "up to date".

1. Write source.json:
   ```bash
   C5=PASS
   printf '{\n  "gameVersion": "%s",\n  "pobCommit": "%s",\n  "pobVersion": "%s",\n  "builtAt": "%s"\n}\n' \
     "$VERSION" "$POB_COMMIT" "$POB_VERSION" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     > vendor/pob/source.json
   ```

2. Re-run the sync-check logic:
   ```bash
   PREV_COMMIT=$(jq -r '.pobCommit' vendor/pob/source.json)
   CURRENT_COMMIT=$(git -C "$POB_PATH" rev-parse HEAD)
   if [ "$PREV_COMMIT" = "$CURRENT_COMMIT" ]; then
     echo "OK: idempotency — detected up to date"
   else
     echo "FAIL: idempotency — commit mismatch (source.json=$PREV_COMMIT, HEAD=$CURRENT_COMMIT)"
     C5=FAIL
   fi
   ```

## Final Output

Display a summary table and result JSON.

**Summary table:**
```
| # | Check                   | Result |
|---|-------------------------|--------|
| 1 | File inventory (4/4)    | PASS   |
| 2 | @generated headers      | PASS   |
| 3 | Counts > 0 (6/6)       | PASS   |
| 4 | Independent cross-check | PASS   |
| 5 | Idempotency             | PASS   |
```

**Result JSON:**
```json
{
  "status": "pass | fail",
  "version": "3.27",
  "pobCommit": "fb6cd055",
  "pobVersion": "v2.60.0",
  "counts": {
    "base_items": 1063,
    "unique_items": 1240,
    "gems": 751,
    "skills": 1409,
    "nodes": 3287,
    "versions": 35
  },
  "checks": {
    "file_inventory": "pass | fail",
    "generated_headers": "pass | fail",
    "counts_positive": "pass | fail",
    "independent_cross_check": "pass | fail",
    "idempotency": "pass | fail"
  },
  "script_time_seconds": 3.09
}
```

**Example terminal output (all pass):**
```
✅ Verify PoB Ref Complete
   Version: 3.27 (fb6cd055, v2.60.0)
   Scripts: 4/4 succeeded in 3.09s
   Checks: 5/5 passed
   Counts: base=1063, unique=1240, gems=751, skills=1409, nodes=3287, versions=35
```

## Error States

| Error | Action |
|-------|--------|
| Submodule init/update fails | STOP — cannot proceed without PoB data |
| VERSION detection returns empty | STOP — `GameVersions.lua` may have changed format |
| Individual script fails (exit != 0) | Log error, continue — verify remaining files |
| Count extraction returns empty | Mark as FAIL, continue other checks |
| Independent cross-check mismatch | Mark as FAIL — script counting logic may have diverged from source |
| Idempotency check fails | Mark as FAIL — does not invalidate other results |
