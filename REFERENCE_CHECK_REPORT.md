# Reference Check Report - Cleanup Safety Analysis

Generated: 2025-10-22

## Executive Summary

**Files to Delete:** 11 scripts
**Autoload Issues Found:** 2 (need fixing)
**Scene References:** 0 (safe)
**Script References:** 0 (safe)

---

## ⚠️ CRITICAL: Autoload Issues Found

### 🔴 Issue #1: aFlagsSystem (DEAD AUTOLOAD)
**Location:** `project.godot:33`
```
aFlagsSystem="*res://scripts/core/FlagsSystem.gd"
```

**Problem:** References an empty 2-line file we want to delete
**Usage Search:** NO references found in any scripts or scenes
**Status:** DEAD AUTOLOAD - never used
**Action Required:** ✅ Remove from project.godot before deleting file

### 🔴 Issue #2: aEnemyDB (BROKEN AUTOLOAD)
**Location:** `project.godot:37`
```
aEnemyDB="*res://scripts/battle/EnemyDB.gd"
```

**Problem:** File doesn't even exist! (only EnemyDB.gd.uid exists)
**Status:** BROKEN - will cause errors if referenced
**Action Required:** ✅ Remove from project.godot

---

## ✅ SAFE TO DELETE: No References Found

### Battle Scripts (6 files)
All empty 2-line stubs in `scripts/battle/`:

#### ✅ AffinitySystem.gd
- **Scene References:** None
- **Script References:** None
- **Autoload:** NO (uses scripts/systems/AffinitySystem.gd instead - line 43)
- **Status:** SAFE TO DELETE

#### ✅ BurstSystem.gd
- **Scene References:** None
- **Script References:** None
- **Autoload:** NO (uses scripts/systems/BurstSystem.gd instead - line 45)
- **Status:** SAFE TO DELETE

#### ✅ CombatSystem.gd
- **Scene References:** None
- **Script References:** None
- **Autoload:** NO
- **Status:** SAFE TO DELETE

#### ✅ CaptureSystem.gd
- **Scene References:** None
- **Script References:** None
- **Autoload:** NO
- **Status:** SAFE TO DELETE

#### ✅ PerkSystem.gd
- **Scene References:** None
- **Script References:** None
- **Autoload:** NO (uses scripts/systems/PerkSystem.gd instead - line 39)
- **Status:** SAFE TO DELETE

#### ✅ SigilsSystem.gd
- **Scene References:** None
- **Script References:** None
- **Autoload:** NO (uses scripts/systems/SigilSystem.gd instead - line 28)
- **Status:** SAFE TO DELETE

### Core Scripts (2 files)

#### ⚠️ FlagsSystem.gd
- **Scene References:** None
- **Script References:** None
- **Autoload:** YES - line 33 `aFlagsSystem`
- **Usage:** None found (dead autoload)
- **Action:** Remove autoload FIRST, then delete file
- **Status:** SAFE TO DELETE (after removing autoload)

#### ✅ InventorySystem.gd (core/)
- **Scene References:** None
- **Script References:** None
- **Autoload:** NO (uses scripts/systems/InventorySystem.gd instead - line 29)
- **Status:** SAFE TO DELETE

### Entity Scripts (3 files)
All empty 2-line stubs in `scripts/entities/`:

#### ✅ Player.gd
- **Scene References:** None
- **Script References:** None
- **Autoload:** NO
- **Status:** SAFE TO DELETE

#### ✅ Enemy.gd
- **Scene References:** None
- **Script References:** None
- **Autoload:** NO
- **Status:** SAFE TO DELETE

#### ✅ PartyMember.gd
- **Scene References:** None
- **Script References:** None
- **Autoload:** NO
- **Status:** SAFE TO DELETE

---

## 📋 CORRECTED CLEANUP PROCEDURE

### Step 1: Fix Autoload Configuration (CRITICAL)

Edit `project.godot` and remove these lines:

```diff
- aFlagsSystem="*res://scripts/core/FlagsSystem.gd"
- aEnemyDB="*res://scripts/battle/EnemyDB.gd"
```

**How to do this:**
- Option A: Open project in Godot Editor → Project Settings → Autoload → Remove aFlagsSystem and aEnemyDB
- Option B: Edit project.godot directly and delete lines 33 and 37

### Step 2: Delete Redundant Files (SAFE)

```bash
# Delete battle/ empty stubs
rm scripts/battle/AffinitySystem.gd
rm scripts/battle/BurstSystem.gd
rm scripts/battle/CombatSystem.gd
rm scripts/battle/CaptureSystem.gd
rm scripts/battle/PerkSystem.gd
rm scripts/battle/SigilsSystem.gd

# Delete core/ duplicates
rm scripts/core/FlagsSystem.gd
rm scripts/core/InventorySystem.gd

# Delete entities/ empty stubs
rm scripts/entities/Player.gd
rm scripts/entities/Enemy.gd
rm scripts/entities/PartyMember.gd
```

### Step 3: Clean Up UID Files (Optional)

Godot creates .uid files for each script. These can be deleted too:

