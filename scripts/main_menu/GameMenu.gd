extends Control

# ------------------------------------------------------------------------------
# GameMenu — centered menu shell (tabs left, content right).
# ------------------------------------------------------------------------------

const TAB_DEFS: Dictionary = {
	"status":  {"title": "Status",  "scene": "res://scenes/main_menu/panels/StatusPanel.tscn"},
	"stats":   {"title": "Stats",   "scene": "res://scenes/main_menu/panels/StatsPanel.tscn"},
	"perks":   {"title": "Perks",   "scene": "res://scenes/main_menu/panels/PerksPanel.tscn"},
	"items":   {"title": "Items",   "scene": "res://scenes/main_menu/panels/ItemsPanel.tscn"},
	"loadout": {"title": "Loadout", "scene": "res://scenes/main_menu/panels/LoadoutPanel.tscn"},
	"bonds":   {"title": "Bonds",   "scene": "res://scenes/main_menu/panels/BondsPanel.tscn"},
	"outreach":{"title": "Outreach","scene": "res://scenes/main_menu/panels/OutreachPanel.tscn"},
	"dorms":   {"title": "Dorms",   "scene": "res://scenes/main_menu/panels/DormsPanel.tscn"},
	"calendar":{"title": "Calendar","scene": "res://scenes/main_menu/panels/CalendarPanel.tscn"},
	"index":   {"title": "Index",   "scene": "res://scenes/main_menu/panels/IndexPanel.tscn"},
	"system":  {"title": "System",  "scene": "res://scenes/main_menu/panels/SystemPanel.tscn"},
}

const TAB_ORDER: PackedStringArray = [
	"status","stats","perks","items","loadout","bonds","outreach","dorms","calendar","index","system"
]

@onready var _left_tabs: VBoxContainer = %LeftTabs
@onready var _panel_holder: Control    = %PanelHolder

var _btn_group: ButtonGroup
var _panels: Dictionary = {}  # tab_id -> Control
var _current_tab: String = ""

# --- Panel state ---
var _is_fullscreen: bool = false  # true when a non-Status panel is open full screen

# --- Dorm hooks ---
var _ds: Node = null
var _pending_saturday_moves: Array = []  # Stores moves for Saturday popup

# --- Controller Manager ---
var _ctrl_mgr: Node = null

func _ready() -> void:
	_btn_group = ButtonGroup.new()

	# Get ControllerManager reference
	_ctrl_mgr = get_node_or_null("/root/aControllerManager")

	# Hide the LeftTabs since tab buttons are now in StatusPanel
	if _left_tabs:
		_left_tabs.visible = false

	# Always start with Status panel
	_select_tab("status")

	# Connect to StatusPanel's tab_selected signal
	call_deferred("_connect_status_panel_signal")

	# Hook: auto-open Dorms tab when someone is added to Common (menu already open)
	_ds = get_node_or_null("/root/aDormSystem")
	if _ds:
		if _ds.has_signal("common_added") and not _ds.is_connected("common_added", Callable(self, "_on_common_added")):
			_ds.connect("common_added", Callable(self, "_on_common_added"))
		# Hook Friday RA Mail popup
		if _ds.has_signal("friday_reveals_ready") and not _ds.is_connected("friday_reveals_ready", Callable(self, "_on_friday_reveals")):
			_ds.connect("friday_reveals_ready", Callable(self, "_on_friday_reveals"))
		# Hook Saturday moves popup
		if _ds.has_signal("saturday_reveals_ready") and not _ds.is_connected("saturday_reveals_ready", Callable(self, "_on_saturday_reveals")):
			_ds.connect("saturday_reveals_ready", Callable(self, "_on_saturday_reveals"))
		if _ds.has_signal("saturday_applied_v2") and not _ds.is_connected("saturday_applied_v2", Callable(self, "_on_saturday_applied")):
			_ds.connect("saturday_applied_v2", Callable(self, "_on_saturday_applied"))

	# Connect to visibility changes to manage MENU_MAIN context
	visibility_changed.connect(_on_visibility_changed)

	# IMPORTANT: Initialize MENU_MAIN context if menu starts visible
	# Use call_deferred to ensure this happens after visibility_changed signal is connected
	call_deferred("_initialize_context")

