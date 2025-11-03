extends Control
class_name PerksPanel

## Perks Panel - Fallout 3-Style Grid Design (Flipped Layout)
## LEFT: Perk Points + Acquired Perks + Details | RIGHT: 8×5 Grid with perk names

# Autoload paths
const STATS_PATH: String = "/root/aStatsSystem"
const PERK_PATH: String = "/root/aPerkSystem"

# Constants
const GRID_ROWS: int = 8  # Header + Level + Tiers 1-5 + Tier 6
const GRID_COLS: int = 5  # 5 stats
const TIER_6_LEVEL_REQUIREMENT: int = 11
const DEFAULT_THRESHOLDS: PackedInt32Array = [1, 3, 5, 7, 10, 11]  # Including Tier 6

# Scene references
@onready var _perk_grid: GridContainer = %PerkGrid
@onready var _points_value: Label = %PointsValue
@onready var _acquired_list: ItemList = %AcquiredList
@onready var _perk_name: Label = %PerkName
@onready var _details_text: Label = %DetailsText

# System references
var _stats: Node = null
var _perk: Node = null

# Data
var _stat_ids: Array[String] = []
var _stat_levels: Dictionary = {}  # stat_id -> level
var _perk_points: int = 0
var _acquired_perks: Array[Dictionary] = []  # All unlocked perks

# Grid navigation
var _grid_cells: Array[Array] = []  # 8×5 array of Controls
var _selected_row: int = 2  # Start at first tier row
var _selected_col: int = 0

# Confirmation popup
var _active_popup: Control = null
var _pending_perk: Dictionary = {}  # Perk waiting for confirmation

func _ready() -> void:
	# Set high input priority so popup input blocking happens before parent nodes
	process_priority = 100

	# Get system references
	_stats = get_node_or_null(STATS_PATH)
	_perk = get_node_or_null(PERK_PATH)

	# Connect signals
	if _acquired_list:
		_acquired_list.item_selected.connect(_on_acquired_perk_selected)

	# Connect system signals
	if _stats:
		if _stats.has_signal("stats_changed"):
			_stats.connect("stats_changed", Callable(self, "_rebuild"))
		if _stats.has_signal("perk_points_changed"):
			_stats.connect("perk_points_changed", Callable(self, "_rebuild"))
	if _perk:
		if _perk.has_signal("perk_unlocked"):
			_perk.connect("perk_unlocked", Callable(self, "_rebuild"))
		if _perk.has_signal("perks_changed"):
			_perk.connect("perks_changed", Callable(self, "_rebuild"))

	# Connect visibility
	visibility_changed.connect(_on_visibility_changed)

	# Initial build
	call_deferred("_first_fill")

func _first_fill() -> void:
	"""Initial population of UI"""
	_rebuild()
	_find_first_selectable_perk()
	_show_selected_perk_details()

func _on_visibility_changed() -> void:
	"""Highlight selection when panel becomes visible"""
	if visible:
		call_deferred("_refresh_highlight")

func _refresh_highlight() -> void:
	"""Refresh grid highlight"""
	_find_first_selectable_perk()
	_highlight_selection()
	_show_selected_perk_details()

func _rebuild() -> void:
	"""Rebuild entire panel - refresh data and UI"""
	_load_data()
	_build_grid()
	_populate_acquired_perks()