```bash
# Delete associated .uid files
rm scripts/battle/AffinitySystem.gd.uid
rm scripts/battle/BurstSystem.gd.uid
rm scripts/battle/CombatSystem.gd.uid
rm scripts/battle/CaptureSystem.gd.uid
rm scripts/battle/PerkSystem.gd.uid
rm scripts/battle/SigilsSystem.gd.uid
rm scripts/battle/EnemyDB.gd.uid  # Orphaned UID file
rm scripts/core/FlagsSystem.gd.uid
rm scripts/core/InventorySystem.gd.uid
rm scripts/entities/Player.gd.uid
rm scripts/entities/Enemy.gd.uid
rm scripts/entities/PartyMember.gd.uid
```

### Step 4: Remove Empty Directories

```bash
# Check if directories are empty, then remove
rmdir scripts/battle/   # Will only remove if empty (DropTables.gd remains)
rmdir scripts/entities/ # Will only remove if empty
```

**Note:** `scripts/battle/` will NOT be empty because `DropTables.gd` is functional and should stay!

---

## 🎯 VERIFIED SAFE FILES TO KEEP

These files in `scripts/battle/` should **NOT** be deleted:

✅ **DropTables.gd** (514 bytes, functional)
- Used for loot drop calculations
- Autoloaded as `aDropTables` (line 38)
- **Keep this file!**

---

## 📊 Current Autoload Configuration

Here are all the autoloads in your project:

```
Line 20: aCSVLoader           → scripts/core/CSVLoader.gd ✅
Line 21: aSettings            → scripts/core/Settings.gd ✅
Line 22: aGameState           → scripts/core/GameState.gd ✅
Line 23: aSaveLoad            → scripts/core/SaveLoad.gd ✅
Line 24: aCombatProfileSystem → scripts/systems/CombatProfileSystem.gd ✅
Line 25: aMainEventSystem     → scripts/systems/MainEventSystem.gd ✅
Line 26: aCalendarSystem      → scripts/systems/CalendarSystem.gd ✅
Line 27: aStatsSystem         → scripts/systems/StatsSystem.gd ✅
Line 28: aSigilSystem         → scripts/systems/SigilSystem.gd ✅
Line 29: aInventorySystem     → scripts/systems/InventorySystem.gd ✅
Line 30: aWorldSpotsSystem    → scripts/systems/WorldSpotsSystem.gd ✅
Line 31: aSceneRouter         → scripts/core/SceneRouter.gd ✅
Line 32: aAudioBus            → scripts/core/AudioBus.gd ✅
Line 33: aFlagsSystem         → scripts/core/FlagsSystem.gd ❌ DELETE THIS
Line 34: aCircleBondDB        → scripts/circles/CircleBondDB.gd ✅
Line 35: aCircleBondSystem    → scripts/circles/CircleBondSystem.gd ✅
Line 36: aMindTypeSystem      → scripts/systems/MindTypeSystem.gd ✅
Line 37: aEnemyDB             → scripts/battle/EnemyDB.gd ❌ DELETE THIS (file missing!)
Line 38: aDropTables          → scripts/battle/DropTables.gd ✅
Line 39: aPerkSystem          → scripts/systems/PerkSystem.gd ✅
Line 40: aStatusEffects       → scripts/systems/StatusEffects.gd ✅
Line 41: aSchoolSystem        → scripts/systems/SchoolSystem.gd ✅
Line 42: aDormSystem          → scripts/systems/DormSystem.gd ✅
Line 43: aAffinitySystem      → scripts/systems/AffinitySystem.gd ✅
Line 44: aRomanceSystem       → scripts/systems/RomanceSystem.gd ✅
Line 45: aBurstSystem         → scripts/systems/BurstSystem.gd ✅
Line 46: aWorldSystem         → scripts/systems/WorldSystem.gd ✅
Line 47: aPhoneHotkeys        → scripts/systems/PhoneHotkeys.gd ✅
Line 48: aEquipmentSystem     → scripts/systems/EquipmentSystem.gd ✅
Line 49: aStarterLoadout      → scripts/systems/StarterLoadout.gd ✅
```

**Total Autoloads:** 30
**Broken/Dead:** 2 (aFlagsSystem, aEnemyDB)
**After Cleanup:** 28 autoloads

---

## ✅ CONCLUSION

**All 11 files are safe to delete** with one condition:

⚠️ **CRITICAL:** You MUST remove 2 autoloads from project.godot FIRST:
1. `aFlagsSystem` (line 33)
2. `aEnemyDB` (line 37)

**No scene or script references exist** for any of the 11 files.

**After cleanup:**
- 11 fewer scripts
- 2 fewer autoloads (including 1 that was broken)
- Cleaner project structure
- No functionality lost

---

## 🚀 READY TO PROCEED?

You have two options:

**Option A: Manual Cleanup via Godot Editor**
1. Open project in Godot
2. Project Settings → Autoload
3. Remove `aFlagsSystem` and `aEnemyDB`
4. Close Godot
5. Run the bash deletion commands

**Option B: Direct project.godot Edit**
1. Edit `project.godot`
2. Delete lines 33 and 37
3. Save file
4. Run the bash deletion commands

Both are safe! The reference check confirms no active usage.

---

## End of Report
