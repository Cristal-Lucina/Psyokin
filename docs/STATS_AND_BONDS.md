# Stats and Bonds System Documentation

## Table of Contents

1. [Overview](#1-overview)
2. [Stats System Architecture](#2-stats-system-architecture)
3. [Core Stats (BRW, MND, TPO, VTL, FCS)](#3-core-stats-brw-mnd-tpo-vtl-fcs)
4. [SXP (Stat Experience Points)](#4-sxp-stat-experience-points)
5. [Fatigue System](#5-fatigue-system)
6. [Daily Stat Increment (DSI)](#6-daily-stat-increment-dsi)
7. [Hero Level & XP](#7-hero-level--xp)
8. [Perk Points](#8-perk-points)
9. [HP/MP Pools](#9-hpmp-pools)
10. [Ally Progression](#10-ally-progression)
11. [Affinity System (Combat Bonuses)](#11-affinity-system-combat-bonuses)
12. [Circle Bond System (Social Progression)](#12-circle-bond-system-social-progression)
13. [Bond Event System](#13-bond-event-system)
14. [Likes/Dislikes Discovery](#14-likesdislikes-discovery)
15. [Love Interests & Romance](#15-love-interests--romance)
16. [Integration with Combat](#16-integration-with-combat)
17. [Save/Load System](#17-saveload-system)
18. [Weekly Calendar Integration](#18-weekly-calendar-integration)

---

## 1. Overview

Psyokin features two interconnected progression systems that drive both combat effectiveness and narrative depth:

**Stats System** (`StatsSystem.gd`)
- Manages 5 core stats for hero and all party members
- SXP (Stat Experience Points) accumulation through activities
- Fatigue mechanics to prevent grinding
- Daily automatic stat growth
- HP/MP pools derived from stats and level
- Perk point rewards for hero progression

**Bond Systems** (Two parallel systems)
- **AffinitySystem** (`AffinitySystem.gd`): Combat-focused relationship bonuses
  - AXP (Affinity XP) earned through co-presence and synergy
  - Affinity Tiers (AT0-AT3) grant combat stat bonuses
  - Weekly conversion with caps to prevent grinding

- **CircleBondSystem** (`CircleBondSystem.gd`): Narrative-focused social progression
  - BXP (Bond Experience Points) earned through events and gifts
  - 5 Bond Layers (Acquaintance → Outer → Middle → Inner → Core)
  - Event-based story progression (E1-E9)
  - Likes/dislikes discovery system
  - Love interest routes and romance options

---

## 2. Stats System Architecture

**File**: `scripts/systems/StatsSystem.gd`

**Autoload Path**: `/root/aStatsSystem`

**Connected Systems**:
- `CalendarSystem` - Daily/weekly triggers for DSI and fatigue reset
- `PartySystem` - Member roster management
- `GameState` - Save/load coordination, hero stat picks
- `CSVLoader` - Party member definitions
- `CombatProfileSystem` - Combat stat calculation
- `EquipmentSystem` - Equipment bonuses

**CSV Data Sources**:
- `res://data/actors/party.csv` - Member base stats, names, DSI values

**Key Responsibilities**:
- Track 5 core stats per character (BRW, MND, TPO, VTL, FCS)
- Manage SXP pools and level calculation
- Apply daily stat increments automatically
- Enforce fatigue thresholds (60 SXP/week cap)
- Track hero level and XP from battles
- Calculate HP/MP pools from VTL/FCS
- Award perk points every 4 hero levels
- Preserve HP/MP percentages on level-up

---

## 3. Core Stats (BRW, MND, TPO, VTL, FCS)

### Stat Definitions

| Stat Code | Full Name | Combat Role | HP/MP Impact |
|-----------|-----------|-------------|--------------|
| **BRW** | Brawn | Physical attack power, weapon damage | — |
| **MND** | Mind | Sigil damage, skill power, ailment potency | — |
| **TPO** | Tempo | Initiative/turn order, # of attacks per turn | — |
| **VTL** | Vitality | Physical defense, max HP | **Max HP = 60 + (VTL × Level × 6)** |
| **FCS** | Focus | Skill accuracy, max MP, skill charge speed | **Max MP = 20 + (FCS × Level × 1.5)** |

### Stat Level Calculation

Each stat has:
- **Base Level**: Starting value from character creation or CSV (1-10+)
- **SXP Pool**: Accumulated Stat Experience Points (0-943+)
- **Bonus Levels**: Derived from SXP thresholds

**Total Stat Level** = Base Level + Bonus Levels from SXP

### Stat Usage in Combat

- **BRW**: Determines physical damage dealt with weapons
  - Attack Minigame reticle size = 40px + (BRW × 5px)
  - Physical damage formula uses BRW directly

- **MND**: Powers sigil attacks (skills/spells)
  - Sigil damage formula uses MND
  - S ATK stat = MND + skill_acc_boost (from weapon)

- **TPO**: Controls battle flow
  - Initiative roll = 1d20 + TPO
  - Attack attempts per turn = 1-4 based on TPO

- **VTL**: Survivability stat
  - Max HP = 60 + (VTL × Level × 6)
  - Physical defense calculations

- **FCS**: Skill effectiveness
  - Max MP = 20 + (FCS × Level × 1.5)
  - Skill charge speed = 1.0 + (FCS × 0.15) multiplier
  - Level 3 focus: 50% MP cost reduction, +15% damage

---

## 4. SXP (Stat Experience Points)

### SXP Thresholds

SXP accumulates to unlock bonus stat levels:

| Bonus Levels | SXP Required | Cumulative Total |
|--------------|--------------|------------------|
| 0 | 0 | 0 |
| 1 | 59 | 59 |
| 2 | 63 | 122 |
| 3 | 67 | 189 |
| 4 | 71 | 260 |
| 5 | 76 | 336 |
| 6 | 80 | 416 |
| 7 | 84 | 500 |
| 8 | 88 | 588 |
| 9 | 92 | 680 |
| 10 | 263 | 943 |

**Example**: A character with 200 SXP in BRW has unlocked 3 bonus levels. If their base BRW is 5, their total BRW = 5 + 3 = **8**.

### SXP Sources

1. **Combat Activities**:
   - Attack: +SXP to BRW
   - Skill usage: +SXP to MND
   - Taking damage: +SXP to VTL
   - Landing hits: +SXP to TPO
   - Successful evasion: +SXP to FCS

2. **Daily Stat Increment (DSI)**:
   - Passive gains every day (see section 6)

3. **Manual Awards**:
   - Story events
   - Quest completion
   - Training activities

### Fatigue Impact on SXP Gains

Once a stat gains **60+ SXP in the current week**, all further gains are **halved** until Monday reset.

**Example**:
- Monday: Gain 10 BRW SXP → Total weekly: 10 (full gains)
- Tuesday: Gain 20 BRW SXP → Total weekly: 30 (full gains)
- Wednesday: Gain 35 BRW SXP → Total weekly: 65 (exceeds 60!)
- Thursday: Attempt to gain 10 BRW SXP → **Actually gain 5** (halved due to fatigue)

---

## 5. Fatigue System

### Purpose
Prevents excessive grinding by halving stat gains after a weekly threshold.

### Mechanics

**Threshold**: 60 SXP per stat per week

**Effect**: Once any stat reaches 60+ SXP gained this week, further gains to that stat are halved (minimum 1 SXP per gain).

**Reset**: Every **Monday** at midnight, all weekly SXP counters reset to 0.

### Tracking

**Hero**:
```gdscript
hero_weekly_sxp: Dictionary = {"BRW":0,"MND":0,"TPO":0,"VTL":0,"FCS":0}
```

**Allies**:
```gdscript
_party_progress[member_id]["weekly_sxp"]: Dictionary
```

### Example Weekly Progression

| Day | BRW Gain | Weekly Total | Fatigued? | Actual Gain |
|-----|----------|--------------|-----------|-------------|
| Mon | 15 | 15 | No | 15 |
| Tue | 20 | 35 | No | 20 |
| Wed | 30 | 65 | **Yes** | 30 |
| Thu | 10 | 70 | **Yes** | **5** (halved) |
| Fri | 8 | 74 | **Yes** | **4** (halved) |
| Mon | 20 | 20 (reset!) | No | 20 |

---

## 6. Daily Stat Increment (DSI)

### Purpose
All party members gain passive stat growth automatically each day, even when not in active party.

### Default DSI Values (Tenths per Day)

| Stat | Tenths/Day | SXP/Day |
|------|------------|---------|
| BRW | 10 | 1.0 |
| MND | 20 | 2.0 |
| TPO | 30 | 3.0 |
| VTL | 10 | 1.0 |
| FCS | 30 | 3.0 |

**Note**: Values are stored as tenths (e.g., 10 tenths = 1.0 SXP) to allow fractional gains without floating point errors.

### Customization per Character

Each party member can have custom DSI values defined in `party.csv`:

```csv
actor_id,name,dsi_brw,dsi_mnd,dsi_tpo,dsi_vtl,dsi_fcs
elara,Elara,1.5,3.0,2.5,1.0,4.0
```

These override the default values for that character.

### Application Timing

DSI is applied:
- **When**: Every day at midnight (CalendarSystem day_advanced signal)
- **Who**: ALL known party members (active, bench, and discovered)
- **Fatigue**: DSI gains respect the weekly fatigue threshold

### Monthly Growth Estimate

Assuming no fatigue (under 60 SXP/week):

| Stat | Daily Gain | Weekly Gain | Monthly Gain (~4 weeks) |
|------|------------|-------------|-------------------------|
| BRW | 1.0 | 7.0 | ~28 SXP |
| MND | 2.0 | 14.0 | ~56 SXP |
| TPO | 3.0 | 21.0 | ~84 SXP (fatigued!) |
| VTL | 1.0 | 7.0 | ~28 SXP |
| FCS | 3.0 | 21.0 | ~84 SXP (fatigued!) |

With fatigue, weekly gains cap around:
- Full week: 60 SXP (threshold)
- Fatigued gains: Variable based on when threshold hit

---

## 7. Hero Level & XP

### Hero Level System

Separate from stat levels, the hero has a traditional level/XP system.

**Level Range**: 1-99

### XP Formula

XP required to reach next level:

```
XP_to_next = 120 + (30 × current_level) + (6 × current_level²)
```

**Examples**:
- Level 1 → 2: 120 + 30 + 6 = **156 XP**
- Level 2 → 3: 120 + 60 + 24 = **204 XP**
- Level 5 → 6: 120 + 150 + 150 = **420 XP**
- Level 10 → 11: 120 + 300 + 600 = **1020 XP**

### XP Sources

1. **Combat Rewards**:
   - Defeating enemies
   - Capturing instead of killing (morality bonus)
   - Battle victory bonuses

2. **Quest Completion**:
   - Story quests
   - Side quests
   - Bond events

3. **Manual Awards**:
   - Scripted events
   - Milestones

### Level-Up Benefits

When hero levels up:
1. **Stat Pools Recalculated**: Max HP/MP increase based on VTL/FCS
2. **HP/MP Percentages Preserved**: Current HP/MP adjusted to maintain same % of new max
3. **Perk Points**: +1 perk point every 4 levels (see section 8)

### Ally Levels

Allies also have individual levels and XP pools:
- Separate XP tracking per member
- Same XP formula as hero
- No perk points for allies (hero-only reward)

---

## 8. Perk Points

### Purpose
Special currency for permanent upgrades and perks.

### Earning Perk Points

**Hero Only** - Allies do not earn perk points.

**Formula**: +1 perk point for every 4 hero levels crossed.

Levels that award perk points: **3, 6, 9, 12, 15, 18, 21, ...**

**Calculation**:
```gdscript
perk_points_gained = floor(new_level / 4) - floor(old_level / 4)
```

**Examples**:
- Level 1 → 2: floor(2/4) - floor(1/4) = 0 - 0 = **0 points**
- Level 2 → 3: floor(3/4) - floor(2/4) = 0 - 0 = **0 points**
- Level 3 → 4: floor(4/4) - floor(3/4) = 1 - 0 = **1 point** ✓
- Level 5 → 7: floor(7/4) - floor(5/4) = 1 - 1 = **0 points**
- Level 5 → 8: floor(8/4) - floor(5/4) = 2 - 1 = **1 point** ✓

### Spending Perk Points

Managed through `PerksPanel.gd`:
- Permanent stat boosts
- Unlock abilities
- Enhance combat mechanics
- Quality of life upgrades

**Spending**:
```gdscript
StatsSystem.spend_perk_point(amount: int) -> int
# Returns actual amount spent (limited by available points)
```

**Signal**:
```gdscript
signal perk_points_changed(new_value: int)
```

---

## 9. HP/MP Pools

### Max HP Formula

```
Max HP = 60 + (VTL × Level × 6)
```

**Examples**:
- Level 1, VTL 5: 60 + (5 × 1 × 6) = **90 HP**
- Level 5, VTL 8: 60 + (8 × 5 × 6) = **300 HP**
- Level 10, VTL 12: 60 + (12 × 10 × 6) = **780 HP**

### Max MP Formula

```
Max MP = 20 + (FCS × Level × 1.5)
```

**Examples**:
- Level 1, FCS 5: 20 + (5 × 1 × 1.5) = **27 MP** (rounded)
- Level 5, FCS 10: 20 + (10 × 5 × 1.5) = **95 MP**
- Level 10, FCS 15: 20 + (15 × 10 × 1.5) = **245 MP**

### HP/MP Preservation on Level-Up

When a character levels up or gains VTL/FCS:

1. **Calculate Old Max**: Based on previous VTL/FCS/Level
2. **Calculate Current %**: `current_hp / old_max_hp`
3. **Recalculate New Max**: Based on new VTL/FCS/Level
4. **Apply Same %**: `new_hp = (current_hp_pct × new_max_hp)`

**Example**:
- Before: Level 4, VTL 8, Max HP 252, Current HP 150 (59.5%)
- After: Level 5, VTL 8, Max HP 300
- New Current HP: 0.595 × 300 = **179 HP** (preserved %)

This prevents the "level-up heal" exploit while ensuring players don't lose progress.

---

## 10. Ally Progression

### Party Member Tracking

Each ally has separate progression data:

```gdscript
_party_progress[member_id] = {
    "label": "Display Name",
    "char_level": 5,
    "start": {"BRW": 6, "MND": 8, "TPO": 7, "VTL": 5, "FCS": 9},
    "sxp": {"BRW": 120, "MND": 80, "TPO": 150, "VTL": 60, "FCS": 200},
    "tenths": {"BRW": 5, "MND": 3, "TPO": 7, "VTL": 2, "FCS": 4},
    "dsi_tenths": {"BRW": 15, "MND": 25, "TPO": 30, "VTL": 10, "FCS": 35},
    "weekly_sxp": {"BRW": 25, "MND": 40, "TPO": 55, "VTL": 15, "FCS": 70}
}
```

### Stat Calculation for Allies

```gdscript
total_stat_level = start[stat] + bonus_levels_from_sxp(sxp[stat])
```

**Example**:
- Start BRW: 6
- Current BRW SXP: 200 (unlocks 3 bonus levels per threshold table)
- **Total BRW = 6 + 3 = 9**

### Ally DSI Application

**Timing**: Every day at midnight, applied to ALL party members (active + bench)

**Process**:
1. Add DSI tenths to tenths accumulator
2. When accumulator ≥ 10, grant 1 SXP and reduce accumulator by 10
3. Apply fatigue if weekly threshold exceeded
4. Repeat for all 5 stats

**Example**:
```gdscript
# Elara's BRW progression
tenths_before = 8
dsi_tenths = 15 (1.5 SXP/day)
tenths_after = 8 + 15 = 23
whole_sxp = floor(23 / 10) = 2
remainder_tenths = 23 - 20 = 3

# Result: +2 BRW SXP, 3 tenths banked for tomorrow
```

### Benched Members

Benched party members:
- ✓ Still gain DSI each day
- ✓ Fatigue still applies
- ✗ Do NOT gain combat SXP (must be in active party)
- ✓ Bond progress continues (Affinity co-presence requires active party)

---

## 11. Affinity System (Combat Bonuses)

**File**: `scripts/systems/AffinitySystem.gd`

**Autoload Path**: `/root/aAffinitySystem`

### Purpose

Tracks **combat relationships** between party members through AXP (Affinity XP), providing stat bonuses when characters fight together.

### Key Concepts

**Pair-Based System**: Relationships tracked between character pairs (e.g., "hero|elara")

**AXP (Affinity XP)**: Experience earned through:
- **Co-presence**: Fighting together in battles
- **Synergy**: Combo attacks, weakness chains, Burst usage

**Affinity Tiers (AT)**: Lifetime AXP converts to tiers granting combat bonuses

### Affinity Tier System

| Tier | Lifetime AXP Required | Combat Bonus | Description |
|------|----------------------|--------------|-------------|
| **AT0** | 0-19 | None | Strangers/Acquaintances |
| **AT1** | 20-59 | **+5%** BRW/VTL/MND | Friends |
| **AT2** | 60-119 | **+10%** BRW/VTL/MND | Close Friends |
| **AT3** | 120+ | **+15%** BRW/VTL/MND | Best Friends/Soulmates |

**Combat Bonus Application**:
- Only applies when **BOTH members are in active party**
- Affects: Brawn, Vitality, Mind (not Tempo or Focus)
- Multiplicative: Final stat = base_stat × (1 + tier_bonus)

**Example**:
- Hero has BRW 10, Elara has BRW 8
- Hero|Elara affinity: AT2 (10% bonus)
- When both active: Hero BRW = 10 × 1.10 = **11**, Elara BRW = 8 × 1.10 = **8.8** (rounds to 9)

### AXP Sources

#### 1. Co-Presence (Daily Cap: +6 per pair)

Earned when both members are in the same battle:

**Rewards**:
- Both active and conscious: **+2 AXP**
- One KO'd, one standing: **+1 AXP**
- Both KO'd: **+0 AXP**

**Daily Cap**: Maximum +6 co-presence AXP per pair per day

**Example**:
- Battle 1 (morning): Hero + Elara both active → +2 AXP
- Battle 2 (afternoon): Hero + Elara both active → +2 AXP
- Battle 3 (evening): Hero + Elara both active → +2 AXP (cap reached!)
- Battle 4 (night): Hero + Elara both active → +0 AXP (capped for today)

#### 2. Synergy (Per-Battle Cap: +3 best events)

Earned through tactical combat cooperation:

**Synergy Events** (+1 AXP each):
- **Weakness Chain**: Character A exploits weakness, Character B follows up
- **Burst Participation**: Both participate in same Burst attack
- **Interrupt Save**: Character A interrupts enemy attacking Character B

**Per-Battle Cap**: Only the **top 3 synergy events** per battle count toward AXP

**Example**:
- Battle starts
- Synergy Event 1: Hero exploits fire weakness, Elara follows → +1 AXP ✓
- Synergy Event 2: Hero + Elara both in Burst → +1 AXP ✓
- Synergy Event 3: Hero interrupts enemy attacking Elara → +1 AXP ✓
- Synergy Event 4: Another weakness chain → +0 AXP (cap reached)
- **Total synergy this battle: +3 AXP**

### Weekly AXP Conversion

**Timing**: Every **Sunday night** at midnight

**Process**:
1. **Floor**: Round down weekly AXP (discard fractional)
2. **Cap**: Maximum 30 AXP per pair per week
3. **Add to Lifetime**: Capped amount added to lifetime AXP total
4. **Compute Tier**: Recalculate affinity tier based on new lifetime total
5. **Reset Weekly**: Clear weekly AXP counters

**Example**:
```
Sunday Night Conversion:
- Hero|Elara weekly AXP: 42.7
- Floored: 42
- Capped: 30 (weekly max)
- Old lifetime: 45 (AT1)
- New lifetime: 45 + 30 = 75 (AT2!) ✓
- Weekly AXP reset to 0
```

### Weekly Progression Example

| Day | Co-Presence | Synergy | Daily Total | Weekly Total |
|-----|-------------|---------|-------------|--------------|
| Mon | 6 (capped) | 3 | 9 | 9 |
| Tue | 4 | 3 | 7 | 16 |
| Wed | 6 (capped) | 2 | 8 | 24 |
| Thu | 5 | 3 | 8 | 32 (will cap!) |
| Fri | 6 (capped) | 1 | 7 | 39 (will cap!) |
| Sat | 6 (capped) | 3 | 9 | 48 (will cap!) |
| Sun | 6 (capped) | 3 | 9 | 57 (will cap!) |
| **Conversion** | — | — | — | **30** (capped!) |

Maximum theoretical weekly AXP: 9 × 7 = 63, but capped at **30**.

---

## 12. Circle Bond System (Social Progression)

**File**: `scripts/circles/CircleBondSystem.gd`

**Autoload Path**: `/root/aCircleBondSystem`

### Purpose

Tracks **narrative relationships** between hero and individual party members through story events, dialogue, and gifts.

### Key Concepts

**BXP (Bond Experience Points)**: Points earned through events, dialogue, and gifts

**Bond Layers**: 5 progression tiers from strangers to soulmates

**Event-Based Progression**: 9 main story events (E1-E9) unlock as BXP thresholds are met

**Likes/Dislikes**: Player discovers character preferences through gameplay

### Bond Layer System

| Layer | Int Value | Events | Description | Threshold to Next |
|-------|-----------|--------|-------------|-------------------|
| **None** | 0 | E0 | Haven't met | — |
| **Acquaintance** | 1 | E1-E3 | Met, casual friends | 10+10 pts |
| **Outer Circle** | 2 | E4-E5 | Good friends | 12+12 pts |
| **Middle Circle** | 3 | E6-E7 | Close friends | 14+14 pts |
| **Inner Circle** | 4 | E8-E9 | Best friends | 16+16 pts |
| **Core** | 5 | E10 (LI only) | Soulmates/Romance | — |

### Event Progression System

**Main Events**: E1-E9 (9 total)

**Event Distribution**:
- **E1**: Introduction (sets layer to Acquaintance, awards **0 base points**)
- **E2-E3**: Acquaintance layer (must pay 10+10 pts to reach Outer)
- **E4-E5**: Outer Circle layer (must pay 12+12 pts to reach Middle)
- **E6-E7**: Middle Circle layer (must pay 14+14 pts to reach Inner)
- **E8-E9**: Inner Circle layer (must pay 16+16 pts to reach Core)
- **E10**: Final event (Love Interests only, Friend/Romance choice)

**Threshold Payment**:
After completing each event (E2-E9), you must accumulate enough BXP to "pay" the threshold before the next event unlocks.

**Total BXP Required** (E1 → E9): 0 + (10+10) + (12+12) + (14+14) + (16+16) = **104 points**

### BXP Sources

#### 1. Main Event Completion

**Base Reward**: +6 BXP for completing any main event (E2-E9)

**Exception**: E1 (introduction) awards **0 base BXP**

#### 2. Dialogue Choices (3 questions per event)

Each main event includes ~3 dialogue questions with response options:

| Response Quality | BXP Award |
|-----------------|-----------|
| **Best** | +2 BXP |
| **Okay** | +1 BXP |
| **Neutral** | 0 BXP |
| **Negative** | -1 BXP |

**Max Dialogue Bonus**: 3 questions × 2 BXP = **+6 BXP** (all best answers)

**Total Event Reward**: 6 (base) + 6 (dialogue) = **12 BXP max per event**

#### 3. Gifts (Once per Layer)

Each bond layer allows **ONE gift** to be given:

| Gift Reaction | BXP Award |
|--------------|-----------|
| **Liked** (matches preference) | +4 BXP |
| **Neutral** | +1 BXP |
| **Disliked** (matches dislike) | -2 BXP |

**Layer Reset**: When entering a new layer (e.g., Acquaintance → Outer), the gift flag resets, allowing another gift.

#### 4. Side Meetups (Optional Filler)

Optional scenes that can be triggered between main events:

**Reward**: +6 BXP per meetup

**Purpose**: Provides extra BXP if player needs to reach threshold or wants to bank points.

### Example Event Progression

#### Event 1 (Introduction)
- Complete E1: +0 base, +4 dialogue (2+1+1) = **4 BXP**
- **Layer**: Acquaintance
- **Bank**: 4 BXP
- **Next Threshold**: 10 BXP (need 6 more)

#### Between E1 and E2
- Give gift (liked): +4 BXP
- **Bank**: 8 BXP (still need 2 more)
- Side meetup: +6 BXP
- **Bank**: 14 BXP (threshold met! 4 overflow)

#### Event 2
- Complete E2: +6 base, +6 dialogue (all best) = **12 BXP**
- **Bank before threshold**: 14 + 12 = 26 BXP
- **Pay threshold**: -10 BXP
- **Bank after**: 16 BXP
- **Layer**: Still Acquaintance (transitions after E3)

#### Event 3
- Complete E3: +6 base, +3 dialogue (2+1+0) = **9 BXP**
- **Bank before threshold**: 16 + 9 = 25 BXP
- **Pay threshold**: -10 BXP
- **Bank after**: 15 BXP
- **Layer**: Outer Circle ✓ (transition after E3)
- **Gift flag reset**: Can give another gift!

### Threshold Payment Timing

| Event Complete | Threshold to Pay | Points Needed | Result |
|----------------|------------------|---------------|--------|
| E1 | — | — | → Acquaintance layer |
| E2 | 10 | 10 | Unlock E3 |
| E3 | 10 | 20 total | → Outer layer |
| E4 | 12 | 32 total | Unlock E5 |
| E5 | 12 | 44 total | → Middle layer |
| E6 | 14 | 58 total | Unlock E7 |
| E7 | 14 | 72 total | → Inner layer |
| E8 | 16 | 88 total | Unlock E9 |
| E9 | 16 | 104 total | → Core layer (LI: E10) |

**Points Overflow**: Any BXP beyond threshold requirements banks forward to the next threshold.

---

## 13. Bond Event System

### Event Structure

**CSV Source**: `res://data/circles/circles_events.csv`

**Event Row Format**:
```csv
character_id,event_id,required_layer,scene_path,dialogue_count,rewards
elara,E2,Acquaintance,res://scenes/events/elara_e2.tscn,3,item_herb_bundle
```

**Event Components**:
1. **Scene**: Visual novel-style cutscene
2. **Dialogue**: ~3 questions with multiple-choice responses
3. **Outcome**: BXP award based on dialogue quality
4. **Rewards**: Optional items, unlocks, or abilities

### Event Unlocking

Events unlock when:
1. **Previous event completed**: Must finish E2 before E3 unlocks
2. **Threshold met**: Must accumulate required BXP
3. **Layer requirement**: Some events require specific bond layer

**Check Method**:
```gdscript
func can_unlock_next_event(bond_id: String) -> bool:
    var event_idx = get_event_index(bond_id)
    if event_idx >= 9: return false  # All events complete
    var threshold = get_next_threshold(bond_id)
    var bank = get_points_bank(bond_id)
    return bank >= threshold
```

### Event Completion Flow

1. **Player initiates event** (from BondsPanel or world trigger)
2. **EventRunner loads scene** from CSV scene_path
3. **Scene plays** with dialogue choices
4. **Dialogue responses scored**:
   - Best: +2 BXP
   - Okay: +1 BXP
   - Neutral: 0 BXP
   - Negative: -1 BXP
5. **Base reward added**: +6 BXP (E2-E9), +0 BXP (E1)
6. **Total BXP awarded**: Base + dialogue_score
7. **Threshold check**: If met, next event unlocks
8. **Layer update**: If event completes layer (E1/E3/E5/E7/E9), layer advances

### Dialogue Scoring Example

**Event 2 Dialogue**:
- Question 1: "What do you think of the mission?" → Answer "Best" (+2 BXP)
- Question 2: "How do you feel about magic?" → Answer "Okay" (+1 BXP)
- Question 3: "Want to grab food later?" → Answer "Best" (+2 BXP)

**Dialogue Total**: 2 + 1 + 2 = **5 BXP**

**Event Total**: 6 (base) + 5 (dialogue) = **11 BXP**

---

## 14. Likes/Dislikes Discovery

### Purpose

Each character has hidden preferences for:
- **Topics**: Conversation subjects they enjoy or dislike
- **Gifts**: Items they love or hate receiving
- **Activities**: Shared experiences they prefer

Player must **discover** these preferences through gameplay—they are NOT visible by default.

### Discovery Mechanics

#### Gift Discovery

When player gives a gift:
1. **Check reaction**: System compares gift_id to character's `gift_likes` / `gift_dislikes` lists
2. **Determine reaction**:
   - In `gift_likes`: Reaction = "liked"
   - In `gift_dislikes`: Reaction = "disliked"
   - Neither: Reaction = "neutral"
3. **Award BXP**: +4 liked, +1 neutral, -2 disliked
4. **Mark discovered**: Add gift_id to `_discovered_likes` or `_discovered_dislikes`

**Code**:
```gdscript
func mark_gift_discovered(id: String, gift_id: String, reaction: String):
    if reaction == "liked":
        _discovered_likes[id].append(gift_id)
    elif reaction == "disliked":
        _discovered_dislikes[id].append(gift_id)
```

#### Dialogue Discovery

Some dialogue choices hint at preferences:
- **Observant choice**: "I noticed you like books" → Discover "books" as liked topic
- **Negative reaction**: Character frowns at mention of "politics" → Discover "politics" as disliked

### Storage Structure

**Author List** (never shown to player):
```gdscript
_defs[character_id] = {
    "gift_likes": ["herb_bundle", "magic_tome", "tea"],
    "gift_dislikes": ["alcohol", "weapons", "meat"]
}
```

**Discovered List** (shown in BondsPanel):
```gdscript
_discovered_likes[character_id] = ["herb_bundle", "tea"]
_discovered_dislikes[character_id] = ["alcohol"]
```

### UI Display

**BondsPanel** shows:
- **Likes**: Only items in `_discovered_likes` (never full list)
- **Dislikes**: Only items in `_discovered_dislikes` (never full list)

**Before Discovery**:
```
Likes: —
Dislikes: —
```

**After Discovering 2 Likes and 1 Dislike**:
```
Likes: Herb Bundle, Tea
Dislikes: Alcohol
```

---

## 15. Love Interests & Romance

### Love Interest Flag

**CSV Field**: `love_interest` (boolean: 0 or 1)

**Example**:
```csv
actor_id,bond_name,love_interest,poly_connects
elara,Elara,1,kael;mira
kael,Kael,1,elara
marcus,Marcus,0,
```

### Love Interest Mechanics

Characters flagged as love interests:
- ✓ Unlock **E10 (Final Event)** after completing E9
- ✓ E10 offers **Friend vs Romance choice**
- ✓ Romance choice locks out other romance routes (unless poly-compatible)
- ✗ Non-LI characters do NOT get E10

### E10 Final Event

**Unlocks**: After E9 completion and meeting Core layer threshold

**Content**:
- Climactic personal story resolution
- **Choice**: "Friend" or "Romance"
- Different endings based on choice

**Friend Route**:
- Maintains platonic relationship
- Unlocks friend-specific abilities
- Can pursue other romances

**Romance Route**:
- Romantic relationship confirmed
- Unlocks romance-specific scenes
- May lock out other romances (unless poly)

### Polyamory System

**CSV Field**: `poly_connects` (semicolon-separated list)

Characters can be poly-compatible with specific others:
```csv
elara,Elara,1,kael;mira
kael,Kael,1,elara
mira,Mira,1,elara
```

**Mechanics**:
- If player romances Elara, they can ALSO romance Kael or Mira
- Kael can romance Elara, but NOT Mira (not in his poly_connects)
- Marcus cannot be romanced alongside anyone (not a love interest)

**Validation**:
```gdscript
func can_romance_both(char_a: String, char_b: String) -> bool:
    var a_poly = _defs[char_a].poly_connects
    var b_poly = _defs[char_b].poly_connects
    return (char_b in a_poly) and (char_a in b_poly)
```

### Romance Tracking

**GameState** stores:
```gdscript
romanced_characters: PackedStringArray = ["elara", "kael"]
```

**Validation on E10**:
```gdscript
func can_start_romance(char_id: String) -> bool:
    for existing in romanced_characters:
        if not can_romance_both(char_id, existing):
            return false  # Incompatible with existing romance
    return true
```

---

## 16. Integration with Combat

### Stats System → Combat

**CombatProfileSystem** queries StatsSystem for combatant stats:

```gdscript
# Get stat levels
var brw = StatsSystem.get_member_stat_level(member_id, "BRW")
var mnd = StatsSystem.get_member_stat_level(member_id, "MND")
var tpo = StatsSystem.get_member_stat_level(member_id, "TPO")
var vtl = StatsSystem.get_member_stat_level(member_id, "VTL")
var fcs = StatsSystem.get_member_stat_level(member_id, "FCS")

# Calculate HP/MP pools
var level = StatsSystem.get_member_level(member_id)
var max_hp = StatsSystem.compute_max_hp(level, vtl)
var max_mp = StatsSystem.compute_max_mp(level, fcs)
```

**Combat Flow**:
1. Battle starts → CombatProfileSystem refreshes all combatant profiles
2. Profiles include base stats from StatsSystem
3. Equipment bonuses applied on top
4. Affinity bonuses applied if applicable
5. Final combat stats used in damage formulas

### Affinity System → Combat

**CombatResolver** applies affinity bonuses to active pairs:

```gdscript
# Check if both members active
if is_in_active_party(member_a) and is_in_active_party(member_b):
    var tier = AffinitySystem.get_affinity_tier(member_a, member_b)
    var bonus = AffinitySystem.get_tier_bonus_multiplier(tier)

    # Apply to BRW, VTL, MND
    final_brw = base_brw * (1.0 + bonus)
    final_vtl = base_vtl * (1.0 + bonus)
    final_mnd = base_mnd * (1.0 + bonus)
```

**Example**:
- Hero (BRW 10) + Elara (BRW 8) at AT2 (10% bonus)
- When both active: Hero BRW = 10 × 1.10 = 11, Elara BRW = 8 × 1.10 = 8.8 → 9

### Bond System → Combat

**Indirect Effects**:
- Bond layer unlocks **Burst attacks** (requires Middle Circle or higher)
- Core layer unlocks **ultimate abilities**
- Romance bonuses may grant special team attacks

**CircleBondSystem** CSV field:
```csv
actor_id,burst_unlocked,reward_core
elara,1,ability_ultimate_heal
```

**Check**:
```gdscript
if CircleBondSystem.get_layer(member_id) >= 3:  # Middle+
    if CircleBondSystem._defs[member_id].burst_unlocked:
        # Can use Burst attacks
```

### SXP Rewards from Combat

**BattleManager** awards SXP based on actions:

```gdscript
# After attack action
StatsSystem.add_sxp_to_member(attacker_id, "BRW", 3)
StatsSystem.add_sxp_to_member(attacker_id, "TPO", 1)

# After skill action
StatsSystem.add_sxp_to_member(caster_id, "MND", 5)
StatsSystem.add_sxp_to_member(caster_id, "FCS", 2)

# After taking damage
StatsSystem.add_sxp_to_member(target_id, "VTL", 2)
```

**Fatigue applies**: If weekly threshold exceeded, gains halved automatically.

### AXP Rewards from Combat

**BattleManager** tracks co-presence and synergy:

```gdscript
# At battle start
func _on_battle_start():
    for pair in active_party_pairs:
        AffinitySystem.add_copresence_axp(pair[0], pair[1], 2)

# During combat
func _on_weakness_exploited(attacker, follower):
    AffinitySystem.add_synergy_axp(attacker, follower, 1, "weakness_chain")

func _on_burst_used(participants):
    for pair in get_pairs(participants):
        AffinitySystem.add_synergy_axp(pair[0], pair[1], 1, "burst")
```

**Caps enforced**: Daily +6 co-presence, per-battle +3 synergy.

---

## 17. Save/Load System

### Stats System Save Data

**Save Format**:
```gdscript
{
    "levels": {"BRW": 5, "MND": 6, "TPO": 7, "VTL": 5, "FCS": 8},
    "xp": {"BRW": 120, "MND": 180, "TPO": 250, "VTL": 100, "FCS": 300},
    "weekly_sxp_hero": {"BRW": 25, "MND": 40, "TPO": 55, "VTL": 15, "FCS": 70},
    "party_dsi": {
        "elara": {
            "char_level": 5,
            "sxp": {"BRW": 80, ...},
            "weekly_sxp": {"BRW": 20, ...},
            "tenths": {"BRW": 5, ...},
            "dsi_tenths": {"BRW": 15, ...}
        },
        ...
    },
    "hero": {"level": 12, "xp": 450}
}
```

**Methods**:
```gdscript
var save_data = StatsSystem.save()
StatsSystem.load(save_data)
```

### Affinity System Save Data

**Save Format**:
```gdscript
{
    "weekly_axp": {"hero|elara": 15.5, "hero|kael": 8.0},
    "lifetime_axp": {"hero|elara": 75, "hero|kael": 42},
    "daily_copresence": {"hero|elara": 4, "hero|kael": 2}
}
```

**Methods**:
```gdscript
var save_data = AffinitySystem.get_save_blob()
AffinitySystem.apply_save_blob(save_data)
```

### Circle Bond System Save Data

**Save Format**:
```gdscript
{
    "event_index": {"elara": 5, "kael": 3},
    "points_bank": {"elara": 18, "kael": 6},
    "layer": {"elara": "Middle", "kael": "Outer"},
    "gift_used_in_layer": {"elara": true, "kael": false},
    "known": {"elara": true, "kael": true, "unknown": false},
    "disc_likes": {"elara": ["herb_bundle", "tea"], "kael": []},
    "disc_dislikes": {"elara": ["alcohol"], "kael": []}
}
```

**Methods**:
```gdscript
var save_data = CircleBondSystem.save()
CircleBondSystem.load(save_data)
```

### GameState Integration

**Coordinated Save**:
```gdscript
# GameState.gd
func save_game() -> Dictionary:
    return {
        "stats": StatsSystem.save(),
        "affinity": AffinitySystem.get_save_blob(),
        "bonds": CircleBondSystem.save(),
        ...
    }

func load_game(data: Dictionary):
    StatsSystem.load(data.stats)
    AffinitySystem.apply_save_blob(data.affinity)
    CircleBondSystem.load(data.bonds)
    ...
```

---

## 18. Weekly Calendar Integration

### CalendarSystem Signals

**File**: `scripts/core/CalendarSystem.gd`

**Signals**:
```gdscript
signal day_advanced(date: Dictionary)  # Every midnight
signal week_reset()                     # Every Sunday → Monday
```

**Date Format**:
```gdscript
{
    "year": 2024,
    "month": 3,
    "day": 15,
    "day_name": "Friday"
}
```

### Stats System Integration

**Daily Trigger** (`day_advanced`):
```gdscript
func _on_day_advanced(date: Dictionary):
    # Apply DSI to all party members
    for member_id in _party_progress.keys():
        if member_id != "hero":
            _apply_daily_dsi(member_id)

    # Check if Monday (reset fatigue)
    var day_index = _dow_index_gregorian(date.year, date.month, date.day)
    if day_index == 0:  # Monday
        reset_week()
```

**Weekly Reset** (`week_reset`):
```gdscript
func _on_week_reset():
    reset_week()  # Clear hero_weekly_sxp and ally weekly_sxp
```

### Affinity System Integration

**Daily Trigger** (`day_advanced`):
```gdscript
func _on_day_advanced(_date: Dictionary):
    reset_daily_caps()  # Clear daily_copresence
```

**Weekly Conversion** (Sunday midnight, before `week_reset`):
```gdscript
func _on_sunday_night():
    convert_weekly_axp()  # Floor → cap → add to lifetime → reset weekly
```

### Day of Week Calculation

**Sakamoto's Algorithm** (Gregorian calendar):
```gdscript
func _dow_index_gregorian(y: int, m: int, d: int) -> int:
    var t = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
    var yy = y - (1 if m < 3 else 0)
    return (yy + yy/4 - yy/100 + yy/400 + t[m-1] + d) % 7  # 0=Mon, 6=Sun
```

**Monday Detection**:
```gdscript
if day_index == 0:
    reset_week()
```

### Weekly Cycle Example

| Day | Date | Event | Stats System | Affinity System |
|-----|------|-------|--------------|----------------|
| Mon | 3/11 | `day_advanced` + `week_reset` | Reset fatigue | Reset daily caps |
| Tue | 3/12 | `day_advanced` | Apply DSI | Reset daily caps |
| Wed | 3/13 | `day_advanced` | Apply DSI | Reset daily caps |
| Thu | 3/14 | `day_advanced` | Apply DSI | Reset daily caps |
| Fri | 3/15 | `day_advanced` | Apply DSI | Reset daily caps |
| Sat | 3/16 | `day_advanced` | Apply DSI | Reset daily caps |
| Sun | 3/17 | `day_advanced` + Sunday conversion | Apply DSI | **Convert weekly AXP** |
| Mon | 3/18 | `day_advanced` + `week_reset` | **Reset fatigue** | Reset daily caps |

**Note**: Sunday is special—AXP conversion happens BEFORE week_reset clears weekly counters.

---

## Summary

### Key Formulas Quick Reference

**Stat Levels**:
```
Total Stat = Base Stat + Bonus Levels from SXP
Bonus Levels = lookup(SXP, [0, 59, 122, 189, 260, 336, 416, 500, 588, 680, 943])
```

**HP/MP**:
```
Max HP = 60 + (VTL × Level × 6)
Max MP = 20 + (FCS × Level × 1.5)
```

**XP to Next Level**:
```
XP_to_next = 120 + (30 × level) + (6 × level²)
```

**Fatigue**:
```
if weekly_sxp[stat] >= 60:
    gain = floor(base_gain × 0.5)
```

**Affinity Bonus**:
```
if both_active(member_a, member_b):
    bonus = tier_bonus[get_tier(lifetime_axp)]  # 0%, 5%, 10%, or 15%
    final_stat = base_stat × (1.0 + bonus)
```

**Bond Progression**:
```
Total BXP Required (E1→E9) = 0 + 20 + 24 + 28 + 32 = 104 points
Event Reward = 6 (base) + dialogue_score + gift_bonus
```

### System Dependencies

```
CalendarSystem
    ↓ day_advanced
    ├→ StatsSystem._on_day_advanced() → Apply DSI
    └→ AffinitySystem._on_day_advanced() → Reset daily caps

CalendarSystem
    ↓ week_reset (Sunday → Monday)
    ├→ StatsSystem.reset_week() → Clear fatigue
    └→ AffinitySystem.convert_weekly_axp() → AXP conversion

BattleManager
    ↓ battle_end
    ├→ StatsSystem.add_sxp_to_member() → Award combat SXP
    ├→ AffinitySystem.add_copresence_axp() → Award co-presence
    ├→ AffinitySystem.add_synergy_axp() → Award synergy
    └→ StatsSystem.add_xp() → Award hero/ally XP

CircleBondSystem
    ↓ complete_event()
    ├→ Award base + dialogue BXP
    ├→ Check threshold → Unlock next event
    └→ Update layer if tier transition event

StatsSystem + AffinitySystem
    ↓ combat_profile_refresh
    └→ CombatProfileSystem → Calculate final combat stats
```

### File References

| System | File Path | Autoload |
|--------|-----------|----------|
| Stats | `scripts/systems/StatsSystem.gd` | `/root/aStatsSystem` |
| Affinity | `scripts/systems/AffinitySystem.gd` | `/root/aAffinitySystem` |
| Circle Bonds | `scripts/circles/CircleBondSystem.gd` | `/root/aCircleBondSystem` |
| Bond DB | `scripts/circles/CircleBondDB.gd` | `/root/aCircleBondDB` |
| Stats Panel | `scripts/main_menu/panels/StatsPanel.gd` | (UI) |
| Bonds Panel | `scripts/main_menu/panels/BondsPanel.gd` | (UI) |
| Party CSV | `data/actors/party.csv` | (Data) |
| Bonds CSV | `data/circles/circle_bonds.csv` | (Data) |
| Events CSV | `data/circles/circles_events.csv` | (Data) |

---

**End of Documentation**