func _load_data() -> void:
	"""Load stat levels and perk points"""
	_stat_levels.clear()
	_stat_ids.clear()
	_perk_points = 0
	_acquired_perks.clear()

	if not _stats:
		return

	# Get stat levels
	if _stats.has_method("get_stats_dict"):
		var stats_data: Variant = _stats.call("get_stats_dict")
		if typeof(stats_data) == TYPE_DICTIONARY:
			for key in stats_data.keys():
				var stat_id: String = String(key)
				var value: Variant = stats_data[key]
				if typeof(value) == TYPE_DICTIONARY:
					var stat_dict: Dictionary = value
					_stat_levels[stat_id] = int(stat_dict.get("level", int(stat_dict.get("lvl", 0))))
				else:
					_stat_levels[stat_id] = int(value)

	# Get perk points
	if _stats.has_method("get_perk_points"):
		_perk_points = int(_stats.call("get_perk_points"))
	elif _stats.has_method("get"):
		var points: Variant = _stats.get("perk_points")
		if typeof(points) in [TYPE_INT, TYPE_FLOAT]:
			_perk_points = int(points)

	# Get stat order
	if _stats.has_method("get_stats_order"):
		var order: Variant = _stats.call("get_stats_order")
		if typeof(order) == TYPE_ARRAY:
			for stat in order:
				var stat_id: String = String(stat)
				if _stat_levels.has(stat_id):
					_stat_ids.append(stat_id)

	# Fallback to all stats
	for stat_id in _stat_levels.keys():
		if not _stat_ids.has(stat_id):
			_stat_ids.append(stat_id)

	# Limit to 5 stats
	while _stat_ids.size() > GRID_COLS:
		_stat_ids.remove_at(_stat_ids.size() - 1)

	# Get all unlocked perks
	_load_acquired_perks()

	# Update points display
	if _points_value:
		_points_value.text = str(_perk_points)

func _load_acquired_perks() -> void:
	"""Load all unlocked perks"""
	_acquired_perks.clear()

	for stat_id in _stat_ids:
		for tier_i in range(6):  # Tiers 0-5 (1-6 in display)
			var perk_info: Dictionary = _get_perk_info(stat_id, tier_i)
			if perk_info["unlocked"]:
				_acquired_perks.append(perk_info)

func _build_grid() -> void:
	"""Build the 8×5 perk grid"""
	# Clear existing grid
	for child in _perk_grid.get_children():
		child.queue_free()
	_grid_cells.clear()

	# Initialize 2D array
	for row in range(GRID_ROWS):
		_grid_cells.append([])

	# Build grid row by row
	for row in range(GRID_ROWS):
		for col in range(GRID_COLS):
			if col >= _stat_ids.size():
				# Empty cell
				var empty: Control = Control.new()
				empty.custom_minimum_size = Vector2(120, 40)
				_perk_grid.add_child(empty)
				_grid_cells[row].append(empty)
				continue

			var stat_id: String = _stat_ids[col]

			if row == 0:
				# Header row: Stat names
				var header: Label = _create_header_cell(stat_id)
				_perk_grid.add_child(header)
				_grid_cells[row].append(header)
			elif row == 1:
				# Level row: Current stat levels
				var level_cell: Label = _create_level_cell(stat_id)
				_perk_grid.add_child(level_cell)
				_grid_cells[row].append(level_cell)
			else:
				# Tier rows (2-7 → Tiers 1-6)
				var tier_index: int = row - 2
				var tier_cell: Button = _create_tier_cell(stat_id, tier_index)
				_perk_grid.add_child(tier_cell)
				_grid_cells[row].append(tier_cell)

func _create_header_cell(stat_id: String) -> Label:
	"""Create header cell with stat name"""
	var label: Label = Label.new()
	label.text = _pretty_stat(stat_id)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(120, 40)
	label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	return label

func _create_level_cell(stat_id: String) -> Label:
	"""Create level cell showing current stat level"""
	var label: Label = Label.new()
	var level: int = _stat_levels.get(stat_id, 0)
	label.text = "Lv.%d" % level
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(120, 40)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
	return label

func _create_tier_cell(stat_id: String, tier_index: int) -> Button:
	"""Create tier cell button with perk name"""
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(120, 40)
	button.add_theme_font_size_override("font_size", 9)

	var perk_info: Dictionary = _get_perk_info(stat_id, tier_index)

	# Set text to perk name
	var perk_name: String = perk_info["name"]
	# Shorten long names
	if perk_name.length() > 15:
		perk_name = perk_name.substr(0, 12) + "..."
	button.text = perk_name

	# Store metadata
	button.set_meta("stat_id", stat_id)
	button.set_meta("tier", tier_index)
	button.set_meta("perk_info", perk_info)

	# Color-code by status
	if perk_info["unlocked"]:
		button.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))  # Green
		button.disabled = true
	elif perk_info["available"]:
		button.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))  # Yellow
		button.disabled = false
	else:
		button.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))  # Gray
		button.disabled = true

	# Hide Tier 6 if stat level < 11
	if tier_index == 5:  # Tier 6
		var stat_level: int = _stat_levels.get(stat_id, 0)
		button.visible = (stat_level >= TIER_6_LEVEL_REQUIREMENT)

	# Connect press
	button.pressed.connect(_on_tier_cell_pressed.bind(stat_id, tier_index))

	# Connect hover for mouse users
	button.mouse_entered.connect(_on_tier_cell_hovered.bind(stat_id, tier_index))

	return button

