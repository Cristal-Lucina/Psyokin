extends Node
class_name PanelManager

## ═══════════════════════════════════════════════════════════════════════════
## PanelManager - Central Panel Navigation & Focus System
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Manages a stack of active panels, tracks focus, and handles navigation
##   between panels. Solves focus management and controller input routing issues.
##
## RESPONSIBILITIES:
##   • Maintains stack of active panels (bottom to top)
##   • Tracks currently active (focused) panel
##   • Emits signals when panels change
##   • Handles back navigation through panel history
##   • Manages panel lifecycle (opened/closed/focused/unfocused)
##
## HOW IT WORKS:
##   1. When a panel opens, call push_panel(panel_node)
##   2. PanelManager adds it to stack and makes it active
##   3. Previous panel receives panel_lost_focus() callback
##   4. New panel receives panel_gained_focus() callback
##   5. When panel closes, call pop_panel() or pop_to_panel(target)
##   6. Focus automatically returns to previous panel in stack
##
## SIGNALS:
##   • panel_pushed(panel) - Panel added to stack
##   • panel_popped(panel) - Panel removed from stack
##   • active_panel_changed(old_panel, new_panel) - Focus changed
##   • panel_stack_empty() - All panels closed
##
## PANEL REQUIREMENTS:
##   Panels should implement these methods (optional but recommended):
##   • panel_gained_focus() -> void - Called when panel becomes active
##   • panel_lost_focus() -> void - Called when panel loses focus
##   • panel_can_close() -> bool - Return false to prevent closing
##
## USAGE EXAMPLE:
##   # Open a panel
##   PanelManager.push_panel(items_panel)
##
##   # Close current panel and return to previous
##   PanelManager.pop_panel()
##
##   # Close all panels up to a specific one
##   PanelManager.pop_to_panel(main_menu_panel)
##
##   # Get currently active panel
##   var active = PanelManager.get_active_panel()
##
## ═══════════════════════════════════════════════════════════════════════════

# ────────────────────────── Signals ──────────────────────────────

## Emitted when a panel is pushed onto the stack
signal panel_pushed(panel: Node)

## Emitted when a panel is popped from the stack
signal panel_popped(panel: Node)

## Emitted when the active (focused) panel changes
signal active_panel_changed(old_panel: Node, new_panel: Node)

## Emitted when the panel stack becomes empty
signal panel_stack_empty()

# ────────────────────────── State ──────────────────────────────

## Stack of active panels (bottom to top)
var _panel_stack: Array[Node] = []

## Enable debug logging
var debug_logging: bool = false

# ────────────────────────── Public API ──────────────────────────────

## Push a panel onto the stack and make it active
func push_panel(panel: Node) -> void:
	if panel == null:
		push_error("[PanelManager] Cannot push null panel")
		return

	# Check if panel is already in stack
	if _panel_stack.has(panel):
		_log("Panel %s already in stack, moving to top" % panel.name)
		_panel_stack.erase(panel)

	# Get previous active panel
	var old_active: Node = get_active_panel()

	# Add to stack
	_panel_stack.append(panel)
	_log("Pushed panel: %s (stack depth: %d)" % [panel.name, _panel_stack.size()])

	# Notify old panel it's losing focus
	if old_active != null and old_active != panel:
		_call_panel_method(old_active, "panel_lost_focus")

	# Notify new panel it's gaining focus
	_call_panel_method(panel, "panel_gained_focus")

	# Emit signals
	emit_signal("panel_pushed", panel)
	emit_signal("active_panel_changed", old_active, panel)

## Pop the current panel from the stack
func pop_panel() -> void:
	if _panel_stack.is_empty():
		_log("Cannot pop - stack is empty")
		return

	# Get current active panel
	var old_active: Node = _panel_stack.pop_back()

	# Check if panel allows closing
	if _call_panel_method(old_active, "panel_can_close") == false:
		_log("Panel %s prevented closing" % old_active.name)
		_panel_stack.append(old_active)  # Put it back
		return

	_log("Popped panel: %s (stack depth: %d)" % [old_active.name, _panel_stack.size()])

	# Notify old panel it's losing focus
	_call_panel_method(old_active, "panel_lost_focus")

	# Get new active panel
	var new_active: Node = get_active_panel()

	# Notify new panel it's gaining focus (if any)
	if new_active != null:
		_call_panel_method(new_active, "panel_gained_focus")

	# Emit signals
	emit_signal("panel_popped", old_active)
	emit_signal("active_panel_changed", old_active, new_active)

	if _panel_stack.is_empty():
		emit_signal("panel_stack_empty")

## Pop all panels up to (but not including) the target panel
## If target is null, pops all panels
func pop_to_panel(target_panel: Node) -> void:
	if target_panel == null:
		# Pop all panels
		while not _panel_stack.is_empty():
			pop_panel()
		return

	# Find target panel in stack
	var target_index: int = _panel_stack.find(target_panel)
	if target_index == -1:
		push_error("[PanelManager] Target panel %s not found in stack" % target_panel.name)
		return

	# Pop panels until we reach the target
	while _panel_stack.size() > target_index + 1:
		pop_panel()

## Get the currently active (top) panel
func get_active_panel() -> Node:
	if _panel_stack.is_empty():
		return null
	return _panel_stack.back()

## Get the previous panel (second from top)
func get_previous_panel() -> Node:
	if _panel_stack.size() < 2:
		return null
	return _panel_stack[_panel_stack.size() - 2]

## Check if a specific panel is in the stack
func has_panel(panel: Node) -> bool:
	return _panel_stack.has(panel)

## Check if a specific panel is currently active
func is_panel_active(panel: Node) -> bool:
	return get_active_panel() == panel

## Get the current stack depth
func get_stack_depth() -> int:
	return _panel_stack.size()

## Get a copy of the entire panel stack
func get_panel_stack() -> Array[Node]:
	return _panel_stack.duplicate()

## Clear the entire panel stack
func clear_stack() -> void:
	_log("Clearing entire panel stack")
	while not _panel_stack.is_empty():
		pop_panel()

## Force reset - clear stack without any lifecycle callbacks
## Use this when changing scenes to avoid calling methods on freed nodes
func force_reset() -> void:
	_log("FORCE RESET - clearing stack without callbacks")
	_panel_stack.clear()
	emit_signal("panel_stack_empty")

## Print the current panel stack (for debugging)
func print_stack() -> void:
	print("[PanelManager] === Panel Stack (depth: %d) ===" % _panel_stack.size())
	for i in range(_panel_stack.size()):
		var panel: Node = _panel_stack[i]
		var marker: String = " (ACTIVE)" if i == _panel_stack.size() - 1 else ""
		print("  [%d] %s%s" % [i, panel.name, marker])

# ────────────────────────── Internal Helpers ──────────────────────────────

## Call a method on a panel if it exists
func _call_panel_method(panel: Node, method: String) -> Variant:
	if panel == null:
		return null

	if panel.has_method(method):
		_log("Calling %s.%s()" % [panel.name, method])
		return panel.call(method)

	return null

## Debug logging helper
func _log(message: String) -> void:
	if debug_logging:
		print("[PanelManager] %s" % message)
