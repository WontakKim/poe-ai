<!-- @generated gameVersion=3.27 pobCommit=fb6cd055 pobVersion=v2.60.0 -->
# Passive Tree — `src/TreeData/3_27/tree.lua`

Passive skill tree data for each game version. One `tree.lua` file per version containing all node definitions, group coordinates, class/ascendancy info, and constants.

## Version Registry

**Source**: `src/GameVersions.lua`

- **Latest version**: 3_27 (display: 3.27)
- **Total versions**: 35 (2_6, ..., 3_27)
- **Variants**: base, ruthless (3.22+), alternate (3.25+), ruthless_alternate (3.25+)

## tree.lua Structure (3_27)

**Path**: `src/TreeData/3_27/tree.lua` (87236 lines)

**Top-level sections**:
| Section | Line | Purpose |
|---------|------|---------|
| tree | 2 | Version identifier |
| classes | 3 | Character class definitions with ascendancies |
| alternate_ascendancies | 281 | Bloodline alternate ascendancy trees |
| groups | 439 | Node group spatial coordinates and orbits |
| nodes | 12063 | All passive skill node definitions |
| jewelSlots | 87132 | Jewel socket node IDs |
| constants | 87198 | Game constants (orbit radii, skills per orbit) |
| points | 87233 | Total and ascendancy passive points |

## Nodes

**Total**: 3287 nodes in 755 groups

### Node Type Breakdown

| Flag | Count | Description |
|------|-------|-------------|
| isKeystone | 54 | Powerful nodes with unique mechanics |
| isNotable | 975 | Mid-power named passives |
| isMastery | 349 | Selectable mastery effect nodes (3.19+) |
| isJewelSocket | 60 | Jewel insertion points |
| isAscendancyStart | 32 | Entry points to ascendancy subtrees |
| isProxy | 84 | Internal positioning markers (not displayed) |
| isBlighted | 30 | Oil-recipe passives |
| isBloodline | 122 | Alternate tree passives (3.25+) |
| isMultipleChoice | 12 | Multiple-choice parent nodes |
| isMultipleChoiceOption | 35 | Options within multiple-choice sets |

Note: Flags overlap — a node can have multiple flags (e.g. `isBloodline` + `isAscendancyStart`).

### Node Fields

All fields found on node entries:
DexClass,DexIntClass,Dexterity,IntClass,Intelligence,StrClass,StrDexClass,StrDexIntClass,StrIntClass,Strength,activeEffectImage,activeIcon,ascendancies,ascendancyName,background,base_dex,base_int,base_str,classStartIndex,expansionJewel,flavourText,flavourTextColour,flavourTextRect,grantedDexterity,grantedIntelligence,grantedPassivePoints,grantedStrength,group,icon,id,in,inactiveIcon,isAscendancyStart,isBlighted,isBloodline,isJewelSocket,isKeystone,isMastery,isMultipleChoice,isMultipleChoiceOption,isNotable,isProxy,masteryEffects,name,nodes,orbit,orbitIndex,orbits,out,recipe,reminderText,skill,stats,x,y

**Common fields** (present on most nodes): skill, name, icon, stats, group, orbit, orbitIndex, out, in

**Type flags**: isKeystone, isNotable, isMastery, isJewelSocket, isAscendancyStart, isProxy, isBlighted, isBloodline, isMultipleChoice, isMultipleChoiceOption

**Attribute grants**: grantedStrength, grantedDexterity, grantedIntelligence, grantedPassivePoints

**Mastery-specific**: inactiveIcon, activeIcon, activeEffectImage, masteryEffects

**Jewel socket**: expansionJewel (with size, index, proxy, parent sub-fields)

**Other**: ascendancyName, classStartIndex, flavourText, reminderText, recipe, root

### Mastery Effects

- **349** mastery nodes with **353** unique selectable effects
- Each mastery has an array of `masteryEffects`, each with `effect` (ID) and `stats` (array of stat lines)

### Stats

- **3512** unique stat line strings across all nodes

## Classes and Ascendancies

**7** base classes, each with ascendancy subclasses:

| Class | Str | Dex | Int | Ascendancies |
|-------|-----|-----|-----|--------------|
| Scion | 20 | 20 | 20 | Ascendant |
| Marauder | 32 | 14 | 14 | Juggernaut, Berserker, Chieftain |
| Ranger | 14 | 32 | 14 | Raider, Deadeye, Pathfinder |
| Witch | 14 | 14 | 32 | Occultist, Elementalist, Necromancer |
| Duelist | 23 | 23 | 14 | Slayer, Gladiator, Champion |
| Templar | 23 | 14 | 23 | Inquisitor, Hierophant, Guardian |
| Shadow | 14 | 23 | 23 | Assassin, Trickster, Saboteur |

