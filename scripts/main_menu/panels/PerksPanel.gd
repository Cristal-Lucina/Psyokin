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
@onready var _details_left_column: RichTextLabel = %LeftColumn
@onready var _details_right_column: RichTextLabel = %RightColumn

# Container references for styling
@onready var _grid_column: VBoxContainer = get_node("Root/GridColumn") if has_node("Root/GridColumn") else null
@onready var _right_column: VBoxContainer = get_node("Root/RightColumn") if has_node("Root/RightColumn") else null

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

# Selection arrow
var _selection_arrow: Label = null
var _debug_box: PanelContainer = null
var _arrow_tween: Tween = null

# Active popup tracking (needed for cleanup when panel is hidden)
var _active_popup: ToastPopup = null
var _active_overlay: CanvasLayer = null

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
	_apply_core_vibe_styling()
	_create_selection_arrow()
	_rebuild()
	_find_first_selectable_perk()
	_show_selected_perk_details()
	_update_arrow_position()

func _apply_core_vibe_styling() -> void:
	"""Apply Core Vibe neon-kawaii styling to PerksPanel elements"""

	# Wrap columns in styled PanelContainers for the neon border look
	if _grid_column:
		var grid_panel = _wrap_in_styled_panel(_grid_column, aCoreVibeTheme.COLOR_SKY_CYAN)
		if grid_panel:
			print("[PerksPanel] Grid column wrapped in styled panel")

	if _right_column:
		var right_panel = _wrap_in_styled_panel(_right_column, aCoreVibeTheme.COLOR_GRAPE_VIOLET)
		if right_panel:
			print("[PerksPanel] Right column wrapped in styled panel")

	# Style perk points value
	if _points_value:
		aCoreVibeTheme.style_label(_points_value, aCoreVibeTheme.COLOR_ELECTRIC_LIME, 18)

	# Style perk name label
	if _perk_name:
		aCoreVibeTheme.style_label(_perk_name, aCoreVibeTheme.COLOR_SKY_CYAN, 18)

	# Style details columns
	if _details_left_column:
		_details_left_column.add_theme_color_override("default_color", aCoreVibeTheme.COLOR_MILK_WHITE)
		_details_left_column.add_theme_font_size_override("normal_font_size", 14)

	if _details_right_column:
		_details_right_column.add_theme_color_override("default_color", aCoreVibeTheme.COLOR_MILK_WHITE)
		_details_right_column.add_theme_font_size_override("normal_font_size", 14)

func _create_selection_arrow() -> void:
	"""Create the selection arrow indicator for perk grid"""
	if not _perk_grid:
		return

	# Create arrow label
	_selection_arrow = Label.new()
	_selection_arrow.text = "◄"  # Left-pointing arrow
	_selection_arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_selection_arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_selection_arrow.add_theme_font_size_override("font_size", 43)
	_selection_arrow.modulate = Color(1, 1, 1, 1)  # White
	_selection_arrow.custom_minimum_size = Vector2(54, 72)
	_selection_arrow.size = Vector2(54, 72)
	_selection_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_arrow.z_index = 100  # Above other elements

	# Add to main PerksPanel (Control) not the PanelContainer
	add_child(_selection_arrow)

	# Ensure size is locked after adding to tree
	await get_tree().process_frame
	_selection_arrow.size = Vector2(54, 72)

	# Create debug box (160px wide, 20px height)
	_debug_box = PanelContainer.new()
	_debug_box.custom_minimum_size = Vector2(160, 20)
	_debug_box.size = Vector2(160, 20)
	_debug_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_box.z_index = 100  # Same layer as arrow

	# Create transparent rounded style
	var debug_style = StyleBoxFlat.new()
	debug_style.bg_color = Color(aCoreVibeTheme.COLOR_INK_CHARCOAL.r, aCoreVibeTheme.COLOR_INK_CHARCOAL.g, aCoreVibeTheme.COLOR_INK_CHARCOAL.b, 0.0)  # Transparent
	debug_style.corner_radius_top_left = 8
	debug_style.corner_radius_top_right = 8
	debug_style.corner_radius_bottom_left = 8
	debug_style.corner_radius_bottom_right = 8
	_debug_box.add_theme_stylebox_override("panel", debug_style)

	add_child(_debug_box)
	await get_tree().process_frame
	_debug_box.size = Vector2(160, 20)

	# Start pulsing animation
	_start_arrow_pulse()

