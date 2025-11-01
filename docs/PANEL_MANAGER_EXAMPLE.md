# PanelManager Integration Example: ItemsPanel

## Before & After Comparison

### BEFORE (Current ItemsPanel)

```gdscript
extends Control
class_name ItemsPanel

var _focus_mode: String = "category"  # Manual focus tracking

func _on_visibility_changed() -> void:
    if visible:
        call_deferred("_grab_category_focus")  # Manual focus management

func _grab_category_focus() -> void:
    if _category_list and _category_list.item_count > 0:
        _focus_mode = "category"
        _category_list.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
    if not visible:
        return  # Manual visibility check

    # Manual focus mode checking...
    if _focus_mode == "party_picker":
        # Handle input...
```

**Problems:**
- Manual focus state management (`_focus_mode`)
- No integration with other panels
- Back navigation not tracked
- Input handling requires visibility checks

### AFTER (With PanelManager)

```gdscript
extends PanelBase  # ← Extend PanelBase instead of Control
class_name ItemsPanel

# Remove manual focus tracking
# var _focus_mode: String = "category"  # ← Delete this

@export var debug_logging: bool = true  # Enable logging

# PanelBase handles visibility automatically!
# func _on_visibility_changed() -> void:  # ← Delete this
#     ...

## Called automatically when panel gains focus
func _on_panel_gained_focus() -> void:
    super()  # Call parent
    _grab_category_focus()  # Just grab focus, that's it!

## Called automatically when panel loses focus
func _on_panel_lost_focus() -> void:
    super()  # Call parent
    _cleanup_popups()  # Clean up any active popups

func _unhandled_input(event: InputEvent) -> void:
    # PanelManager ensures only active panel receives input
    if not is_active():
        return  # Not active, ignore input

    # Handle input normally...
```

**Benefits:**
- Automatic focus management
- Clean lifecycle callbacks
- Integrated with navigation stack
- Input routing handled automatically

## Step-by-Step Migration

### Step 1: Change Base Class

```gdscript
# OLD:
extends Control

# NEW:
extends PanelBase
```

### Step 2: Remove Manual Visibility Handling

```gdscript
# DELETE THIS:
func _on_visibility_changed() -> void:
    if visible:
        call_deferred("_grab_category_focus")

# DELETE THIS:
func _ready() -> void:
    visibility_changed.connect(_on_visibility_changed)
```

### Step 3: Implement Focus Callbacks

```gdscript
# ADD THIS:
func _on_panel_gained_focus() -> void:
    super()  # Always call super
    print("[ItemsPanel] Gained focus - setting up...")

    # Grab focus on appropriate control
    call_deferred("_grab_category_focus")

    # Refresh data if needed
    _rebuild()

func _on_panel_lost_focus() -> void:
    super()  # Always call super
    print("[ItemsPanel] Lost focus - cleaning up...")

    # Close any popups
    if _party_picker_list and is_instance_valid(_party_picker_list):
        _party_picker_list.queue_free()
        _party_picker_list = null
```

### Step 4: Update Input Handling

```gdscript
func _unhandled_input(event: InputEvent) -> void:
    # OLD:
    # if not visible:
    #     return

    # NEW:
    if not is_active():
        return  # Only handle input if we're the active panel

    # Rest of input handling...
```

### Step 5: Update Party Picker to Use PanelManager

```gdscript
func _show_party_picker() -> void:
    # Create party picker panel
    _party_picker_list = ItemList.new()
    _party_picker_list.custom_minimum_size = Vector2(0, 300)
    # ... setup party picker ...

    # Add to scene
    if _scroll_container:
        _scroll_container.add_child(_party_picker_list)

    # Push to PanelManager!
    PanelManager.push_panel(_party_picker_list)  # ← NEW!

    # Focus will be handled by PanelManager
    call_deferred("_grab_party_picker_focus")

func _close_party_picker() -> void:
    # Pop from PanelManager
    if _party_picker_list and is_instance_valid(_party_picker_list):
        PanelManager.pop_panel()  # ← NEW!
        _party_picker_list.queue_free()
        _party_picker_list = null

    # ItemsPanel will automatically regain focus
```

## Complete ItemsPanel Integration Example

