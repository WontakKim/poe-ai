<!-- @generated gameVersion=3.27 pobCommit=fb6cd055 pobVersion=v2.60.0 -->
# Skill Gems — `src/Data/Gems.lua` + `src/Data/Skills/`

Skill gem data has two sources joined by `grantedEffectId`:
- **Gems.lua** — gem item registry (what the player picks up)
- **Skills/*.lua** — skill effect definitions (what the gem does)

## Gems.lua — Gem Item Registry

**Path**: `src/Data/Gems.lua` (751 entries)

**Category breakdown**:
- Active-only: 537 (includes 52 vaal, 198 transfigured)
- Support-only: 205 (includes 38 awakened)
- Active+Support hybrid: 9 (support gems that also grant an active skill)

**Fields** (14 unique):
baseTypeName, gameId, grantedEffectId, name, naturalMaxLevel, reqDex, reqInt, reqStr, secondaryEffectName, secondaryGrantedEffectId, tags, tagString, vaalGem, variantId

**Tag keys** (54 unique):
| grants_active_skill | 546 |
| area | 370 |
| spell | 368 |
| intelligence | 296 |
| dexterity | 260 |
| duration | 257 |
| attack | 245 |
| support | 214 |
| strength | 190 |
| projectile | 164 |
| melee | 126 |
| physical | 122 |
| fire | 116 |
| lightning | 106 |
| cold | 81 |
| minion | 73 |
| bow | 65 |
| chaos | 62 |
| vaal | 52 |
| strike | 50 |
| aura | 48 |
| critical | 44 |
| channelling | 40 |
| awakened | 38 |
| movement | 37 |
| trap | 33 |
| trigger | 30 |
| slam | 30 |
| travel | 25 |
| totem | 22 |
| hex | 21 |
| chaining | 21 |
| nova | 20 |
| golem | 17 |
| mine | 16 |
| orb | 14 |
| curse | 14 |
| warcry | 13 |
| brand | 12 |
| low_max_level | 10 |
| random_element | 8 |
| arcane | 8 |
| retaliation | 7 |
| link | 7 |
| blink | 7 |
| mark | 6 |
| guard | 6 |
| exceptional | 6 |
| herald | 5 |
| blessing | 3 |
| banner | 3 |
| stance | 2 |

**naturalMaxLevel distribution**:
- 20: 702 entries
- 5: 35 entries
- 1: 6 entries
- 4: 3 entries
- 3: 3 entries
- 6: 2 entries

**Example — Active gem (Arc)**:
```lua
	["Metadata/Items/Gems/SkillGemArc"] = {
		name = "Arc",
		baseTypeName = "Arc",
		gameId = "Metadata/Items/Gems/SkillGemArc",
		variantId = "Arc",
		grantedEffectId = "Arc",
		tags = {
			intelligence = true,
			grants_active_skill = true,
			spell = true,
			chaining = true,
			lightning = true,
		},
		tagString = "Spell, Chaining, Lightning",
		reqStr = 0,
		reqDex = 0,
		reqInt = 100,
		naturalMaxLevel = 20,
	},
	},
```

**Example — Support gem (Added Cold Damage)**:
```lua
	["Metadata/Items/Gems/SkillGemSupportAddedColdDamage"] = {
		name = "Added Cold Damage",
		gameId = "Metadata/Items/Gems/SupportGemAddedColdDamage",
		variantId = "SupportAddedColdDamage",
		grantedEffectId = "SupportAddedColdDamage",
		tags = {
			cold = true,
			dexterity = true,
			support = true,
		},
		tagString = "Cold, Support",
		reqStr = 0,
		reqDex = 100,
		reqInt = 0,
		naturalMaxLevel = 20,
	},
	},
```

## Skills/ — Skill Effect Definitions

**Path**: `src/Data/Skills/` (10 files, 1409 definitions, 783 player-visible, 626 hidden)

**Definitions per file**:
| spectre | 355 | 1 | 354 |
| act_int | 222 | 222 | 0 |
| act_dex | 196 | 195 | 1 |
| other | 146 | 7 | 139 |
| act_str | 130 | 130 | 0 |
| sup_int | 90 | 90 | 0 |
| minion | 72 | 0 | 72 |
| sup_dex | 70 | 70 | 0 |
| sup_str | 68 | 68 | 0 |
| glove | 60 | 0 | 60 |

**Top-level fields** (44 unique):
addFlags, addMinionList, addSkillTypes, baseEffectiveness, baseFlags, baseMods, baseTypeName, cannotBeSupported, castTime, color, constantStats, description, end, excludeSkillTypes, explosiveArrowFunc, fromItem, fromTree, hidden, ignoreMinionTypes, incrementalEffectiveness, initialFunc, isTrigger, levelMods, levels, minionHasItemSet, minionList, minionSkillTypes, minionUses, name, notMinionStat, parts, plusVersionOf, postCritFunc, preDamageFunc, preSkillTypeFunc, qualityStats, requireSkillTypes, skillTotemId, skillTypes, statDescriptionScope, statMap, stats, support, supportGemsOnly, weaponTypes

**Level entry named fields** (17 unique):
- levelRequirement: 31425 occurrences
- statInterpolation: 27070 occurrences
- cost: 19967 occurrences
- damageEffectiveness: 13862 occurrences
- critChance: 7752 occurrences
- manaMultiplier: 7393 occurrences
- baseMultiplier: 7284 occurrences
- cooldown: 6987 occurrences
- storedUses: 6913 occurrences
- attackSpeedMultiplier: 4616 occurrences
- PvPDamageMultiplier: 3160 occurrences
- vaalStoredUses: 2052 occurrences
- soulPreventionDuration: 2052 occurrences
- manaReservationPercent: 1220 occurrences
- duration: 695 occurrences
- manaReservationFlat: 402 occurrences
- attackTime: 280 occurrences

**Cost types** (7 unique, inside `cost = { ... }`):
ES, Life, Mana, ManaPercent, ManaPercentPerMinute, ManaPerMinute, Soul

**SkillType enum**: 125 unique values (e.g. `SkillType.Spell`, `SkillType.Attack`, `SkillType.Damage`, ...)

**Example — Active skill (Arc)**:
```lua
skills["Arc"] = {
	name = "Arc",
	baseTypeName = "Arc",
	color = 3,
	baseEffectiveness = 1.584900021553,
	incrementalEffectiveness = 0.039500001817942,
	description = "An arc of lightning reaches from the caster to a targeted enemy and chains to other enemies, but not immediately back. Each time the arc chains, it will also chain a secondary arc to another enemy that the main arc has not already hit, which cannot chain further.",
	skillTypes = { [SkillType.Spell] = true, [SkillType.Damage] = true, [SkillType.Trappable] = true, [SkillType.Totemable] = true, [SkillType.Mineable] = true, [SkillType.Chains] = true, [SkillType.Multicastable] = true, [SkillType.Triggerable] = true, [SkillType.Lightning] = true, [SkillType.CanRapidFire] = true, },
	statDescriptionScope = "beam_skill_stat_descriptions",
	castTime = 0.7,
	statMap = {
		["arc_damage_+%_final_for_each_remaining_chain"] = {
			mod("Damage", "MORE", nil, 0, bit.bor(KeywordFlag.Hit, KeywordFlag.Ailment), { type = "PerStat", stat = "ChainRemaining" }),
		},
	},
	baseFlags = {
		spell = true,
		chaining = true,
	},
	qualityStats = {
		Default = {
			{ "number_of_chains", 0.05 },
		},
	},
	constantStats = {
		{ "arc_damage_+%_final_for_each_remaining_chain", 15 },
		{ "arc_chain_distance", 35 },
	},
	stats = {
		"spell_minimum_base_lightning_damage",
		"spell_maximum_base_lightning_damage",
		"number_of_chains",
		"arc_enhanced_behaviour",
		"disable_visual_hit_effect",
	},
	notMinionStat = {
		"spell_minimum_base_lightning_damage",
		"spell_maximum_base_lightning_damage",
	},
	levels = {
		[1] = { 0.30000001192093, 1.7000000476837, 4, PvPDamageMultiplier = -25, critChance = 6, damageEffectiveness = 1.2, levelRequirement = 12, statInterpolation = { 3, 3, 1, }, cost = { Mana = 8, }, },
		[2] = { 0.30000001192093, 1.7000000476837, 4, PvPDamageMultiplier = -25, critChance = 6, damageEffectiveness = 1.2, levelRequirement = 15, statInterpolation = { 3, 3, 1, }, cost = { Mana = 9, }, },
		...
	}
}
```

**Example — Support skill (Added Cold Damage)**:
```lua
skills["SupportAddedColdDamage"] = {
	name = "Added Cold Damage",
	description = "Supports any skill that hits enemies.",
	color = 2,
	baseEffectiveness = 0.58050000667572,
	incrementalEffectiveness = 0.035900000482798,
	support = true,
	requireSkillTypes = { SkillType.Attack, SkillType.Damage, },
	addSkillTypes = { },
	excludeSkillTypes = { },
	statDescriptionScope = "gem_stat_descriptions",
	qualityStats = {
		Default = {
			{ "cold_damage_+%", 0.5 },
		},
	},
	stats = {
		"global_minimum_added_cold_damage",
		"global_maximum_added_cold_damage",
	},
	levels = {
		[1] = { 0.80000001192093, 1.2000000476837, levelRequirement = 8, manaMultiplier = 20, statInterpolation = { 3, 3, }, },
		[2] = { 0.80000001192093, 1.2000000476837, levelRequirement = 10, manaMultiplier = 20, statInterpolation = { 3, 3, }, },
		...
	}
}
```

## Join: Gems.lua → Skills/

**Primary link**: `Gems.lua[key].grantedEffectId` == `skills["..."]` key in Skills/ files.

**Secondary effects**: 86 gems have `secondaryGrantedEffectId` — resolves to another Skills/ key.
- Vaal gems: points to the companion non-vaal skill (e.g. VaalArc → Arc)
- Trigger supports/skills: points to the triggered sub-effect

**secondaryEffectName**: 8 gems have this field (display name for the secondary effect).

## Edge Cases

1. **Transfigured gems** (198 entries): key contains `AltX`/`AltY`/`AltZ`. The `gameId` points to the BASE gem (not the variant), while `grantedEffectId` is unique per variant.

2. **Vaal gems** (52 entries): have `vaalGem = true` and `secondaryGrantedEffectId` pointing to the non-vaal companion skill. In Skills/, vaal costs use `cost = { Soul = N }` with `vaalStoredUses` and `soulPreventionDuration`.

3. **Awakened support gems** (38 entries): have `awakened = true` tag, `naturalMaxLevel = 5`. In Skills/, they have `plusVersionOf` pointing to the base support.

4. **Active+Support hybrid gems** (9 entries): Shockwave, Predator, Impending Doom, Prismatic Burst, Flamewood, Sacred Wisps, Windburst, Kinetic Instability, Living Lightning. These are support gems that also grant an active skill effect.

5. **Hidden skills**: 626 of 1409 skill definitions have `hidden = true` — these are spectre, minion, item-granted, and tree-granted skills with no corresponding gem entry.
   - glove.lua: 60 hidden (enchantment procs)
   - minion.lua: 72 hidden
   - spectre.lua: 354 of 355 hidden
   - other.lua: 139 of 146 hidden (includes `fromItem = true` and `fromTree = true`)
   - act_dex.lua: 1 of 196 hidden

6. **Support-specific Skills/ fields**: `support = true`, `requireSkillTypes`, `addSkillTypes`, `excludeSkillTypes`, `manaMultiplier` (in levels instead of `cost`), `plusVersionOf` (awakened only).

7. **Level data structure**: Positional values in `levels[N] = { val1, val2, ... }` correspond 1:1 to the `stats[]` array. Named keys (levelRequirement, critChance, etc.) follow the positional values.