func _start_arrow_pulse() -> void:
	"""Start pulsing animation for the arrow"""
	if not _selection_arrow:
		return

	# Kill existing tween if any
	if _arrow_tween and is_instance_valid(_arrow_tween):
		_arrow_tween.kill()

	_arrow_tween = create_tween()
	_arrow_tween.set_loops()
	_arrow_tween.set_trans(Tween.TRANS_SINE)
	_arrow_tween.set_ease(Tween.EASE_IN_OUT)

	# Pulse left 6 pixels then back
	var base_x = _selection_arrow.position.x
	_arrow_tween.tween_property(_selection_arrow, "position:x", base_x - 6, 0.6)
	_arrow_tween.tween_property(_selection_arrow, "position:x", base_x, 0.6)

func _wrap_in_styled_panel(container: Control, border_color: Color) -> PanelContainer:
	"""Wrap a container in a styled PanelContainer with rounded neon borders"""
	if not container or not container.get_parent():
		return null

	var parent = container.get_parent()
	var index = container.get_index()

	# Create styled panel
	var panel = PanelContainer.new()
	var panel_style = aCoreVibeTheme.create_panel_style(
		border_color,                             # Border color
		aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
		aCoreVibeTheme.PANEL_OPACITY_SEMI,        # Semi-transparent
		aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
		aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
		aCoreVibeTheme.SHADOW_SIZE_MEDIUM         # 6px glow
	)
	panel_style.content_margin_left = 10
	panel_style.content_margin_top = 10
	panel_style.content_margin_right = 10
	panel_style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", panel_style)

	# Preserve size flags
	panel.size_flags_horizontal = container.size_flags_horizontal
	panel.size_flags_vertical = container.size_flags_vertical

	# Reparent container into panel
	parent.remove_child(container)
	panel.add_child(container)
	parent.add_child(panel)
	parent.move_child(panel, index)

	return panel

func _on_visibility_changed() -> void:
	"""Highlight selection when panel becomes visible, cleanup popups when hidden"""
	if visible:
		call_deferred("_refresh_highlight")
	else:
		# Clean up any active popups when panel is hidden
		_cleanup_active_popup()

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
	"""Create header cell with stat name - Core Vibe styled"""
	var label: Label = Label.new()
	label.text = _pretty_stat(stat_id)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(120, 40)
	# Core Vibe: Sky Cyan headers
	label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_SKY_CYAN)
	label.add_theme_font_size_override("font_size", 14)
	return label

