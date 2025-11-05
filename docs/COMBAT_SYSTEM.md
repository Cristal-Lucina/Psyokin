# COMBAT SYSTEM DOCUMENTATION

## Table of Contents
1. [Overview](#overview)
2. [System Architecture](#system-architecture)
3. [Combat Flow](#combat-flow)
4. [Combatant Data Structure](#combatant-data-structure)
5. [Initiative & Turn Order](#initiative--turn-order)
6. [Actions](#actions)
7. [Minigames](#minigames)
8. [Damage Calculation](#damage-calculation)
9. [Hit & Evasion](#hit--evasion)
10. [Critical Hits](#critical-hits)
11. [Type Systems](#type-systems)
12. [Status Effects & Ailments](#status-effects--ailments)
13. [Buffs & Debuffs](#buffs--debuffs)
14. [Burst Gauge System](#burst-gauge-system)
15. [Capture Mechanics](#capture-mechanics)
16. [Rewards & Experience](#rewards--experience)
17. [HP/MP Persistence](#hpmp-persistence)
18. [Morality Integration](#morality-integration)

---

## Overview

Psyokin uses a **turn-based combat system** inspired by classic JRPGs with modern mechanics. Combat features:
- **Turn order** based on initiative rolls using TPO (Tempo) stat
- **8-slot roster**: 3 allies vs up to 5 enemies
- **Interactive minigames** for attacks, skills, and bursts (skill-based action combat)
- **Mind type** effectiveness (9 types + Omega/Neutral)
- **Weapon triangle** system (Pierce > Slash > Blunt > Pierce)
- **Capture system** for non-lethal combat (affects morality)
- **Burst gauge** for powerful team-based attacks
- **Status ailments** and **buff/debuff** management
- **HP/MP persistence** between battles

---

## System Architecture

### Core Components

| Component | Path | Purpose |
|-----------|------|---------|
| **BattleManager** | `/root/aBattleManager` | Core combat controller - manages turns, rounds, combatants, and battle state |
| **Battle.gd** | `scenes/battle/Battle.tscn` | UI scene for battle display, player input, and visual presentation |
| **CombatResolver** | Child of Battle.gd | Damage calculation engine - implements all combat formulas |
| **MinigameManager** | `/root/aMinigameManager` | Coordinates all battle minigames - launches and handles results |
| **CombatProfileSystem** | `/root/aCombatProfileSystem` | Manages combatant stats, HP/MP, and equipment-derived values |
| **GameState** | `/root/aGameState` | Stores HP/MP persistence and party roster |
| **StatsSystem** | `/root/aStatsSystem` | Base stats (BRW, VTL, TPO, FCS, MND) and leveling |
| **EquipmentSystem** | `/root/aEquipmentSystem` | Weapon, armor, head, foot, bracelet gear |
| **SigilSystem** | `/root/aSigilSystem` | Sigils (equipable skills) and active skill selection |

### Dependency Flow
```
Battle.gd (UI/Input)
    ↓
BattleManager (Turn Logic)
    ↓
CombatResolver (Formulas)
    ↓
CombatProfileSystem (Stats)
    ↓
StatsSystem + EquipmentSystem + SigilSystem
```

---

## Combat Flow

### Battle Initialization

1. **Trigger**: `BattleManager.start_random_encounter(enemy_ids, return_scene)`
2. **Scene Transition**: Transitions to `Battle.tscn` via TransitionManager
3. **Combatant Setup**: `BattleManager.initialize_battle(ally_party, enemy_list)`
   - Creates ally combatants from party roster (max 3: hero + 2 active members)
   - Creates enemy combatants from CSV definitions
   - Loads HP/MP from `GameState.member_data` for allies
   - Loads equipment and sigils
4. **Battle Start**: Emits `battle_started` signal
5. **Round 1**: Calls `start_round()`

### Round Structure

Each round follows this sequence:

```
1. ROUND_START
   ├── Increment round number
   ├── Roll initiative for all combatants
   ├── Sort combatants by initiative (highest → lowest)
   ├── Add cleanup turn at end
   ├── Process round-start effects:
   │   ├── Reset has_acted_this_round flags
   │   ├── Reset weapon_weakness_hits counters
   │   ├── Reset changed_type_this_round flags
   │   ├── Decrement buff/debuff durations
   │   └── Apply HoT (Heal over Time) effects
   ├── Emit round_started signal
   └── Wait for turn order animation

2. TURN_ACTIVE (for each combatant)
   ├── Process turn-start ailment effects (Poison/Burn damage, auto-cure rolls)
   ├── Check for KO from ailment damage
   ├── Process buff/debuff durations
   ├── Apply regeneration buffs
   ├── Emit turn_started signal
   ├── [Player input OR AI decision]
   ├── Execute action
   ├── Check for battle end
   └── Emit turn_ended signal

3. ROUND_END
   ├── Check victory/defeat conditions
   ├── Pause 0.5 seconds
   └── Start next round

4. BATTLE_END (Victory or Defeat)
   ├── Calculate rewards (LXP, GXP, AXP, Creds, Items)
   ├── Apply morality deltas for kills/captures
   ├── Save HP/MP to GameState.member_data
   ├── Clear status effects (buffs, debuffs, ailments)
   ├── Emit battle_ended signal
   └── Return to overworld
```

### Turn Skipping Rules

A combatant's turn is **skipped** if:
- **KO'd** (`is_ko == true`)
- **Fled** (`is_fled == true`)
- **Captured** (`is_captured == true` for enemies)
- **Fallen** (`is_fallen == true`) - skip NEXT turn after becoming Fallen
- **Revived** (`ailment == "revived"`) - skip turn to recover from revival
- **Already acted** (`has_acted_this_round == true`)

---

## Combatant Data Structure

Each combatant (ally or enemy) is a Dictionary with these fields:

```gdscript
{
    # Identity
    "id": String,                  # Unique ID (member_id for allies, "enemy_0", "enemy_1" for enemies)
    "display_name": String,        # Display name
    "is_ally": bool,               # true = player party, false = enemy
    "slot": int,                   # Position in battle (0-2 for allies, 0-4 for enemies)
    "level": int,                  # Character level

    # Stats (Dictionary)
    "stats": {
        "BRW": int,    # Brawn - Physical attack scaling
        "VTL": int,    # Vitality - HP, physical evasion
        "TPO": int,    # Tempo - Initiative, crit chance, hit/eva bonus
        "FCS": int,    # Focus - MP, sigil evasion
        "MND": int,    # Mind - Sigil damage scaling
        "Speed": int   # From footwear - initiative bonus
    },

    # HP/MP Pools
    "hp": int,         # Current HP
    "hp_max": int,     # Maximum HP (30 + VTL × Level × 6)
    "mp": int,         # Current MP
    "mp_max": int,     # Maximum MP (20 + FCS × Level × 1.5)

    # Initiative
    "initiative": int,  # Rolled each round (XdY + Speed + buffs)

    # Status Flags
    "is_ko": bool,         # Knocked out (HP = 0)
    "is_fled": bool,       # Fled from battle
    "is_fallen": bool,     # Weapon weakness: skip next turn
    "fallen_round": int,   # Round when became Fallen
    "is_defending": bool,  # Defend stance (30% damage reduction)
    "is_channeling": bool, # Channeling a skill
    "channel_data": {},    # Skill being channeled
    "has_acted_this_round": bool,  # Already took action this round

    # Equipment (Dictionary)
    "equipment": {
        "weapon": String,    # Weapon item ID
        "armor": String,     # Armor item ID
        "head": String,      # Head item ID (headgear)
        "foot": String,      # Foot item ID (footwear)
        "bracelet": String   # Bracelet item ID (sigil holder)
    },

    # Sigils & Skills
    "sigils": Array[String],  # Equipped sigil instance IDs
    "skills": Array[String],  # Active skill IDs for each sigil

    # Buffs/Debuffs (Arrays of Dictionaries)
    "buffs": [
        {"type": String, "value": float, "duration": int}
        # Examples: "atk_up", "def_up", "regen", "phys_acc", "evasion"
    ],
    "debuffs": [
        {"type": String, "value": float, "duration": int}
        # Examples: "atk_down", "def_down", "spd_down"
    ],

    # Ailments (String)
    "ailment": String,  # Current ailment: "poison", "burn", "sleep", "freeze",
                        # "malaise", "berserk", "charm", "fainted", "revived", ""
    "ailment_turn_count": int,  # Turns afflicted with current ailment

    # Mind Type
    "mind_type": String,  # Mind type: "Fire", "Water", "Earth", "Air", "Data", "Void",
                          # "Omega", "none"

    # Combat Tracking
    "weapon_weakness_hits": int,  # Weapon triangle hits this round (Fallen at 2)
    "changed_type_this_round": bool,  # Player can change type once per round

    # Enemy-Specific Fields
    "is_captured": bool,       # Captured via Bind item
    "is_boss": bool,           # Boss enemy flag
    "capture_difficulty": String,  # "None", "Easy", "Medium", "Hard", "VeryHard"
    "capture_resist": int,     # 0-60 resistance to capture
    "env_tag": String,         # "Regular", "Elite", "Boss" (for morality)
    "cred_range": String,      # Credit drop range (e.g., "10-20")
    "drop_table": String       # Item drop table ID
}
```

---

## Initiative & Turn Order

### Initiative Roll Formula

Each round, every combatant rolls initiative:

```
Initiative = BestRoll(XdY) + Speed + SpeedBuffs

Where:
- X = dice count based on TPO tier:
    - TPO ≥ 10: Roll 4d20, keep highest
    - TPO ≥ 7:  Roll 3d20, keep highest
    - TPO ≥ 4:  Roll 2d20, keep highest
    - TPO < 4:  Roll 1d20
- Y = 20 (d20)
- Speed = Footwear speed stat
- SpeedBuffs = Sum of spd_up/spd_down buff modifiers
```

### Turn Order Sorting

Combatants are sorted **highest initiative first** with these priority rules:

1. **Normal combatants** (not KO'd, not Fallen) → highest initiative
2. **Fallen combatants** (will skip turn but still sorted)
3. **KO'd combatants** → bottom (initiative = -1)

**Tiebreakers** (in order):
1. TPO (higher first)
2. Speed stat (higher first)
3. Coin flip

**Special**: A **cleanup turn** is added at the end (initiative = -999) to ensure round always ends properly.

---

## Actions

### Available Actions

| Action | Input | Description |
|--------|-------|-------------|
| **Attack** | A button | Basic physical attack with equipped weapon |
| **Skill** | X button | Use a sigil skill (costs MP) |
| **Item** | Y button | Use a consumable item (healing, buffs, etc.) |
| **Defend** | B button | Reduce incoming damage by 30% until next action |
| **Capture** | LB button | Use Bind item to capture enemy non-lethally |
| **Burst** | RB button | Powerful team attack (costs Burst Gauge) |
| **Run** | Start | Attempt to flee battle (20% base chance) |
| **Status** | Select | View detailed combatant stats and buffs |

### Attack Action

**Flow**:
1. Select enemy target
2. Check hit (Weapon ACC + 0.25×TPO vs Footwear EVA + 0.15×VTL)
3. Check critical (Base 5% + TPO×0.15% + Weapon Crit Bonus)
4. Calculate damage (see Damage Calculation section)
5. Check weapon weakness (weapon triangle)
6. Apply damage and effects
7. Add Burst Gauge (+5 on hit, +2 on miss)

**Weapon Weakness**: If attacker's weapon beats defender's weapon in triangle:
- Deal +25% damage (Stumble modifier)
- Target gains 1 weapon_weakness_hit
- Target's initiative reduced by 5
- Turn order re-sorted
- If target reaches 2 hits this round → **Fallen** (skip next turn)

### Skill Action

**Flow**:
1. Open skill menu (shows equipped sigils' active skills)
2. Select skill
3. Check MP cost
4. Select target(s)
5. Check hit (Skill ACC + Weapon Skill Boost + 0.25×TPO vs Footwear EVA + 0.15×FCS)
6. Check critical (if skill allows)
7. Calculate damage (see Damage Calculation section)
8. Apply skill effects (damage, healing, buffs, ailments)
9. Deduct MP cost
10. Add Burst Gauge (+10 on hit, +5 on miss)

**Skill Types**:
- **Damage**: Deals sigil damage to enemies
- **Healing**: Restores HP to allies
- **Buff**: Applies buffs (atk_up, def_up, regen, etc.)
- **Debuff**: Applies debuffs to enemies
- **Ailment**: Inflicts status ailments (poison, sleep, etc.)
- **Multi-Hit**: Hits multiple times (defense scaled by √H)

### Item Action

**Flow**:
1. Open item menu (categorized tabs: Healing, Status, Combat, KeyItems)
2. Select item
3. Check if usable in battle
4. Select target (if needed)
5. Apply item effect
6. Consume item (decrease inventory count)
7. Add Burst Gauge (+5)

**Item Categories**:
- **Healing**: Restore HP/MP (Energy Drink, Potion, Ether, etc.)
- **Status**: Cure ailments (Antidote, Thaw Blanket, Smelling Salts, etc.)
- **Combat**: Buff/debuff items (Eye Drops, Focus Tonic, Shield Orb, etc.)
- **Bind**: Capture items (Basic Bind, Intermediate Bind, Advanced Bind, Expert Bind, Master Bind)

### Defend Action

**Flow**:
1. Set `is_defending = true` on combatant
2. Incoming damage reduced by 30% until combatant takes offensive action
3. Defend persists across rounds until combatant attacks/uses skill
4. Add Burst Gauge (+3)

**Notes**:
- Defending does NOT consume a turn
- Useful for low HP allies or when waiting for MP to regenerate
- Can be combined with Shield Orb for even higher defense

### Capture Action

**Flow**:
1. Open capture menu (shows available Bind items)
2. Select Bind item tier
3. Select enemy target
4. Calculate capture chance (see Capture Mechanics section)
5. Roll capture attempt
6. If success:
   - Enemy marked as `is_captured = true`
   - Enemy removed from battle
   - Record capture for morality (+1 Regular, +3 Elite, +15 Boss)
   - Add Burst Gauge (+20)
7. If failure:
   - Bind item consumed anyway
   - Add Burst Gauge (+5)

### Burst Action

**Flow**:
1. Open burst menu (shows available burst tiers based on gauge level)
2. Select burst tier (Single/Duel/Omega)
3. Select participants (Duel = 2, Omega = 3)
4. Spend burst gauge
5. Launch minigame (timing-based button presses)
6. Calculate damage based on minigame performance
7. Apply massive damage to all enemies

**Burst Tiers**:
- **Single Burst**: 25 gauge, 1 character, hits all enemies
- **Duel Burst**: 55 gauge, 2 characters, hits all enemies + bonus
- **Omega Burst**: 90 gauge, 3 characters, hits all enemies + massive bonus

### Run Action

**Flow**:
1. Calculate run chance: `Base 20% + (RunAttempts × 10%)`
2. Roll attempt
3. If success:
   - Battle ends (no rewards)
   - Return to overworld
4. If failure:
   - Increment run attempt counter
   - Turn ends
   - Add Burst Gauge (+2)

**Notes**:
- Can only attempt once per round
- Some battles have `no_escape = true` (boss battles)
- Run chance caps at 90%

---

## Minigames

Psyokin features **interactive minigames** for most combat actions, adding a skill-based element to turn-based combat. Minigame performance affects damage, MP cost, and critical hit chances.

### Minigame System Overview

**Manager**: `MinigameManager` (autoload at `/root/aMinigameManager`)

**Base Class**: `BaseMinigame` - Provides common overlay, status effect visuals, and completion signaling

**Minigame Result Structure**:
```gdscript
{
  "success": bool,           # Did the minigame complete successfully?
  "grade": String,           # "perfect", "great", "good", "ok", "miss"
  "damage_modifier": float,  # Damage multiplier (e.g., 1.1 for +10%)
  "is_crit": bool,          # Force critical hit?
  "mp_modifier": float,      # MP cost modifier for skills
  "tier_downgrade": int,     # Skill tier reduction (0 = no change)
  "focus_level": int         # Achieved focus level for skills (0-3)
}
```

### Status Effect Impact on Minigames

All minigames are affected by active status ailments:

| Ailment | Effect on Minigame |
|---------|-------------------|
| **Malaise** | 10% faster time limit (base_duration × 0.9) |
| **Burn** | Charge halt mechanic + fiery orange border animation |
| **Poison** | Charge halt mechanic + purple border animation |
| **Freeze** | Visual effect + light blue border animation |
| **Sleep** | Charge halt mechanic + white border animation |

**Visual Effects**: All ailments add animated wavy borders around the minigame panel in their respective colors.

---

### Attack Minigame

**Trigger**: Basic Attack action (A button)

**Type**: Timing-based weak spot tracking

**Mechanics**:
1. **Phase 1 - Watching (3 seconds)**:
   - Weak spot (yellow dot) moves randomly around circular arena
   - Player controls circular view window using directional input
   - View radius scales with **BRW stat** (40px + BRW×5px)
   - Red aiming reticle in center of view
   - Timer starts on first movement input

2. **Phase 2 - Charging**:
   - **HOLD A (Accept)** button to start charging
   - Charge bar fills over ~0.67 seconds (red → yellow → green → blue)
   - Player can continue moving view while charging
   - Release button to attack at current charge level
   - Can overcharge past 100% (penalty!)

**Grading System**:

| Grade | Condition | Damage Modifier | Crit? |
|-------|-----------|----------------|-------|
| **CRIT (Blue)** | 81-99% charge + weak spot in red dot | +10% | Yes |
| **GREAT (Green)** | 10-80% charge + weak spot in red dot | +10% | No |
| **GOOD (Yellow)** | Any charge + weak spot visible (not in red dot) | 0% | No |
| **OK (Red)** | 100%+ charge (overcharged) OR weak spot not visible | -10% | No |

**Status Effects**:
- **Burn/Poison**: Screen shakes every 0.3 seconds (±8px offset), making aiming harder

**Notes**:
- Higher BRW = larger view radius (easier to find weak spot)
- Can slide view WHILE charging for last-second adjustments
- Missing the red dot caps max grade at GOOD (+0% damage)
- Not finding weak spot at all caps max grade at OK (-10% damage)

---

### Skill Minigame

**Trigger**: Skill action (X button)

**Type**: Focus charging + button sequence

**Mechanics**:
1. **Phase 1 - Charging (variable duration)**:
   - **HOLD A (Accept)** to charge focus level
   - Charge speed based on **FCS stat** (1.0 + FCS×0.15 speed multiplier)
   - 4 focus levels: 0, 1, 2, 3
   - Visual: Circular party icon grows and glows with mind type color
   - Number drops from 0 → 1 → 2 → 3 with gravity animation
   - 3 second overall time limit from first charge

2. **Phase 2 - Inputting (5 seconds)**:
   - Button sequence displayed (A, B, X, Y buttons)
   - Sequence length = skill tier (Tier 1 = 1 button, Tier 3 = 3 buttons)
   - Must input exact sequence within time limit
   - Each wrong button = misclick (can cause tier downgrade)

**Grading System**:

Focus level achieved determines MP cost and damage:

| Focus Level | MP Cost | Skill Tier | Damage Modifier |
|-------------|---------|------------|----------------|
| **0** | Full MP | -2 tiers (min 1) | Normal |
| **1** | Full MP | -1 tier | Normal |
| **2** | Full MP | Same tier | Normal |
| **3** | 50% MP | Same tier | +15% damage |

**Sequence Accuracy**:
- Perfect sequence (no misclicks) = No tier downgrade
- 1 misclick = -1 tier downgrade
- 2+ misclicks = -2 tier downgrade

**Status Effects**:
- **Burn/Poison/Sleep**: Charge randomly halts for 0.3 seconds (must release and repress button to continue)

**Notes**:
- Higher FCS = faster charging (easier to reach level 3)
- Level 3 + perfect sequence = 50% MP cost + 15% damage bonus
- Skill tier downgrades affect potency and effects
- Mind type determines party icon color (Fire = orange-red, Water = blue, etc.)

---

### Burst Minigame

**Trigger**: Burst action (RB button)

**Type**: Button mashing

**Mechanics**:
1. **Mashing Phase (3 seconds)**:
   - **MASH A (Accept)** as fast as possible
   - Each press increases Sync Level by (5.0 + Affinity×0.5)
   - Sync level slowly decays over time (-5/second)
   - Max sync level: 100%

**Grading System**:

| Grade | Sync Level | Damage Modifier | Crit? |
|-------|-----------|----------------|-------|
| **PERFECT** | 80-100% | +25% | Yes (if 90%+) |
| **GREAT** | 60-79% | +15% | No |
| **GOOD** | 0-59% | 0% | No |

**Notes**:
- Bursts are **unmissable** - minimum grade is GOOD (normal damage)
- Higher Affinity between participants = faster sync gain
- Fastest mashing wins (no penalty for over-mashing)
- Visual: Sync bar changes color (red → green → gold)

---

### Capture Minigame

**Trigger**: Capture action (LB button)

**Type**: Timing-based bind throw (CURRENTLY NOT IMPLEMENTED - Auto-success based on formula)

**Current Implementation**:
- Capture minigame is **bypassed**
- Success determined by capture formula only (see Capture Mechanics section)
- Future implementation will add timing-based throw mechanic

---

### Run Minigame

**Trigger**: Run action (Start button)

**Type**: Timing-based escape sequence (CURRENTLY NOT IMPLEMENTED - Auto-roll based on formula)

**Current Implementation**:
- Run minigame is **bypassed**
- Success determined by run chance formula only
- Future implementation will add timing-based escape sequence

---

### Minigame Status Effect Visuals

All minigames display animated borders when combatant has ailments:

**Border Animations** (wavy sine wave, 20 segments, 3px thickness):

| Ailment | Color | Animation Speed |
|---------|-------|----------------|
| **Burn** | Fiery orange (1.0, 0.4, 0.0) | 2.0 rad/s wave |
| **Poison** | Pale purple (0.6, 0.3, 0.8) | 2.0 rad/s wave |
| **Freeze** | Light blue (0.6, 0.8, 1.0) | 2.0 rad/s wave |
| **Malaise** | Dark blue (0.1, 0.2, 0.5) | 2.0 rad/s wave |
| **Sleep** | White (1.0, 1.0, 1.0) | 2.0 rad/s wave |

**Dimmed Background**: All minigames use a semi-transparent black overlay (alpha 0.7) to focus attention

**Panel Size**: 35% of screen size, centered

**Input Grace Period**: 0.3 second grace period after minigame opens to prevent button carryover from target selection

---

## Damage Calculation

### Physical Damage Formula

```
1. Pre-Mitigation Damage
   PreMit = (WeaponATK + BRW × BRW_Scale) × Potency/100

2. Apply Type, Crit, and Buffs
   ATK_Power = PreMit × (1 + TYPE) × (Crit ? 2 : 1) × (1 + ATK_Buffs − ATK_Debuffs)

3. Apply Defense Mitigation
   PDEF_PerHit = PDEF / √MultiHit
   Raw = max(ATK_Power − PDEF_PerHit, 0)

4. Apply Defensive Modifiers
   AfterMods = Raw × Defend_Mult × Shield_Mult

5. Apply Enemy Damage Reduction (if attacker is enemy)
   AfterMods = AfterMods × 0.7

6. Apply Mitigation Floor
   Damage = max(AfterMods, ceil(ATK_Power × DMG_FLOOR))

Where:
- WeaponATK = Base weapon attack (from equipment CSV)
- BRW_Scale = Weapon's BRW scaling (usually 0.5)
- Potency = Skill potency % (100 for basic attack)
- TYPE = Mind type bonus (+0.25 weakness, -0.25 resist, 0 neutral)
- ATK_Buffs = Sum of atk_up buffs
- ATK_Debuffs = Sum of atk_down debuffs (negative values)
- PDEF = Armor's physical defense stat
- MultiHit = Number of hits (1 for basic attack)
- Defend_Mult = 0.7 if defending, 1.0 otherwise
- Shield_Mult = 1.0 - (def_up + def_down buffs)
- DMG_FLOOR = 0.20 for player→enemy, 0.15 for enemy→player
- Enemy damage is reduced to 70% for balance
```

### Sigil Damage Formula

```
1. Pre-Mitigation Damage
   PreMit = (BaseSIG + SIG_Bonus + MND × MND_Scale) × Potency/100

2. Apply Type, Crit, and Buffs
   Skill_Power = PreMit × (1 + TYPE) × (Crit ? 2 : 1) × (1 + SKL_Buffs − SKL_Debuffs)

3. Apply Defense Mitigation
   MDEF_PerHit = MDEF / √MultiHit
   Raw = max(Skill_Power − MDEF_PerHit, 0)

4. Apply Defensive Modifiers
   AfterMods = Raw × Defend_Mult × Shield_Mult

5. Apply Enemy Damage Reduction (if attacker is enemy)
   AfterMods = AfterMods × 0.7

6. Apply Mitigation Floor
   Damage = max(AfterMods, ceil(Skill_Power × DMG_FLOOR))

Where:
- BaseSIG = Skill's base SIG power (from skills CSV)
- SIG_Bonus = Weapon's SIG bonus stat
- MND_Scale = Skill's MND scaling factor (usually 1.0)
- SKL_Buffs = Sum of skl_up buffs
- SKL_Debuffs = Sum of skl_down debuffs
- MDEF = Armor's magic defense stat
```

---

## Hit & Evasion

### Physical Hit Check

```
Hit% = WeaponACC + 0.25×TPO + PhysACC_Buffs
Eva% = FootwearEVA + 0.15×VTL + EVA_Buffs
Final = clamp(Hit% − Eva%, 5%, 95%)

Roll d100:
- If roll ≤ Final → HIT
- If roll > Final → MISS
```

**Defaults**:
- WeaponACC = 90% (most weapons)
- FootwearEVA = 0% (base footwear)

### Sigil Hit Check

```
Hit% = SkillACC + WeaponSkillBoost + 0.25×TPO + MindACC_Buffs
Eva% = FootwearEVA + 0.15×FCS + EVA_Buffs
Final = clamp(Hit% − Eva%, 5%, 95%)

Roll d100:
- If roll ≤ Final → HIT
- If roll > Final → MISS
```

**Defaults**:
- SkillACC = 95% (most skills)
- WeaponSkillBoost = 0-10% (varies by weapon)

---

## Critical Hits

### Critical Chance Formula

```
CritChance = Base(5%) + TPO×0.15% + WeaponCritBonus% + SkillCritBonus%
Final = clamp(CritChance, 0%, 95%)

Roll d100:
- If roll ≤ Final → CRITICAL
- If roll > Final → Normal
```

**Critical Effect**: Damage × 2.0

**Example**:
- TPO = 10
- Weapon Crit Bonus = 5%
- CritChance = 5% + (10 × 0.15%) + 5% = **11.5%**

---

## Type Systems

### Mind Type Effectiveness

**6 types + Omega** in two cycles:
- **Fire > Air > Earth > Water > Fire** (4-way cycle)
- **Data > Void > Data** (2-way cycle)

| Attacker Type | Weak Against (×0.75) | Resists (×1.25) |
|---------------|---------------------|-----------------|
| **Fire** | Water | Air |
| **Water** | Earth | Fire |
| **Earth** | Air | Water |
| **Air** | Fire | Earth |
| **Data** | Void | — |
| **Void** | Data | — |
| **Omega** | — | None (neutral to all) |

**Modifier Values**:
- Weakness: +0.25 (×1.25 damage multiplier when attacker hits defender's weakness)
- Resistance: -0.25 (×0.75 damage multiplier when defender resists attacker)
- Neutral: 0.0 (×1.0 damage multiplier)

### Weapon Triangle System

```
Pierce → Slash → Blunt → Pierce
  ↓       ↓       ↓
Wins    Wins    Wins
```

**Effects**:
- Weapon triangle advantage grants **+25% damage** (Stumble)
- Target gains 1 weapon_weakness_hit counter
- Target loses 5 initiative (turn order re-sorted)
- 2 weapon_weakness_hits in one round → **Fallen** (skip next turn)

---

## Status Effects & Ailments

### Ailment Processing

Ailments are processed **at the start of each combatant's turn** (not at round start).

| Ailment | Effect | Auto-Cure Chance | Notes |
|---------|--------|------------------|-------|
| **Poison** | 8% max HP damage per turn | 30% + 10% per turn (max 90%) | DoT effect |
| **Burn** | 8% max HP damage per turn | 30% + 10% per turn (max 90%) | DoT effect |
| **Sleep** | Skip turn | 20% per turn | Wakes when hit or item used |
| **Freeze** | 30% action success chance | 20% per turn | Can still act (30% success) |
| **Malaise** | 30% action success chance | 30% + 10% per turn (max 90%) | Reduces action reliability |
| **Berserk** | Attacks random target | 30% + 10% per turn (max 90%) | Loss of control |
| **Charm** | Uses healing/buff items on enemy | 30% + 10% per turn (max 90%) | Helps enemies |
| **Fainted** | KO'd (HP = 0) | Cannot auto-cure | Requires revival item/skill |
| **Revived** | Skip turn to recover | Auto-cures after 1 turn | From revival items/skills |

**Ailment Turn Counter**: Increments each turn, used for escalating auto-cure chances.

---

## Buffs & Debuffs

### Buff Types

| Buff Type | Effect | Duration | Source |
|-----------|--------|----------|--------|
| **atk_up** | Increase physical damage | 3-5 turns | Power Drink, skills |
| **def_up** | Reduce incoming damage | 3-5 turns | Shield Orb, skills |
| **skl_up** | Increase sigil damage | 3-5 turns | Focus Tonic, skills |
| **spd_up** | Increase initiative | 3-5 turns | Hyper Chews, skills |
| **phys_acc** | Increase physical hit rate | 3-5 turns | Eye Drops, skills |
| **mind_acc** | Increase sigil hit rate | 3-5 turns | Focus Tonic, skills |
| **evasion** | Increase evasion | 3-5 turns | Hyper Chews, skills |
| **regen** | Heal 5% max HP per turn | 3-5 turns | Regen Capsule, skills |

### Debuff Types

| Debuff Type | Effect | Duration | Source |
|-------------|--------|----------|--------|
| **atk_down** | Decrease physical damage | 3-5 turns | Enemy skills |
| **def_down** | Increase incoming damage | 3-5 turns | Enemy skills |
| **skl_down** | Decrease sigil damage | 3-5 turns | Enemy skills |
| **spd_down** | Decrease initiative | 3-5 turns | Enemy skills |

### Buff Management

- **Duration**: Decremented at **round start** (not turn start)
- **Stacking**: Multiple buffs of same type stack additively
- **Refresh**: Reapplying a buff refreshes its duration
- **Clearing**: All buffs/debuffs are cleared at battle end

---

## Burst Gauge System

### Gauge Mechanics

**Capacity**: 100 points (shared across entire party)

**Gain Sources**:
- Attack hits: +5
- Attack misses: +2
- Skill hits: +10
- Skill misses: +5
- Item use: +5
- Defend: +3
- Capture success: +20
- Capture fail: +5
- Run attempt: +2

**Per-Round Cap**: Gain capped at +25 per round (to prevent burst spam)

### Burst Tiers

| Tier | Cost | Participants | Description |
|------|------|--------------|-------------|
| **Single** | 25 | 1 character | Individual burst attack, hits all enemies |
| **Duel** | 55 | 2 characters | Dual combo attack, increased damage |
| **Omega** | 90 | 3 characters | Ultimate team attack, massive damage |

**Burst Damage**: Based on minigame performance (timing-based button presses). Perfect timing grants bonus damage multipliers.

---

## Capture Mechanics

### Capture Chance Formula

```
CaptureChance = Base + ItemMod − EnemyResist − (k × HP%) + StateBonus
Final = clamp(CaptureChance, 0%, 100%)

Where:
- Base = 35% (default encounter value)
- ItemMod = Bind item modifier:
    - Basic Bind: +10%
    - Intermediate Bind: +25%
    - Advanced Bind: +40%
    - Expert Bind: +60%
    - Master Bind: +100%
- EnemyResist = 0-60% (from enemy definition)
- k = 0.15 (HP coefficient, reduced from 0.4 for viability)
- HP% = Current HP as percentage (0-100%)
- StateBonus:
    - Sleep/Freeze/Bound: +15%
    - Stunned/Fallen: +10%
    - Other: 0%
```

### Capture Difficulty Tiers

| Tier | Capture Resist | Example |
|------|----------------|---------|
| **None** | N/A | Cannot be captured (bosses, story enemies) |
| **Easy** | 0-10% | Common enemies |
| **Medium** | 15-25% | Uncommon enemies |
| **Hard** | 30-40% | Rare enemies |
| **Very Hard** | 50-60% | Legendary enemies |

### Capture Effects

**On Success**:
- Enemy removed from battle (marked `is_captured = true`)
- Battle rewards enhanced:
  - +50% creds
  - +50% item drop chance
- Morality bonus applied (+1 Regular, +3 Elite, +15 Boss)
- Burst gauge +20

**On Failure**:
- Bind item consumed
- Turn wasted
- Burst gauge +5

**Morality Impact**: Capturing enemies instead of killing them grants **positive morality points** and avoids negative morality from kills. This is a core gameplay mechanic encouraging non-lethal playstyles.

---

## Rewards & Experience

### Battle Rewards Calculated At Victory

**Breakdown**:
1. **LXP (Level Experience)** - Character levels
2. **GXP (Sigil Growth Experience)** - Sigil levels
3. **AXP (Affinity Experience)** - Co-presence bonuses
4. **Creds** - Currency
5. **Items** - Enemy drops

### LXP Distribution

```
BaseXP = Sum of all defeated enemies' XP (EnemyLevel × 10)

For each party member:
- If active and not KO'd: Award 100% of BaseXP
- If active but KO'd: Award 50% of BaseXP
- If benched: Award 0% (not in battle)

LXP → StatsSystem.add_xp(member_id, amount)
```

### GXP Distribution

```
GXP_PerSigil = BaseXP × 0.5 (Sigils get 50% of base XP)

For each equipped sigil:
- Base GXP: GXP_PerSigil
- Bonus: +5 GXP if sigil's skill was used in battle

GXP → SigilSystem.add_xp_to_instance(sigil_id, amount)
```

### AXP Distribution (Affinity XP)

```
For each pair of party members (co-present in battle):
- Both active at battle end: +2 AXP
- One KO'd, one standing: +1 AXP
- Both KO'd: +0 AXP

AXP → AffinitySystem.add_copresence_axp(memberA, memberB, amount)
```

### Creds Calculation

```
For each defeated enemy:
- Roll random value from cred_range (e.g., "10-20")
- If captured: Apply ×1.5 multiplier
- Sum all creds

Total → GameState.add_creds(amount)
```

### Item Drops

```
For each defeated enemy with drop_table:
- Load drop table from drop_tables.csv
- For each item in table:
    - Base drop rate (e.g., 0.20 = 20%)
    - If captured: Apply ×1.5 multiplier to drop rate
    - Roll for drop
    - If success: Add to drops array

Dropped items → InventorySystem.add_item(item_id, qty)
```

---

## HP/MP Persistence

### Save HP/MP After Battle

At battle end, `BattleManager._save_party_hp_mp_and_clear_status()` is called:

**Victory**:
```
For each ally:
- If KO'd: Revive with 1 HP
- If active: Save current HP
- Save current MP
- Clear all status effects (ailments, buffs, debuffs)

→ GameState.member_data[member_id] = {hp, mp, buffs: [], debuffs: [], ailment: ""}
```

**Defeat**:
```
For each ally:
- Save current HP (including 0 if KO'd)
- Save current MP
- Clear all status effects

→ GameState.member_data[member_id] = {hp, mp, buffs: [], debuffs: [], ailment: ""}
```

### Load HP/MP Before Battle

When battle initializes, `BattleManager._create_ally_combatant()` loads from:

**Priority 1**: `GameState.member_data[member_id]`
- HP and MP values from last battle or save file

**Priority 2**: `CombatProfileSystem.get_profile(member_id)`
- Computed HP/MP from stats (if no saved data)

**Fallback**: Full HP/MP based on level and stats

### Day Advancement Healing

`CombatProfileSystem.heal_all_to_full()` is called when:
- A new day starts (via CalendarSystem.day_advanced signal)
- Player manually triggers full heal (e.g., rest at dorm)

**Effect**:
- All party members (active + benched) restored to full HP/MP
- All ailments cleared
- All buffs/debuffs cleared

---

## Morality Integration

### Morality Deltas

The combat system integrates with `MoralitySystem` to track player ethics:

**Kills** (negative morality):
```
Regular enemy kill: -1
Elite enemy kill: -3
Boss enemy kill: -15

Applied via: MoralitySystem.apply_delta(delta, "Killed X enemy")
```

**Captures** (positive morality):
```
Regular enemy capture: +1
Elite enemy capture: +3
Boss enemy capture: +15

Applied via: MoralitySystem.apply_delta(delta, "Captured X enemy")
```

**Tracking**:
- `BattleManager.battle_kills` - Dictionary of env_tag → count
- `BattleManager.battle_captures` - Dictionary of env_tag → count

**Application**:
- At battle end, `_apply_morality_for_battle()` iterates through kills/captures
- Deltas applied per enemy type
- Affects ending and story choices

**VR Battle Exception**: Morality is NOT applied in VR training battles (future feature)

---

## Summary

The Psyokin combat system is a deep, turn-based JRPG system with:
- **Initiative-based turn order** with dynamic re-sorting
- **Weapon triangle** and **mind type** systems for tactical depth
- **Status ailments** with auto-cure escalation
- **Buff/debuff** management with stacking and durations
- **Burst gauge** for team-based super attacks
- **Capture mechanics** for non-lethal combat and morality choices
- **HP/MP persistence** between battles
- **Comprehensive reward system** (LXP, GXP, AXP, Creds, Items)
- **Morality tracking** for ethical combat choices

All formulas are balanced around strategic stat allocation (BRW, VTL, TPO, FCS, MND) and tactical equipment/sigil loadouts.
