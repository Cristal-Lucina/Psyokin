# Unified Panel Architecture Design

**Created:** 2025-11-04
**Branch:** `claude/pull-from-main-011CUmvLCYMELiqfZTQVTdkT`

---

## Executive Summary

This document outlines the unified architecture for all GameMenu panels in Psyokin. The goal is to create a cohesive, consistent experience across all panels by:

1. **Standardizing on PanelBase** - All panels extend `PanelBase` for consistent lifecycle management
2. **Unified Popup System** - Use `ConfirmationPopup` and `ToastPopup` throughout
3. **Consistent Navigation** - NavState pattern with accept-to-move flow
4. **Centralized Data Access** - Pull from `CombatProfileSystem` and `GameState`
5. **Panel Stack Management** - Integrate with `aPanelManager`

---

## GameMenu Navigation Architecture

**Important:** StatusPanel is the **root/entry panel** of GameMenu.

### Navigation Flow

```
GameMenu Opens
    └─> StatusPanel (ALWAYS visible first - no button to access it)
         ├─ Tab List (Left): Shows all other panels
         │   ├─ Stats (StatusPanel itself)
         │   ├─ Perks → PerksPanel
         │   ├─ Items → ItemsPanel
         │   ├─ Loadout → LoadoutPanel
         │   ├─ Bonds → BondsPanel
         │   ├─ Outreach → OutreachPanel
         │   ├─ Dorms → DormsPanel
         │   ├─ Calendar → CalendarPanel
         │   ├─ Index → IndexPanel
         │   └─ System → SystemPanel
         │
         └─ Content (Right): Party status, HP/MP, money, date/time
```

**User Experience:**
1. Open GameMenu → **StatusPanel appears automatically**
2. Navigate **right** from tab list → Enter StatusPanel content (party management)
3. Press **Accept** on a different tab → Switch to that panel (PerksPanel, DormsPanel, etc.)
4. Press **Back** from other panels → Return to StatusPanel

**Key Insight:** StatusPanel has dual role:
- **Hub panel:** Shows tabs to access all other panels
- **Content panel:** Shows party status, HP/MP, and provides party management features

---

## Current State Analysis

### ✅ Panels Following Best Practices

**DormsPanel** (REFERENCE PATTERN)
- ✅ Extends `PanelBase`
- ✅ Uses `NavState` enum (ROSTER_SELECT, COMMON_SELECT, ROOM_SELECT, ACTION_SELECT)
- ✅ Uses `ConfirmationPopup.create()` and `ToastPopup.create()`
- ✅ Custom `_input()` for controller navigation
- ✅ Accept-to-move flow with `_nav_state_history`
- ✅ Panel animations on focus change
- ✅ Integration with `aPanelManager`

**BondsPanel**
- ✅ Extends `PanelBase`
- ✅ Has `NavState` enum (BOND_LIST, BOND_DETAIL)
- ❌ Uses ad-hoc CanvasLayer popups instead of ConfirmationPopup/ToastPopup
- ✅ Custom `_input()` for navigation

**OutreachPanel**
- ✅ Extends `PanelBase`
- ✅ Has `NavState` enum (CATEGORY_SELECT, MISSION_LIST, POPUP_ACTIVE)
- ❌ Creates Panel nodes manually instead of using ConfirmationPopup/ToastPopup
- ✅ Custom `_input()` for navigation

### ❌ Panels Needing Major Refactoring

**StatusPanel** ⭐ (ROOT/HUB PANEL - shown first when GameMenu opens)
- ❌ Extends `Control` (should extend `PanelBase`)
- ⚠️ Has simple NavState (MENU, CONTENT, POPUP_ACTIVE) - this is actually good!
- ❌ Creates Panel nodes manually with `_style_popup_panel()`, manual fade animations
- ❌ Manual `aPanelManager` push/pop logic
- ✅ Custom `_input()` for navigation
- 🎯 **Special Role:** Serves as both hub (tab list to other panels) AND content panel (party management)

**CalendarPanel**
- ❌ Extends `Control` (should extend `PanelBase`)
- ❌ No NavState machine (simple display panel)
- ✅ No popups needed (display only)

**IndexPanel**
- ❌ Extends `Control` (should extend `PanelBase`)
- ❌ No NavState machine
- ⚠️ Has filter-based navigation that could benefit from states

