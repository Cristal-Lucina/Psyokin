# Battle Sequence System - Complete Guide

This system orchestrates tight, polished battle sequences with precise timing, animations, and input control.

## Overview

The Battle Sequence System consists of three CSV files that work together to create the exact battle flow you specified:

1. **battle_sequences.csv** - Defines step-by-step sequences for different battle phases
2. **battle_marker_positions.csv** - Where characters move TO when taking their turn
3. **battle_sequence_timing.csv** - Timing configuration for animations and transitions

## Files

### 1. battle_sequences.csv

Defines the exact flow of events for each battle phase.

**Columns:**
| Column | Description | Example |
|--------|-------------|---------|
| **sequence_id** | Unique ID | 1 |
| **sequence_name** | Name of sequence | BATTLE_START, TURN_START_ALLY |
| **phase** | Phase this belongs to | battle_start, turn_start, action_execute |
| **step** | Step number (order) | 1, 2, 3 |
| **action** | What to do | LOCK_INPUT, RUN_TO_MARKER, SHOW_TEXT |
| **duration** | How long it takes (seconds) | 0.5, 0.3 |
| **fade_duration** | Fade duration (seconds) | 0.8 |
| **camera_distance** | Camera zoom amount | 0.7, 1.0 |
| **lock_input** | Lock input? | TRUE/FALSE |
| **unlock_input** | Unlock input? | TRUE/FALSE |
| **text** | Text to display | "Battle Start!", "[COMBATANT]'s Turn!" |
| **wait_for_input** | Wait for player accept? | TRUE/FALSE |
| **enabled** | Is this step active? | TRUE/FALSE |
| **notes** | Developer notes | Description |

**Sequence Names:**
- **BATTLE_START** - Battle intro sequence
- **TURN_START_ALLY** - Ally turn begins
- **TURN_START_ENEMY** - Enemy turn begins
- **ACTION_ATTACK_ALLY** - Ally attacks
- **ACTION_ATTACK_ENEMY** - Enemy attacks
- **ACTION_ATTACK_HIT** - Attack hits
- **ACTION_ATTACK_MISS** - Attack misses
- **TURN_END** - Turn ends
- **ROUND_END** - Round ends

**Available Actions:**
- **LOCK_INPUT** / **UNLOCK_INPUT** - Control input
- **UNLOCK_ACTION_MENU** - Unlock action menu specifically
- **FADE_IN_BACKGROUND** - Background fades in
- **FADE_IN_CHARACTERS** - Characters fade in
- **CAMERA_FOCUS_ENEMIES** - Camera zooms to enemies
- **SHOW_EXCLAMATION** - Exclamation marks over enemies
- **CAMERA_SLIDE_BACK** - Camera returns to normal
- **FADE_IN_UI** - UI elements fade in
- **SHOW_TEXT** - Display text message
- **PLACE_TURN_ORDER** - Show turn order
- **RUN_TO_MARKER** - Character runs to battle marker
- **FADE_IN_ACTION_MENU** - Action menu appears
- **RUN_BACK** - Character runs back
- **FACE_FORWARD** - Character faces forward
- **WAIT** - Wait for duration

**Text Placeholders:**
- **[COMBATANT]** - Current combatant's name
- **[ATTACKER]** - Attacker's name
- **[TARGET]** - Target's name
- **[ROUND]** - Round number
- **[DAMAGE]** - Damage amount
- **[HEALTH_HINT]** - Health status hint

### 2. battle_marker_positions.csv

Defines where characters move TO when it's their turn (the "battle marker" position).

**Columns:**
| Column | Description | Example |
|--------|-------------|---------|
| **marker_id** | Unique ID | 1 |
| **side** | ally or enemy | ally |
| **position_index** | Position (0, 1, 2) | 0 |
| **marker_name** | Descriptive name | Hero Battle Marker |
| **marker_x** | X offset from starting position | 80 (pixels) |
| **marker_y** | Y offset from starting position | 40 |
| **run_duration** | How long run takes | 0.4 (seconds) |
| **face_direction** | Which way to face | RIGHT, LEFT |
| **notes** | Description | Hero's action position |

**How It Works:**
- Starting position: Where character begins (from character_marker_positions.csv)
- Battle marker: Where they move TO for their action
- Example: Hero starts at X=40, marker_x=80, so they move to X=120

### 3. battle_sequence_timing.csv

Global timing configuration for animations and transitions.

**Columns:**
| Column | Description | Example |
|--------|-------------|---------|
| **timing_id** | Unique ID | 1 |
| **event_name** | Name of timed event | background_fade_in |
| **duration** | Event duration (seconds) | 0.8 |
| **fade_duration** | Fade time (seconds) | 0.8 |
| **wait_after** | Pause after event | 0.5 |
| **enabled** | Is this active? | TRUE/FALSE |
| **notes** | Description | Background fades in |

**Timing Events:**
- **background_fade_in** - Background appears
- **characters_fade_in** - Characters appear
- **camera_focus_enemies** - Camera zoom
- **exclamation_show** - Exclamation effect
- **camera_slide_back** - Camera returns
- **ui_fade_in** - UI appears
- **run_to_marker** - Run to battle position
- **run_back** - Run back to start
- **action_menu_fade_in** / **action_menu_fade_out** - Menu transitions
- **hit_animation** / **hurt_animation** / **guard_animation** - Combat animations
- **miss_text_show** - MISS text
- **turn_order_slide_out** - Turn order exit
- **turn_marker_move** - Turn indicator moves

## Battle Flow Breakdown

### Battle Start Sequence

