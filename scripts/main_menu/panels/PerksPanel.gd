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

# Note: Confirmation popup handling is now done by ConfirmationPopup class
# (removed _active_popup and _pending_perk - no longer needed)

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

func _rebuild(_arg1 = null, _arg2 = null, _arg3 = null) -> void:
	"""Rebuild entire panel - refresh data and UI
	Accepts optional arguments from signals (perk_points_changed sends 1, perk_unlocked sends 3)"""
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
			var perk_name: String = String(_perk.call("get_perk_name", stat_id, tier_index))
			if perk_name != "":
				info["name"] = perk_name

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
			var grid_cell: Control = _grid_cells[row][col]
			if grid_cell is Button:
				grid_cell.modulate = Color(1.0, 1.0, 1.0, 1.0)

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
	# Note: ConfirmationPopup blocks mouse input automatically (MOUSE_FILTER_STOP)
	var perk: Dictionary = _get_perk_info(stat_id, tier_index)
	_show_perk_details(perk)

func _on_tier_cell_pressed(stat_id: String, tier_index: int) -> void:
	"""Handle tier cell button press"""
	# Note: ConfirmationPopup blocks mouse input automatically (MOUSE_FILTER_STOP)
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
	"""Show confirmation popup before unlocking perk using ConfirmationPopup"""
	var perk_name: String = perk.get("name", "Unknown Perk")
	var desc: String = perk.get("description", "")

	# Build message with perk details
	var message := "%s\n\n%s\n\nCost: 1 Perk Point\n\nUnlock this perk?" % [perk_name, desc]

	print("[PerksPanel] Showing perk confirmation for: %s" % perk_name)

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

	# Handle response
	if result:
		print("[PerksPanel] User confirmed perk unlock")
		_unlock_perk(perk)
	else:
		print("[PerksPanel] User canceled perk unlock")

func _on_acquired_perk_selected(index: int) -> void:
	"""Show details for selected acquired perk"""
	if index < 0 or index >= _acquired_perks.size():
		return

	var perk: Dictionary = _acquired_perks[index]
	_show_perk_details(perk)

func _input(_event: InputEvent) -> void:
	"""Handle input for perk grid navigation"""
	# Note: ConfirmationPopup handles its own input, so we don't need to handle it here
	# (Old manual popup handling removed - ConfirmationPopup is self-contained)
	pass  # Empty function - kept for override clarity

func _unhandled_input(event: InputEvent) -> void:
	"""Handle controller input for grid navigation"""
	if not visible:
		return

	# Note: ConfirmationPopup handles its own input blocking, no need to check here

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
		var stat_name: Variant = _stats.call("get_stat_display_name", stat_id)
		if typeof(stat_name) == TYPE_STRING and String(stat_name) != "":
			return String(stat_name)

	var formatted: String = stat_id.replace("_", " ").strip_edges()
	if formatted.length() == 0:
		return "Stat"
	return formatted.substr(0, 1).to_upper() + formatted.substr(1)
