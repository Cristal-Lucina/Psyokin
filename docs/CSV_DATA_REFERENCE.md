# CSV DATA REFERENCE

## Table of Contents
1. [Overview](#overview)
2. [File Structure](#file-structure)
3. [Actors](#actors)
4. [Circles & Bonds](#circles--bonds)
5. [Combat](#combat)
6. [Dorms](#dorms)
7. [Items](#items)
8. [Progression](#progression)
9. [Skills & Sigils](#skills--sigils)
10. [World](#world)

---

## Overview

This document provides a comprehensive reference for all CSV data files currently in the Psyokin project. All CSV files are located in the `data/` directory and follow a consistent structure for easy parsing and modification.

**Location**: `data/`

**Total CSV Files**: 17

**Categories**:
- Actors (3 files) - Character and enemy definitions
- Circles (2 files) - Relationship and bond systems
- Combat (4 files) - Combat mechanics and status effects
- Dorms (2 files) - Dorm room configuration
- Items (1 file) - All game items
- Progression (1 file) - Enemy progression data
- Skills (3 files) - Sigils and skill definitions
- World (1 file) - World locations and activities

---

## File Structure

```
data/
├── actors/
│   ├── actors.csv              # Basic actor definitions (unused legacy)
│   ├── enemies.csv             # Enemy combatant definitions
│   └── party.csv               # Party member definitions
├── circles/
│   ├── circle_bonds.csv        # Relationship bonds configuration
│   └── circles_events.csv      # Circle event definitions
├── combat/
│   ├── burst_abilities.csv     # Burst attack definitions
│   ├── mind_types.csv          # Mind type system configuration
│   ├── status_effects.csv      # Status effects and ailments
│   └── test_ailment_items.csv  # Test items for status effects
├── dorms/
│   ├── affinity_power_config.csv  # Affinity bonus configuration
│   └── room_config.csv            # Dorm room layout
├── items/
│   └── items.csv               # All items (equipment, consumables, etc.)
├── progression/
│   └── enemy_defs.csv          # Simple enemy stat definitions (legacy)
├── skills/
│   ├── sigil_holder.csv        # Sigil level progression
│   ├── sigil_xp_table.csv      # XP requirements per tier
│   └── skills.csv              # Skill definitions per element
└── world/
    └── world_spots.csv         # World locations and activities
```

---

## Actors

### actors.csv
**Location**: `data/actors/actors.csv`

**Purpose**: Basic actor definitions (appears to be unused legacy file, superseded by party.csv)

**Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `actor_id` | String | Unique actor identifier |
| `name` | String | Display name |
| `level_start` | Int | Starting level |
| `start_brw` | Int | Starting BRW stat |
| `start_mnd` | Int | Starting MND stat |
| `start_tpo` | Int | Starting TPO stat |
| `start_vtl` | Int | Starting VTL stat |
| `start_fcs` | Int | Starting FCS stat |
| `start_weapon` | String | Starting weapon item ID |
| `start_armor` | String | Starting armor item ID |
| `start_head` | String | Starting head item ID |
| `start_foot` | String | Starting foot item ID |
| `start_bracelet` | String | Starting bracelet item ID |
| `start_sigils` | String (semicolon-separated) | Starting sigil IDs |
| `portrait` | String | Path to portrait image |
| `sprite` | String | Path to sprite resource |
| `join_to_active` | Boolean | Join active party on recruitment |
| `notes` | String | Developer notes |

**Example Entry**:
```csv
hero,Hero,1,2,1,2,2,1,,,,,,SIG_FIRE,portraits/hero.png,sprites/hero.tres,true,Main character (balanced STR/VIT/DEX)
```

---

### enemies.csv
**Location**: `data/actors/enemies.csv`

**Purpose**: Complete enemy combatant definitions for battle system

**Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `actor_id` | String | Unique enemy identifier |
| `name` | String | Display name |
| `level_start` | Int | Enemy level |
| `start_brw` | Int | BRW stat |
| `start_mnd` | Int | MND stat |
| `start_tpo` | Int | TPO stat (initiative) |
| `start_vtl` | Int | VTL stat (HP) |
| `start_fcs` | Int | FCS stat (MP) |
| `start_weapon` | String | Weapon item ID |
| `start_armor` | String | Armor item ID |
| `start_head` | String | Head item ID |
| `start_foot` | String | Foot item ID |
| `start_bracelet` | String | Bracelet item ID |
| `start_sigils` | String (semicolon-separated) | Equipped sigil IDs |
| `start_skills` | String (semicolon-separated) | Active skill IDs |
| `mind_type` | String | Mind type (Fire/Water/Earth/Air/Data/Void) |
| `portrait` | String | Portrait path |
| `sprite` | String | Sprite path |
| `dsi_brw` | Float | BRW stat scaling per level |
| `dsi_mnd` | Float | MND stat scaling per level |
| `dsi_tpo` | Float | TPO stat scaling per level |
| `dsi_vtl` | Float | VTL stat scaling per level |
| `dsi_fcs` | Float | FCS stat scaling per level |
| `item_drops` | String | Drop table ID |
| `cred_range` | String | Credit drop range (e.g., "10-20") |
| `boss_tag` | Boolean | Is boss enemy |
| `capture_tag` | String | Capture difficulty (Easy/Medium/Hard/None) |
| `capture_resist` | Int | Capture resistance % (0-60) |
| `env_tag` | String | Enemy tier (Regular/Elite/Boss) |

**Example Entry**:
```csv
slime,Slime,1,1,1,1,3,1,,,,,,,FIRE_L1,Water,,,0.5,0.5,0.5,1,0.5,drop_table_slime,10-20,FALSE,Easy,10,Regular
```

**Enemy Tiers**:
- **Regular**: Standard enemies, low rewards
- **Elite**: Stronger enemies, better rewards
- **Boss**: Major encounters, high rewards, often non-capturable

---

### party.csv
**Location**: `data/actors/party.csv`

**Purpose**: Party member definitions with combat stats and relationship data

**Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `actor_id` | String | Unique party member identifier |
| `name` | String | Display name |
| `level_start` | Int | Starting level |
| `start_brw` | Int | Starting BRW stat |
| `start_mnd` | Int | Starting MND stat |
| `start_tpo` | Int | Starting TPO stat |
| `start_vtl` | Int | Starting VTL stat |
| `start_fcs` | Int | Starting FCS stat |
| `mind_type` | String | Mind type |
| `start_weapon` | String | Starting weapon item ID |
| `start_armor` | String | Starting armor item ID |
| `start_head` | String | Starting head item ID |
| `start_foot` | String | Starting foot item ID |
| `start_bracelet` | String | Starting bracelet item ID |
| `start_sigils` | String (semicolon-separated) | Starting sigil IDs |
| `portrait` | String | Portrait path |
| `sprite` | String | Sprite path |
| `join_to_active` | Boolean | Join active party on recruitment |
| `notes` | String | Developer notes |
| `dsi_brw` | Float | BRW growth per level |
| `dsi_mnd` | Float | MND growth per level |
| `dsi_tpo` | Float | TPO growth per level |
| `dsi_vtl` | Float | VTL growth per level |
| `dsi_fcs` | Float | FCS growth per level |
| `burst_skill` | String | Burst skill ID |
| `bestie_buff` | String (semicolon-separated) | Actor IDs that provide buff |
| `rival_debuff` | String (semicolon-separated) | Actor IDs that provide debuff |

**Example Entry**:
```csv
secret_girl,Tessa,1,1,1,1,1,1,Air,,,,,,SIG_002,portraits/rhea.png,sprites/rhea.tres,TRUE,Mage archetype,1,3,2,2,2,,red_girl;scientist,ai_friend
```

**Relationship Mechanics**:
- `bestie_buff`: Nearby dorm rooms with these members grant bonuses
- `rival_debuff`: Nearby dorm rooms with these members grant penalties

---

## Circles & Bonds

### circle_bonds.csv
**Location**: `data/circles/circle_bonds.csv`

**Purpose**: Relationship bond progression system

**Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `actor_id` | String | Party member ID |
| `bond_name` | String | Display name for bond |
| `bond_layer` | Int | Current bond layer (0-4) |
| `love_interest` | Boolean | Romance option available |
| `poly_connects` | String (semicolon-separated) | Compatible poly relationships |
| `burst_unlocked` | Boolean | Burst attack unlocked |
| `gift_likes` | String | Preferred gift type |
| `gift_dislikes` | String | Disliked gift type |
| `bond_description` | String | Bond relationship description |
| `story_points` | String | Story progress markers |
| `reward_outer` | String | Layer 1 rewards |
| `reward_middle` | String | Layer 2 rewards |
| `reward_inner` | String | Layer 3 rewards |
| `reward_core` | String | Layer 4 rewards |
| `bond_hint` | String | Hint for progressing bond |

**Example Entry**:
```csv
secret_girl,Tessa,0,Yes,ai_friend;red_girl;scientist,No,tech,flowers,Mysterious ally with hidden agenda; trusts slowly.,Met; first hangout queued.,consumable:starter_pack;unlock:psyokin_growth_basic,passive:circle_bonus_or_discount,unlock:exclusive_mission_or_area;combat:assist_or_stance,perk:route_perk_final;flag:anchor_choice,Here is a hint for this bond.
```

**Bond Layers**:
- **Layer 0 (Outer)**: Initial meeting, basic rewards
- **Layer 1 (Middle)**: Developing friendship, passive bonuses
- **Layer 2 (Inner)**: Close bond, unlock exclusive content
- **Layer 3 (Core)**: Maximum bond, route-specific perks

**Gift Types**:
- `tech` - Technology items
- `flowers` - Flowers and plants
- `manga` - Books and manga
- `perfume` - Perfume and fragrances
- `ring` - Jewelry
- `chocolate` - Food and sweets
- `figurine` - Collectible figures

---

### circles_events.csv
**Location**: `data/circles/circles_events.csv`

**Purpose**: Circle hangout event definitions

**Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `event_id` | String | Unique event identifier |
| `circle_id` | String | Circle/character ID |
| `layer` | Int | Bond layer required |
| `phase_mask` | String | Valid phases (M/A/E = Morning/Afternoon/Evening) |
| `weekday_mask` | String | Valid weekdays |
| `locations` | String (pipe-separated) | Valid locations |
| `date_start` | String | Event availability start date |
| `date_end` | String | Event availability end date |
| `difficulty` | String | Difficulty tier (Normal/Hard) |
| `ggt_bonus_ep` | Int | Bonus EP for this event |
| `synergy_tags` | String | Synergy bonus tags |
| `pass_target_override` | Int | Override pass target |
| `gates_stats` | String (pipe-separated) | Stat requirements (e.g., "BRW>=2|FCS>=2") |
| `gates_items` | String | Item requirements |
| `gates_flags` | String | Flag requirements |
| `notes` | String | Developer notes |
| `is_bonus_date` | Boolean | Special bonus date |

**Example Entry**:
```csv
love_intro_01,love_red,1,MA,Mon,card_shop|dance_club,11-May,20-May,Normal,1,perfume,,BRW>=2|FCS>=2,,,First meet-up,0
```

**Phase Codes**:
- `M` - Morning
- `A` - Afternoon
- `E` - Evening
- `N` - Night

---

## Combat

### burst_abilities.csv
**Location**: `data/combat/burst_abilities.csv`

**Purpose**: Burst attack definitions (team super attacks)

**Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `burst_id` | String | Unique burst identifier |
| `name` | String | Display name |
| `participants` | String (semicolon-separated) | Required party members |
| `unlock_condition` | String | Unlock requirement |
| `burst_cost` | Int | Burst gauge cost |
| `type` | String | Burst type (Attack/Heal/Buff) |
| `element` | String | Elemental type |
| `target` | String | Target type (Enemies/Enemy/Allies) |
| `power` | Int | Base power |
| `acc` | Int | Accuracy % |
| `aoe` | Boolean | Area of effect |
| `crit_bonus_pct` | Int | Critical hit bonus % |
| `description` | String | Burst description |
| `tags` | String (semicolon-separated) | Burst tags |
| `scaling_brw` | Float | BRW scaling factor |
| `scaling_mnd` | Float | MND scaling factor |
| `scaling_fcs` | Float | FCS scaling factor |
| `status_apply` | String | Status effect to apply |
| `status_chance` | Int | Status application chance % |
| `duration` | Int | Status effect duration (rounds) |

**Example Entry**:
```csv
BURST_HERO_SOLO,Psychic Pulse,hero,always,50,Attack,Void,Enemies,120,95,1,15,Unleash raw psychic energy in all directions.,Burst;AoE,0.5,1,0.5,Stagger,40,2
```

**Burst Tiers**:
- **Solo Burst**: 1 participant, 25-50 gauge cost
- **Duo Burst**: 2 participants, 70-85 gauge cost, affinity tier 2+ required
- **Trio Burst**: 3 participants, 95-100 gauge cost, affinity tier 4+ required
- **Ultimate Burst**: 4 participants, 150 gauge cost, affinity tier 6+ required

---

### mind_types.csv
**Location**: `data/combat/mind_types.csv`

**Purpose**: Mind type system configuration (elemental advantages)

**Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `mind_type_id` | String | Type identifier |
| `name` | String | Display name |
| `allowed_schools` | String (semicolon-separated) | Schools this type can use |
| `weak_to` | String | Type this is weak against |
| `resist_to` | String | Type this resists |
| `desc` | String | Description |

**Example Entry**:
```csv
Fire,Fire,Fire;Normal,Water,Air,Hot-headed attunement.
```

**Type Relationships**:
```
Fire > Air > Earth > Water > Fire (cycle 1)
Data > Void > Data (cycle 2)
Omega = neutral to all
```

**Damage Modifiers**:
- Weakness: ×1.25 damage
- Resistance: ×0.75 damage
- Neutral: ×1.0 damage

---

### status_effects.csv
**Location**: `data/combat/status_effects.csv`

**Purpose**: Status effect and ailment definitions

**Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `effect_id` | String | Unique effect identifier |
| `category` | String | Category (ailment/buff/debuff) |
| `name` | String | Display name |
| `default_duration` | Int | Default duration in rounds |
| `magnitude` | Int | Effect magnitude (%) |
| `description` | String | Effect description |

**Example Entry**:
```csv
poison,ailment,Poison,0,5,DoT 5% MaxHP/turn
```

**Categories**:
- **Ailments**: Negative status effects (poison, burn, sleep, etc.)
- **Buffs**: Positive status effects (attack up, regen, haste, etc.)
- **Debuffs**: Enemy-applied negative effects (attack down, defense down, etc.)

**Notable Effects**:
- **Poison/Burn**: 5% max HP damage per turn
- **Sleep/Freeze**: Cannot act
- **Berserk**: Only basic attacks, +50% ATK damage
- **Malaise**: Stat penalties
- **Regen**: Heal 5% max HP per turn
- **Attack Up/Mind Up**: +25% damage
- **Protect/Shell**: +25% physical/magical defense

---

### test_ailment_items.csv
**Location**: `data/combat/test_ailment_items.csv`

**Purpose**: Test items for status effects and debugging

**Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `item_id` | String | Test item identifier |
| `name` | String | Display name |
| `category` | String | Category (Test/Cure/Buff/Debuff/Bomb) |
| `use_type` | String | Usage context (battle/both) |
| `targeting` | String | Target type (Any/Ally/Enemy) |
| `battle_status_effect` | String | Status effect to apply |
| `round_duration` | Int | Effect duration |
| `mind_type_tag` | String | Element tag |
| `short_description` | String | Item description |

**Example Entry**:
```csv
TEST_POISON,Test Poison Vial,Test,battle,Any,Poison,99,none,Inflict poison (8% HP/turn 30%+10%/turn cure)
```

**Test Item Categories**:
- **Status Ailment Test Items**: Apply ailments for testing
- **Cure Items**: Remove specific ailments
- **Buff Items**: Apply temporary buffs (3 rounds)
- **Debuff Test Items**: Apply debuffs for testing
- **Bomb Items**: Deal 50 AOE damage by element

---

## Dorms

### affinity_power_config.csv
**Location**: `data/dorms/affinity_power_config.csv`

**Purpose**: Affinity bonus configuration for dorm room neighbors

**Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `affinity_level` | Int | Net affinity level (-3 to 5) |
| `roll_bonus` | Int | Dice roll bonus/penalty |
| `description` | String | Affinity situation description |

**Example Entry**:
```csv
3,4,Three besties as neighbors
```

**Affinity Levels**:
- **-3**: Three rivals as neighbors (-4 penalty)
- **-2**: Two rivals and one neutral (-2 penalty)
- **-1**: One rival and two neutrals (-1 penalty)
- **0**: All neutral neighbors (no bonus)
- **+1**: Mixed besties and rivals (+1 bonus)
- **+2**: Two besties and one neutral (+2 bonus)
- **+3**: Three besties as neighbors (+4 bonus)
- **+4**: Three besties + AT2 battle affinity (+8 bonus)
- **+5**: Three besties + AT3 battle affinity (+10 bonus, MAX)

**Usage**: Determines bonus for mini-game rolls based on dorm room placement

---

### room_config.csv
**Location**: `data/dorms/room_config.csv`

**Purpose**: Dorm room layout and neighbor configuration

**Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `room_id` | String | Unique room identifier |
| `room_name` | String | Display name |
| `description` | String | Room description |
| `neighbors` | String (semicolon-separated) | Adjacent room IDs |
| `floor` | Int | Floor number |
| `position` | String | Position label |

**Example Entry**:
```csv
301,Corner Room A,Cozy corner room with windows on two sides,302;305,3,top_left
```

**Floor 3 Layout**:
```
[301]─[302]─[303]─[304]
  │     │     │     │
[305]─[306]─[307]─[308]
```

**Room Types**:
- **Corner Rooms**: 2 neighbors (301, 304, 305, 308)
- **Central Rooms**: 3 neighbors (302, 303, 306, 307)

---

## Items

### items.csv
**Location**: `data/items/items.csv`

**Purpose**: Complete item database (equipment, consumables, materials, gifts, key items)

**Columns** (47 total):
| Column | Type | Description |
|--------|------|-------------|
| `item_id` | String | Unique item identifier |
| `name` | String | Display name |
| `category` | String | Item category |
| `equip_slot` | String | Equipment slot (if equippable) |
| `rarity` | String | Rarity tier |
| `icon` | String | Icon path |
| `buy_price` | Int | Purchase price |
| `sell_price` | Int | Sell price |
| `shop_tier` | Int | Shop tier availability |
| `sellable` | Boolean | Can be sold |
| `stack_max` | Int | Maximum stack size |
| `drop_source` | String | Drop source |
| `notes` | String | Developer notes |
| `short_description` | String | Short description |
| `full_description` | String | Full description |
| `mind_type_tag` | String | Element tag |
| `watk_type_tag` | String | Weapon attack type (slash/pierce/impact/wand) |
| `armor_flat` | Int | Physical defense (armor) |
| `ward_flat` | Int | Magic defense (armor) |
| `max_hp_boost` | Int | HP boost (headwear) |
| `max_mp_boost` | Int | MP boost (headwear) |
| `ail_resist_pct` | Int | Ailment resistance % |
| `mind_type_resists` | String | Specific type resistances |
| `base_eva` | Int | Evasion stat (footwear) |
| `speed` | Int | Speed stat (footwear) |
| `base_watk` | Int | Weapon attack power |
| `base_acc` | Int | Weapon accuracy |
| `crit_bonus_pct` | Int | Critical bonus % |
| `scale_brw` | Float | BRW scaling factor |
| `skill_acc_boost` | Int | Skill accuracy boost |
| `non_lethal` | Boolean | Non-lethal weapon |
| `sigil_slots` | Int | Sigil slots (bracelet) |
| `sigil_school` | String | Sigil school restriction |
| `equip_req_perk` | String | Required perk |
| `equip_req_stats` | String | Required stats |
| `set_id` | String | Equipment set ID |
| `use_type` | String | Usage context (battle/field/both) |
| `targeting` | String | Target type |
| `cooldown` | Int | Cooldown (rounds) |
| `uses_per_battle` | Int | Uses per battle limit |
| `battle_status_effect` | String | Status effect to apply |
| `field_status_effect` | String | Field status effect |
| `round_duration` | Int | Effect duration |
| `capture_type` | String | Capture bind type |
| `stat_boost` | String | Stat boost effect |
| `lvl_boost` | Int | Level boost (XP items) |
| `flags` | String | Special flags |
| `upgrade_of` | String | Item this upgrades from |
| `upgrade_step` | Int | Upgrade tier |
| `upgrade_input` | String | Upgrade materials |
| `craft_input` | String | Crafting materials |
| `craft_output` | String | Crafting result |
| `gift_type` | String | Gift category for relationships |

**Item Categories**:
- **Weapons**: Equippable weapons (slash/pierce/impact/wand)
- **Armor**: Body armor (physical + magical defense)
- **Headwear**: Head slot (HP/MP boost)
- **Footwear**: Foot slot (evasion + speed)
- **Bracelets**: Bracelet slot (sigil holders)
- **Sigils**: Equippable sigils (elemental skills)
- **Consumables**: Healing, buffs, stat boosts
- **Bindings**: Capture items (40-70% capture rate boost)
- **Materials**: Crafting materials
- **Gifts**: Relationship gifts
- **Key**: Story-critical key items

**Example Entries**:

**Weapon**:
```csv
WEA_001,Bokken,Weapons,Weapon,Common,null,100,50,1,TRUE,1,shop_start,Starter gear,"Simple wooden practice sword","A wooden practice sword used for training.",none,slash,null,null,null,null,null,null,null,null,3,80,null,1,null,FALSE,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,Starter,null,null,null,null,null,null
```

**Consumable**:
```csv
CON_001,Health Drink,Consumables,none,Common,null,30,15,1,TRUE,99,null,Basic heal.,Restores a bit of health.,A basic sports drink that restores 50 HP to one ally.,none,null,null,null,null,null,null,null,null,null,null,null,null,null,null,FALSE,null,null,null,null,null,both,Ally,null,null,Heal 50 HP,Heal 50 HP,1,null,null,null,null,null,null,null,null,null,null
```

**Bind**:
```csv
BIND_001,Basic Bind,Bindings,none,Common,null,200,100,1,TRUE,99,Tech Lab,Basic capture bind.,Capture enemies (low rate).,A basic energy bind that captures weakened enemies. Adds +40% to capture rate.,none,null,null,null,null,null,null,null,null,null,null,null,null,null,null,TRUE,null,null,null,null,null,battle,Enemy,null,null,Capture Attempt,null,1,null,40,null,null,null,null,null,null,null,null
```

---

## Progression

### enemy_defs.csv
**Location**: `data/progression/enemy_defs.csv`

**Purpose**: Simple enemy stat definitions (legacy, superseded by actors/enemies.csv)

**Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `enemy_id` | String | Enemy identifier |
| `name` | String | Display name |
| `hp` | Int | Hit points |
| `atk` | Int | Attack power |
| `def` | Int | Defense |
| `exp` | Int | Experience reward |
| `notes` | String | Developer notes |

**Example Entry**:
```csv
slime,Slime,10,3,0,5,Basic slime
```

**Note**: This file appears to be an early prototype and is likely unused in favor of the more complete `actors/enemies.csv`.

---

## Skills & Sigils

### sigil_holder.csv
**Location**: `data/skills/sigil_holder.csv`

**Purpose**: Sigil level progression and skill unlocks

**Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `sigil_id` | String | Sigil identifier |
| `lv1` | String | Level 1 skill ID |
| `lv2` | String | Level 2 skill ID |
| `lv3` | String | Level 3 skill ID |
| `lv4` | String | Level 4 skill ID |

**Example Entry**:
```csv
SIG_001,FIRE_L1,FIRE_L2,FIRE_L3,FIRE_L4
```

**Sigil Types**:
- `SIG_001`: Fire Sigil (FIRE_L1 → FIRE_L4)
- `SIG_002`: Water Sigil (WATER_L1 → WATER_L4)
- `SIG_003`: Earth Sigil (EARTH_L1 → EARTH_L4)
- `SIG_004`: Air Sigil (AIR_L1 → AIR_L4)
- `SIG_005`: Void Sigil (VOID_L1 → VOID_L4)
- `SIG_006`: Data Sigil (DATA_L1 → DATA_L4)

**Level Progression**: Sigils gain XP from battle and unlock stronger skills at levels 2, 3, and 4.

---

### sigil_xp_table.csv
**Location**: `data/skills/sigil_xp_table.csv`

**Purpose**: XP requirements for sigil level progression by tier

**Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `tier` | Int | Sigil tier (1-3) |
| `lv2_xp` | Int | XP required for level 2 |
| `lv3_xp` | Int | XP required for level 3 |
| `lv4_xp` | Int | XP required for level 4 |

**Example Entry**:
```csv
1,50,150,300
```

**Tier Progression**:
- **Tier 1**: 50 → 150 → 300 XP
- **Tier 2**: 75 → 200 → 400 XP
- **Tier 3**: 100 → 250 → 500 XP

**XP Gain**: Sigils gain XP from:
- Participating in battle (base GXP)
- Using skills in battle (+5 GXP bonus)

---

### skills.csv
**Location**: `data/skills/skills.csv`

**Purpose**: Skill definitions for all elements and levels

**Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `skill_id` | String | Unique skill identifier |
| `name` | String | Display name |
| `school` | String | Elemental school |
| `type` | String | Skill type (Attack/Heal/Buff/Debuff) |
| `element` | String | Element (fire/water/earth/air/void/data) |
| `target` | String | Target type (Enemy/Enemies/Ally/Allies) |
| `power` | Int | Base power |
| `acc` | Int | Accuracy % |
| `cost_mp` | Int | MP cost |
| `cooldown` | Int | Cooldown (rounds) |
| `uses_per_battle` | Int | Uses per battle limit |
| `aoe` | Boolean | Area of effect |
| `crit_bonus_pct` | Int | Critical bonus % |
| `notes` | String | Developer notes |
| `tags` | String (semicolon-separated) | Skill tags |
| `scaling_brw` | Float | BRW scaling factor |
| `scaling_mnd` | Float | MND scaling factor |
| `scaling_fcs` | Float | FCS scaling factor |
| `status_apply` | String | Status effect to apply |
| `status_chance` | Int | Status application chance % |
| `duration` | Int | Status duration (rounds) |

**Example Entry**:
```csv
FIRE_L1,Fire Bolt,Fire,Attack,fire,Enemy,30,90,6,0,0,0,0,Basic single-target fire.,Burn,0,1,0,Burn,20,3
```

**Skill Levels**:
- **L1**: Single target, 30 power, 6 MP
- **L2**: AOE, 40 power, 10 MP
- **L3**: Single target, 65 power, 14 MP, +5% crit
- **L4**: AOE, 95 power, 20 MP, +10% crit

**Elemental Schools**:
- **Fire**: Applies Burn (DoT)
- **Water**: Applies Confuse
- **Earth**: Applies Defense Down
- **Air**: Applies Charm
- **Void**: Applies Malaise
- **Data**: Applies Mind Block

---

## World

### world_spots.csv
**Location**: `data/world/world_spots.csv`

**Purpose**: World location definitions for activities and stat training

**Columns**:
| Column | Type | Description |
|--------|------|-------------|
| `spot_id` | String | Unique location identifier |
| `name` | String | Display name |
| `phase` | String | Valid time phases (M/A/E/N) |
| `location_id` | String | World location ID |
| `base_sxp` | Int | Base stat XP reward |
| `stats` | String (semicolon-separated) | Stats trained |
| `tags` | String (pipe-separated) | Location tags |
| `first_time_bonus` | Int | First visit bonus multiplier |
| `weekend_bonus` | Int | Weekend bonus multiplier |
| `tournament_bonus` | Int | Tournament bonus multiplier |
| `cred_payout` | String (semicolon-separated) | Credit rewards (min;max) |
| `gates` | String | Gate requirements (7-bit flag string) |
| `notes` | String | Developer notes |
| `start_date` | String | Availability start date |
| `end_date` | String | Availability end date |
| `track` | String | Stat track type |

**Example Entry**:
```csv
ARC_MORNING,Arcade Training (AM),M/A/E,DOWNTOWN,6,BRW;FCS,Arcade|Fun,1,0,0,10;25,-;-;-;1100000,Test AM,05/11,05/20,Dex
```

**Phase Codes**:
- `M` - Morning
- `A` - Afternoon
- `E` - Evening
- `N` - Night

**Stat Tracks**:
- **Dex**: BRW + FCS (physical dexterity)
- **Mind**: MND + FCS (mental focus)
- **Rand**: Random stat selection

**Gate Flags** (7-bit binary string):
- Position 0: Gate 1
- Position 1: Gate 2
- Position 2: Gate 3
- Position 3: Gate 4
- Position 4: Gate 5
- Position 5: Gate 6
- Position 6: Gate 7

**Example**: `1100000` means Gates 1 and 2 are required

---

## Summary

This reference covers all 17 CSV files currently in the Psyokin data directory:

**By System**:
- **Character & Enemy Data**: 3 files (actors, enemies, party)
- **Relationship System**: 2 files (bonds, circle events)
- **Combat Mechanics**: 4 files (bursts, types, status, test items)
- **Dorm System**: 2 files (affinity config, room layout)
- **Items & Equipment**: 1 comprehensive file
- **Progression**: 1 legacy file
- **Skills & Sigils**: 3 files (skills, sigil holders, XP table)
- **World & Activities**: 1 file

**Data-Driven Design**:
All systems use CSV files for easy content editing without code changes. This approach enables:
- Rapid iteration on game balance
- Easy content expansion
- Localization support (dialogue CSVs)
- Designer-friendly data entry
- Version control friendly (line-by-line diffs)

**Next Steps**:
Refer to `EVENT_DIALOGUE_SYSTEM.md` for the planned CSV expansion including:
- Event system CSVs
- Dialogue CSVs (multi-language)
- NPC schedule CSVs
- Mission CSVs
- Shop progression CSVs