func _input(event: InputEvent) -> void:
	# Skip if input already handled by popup or other node
	if get_viewport().is_input_handled():
		return

	# Debug: Log ALL joypad button events
	if event is InputEventJoypadButton:
		print("[GameMenu._input] Button %d, pressed=%s, visible=%s, fullscreen=%s, is_handled=%s" % [
			event.button_index,
			event.pressed,
			visible,
			_is_fullscreen,
			get_viewport().is_input_handled()
		])

	if not visible:
		return

	# If in fullscreen mode, B returns to Status tab
	if _is_fullscreen:
		if event.is_action_pressed(aInputManager.ACTION_BACK):
			# Check if we can leave current panel (for Dorms validation)
			if _current_tab == "dorms" and not _can_leave_dorms():
				_toast("Finish placing everyone from the Common Room before leaving Dorms.")
				get_viewport().set_input_as_handled()
				return

			_exit_fullscreen()
			get_viewport().set_input_as_handled()
		# Let panel handle all other input
		return

	# When viewing Status panel, B closes the menu
	if event.is_action_pressed(aInputManager.ACTION_BACK):
		_close_menu()
		get_viewport().set_input_as_handled()

func _initialize_context() -> void:
	"""Initialize controller context after ready - handles case where menu starts visible"""
	if _ctrl_mgr and visible and _ctrl_mgr.get_current_context() == _ctrl_mgr.InputContext.OVERWORLD:
		print("[GameMenu] Initializing - pushing MENU_MAIN context")
		_ctrl_mgr.push_context(_ctrl_mgr.InputContext.MENU_MAIN)

func _connect_status_panel_signal() -> void:
	"""Connect to StatusPanel's tab_selected signal"""
	var status_panel = _panels.get("status")
	if status_panel and status_panel.has_signal("tab_selected"):
		if not status_panel.is_connected("tab_selected", Callable(self, "_on_status_panel_tab_selected")):
			status_panel.connect("tab_selected", Callable(self, "_on_status_panel_tab_selected"))

func _on_status_panel_tab_selected(tab_id: String) -> void:
	"""Handle tab selection from StatusPanel"""
	print("[GameMenu] Tab selected from StatusPanel: ", tab_id)
	_enter_fullscreen(tab_id)

func _select_tab(tab_id: String) -> void:
	# Guard: don't leave Dorms if Common has people to place
	if _current_tab == "dorms" and tab_id != "dorms":
		if not _can_leave_dorms():
			_toast("Finish placing everyone from the Common Room before leaving Dorms.")
			return

	if _current_tab == tab_id:
		return
	_current_tab = tab_id
	_show_panel(tab_id)

	var settings: Node = get_node_or_null("/root/aSettings")
	if settings and settings.has_method("set_value"):
		settings.call("set_value", "main_menu_last_tab", tab_id)

func _show_panel(tab_id: String) -> void:
	# If switching to a non-Status panel, enter fullscreen mode
	if tab_id != "status":
		_enter_fullscreen(tab_id)
		return

	# Showing Status panel - normal view with integrated tab buttons
	_is_fullscreen = false

	for child in _panel_holder.get_children():
		child.visible = false
	var panel := _get_or_create_panel(tab_id)
	if panel:
		panel.visible = true

func _get_or_create_panel(tab_id: String) -> Control:
	if _panels.has(tab_id):
		return _panels[tab_id] as Control

	if not TAB_DEFS.has(tab_id):
		push_warning("Unknown tab_id: %s" % tab_id)
		return null

	var scene_path: String = String(TAB_DEFS[tab_id]["scene"])
	var ps := load(scene_path) as PackedScene
	if ps == null:
		push_warning("Missing panel scene: %s" % scene_path)
		return null

	var inst := ps.instantiate() as Control
	_panel_holder.add_child(inst)
	_panels[tab_id] = inst
	return inst

# --- Hooks / helpers ---

func _on_common_added(_aid: String) -> void:
	_open_dorms_tab()

func _open_dorms_tab() -> void:
	_select_tab("dorms")

func _on_friday_reveals(pairs: Array) -> void:
	"""Show Friday RA Mail popup with revealed relationships"""
	if pairs.size() == 0:
		return  # Don't show popup if no reveals

	# Pause the game
	get_tree().paused = true

	# Build message from pairs
	var lines: PackedStringArray = []
	lines.append("The following neighbor relationships have been revealed after being neighbors for 2+ weeks:")
	lines.append("")  # Empty line for spacing

	for pair_v in pairs:
		if typeof(pair_v) != TYPE_DICTIONARY:
			continue
		var pair: Dictionary = pair_v
		var a_name: String = String(pair.get("a_name", ""))
		var b_name: String = String(pair.get("b_name", ""))
		var status: String = String(pair.get("status", "Neutral"))

		lines.append("• %s and %s are %s" % [a_name, b_name, status])

	var message := _join_lines(lines)

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