func _get_perk_info(stat_id: String, tier_index: int) -> Dictionary:
	"""Get complete info about a perk"""
	var stat_level: int = _stat_levels.get(stat_id, 0)

	var info: Dictionary = {
		"stat_id": stat_id,
		"tier": tier_index,
		"name": "%s T%d" % [_pretty_stat(stat_id), tier_index + 1],
		"description": "",
		"threshold": DEFAULT_THRESHOLDS[min(tier_index, DEFAULT_THRESHOLDS.size() - 1)],
		"unlocked": false,
		"available": false,
		"perk_id": ""
	}

	# Get data from PerkSystem
	if _perk:
		if _perk.has_method("get_threshold"):
			info["threshold"] = int(_perk.call("get_threshold", stat_id, tier_index))
		elif _perk.has_method("get_thresholds"):
			var thresholds: Variant = _perk.call("get_thresholds", stat_id)
			if typeof(thresholds) == TYPE_ARRAY and tier_index < (thresholds as Array).size():
				info["threshold"] = int((thresholds as Array)[tier_index])

		if _perk.has_method("get_perk_id"):
			info["perk_id"] = String(_perk.call("get_perk_id", stat_id, tier_index))

		if _perk.has_method("get_perk_name"):
			var name: String = String(_perk.call("get_perk_name", stat_id, tier_index))
			if name != "":
				info["name"] = name

		if _perk.has_method("get_perk_desc"):
			info["description"] = String(_perk.call("get_perk_desc", stat_id, tier_index))

		if _perk.has_method("is_unlocked"):
			info["unlocked"] = bool(_perk.call("is_unlocked", stat_id, tier_index))
		elif _perk.has_method("has_perk") and info["perk_id"] != "":
			info["unlocked"] = bool(_perk.call("has_perk", info["perk_id"]))

	# Check availability
	var meets_requirement: bool = stat_level >= info["threshold"]
	info["available"] = meets_requirement and not info["unlocked"] and _perk_points > 0

	return info

func _populate_acquired_perks() -> void:
	"""Populate the acquired perks list"""
	if not _acquired_list:
		return

	_acquired_list.clear()

	for perk in _acquired_perks:
		_acquired_list.add_item(perk["name"])

func _find_first_selectable_perk() -> void:
	"""Find and select first selectable perk in grid"""
	for row in range(2, GRID_ROWS):  # Start from first tier row
		for col in range(GRID_COLS):
			if col >= _grid_cells[row].size():
				continue
			var cell: Control = _grid_cells[row][col]
			if cell is Button and cell.visible:
				_selected_row = row
				_selected_col = col
				return

func _highlight_selection() -> void:
	"""Highlight the currently selected grid cell"""
	# Clear all highlights first
	for row in range(2, GRID_ROWS):
		for col in range(GRID_COLS):
			if row >= _grid_cells.size() or col >= _grid_cells[row].size():
				continue
			var cell: Control = _grid_cells[row][col]
			if cell is Button:
				cell.modulate = Color(1.0, 1.0, 1.0, 1.0)

	# Highlight selected
	if _selected_row < 0 or _selected_row >= _grid_cells.size():
		return
	if _selected_col < 0 or _selected_col >= _grid_cells[_selected_row].size():
		return

	var cell: Control = _grid_cells[_selected_row][_selected_col]
	if cell is Button:
		cell.modulate = Color(1.3, 1.3, 0.8, 1.0)  # Yellow glow

func _show_selected_perk_details() -> void:
	"""Show details for currently selected perk"""
	if _selected_row < 2 or _selected_row >= _grid_cells.size():
		return
	if _selected_col < 0 or _selected_col >= _grid_cells[_selected_row].size():
		return

	var cell: Control = _grid_cells[_selected_row][_selected_col]
	if not cell is Button or not cell.has_meta("perk_info"):
		return

	var perk: Dictionary = cell.get_meta("perk_info")
	_show_perk_details(perk)