```
1. LOCK_INPUT                    - Lock all input
2. FADE_IN_BACKGROUND (0.8s)     - Location appears
3. FADE_IN_CHARACTERS (0.8s)     - Characters appear
4. CAMERA_FOCUS_ENEMIES (0.5s)   - Zoom to enemies (0.7x)
5. SHOW_EXCLAMATION (0.3s)       - ! ! ! over enemies
6. WAIT (0.5s)                   - Hold dramatic moment
7. CAMERA_SLIDE_BACK (0.6s)      - Return to normal (1.0x)
8. FADE_IN_UI (0.5s)             - UI elements appear
9. SHOW_TEXT "Battle Start!" >   - Battle announcement
10. PLACE_TURN_ORDER             - Show turn order
```

### Ally Turn Start

```
1. SHOW_TEXT "[Name]'s Turn!" >  - Turn announcement
2. RUN_TO_MARKER (0.4s)          - Run to battle marker
3. FADE_IN_ACTION_MENU (0.3s)    - Menu appears
4. UNLOCK_ACTION_MENU            - Enable input
```

### Attack Flow (Hit)

```
1. LOCK_ACTION_MENU              - Lock menu
2. UNLOCK_TARGET_SELECT          - Enable targeting
3. WAIT_TARGET_SELECT            - Player selects
4. LOCK_TARGET_SELECT            - Lock selection
5. CALCULATE_HIT                 - Roll hit check
6. START_MINIGAME                - Attack minigame
7. WAIT_MINIGAME                 - Player plays
8. LOCK_MINIGAME                 - Lock when done
9. CALCULATE_DAMAGE              - Roll damage
10. PLAY_ATTACK_ANIM (0.3s)      - Attacker animates
11. PLAY_HURT_ANIM (0.3s)        - Defender hurt
12. BOTH_TO_IDLE                 - Return to idle
13. SHOW_TEXT "[A] attacked [T]!" - Attack message
14. SHOW_TEXT "[T] hit for [D]!" - Damage message
15. SHOW_TEXT "[Health hint]" >  - Health status
```

### Attack Flow (Miss)

```
1-5. (same as hit)
6. SHOW_MISS_TEXT (0.2s)         - MISS appears
7. PLAY_ATTACK_ANIM (0.3s)       - Attacker swings
8. PLAY_GUARD_ANIM (0.3s)        - Defender blocks
9. BOTH_TO_IDLE                  - Return to idle
10. SHOW_TEXT "[A] attacked [T]!" - Attack message
11. SHOW_TEXT "The attack missed!" > - Miss message
```

### Turn End

```
1. RUN_BACK (0.4s)               - Back to start position
2. FACE_FORWARD                  - Turn to face enemies
3. MOVE_TURN_MARKER (0.2s)       - Highlight next turn
```

### Round End

```
1. SLIDE_OUT_TURN_ORDER (0.4s)   - Turn order exits
2. SHOW_TEXT "End of round!" >   - Round end message
3. CALCULATE_INITIATIVE          - Roll new turn order
4. PLACE_TURN_ORDER              - Show new order
5. SHOW_TEXT "Round [R] - [Name]'s Turn!" > - New round
```

## Making Adjustments

### Make battle start faster

Edit **battle_sequences.csv**:
```csv
sequence_id,sequence_name,phase,step,action,duration,fade_duration
2,BATTLE_START,battle_start,2,FADE_IN_BACKGROUND,0,0.4
3,BATTLE_START,battle_start,3,FADE_IN_CHARACTERS,0,0.4
```
Change `fade_duration` from 0.8 to 0.4

### Change battle marker position

Edit **battle_marker_positions.csv**:
```csv
marker_id,side,position_index,marker_x
1,ally,0,100
```
Change `marker_x` from 80 to 100 (move further forward)

### Adjust run speed

Edit **battle_marker_positions.csv**:
```csv
marker_id,run_duration
1,0.3
```
Change `run_duration` from 0.4 to 0.3 (faster)

### Disable battle start camera zoom

Edit **battle_sequences.csv**:
```csv
sequence_id,enabled
4,FALSE
5,FALSE
6,FALSE
7,FALSE
```
Set camera-related steps to `enabled=FALSE`

### Skip action menu fade

Edit **battle_sequences.csv**:
```csv
sequence_id,sequence_name,action,enabled
13,TURN_START_ALLY,FADE_IN_ACTION_MENU,FALSE
```
Set to FALSE to skip fade (instant appear)

## Integration with Battle.gd

The system is accessed through `battle_sequence_orch`:

```gdscript
# Run battle start sequence
await battle_sequence_orch.run_sequence("BATTLE_START", {})

# Run ally turn start
await battle_sequence_orch.run_sequence("TURN_START_ALLY", {
	"combatant": current_combatant,
	"round": battle_mgr.current_round
})

# Run attack hit sequence
await battle_sequence_orch.run_sequence("ACTION_ATTACK_HIT", {
	"combatant": attacker,
	"target": target,
	"damage": damage_amount
})
```

## Current Implementation Status

✅ **Implemented:**
- CSV loading system
- Sequence orchestrator
- Basic actions (text, wait, input locking)
- Run to marker
- Run back
- Action menu fade

⏳ **To Implement:**
- Camera zoom/focus
- Background fade
- Character fade in
- Exclamation effects
- UI fade in
- Attack/hurt/guard animations
- MISS text display
- Minigame integration
- Full hit/miss flow

## Next Steps

The system is ready to use! To implement the full battle flow:

1. **Battle Start** - Add camera and fade implementations
2. **Turn Flow** - Connect to existing turn system
3. **Combat** - Integrate attack animations and minigames
4. **Round End** - Add turn order slide animations

Each sequence is modular and can be tested independently!