**SystemPanel**
- ❌ Extends `Control` (should extend `PanelBase`)
- ❌ No NavState machine
- ✅ Opens overlays using `_open_overlay()` (different pattern, may be OK)

**SigilSkillMenu**
- ❌ Extends `Control` (should extend `PanelBase`)
- ⚠️ Has `NavMode` enum (SOCKET_NAV, SKILLS_NAV) but should use NavState pattern
- ❌ No popup system analysis yet

---

## Unified Architecture Design

### 1. Base Class Hierarchy

```gdscript
Control (Godot)
  └─ PanelBase (scripts/core/PanelBase.gd)
      ├─ StatusPanel
      ├─ PerksPanel
      ├─ ItemsPanel
      ├─ LoadoutPanel
      ├─ BondsPanel
      ├─ OutreachPanel
      ├─ DormsPanel ✅ (reference)
      ├─ CalendarPanel
      ├─ IndexPanel
      ├─ SystemPanel
      └─ SigilSkillMenu
```

### 2. Popup System (MANDATORY)

**All panels MUST use these classes for popups:**

```gdscript
# YES/NO confirmation dialogs
var popup = ConfirmationPopup.create("Are you sure?")
add_child(popup)
var result: bool = await popup.confirmed
popup.queue_free()
if result:
    # User pressed Accept
else:
    # User pressed Cancel/Back

# Notice/toast messages
var popup = ToastPopup.create("Operation successful!", "Success")
add_child(popup)
await popup.confirmed
popup.queue_free()
```

**Key Benefits:**
- Automatic input blocking via `set_input_as_handled()`
- Consistent styling (dark gray bg, pink border, rounded corners)
- Controller support (Accept/Back/Left/Right)
- Process even when game paused (`PROCESS_MODE_ALWAYS`)
- Auto-centering and focus management

**⚠️ CRITICAL: Popup Usage When Game is Paused**

When showing popups while the game is paused (like in GameMenu where `get_tree().paused = true`), you **MUST** use a CanvasLayer overlay with `PROCESS_MODE_ALWAYS`:

```gdscript
# Create CanvasLayer overlay for popup (ensures it's on top and processes input first)
var overlay := CanvasLayer.new()
overlay.layer = 100  # High layer to ensure it's on top
overlay.process_mode = Node.PROCESS_MODE_ALWAYS  # Process even when paused
get_tree().root.add_child(overlay)
get_tree().root.move_child(overlay, 0)  # Move to first position so it processes input first

# Create and show popup
var popup := ConfirmationPopup.create(message)
popup.process_mode = Node.PROCESS_MODE_ALWAYS  # Process even when paused
overlay.add_child(popup)

# Wait for user response
var result: bool = await popup.confirmed

# Clean up
popup.queue_free()
overlay.queue_free()
```

**Why this is necessary:**
1. **GameMenu pauses the game** when visible (`get_tree().paused = true`)
2. Without `PROCESS_MODE_ALWAYS`, nodes **don't receive ANY input events** while paused
3. The overlay needs `PROCESS_MODE_ALWAYS` to render and process input
4. The popup needs `PROCESS_MODE_ALWAYS` to handle button presses
5. Moving overlay to position 0 ensures it processes input **before** other UI elements

**Common mistake:** Forgetting to set `process_mode` on both the overlay AND the popup will result in a popup that is visible but doesn't respond to any input.

**❌ NEVER DO THIS:**
```gdscript
# DON'T create Panel nodes manually
var popup_panel: Panel = Panel.new()
popup_panel.process_mode = Node.PROCESS_MODE_ALWAYS
# ... manual styling, manual positioning, manual input handling
```

```gdscript
# DON'T create CanvasLayer popups manually
var canvas_layer := CanvasLayer.new()
canvas_layer.layer = 100
# ... manual creation
```

### 3. Navigation State Machine Pattern

**For panels with multi-section navigation (like DormsPanel, BondsPanel):**

