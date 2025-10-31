extends Control
class_name PerksPanel

## Perks Panel - Clean 3-Column Controller-First Design
## LEFT: Stat selection | MIDDLE: Tier/perk list | RIGHT: Perk details + unlock

# Autoload paths
const STATS_PATH: String = "/root/aStatsSystem"
const PERK_PATH: String = "/root/aPerkSystem"

# Constants
const MAX_TIERS: int = 5
const DEFAULT_THRESHOLDS: PackedInt32Array = [1, 3, 5, 7, 10]

# Scene references
@onready var _stat_list: ItemList = %StatList
@onready var _tier_list: ItemList = %TierList
@onready var _tier_label: Label = %TierLabel
@onready var _points_value: Label = %PointsValue
@onready var _perk_name: Label = %PerkName
@onready var _details_text: Label = %DetailsText
@onready var _unlock_button: Button = %UnlockButton

# System references
var _stats: Node = null
var _perk: Node = null

# Data
var _stat_ids: Array[String] = []
var _stat_levels: Dictionary = {}  # stat_id -> level
var _perk_points: int = 0

# Selection state
var _selected_stat: String = ""
var _selected_tier: int = -1
var _focus_mode: String = "stats"  # "stats" or "tiers"

# Perk data for current stat
var _tier_data: Array[Dictionary] = []  # Array of perk info for selected stat

func _ready() -> void:
	# Get system references
	_stats = get_node_or_null(STATS_PATH)
	_perk = get_node_or_null(PERK_PATH)

	# Connect signals
	if _stat_list:
		_stat_list.item_selected.connect(_on_stat_selected)
	if _tier_list:
		_tier_list.item_selected.connect(_on_tier_selected)
	if _unlock_button:
		_unlock_button.pressed.connect(_on_unlock_pressed)

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
	if _stat_list and _stat_list.item_count > 0:
		_stat_list.select(0)
		_selected_stat = _stat_ids[0]
		_populate_tiers()
		call_deferred("_grab_stat_focus")

func _on_visibility_changed() -> void:
	"""Grab focus when panel becomes visible"""
	if visible:
		call_deferred("_grab_stat_focus")

func _grab_stat_focus() -> void:
	"""Helper to grab focus on stat list"""
	if _stat_list and _stat_list.item_count > 0:
		_focus_mode = "stats"
		_stat_list.grab_focus()

func _rebuild() -> void:
	"""Rebuild entire panel - refresh data and UI"""
	_load_data()
	_populate_stats()
	_populate_tiers()
	_update_details()

func _load_data() -> void:
	"""Load stat levels and perk points"""
	_stat_levels.clear()
	_stat_ids.clear()
	_perk_points = 0

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

	# Update points display
	if _points_value:
		_points_value.text = str(_perk_points)

func _populate_stats() -> void:
	"""Populate stat list"""
	if not _stat_list:
		return

	var prev_selection: int = -1
	var selected_items: Array = _stat_list.get_selected_items()
	if selected_items.size() > 0:
		prev_selection = selected_items[0]

	_stat_list.clear()

	for stat_id in _stat_ids:
		var level: int = _stat_levels.get(stat_id, 0)
		var display_name: String = _pretty_stat(stat_id)
		_stat_list.add_item("%s (Lv.%d)" % [display_name, level])

	# Restore or select first
	if prev_selection >= 0 and prev_selection < _stat_list.item_count:
		_stat_list.select(prev_selection)
		_selected_stat = _stat_ids[prev_selection]
	elif _stat_list.item_count > 0:
		_stat_list.select(0)
		_selected_stat = _stat_ids[0]

func _populate_tiers() -> void:
	"""Populate tier/perk list for selected stat"""
	if not _tier_list or _selected_stat == "":
		return

	_tier_list.clear()
	_tier_data.clear()

	# Update header
	if _tier_label:
		_tier_label.text = "Perks (%s)" % _pretty_stat(_selected_stat)

	var stat_level: int = _stat_levels.get(_selected_stat, 0)

	for tier_i in range(MAX_TIERS):
		var perk_info: Dictionary = _get_perk_info(_selected_stat, tier_i, stat_level)
		_tier_data.append(perk_info)

		var display: String = ""
		var color: Color = Color.WHITE

		# Format display text
		if perk_info["unlocked"]:
			display = "✔ T%d: %s [Unlocked]" % [tier_i + 1, perk_info["name"]]
			color = Color(0.6, 1.0, 0.6)  # Green
		elif perk_info["available"]:
			display = "T%d: %s [Available]" % [tier_i + 1, perk_info["name"]]
			color = Color(1.0, 1.0, 0.6)  # Yellow
		else:
			display = "T%d: %s [Locked]" % [tier_i + 1, perk_info["name"]]
			color = Color(0.7, 0.7, 0.7)  # Gray

		_tier_list.add_item(display)
		_tier_list.set_item_custom_fg_color(tier_i, color)

	# Select first tier if none selected
	if _tier_list.item_count > 0 and _selected_tier < 0:
		_tier_list.select(0)
		_selected_tier = 0

