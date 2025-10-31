extends Control
class_name StatsPanel

## StatsPanel - Comprehensive Character Stats Display
## Shows base stats, equipment stats, and derived combat stats for party members

const STATS_AUTOLOAD_PATH : String = "/root/aStatsSystem"
const GS_PATH             : String = "/root/aGameState"
const EQ_PATH             : String = "/root/aEquipmentSystem"
const INV_PATH            : String = "/root/aInventorySystem"

# Base stat keys
const BASE_STATS: Array[String] = ["BRW", "MND", "TPO", "VTL", "FCS"]

@onready var _party_list: ItemList = %PartyList
@onready var _member_name: Label = %MemberName
@onready var _base_grid: GridContainer = %BaseStatsGrid
@onready var _equip_grid: GridContainer = %EquipmentGrid
@onready var _derived_grid: GridContainer = %DerivedGrid
@onready var _radar_container: VBoxContainer = %RadarContainer

var _stats: Node = null
var _gs: Node = null
var _eq: Node = null
var _inv: Node = null

# Radar chart for stat visualization
var _radar_chart: Control = null

# Party data
var _party_tokens: Array[String] = []
var _party_labels: Array[String] = []

func _ready() -> void:
	_stats = get_node_or_null(STATS_AUTOLOAD_PATH)
	_gs = get_node_or_null(GS_PATH)
	_eq = get_node_or_null(EQ_PATH)
	_inv = get_node_or_null(INV_PATH)

	# Connect signals
	if _stats:
		if _stats.has_signal("stats_changed"):
			_stats.connect("stats_changed", Callable(self, "_on_stats_changed"))
		if _stats.has_signal("level_up"):
			_stats.connect("level_up", Callable(self, "_on_stats_changed"))

	if _gs:
		for sig in ["party_changed", "active_changed", "roster_changed"]:
			if _gs.has_signal(sig):
				_gs.connect(sig, Callable(self, "_on_party_changed"))

	if _eq and _eq.has_signal("equipment_changed"):
		_eq.connect("equipment_changed", Callable(self, "_on_equipment_changed"))

	# Connect party list signals
	if _party_list:
		_party_list.item_selected.connect(_on_party_member_selected)

	# Connect visibility change
	visibility_changed.connect(_on_visibility_changed)

	# Create radar chart
	_create_radar_chart()

	call_deferred("_first_fill")

func _first_fill() -> void:
	_refresh_party()
	if _party_list.item_count > 0:
		_party_list.select(0)
		_party_list.grab_focus()
		_on_party_member_selected(0)

func _on_visibility_changed() -> void:
	"""Grab focus when panel becomes visible"""
	if visible and _party_list and _party_list.item_count > 0:
		_party_list.grab_focus()

func _on_party_changed(_arg = null) -> void:
	var current_selection = -1
	if _party_list.get_selected_items().size() > 0:
		current_selection = _party_list.get_selected_items()[0]

	_refresh_party()

	# Restore selection
	if current_selection >= 0 and current_selection < _party_list.item_count:
		_party_list.select(current_selection)
		_on_party_member_selected(current_selection)
	elif _party_list.item_count > 0:
		_party_list.select(0)
		_on_party_member_selected(0)

func _on_stats_changed(_arg1 = null, _arg2 = null) -> void:
	# Refresh current member stats
	var selected = _party_list.get_selected_items()
	if selected.size() > 0:
		_on_party_member_selected(selected[0])

func _on_equipment_changed(member: String) -> void:
	# Refresh if it's the currently viewed member
	var selected = _party_list.get_selected_items()
	if selected.size() > 0:
		var idx = selected[0]
		if idx >= 0 and idx < _party_tokens.size():
			if _party_tokens[idx].to_lower() == member.to_lower():
				_on_party_member_selected(idx)

func _refresh_party() -> void:
	"""Rebuild party member list"""
	_party_list.clear()
	_party_tokens.clear()
	_party_labels.clear()

	var tokens: Array[String] = _gather_party_tokens()

	if tokens.is_empty():
		tokens.append("hero")

	for token in tokens:
		var display_name = _get_display_name(token)
		_party_list.add_item(display_name)
		_party_tokens.append(token)
		_party_labels.append(display_name)