```gdscript
extends PanelBase
class_name YourPanel

enum NavState { SECTION_A, SECTION_B, SECTION_C, POPUP_ACTIVE }
var _nav_state: NavState = NavState.SECTION_A
var _nav_state_history: Array[NavState] = []

# Navigation indices
var _section_a_index: int = 0
var _section_b_index: int = 0

# Button arrays for each section
var _section_a_buttons: Array[Button] = []
var _section_b_buttons: Array[Button] = []

func _input(event: InputEvent) -> void:
    if not is_active():
        return

    # Handle directional navigation based on current state
    if event.is_action_pressed("move_up"):
        _navigate_up()
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("move_down"):
        _navigate_down()
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("move_left"):
        _navigate_left()
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("move_right"):
        _navigate_right()
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("menu_accept"):
        _on_accept_input()
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed("menu_back"):
        _on_back_input()
        # Only set_input_as_handled if we handle it (have history)

func _push_nav_state(new_state: NavState) -> void:
    """Push current state to history and switch to new state"""
    _nav_state_history.append(_nav_state)
    _nav_state = new_state

func _on_back_input() -> void:
    # Go back through history
    if _nav_state_history.size() > 0:
        _nav_state = _nav_state_history.pop_back()
        get_viewport().set_input_as_handled()
        # Update focus based on restored state
    else:
        # No history - let GameMenu handle (for panel transition)
        # Do NOT call set_input_as_handled()
        pass
```

**For simple panels (CalendarPanel, SystemPanel):**
- May not need NavState if they're simple display/button panels
- Still extend PanelBase for lifecycle management
- Still use ConfirmationPopup/ToastPopup if needed

### 4. Panel Lifecycle Integration

```gdscript
extends PanelBase
class_name YourPanel

func _ready() -> void:
    super()  # MUST call PanelBase._ready()

    # Panel initialization
    set_anchors_preset(Control.PRESET_FULL_RECT)
    size_flags_horizontal = Control.SIZE_EXPAND_FILL
    size_flags_vertical = Control.SIZE_EXPAND_FILL

    # Connect to data systems
    _setup_data_connections()

    # Build UI
    _rebuild()

func _on_panel_gained_focus() -> void:
    super()  # Call parent
    print("[YourPanel] Gained focus")

    # Reset navigation state
    _nav_state = NavState.INITIAL_STATE
    _nav_state_history.clear()

    # Grab initial focus
    _focus_initial_element()

func _on_panel_lost_focus() -> void:
    super()  # Call parent
    print("[YourPanel] Lost focus")

    # Cleanup if needed
    pass

func _can_panel_close() -> bool:
    # Check for pending changes
    if _has_pending_changes():
        _show_toast("Please save or discard changes before leaving.")
        return false
    return true
```

### 5. Data Access Standardization

**ALL panels should pull from these sources:**

```gdscript
# Combat Profile System - current HP/MP/level
var _cps: Node = null

# GameState - party, bench, money, metadata
var _gs: Node = null

# Stats System - stat-based calculations
var _stats: Node = null

# Calendar System - date/time
var _cal: Node = null

func _ready() -> void:
    super()

    # Get system references (safe lookups)
    _cps = get_node_or_null("/root/aCombatProfileSystem")
    _gs = get_node_or_null("/root/aGameState")
    _stats = get_node_or_null("/root/aStatsSystem")
    _cal = get_node_or_null("/root/aCalendarSystem")

    # Connect to system signals
    _connect_system_signals()

func _connect_system_signals() -> void:
    # CombatProfileSystem updates
    if _cps and _cps.has_signal("profile_changed"):
        _cps.connect("profile_changed", Callable(self, "_rebuild"))

    # GameState changes
    if _gs and _gs.has_signal("party_changed"):
        _gs.connect("party_changed", Callable(self, "_rebuild"))

    # Calendar updates
    if _cal and _cal.has_signal("day_advanced"):
        _cal.connect("day_advanced", Callable(self, "_rebuild"))
```

### 6. Accept-to-Move Flow (DormsPanel Pattern)

**Key principle:** User must press Accept to navigate between major sections.

```gdscript
func _navigate_right() -> void:
    match _nav_state:
        NavState.ROSTER:
            # Can't navigate right until user selects a roster item
            # Selection happens via Accept button
            pass

        NavState.DETAILS:
            # User selected roster item, now can navigate to actions
            _push_nav_state(NavState.ACTIONS)
            _focus_actions()

func _on_accept_input() -> void:
    match _nav_state:
        NavState.ROSTER:
            # User selected a roster item
            _selected_item = _get_current_roster_item()
            _push_nav_state(NavState.DETAILS)
            _focus_details()

        NavState.ACTIONS:
            # User pressed an action button
            _execute_current_action()
```

---

## Implementation Plan

### Phase 1: Core Infrastructure (Foundation)