func _get_perk_info(stat_id: String, tier_index: int, stat_level: int) -> Dictionary:
	"""Get complete info about a perk"""
	var info: Dictionary = {
		"stat_id": stat_id,
		"tier": tier_index,
		"name": "Perk T%d" % (tier_index + 1),
		"description": "",
		"threshold": DEFAULT_THRESHOLDS[min(tier_index, DEFAULT_THRESHOLDS.size() - 1)],
		"unlocked": false,
		"available": false,
		"perk_id": ""
	}

	# Get threshold
	if _perk:
		if _perk.has_method("get_threshold"):
			info["threshold"] = int(_perk.call("get_threshold", stat_id, tier_index))
		elif _perk.has_method("get_thresholds"):
			var thresholds: Variant = _perk.call("get_thresholds", stat_id)
			if typeof(thresholds) == TYPE_ARRAY and tier_index < (thresholds as Array).size():
				info["threshold"] = int((thresholds as Array)[tier_index])

		# Get perk ID
		if _perk.has_method("get_perk_id"):
			info["perk_id"] = String(_perk.call("get_perk_id", stat_id, tier_index))

		# Get perk name
		if _perk.has_method("get_perk_name"):
			var name: String = String(_perk.call("get_perk_name", stat_id, tier_index))
			if name != "":
				info["name"] = name

		# Get perk description
		if _perk.has_method("get_perk_desc"):
			info["description"] = String(_perk.call("get_perk_desc", stat_id, tier_index))

		# Check if unlocked
		if _perk.has_method("is_unlocked"):
			info["unlocked"] = bool(_perk.call("is_unlocked", stat_id, tier_index))
		elif _perk.has_method("has_perk") and info["perk_id"] != "":
			info["unlocked"] = bool(_perk.call("has_perk", info["perk_id"]))

	# Check if available (meets stat requirement and not unlocked)
	var meets_requirement: bool = stat_level >= info["threshold"]
	info["available"] = meets_requirement and not info["unlocked"] and _perk_points > 0

	return info

func _update_details() -> void:
	"""Update perk details panel"""
	if _selected_tier < 0 or _selected_tier >= _tier_data.size():
		_clear_details()
		return

	var perk: Dictionary = _tier_data[_selected_tier]

	# Update name
	if _perk_name:
		_perk_name.text = perk["name"]

	# Build details text
	var details: String = ""

	# Tier
	details += "Tier: %d\n\n" % (perk["tier"] + 1)

	# Description
	if perk["description"] != "":
		details += "%s\n\n" % perk["description"]

	# Requirements
	var stat_level: int = _stat_levels.get(perk["stat_id"], 0)
	var threshold: int = perk["threshold"]
	details += "Requires: %s ≥ %d\n" % [_pretty_stat(perk["stat_id"]), threshold]
	details += "Current: %s = %d\n\n" % [_pretty_stat(perk["stat_id"]), stat_level]

	# Status
	if perk["unlocked"]:
		details += "Status: ✔ Unlocked\n"
	elif perk["available"]:
		details += "Status: Available to unlock!\n"
		details += "Cost: 1 Perk Point\n"
		details += "Points available: %d\n" % _perk_points
	else:
		if stat_level < threshold:
			details += "Status: Locked (need %d more %s)\n" % [threshold - stat_level, _pretty_stat(perk["stat_id"])]
		elif _perk_points <= 0:
			details += "Status: Need perk points\n"
		else:
			details += "Status: Locked\n"

	if _details_text:
		_details_text.text = details

	# Update unlock button
	if _unlock_button:
		_unlock_button.visible = perk["available"]
		_unlock_button.disabled = not perk["available"]

func _clear_details() -> void:
	"""Clear details panel"""
	if _perk_name:
		_perk_name.text = "(Select a perk)"
	if _details_text:
		_details_text.text = ""
	if _unlock_button:
		_unlock_button.visible = false

func _on_stat_selected(index: int) -> void:
	"""Handle stat selection"""
	if index < 0 or index >= _stat_ids.size():
		return

	_selected_stat = _stat_ids[index]
	_selected_tier = -1  # Reset tier selection
	_populate_tiers()
	_update_details()

func _on_tier_selected(index: int) -> void:
	"""Handle tier selection"""
	if index < 0 or index >= _tier_data.size():
		return

	_selected_tier = index
	_update_details()

func _on_unlock_pressed() -> void:
	"""Handle unlock button press"""
	if _selected_tier < 0 or _selected_tier >= _tier_data.size():
		return

	var perk: Dictionary = _tier_data[_selected_tier]
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
		# No perk system, treat as success
		unlocked = true

	# Refund if failed
	if not unlocked:
		print("[PerksPanel] Unlock failed, refunding point")
		if _stats and _stats.has_method("add_perk_points"):
			_stats.call("add_perk_points", 1)

	# Rebuild UI
	_rebuild()

func _unhandled_input(event: InputEvent) -> void:
	"""Handle controller input"""
	if not visible:
		return

	# Handle focus switching
	if _focus_mode == "stats":
		if event.is_action_pressed("menu_accept") or event.is_action_pressed("ui_right"):
			# Move to tier list if available
			if _tier_list and _tier_list.item_count > 0:
				_focus_mode = "tiers"
				_tier_list.grab_focus()
				get_viewport().set_input_as_handled()
	elif _focus_mode == "tiers":
		if event.is_action_pressed("menu_back") or event.is_action_pressed("ui_left"):
			# Return to stat list
			_focus_mode = "stats"
			_stat_list.grab_focus()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("menu_accept"):
			# Try to unlock selected perk
			if _selected_tier >= 0 and _selected_tier < _tier_data.size():
				var perk: Dictionary = _tier_data[_selected_tier]
				if perk["available"]:
					_unlock_perk(perk)
					get_viewport().set_input_as_handled()

# ==============================================================================
# Helper Functions
# ==============================================================================

func _pretty_stat(stat_id: String) -> String:
	"""Get display name for a stat"""
	if _stats and _stats.has_method("get_stat_display_name"):
		var name: Variant = _stats.call("get_stat_display_name", stat_id)
		if typeof(name) == TYPE_STRING and String(name) != "":
			return String(name)

	# Fallback formatting
	var formatted: String = stat_id.replace("_", " ").strip_edges()
	if formatted.length() == 0:
		return "Stat"
	return formatted.substr(0, 1).to_upper() + formatted.substr(1)
