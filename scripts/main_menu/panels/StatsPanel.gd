extends Control
class_name StatsPanel

## StatsPanel - Comprehensive Character Stats Display
## Shows base stats, equipment stats, and derived combat stats for party members

const STATS_AUTOLOAD_PATH : String = "/root/aStatsSystem"
const GS_PATH             : String = "/root/aGameState"
const EQ_PATH             : String = "/root/aEquipmentSystem"
const INV_PATH            : String = "/root/aInventorySystem"
const CPS_PATH            : String = "/root/aCombatProfileSystem"
const SIG_PATH            : String = "/root/aSigilSystem"
const AFF_PATH            : String = "/root/aAffinitySystem"

# Base stat keys
const BASE_STATS: Array[String] = ["BRW", "MND", "TPO", "VTL", "FCS"]

# Party member tokens for affinity display
const PARTY_MEMBERS: Array[String] = ["hero", "tessa", "kai", "skye", "rise", "matcha", "douglas", "sev"]

@onready var _party_list: ItemList = %PartyList
@onready var _member_name: Label = %MemberName
@onready var _base_grid: GridContainer = %BaseStatsGrid
@onready var _battle_grid: GridContainer = %BattleStatsGrid
@onready var _affinity_grid: GridContainer = %AffinityGrid
@onready var _radar_container: VBoxContainer = %RadarContainer

# Panel containers for styling
@onready var _party_panel: PanelContainer = get_node("Root/PartyPanel") if has_node("Root/PartyPanel") else null
@onready var _stats_panel: PanelContainer = get_node("Root/StatsPanel") if has_node("Root/StatsPanel") else null
@onready var _visual_panel: PanelContainer = get_node("Root/VisualPanel") if has_node("Root/VisualPanel") else null

var _stats: Node = null
var _gs: Node = null
var _eq: Node = null
var _inv: Node = null
var _cps: Node = null
var _sig: Node = null
var _aff: Node = null

# Radar chart for stat visualization
var _radar_chart: Control = null

# Party data
var _party_tokens: Array[String] = []
var _party_labels: Array[String] = []

func _ready() -> void:
	# Set process mode to work while game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	_stats = get_node_or_null(STATS_AUTOLOAD_PATH)
	_gs = get_node_or_null(GS_PATH)
	_eq = get_node_or_null(EQ_PATH)
	_inv = get_node_or_null(INV_PATH)
	_cps = get_node_or_null(CPS_PATH)
	_sig = get_node_or_null(SIG_PATH)
	_aff = get_node_or_null(AFF_PATH)

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
	_apply_core_vibe_styling()
	_refresh_party()
	if _party_list.item_count > 0:
		_party_list.select(0)
		_party_list.grab_focus()
		_on_party_member_selected(0)

func _apply_core_vibe_styling() -> void:
	"""Apply Core Vibe neon-kawaii styling to StatsPanel elements"""

	# Style the three main panel containers with rounded neon borders
	if _party_panel:
		var party_style = aCoreVibeTheme.create_panel_style(
			aCoreVibeTheme.COLOR_SKY_CYAN,            # Sky Cyan border (party)
			aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
			aCoreVibeTheme.PANEL_OPACITY_SEMI,        # Semi-transparent
			aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
			aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
			aCoreVibeTheme.SHADOW_SIZE_MEDIUM         # 6px glow
		)
		party_style.content_margin_left = 10
		party_style.content_margin_top = 10
		party_style.content_margin_right = 10
		party_style.content_margin_bottom = 10
		_party_panel.add_theme_stylebox_override("panel", party_style)

	if _stats_panel:
		var stats_style = aCoreVibeTheme.create_panel_style(
			aCoreVibeTheme.COLOR_ELECTRIC_LIME,       # Electric Lime border (stats)
			aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
			aCoreVibeTheme.PANEL_OPACITY_SEMI,        # Semi-transparent
			aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
			aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
			aCoreVibeTheme.SHADOW_SIZE_MEDIUM         # 6px glow
		)
		stats_style.content_margin_left = 10
		stats_style.content_margin_top = 10
		stats_style.content_margin_right = 10
		stats_style.content_margin_bottom = 10
		_stats_panel.add_theme_stylebox_override("panel", stats_style)

	if _visual_panel:
		var visual_style = aCoreVibeTheme.create_panel_style(
			aCoreVibeTheme.COLOR_GRAPE_VIOLET,        # Grape Violet border (visual/radar)
			aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
			aCoreVibeTheme.PANEL_OPACITY_SEMI,        # Semi-transparent
			aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
			aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
			aCoreVibeTheme.SHADOW_SIZE_MEDIUM         # 6px glow
		)
		visual_style.content_margin_left = 10
		visual_style.content_margin_top = 10
		visual_style.content_margin_right = 10
		visual_style.content_margin_bottom = 10
		_visual_panel.add_theme_stylebox_override("panel", visual_style)

	# Note: Battle stat cells and affinity cells are dynamically created,
	# so their styling is applied in their creation functions.
	# RadarChart colors are updated in the RadarChart class itself.

