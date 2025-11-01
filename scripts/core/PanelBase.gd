extends Control
class_name PanelBase

## ═══════════════════════════════════════════════════════════════════════════
## PanelBase - Base Class for All Menu Panels
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Provides standard interface for panels to work with PanelManager.
##   All menu panels should extend this class or implement its interface.
##
## FEATURES:
##   • Automatic registration with PanelManager when visible
##   • Standard lifecycle callbacks (gained/lost focus)
##   • Optional close prevention logic
##   • Automatic focus management
##
## LIFECYCLE:
##   1. Panel becomes visible → auto-registers with PanelManager
##   2. Panel receives panel_gained_focus() callback
##   3. Panel loses focus → panel_lost_focus() callback
##   4. Panel closes → auto-unregisters from PanelManager
##
## SUBCLASS USAGE:
##   Override these methods in your panel:
##   • _on_panel_gained_focus() - Focus logic
##   • _on_panel_lost_focus() - Cleanup logic
##   • _can_panel_close() - Return false to prevent closing
##
## EXAMPLE:
##   extends PanelBase
##
##   func _on_panel_gained_focus() -> void:
##       super()  # Call parent
##       _item_list.grab_focus()
##
##   func _on_panel_lost_focus() -> void:
##       super()  # Call parent
##       _close_popup()
##
## ═══════════════════════════════════════════════════════════════════════════

# ────────────────────────── Configuration ──────────────────────────────

## Enable debug logging for this panel
@export var debug_logging: bool = false

## Automatically push to PanelManager when visible
@export var auto_register: bool = true

## Automatically pop from PanelManager when hidden
@export var auto_unregister: bool = true

# ────────────────────────── State ──────────────────────────────

## Reference to PanelManager autoload
var _panel_manager: Node = null

## Whether this panel is currently registered
var _is_registered: bool = false

# ────────────────────────── Lifecycle ──────────────────────────────

func _ready() -> void:
	# Get PanelManager reference
	_panel_manager = get_node_or_null("/root/PanelManager")
	if _panel_manager == null:
		push_warning("[%s] PanelManager not found - panel management disabled" % name)

	# Connect visibility signal
	visibility_changed.connect(_on_visibility_changed)

	# Register if already visible
	if visible and auto_register:
		_register_panel()

## Called when panel becomes visible/invisible
func _on_visibility_changed() -> void:
	if visible:
		if auto_register:
			_register_panel()
	else:
		if auto_unregister:
			_unregister_panel()

# ────────────────────────── Panel Manager Interface ──────────────────────────────

## Called by PanelManager when this panel gains focus (becomes active)
func panel_gained_focus() -> void:
	_log("Gained focus")
	_on_panel_gained_focus()

## Called by PanelManager when this panel loses focus
func panel_lost_focus() -> void:
	_log("Lost focus")
	_on_panel_lost_focus()

## Called by PanelManager to check if panel can close
## Return false to prevent closing
func panel_can_close() -> bool:
	var can_close: bool = _can_panel_close()
	if not can_close:
		_log("Close prevented")
	return can_close

# ────────────────────────── Override These ──────────────────────────────

## Override in subclass: Called when panel gains focus
func _on_panel_gained_focus() -> void:
	pass

## Override in subclass: Called when panel loses focus
func _on_panel_lost_focus() -> void:
	pass

## Override in subclass: Return false to prevent panel from closing
func _can_panel_close() -> bool:
	return true

# ────────────────────────── Public API ──────────────────────────────

## Manually push this panel to PanelManager
func push_to_manager() -> void:
	_register_panel()

## Manually pop this panel from PanelManager
func pop_from_manager() -> void:
	_unregister_panel()

## Check if this panel is currently active (has focus)
func is_active() -> bool:
	if _panel_manager == null:
		return false
	return _panel_manager.is_panel_active(self)

## Check if this panel is in the PanelManager stack
func is_registered() -> bool:
	return _is_registered

# ────────────────────────── Internal Helpers ──────────────────────────────

## Register panel with PanelManager
func _register_panel() -> void:
	if _panel_manager == null:
		return

	if _is_registered:
		_log("Already registered")
		return

	_log("Registering with PanelManager")
	_panel_manager.push_panel(self)
	_is_registered = true

## Unregister panel from PanelManager
func _unregister_panel() -> void:
	if _panel_manager == null:
		return

	if not _is_registered:
		_log("Not registered")
		return

	# Only pop if we're the active panel
	if _panel_manager.is_panel_active(self):
		_log("Unregistering from PanelManager")
		_panel_manager.pop_panel()
		_is_registered = false

## Debug logging helper
func _log(message: String) -> void:
	if debug_logging:
		print("[%s] %s" % [name, message])