func _show_perk_details(perk: Dictionary) -> void:
	"""Show perk details in left panel"""
	if _perk_name:
		_perk_name.text = perk["name"]

	var details: String = ""
	details += "Tier: %d\n\n" % (perk["tier"] + 1)

	if perk["description"] != "":
		details += "%s\n\n" % perk["description"]

	var stat_level: int = _stat_levels.get(perk["stat_id"], 0)
	var threshold: int = perk["threshold"]
	details += "Requires: %s ≥ %d\n" % [_pretty_stat(perk["stat_id"]), threshold]
	details += "Current: %s = %d\n\n" % [_pretty_stat(perk["stat_id"]), stat_level]

	if perk["unlocked"]:
		details += "Status: ✔ Unlocked\n"
	elif perk["available"]:
		details += "Status: Available!\n"
		details += "Cost: 1 Perk Point\n"
		details += "Press A to unlock\n"
	else:
		if stat_level < threshold:
			details += "Status: Locked (need %d more %s)\n" % [threshold - stat_level, _pretty_stat(perk["stat_id"])]
		else:
			details += "Status: Need perk points\n"

	if _details_text:
		_details_text.text = details

func _on_tier_cell_hovered(stat_id: String, tier_index: int) -> void:
	"""Handle mouse hover over tier cell"""
	# Block hover interactions when popup is active
	if _active_popup and is_instance_valid(_active_popup):
		return

	var perk: Dictionary = _get_perk_info(stat_id, tier_index)
	_show_perk_details(perk)

func _on_tier_cell_pressed(stat_id: String, tier_index: int) -> void:
	"""Handle tier cell button press"""
	# Block button presses when popup is active
	if _active_popup and is_instance_valid(_active_popup):
		return

	var perk: Dictionary = _get_perk_info(stat_id, tier_index)
	if not perk["available"]:
		return

	# Show confirmation popup instead of immediately unlocking
	_show_perk_confirmation(perk)

func _unlock_perk(perk: Dictionary) -> void:
	"""Attempt to unlock a perk"""
	var stat_id: String = perk["stat_id"]
	var tier: int = perk["tier"]

	# Verify requirements
	var stat_level: int = _stat_levels.get(stat_id, 0)
	if stat_level < perk["threshold"]:
		print("[PerksPanel] Cannot unlock: stat level too low")
		return

	if _perk_points < 1:
		print("[PerksPanel] Cannot unlock: no perk points")
		return

	# Spend perk point
	var spent: int = 0
	if _stats and _stats.has_method("spend_perk_point"):
		spent = int(_stats.call("spend_perk_point", 1))
	if spent < 1:
		print("[PerksPanel] Failed to spend perk point")
		return

	# Try to unlock
	var unlocked: bool = false
	if _perk:
		if _perk.has_method("unlock_by_id") and perk["perk_id"] != "":
			unlocked = bool(_perk.call("unlock_by_id", perk["perk_id"]))
		elif _perk.has_method("unlock_perk"):
			unlocked = bool(_perk.call("unlock_perk", stat_id, tier))
		elif _perk.has_method("unlock"):
			unlocked = bool(_perk.call("unlock", stat_id, tier))
	else:
		unlocked = true

	# Refund if failed
	if not unlocked:
		print("[PerksPanel] Unlock failed, refunding point")
		if _stats and _stats.has_method("add_perk_points"):
			_stats.call("add_perk_points", 1)

	# Rebuild
	_rebuild()
	_highlight_selection()
	_show_selected_perk_details()