func _on_visibility_changed() -> void:
	"""Grab focus when panel becomes visible"""
	if visible and _party_list:
		# Defer to ensure ItemList is ready
		call_deferred("_grab_party_list_focus")

func _grab_party_list_focus() -> void:
	"""Helper to grab focus on party list"""
	if _party_list and _party_list.item_count > 0:
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
	_rebuild_battle_stats(token)
	_rebuild_affinity_grid(token)
	_update_radar_chart(token)

func _rebuild_base_stats(token: String) -> void:
	"""Build the base stats grid (Name, Mind Type, Level, XP)"""
	_clear_grid(_base_grid)

	# Get display name
	var display_name: String = _get_display_name(token)
	_add_stat_pair(_base_grid, "Name", display_name)

	# Get mind type
	var mind_type: String = _get_member_mind_type(token)
	_add_stat_pair(_base_grid, "Mind Type", mind_type)

	# Get level and XP
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
		_add_stat_pair(_base_grid, "LXP", "%d / %d" % [xp, to_next])
	else:
		_add_stat_pair(_base_grid, "LXP", str(xp))

	# Base stats are not displayed in the grid, only in the radar chart

func _rebuild_battle_stats(token: String) -> void:
	"""Build battle stats grid from CombatProfileSystem"""
	_clear_grid(_battle_grid)

	if not _cps:
		print("[StatsPanel] CombatProfileSystem not available")
		return

	# Get combat profile
	var profile: Dictionary = {}
	if _cps.has_method("get_profile"):
		var profile_v = _cps.call("get_profile", token)
		if typeof(profile_v) == TYPE_DICTIONARY:
			profile = profile_v

	# Display all battle stats in 2 columns - each cell has "LABEL: VALUE"
	# Note: CombatProfileSystem stores stats in nested dictionaries
	var weapon: Dictionary = profile.get("weapon", {})
	var defense: Dictionary = profile.get("defense", {})
	var stats: Dictionary = profile.get("stats", {})

	# Get core stats for calculations
	var brw: int = stats.get("BRW", 1)
	var mnd: int = stats.get("MND", 1)
	var tpo: int = stats.get("TPO", 1)
	var vtl: int = stats.get("VTL", 1)
	var fcs: int = stats.get("FCS", 1)

	# Calculate derived stats with new formulas
	var skill_boost: int = weapon.get("skill_acc_boost", 0)
	var s_atk: int = mnd + skill_boost

	# Accuracy: Base + TPO×2.0 (each TPO point adds 0.20 percentage points)
	var weapon_acc: int = weapon.get("accuracy", 0)
	var tpo_acc_bonus: float = tpo * 2.0
	var total_acc: float = weapon_acc + tpo_acc_bonus

	# Crit Rate: 5% + BRW×0.5% + weapon/equipment bonuses
	var weapon_crit: int = weapon.get("crit_bonus_pct", 0)
	var crit_rate: float = 5.0 + (brw * 0.5) + weapon_crit
	crit_rate = clamp(crit_rate, 5.0, 50.0)

	# Ailment Power: MND×2%
	var ailment_bonus: float = mnd * 2.0

	# Evasion with stat contribution (VTL×2.0)
	var base_eva: int = defense.get("peva", 0)
	var vtl_eva_bonus: float = vtl * 2.0
	var total_eva: float = base_eva + vtl_eva_bonus

	# Initiative: Get TPO tier and speed bonus
	var speed_bonus: int = defense.get("speed", 0)
	var init_tier: int = _get_initiative_tier(tpo)
	var init_text: String = "%s + %d" % [_get_dice_notation(init_tier), speed_bonus]

	# Display stats in order: HP/MP/PATK/SATK/PDEF/SDEF/ACC/INIT/CRIT BOOST/AIL BOOST
	_add_battle_stat(_battle_grid, "Max HP", profile.get("hp_max", 0))
	_add_battle_stat(_battle_grid, "Max MP", profile.get("mp_max", 0))
	_add_battle_stat(_battle_grid, "Physical Attack", weapon.get("attack", 0))
	_add_battle_stat(_battle_grid, "Skill Attack", s_atk)
	_add_battle_stat(_battle_grid, "Physical Defense", defense.get("pdef", 0))
	_add_battle_stat(_battle_grid, "Skill Defense", defense.get("mdef", 0))
	_add_battle_stat_float(_battle_grid, "Accuracy", total_acc, "%.1f%%")
	_add_battle_stat_string(_battle_grid, "Initiative", init_text)
	_add_battle_stat_float(_battle_grid, "Crit Boost", crit_rate, "+%.1f%%")
	_add_battle_stat_float(_battle_grid, "Ailment Boost", ailment_bonus, "+%.0f%%")