func _gather_party_tokens() -> Array[String]:
	"""Get all party member tokens"""
	var out: Array[String] = []
	if _gs == null:
		return out

	# Active party
	for m in ["get_active_party_ids", "get_party_ids", "list_active_party"]:
		if _gs.has_method(m):
			var raw: Variant = _gs.call(m)
			if typeof(raw) == TYPE_PACKED_STRING_ARRAY:
				for s in (raw as PackedStringArray):
					out.append(String(s))
			elif typeof(raw) == TYPE_ARRAY:
				for s in (raw as Array):
					out.append(String(s))
			if out.size() > 0:
				break

	# Bench
	if _gs.has_method("get"):
		var bench_v: Variant = _gs.get("bench")
		if typeof(bench_v) == TYPE_PACKED_STRING_ARRAY:
			for s in (bench_v as PackedStringArray):
				if not out.has(String(s)):
					out.append(String(s))
		elif typeof(bench_v) == TYPE_ARRAY:
			for s in (bench_v as Array):
				if not out.has(String(s)):
					out.append(String(s))

	return out

func _get_display_name(token: String) -> String:
	"""Get display name for a party member"""
	if token == "hero":
		if _gs and _gs.has_method("get"):
			var name = String(_gs.get("player_name"))
			if name.strip_edges() != "":
				return name
		return "Player"

	if _gs and _gs.has_method("_display_name_for_id"):
		var v: Variant = _gs.call("_display_name_for_id", token)
		if typeof(v) == TYPE_STRING and String(v) != "":
			return String(v)

	return token.capitalize()

func _on_party_member_selected(index: int) -> void:
	"""Handle party member selection"""
	if index < 0 or index >= _party_tokens.size():
		return

	var token: String = _party_tokens[index]
	var display_name: String = _party_labels[index]

	_member_name.text = display_name

	# Rebuild all stat grids
	_rebuild_base_stats(token)
	_rebuild_equipment_stats(token)
	_rebuild_derived_stats(token)
	_update_radar_chart(token)

func _rebuild_base_stats(token: String) -> void:
	"""Build the base stats grid (BRW, MND, TPO, VTL, FCS, Level, XP)"""
	_clear_grid(_base_grid)

	var level = 1
	var xp = 0
	var to_next = 0

	if _stats:
		if _stats.has_method("get_member_level"):
			level = int(_stats.call("get_member_level", token))
		if _stats.has_method("get_xp"):
			xp = int(_stats.call("get_xp", token))
		if _stats.has_method("xp_to_next_level"):
			to_next = int(_stats.call("xp_to_next_level", token))

	_add_stat_pair(_base_grid, "Level", str(level))

	if to_next > 0:
		_add_stat_pair(_base_grid, "XP", "%d / %d" % [xp, to_next])
	else:
		_add_stat_pair(_base_grid, "XP", str(xp))

	# Base stats
	for stat_key in BASE_STATS:
		var value = _get_stat_value(token, stat_key)
		_add_stat_pair(_base_grid, stat_key, str(value))

func _rebuild_equipment_stats(token: String) -> void:
	"""Build equipment stats grid (weapon/armor/head/foot/bracelet stats)"""
	_clear_grid(_equip_grid)

	var equip = _get_equipment(token)

	# Weapon stats
	var weapon_id = String(equip.get("weapon", ""))
	if weapon_id != "" and weapon_id != "—":
		var w_def = _get_item_def(weapon_id)
		var brw = _get_stat_value(token, "BRW")
		var base_watk = int(w_def.get("base_watk", 0))
		var scale = float(w_def.get("scale_brw", 0.0))
		var total_atk = base_watk + int(round(scale * float(brw)))

		_add_stat_pair(_equip_grid, "W.Attack", str(total_atk))
		_add_stat_pair(_equip_grid, "W.Acc", str(w_def.get("base_acc", 0)))
		_add_stat_pair(_equip_grid, "Crit %", str(w_def.get("crit_bonus_pct", 0)))

	# Armor stats
	var armor_id = String(equip.get("armor", ""))
	if armor_id != "" and armor_id != "—":
		var a_def = _get_item_def(armor_id)
		var vtl = _get_stat_value(token, "VTL")
		var armor_flat = int(a_def.get("armor_flat", 0))
		var pdef = int(round(float(armor_flat) * (5.0 + 0.25 * float(vtl))))

		_add_stat_pair(_equip_grid, "P.Def", str(pdef))
		_add_stat_pair(_equip_grid, "Ail.Res %", str(a_def.get("ail_resist_pct", 0)))

	# Head stats
	var head_id = String(equip.get("head", ""))
	if head_id != "" and head_id != "—":
		var h_def = _get_item_def(head_id)
		var fcs = _get_stat_value(token, "FCS")
		var ward = int(h_def.get("ward_flat", 0))
		var mdef = int(round(float(ward) * (5.0 + 0.25 * float(fcs))))

		_add_stat_pair(_equip_grid, "M.Def", str(mdef))
		if int(h_def.get("max_hp_boost", 0)) > 0:
			_add_stat_pair(_equip_grid, "HP Bonus", str(h_def.get("max_hp_boost", 0)))
		if int(h_def.get("max_mp_boost", 0)) > 0:
			_add_stat_pair(_equip_grid, "MP Bonus", str(h_def.get("max_mp_boost", 0)))

	# Foot stats
	var foot_id = String(equip.get("foot", ""))
	if foot_id != "" and foot_id != "—":
		var f_def = _get_item_def(foot_id)
		_add_stat_pair(_equip_grid, "Speed", str(f_def.get("speed", 0)))
		_add_stat_pair(_equip_grid, "Evasion", str(f_def.get("base_eva", 0)))