func _show_perk_confirmation(perk: Dictionary) -> void:
	"""Show confirmation popup before unlocking perk"""
	# Prevent multiple popups
	if _active_popup and is_instance_valid(_active_popup):
		print("[PerksPanel] Popup already open, ignoring request")
		return

	# Store pending perk
	_pending_perk = perk

	# Create popup panel
	var popup_panel: Panel = Panel.new()
	popup_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	popup_panel.z_index = 100
	popup_panel.modulate.a = 0.0  # Start transparent for fade-in
	popup_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Block input during fade
	add_child(popup_panel)

	# Apply consistent styling
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 1.0)  # Dark gray
	style.border_color = Color(1.0, 0.7, 0.75, 1.0)  # Pink border
	style.set_border_width_all(2)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	popup_panel.add_theme_stylebox_override("panel", style)

	# Set active popup
	_active_popup = popup_panel
	print("[PerksPanel] Popup created and set as active")

	# Create content container
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.custom_minimum_size.x = 400
	popup_panel.add_child(vbox)

	# Title
	var title: Label = Label.new()
	title.text = "Confirm Perk Selection"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.75, 1.0))  # Pink
	vbox.add_child(title)

	# Perk name
	var perk_name: Label = Label.new()
	perk_name.text = perk.get("name", "Unknown Perk")
	perk_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	perk_name.add_theme_font_size_override("font_size", 14)
	vbox.add_child(perk_name)

	# Description
	var desc: Label = Label.new()
	desc.text = perk.get("description", "")
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 380
	vbox.add_child(desc)

	# Cost info
	var cost: Label = Label.new()
	cost.text = "Cost: 1 Perk Point"
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.add_theme_font_size_override("font_size", 12)
	vbox.add_child(cost)

	# Button row
	var button_row: HBoxContainer = HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 16)
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(button_row)

	# Confirm button
	var confirm_btn: Button = Button.new()
	confirm_btn.text = "Unlock Perk"
	confirm_btn.custom_minimum_size.x = 120
	confirm_btn.process_mode = Node.PROCESS_MODE_ALWAYS  # Must process when game is paused
	confirm_btn.focus_mode = Control.FOCUS_ALL
	confirm_btn.pressed.connect(_on_confirm_perk)
	button_row.add_child(confirm_btn)

	# Cancel button
	var cancel_btn: Button = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size.x = 120
	cancel_btn.process_mode = Node.PROCESS_MODE_ALWAYS  # Must process when game is paused
	cancel_btn.focus_mode = Control.FOCUS_ALL
	cancel_btn.pressed.connect(_on_cancel_perk)
	button_row.add_child(cancel_btn)

	# Set up focus neighbors for left/right navigation
	confirm_btn.focus_neighbor_right = confirm_btn.get_path_to(cancel_btn)
	cancel_btn.focus_neighbor_left = cancel_btn.get_path_to(confirm_btn)

	# Auto-size and center
	await get_tree().process_frame
	await get_tree().process_frame
	popup_panel.size = vbox.size + Vector2(20, 20)
	vbox.position = Vector2(10, 10)

	var viewport_size: Vector2 = get_viewport_rect().size
	popup_panel.position = (viewport_size - popup_panel.size) / 2.0

	# Game is already paused by GameMenu - no need to pause again

	# Fade in
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(popup_panel, "modulate:a", 1.0, 0.3)
	tween.tween_callback(func():
		popup_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		confirm_btn.grab_focus()
	)

func _on_confirm_perk() -> void:
	"""User confirmed perk unlock"""
	if _pending_perk.is_empty():
		return

	# Close popup
	_close_confirmation_popup()

	# Unlock the perk
	_unlock_perk(_pending_perk)
	_pending_perk.clear()

func _on_cancel_perk() -> void:
	"""User cancelled perk unlock"""
	_pending_perk.clear()
	_close_confirmation_popup()

func _close_confirmation_popup() -> void:
	"""Close and fade out confirmation popup"""
	if not _active_popup or not is_instance_valid(_active_popup):
		return

	var popup_to_close = _active_popup
	_active_popup = null

	# Fade out
	popup_to_close.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(popup_to_close, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func():
		# Don't unpause here - let GameMenu control pause state
		# The game should stay paused while the menu is open
		if is_instance_valid(popup_to_close):
			popup_to_close.queue_free()
	)

func _on_acquired_perk_selected(index: int) -> void:
	"""Show details for selected acquired perk"""
	if index < 0 or index >= _acquired_perks.size():
		return

	var perk: Dictionary = _acquired_perks[index]
	_show_perk_details(perk)