func _create_level_cell(stat_id: String) -> Label:
	"""Create level cell showing current stat level - Core Vibe styled"""
	var label: Label = Label.new()
	var level: int = _stat_levels.get(stat_id, 0)
	label.text = "Lv.%d" % level
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(120, 40)
	# Core Vibe: Electric Lime level display
	label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_ELECTRIC_LIME)
	label.add_theme_font_size_override("font_size", 14)
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

	# Create styled button with borders
	var button_style = StyleBoxFlat.new()
	button_style.bg_color = aCoreVibeTheme.COLOR_INK_CHARCOAL
	button_style.corner_radius_top_left = 8
	button_style.corner_radius_top_right = 8
	button_style.corner_radius_bottom_left = 8
	button_style.corner_radius_bottom_right = 8
	button_style.content_margin_left = 4
	button_style.content_margin_top = 4
	button_style.content_margin_right = 4
	button_style.content_margin_bottom = 4

	# Core Vibe: Color-code by status with neon colors and borders
	if perk_info["unlocked"]:
		# Unlocked: Electric Lime text, no border
		button.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_ELECTRIC_LIME)
		button.disabled = true
		button_style.border_width_left = 0
		button_style.border_width_top = 0
		button_style.border_width_right = 0
		button_style.border_width_bottom = 0
	elif perk_info["available"]:
		# Available: Milk White text, Plasma Teal border
		button.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
		button.disabled = false
		button_style.border_width_left = 2
		button_style.border_width_top = 2
		button_style.border_width_right = 2
		button_style.border_width_bottom = 2
		button_style.border_color = aCoreVibeTheme.COLOR_PLASMA_TEAL
	else:
		# Locked: Dimmed Milk White (disabled), no border
		button.add_theme_color_override("font_color", Color(aCoreVibeTheme.COLOR_MILK_WHITE.r, aCoreVibeTheme.COLOR_MILK_WHITE.g, aCoreVibeTheme.COLOR_MILK_WHITE.b, 0.3))
		button.disabled = true
		button_style.border_width_left = 0
		button_style.border_width_top = 0
		button_style.border_width_right = 0
		button_style.border_width_bottom = 0

	# Apply style
	button.add_theme_stylebox_override("normal", button_style)
	button.add_theme_stylebox_override("hover", button_style.duplicate())
	button.add_theme_stylebox_override("pressed", button_style.duplicate())
	button.add_theme_stylebox_override("disabled", button_style.duplicate())

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
	"""Highlight the currently selected grid cell and update arrow position"""
	# Clear all highlights and restore original styles
	for row in range(2, GRID_ROWS):
		for col in range(GRID_COLS):
			if row >= _grid_cells.size() or col >= _grid_cells[row].size():
				continue
			var grid_cell: Control = _grid_cells[row][col]
			if grid_cell is Button:
				grid_cell.modulate = Color(1.0, 1.0, 1.0, 1.0)
				# Restore original border based on perk status
				if grid_cell.has_meta("perk_info"):
					var perk_info: Dictionary = grid_cell.get_meta("perk_info")
					var button_style = grid_cell.get_theme_stylebox("normal")
					if button_style and button_style is StyleBoxFlat:
						var style: StyleBoxFlat = button_style as StyleBoxFlat
						if perk_info["available"]:
							# Restore Plasma Teal border
							style.border_color = aCoreVibeTheme.COLOR_PLASMA_TEAL

	# Highlight selected
	if _selected_row < 0 or _selected_row >= _grid_cells.size():
		if _selection_arrow:
			_selection_arrow.visible = false
		if _debug_box:
			_debug_box.visible = false
		return
	if _selected_col < 0 or _selected_col >= _grid_cells[_selected_row].size():
		if _selection_arrow:
			_selection_arrow.visible = false
		if _debug_box:
			_debug_box.visible = false
		return

	var cell: Control = _grid_cells[_selected_row][_selected_col]
	if cell is Button:
		# Core Vibe: Bubble Magenta glow and border for selection
		cell.modulate = Color(1.8, 1.2, 1.6, 1.0)  # Bubble Magenta glow

		# Change border to Bubble Magenta
		var button_style = cell.get_theme_stylebox("normal")
		if button_style and button_style is StyleBoxFlat:
			var style: StyleBoxFlat = button_style as StyleBoxFlat
			if cell.has_meta("perk_info"):
				var perk_info: Dictionary = cell.get_meta("perk_info")
				if perk_info["available"]:
					style.border_color = aCoreVibeTheme.COLOR_BUBBLE_MAGENTA
					style.border_width_left = 2
					style.border_width_top = 2
					style.border_width_right = 2
					style.border_width_bottom = 2

	# Update arrow position
	_update_arrow_position()

