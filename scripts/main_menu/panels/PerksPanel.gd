extends Control
class_name PerksPanel

## Perks Panel - Fallout 3-Style Grid Design
## LEFT: 8×5 Grid (Stats × Tiers) | RIGHT: New Perk button + Acquired Perks + Details

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
@onready var _new_perk_button: Button = %NewPerkButton
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
var _selection_active: bool = false  # True when "New Perk" is pressed

func _ready() -> void:
	# Get system references
	_stats = get_node_or_null(STATS_PATH)
	_perk = get_node_or_null(PERK_PATH)

	# Connect signals
	if _new_perk_button:
		_new_perk_button.pressed.connect(_on_new_perk_pressed)
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

func _on_visibility_changed() -> void:
	"""Reset selection when panel becomes visible"""
	if visible:
		_selection_active = false
		_update_new_perk_button()

func _rebuild() -> void:
	"""Rebuild entire panel - refresh data and UI"""
	_load_data()
	_build_grid()
	_populate_acquired_perks()
	_update_new_perk_button()
	_clear_details()

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
				empty.custom_minimum_size = Vector2(80, 32)
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
	label.custom_minimum_size = Vector2(80, 32)
	label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	return label

func _create_level_cell(stat_id: String) -> Label:
	"""Create level cell showing current stat level"""
	var label: Label = Label.new()
	var level: int = _stat_levels.get(stat_id, 0)
	label.text = "Lv.%d" % level
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(80, 32)
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
	return label

func _create_tier_cell(stat_id: String, tier_index: int) -> Button:
	"""Create tier cell button"""
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(80, 32)
	button.add_theme_font_size_override("font_size", 10)

	var perk_info: Dictionary = _get_perk_info(stat_id, tier_index)

	# Set text
	button.text = "T%d" % (tier_index + 1)

	# Store metadata
	button.set_meta("stat_id", stat_id)
	button.set_meta("tier", tier_index)
	button.set_meta("perk_info", perk_info)

	# Color-code by status
	if perk_info["unlocked"]:
		button.text = "✔ T%d" % (tier_index + 1)
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

func _update_new_perk_button() -> void:
	"""Update New Perk button state"""
	if not _new_perk_button:
		return

	_new_perk_button.disabled = (_perk_points <= 0)

	if _selection_active:
		_new_perk_button.text = "Cancel Selection"
	else:
		_new_perk_button.text = "New Perk"

func _on_new_perk_pressed() -> void:
	"""Toggle perk selection mode"""
	_selection_active = not _selection_active
	_update_new_perk_button()

	if _selection_active:
		# Find first available perk
		_find_first_available_perk()
	else:
		_clear_selection()

func _find_first_available_perk() -> void:
	"""Find and select first available perk in grid"""
	for row in range(2, GRID_ROWS):  # Start from first tier row
		for col in range(GRID_COLS):
			if col >= _grid_cells[row].size():
				continue
			var cell: Control = _grid_cells[row][col]
			if cell is Button and not cell.disabled and cell.visible:
				_selected_row = row
				_selected_col = col
				_highlight_selection()
				_show_selected_perk_details()
				return

func _clear_selection() -> void:
	"""Clear grid selection highlighting"""
	_unhighlight_selection()

func _highlight_selection() -> void:
	"""Highlight the currently selected grid cell"""
	if _selected_row < 0 or _selected_row >= _grid_cells.size():
		return
	if _selected_col < 0 or _selected_col >= _grid_cells[_selected_row].size():
		return

	var cell: Control = _grid_cells[_selected_row][_selected_col]
	if cell is Button:
		cell.modulate = Color(1.3, 1.3, 0.8, 1.0)  # Yellow glow

func _unhighlight_selection() -> void:
	"""Remove highlight from currently selected cell"""
	if _selected_row < 0 or _selected_row >= _grid_cells.size():
		return
	if _selected_col < 0 or _selected_col >= _grid_cells[_selected_row].size():
		return

	var cell: Control = _grid_cells[_selected_row][_selected_col]
	if cell is Button:
		cell.modulate = Color(1.0, 1.0, 1.0, 1.0)

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
	"""Show perk details in right panel"""
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
	else:
		if stat_level < threshold:
			details += "Status: Locked (need %d more %s)\n" % [threshold - stat_level, _pretty_stat(perk["stat_id"])]
		else:
			details += "Status: Need perk points\n"

	if _details_text:
		_details_text.text = details

func _clear_details() -> void:
	"""Clear details panel"""
	if _perk_name:
		_perk_name.text = "(Select a perk)"
	if _details_text:
		_details_text.text = ""

func _on_tier_cell_pressed(stat_id: String, tier_index: int) -> void:
	"""Handle tier cell button press"""
	if not _selection_active:
		return

	var perk: Dictionary = _get_perk_info(stat_id, tier_index)
	if not perk["available"]:
		return

	_unlock_perk(perk)

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

	# Exit selection mode and rebuild
	_selection_active = false
	_rebuild()

func _on_acquired_perk_selected(index: int) -> void:
	"""Show details for selected acquired perk"""
	if index < 0 or index >= _acquired_perks.size():
		return

	var perk: Dictionary = _acquired_perks[index]
	_show_perk_details(perk)

func _unhandled_input(event: InputEvent) -> void:
	"""Handle controller input for grid navigation"""
	if not visible or not _selection_active:
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
	elif event.is_action_pressed("menu_back"):
		_selection_active = false
		_update_new_perk_button()
		_clear_selection()
		handled = true

	if handled:
		get_viewport().set_input_as_handled()

func _navigate_grid(col_delta: int, row_delta: int) -> void:
	"""Navigate through selectable grid cells"""
	_unhighlight_selection()

	var new_row: int = _selected_row + row_delta
	var new_col: int = _selected_col + col_delta

	# Clamp to grid bounds
	new_row = clamp(new_row, 2, GRID_ROWS - 1)  # Only tier rows
	new_col = clamp(new_col, 0, GRID_COLS - 1)

	# Find next valid cell
	while true:
		if new_row < 2 or new_row >= _grid_cells.size():
			break
		if new_col < 0 or new_col >= _grid_cells[new_row].size():
			break

		var cell: Control = _grid_cells[new_row][new_col]
		if cell is Button and cell.visible:
			_selected_row = new_row
			_selected_col = new_col
			break

		# Try next cell in direction
		if col_delta != 0:
			new_col += col_delta
		elif row_delta != 0:
			new_row += row_delta
		else:
			break

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
			_unlock_perk(perk)

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
