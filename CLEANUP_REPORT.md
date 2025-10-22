# Psyokin Project Cleanup Report

Generated: 2025-10-22

## Executive Summary

**Total Scripts Analyzed:** 79
**Redundant Duplicates:** 6 scripts (can be safely deleted)
**Empty Placeholders:** 9 scripts (2 lines, no implementation)
**Documented Placeholders:** 5 scripts (save hooks only)
**Functional Minimal Scripts:** 11 scripts (working but simple)
**Fully Implemented Scripts:** 48 scripts

---

## 🗑️ RECOMMENDED FOR DELETION (11 scripts)

### A. Redundant Duplicates (6 scripts)
These are empty stubs in `/scripts/battle/` that have been superseded by fully implemented versions in `/scripts/systems/`:

#### 🔴 DELETE:
1. `scripts/battle/AffinitySystem.gd` (2 lines, empty)
   - ✅ Real version: `scripts/systems/AffinitySystem.gd` (documented placeholder)

2. `scripts/battle/BurstSystem.gd` (2 lines, empty)
   - ✅ Real version: `scripts/systems/BurstSystem.gd` (documented placeholder)

3. `scripts/battle/PerkSystem.gd` (2 lines, empty)
   - ✅ Real version: `scripts/systems/PerkSystem.gd` (9732 lines, FUNCTIONAL)

4. `scripts/battle/SigilsSystem.gd` (2 lines, empty)
   - ✅ Real version: `scripts/systems/SigilSystem.gd` (31671 lines, FUNCTIONAL)

5. `scripts/battle/CombatSystem.gd` (2 lines, empty)
   - ⚠️ No implemented version exists yet (future placeholder)

6. `scripts/battle/CaptureSystem.gd` (2 lines, empty)
   - ⚠️ No implemented version exists yet (future placeholder)

7. `scripts/core/InventorySystem.gd` (2 lines, empty)
   - ✅ Real version: `scripts/systems/InventorySystem.gd` (documented, FUNCTIONAL)

8. `scripts/core/FlagsSystem.gd` (2 lines, empty)
   - ⚠️ Flags are managed directly in GameState (no separate system needed)

### B. Empty Entity Placeholders (3 scripts)
These entity scripts have no implementation. Party members are managed through CSV + GameState/StatsSystem instead:

#### 🔴 DELETE:
9. `scripts/entities/Player.gd` (2 lines, empty)
10. `scripts/entities/Enemy.gd` (2 lines, empty)
11. `scripts/entities/PartyMember.gd` (2 lines, empty)

---

## ⚠️ PLACEHOLDER STUBS - Keep for Future Implementation (5 scripts)

These have documented save/load hooks but no actual logic yet. **Keep these** as they're integrated into GameState:

### In scripts/systems/:
1. ✅ **RomanceSystem.gd** - Documented placeholder for romance mechanics
2. ✅ **BurstSystem.gd** - Documented placeholder for burst meter
3. ✅ **AffinitySystem.gd** - Documented placeholder for elemental affinities
4. ✅ **SchoolSystem.gd** - Placeholder for school/academy system
5. ✅ **WorldSystem.gd** - Placeholder for world state management

**Action:** Keep these - they're part of the save architecture

---

## 📦 MINIMAL BUT FUNCTIONAL - Keep (6 scripts)

These are small but actively used:

1. ✅ **scripts/systems/MindTypeSystem.gd** (31 lines) - Used by SigilSystem for school compatibility
2. ✅ **scripts/core/Settings.gd** (34 lines) - Key/value store for game settings
3. ✅ **scripts/core/SceneRouter.gd** (49 lines) - Scene transition helper
4. ✅ **scripts/core/Boot.gd** (35 lines) - Initial game boot logic
5. ✅ **scripts/core/AudioBus.gd** (30 lines) - Audio management
6. ✅ **scripts/battle/DropTables.gd** (15 lines) - CSV loader for drop tables (stub `roll()` method)

**Action:** Keep these - they're functional utilities

---

## ✅ FULLY IMPLEMENTED SYSTEMS (48 scripts)

These are complete and actively used:

### Core Systems (9 scripts)
- GameState.gd ✅ Documented
- SaveLoad.gd ✅ Documented
- CSVLoader.gd
- Boot.gd
- Settings.gd
- SceneRouter.gd
- AudioBus.gd

### Progression Systems (5 scripts)
- CalendarSystem.gd ✅ Documented
- StatsSystem.gd ✅ Documented
- InventorySystem.gd ✅ Documented
- EquipmentSystem.gd ✅ Documented
- SigilSystem.gd ✅ Documented