```gdscript
extends PanelBase
class_name ItemsPanel

# Enable debug logging
@export var debug_logging: bool = true

# Auto-register when visible
@export var auto_register: bool = true

# ... rest of your variables ...

func _ready() -> void:
    # Get system references
    _inv = get_node_or_null(INV_PATH)
    _csv = get_node_or_null(CSV_PATH)
    # ... rest of setup ...

    # Connect signals (but NOT visibility_changed - PanelBase handles it)
    if _category_list:
        _category_list.item_selected.connect(_on_category_selected)
    if _item_list:
        _item_list.item_selected.connect(_on_item_selected)

    # Initial build (only if visible at start)
    if visible:
        call_deferred("_first_fill")

## PanelBase callback - Called when panel gains focus
func _on_panel_gained_focus() -> void:
    super()  # Always call super!

    print("[ItemsPanel] Gained focus")

    # Refresh data
    _rebuild()

    # Grab initial focus
    call_deferred("_grab_category_focus")

## PanelBase callback - Called when panel loses focus
func _on_panel_lost_focus() -> void:
    super()  # Always call super!

    print("[ItemsPanel] Lost focus")

    # Clean up active popups
    _close_party_picker()

## PanelBase callback - Check if panel can close
func _can_panel_close() -> bool:
    # Prevent closing if party picker is active
    if _party_picker_list and is_instance_valid(_party_picker_list):
        print("[ItemsPanel] Cannot close - party picker is active")
        return false

    return true

func _unhandled_input(event: InputEvent) -> void:
    """Handle controller input"""

    # Only handle input if we're the active panel
    if not is_active():
        return

    # Handle party picker input
    if _party_picker_list and is_instance_valid(_party_picker_list):
        if event.is_action_pressed("menu_accept"):
            _on_party_picker_accept()
            get_viewport().set_input_as_handled()
            return
        elif event.is_action_pressed("menu_back"):
            _close_party_picker()  # This will pop from PanelManager
            get_viewport().set_input_as_handled()
            return
        return

    # Handle normal input
    if event.is_action_pressed("menu_back"):
        # Let PanelManager handle back navigation
        PanelManager.pop_panel()
        get_viewport().set_input_as_handled()
        return

    # ... rest of input handling ...
```

## GameMenu Integration

Update GameMenu to use PanelManager:

```gdscript
# In GameMenu.gd

func _on_status_panel_tab_selected(tab_name: String) -> void:
    var panel: Control = _panels.get(tab_name)
    if panel:
        # Hide other panels
        for p in _panels.values():
            if p != panel:
                p.visible = false

        # Show selected panel (will auto-push to PanelManager)
        panel.visible = true

func _unhandled_input(event: InputEvent) -> void:
    if not visible:
        return

    if event.is_action_pressed("menu_back"):
        # Let PanelManager handle back navigation
        if PanelManager.get_stack_depth() > 1:
            PanelManager.pop_panel()
        else:
            _close_menu()  # Close entire menu
        get_viewport().set_input_as_handled()
```

## Testing Checklist

After integration, test:

- [ ] Opening ItemsPanel sets focus correctly
- [ ] Navigating to Recovery category works
- [ ] Using recovery item opens party picker
- [ ] Party picker has focus
- [ ] Pressing B closes party picker and returns to ItemsPanel
- [ ] ItemsPanel regains focus automatically
- [ ] Items don't disappear after use
- [ ] Back button works correctly
- [ ] Opening another panel (e.g., StatsPanel) works
- [ ] Returning to ItemsPanel restores state
- [ ] Calling `PanelManager.print_stack()` shows correct stack

## Debug Commands

Add these to your game for testing:

```gdscript
# In Main.gd or debug console

## Print current panel stack
func debug_print_panels() -> void:
    PanelManager.print_stack()

## Get active panel info
func debug_active_panel() -> void:
    var active = PanelManager.get_active_panel()
    if active:
        print("Active panel: ", active.name)
    else:
        print("No active panel")

## Clear all panels
func debug_clear_panels() -> void:
    PanelManager.clear_stack()
```

## Expected Console Output

With debug logging enabled, you should see:

```
[PanelManager] Pushed panel: ItemsPanel (stack depth: 1)
[ItemsPanel] Gained focus
[ItemsPanel] Calling _grab_category_focus()
[PanelManager] === Panel Stack (depth: 1) ===
  [0] ItemsPanel (ACTIVE)

# After using recovery item:
[PanelManager] Pushed panel: PartyPicker (stack depth: 2)
[ItemsPanel] Lost focus
[PartyPicker] Gained focus

# After selecting party member:
[PanelManager] Popped panel: PartyPicker (stack depth: 1)
[PartyPicker] Lost focus
[ItemsPanel] Gained focus
[ItemsPanel] Calling _grab_item_focus()
```

## Next Steps

1. **Test ItemsPanel integration** thoroughly
2. **Migrate StatusPanel** (simpler panel, good second test)
3. **Migrate StatsPanel**
4. **Migrate remaining panels** one by one
5. **Add panel transitions** (fade/slide animations)
6. **Add breadcrumb UI** showing panel history
