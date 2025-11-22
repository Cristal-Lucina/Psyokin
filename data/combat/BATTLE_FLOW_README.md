# Battle Flow Manager - CSV Configuration Guide

This guide explains how to use the CSV databases to configure battle flow and special events.

## Files Overview

1. **battle_flow_config.csv** - Controls how battle elements behave
2. **battle_events.csv** - Defines special battle events and triggers

---

## 1. battle_flow_config.csv

Controls the main battle scene behavior including element priorities, concurrent allowances, and which elements activate on battle start.

### Columns

| Column | Description | Valid Values |
|--------|-------------|--------------|
| **element_id** | Unique ID (1-38) | Integer |
| **element_name** | Descriptive name | String |
| **priority** | Execution priority | 0-5 (CRITICAL, URGENT, HIGH, MEDIUM, LOW, AMBIENT) |
| **can_interrupt** | Can this interrupt other elements? | TRUE/FALSE |
| **concurrent_with** | Element IDs that can run at same time | "1,2,3" or "ALL" or "" |
| **active_on_battle_start** | Activate when battle begins? | TRUE/FALSE |
| **notes** | Developer notes | String |

### Priority Levels

- **0 (CRITICAL)** - Highest priority, blocks everything (Input, State Machine, Pause)
- **1 (URGENT)** - Very high priority (Events Queue, Targeting, Reactions)
- **2 (HIGH)** - High priority (Animations, Minigames, Camera)
- **3 (MEDIUM)** - Medium priority (Effects, Damage Numbers, Sounds)
- **4 (LOW)** - Low priority (UI Panels, Status Display)
- **5 (AMBIENT)** - Lowest priority (Background Music, Environment)

### Concurrent Element IDs

Use comma-separated element IDs to specify which elements can run simultaneously:

```csv
14,15,17,20,24,25  # Can run with these specific elements
ALL                # Can run with any element
                   # Empty = Cannot run concurrently
```

### Example Rows

```csv
element_id,element_name,priority,can_interrupt,concurrent_with,active_on_battle_start,notes
1,BATTLE_STATE_MACHINE,0,TRUE,"2,6,7,9,10,11,12",TRUE,Core state machine - highest priority
14,CHARACTER_ANIMATION,3,FALSE,"ALL",FALSE,Character sprite animations
30,ACTION_MENU,1,FALSE,"6,7,9,10,11,12,28,29,31,32,33,34,35",FALSE,Player action menu
```

### How It Works

1. **Priority determines execution order** - Lower number = higher priority
2. **Elements with higher priority can block lower priority elements**
3. **Concurrent_with allows elements to run simultaneously** despite priority
4. **active_on_battle_start automatically activates elements** when battle begins

---

## 2. battle_events.csv

Defines special events that trigger during battle based on conditions.

### Columns

| Column | Description | Valid Values |
|--------|-------------|--------------|
| **event_id** | Unique event ID | Integer |
| **event_name** | Descriptive name (uppercase) | String |
| **trigger_type** | What type of trigger | See Trigger Types below |
| **trigger_condition** | When to trigger | See Condition Format below |
| **priority** | Event priority | CRITICAL, URGENT, HIGH, MEDIUM, LOW |
| **actions** | Actions to execute | Semicolon-separated list |
| **repeatable** | Can trigger multiple times? | TRUE/FALSE |
| **enabled** | Is this event active? | TRUE/FALSE |
| **notes** | Developer notes | String |

### Trigger Types

- **HP_THRESHOLD** - When HP crosses a threshold
- **TURN_COUNT** - Based on turn number
- **ROUND_NUMBER** - Based on round number
- **GAUGE_THRESHOLD** - When a gauge reaches a value
- **COMBO_COUNT** - Combo counter milestones
- **CRIT_COUNT** - Critical hit streaks
- **DAMAGE_THRESHOLD** - Damage taken/dealt
- **STATUS_CHANGE** - Status effects applied/removed
- **TIME_THRESHOLD** - Battle time limit
- **ESCAPE_COUNT** - Number of escape attempts
- **BATTLE_END** - When battle ends

### Condition Format

Conditions use format: `variable_operator_value`

**Operators:**
- **below** - Less than (e.g., `enemy_hp_below_50`)
- **above** - Greater than (e.g., `burst_gauge_above_75`)
- **equals** - Exactly equal (e.g., `turn_number_equals_1`)
- **mod** - Modulo operation (e.g., `turn_number_mod_5_equals_0`)

**Examples:**
```csv
enemy_hp_below_50              # Enemy HP is below 50
all_party_hp_below_25          # All party members below 25 HP
turn_number_equals_1           # First turn
combo_count_equals_5           # 5-hit combo
battle_time_above_300          # Battle lasted 5+ minutes
turn_number_mod_5_equals_0     # Every 5th turn
```

### Available Actions

**Input Control:**
- LOCK_INPUT, UNLOCK_INPUT
- PAUSE_BATTLE, RESUME_BATTLE

**Audio:**
- PLAY_SOUND, PLAY_WARNING_SOUND, PLAY_ACHIEVEMENT_SOUND
- PLAY_HEAL_SOUND, PLAY_STATUS_SOUND, PLAY_SPECIAL_SOUND
- PLAY_URGENT_MUSIC, PLAY_PERFECT_MUSIC

**Visual Effects:**
- FLASH_SCREEN, CAMERA_SHAKE, SLOW_MOTION
- PULSE_HP_BARS, PULSE_TIMER
- SPARKLE_EFFECT
- CHANGE_BACKGROUND, PLAY_WEATHER_EFFECT

