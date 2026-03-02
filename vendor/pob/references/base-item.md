<!-- @generated gameVersion=3.27 pobCommit=fb6cd055 pobVersion=v2.60.0 -->
# Base Items — `src/Data/Bases/`

**Files (22)**: amulet, axe, belt, body, boots, bow, claw, dagger, fishing, flask, gloves, graft, helmet, jewel, mace, quiver, ring, shield, staff, sword, tincture, wand

**Usable (20)**: Exclude fishing (joke item) and graft (Sanctum-internal).

**Item counts** (1,063 total usable):
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
	type = "One Handed Sword",
	socketLimit = 3,
	tags = { default = true, one_hand_weapon = true, onehand = true, sword = true, weapon = true, },
	influenceTags = { shaper = "sword_shaper", elder = "sword_elder", adjudicator = "sword_adjudicator", basilisk = "sword_basilisk", crusader = "sword_crusader", eyrie = "sword_eyrie", cleansing = "sword_cleansing", tangle = "sword_tangle" },
	implicit = "40% increased Global Accuracy Rating",
	implicitModTypes = { { "attack" }, },
	weapon = { PhysicalMin = 4, PhysicalMax = 9, CritChanceBase = 5, AttackRateBase = 1.55, Range = 11, },
	req = { str = 8, dex = 8, },
}
```

**Top-level fields**:
- `type` — Item base type (e.g., "One Handed Sword")
- `socketLimit` — Maximum socket count
- `tags` — Boolean categories (e.g., sword, weapon, fire_damage)
- `influenceTags` — Influence-specific tags (e.g., shaper, elder)
- `implicit` — Implicit mod string
- `implicitModTypes` — Nested arrays of implicit mod types (e.g., `{ { "attack" }, }`)
- `weapon` — Weapon stats (appears in weapon bases)
- `armour` — Armour stats (appears in armour bases)
- `flask` — Flask stats (appears in flask.lua)
- `tincture` — Tincture stats (appears in tincture.lua)
- `req` — Requirements table (str, dex, int)
- `subType` — Secondary type classification (rare)
- `hidden` — Boolean; set to true for test/unreleased items
- `flavourText` — Flavour text string (rare)

**Type-specific stat fields** (exactly one per item, or none):
- **weapon** (sword, axe, mace, dagger, claw, wand, staff, bow): `{ AttackRateBase, CritChanceBase, PhysicalMax, PhysicalMin, Range }`
- **armour** (body, boots, gloves, helmet, shield): `{ ArmourBaseMax, ArmourBaseMin, BlockChance, EnergyShieldBaseMax, EnergyShieldBaseMin, EvasionBaseMax, EvasionBaseMin, MovementPenalty, WardBaseMax, WardBaseMin }` (sparse — different bases have different subsets)
- **flask** (flask): `{ buff, chargesMax, chargesUsed, duration, life, mana }` (sparse — life/mana/utility flasks differ)
- **tincture** (tincture): `{ cooldown, manaBurn }`
- **jewel/amulet/ring/belt/quiver**: No type-specific stat fields.

**Caveats**:
1. **Multiline implicit strings** — Files with `\n` in implicit mod strings (boots, dagger, tincture, ring, graft, helmet, claw, gloves, staff, belt, amulet): Parser must handle escaped newlines in implicit field values.
2. **Hidden items** — Files with `hidden = true` entries (body, sword, quiver): These are unreleased/test items and should be marked during import.
3. **Flavour text** — Files with `flavourText` field (body, sword, ring, amulet): Additional cosmetic field that may vary per entry.
4. **Excluded files** — `fishing.lua` and `graft.lua` are excluded from usable count: fishing is a joke item, graft is Sanctum-internal.
5. **Sparse armour sub-fields** — BlockChance, EnergyShieldBase*, EvasionBase*, WardBase* appear only on specific bases (e.g., shields have BlockChance; evasion bases have EvasionBaseMax/EvasionBaseMin).
6. **Sparse flask sub-fields** — life/mana fields appear only on life/mana flasks; buff/duration/chargesUsed/chargesMax vary by flask type (utility vs life/mana).