func _rebuild_derived_stats(token: String) -> void:
	"""Build derived stats grid (HP, MP, pools)"""
	_clear_grid(_derived_grid)

	var hp_max = 0
	var mp_max = 0
	var hp_current = 0
	var mp_current = 0

	if _gs and _gs.has_method("compute_member_pools"):
		var pools = _gs.call("compute_member_pools", token)
		hp_max = int(pools.get("hp_max", 0))
		mp_max = int(pools.get("mp_max", 0))

	# Try to get current HP/MP from combat profiles
	var cps = get_node_or_null("/root/aCombatProfileSystem")
	if cps and cps.has_method("get_profile"):
		var profile = cps.call("get_profile", token)
		if typeof(profile) == TYPE_DICTIONARY:
			hp_current = int(profile.get("hp", hp_max))
			mp_current = int(profile.get("mp", mp_max))
	else:
		hp_current = hp_max
		mp_current = mp_max

	_add_stat_pair(_derived_grid, "HP", "%d / %d" % [hp_current, hp_max])
	_add_stat_pair(_derived_grid, "MP", "%d / %d" % [mp_current, mp_max])

func _get_equipment(token: String) -> Dictionary:
	"""Get equipped items for a member"""
	if _gs and _gs.has_method("get_member_equip"):
		var equip_v = _gs.call("get_member_equip", token)
		if typeof(equip_v) == TYPE_DICTIONARY:
			return equip_v
	return {}

func _get_item_def(item_id: String) -> Dictionary:
	"""Get item definition"""
	if item_id == "" or item_id == "—":
		return {}

	if _eq and _eq.has_method("get_item_def"):
		var def_v = _eq.call("get_item_def", item_id)
		if typeof(def_v) == TYPE_DICTIONARY:
			return def_v

	if _inv and _inv.has_method("get_item_defs"):
		var defs_v = _inv.call("get_item_defs")
		if typeof(defs_v) == TYPE_DICTIONARY:
			var defs: Dictionary = defs_v
			return defs.get(item_id, {})

	return {}

func _get_stat_value(token: String, stat_key: String) -> int:
	"""Get a stat value for a member"""
	if _gs and _gs.has_method("get_member_stat"):
		return int(_gs.call("get_member_stat", token, stat_key))
	return 1

func _add_stat_pair(grid: GridContainer, label: String, value: String) -> void:
	"""Add a label/value pair to a grid"""
	var lbl = Label.new()
	lbl.text = label + ":"
	grid.add_child(lbl)

	var val = Label.new()
	val.text = value
	grid.add_child(val)

func _clear_grid(grid: GridContainer) -> void:
	"""Clear all children from a grid"""
	for child in grid.get_children():
		child.queue_free()

func _create_radar_chart() -> void:
	"""Create radar chart for stat visualization"""
	# Placeholder - you can add your radar chart implementation here
	var placeholder = Label.new()
	placeholder.text = "[Radar Chart]"
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_radar_container.add_child(placeholder)
	_radar_chart = placeholder

func _update_radar_chart(token: String) -> void:
	"""Update radar chart with current member stats"""
	# Placeholder - implement radar chart update logic
	pass

func _unhandled_input(event: InputEvent) -> void:
	"""Handle controller input - ItemList handles UP/DOWN automatically"""
	if not visible or not _party_list:
		return

	# A button to confirm selection (though selection already updates display)
	if event.is_action_pressed("menu_accept"):
		var selected = _party_list.get_selected_items()
		if selected.size() > 0:
			_on_party_member_selected(selected[0])
			get_viewport().set_input_as_handled()