**UI:**
- SHOW_MESSAGE, SHOW_NOTIFICATION, SHOW_COMBO_TEXT
- SHOW_TUTORIAL_POPUP, SHOW_BADGE, SHOW_TIMER
- SHOW_HINT, SHOW_WARNING, SHOW_STATUS_ICON
- HIGHLIGHT_CAPTURE_BUTTON

**Gameplay:**
- SPAWN_ENEMIES, PLAY_CUTSCENE, BOSS_TRANSFORM
- BONUS_DAMAGE, BONUS_REWARD, BONUS_REWARDS
- APPLY_WEATHER_BUFFS, INCREASE_ESCAPE_DIFFICULTY
- SPECIAL_ANIMATION

### Example Events

```csv
event_id,event_name,trigger_type,trigger_condition,priority,actions,repeatable,enabled,notes
1,BOSS_PHASE_TRANSITION,HP_THRESHOLD,enemy_hp_below_50,CRITICAL,"LOCK_INPUT;PLAY_CUTSCENE;BOSS_TRANSFORM;UNLOCK_INPUT",FALSE,TRUE,Boss transforms at 50% HP
2,TUTORIAL_FIRST_TURN,TURN_COUNT,turn_number_equals_1,URGENT,"PAUSE_BATTLE;SHOW_TUTORIAL_POPUP;RESUME_BATTLE",FALSE,TRUE,Show tutorial on first turn
4,BURST_GAUGE_FULL,GAUGE_THRESHOLD,burst_gauge_equals_100,MEDIUM,"PLAY_SOUND;FLASH_SCREEN;SHOW_NOTIFICATION",TRUE,TRUE,Notify when burst gauge is full
```

---

## Making Changes

### To Adjust Battle Flow:

1. **Open `battle_flow_config.csv`** in a spreadsheet editor or text editor
2. **Find the element** you want to modify
3. **Change priority** to make it execute earlier/later
4. **Update concurrent_with** to allow/prevent simultaneous execution
5. **Toggle active_on_battle_start** to auto-activate

**Example:** Make damage numbers show faster:
```csv
Before: 20,DAMAGE_NUMBERS_QUEUE,3,FALSE,"6,7,9,10,11,12,14,15,17,24,25",FALSE
After:  20,DAMAGE_NUMBERS_QUEUE,2,FALSE,"6,7,9,10,11,12,14,15,17,24,25",FALSE
        ↑ Changed priority from 3 (MEDIUM) to 2 (HIGH)
```

### To Add Special Events:

1. **Open `battle_events.csv`**
2. **Add a new row** with a unique event_id
3. **Define the trigger** (when it happens)
4. **List the actions** (what it does) separated by semicolons
5. **Set enabled=TRUE** to activate it

**Example:** Add low MP warning:
```csv
16,LOW_MP_WARNING,HP_THRESHOLD,party_mp_below_10,MEDIUM,"PLAY_WARNING_SOUND;SHOW_WARNING",TRUE,TRUE,Warn when MP is critically low
```

### To Disable Events:

Change `enabled` column from `TRUE` to `FALSE`:

```csv
Before: 13,WEATHER_CHANGE,TURN_COUNT,turn_number_mod_5_equals_0,LOW,"...",TRUE,TRUE
After:  13,WEATHER_CHANGE,TURN_COUNT,turn_number_mod_5_equals_0,LOW,"...",TRUE,FALSE
                                                                                    ↑
```

---

## Testing Changes

1. Save the CSV file
2. Launch the battle scene in Godot
3. Watch the console for `[BattleFlow]` and `[BattleEvent]` messages
4. Verify elements activate in the correct order
5. Check that events trigger at the right times

---

## Troubleshooting

### Elements Not Loading
- Check CSV file is saved in `data/combat/`
- Verify no syntax errors (missing commas, extra quotes)
- Look for `[BattleFlowConfigLoader]` errors in console

### Events Not Triggering
- Verify `enabled=TRUE`
- Check trigger_condition format matches expected variables
- Ensure event hasn't already triggered if `repeatable=FALSE`

### Priority Issues
- Lower number = higher priority (0 is highest)
- Elements with same priority execute in order encountered
- Use concurrent_with to allow simultaneous execution

---

## Advanced Tips

### Creating Event Chains

Use multiple events with different triggers to create sequences:

```csv
17,BOSS_WARNING,HP_THRESHOLD,enemy_hp_below_75,HIGH,"PLAY_WARNING_SOUND;SHOW_MESSAGE",FALSE,TRUE,Boss getting angry
1,BOSS_PHASE_TRANSITION,HP_THRESHOLD,enemy_hp_below_50,CRITICAL,"LOCK_INPUT;PLAY_CUTSCENE;BOSS_TRANSFORM;UNLOCK_INPUT",FALSE,TRUE,Boss transforms
18,BOSS_ENRAGE,HP_THRESHOLD,enemy_hp_below_25,HIGH,"PLAY_URGENT_MUSIC;SHOW_WARNING",FALSE,TRUE,Boss enters rage mode
```

### Balancing Priorities

- Reserve 0 (CRITICAL) for input and pause only
- Use 1 (URGENT) for game-critical systems
- Most elements should be 2-4 (HIGH to LOW)
- Background elements use 5 (AMBIENT)

### Performance Optimization

- Set concurrent_with="ALL" for non-interfering elements (music, backgrounds)
- Use specific element lists for elements that need coordination
- Disable unused events with enabled=FALSE instead of deleting them
