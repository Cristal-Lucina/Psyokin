# UI Popup Patterns - Critical Reference

**Last Updated:** 2025-01-05
**Context:** Godot 4.5.1, Psyokin JRPG

---

## ⚠️ CRITICAL: Popups in Paused Contexts

### The Problem

**GameMenu pauses the game when visible:**
```gdscript
func _on_visibility_changed() -> void:
    if visible:
        get_tree().paused = true  # ← Game is PAUSED!
```

When `get_tree().paused = true`, nodes with default `PROCESS_MODE_INHERIT` **do not process ANY input events**. This means:
- Popups won't receive button presses
- Animations won't update
- `_input()` and `_unhandled_input()` won't be called
- The popup appears frozen and unresponsive

### The Solution

**ALWAYS use CanvasLayer overlay with `PROCESS_MODE_ALWAYS`:**

```gdscript
func _show_confirmation(message: String) -> void:
    # Create CanvasLayer overlay for popup
    var overlay := CanvasLayer.new()
    overlay.layer = 100  # High layer to render on top
    overlay.process_mode = Node.PROCESS_MODE_ALWAYS  # ← CRITICAL!
    get_tree().root.add_child(overlay)
    get_tree().root.move_child(overlay, 0)  # Process input first

    # Create popup
    var popup := ToastPopup.create(message, "Confirm")
    popup.process_mode = Node.PROCESS_MODE_ALWAYS  # ← CRITICAL!
    overlay.add_child(popup)

    # Wait for response
    var result: bool = await popup.confirmed

    # Cleanup
    popup.queue_free()
    overlay.queue_free()

    # Handle result
    if result:
        print("User confirmed")
```

### Why Each Step Matters

1. **CanvasLayer with high layer (100)**: Ensures popup renders above all other UI
2. **`overlay.process_mode = PROCESS_MODE_ALWAYS`**: Allows overlay to process while paused
3. **`get_tree().root.add_child(overlay)`**: Adds to viewport root for proper centering
4. **`move_child(overlay, 0)`**: Processes input **before** other nodes (input priority)
5. **`popup.process_mode = PROCESS_MODE_ALWAYS`**: Allows popup to receive input while paused
6. **Cleanup both popup and overlay**: Prevents memory leaks

### Common Mistakes

❌ **Forgetting PROCESS_MODE_ALWAYS on overlay:**
```gdscript
var overlay := CanvasLayer.new()
overlay.layer = 100
// Missing: overlay.process_mode = Node.PROCESS_MODE_ALWAYS
```
Result: Popup visible but frozen, no input processing

❌ **Forgetting PROCESS_MODE_ALWAYS on popup:**
```gdscript
var popup := ToastPopup.create(message, "Confirm")
// Missing: popup.process_mode = Node.PROCESS_MODE_ALWAYS
```
Result: Popup visible but doesn't respond to buttons

❌ **Adding popup directly to panel instead of overlay:**
```gdscript
var popup := ToastPopup.create(message, "Confirm")
add_child(popup)  // Wrong! Not centered, wrong z-order
```
Result: Popup positioned wrong, may be behind other UI

❌ **Not cleaning up overlay:**
```gdscript
popup.queue_free()
// Missing: overlay.queue_free()
```
Result: Memory leak, overlay stays in scene tree

### Testing Checklist

When implementing a popup in a paused context:

- [ ] Create CanvasLayer overlay
- [ ] Set `overlay.process_mode = PROCESS_MODE_ALWAYS`
- [ ] Set `overlay.layer = 100` (or higher)
- [ ] Add overlay to `get_tree().root`
- [ ] Move overlay to position 0 with `move_child(overlay, 0)`
- [ ] Create popup with `ToastPopup.create()`
- [ ] Set `popup.process_mode = PROCESS_MODE_ALWAYS`
- [ ] Add popup to overlay, not to panel
- [ ] Clean up both popup and overlay after use
- [ ] Test that popup responds to controller input
- [ ] Test that popup responds to keyboard input
- [ ] Verify popup is centered on screen
- [ ] Verify popup is on top of all other UI

---

## Examples from Codebase

### ✅ Correct: GameMenu Friday Reveals Popup

```gdscript
func _on_friday_reveals(pairs: Array) -> void:
    # Pause the game
    get_tree().paused = true

    # Show popup using ToastPopup as overlay (controller-friendly)
    var overlay := CanvasLayer.new()
    overlay.layer = 100  # High layer to ensure it's on top
    overlay.process_mode = Node.PROCESS_MODE_ALWAYS  # Process even when paused
    get_tree().root.add_child(overlay)  # Add to root
    get_tree().root.move_child(overlay, 0)  # Move to first position so it processes input first

    var popup := ToastPopup.create(message, "RA MAIL - FRIDAY NEIGHBOR REPORT")
    popup.process_mode = Node.PROCESS_MODE_ALWAYS  # Process even when paused
    overlay.add_child(popup)
    await popup.confirmed  # User can accept or cancel
    popup.queue_free()
    overlay.queue_free()

    # Unpause the game
    get_tree().paused = false
```

### ✅ Correct: PerksPanel Perk Confirmation

```gdscript
func _show_perk_confirmation(perk: Dictionary) -> void:
    var message := "%s\n\n%s\n\nCost: 1 Perk Point\n\nUnlock this perk?" % [perk_name, desc]

    # Create CanvasLayer overlay for popup
    var overlay := CanvasLayer.new()
    overlay.layer = 100
    overlay.process_mode = Node.PROCESS_MODE_ALWAYS
    get_tree().root.add_child(overlay)
    get_tree().root.move_child(overlay, 0)

    # Create and show popup
    var popup := ToastPopup.create(message, "Confirm")
    popup.process_mode = Node.PROCESS_MODE_ALWAYS
    overlay.add_child(popup)

    # Wait for user response
    var result: bool = await popup.confirmed

    # Clean up
    popup.queue_free()
    overlay.queue_free()

    # Handle response
    if result:
        _unlock_perk(perk)
```

---

## Related Documentation

- `docs/UNIFIED_PANEL_ARCHITECTURE.md` - Full panel architecture guide
- `scripts/main_menu/panels/ToastPopup.gd` - Unified popup implementation
- `scripts/main_menu/GameMenu.gd` - Example usage in GameMenu

---

## Key Takeaway

**When the game is paused, ALWAYS set `process_mode = Node.PROCESS_MODE_ALWAYS` on BOTH the overlay AND the popup, or the popup will be visible but completely unresponsive to input.**