func _on_saturday_applied(new_layout: Dictionary, moves: Array) -> void:
	"""Store Saturday moves for later display"""
	_pending_saturday_moves = moves

func _on_saturday_reveals(pairs: Array) -> void:
	"""Show Saturday moves popup with executed moves and new relationships"""
	# Combine moves and relationship reveals
	var popup := preload("res://scripts/main_menu/panels/SaturdayMovesPopup.gd").create(_pending_saturday_moves, pairs)
	add_child(popup)
	await popup.closed
	popup.queue_free()
	_pending_saturday_moves.clear()

func _can_leave_dorms() -> bool:
	var ds := get_node_or_null("/root/aDormSystem")
	if ds == null:
		return true
	var list_v: Variant = ds.call("get_common") # merged Common + staged-to-place
	if typeof(list_v) == TYPE_PACKED_STRING_ARRAY:
		return (list_v as PackedStringArray).size() == 0
	if typeof(list_v) == TYPE_ARRAY:
		return (list_v as Array).size() == 0
	return true

func _toast(msg: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Heads up"
	dlg.dialog_text = msg
	add_child(dlg)
	dlg.popup_centered()
	await dlg.confirmed
	dlg.queue_free()

func _on_visibility_changed() -> void:
	"""Handle menu visibility changes - manage MENU_MAIN context and pause state"""
	if visible:
		# Pause the game when menu is shown
		get_tree().paused = true
		print("[GameMenu] Menu opened - pausing game")

		# Menu opened - push MENU_MAIN context as the base menu context
		# Only push if we're currently at OVERWORLD (not already in menu)
		if _ctrl_mgr and _ctrl_mgr.get_current_context() == _ctrl_mgr.InputContext.OVERWORLD:
			print("[GameMenu] Menu opened - pushing MENU_MAIN context")
			_ctrl_mgr.push_context(_ctrl_mgr.InputContext.MENU_MAIN)
	else:
		# Unpause the game when menu is hidden
		get_tree().paused = false
		print("[GameMenu] Menu closed - unpausing game")
		# Menu closed - pop back to OVERWORLD, cleaning up any panel contexts
		if _ctrl_mgr:
			print("[GameMenu] Menu closed - cleaning up contexts (current: %s, stack depth: %d)" % [
				_ctrl_mgr.InputContext.keys()[_ctrl_mgr.get_current_context()],
				_ctrl_mgr.context_stack.size()
			])
			# Pop all contexts until we're back at OVERWORLD
			var safety_counter = 0
			while _ctrl_mgr.get_current_context() != _ctrl_mgr.InputContext.OVERWORLD and safety_counter < 10:
				print("[GameMenu]   Popping context: %s" % _ctrl_mgr.InputContext.keys()[_ctrl_mgr.get_current_context()])
				_ctrl_mgr.pop_context()
				safety_counter += 1
				# Safety check to prevent infinite loop
				if _ctrl_mgr.context_stack.is_empty() and _ctrl_mgr.get_current_context() != _ctrl_mgr.InputContext.OVERWORLD:
					print("[GameMenu]   WARNING: Context stack empty but not at OVERWORLD - forcing context")
					_ctrl_mgr.set_context(_ctrl_mgr.InputContext.OVERWORLD)
					break
			print("[GameMenu] Context cleanup complete - now at: %s" % _ctrl_mgr.InputContext.keys()[_ctrl_mgr.get_current_context()])

func _close_menu() -> void:
	"""Close the game menu"""
	# Check if we can leave the current tab (for Dorms)
	if _current_tab == "dorms":
		if not _can_leave_dorms():
			_toast("Finish placing everyone from the Common Room before closing the menu.")
			return

	# Hide the menu and unpause
	visible = false
	get_tree().paused = false

func _enter_fullscreen(tab_id: String) -> void:
	"""Enter fullscreen mode for a panel"""
	print("[GameMenu] Entering fullscreen for tab: %s" % tab_id)

	# Get current panel (should be Status) and new panel
	var current_panel = _panels.get(_current_tab)
	var new_panel := _get_or_create_panel(tab_id)

	if not new_panel:
		return

	_is_fullscreen = true
	_current_tab = tab_id

	# If we have a current panel, animate the transition
	if current_panel and current_panel != new_panel:
		# Get viewport width for slide distance
		var viewport_width = get_viewport_rect().size.x

		# Position new panel off-screen to the right
		new_panel.position.x = viewport_width
		new_panel.visible = true
		new_panel.set_anchors_preset(Control.PRESET_FULL_RECT)

		# Create tween for smooth animation
		var tween = create_tween()
		tween.set_parallel(true)  # Run both animations simultaneously
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)

		# Slide current panel out to the left
		tween.tween_property(current_panel, "position:x", -viewport_width, 0.3)

		# Slide new panel in from the right
		tween.tween_property(new_panel, "position:x", 0, 0.3)

		# Hide current panel when animation completes
		tween.chain().tween_callback(func():
			current_panel.visible = false
			current_panel.position.x = 0  # Reset position for next time
		)
	else:
		# No current panel, just show the new one immediately
		new_panel.visible = true
		new_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		new_panel.position.x = 0

	# Give panel focus if it has the method
	# This will push the panel's specific context (e.g., MENU_ITEMS)
	if new_panel.has_method("panel_gained_focus"):
		print("[GameMenu] Calling panel_gained_focus for %s" % tab_id)
		new_panel.call("panel_gained_focus")
	if _ctrl_mgr:
		print("[GameMenu] After panel_gained_focus - context: %s, stack depth: %d" % [
			_ctrl_mgr.InputContext.keys()[_ctrl_mgr.get_current_context()],
			_ctrl_mgr.context_stack.size()
		])