func _input(event: InputEvent) -> void:
	"""Catch ALL input when popup is active to prevent it from reaching other systems"""
	# When popup is active, block everything except what we explicitly handle
	if _active_popup and is_instance_valid(_active_popup):
		# Handle Accept - manually trigger confirm (don't rely on button focus/signals)
		if event.is_action_pressed("menu_accept"):
			print("[PerksPanel._input] Accept pressed - confirming perk")
			_on_confirm_perk()
			get_viewport().set_input_as_handled()
			return
		# Handle Back to cancel
		elif event.is_action_pressed("menu_back"):
			print("[PerksPanel._input] Back pressed - cancelling perk")
			_on_cancel_perk()
			get_viewport().set_input_as_handled()
			return
		# Block ALL other input to prevent grid navigation in background
		get_viewport().set_input_as_handled()
		return

func _unhandled_input(event: InputEvent) -> void:
	"""Handle controller input for grid navigation"""
	if not visible:
		return

	# Block ALL input when popup is active (buttons handle their own input via signals)
	if _active_popup and is_instance_valid(_active_popup):
		print("[PerksPanel._unhandled_input] POPUP ACTIVE - blocking: %s" % event)
		get_viewport().set_input_as_handled()
		return

	var handled: bool = false

	if event.is_action_pressed("ui_up"):
		_navigate_grid(0, -1)
		handled = true
	elif event.is_action_pressed("ui_down"):
		_navigate_grid(0, 1)
		handled = true
	elif event.is_action_pressed("ui_left"):
		_navigate_grid(-1, 0)
		handled = true
	elif event.is_action_pressed("ui_right"):
		_navigate_grid(1, 0)
		handled = true
	elif event.is_action_pressed("menu_accept"):
		_activate_selected_cell()
		handled = true

	if handled:
		get_viewport().set_input_as_handled()

func _navigate_grid(col_delta: int, row_delta: int) -> void:
	"""Navigate through selectable grid cells"""
	var new_row: int = _selected_row + row_delta
	var new_col: int = _selected_col + col_delta

	# Clamp to grid bounds
	new_row = clamp(new_row, 2, GRID_ROWS - 1)  # Only tier rows
	new_col = clamp(new_col, 0, GRID_COLS - 1)

	# Find next valid cell
	var found: bool = false
	var attempts: int = 0
	while not found and attempts < 50:
		if new_row < 2 or new_row >= _grid_cells.size():
			break
		if new_col < 0 or new_col >= _grid_cells[new_row].size():
			break

		var cell: Control = _grid_cells[new_row][new_col]
		if cell is Button and cell.visible:
			_selected_row = new_row
			_selected_col = new_col
			found = true
			break

		# Try next cell in direction
		if col_delta != 0:
			new_col += col_delta
			if new_col < 0 or new_col >= GRID_COLS:
				break
		elif row_delta != 0:
			new_row += row_delta
			if new_row < 2 or new_row >= GRID_ROWS:
				break
		else:
			break

		attempts += 1

	_highlight_selection()
	_show_selected_perk_details()

func _activate_selected_cell() -> void:
	"""Activate (unlock) the selected perk"""
	if _selected_row < 2 or _selected_row >= _grid_cells.size():
		return
	if _selected_col < 0 or _selected_col >= _grid_cells[_selected_row].size():
		return

	var cell: Control = _grid_cells[_selected_row][_selected_col]
	if cell is Button and not cell.disabled and cell.has_meta("perk_info"):
		var perk: Dictionary = cell.get_meta("perk_info")
		if perk["available"]:
			_show_perk_confirmation(perk)

# ==============================================================================
# Helper Functions
# ==============================================================================

func _pretty_stat(stat_id: String) -> String:
	"""Get display name for a stat"""
	if _stats and _stats.has_method("get_stat_display_name"):
		var name: Variant = _stats.call("get_stat_display_name", stat_id)
		if typeof(name) == TYPE_STRING and String(name) != "":
			return String(name)

	var formatted: String = stat_id.replace("_", " ").strip_edges()
	if formatted.length() == 0:
		return "Stat"
	return formatted.substr(0, 1).to_upper() + formatted.substr(1)