func _rebuild_affinity_grid(token: String) -> void:
	"""Build affinity grid showing relationships with all party members"""
	_clear_grid(_affinity_grid)

	# Get list of recruited party members
	var recruited_members: Array[String] = _gather_party_tokens()

	# Only show affinity for recruited members (excluding current member)
	for member_token in recruited_members:
		# Skip if this is the current member
		if member_token.to_lower() == token.to_lower():
			continue

		# Get affinity value
		var affinity: int = _get_affinity(token, member_token)
		var tier_text: String = _get_affinity_tier_text(affinity)
		var member_name: String = _get_display_name(member_token)

		var cell = _create_affinity_cell(member_name, tier_text)
		_affinity_grid.add_child(cell)

func _get_affinity(member1: String, member2: String) -> int:
	"""Get affinity value between two members"""
	if not _aff:
		return 0

	if _aff.has_method("get_affinity"):
		var v = _aff.call("get_affinity", member1, member2)
		if typeof(v) == TYPE_INT:
			return int(v)

	return 0

func _get_affinity_tier_text(affinity: int) -> String:
	"""Convert affinity value to tier text"""
	if affinity >= 120:
		return "AT3"
	elif affinity >= 60:
		return "AT2"
	elif affinity >= 20:
		return "AT1"
	else:
		return "AT0"

func _create_affinity_cell(member_name: String, tier: String) -> PanelContainer:
	"""Create a rounded Core Vibe cell for affinity display"""
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 30)

	# Core Vibe: Sky Cyan border with Ink Charcoal background (relationships)
	var style = aCoreVibeTheme.create_panel_style(
		aCoreVibeTheme.COLOR_SKY_CYAN,            # Sky Cyan border (relationship)
		aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
		aCoreVibeTheme.PANEL_OPACITY_FULL,        # Fully opaque
		aCoreVibeTheme.CORNER_RADIUS_SMALL,       # 12px corners
		aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
		aCoreVibeTheme.SHADOW_SIZE_SMALL          # 4px glow
	)
	panel.add_theme_stylebox_override("panel", style)

	# Add margin for padding inside cell
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)

	# HBoxContainer to hold label and value side by side
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	margin.add_child(hbox)

	# Member name label - 25 characters wide
	var label := Label.new()
	label.text = member_name
	label.custom_minimum_size = Vector2(150, 0)  # ~25 characters at 12pt
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.add_theme_font_size_override("font_size", 12)
	# Core Vibe: Milk White label color
	label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hbox.add_child(label)

	# Tier value - 5 characters wide
	var value_label := Label.new()
	value_label.text = tier
	value_label.custom_minimum_size = Vector2(30, 0)  # ~5 characters at 12pt
	value_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	value_label.add_theme_font_size_override("font_size", 12)
	# Core Vibe: Bubble Magenta for affinity tier (relationship strength)
	value_label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_BUBBLE_MAGENTA)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(value_label)

	return panel

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

func _get_member_mind_type(member_token: String) -> String:
	"""Get the mind type for a party member"""
	if _sig and _sig.has_method("resolve_member_mind_base"):
		var v: Variant = _sig.call("resolve_member_mind_base", member_token)
		if typeof(v) == TYPE_STRING and String(v).strip_edges() != "":
			return String(v)
	if _gs and _gs.has_method("get_member_field"):
		var v2: Variant = _gs.call("get_member_field", member_token, "mind_type")
		if typeof(v2) == TYPE_STRING and String(v2).strip_edges() != "":
			return String(v2)
	return "Omega"