func _update_arrow_position() -> void:
	"""Update arrow position to align with selected perk cell"""
	if not _selection_arrow or not _perk_grid:
		return

	if _selected_row < 2 or _selected_row >= _grid_cells.size():
		_selection_arrow.visible = false
		if _debug_box:
			_debug_box.visible = false
		return

	if _selected_col < 0 or _selected_col >= _grid_cells[_selected_row].size():
		_selection_arrow.visible = false
		if _debug_box:
			_debug_box.visible = false
		return

	var cell: Control = _grid_cells[_selected_row][_selected_col]
	if not cell is Button or not cell.visible:
		_selection_arrow.visible = false
		if _debug_box:
			_debug_box.visible = false
		return

	_selection_arrow.visible = true

	# Wait for layout to complete
	await get_tree().process_frame

	# Get cell global position
	var cell_global_pos = cell.global_position
	var panel_global_pos = global_position

	# Calculate position in PerksPanel coordinates
	var cell_offset_in_panel = cell_global_pos - panel_global_pos

	# Position arrow to the right center of the cell with offset, then shift right 40px more, then left 16px
	var arrow_x = cell_offset_in_panel.x + cell.size.x - 8.0 - 80.0 + 40.0 + 40.0 - 8.0 - 8.0
	var arrow_y = cell_offset_in_panel.y + (cell.size.y / 2.0) - (_selection_arrow.size.y / 2.0)

	_selection_arrow.position = Vector2(arrow_x, arrow_y)

	# Position debug box to the left of arrow
	if _debug_box:
		_debug_box.visible = true
		var debug_x = arrow_x - _debug_box.size.x - 4.0  # 4px gap to the left of arrow
		var debug_y = arrow_y + (_selection_arrow.size.y / 2.0) - (_debug_box.size.y / 2.0)  # Center vertically with arrow
		_debug_box.position = Vector2(debug_x, debug_y)

	# Restart pulsing animation with new position
	_start_arrow_pulse()

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
	"""Show perk details in two-column layout"""
	if _perk_name:
		_perk_name.text = perk["name"]

	if not _details_left_column or not _details_right_column:
		return

	var stat_level: int = _stat_levels.get(perk["stat_id"], 0)
	var threshold: int = perk["threshold"]
	var sky_cyan_hex: String = "#4DE9FF"

	# Build LEFT column: Tier, Description, Requires, Current
	var left_text: String = ""
	left_text += "[color=%s]Tier:[/color] %d\n\n" % [sky_cyan_hex, perk["tier"] + 1]

	if perk["description"] != "":
		left_text += "[color=%s]Description:[/color]\n%s\n\n" % [sky_cyan_hex, perk["description"]]

	left_text += "[color=%s]Requires:[/color]\n%s ≥ %d\n\n" % [sky_cyan_hex, _pretty_stat(perk["stat_id"]), threshold]
	left_text += "[color=%s]Current:[/color]\n%s = %d" % [sky_cyan_hex, _pretty_stat(perk["stat_id"]), stat_level]

	# Build RIGHT column: Status, Cost, Unlockable
	var right_text: String = ""

	if perk["unlocked"]:
		right_text += "[color=%s]Status:[/color]\n✔ Unlocked\n\n" % sky_cyan_hex
	elif perk["available"]:
		right_text += "[color=%s]Status:[/color]\nAvailable!\n\n" % sky_cyan_hex
		right_text += "[color=%s]Cost:[/color]\n1 Perk Point\n\n" % sky_cyan_hex
		right_text += "[color=%s]Unlockable:[/color]\nPress A to unlock" % sky_cyan_hex
	else:
		if stat_level < threshold:
			right_text += "[color=%s]Status:[/color]\nLocked\n\n" % sky_cyan_hex
			right_text += "[color=%s]Unlockable:[/color]\nNeed %d more %s" % [sky_cyan_hex, threshold - stat_level, _pretty_stat(perk["stat_id"])]
		else:
			right_text += "[color=%s]Status:[/color]\nLocked\n\n" % sky_cyan_hex
			right_text += "[color=%s]Unlockable:[/color]\nNeed perk points" % sky_cyan_hex

	_details_left_column.text = left_text
	_details_right_column.text = right_text

func _on_tier_cell_hovered(stat_id: String, tier_index: int) -> void:
	"""Handle mouse hover over tier cell"""
	# Note: ToastPopup blocks mouse input automatically (MOUSE_FILTER_STOP)
	var perk: Dictionary = _get_perk_info(stat_id, tier_index)
	_show_perk_details(perk)