### Nodes Per Ascendancy

| Ascendancy | Nodes |
|------------|-------|
| Ascendant | 50 |
| Saboteur | 23 |
| Raider | 23 |
| Assassin | 21 |
| Deadeye | 19 |
| Warlock | 18 |
| Necromancer | 18 |
| Hierophant | 17 |
| Elementalist | 17 |
| Champion | 16 |
| Chieftain | 16 |
| Berserker | 16 |
| Guardian | 16 |
| Gladiator | 15 |
| Warden | 15 |
| Juggernaut | 15 |
| Slayer | 15 |
| Trickster | 15 |
| Pathfinder | 15 |
| Inquisitor | 15 |
| Occultist | 15 |
| Primalist | 11 |
| Olroth | 10 |
| Farrul | 10 |
| Trialmaster | 8 |
| Aul | 8 |
| Delirious | 7 |
| KingInTheMists | 7 |
| Oshabi | 7 |
| Breachlord | 7 |
| Lycia | 7 |
| Catarina | 7 |

### Alternate Ascendancies

13 alternate ascendancy definitions in `["alternate_ascendancies"]`:

| ID | Name |
|---------|------|
| Warden | Warden of the Maji |
| Warlock | Warlock of the Mists |
| Primalist | Wildwood Primalist |
| Trialmaster | Chaos Bloodline |
| Oshabi | Oshabi Bloodline |
| KingInTheMists | Nameless Bloodline |
| Catarina | Catarina Bloodline |
| Aul | Aul Bloodline |
| Lycia | Lycia Bloodline |
| Olroth | Olroth Bloodline |
| Farrul | Farrul Bloodline |
| Delirious | Delirious Bloodline |
| Breachlord | Breachlord Bloodline |

These are bloodline-based alternate ascendancy trees (3.25+). Nodes belonging to alternate ascendancies have `isBloodline = true`.

## Groups

**755** node groups defining spatial layout.

Each group has:
- `x`, `y` — coordinates
- `orbits` — available orbit radius indices
- `nodes` — array of node IDs in this group
- `background` (optional) — `image`, `isHalfImage`

## Constants

```lua
    ["constants"]= {
        ["classes"]= {
            ["StrDexIntClass"]= 0,
            ["StrClass"]= 1,
            ["DexClass"]= 2,
            ["IntClass"]= 3,
            ["StrDexClass"]= 4,
            ["StrIntClass"]= 5,
            ["DexIntClass"]= 6
        },
        ["characterAttributes"]= {
            ["Strength"]= 0,
            ["Dexterity"]= 1,
            ["Intelligence"]= 2
        },
        ["PSSCentreInnerRadius"]= 130,
        ["skillsPerOrbit"]= {
            1,
            6,
            16,
            16,
            40,
            72,
            72
        },
        ["orbitRadii"]= {
            0,
            82,
            162,
            335,
            493,
            662,
            846
        }
    },
```

- `skillsPerOrbit`: max nodes per orbit ring [1, 6, 16, 16, 40, 72, 72]
- `orbitRadii`: pixel distances [0, 82, 162, 335, 493, 662, 846]
- `PSSCentreInnerRadius`: 130

## Points

- `totalPoints`: 123 (passive skill points available)
- `ascendancyPoints`: 8

## Jewel Slots

**60** jewel socket node IDs listed in top-level `jewelSlots` array.

## Historical Node Counts

| Version | Nodes |
|---------|-------|
| 3_10 | 2573 |
| 3_11 | 2681 |
| 3_12 | 2698 |
| 3_13 | 2706 |
| 3_14 | 2723 |
| 3_15 | 2734 |
| 3_16 | 2814 |
| 3_17 | 2816 |
| 3_18 | 2823 |
| 3_19 | 2831 |
| 3_20 | 2844 |
| 3_21 | 2919 |
| 3_22 | 2935 |
| 3_22_ruthless | 2935 |
| 3_23 | 2979 |
| 3_23_ruthless | 2979 |
| 3_24 | 2979 |
| 3_24_ruthless | 2979 |
| 3_25 | 3142 |
| 3_25_alternate | 3182 |
| 3_25_ruthless | 3142 |
| 3_25_ruthless_alternate | 3182 |
| 3_26 | 3159 |
| 3_26_alternate | 3182 |
| 3_26_ruthless | 3159 |
| 3_26_ruthless_alternate | 3182 |
| 3_27 | 3287 |
| 3_27_alternate | 3317 |
| 3_27_ruthless | 3287 |
| 3_27_ruthless_alternate | 3317 |

## Examples

### Keystone