func _add_stat_pair(grid: GridContainer, label: String, value: String) -> void:
	"""Add a label/value pair to a grid with Core Vibe styling"""
	var lbl = Label.new()
	lbl.text = label + ":"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Core Vibe: Sky Cyan label color
	lbl.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_SKY_CYAN)
	lbl.add_theme_font_size_override("font_size", 14)
	grid.add_child(lbl)

	var val = Label.new()
	val.text = value
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Core Vibe: Electric Lime value color
	val.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_ELECTRIC_LIME)
	val.add_theme_font_size_override("font_size", 14)
	grid.add_child(val)

func _add_battle_stat(grid: GridContainer, label: String, value: int) -> void:
	"""Add a battle stat as a rounded grey cell (matches LoadoutPanel style)"""
	var cell = _create_stat_cell(label, str(value))
	grid.add_child(cell)

func _add_battle_stat_float(grid: GridContainer, label: String, value: float, format: String = "%.1f") -> void:
	"""Add a battle stat with float value and custom formatting"""
	var formatted_value: String = format % value
	var cell = _create_stat_cell(label, formatted_value)
	grid.add_child(cell)

func _add_battle_stat_string(grid: GridContainer, label: String, value: String) -> void:
	"""Add a battle stat with string value"""
	var cell = _create_stat_cell(label, value)
	grid.add_child(cell)

func _get_initiative_tier(tpo: int) -> int:
	"""Get initiative tier based on TPO value (1-4)"""
	if tpo <= 3:
		return 1
	elif tpo <= 6:
		return 2
	elif tpo <= 9:
		return 3
	else:
		return 4

func _get_dice_notation(tier: int) -> String:
	"""Get dice notation for initiative tier"""
	match tier:
		1: return "1D20"
		2: return "2D20"
		3: return "3D20"
		4: return "4D20"
		_: return "1D20"

func _create_stat_cell(stat_label: String, value: String) -> PanelContainer:
	"""Create a rounded Core Vibe cell containing a stat label and value"""
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 30)

	# Core Vibe: Plasma Teal border with Ink Charcoal background
	var style = aCoreVibeTheme.create_panel_style(
		aCoreVibeTheme.COLOR_PLASMA_TEAL,         # Plasma Teal border (stat display)
		aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
		aCoreVibeTheme.PANEL_OPACITY_FULL,        # Fully opaque
		aCoreVibeTheme.CORNER_RADIUS_SMALL,       # 12px corners
		aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
		aCoreVibeTheme.SHADOW_SIZE_SMALL          # 4px glow
	)
	panel.add_theme_stylebox_override("panel", style)

	# Add margin for padding inside cell
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)

	# HBoxContainer to hold label and value side by side
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	margin.add_child(hbox)

	# Label - 25 characters wide
	var label := Label.new()
	label.text = stat_label
	label.custom_minimum_size = Vector2(150, 0)  # ~25 characters at 12pt
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	label.add_theme_font_size_override("font_size", 12)
	# Core Vibe: Milk White label color
	label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hbox.add_child(label)

	# Value - 5 characters wide
	var value_label := Label.new()
	value_label.text = value
	value_label.custom_minimum_size = Vector2(30, 0)  # ~5 characters at 12pt
	value_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	value_label.add_theme_font_size_override("font_size", 12)
	# Core Vibe: Electric Lime value color
	value_label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_ELECTRIC_LIME)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(value_label)

	return panel

func _clear_grid(grid: GridContainer) -> void:
	"""Clear all children from a grid"""
	for child in grid.get_children():
		child.queue_free()

func _create_radar_chart() -> void:
	"""Create radar chart for stat visualization"""
	var chart = RadarChart.new()
	chart.custom_minimum_size = Vector2(280, 280)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_radar_container.add_child(chart)
	_radar_chart = chart

func _update_radar_chart(token: String) -> void:
	"""Update radar chart with current member stats"""
	if not _radar_chart or not _radar_chart.has_method("set_stats"):
		return

	var stat_values: Array[float] = []
	for stat_key in BASE_STATS:
		stat_values.append(float(_get_stat_value(token, stat_key)))

	_radar_chart.call("set_stats", BASE_STATS, stat_values)

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