**Goal:** Ensure popup classes and PanelBase are solid.

✅ Already complete:
- `ConfirmationPopup` class exists and works
- `ToastPopup` class exists and works
- `PanelBase` class exists and works

### Phase 2: Convert Simple Panels

**2.1 CalendarPanel** ⏱️ Estimated: 30 minutes
- Change `extends Control` → `extends PanelBase`
- Add `super()` call in `_ready()`
- Implement `_on_panel_gained_focus()` (optional - just set initial focus)
- Test visibility and focus management

**2.2 SystemPanel** ⏱️ Estimated: 30 minutes
- Change `extends Control` → `extends PanelBase`
- Add `super()` call in `_ready()`
- Implement `_on_panel_gained_focus()` to focus first button
- Test button navigation

**2.3 IndexPanel** ⏱️ Estimated: 45 minutes
- Change `extends Control` → `extends PanelBase`
- Add `super()` call in `_ready()`
- Optional: Add simple NavState (FILTER, LIST, DETAIL)
- Implement `_on_panel_gained_focus()` to reset state
- Test filter and list navigation

### Phase 3: Convert Complex Panels

**3.1 StatusPanel** ⭐ (ROOT PANEL) ⏱️ Estimated: 2-3 hours
- Change `extends Control` → `extends PanelBase`
- Add `super()` call in `_ready()`
- **Keep NavState (MENU, CONTENT, POPUP_ACTIVE)** - Perfect for its dual role!
  - MENU = Tab list (hub to other panels)
  - CONTENT = Party status/management section
  - POPUP_ACTIVE = Handles recovery/switch popups
- **CRITICAL:** Replace ALL manual popup creation:
  - `_show_no_bench_notice()` → use `ToastPopup.create()`
  - `_show_already_at_max_notice()` → use `ToastPopup.create()`
  - `_show_heal_confirmation()` → use `ToastPopup.create()`
  - `_show_swap_confirmation()` → use `ToastPopup.create()`
  - `_show_member_picker()` → Keep as custom ItemList popup (special case)
- Remove manual `_style_popup_panel()`, `_fade_in_popup()`, `_fade_out_popup()`
- Remove manual `aPanelManager` push/pop (handled by PanelBase)
- **Important:** StatusPanel is first panel shown, navigated right from tab list
- Test all recovery, switch, and party management flows

**3.2 SigilSkillMenu** ⏱️ Estimated: 2 hours
- Change `extends Control` → `extends PanelBase`
- Rename `NavMode` → `NavState` for consistency
- Replace any ad-hoc popup creation with ConfirmationPopup/ToastPopup
- Implement proper `_on_panel_gained_focus()` and `_on_back_input()`
- Test socket and skills navigation

### Phase 4: Update Existing PanelBase Panels