### Social Systems (6 scripts)
- DormSystem.gd ✅ Documented
- CircleBondSystem.gd ✅ Documented
- CircleBondDB.gd
- CBXPSystem.gd
- CircleSystem.gd
- MeetupsSystem.gd
- EventRunner.gd

### Battle/Perk Systems (4 scripts)
- PerkSystem.gd ✅ Documented
- CombatProfileSystem.gd
- StatusEffects.gd
- DropTables.gd

### Utility Systems (10 scripts)
- MindTypeSystem.gd
- PartySystem.gd
- IndexSystem.gd
- MainEventSystem.gd
- OutreachSystem.gd
- WorldSpotsSystem.gd
- PhoneHotkeys.gd
- StarterLoadout.gd

### UI Panels (8 scripts)
- LoadoutPanel.gd ✅ Documented
- StatusPanel.gd ✅ Documented
- BondsPanel.gd ✅ Documented
- DormsPanel.gd ✅ Documented
- ItemsPanel.gd
- PerksPanel.gd
- CalendarPanel.gd
- IndexPanel.gd
- ItemInspect.gd
- OutreachPanel.gd
- StatsPanel.gd
- SystemPanel.gd
- SigilSkillMenu.gd

### UI Menus (6 scripts)
- GameMenu.gd
- Title.gd
- SaveLoadMenu.gd
- OptionsMenu.gd
- SaveMenu.gd
- LoadMenu.gd
- PhoneMenu.gd
- MeetupsMenu.gd
- TrainingMenu.gd
- EventUI.gd

### Main Scene (1 script)
- Main.gd ✅ Documented

### Creation (1 script)
- CharacterCreation.gd

### Battle UI (3 scripts)
- BattleHUD.gd
- VictoryScreen.gd
- TargetPicker.gd

### Dev Tools (2 scripts)
- ItemCheatBar.gd
- ProgressionCheatBar.gd

---

## 📋 CLEANUP ACTION PLAN

### Phase 1: Delete Redundant Files (SAFE)

```bash
# Delete empty duplicates in scripts/battle/
rm scripts/battle/AffinitySystem.gd
rm scripts/battle/BurstSystem.gd
rm scripts/battle/CombatSystem.gd
rm scripts/battle/CaptureSystem.gd
rm scripts/battle/PerkSystem.gd
rm scripts/battle/SigilsSystem.gd

# Delete empty core duplicate
rm scripts/core/InventorySystem.gd
rm scripts/core/FlagsSystem.gd

# Delete empty entity stubs
rm scripts/entities/Player.gd
rm scripts/entities/Enemy.gd
rm scripts/entities/PartyMember.gd
```

### Phase 2: Verify No References Exist

After deletion, search for any references:

```bash
grep -r "battle/AffinitySystem" scenes/
grep -r "battle/BurstSystem" scenes/
grep -r "battle/CombatSystem" scenes/
grep -r "battle/CaptureSystem" scenes/
grep -r "battle/PerkSystem" scenes/
grep -r "battle/SigilsSystem" scenes/
grep -r "core/InventorySystem" scenes/
grep -r "core/FlagsSystem" scenes/
grep -r "entities/Player" scenes/
grep -r "entities/Enemy" scenes/
grep -r "entities/PartyMember" scenes/
```

If any references are found, update them to point to the correct systems.

### Phase 3: Clean Empty Folders

```bash
# If scripts/battle/ is now empty, delete it
rmdir scripts/battle/

# If scripts/entities/ is now empty, delete it
rmdir scripts/entities/
```

---

## 🎯 RESULT AFTER CLEANUP

**Before:** 79 scripts
**After:** 68 scripts (11 deleted)

**Benefits:**
- ✅ No redundant duplicates
- ✅ Cleaner project structure
- ✅ Faster searches and navigation
- ✅ Less confusion about which version to use
- ✅ Smaller repository size

---

## ⚠️ WARNINGS

**DO NOT DELETE:**
- Placeholder stubs in `scripts/systems/` (RomanceSystem, BurstSystem, AffinitySystem, SchoolSystem, WorldSystem)
  - These are integrated into GameState.save()/load()
  - Deleting them will break save compatibility

**VERIFY BEFORE DELETING:**
- Check your autoload configuration (Project Settings > Autoload)
- Ensure no scene files reference the empty scripts
- Check if any `.tscn` files attach these as scripts

---

## 📊 Documentation Status

**Fully Documented:** 18/79 scripts (23%)
- All core systems ✅
- All major UI panels ✅
- Main scene ✅

**Remaining to Document:** 50 scripts
- UI menus (9 scripts)
- Utility systems (7 scripts)
- Social systems (4 scripts)
- Battle UI (3 scripts)
- Creation/Dev tools (3 scripts)
- Others (24 scripts)

---

## End of Report