# ==============================================================================
# RadarChart - Custom Control for Radar/Spider Graph Visualization
# ==============================================================================

class RadarChart extends Control:
	"""Draws a radar/spider chart for visualizing multiple stat values"""

	var _stat_labels: Array[String] = []
	var _stat_values: Array[float] = []  # Actual values for labels
	var _stat_values_capped: Array[float] = []  # Capped values for visual display
	var _max_value: float = 100.0

	# Core Vibe: Neon-kawaii radar chart colors
	var grid_color: Color = aCoreVibeTheme.COLOR_MILK_WHITE  # White grid lines
	var stat_color: Color = Color(aCoreVibeTheme.COLOR_ELECTRIC_LIME.r, aCoreVibeTheme.COLOR_ELECTRIC_LIME.g, aCoreVibeTheme.COLOR_ELECTRIC_LIME.b, 0.3)  # Electric Lime fill
	var stat_border_color: Color = aCoreVibeTheme.COLOR_ELECTRIC_LIME  # Electric Lime border
	var label_color: Color = aCoreVibeTheme.COLOR_MILK_WHITE  # Milk White labels

	func set_stats(labels: Array[String], values: Array[float]) -> void:
		"""Set the stat labels and values to display"""
		_stat_labels = labels.duplicate()
		_stat_values = values.duplicate()  # Keep original values for labels

		# Create capped version for visual display
		_stat_values_capped = []
		for val in values:
			_stat_values_capped.append(min(val, 10.0))

		# Set max value to 10 for consistent scaling
		_max_value = 10.0

		queue_redraw()

	func _draw() -> void:
		if _stat_labels.size() == 0 or _stat_values.size() == 0:
			return

		var center: Vector2 = size / 2.0
		var radius: float = min(size.x, size.y) * 0.35
		var num_stats: int = _stat_labels.size()

		if num_stats == 0:
			return

		# Draw grid (background pentagon/polygon with rings)
		_draw_grid(center, radius, num_stats)

		# Draw stat polygon
		_draw_stat_polygon(center, radius, num_stats)

		# Draw labels
		_draw_labels(center, radius * 1.15, num_stats)

	func _draw_grid(center: Vector2, radius: float, num_stats: int) -> void:
		"""Draw the background grid lines"""
		var angle_step: float = TAU / float(num_stats)

		# Draw concentric rings (25%, 50%, 75%, 100%)
		for ring in [0.25, 0.5, 0.75, 1.0]:
			var points: PackedVector2Array = []
			for i in range(num_stats):
				var angle: float = -PI / 2.0 + angle_step * i
				var point: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius * ring
				points.append(point)
			points.append(points[0])  # Close the polygon
			draw_polyline(points, grid_color, 1.0)

		# Draw lines from center to each vertex
		for i in range(num_stats):
			var angle: float = -PI / 2.0 + angle_step * i
			var point: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
			draw_line(center, point, grid_color, 1.0)

	func _draw_stat_polygon(center: Vector2, radius: float, num_stats: int) -> void:
		"""Draw the stat value polygon (using capped values for visual display)"""
		if _stat_values_capped.size() != num_stats:
			return

		var angle_step: float = TAU / float(num_stats)
		var points: PackedVector2Array = []

		for i in range(num_stats):
			var angle: float = -PI / 2.0 + angle_step * i
			var value_ratio: float = clamp(_stat_values_capped[i] / _max_value, 0.0, 1.0)
			var point: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius * value_ratio
			points.append(point)

		if points.size() >= 3:
			# Draw filled polygon
			draw_colored_polygon(points, stat_color)

			# Draw border
			points.append(points[0])  # Close the polygon
			draw_polyline(points, stat_border_color, 2.0)

	func _draw_labels(center: Vector2, radius: float, num_stats: int) -> void:
		"""Draw stat labels around the chart"""
		if _stat_labels.size() != num_stats:
			return

		var angle_step: float = TAU / float(num_stats)
		var font: Font = get_theme_default_font()
		var font_size: int = 14

		for i in range(num_stats):
			var angle: float = -PI / 2.0 + angle_step * i
			var label_pos: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
			var label: String = "%s: %d" % [_stat_labels[i], int(_stat_values[i])]

			# Get text size for centering
			var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			label_pos -= text_size / 2.0

			draw_string(font, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, label_color)
