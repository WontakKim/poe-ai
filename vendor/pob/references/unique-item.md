<!-- @generated gameVersion=3.28 pobCommit=3acd9100 pobVersion=v2.60.0 -->
# Unique Items — `src/Data/Uniques/`

**Main files (22)**: amulet, axe, belt, body, boots, bow, claw, dagger, fishing, flask, gloves, graft, helmet, jewel, mace, quiver, ring, shield, staff, sword, tincture, wand

**Usable (20)**: Exclude fishing and graft.

**Special/ folder**: BoundByDestiny.lua (0), Generated.lua (12), New.lua (5), race.lua (11), WatchersEye.lua (0)

**Item counts**:
| File | Count | File | Count |
|------|-------|------|-------|
| jewel | 178 | mace | 58 |
| helmet | 118 | staff | 42 |
| ring | 111 | flask | 38 |
| body | 101 | bow | 33 |
| gloves | 87 | axe | 33 |
| amulet | 87 | wand | 27 |
| shield | 78 | quiver | 25 |
| boots | 77 | dagger | 23 |
| belt | 62 | claw | 21 |
| sword | 61 | tincture | 5 |
| **Total (usable)** | **1265** | | |

**Block format** (items separated by `]],[[`, first starts with `[[`, last ends with `]]`):
```lua
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
```

Block structure:
- Line 1: `[[` (block start marker)
- Line 2: Item name
- Line 3: Base type name
- Lines 4-N: Metadata lines and implicit/explicit mods
  - Metadata lines match the patterns listed below
  - After `Implicits: N`, the next N lines are implicit mods
  - Remaining lines are explicit mods

**Metadata patterns** (extracted from source):

- **Colon-terminated**:
  - `Duelist:`
  - `Energy Shield:`
  - `Has Alt Variant Three:`
  - `Has Alt Variant Two:`
  - `Has Alt Variant:`
  - `Implicits:`
  - `Item Level:`
  - `League:`
  - `LevelReq:`
  - `Limited to:`
  - `Marauder:`
  - `Radius:`
  - `Ranger:`
  - `Requires Level:`
  - `Scion:`
  - `Selected Alt Variant Three:`
  - `Selected Alt Variant Two:`
  - `Selected Alt Variant:`
  - `Selected Variant:`
  - `Shadow:`
  - `Sockets:`
  - `Source:`
  - `Talisman Tier:`
  - `Templar:`
  - `Upgrade:`
  - `Variant:`
  - `Witch:`

- **Non-colon markers** (standalone lines):
  - `Corrupted`
  - `Elder Item`
  - `Mirrored`
  - `Shaper Item`

Lines matching these patterns are metadata — everything else after the Implicits section is a mod line.

**Level requirement formats**:
- `LevelReq: N` — 98 occurrences
- `Requires Level N, X Str, Y Dex` — 626 occurrences
- If neither present, fall back to the base item's level requirement.

**Parsing notes**:
1. 495 of 1265 items lack an `Implicits:` line — treat as 0 implicits (all non-metadata lines are explicit mods).
2. Variant prefix `{variant:N}` on the base type line (line 3): amulet (1), axe (2), belt (1), body (3), boots (4), bow (1), claw (2), gloves (3), helmet (2), quiver (8), shield (4), staff (2), sword (1), wand (15). Parser must select the correct base type for the current variant.
3. Variant filtering: find "Current" variant index (or last variant if none labeled "Current"), keep only mods matching that index or with no variant prefix.
4. Strip `{variant:N}`, `{variant:N,M}`, and `{tags:...}` prefixes from kept lines.
5. Special/New.lua uses `data.uniques.new = {` format (NOT `return {`).
6. Special/WatchersEye.lua and BoundByDestiny.lua contain dynamically-generated items (0 parseable entries). Generated.lua has static entries that ARE parseable.