```lua
        [58556]= {
            ["skill"]= 58556,
            ["name"]= "Divine Shield",
            ["icon"]= "Art/2DArt/SkillIcons/passives/EnergisedFortress.png",
            ["isKeystone"]= true,
            ["stats"]= {
                "Cannot Recover Energy Shield to above Armour\n3% of Physical Damage prevented from Hits Recently is Regenerated as Energy Shield per second"
            },
            ["reminderText"]= {
                "(Recently refers to the past 4 seconds)"
            },
            ["flavourText"]= {
                "My faith is my shield."
            },
            ["group"]= 76,
            ["orbit"]= 0,
            ["orbitIndex"]= 0,
            ["out"]= {
                "44202"
            },
            ["in"]= {}
        },
```

### Notable (non-ascendancy)

```lua
        [13164]= {
            ["skill"]= 13164,
            ["name"]= "Divine Judgement",
            ["icon"]= "Art/2DArt/SkillIcons/passives/CelestialPunishment.png",
            ["isNotable"]= true,
            ["recipe"]= {
                "SepiaOil",
                "TealOil",
                "BlackOil"
            },
            ["stats"]= {
                "50% increased Elemental Damage"
            },
            ["group"]= 63,
            ["orbit"]= 2,
            ["orbitIndex"]= 12,
            ["out"]= {
                "44298"
            },
            ["in"]= {
                "41251",
                "8198"
            }
        },
```

### Mastery (first 2 effects shown)

```lua
        [44298]= {
            ["skill"]= 44298,
            ["name"]= "Elemental Mastery",
            ["icon"]= "Art/2DArt/SkillIcons/passives/MasteryElementalDamage.png",
            ["isMastery"]= true,
            ["inactiveIcon"]= "Art/2DArt/SkillIcons/passives/MasteryPassiveIcons/PassiveMasteryElementalInactive.png",
            ["activeIcon"]= "Art/2DArt/SkillIcons/passives/MasteryPassiveIcons/PassiveMasteryElementalActive.png",
            ["activeEffectImage"]= "Art/2DArt/UIImages/InGame/PassiveMastery/MasteryBackgroundGraphic/MasteryElementalPattern.png",
            ["masteryEffects"]= {
                {
                    ["effect"]= 48385,
                    ["stats"]= {
                        "Exposure you inflict applies at least -18% to the affected Resistance"
                    }
                },
                {
                    ["effect"]= 4119,
                    ["stats"]= {
                        "60% reduced Reflected Elemental Damage taken"
                    }
                },
                {
                ...
            }
        },
```

### Jewel Socket

```lua
        [36931]= {
            ["skill"]= 36931,
            ["name"]= "Small Jewel Socket",
            ["icon"]= "Art/2DArt/SkillIcons/passives/MasteryBlank.png",
            ["isJewelSocket"]= true,
            ["expansionJewel"]= {
                ["size"]= 0,
                ["index"]= 0,
                ["proxy"]= "49951",
                ["parent"]= "17219"
            },
            ["stats"]= {},
            ["group"]= 35,
            ["orbit"]= 2,
            ["orbitIndex"]= 12,
            ["out"]= {},
            ["in"]= {
                "49951",
                "28018"
            }
        },
```

### Small (regular) Node

```lua
        [7092]= {
            ["skill"]= 7092,
            ["name"]= "Physical and Lightning Damage",
            ["icon"]= "Art/2DArt/SkillIcons/passives/DivineWrath.png",
            ["stats"]= {
                "8% increased Lightning Damage",
                "8% increased Physical Damage"
            },
            ["group"]= 63,
            ["orbit"]= 3,
            ["orbitIndex"]= 3,
            ["out"]= {
                "14665"
            },
            ["in"]= {
                "29061"
            }
        },
```

## Edge Cases

1. **Old format versions (2_6, 3_6-3_9)**: Compact/minified Lua — field names are abbreviated (`["oo"]`, `["n"]`). No `["skill"]=` field, so grep-based counting returns 0. Only versions 3.10+ use the expanded readable format.

2. **Alternate tree variants**: `{version}_alternate` directories contain the alternate ascendancy tree. These have additional bloodline nodes. See Historical Node Counts table for per-version comparison.

3. **Ruthless variants**: `{version}_ruthless` directories. Same base tree structure, may have different node values.

4. **Proxy nodes** (84): Internal positioning markers with `isProxy = true` and `name = "Position Proxy"`. Not displayed to players.

5. **Multiple choice sets**: Parent node has `isMultipleChoice = true`, children have `isMultipleChoiceOption = true`. Player must pick exactly one option. Used by Ascendant class and bloodline ascendancies.

6. **Blighted passives** (30): Have `recipe` field with 3 oil names for anointing.

7. **Stats with newlines**: Some stat strings contain `\n` for multi-line display (especially keystones).

8. **classStartIndex**: 7 nodes have this field — these are the starting nodes for each class on the tree.
