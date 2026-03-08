<!-- @generated gameVersion=3.28 pobCommit=3acd9100 pobVersion=v2.60.0 -->
# Base Items — `src/Data/Bases/`

**Files (22)**: amulet, axe, belt, body, boots, bow, claw, dagger, fishing, flask, gloves, graft, helmet, jewel, mace, quiver, ring, shield, staff, sword, tincture, wand

**Usable (20)**: Exclude fishing (joke item) and graft (Sanctum-internal).

**Item counts**:
| File | Count | File | Count |
|------|-------|------|-------|
| body | 123 | flask | 48 |
| shield | 98 | dagger | 32 |
| helmet | 95 | bow | 29 |
| sword | 84 | wand | 28 |
| mace | 81 | staff | 28 |
| boots | 81 | quiver | 28 |
| gloves | 80 | claw | 28 |
| amulet | 61 | jewel | 15 |
| axe | 53 | belt | 13 |
| ring | 48 | tincture | 10 |
| **Total (usable)** | **1063** | | |

**Lua format** (example from `sword.lua`):
```lua
itemBases["Rusted Sword"] = {
	type = "One Handed Sword",  -- Item type string
	socketLimit = 3,  -- Max sockets (omitted if 0)
	tags = { default = true, one_hand_weapon = true, onehand = true, sword = true, weapon = true, },  -- Classification tags
	influenceTags = { shaper = "sword_shaper", elder = "sword_elder", adjudicator = "sword_adjudicator", basilisk = "sword_basilisk", crusader = "sword_crusader", eyrie = "sword_eyrie", cleansing = "sword_cleansing", tangle = "sword_tangle" },  -- Influence variant IDs (weapons only)
	implicit = "40% increased Global Accuracy Rating",  -- Implicit mod text (may contain \n for multiline)
	implicitModTypes = { { "attack" }, },  -- Implicit mod tags (array of arrays)
	weapon = { PhysicalMin = 4, PhysicalMax = 9, CritChanceBase = 5, AttackRateBase = 1.55, Range = 11, },  -- Type-specific stats (weapons, armour, flask, tincture)
	req = { str = 8, dex = 8, },  -- Minimum requirements (str, dex, int, level)
}
```

**Top-level fields**:
`armour`, `flask`, `flavourText`, `hidden`, `implicit`, `implicitModTypes`, `influenceTags`, `req`, `socketLimit`, `subType`, `tags`, `tincture`, `type`, `weapon`

**Type-specific stat fields** (exactly one per item, or none):
- **weapon** (axe, bow, claw, dagger, mace, staff, sword, wand): `{ AttackRateBase, CritChanceBase, PhysicalMax, PhysicalMin, Range }`
- **armour** (body, boots, gloves, helmet, shield): `{ ArmourBaseMax, ArmourBaseMin, BlockChance, EnergyShieldBaseMax, EnergyShieldBaseMin, EvasionBaseMax, EvasionBaseMin, MovementPenalty, WardBaseMax, WardBaseMin }`
- **flask** (flask): `{ buff, chargesMax, chargesUsed, duration, life, mana }`
- **tincture** (tincture): `{ cooldown, manaBurn }`
- **jewel/amulet/ring/belt/quiver**: No type-specific stat fields.

**Caveats**:
- **Multiline implicits**: Files with literal `\n` in implicit strings: amulet, belt, boots, claw, dagger, gloves, graft, helmet, ring, staff, tincture. Require unescaping when parsing.
- **Hidden items**: Files containing `hidden = true`: body, quiver, sword. Quest items, divination card bases, etc.
- **Flavour text**: Files with optional `flavourText` field: amulet, body, ring, sword.
- **Sparse armour sub-fields** (per-file distribution):
  body.lua: ArmourBaseMax, ArmourBaseMin, EnergyShieldBaseMax, EnergyShieldBaseMin, EvasionBaseMax, EvasionBaseMin, MovementPenalty
  boots.lua: ArmourBaseMax, ArmourBaseMin, EnergyShieldBaseMax, EnergyShieldBaseMin, EvasionBaseMax, EvasionBaseMin, WardBaseMax, WardBaseMin
  gloves.lua: ArmourBaseMax, ArmourBaseMin, EnergyShieldBaseMax, EnergyShieldBaseMin, EvasionBaseMax, EvasionBaseMin, WardBaseMax, WardBaseMin
  helmet.lua: ArmourBaseMax, ArmourBaseMin, EnergyShieldBaseMax, EnergyShieldBaseMin, EvasionBaseMax, EvasionBaseMin, WardBaseMax, WardBaseMin
  shield.lua: ArmourBaseMax, ArmourBaseMin, BlockChance, EnergyShieldBaseMax, EnergyShieldBaseMin, EvasionBaseMax, EvasionBaseMin, MovementPenalty
- **Sparse flask sub-fields**: `life`/`mana` on Life/Mana flasks. `buff`/`duration` on Utility flasks. All flasks have `chargesUsed`/`chargesMax`.