**4.1 BondsPanel** ⏱️ Estimated: 1 hour
- Replace `_show_info_popup()` CanvasLayer creation with `ToastPopup.create()`
- Replace story overlay creation (if it's a simple confirmation) with `ConfirmationPopup.create()`
- Remove manual popup management code
- Test bond list and detail navigation

**4.2 OutreachPanel** ⏱️ Estimated: 1 hour
- Replace `_show_set_current_confirmation()` Panel creation with `ConfirmationPopup.create()`
- Remove manual popup styling and positioning
- Test category, mission list, and confirmation flows

**4.3 PerksPanel, ItemsPanel, LoadoutPanel** ⏱️ Estimated: 30 min each
- Audit for any ad-hoc popup creation
- Replace with ConfirmationPopup/ToastPopup if found
- Ensure NavState is consistent and well-documented

### Phase 5: Testing & Polish

**5.1 Navigation Testing**
- Test accept-to-move flow in all panels
- Test back button navigation (history stack)
- Test controller navigation (up/down/left/right)
- Test popup blocking (directional input disabled during popups)

**5.2 Data Integration Testing**
- Verify all panels pull from CombatProfileSystem
- Verify all panels pull from GameState
- Test signal connections (profile_changed, party_changed, etc.)
- Test data reactivity (UI updates when data changes)

**5.3 Edge Cases**
- Test rapid panel switching
- Test popup spam prevention
- Test focus restoration after popup close
- Test panel close prevention (_can_panel_close)

---

## Key Patterns & Best Practices

### ✅ DO

1. **Always extend PanelBase** for menu panels
2. **Always use ConfirmationPopup/ToastPopup** for dialogs
3. **Always call super()** in `_ready()`, `_on_panel_gained_focus()`, etc.
4. **Use NavState enums** for multi-section panels
5. **Track navigation history** with `_nav_state_history`
6. **Check is_active()** before processing input
7. **Let GameMenu handle back** when no history (don't set_input_as_handled)
8. **Use safe lookups** for autoloads (`get_node_or_null()`)
9. **Connect to system signals** for reactive UI updates
10. **Implement _can_panel_close()** if panel has pending state

### ❌ DON'T

1. **Don't extend Control** for menu panels (use PanelBase)
2. **Don't create Panel/CanvasLayer popups manually** (use ConfirmationPopup/ToastPopup)
3. **Don't manually push/pop from aPanelManager** (PanelBase handles this)
4. **Don't block input without good reason** (popups auto-block)
5. **Don't forget to call super()** in lifecycle methods
6. **Don't hard-reference autoloads** (they may not exist in test environments)
7. **Don't use direct symbol access** (e.g., `aGameState.party`) - use get_node_or_null
8. **Don't forget to clear history** when resetting navigation
9. **Don't process input when inactive** (check `is_active()` first)
10. **Don't create duplicate signal connections** (check `is_connected()` first)

---

## File Reference Map

### Core Classes
- `scripts/core/PanelBase.gd` - Base class for all panels
- `scripts/main_menu/panels/ConfirmationPopup.gd` - Yes/No dialogs
- `scripts/main_menu/panels/ToastPopup.gd` - Notice/toast messages

### Data Systems
- `scripts/systems/CombatProfileSystem.gd` - HP/MP/level data
- `scripts/core/GameState.gd` - Party, bench, money, metadata
- `scripts/systems/StatsSystem.gd` - Stat calculations
- `scripts/systems/CalendarSystem.gd` - Date/time tracking

### Panels to Refactor
- `scripts/main_menu/panels/StatusPanel.gd` - MAJOR refactor needed
- `scripts/main_menu/panels/CalendarPanel.gd` - Simple conversion
- `scripts/main_menu/panels/IndexPanel.gd` - Simple conversion
- `scripts/main_menu/panels/SystemPanel.gd` - Simple conversion
- `scripts/main_menu/panels/SigilSkillMenu.gd` - Medium refactor
- `scripts/main_menu/panels/BondsPanel.gd` - Popup system update
- `scripts/main_menu/panels/OutreachPanel.gd` - Popup system update

### Reference Implementations
- `scripts/main_menu/panels/DormsPanel.gd` - ⭐ **GOLD STANDARD** - Study this!
- `scripts/main_menu/panels/PerksPanel.gd` - Good example (audit needed)
- `scripts/main_menu/panels/LoadoutPanel.gd` - Good example (audit needed)

---

## Expected Outcomes

After completing this refactor:

1. **Consistent User Experience**
   - All panels feel cohesive
   - Same popup style throughout
   - Same navigation patterns
   - Same accept-to-move flow

2. **Easier Maintenance**
   - Single source of truth for popups
   - Shared base class handles common logic
   - Consistent patterns make bugs easier to find

3. **Better Controller Support**
   - All panels handle gamepad input consistently
   - Popups auto-block input properly
   - Navigation history works everywhere

4. **Cleaner Code**
   - Less duplicate popup creation code
   - Less manual aPanelManager management
   - Clearer separation of concerns

5. **More Robust**
   - Panels can prevent closing when needed
   - Proper focus management
   - Safe autoload lookups

---

## Next Steps

1. **Review this document** - Make sure the plan makes sense
2. **Start with Phase 2** - Convert simple panels first
3. **Test each panel** thoroughly after conversion
4. **Move to Phase 3** - Tackle complex panels
5. **Update remaining panels** in Phase 4
6. **Comprehensive testing** in Phase 5
7. **Commit and push** when stable

---

## Questions for Review

Before starting implementation, please confirm:

1. ✅ Does this architecture align with your vision?
2. ✅ Is the DormsPanel pattern the right reference?
3. ✅ Should ALL popups use ConfirmationPopup/ToastPopup (no exceptions)?
4. ✅ Should we add NavState to simple panels like CalendarPanel, or is that overkill?
5. ✅ Any special cases or panels that need different treatment?

---

**Ready to proceed?** Let's start with Phase 2 and convert the simple panels first! 🚀
