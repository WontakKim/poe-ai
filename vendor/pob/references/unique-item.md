<!-- @generated gameVersion=3.27 pobCommit=fb6cd055 pobVersion=v2.60.0 -->
# Unique Items — `src/Data/Uniques/`

**Main files (22)**: amulet, axe, belt, body, boots, bow, claw, dagger, fishing, flask, gloves, graft, helmet, jewel, mace, quiver, ring, shield, staff, sword, tincture, wand

**Usable (20)**: Exclude fishing and graft.

**Special/ folder**: BoundByDestiny (0), Generated (12), New (25), race (11), WatchersEye (0)

**Item counts**:
| File | Count | File | Count |
|------|-------|------|-------|
| jewel | 178 | mace | 57 |
| helmet | 116 | staff | 41 |
| ring | 103 | flask | 37 |
| body | 100 | bow | 32 |
| gloves | 85 | axe | 32 |
| amulet | 85 | wand | 26 |
| boots | 77 | quiver | 25 |
| shield | 76 | dagger | 22 |
| belt | 62 | claw | 21 |
| sword | 60 | tincture | 5 |
| **Total (usable)** | **1240** | | |

**Block format** (items separated by `]],[[`, first starts with `[[`, last ends with `]]`):
```
[[
Ahn's Might
Midnight Blade
Implicits: 1
40% increased Global Accuracy Rating
Adds (80-115) to (150-205) Physical Damage
(15-25)% increased Critical Strike Chance
-1 to Maximum Frenzy Charges
10% increased Area of Effect
+100 Strength Requirement
+50% Global Critical Strike Multiplier while you have no Frenzy Charges
+(400-500) to Accuracy Rating while at Maximum Frenzy Charges
]]
```

Block structure:
- Line 1: Item name
- Line 2: Base type name
- Metadata lines (League:, Variant:, etc.) — patterns listed below
- `Implicits: N` — declares count of implicit mods to follow
- Implicit mods (N lines)
- Explicit mods (remaining lines until `]]` or `]],[[`)

**Metadata patterns** (extracted from source):
- **Colon-terminated**: Duelist:, Energy Shield:, Has Alt Variant Three:, Has Alt Variant Two:, Has Alt Variant:, Implicits:, Item Level:, League:, LevelReq:, Limited to:, Marauder:, Radius:, Ranger:, Requires Level:, Scion:, Selected Alt Variant Three:, Selected Alt Variant Two:, Selected Alt Variant:, Selected Variant:, Shadow:, Sockets:, Source:, Talisman Tier:, Templar:, Upgrade:, Variant:, Witch:
- **Non-colon markers**: Corrupted, Elder Item, Mirrored, Shaper Item
- Lines matching these patterns are metadata — everything else after Implicits section is a mod line.

**Level requirement formats**:
- `LevelReq: N` — 98 occurrences
- `Requires Level N, X Str, Y Dex` — 601 occurrences
- If neither present, fall back to the base item's level requirement.

**Parsing notes**:
1. 488 of 1240 items lack an `Implicits:` line — treat as 0 implicits (all non-metadata lines are explicit mods).
2. Variant prefix `{variant:N}` can appear on the base type line (line 2) in 20 files — parser must select the correct base type for the current variant.
3. Variant filtering: find "Current" variant index (or last variant if none labeled "Current"), keep only mods matching that index or with no variant prefix.
4. Strip `{variant:N}`, `{variant:N,M}`, and `{tags:...}` prefixes from kept lines.
5. Special/New.lua uses `data.uniques.new = {` format (NOT `return {`).
6. Special/WatchersEye.lua and BoundByDestiny.lua contain dynamically-generated items (0 parseable entries). Generated.lua has static entries that ARE parseable.