func _on_tier_cell_pressed(stat_id: String, tier_index: int) -> void:
	"""Handle tier cell button press"""
	# Note: ToastPopup blocks mouse input automatically (MOUSE_FILTER_STOP)
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
	"""Show confirmation popup before unlocking perk using ToastPopup"""
	var perk_name: String = perk.get("name", "Unknown Perk")
	var desc: String = perk.get("description", "")

	# Build message with perk details
	var message := "%s\n\n%s\n\nCost: 1 Perk Point\n\nUnlock this perk?" % [perk_name, desc]

	print("[PerksPanel] Showing perk confirmation for: %s" % perk_name)

	# Clean up any existing popup first
	_cleanup_active_popup()

	# Create CanvasLayer overlay for popup (ensures it's on top and processes input first)
	var overlay := CanvasLayer.new()
	overlay.layer = 100  # High layer to ensure it's on top
	overlay.process_mode = Node.PROCESS_MODE_ALWAYS  # Process even when paused
	overlay.process_priority = -1000  # CRITICAL: Process before GameMenu
	get_tree().root.add_child(overlay)

	# Create and show popup
	var popup := ToastPopup.create(message, "Confirm")
	popup.process_mode = Node.PROCESS_MODE_ALWAYS  # Process even when paused
	overlay.add_child(popup)

	# Track active popup for cleanup
	_active_popup = popup
	_active_overlay = overlay

	# Wait for user response
	var result: bool = await popup.confirmed

	# Defer clearing tracking variables to next frame
	# This allows the input blocking check to work in the same frame
	call_deferred("_clear_popup_tracking")

	# Clean up (only if not already cleaned up)
	if is_instance_valid(popup):
		popup.queue_free()
	if is_instance_valid(overlay):
		overlay.queue_free()

	# Handle response
	if result:
		print("[PerksPanel] User confirmed perk unlock")
		_unlock_perk(perk)
	else:
		print("[PerksPanel] User canceled perk unlock")

func _clear_popup_tracking() -> void:
	"""Deferred clearing of popup tracking variables"""
	_active_popup = null
	_active_overlay = null

func _cleanup_active_popup() -> void:
	"""Clean up any active popup and overlay"""
	print("[PerksPanel] _cleanup_active_popup called, popup=%s, overlay=%s" % [_active_popup != null, _active_overlay != null])

	# Store references locally before clearing tracking variables
	var popup = _active_popup
	var overlay = _active_overlay

	# Clear tracking immediately to prevent re-entrance
	_active_popup = null
	_active_overlay = null

	# Emit signal to unblock await BEFORE freeing
	if popup and is_instance_valid(popup):
		print("[PerksPanel] Emitting confirmed(false) and queuing free")
		# Emit signal first to unblock the await (this is synchronous)
		popup.confirmed.emit(false)
		# Queue free (deferred deletion)
		popup.queue_free()

	# Clean up overlay
	if overlay and is_instance_valid(overlay):
		print("[PerksPanel] Freeing active overlay")
		overlay.queue_free()

func _on_acquired_perk_selected(index: int) -> void:
	"""Show details for selected acquired perk"""
	if index < 0 or index >= _acquired_perks.size():
		return

	var perk: Dictionary = _acquired_perks[index]
	_show_perk_details(perk)

func _input(_event: InputEvent) -> void:
	"""Handle input for perk grid navigation"""
	# Note: ToastPopup handles its own input, so we don't need to handle it here
	# (Old manual popup handling removed - ToastPopup is self-contained)
	pass  # Empty function - kept for override clarity

func _unhandled_input(event: InputEvent) -> void:
	"""Handle controller input for grid navigation"""
	if not visible:
		return

	# Block all input if popup is active
	if _active_popup != null:
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
		var stat_name: Variant = _stats.call("get_stat_display_name", stat_id)
		if typeof(stat_name) == TYPE_STRING and String(stat_name) != "":
			return String(stat_name)

	var formatted: String = stat_id.replace("_", " ").strip_edges()
	if formatted.length() == 0:
		return "Stat"
	return formatted.substr(0, 1).to_upper() + formatted.substr(1)
