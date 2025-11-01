# aPanelManager System Setup Guide

## Overview

The **aPanelManager** system provides centralized panel navigation and focus management. It solves focus issues, controller input routing problems, and provides a clean navigation stack.

## Architecture

```
aPanelManager (Autoload/Singleton)
├── Maintains stack of active panels
├── Tracks currently focused panel
├── Emits signals on panel changes
└── Handles back navigation

PanelBase (Base Class)
├── Standard interface for all panels
├── Auto-registration with aPanelManager
├── Lifecycle callbacks (gained/lost focus)
└── Optional close prevention
```

## Setup Steps

### 1. Add aPanelManager as Autoload

In **Project Settings → Autoload**, add:

```
Name: aPanelManager
Path: res://scripts/core/PanelManager.gd
Enabled: ✓
```

### 2. Update Existing Panels

**Option A: Extend PanelBase** (Recommended for new panels)

```gdscript
extends PanelBase

@export var debug_logging: bool = true

func _on_panel_gained_focus() -> void:
    super()  # Call parent
    print("[MyPanel] Got focus!")
    _my_list.grab_focus()

func _on_panel_lost_focus() -> void:
    super()  # Call parent
    print("[MyPanel] Lost focus!")
    _cleanup_popups()
```

**Option B: Implement Interface** (For existing panels)

```gdscript
extends Control

func _ready() -> void:
    visibility_changed.connect(_on_visibility_changed)

func _on_visibility_changed() -> void:
    if visible:
        aPanelManager.push_panel(self)
    else:
        if aPanelManager.is_panel_active(self):
            aPanelManager.pop_panel()

## Called by aPanelManager
func panel_gained_focus() -> void:
    print("[MyPanel] Gained focus")
    _my_list.grab_focus()

## Called by aPanelManager
func panel_lost_focus() -> void:
    print("[MyPanel] Lost focus")
    _cleanup_popups()

## Optional: Prevent closing
func panel_can_close() -> bool:
    return not _has_unsaved_changes()
```

### 3. Update GameMenu Integration

```gdscript
# In GameMenu.gd

func _on_tab_activated(tab_name: String) -> void:
    var panel: Control = _panels.get(tab_name)
    if panel:
        # Panel will auto-register with aPanelManager when made visible
        panel.visible = true

func _on_back_pressed() -> void:
    # Let aPanelManager handle navigation
    aPanelManager.pop_panel()
```

## Usage Examples

### Opening a Panel

```gdscript
# Automatic (if using PanelBase with auto_register=true)
items_panel.visible = true  # Automatically pushes to aPanelManager

# Manual
aPanelManager.push_panel(items_panel)
```

### Closing a Panel

```gdscript
# Automatic (if using PanelBase with auto_unregister=true)
items_panel.visible = false  # Automatically pops from aPanelManager

# Manual
aPanelManager.pop_panel()  # Closes current panel
```

### Navigation

```gdscript
# Go back to previous panel
aPanelManager.pop_panel()

# Go back to specific panel (close all above it)
aPanelManager.pop_to_panel(main_menu_panel)

# Close all panels
aPanelManager.clear_stack()
```

### Checking Panel State

```gdscript
# Get current active panel
var active = aPanelManager.get_active_panel()

# Check if specific panel is active
if aPanelManager.is_panel_active(my_panel):
    print("My panel has focus!")

# Get stack depth
var depth = aPanelManager.get_stack_depth()

# Debug print stack
aPanelManager.print_stack()
```

## Signals

Connect to aPanelManager signals for global panel tracking:

```gdscript
func _ready() -> void:
    aPanelManager.panel_pushed.connect(_on_panel_pushed)
    aPanelManager.panel_popped.connect(_on_panel_popped)
    aPanelManager.active_panel_changed.connect(_on_active_panel_changed)
    aPanelManager.panel_stack_empty.connect(_on_all_panels_closed)

func _on_panel_pushed(panel: Node) -> void:
    print("Panel opened: ", panel.name)

func _on_panel_popped(panel: Node) -> void:
    print("Panel closed: ", panel.name)

func _on_active_panel_changed(old_panel: Node, new_panel: Node) -> void:
    print("Focus changed: %s → %s" % [
        old_panel.name if old_panel else "none",
        new_panel.name if new_panel else "none"
    ])

func _on_all_panels_closed() -> void:
    print("All panels closed - return to game")
```

## Benefits

✅ **Centralized Focus Management** - One source of truth for which panel is active
✅ **Automatic Back Navigation** - Panel history tracked automatically
✅ **Clean Lifecycle** - Predictable gained/lost focus callbacks
✅ **Controller Input Routing** - Active panel always gets priority
✅ **Popup Management** - Popups can be panels too!
✅ **Debug Visibility** - Print panel stack anytime
✅ **Transition Ready** - Foundation for panel transitions

## Migration Path

1. **Phase 1:** Add aPanelManager autoload
2. **Phase 2:** Convert one panel (e.g., ItemsPanel) to use PanelBase
3. **Phase 3:** Test thoroughly with controller
4. **Phase 4:** Migrate remaining panels one by one
5. **Phase 5:** Update GameMenu to use aPanelManager signals

## Common Patterns

### Popup as Panel

```gdscript
# Popups can be panels too!
var popup = Panel.new()
popup.set_script(preload("res://scripts/core/PanelBase.gd"))
add_child(popup)
popup.visible = true  # Automatically pushes to stack

# Close popup
popup.visible = false  # Automatically pops from stack
```

### Preventing Accidental Close

```gdscript
func _can_panel_close() -> bool:
    if _has_unsaved_changes:
        _show_confirm_dialog()
        return false  # Prevent close
    return true  # Allow close
```

### Focus Chain

```gdscript
func _on_panel_gained_focus() -> void:
    super()
    # Restore last focused element
    if _last_focused_element:
        _last_focused_element.grab_focus()
    else:
        _default_element.grab_focus()

func _on_panel_lost_focus() -> void:
    super()
    # Remember what was focused
    _last_focused_element = get_viewport().gui_get_focus_owner()
```

## Troubleshooting

**Q: Panel focus not working?**
A: Make sure panel implements `panel_gained_focus()` and calls `grab_focus()` on appropriate control.

**Q: Back button doesn't work?**
A: Check that `aPanelManager.pop_panel()` is called on back button press.

**Q: Multiple panels have focus?**
A: Only one panel should be active at a time. Check for manual focus grabbing outside aPanelManager.

**Q: Stack gets corrupted?**
A: Call `aPanelManager.print_stack()` to debug. Ensure panels don't manually modify visibility without aPanelManager.

## Next Steps

After implementing aPanelManager:
- Add panel transition animations (fade, slide, etc.)
- Implement panel sound effects
- Add breadcrumb navigation UI
- Enhance with panel analytics/metrics
