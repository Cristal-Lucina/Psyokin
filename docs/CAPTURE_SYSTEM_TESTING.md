# Capture System Testing Guide

## Overview
The capture and morality system has been implemented! This guide explains how to test it.

## What Was Implemented

### 1. Capture Mechanics (Chapter 4.8)
- **Capture Button**: New action button in battle UI
- **Bind Items**: Five tiers of capture items (BIND_001 through BIND_005)
- **Capture Formula**:
  ```
  Catch% = Base(35) + ItemMod - EnemyResist - 0.4×HP% + StateBonus
  ```
  - ItemMod: +10/+25/+40/+60/+100 depending on bind tier
  - EnemyResist: 0-60 from enemy data
  - HP%: Current HP as percentage (lower = better chance)
  - StateBonus: +15 for Sleep/Freeze/Bound, +10 for Stunned/Fallen

### 2. Morality System (Chapter 14)
- **Morality Meter**: Tracked in MoralitySystem autoload
- **Range**: -100 to +100
- **Diminishing Returns**: Applied automatically (see formula below)
- **Daily Cap**: ±30 points per calendar day
- **Tier System**: P3, P2, N, B2, B3 based on meter value

### 3. Battle Outcome Tracking
- **Kills vs Captures**: BattleManager tracks each defeat by enemy type
- **Morality Deltas** (applied at victory):
  - Regular Kill: -1, Regular Capture: +1
  - Elite Kill: -3, Elite Capture: +3
  - Boss Kill: -15, Boss Capture: +15
- **Non-Lethal Rewards** (when all enemies captured):
  - LXP: ×0.30
  - Credits: ×1.5
  - Drop Rate: ×1.5

## Testing the System

### Starting the Game
The game now automatically gives you test bind items when Main.gd loads:
- 5× Weak Bind (+10 capture)
- 3× Standard Bind (+25 capture)
- 2× Strong Bind (+40 capture)

### How to Capture Enemies

1. **Trigger a Battle**
   - Walk around until you encounter enemies

2. **Lower Enemy HP**
   - Attack enemies to reduce their HP (lower HP = higher capture chance)
   - Optional: Apply status effects (Sleep, Stun, etc.) for bonuses

3. **Use Capture Button**
   - Click the "Capture" button in the action menu
   - The game will auto-select your first available bind item
   - Click the enemy you want to capture

4. **View Results**
   - Success: Enemy is captured, falls off screen like KO
   - Failure: Enemy breaks free, battle continues
   - The bind item is consumed either way

### Testing Morality Changes

1. **Pure Lethal Run**
   - Kill all enemies in battle (don't capture any)
   - Check console for morality deltas at victory
   - Example: 3 Regular kills = -3 morality

2. **Pure Capture Run**
   - Capture all enemies (don't kill any)
   - Check console for morality deltas at victory
   - Example: 3 Regular captures = +3 morality

3. **Mixed Battle**
   - Kill some enemies, capture others
   - Both penalties and bonuses will be applied

4. **Check Morality Meter**
   - Currently logged to console only
   - TODO: Display on status screen

### Expected Behaviors

- **Capture Chance Display**: Shows in battle log when attempting capture
- **Turn Cell Animation**: Captured enemies fall off screen (same as KO)
- **Bind Consumption**: Item is consumed whether capture succeeds or fails
- **Battle Victory**: Works with any combination of kills/captures
- **Morality Tracking**: Applied automatically at battle end

### Console Output Examples

```
[BattleManager] Recorded capture: Slime (Regular)
[BattleManager] Recorded kill: Dark Knight (Elite)
[BattleManager] Applied morality: Kills={"Elite": 1}, Captures={"Regular": 2}
[MoralitySystem] Applied delta: +1 for Captured Regular enemy (meter: 1)
[MoralitySystem] Applied delta: +1 for Captured Regular enemy (meter: 2)
[MoralitySystem] Applied delta: -3 for Killed Elite enemy (meter: -1)
```

## Testing Scenarios

### Scenario 1: Basic Capture Test
1. Start battle
2. Damage enemy to ~25% HP
3. Use Weak Bind (+10)
4. Observe capture chance (should be moderate)
5. Verify enemy is removed on success

### Scenario 2: High Capture Chance
1. Start battle
2. Damage enemy to ~10% HP
3. Apply Stun/Sleep if available
4. Use Strong Bind (+40)
5. Should have very high success rate

### Scenario 3: Low Capture Chance
1. Start battle
2. Use Weak Bind on full HP enemy
3. Should have low success rate
4. Verify bind is consumed even on failure

### Scenario 4: Morality Delta Testing
1. Fight 3 battles
2. Battle 1: Kill all enemies
3. Battle 2: Capture all enemies
4. Battle 3: Mix of kills and captures
5. Check console for morality changes

## Known Limitations / TODOs

### Missing Features
- ☐ Bind item selection menu (currently auto-selects first available)
- ☐ Capture chance preview when hovering enemies
- ☐ Morality UI display on status screen
- ☐ Morality change toast notifications
- ☐ Non-lethal reward modifiers (needs reward system integration)
- ☐ VR battle flag (will be added when VR system implemented)

### Testing Tools Needed
- Manual way to check morality meter value
- Status screen UI for morality display
- In-game calendar to test daily reset

## File Changes

### New/Modified Files
- `scripts/battle/CombatResolver.gd`: Added capture chance calculation
- `scripts/battle/Battle.gd`: Added capture button handler and execution
- `scripts/battle/BattleManager.gd`: Added kill/capture tracking
- `scenes/battle/Battle.tscn`: Added CaptureButton to action menu
- `scripts/main/Main.gd`: Added test bind item helper
- `data/actors/enemies.csv`: Added capture_resist and env_tag columns
- `data/items/items.csv`: Added BIND_001-005 items with capture_mod

### Existing Systems Used
- `scripts/systems/MoralitySystem.gd`: Already implemented
- `scripts/systems/InventorySystem.gd`: For bind item management
- `scripts/battle/TurnOrderDisplay.gd`: For capture animations

## Formulas Reference

### Capture Chance
```
Catch% = clamp(Base + ItemMod - EnemyResist - 0.4×HP% + StateBonus, 0, 100)
```

### Morality Diminishing Returns
```
applied_delta = sign(raw_delta) × floor(|raw_delta| × (1 - 0.5 × |M|/100) + 0.5)
```
Where M is current morality meter value.

### Daily Cap
The system tracks accumulated deltas per calendar day. Once ±30 is reached, further deltas are capped at ±30 for that day. Resets at calendar date change (month/day format).

## Next Steps

To complete the system:
1. Add morality UI to status screen (show meter next to portrait)
2. Integrate with reward system for non-lethal modifiers
3. Add bind item selection menu (if more than one type available)
4. Add VR battle flag system
5. Create morality tier effects (dialogue changes, access to areas, etc.)

## Questions/Issues?

If you encounter issues:
1. Check console output for error messages
2. Verify bind items are in inventory (should auto-add on game start)
3. Confirm MoralitySystem autoload is registered
4. Check that enemies have capture_resist and env_tag in CSV

Happy testing!