func _exit_fullscreen() -> void:
	"""Exit fullscreen mode - return to Status tab with sidebar"""
	print("[GameMenu] Exiting fullscreen from tab: %s" % _current_tab)
	if _ctrl_mgr:
		print("[GameMenu] Before panel_lost_focus - context: %s, stack depth: %d" % [
			_ctrl_mgr.InputContext.keys()[_ctrl_mgr.get_current_context()],
			_ctrl_mgr.context_stack.size()
		])

	# Get current panel and Status panel
	var current_panel = _panels.get(_current_tab)
	var status_panel = _get_or_create_panel("status")

	# Call panel_lost_focus on the current panel
	# This will pop the panel's specific context (e.g., MENU_ITEMS -> MENU_MAIN)
	if current_panel and current_panel.has_method("panel_lost_focus"):
		print("[GameMenu] Calling panel_lost_focus for %s" % _current_tab)
		current_panel.call("panel_lost_focus")

	if _ctrl_mgr:
		print("[GameMenu] After panel_lost_focus - context: %s, stack depth: %d" % [
			_ctrl_mgr.InputContext.keys()[_ctrl_mgr.get_current_context()],
			_ctrl_mgr.context_stack.size()
		])

	_is_fullscreen = false

	# Remember which tab was being viewed
	var previous_tab = _current_tab

	# Animate the transition back to Status
	if current_panel and status_panel and current_panel != status_panel:
		# Get viewport width for slide distance
		var viewport_width = get_viewport_rect().size.x

		# Position Status panel off-screen to the left
		status_panel.position.x = -viewport_width
		status_panel.visible = true
		status_panel.set_anchors_preset(Control.PRESET_FULL_RECT)

		# Create tween for smooth animation
		var tween = create_tween()
		tween.set_parallel(true)  # Run both animations simultaneously
		tween.set_ease(Tween.EASE_IN_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)

		# Slide current panel out to the right
		tween.tween_property(current_panel, "position:x", viewport_width, 0.3)

		# Slide Status panel in from the left
		tween.tween_property(status_panel, "position:x", 0, 0.3)

		# Hide current panel and restore tab selection when animation completes
		tween.chain().tween_callback(func():
			current_panel.visible = false
			current_panel.position.x = 0  # Reset position for next time

			# Restore focus to the tab that was just being viewed
			if status_panel.has_method("select_tab"):
				status_panel.call("select_tab", previous_tab)
		)

		# Update current tab AFTER animation completes
		_current_tab = "status"
	else:
		# No animation needed, just switch immediately
		_select_tab("status")

		# Restore focus to the tab that was just being viewed
		if status_panel and status_panel.has_method("select_tab"):
			status_panel.call("select_tab", previous_tab)

func _join_lines(arr: PackedStringArray) -> String:
	"""Helper to join PackedStringArray into a single string"""
	var out := ""
	for i in range(arr.size()):
		if i > 0:
			out += "\n"
		out += arr[i]
	return out
