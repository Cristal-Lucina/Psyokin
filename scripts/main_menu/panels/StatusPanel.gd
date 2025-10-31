## ============================================================================
## StatusPanel - Party Status & Appearance Display
## ============================================================================
##
## PURPOSE:
##   Main menu panel displaying party member HP/MP status, general game info
##   (CREDS, perk points, date/time), and character appearance customization.
##   Includes party management with Leader/Active/Bench sections and member swapping.
##
## RESPONSIBILITIES:
##   • Party member HP/MP display (with max values)
##   • Party member level and appearance preview
##   • Party management (Leader + 2 Active + 5 Bench = 8 total slots)
##   • Active member swapping with bench via switch buttons
##   • Money and perk points display
##   • Current date/time display
##   • Hint/flavor text display
##   • Character appearance editor (skin, brow, eye, hair colors)
##   • Real-time status updates from combat/progression
##
## DISPLAY SECTIONS:
##   Left Panel (Party Management):
##   • LEADER section: Hero (fixed, cannot be swapped)
##   • ACTIVE section: 2 active party slots with "Switch" buttons
##   • BENCH section: 5 bench slots for reserve members
##   • Empty slots shown when positions available
##   • Refresh button to update display
##
##   Right Panel:
##   • CREDS counter
##   • Perk points available
##   • Current date (calendar)
##   • Current time phase (Morning/Afternoon/Evening)
##   • Hint text area
##   • Character appearance customization (colors)
##
## APPEARANCE SYSTEM:
##   Four customizable color components:
##   • Skin tone
##   • Brow color
##   • Eye color
##   • Hair color
##   Stored in GameState metadata and CombatProfileSystem
##
## CONNECTED SYSTEMS (Autoloads):
##   • GameState - Money, perk points, party roster, appearance metadata
##   • CombatProfileSystem - Current HP/MP values
##   • StatsSystem - Member levels, stat-based HP/MP pools
##   • CalendarSystem - Date/time display
##   • SigilSystem - (future) Sigil status display
##   • MainEventSystem - Hint text from story events
##
## CSV DATA SOURCES:
##   • res://data/actors/party.csv - Member base data and appearance
##
## KEY METHODS:
##   • _rebuild_party() - Update party member list with Leader/Active/Bench sections
##   • _create_member_card() - Create a member card with HP/MP and optional Switch button
##   • _create_empty_slot() - Create placeholder for empty party/bench slots
##   • _show_member_picker() - Show popup to select bench member for swapping
##   • _perform_swap() - Execute member swap between active and bench
##   • _update_summary() - Update CREDS/perks/date/time
##   • _rebuild_appearance() - Update appearance color swatches
##
## ============================================================================

extends Control
class_name StatusPanel

## Shows party HP/MP, summary info, and appearance.
## Prefers GameState meta + CombatProfileSystem; falls back to Stats/CSV.

# Signal emitted when a menu tab button is clicked
signal tab_selected(tab_id: String)

const GS_PATH        := "/root/aGameState"
const STATS_PATH     := "/root/aStatsSystem"
const CAL_PATH       := "/root/aCalendarSystem"
const PARTY_PATH     := "/root/aPartySystem"
const CSV_PATH       := "/root/aCSVLoader"
const RESOLVER_PATH  := "/root/PartyStatsResolver"
const SIGIL_PATH     := "/root/aSigilSystem"
const CPS_PATH       := "/root/aCombatProfileSystem"

const PARTY_CSV := "res://data/actors/party.csv"
const MES_PATH  := "/root/aMainEventSystem"
const ALT_MES_PATHS := [
	"/root/aMainEvents", "/root/aMainEvent",
	"/root/MainEventSystem", "/root/MainEvents", "/root/MainEvent"
]

# Tab button definitions
const TAB_DEFS: Dictionary = {
	"stats":   {"title": "Stats"},
	"perks":   {"title": "Perks"},
	"items":   {"title": "Items"},
	"loadout": {"title": "Loadout"},
	"bonds":   {"title": "Bonds"},
	"outreach":{"title": "Outreach"},
	"dorms":   {"title": "Dorms"},
	"calendar":{"title": "Calendar"},
	"index":   {"title": "Index"},
	"system":  {"title": "System"},
}

const TAB_ORDER: PackedStringArray = [
	"stats","perks","items","loadout","bonds","outreach","dorms","calendar","index","system"
]

# Character preview constants
const CHAR_BASE_PATH = "res://assets/graphics/characters/"
const CHAR_VARIANTS = ["char_a_p1"]
const LAYERS = {
	"base": {"code": "0bas", "node_name": "BaseSprite", "path": ""},
	"outfit": {"code": "1out", "node_name": "OutfitSprite", "path": "1out"},
	"cloak": {"code": "2clo", "node_name": "CloakSprite", "path": "2clo"},
	"face": {"code": "3fac", "node_name": "FaceSprite", "path": "3fac"},
	"hair": {"code": "4har", "node_name": "HairSprite", "path": "4har"},
	"hat": {"code": "5hat", "node_name": "HatSprite", "path": "5hat"},
	"tool_a": {"code": "6tla", "node_name": "ToolASprite", "path": "6tla"},
	"tool_b": {"code": "7tlb", "node_name": "ToolBSprite", "path": "7tlb"}
}

@onready var _tab_buttons_container: VBoxContainer = %TabButtons
@onready var _refresh   : Button        = $Root/Left/PartyHeader/RefreshBtn
@onready var _party     : VBoxContainer = $Root/Left/PartyScroll/PartyList
@onready var _creds     : Label         = $Root/Right/InfoGrid/MoneyValue
@onready var _perk      : Label         = $Root/Right/InfoGrid/PerkValue
@onready var _morality  : Label         = $Root/Right/InfoGrid/MoralityValue
@onready var _date      : Label         = $Root/Right/InfoGrid/DateValue
@onready var _phase     : Label         = $Root/Right/InfoGrid/PhaseValue
@onready var _hint      : RichTextLabel = $Root/Right/HintValue

# Character Preview UI
@onready var character_layers = $Root/Right/CharacterPreviewBox/ViewportWrapper/CharacterLayers

var _gs        : Node = null
var _st        : Node = null
var _cal       : Node = null
var _mes       : Node = null
var _party_sys : Node = null
var _csv       : Node = null
var _resolver  : Node = null
var _sig       : Node = null
var _cps       : Node = null
var _ctrl_mgr  : Node = null  # ControllerManager reference

# party.csv cache
var _csv_by_id   : Dictionary = {}      # "actor_id" -> row dict
var _name_to_id  : Dictionary = {}      # lowercase "name" -> "actor_id"

# Controller navigation for tab buttons
var _tab_buttons: Array[Button] = []
var _selected_button_index: int = 0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical   = Control.SIZE_EXPAND_FILL

	_gs        = get_node_or_null(GS_PATH)
	_st        = get_node_or_null(STATS_PATH)
	_cal       = get_node_or_null(CAL_PATH)
	_party_sys = get_node_or_null(PARTY_PATH)
	_csv       = get_node_or_null(CSV_PATH)
	_resolver  = get_node_or_null(RESOLVER_PATH)
	_sig       = get_node_or_null(SIGIL_PATH)
	_cps       = get_node_or_null(CPS_PATH)
	_ctrl_mgr  = get_node_or_null("/root/aControllerManager")

	_resolve_event_system()
	_normalize_scroll_children()
	_connect_signals()
	_connect_controller_signals()
	_load_party_csv_cache()
	_build_tab_buttons()

	if _refresh and not _refresh.pressed.is_connected(_rebuild_all):
		_refresh.pressed.connect(_rebuild_all)

	if not is_connected("visibility_changed", Callable(self, "_on_visibility_changed")):
		connect("visibility_changed", Callable(self, "_on_visibility_changed"))

	call_deferred("_first_fill")

func _first_fill() -> void:
	# refresh soft refs (autoload init order resilience)
	if _gs == null:        _gs        = get_node_or_null(GS_PATH)
	if _st == null:        _st        = get_node_or_null(STATS_PATH)
	if _cal == null:       _cal       = get_node_or_null(CAL_PATH)
	if _party_sys == null: _party_sys = get_node_or_null(PARTY_PATH)
	if _csv == null:       _csv       = get_node_or_null(CSV_PATH)
	if _resolver == null:  _resolver  = get_node_or_null(RESOLVER_PATH)
	if _sig == null:       _sig       = get_node_or_null(SIGIL_PATH)
	if _cps == null:       _cps       = get_node_or_null(CPS_PATH)
	_load_party_csv_cache()
	_rebuild_all()

func _build_tab_buttons() -> void:
	"""Build the menu tab buttons"""
	if not _tab_buttons_container:
		return

	# Clear existing buttons
	for child in _tab_buttons_container.get_children():
		child.queue_free()
	_tab_buttons.clear()

	# Create buttons for each tab
	var ids: Array = Array(TAB_ORDER)
	for tab_id_any in ids:
		var tab_id: String = String(tab_id_any)
		if not TAB_DEFS.has(tab_id):
			continue
		var meta: Dictionary = TAB_DEFS[tab_id]

		var btn := Button.new()
		btn.text = String(meta["title"])
		btn.focus_mode = Control.FOCUS_ALL
		btn.size_flags_horizontal = Control.SIZE_FILL
		btn.set_meta("tab_id", tab_id)
		btn.pressed.connect(_on_tab_button_pressed.bind(tab_id))
		_tab_buttons_container.add_child(btn)
		_tab_buttons.append(btn)

	# Highlight first button
	if _tab_buttons.size() > 0:
		_selected_button_index = 0
		_highlight_button(_selected_button_index)

func _on_tab_button_pressed(tab_id: String) -> void:
	"""Handle tab button press - emit signal for GameMenu to handle"""
	tab_selected.emit(tab_id)


func _navigate_buttons(direction: int) -> void:
	"""Navigate through tab buttons with controller"""
	if _tab_buttons.is_empty():
		return

	# Unhighlight current
	_unhighlight_button(_selected_button_index)

	# Update index with wrap-around
	_selected_button_index += direction
	if _selected_button_index < 0:
		_selected_button_index = _tab_buttons.size() - 1
	elif _selected_button_index >= _tab_buttons.size():
		_selected_button_index = 0

	# Highlight new selection
	_highlight_button(_selected_button_index)

func _confirm_button_selection() -> void:
	"""Confirm the currently highlighted button"""
	if _selected_button_index >= 0 and _selected_button_index < _tab_buttons.size():
		var button = _tab_buttons[_selected_button_index]
		var tab_id: String = String(button.get_meta("tab_id"))
		_on_tab_button_pressed(tab_id)

func _highlight_button(index: int) -> void:
	"""Highlight a tab button"""
	if index >= 0 and index < _tab_buttons.size():
		var button = _tab_buttons[index]
		button.modulate = Color(1.2, 1.2, 0.8, 1.0)  # Yellow tint
		button.grab_focus()

func _unhighlight_button(index: int) -> void:
	"""Remove highlight from a tab button"""
	if index >= 0 and index < _tab_buttons.size():
		var button = _tab_buttons[index]
		button.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal color

func _connect_controller_signals() -> void:
	"""Connect to ControllerManager signals for tab navigation"""
	if not _ctrl_mgr:
		return

	if _ctrl_mgr.has_signal("navigate_pressed"):
		if not _ctrl_mgr.is_connected("navigate_pressed", Callable(self, "_on_controller_navigate")):
			_ctrl_mgr.connect("navigate_pressed", Callable(self, "_on_controller_navigate"))

	if _ctrl_mgr.has_signal("action_button_pressed"):
		if not _ctrl_mgr.is_connected("action_button_pressed", Callable(self, "_on_controller_action")):
			_ctrl_mgr.connect("action_button_pressed", Callable(self, "_on_controller_action"))

func _on_controller_navigate(direction: Vector2, context: int) -> void:
	"""Handle navigation from ControllerManager - only in MENU_MAIN context"""
	if not visible or _tab_buttons.is_empty():
		return

	# Only handle navigation when in MENU_MAIN context
	if _ctrl_mgr and _ctrl_mgr.get_current_context() != _ctrl_mgr.InputContext.MENU_MAIN:
		return

	if direction == Vector2.UP:
		print("[StatusPanel] Controller navigate UP")
		_navigate_buttons(-1)
	elif direction == Vector2.DOWN:
		print("[StatusPanel] Controller navigate DOWN")
		_navigate_buttons(1)

func _on_controller_action(action: String, context: int) -> void:
	"""Handle action button from ControllerManager - only in MENU_MAIN context"""
	if not visible or _tab_buttons.is_empty():
		return

	# Only handle accept action when in MENU_MAIN context
	if _ctrl_mgr and _ctrl_mgr.get_current_context() != _ctrl_mgr.InputContext.MENU_MAIN:
		return

	if action == "accept":
		print("[StatusPanel] Controller ACCEPT - confirming selection: %d" % _selected_button_index)
		_confirm_button_selection()

func _connect_signals() -> void:
	# Calendar
	if _cal:
		if _cal.has_signal("day_advanced") and not _cal.is_connected("day_advanced", Callable(self, "_on_cal_day_adv")):
			_cal.connect("day_advanced", Callable(self, "_on_cal_day_adv"))
		if _cal.has_signal("phase_advanced") and not _cal.is_connected("phase_advanced", Callable(self, "_on_cal_phase_adv")):
			_cal.connect("phase_advanced", Callable(self, "_on_cal_phase_adv"))
		if _cal.has_signal("week_reset") and not _cal.is_connected("week_reset", Callable(self, "_rebuild_all")):
			_cal.connect("week_reset", Callable(self, "_rebuild_all"))

	# Stats
	if _st and _st.has_signal("stats_changed"):
		_st.connect("stats_changed", Callable(self, "_rebuild_all"))
	if _st and _st.has_signal("stat_leveled_up"):
		_st.connect("stat_leveled_up", Callable(self, "_rebuild_all"))

	# GameState / Party changes
	for src in [_gs, _party_sys]:
		if src == null: continue
		for sig in ["party_changed","active_changed","roster_changed","changed"]:
			if src.has_signal(sig) and not src.is_connected(sig, Callable(self, "_on_party_changed")):
				src.connect(sig, Callable(self, "_on_party_changed"))

	# Combat Profile updates (reflect current HP/MP/level)
	if _cps:
		for sig2 in ["profile_changed","profiles_changed"]:
			if _cps.has_signal(sig2) and not _cps.is_connected(sig2, Callable(self, "_rebuild_all")):
				_cps.connect(sig2, Callable(self, "_rebuild_all"))

	# Creation screen may fire this; listen globally
	for n in get_tree().root.get_children():
		if n.has_signal("creation_applied") and not n.is_connected("creation_applied", Callable(self, "_rebuild_all")):
			n.connect("creation_applied", Callable(self, "_rebuild_all"))

func _on_cal_day_adv(_date_dict: Dictionary) -> void:
	_rebuild_all()

func _on_cal_phase_adv(_phase_i: int) -> void:
	_rebuild_all()

func _on_party_changed(_a: Variant = null) -> void:
	_load_party_csv_cache()
	_rebuild_party()

func _resolve_event_system() -> void:
	_mes = get_node_or_null(MES_PATH)
	if _mes == null:
		for p in ALT_MES_PATHS:
			_mes = get_node_or_null(p)
			if _mes: break
	if _mes == null:
		for n in get_tree().root.get_children():
			if n.has_method("get_current_hint"):
				_mes = n; break
	if _mes and _mes.has_signal("event_changed"):
		if not _mes.is_connected("event_changed", Callable(self, "_on_event_changed")):
			_mes.connect("event_changed", Callable(self, "_on_event_changed"))

func _normalize_scroll_children() -> void:
	if not _party: return
	var parent := _party.get_parent()
	if parent is ScrollContainer:
		for c in (parent as ScrollContainer).get_children():
			if c != _party:
				(c as Node).queue_free()

func _rebuild_all() -> void:
	_rebuild_party()
	_update_summary()
	_rebuild_appearance()

# --------------------- Party (left panel) ---------------------

func _rebuild_party() -> void:
	if not _party: return
	for c in _party.get_children(): c.queue_free()

	# Enforce party limits first
	if _gs and _gs.has_method("_enforce_party_limits"):
		_gs.call("_enforce_party_limits")

	# Get party structure from GameState
	var party_ids: Array = []
	var bench_ids: Array = []
	if _gs:
		if _gs.has_method("get"):
			var p_v: Variant = _gs.get("party")
			if typeof(p_v) == TYPE_ARRAY:
				for id in (p_v as Array):
					party_ids.append(String(id))
			var b_v: Variant = _gs.get("bench")
			if typeof(b_v) == TYPE_ARRAY:
				for id in (b_v as Array):
					bench_ids.append(String(id))

	# Debug output
	print("[StatusPanel] Party IDs: ", party_ids)
	print("[StatusPanel] Bench IDs: ", bench_ids)

	# Ensure hero is always at index 0
	if party_ids.is_empty() or party_ids[0] != "hero":
		party_ids.insert(0, "hero")

	# Handle edge case: if party has more than 3 members, move extras to bench
	if party_ids.size() > 3:
		for i in range(3, party_ids.size()):
			if not bench_ids.has(party_ids[i]):
				bench_ids.append(party_ids[i])
		party_ids = party_ids.slice(0, 3)

	# === LEADER SECTION ===
	var leader_header := Label.new()
	leader_header.text = "=== LEADER ==="
	leader_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leader_header.add_theme_font_size_override("font_size", 10)
	_party.add_child(leader_header)

	if party_ids.size() > 0:
		var leader_data := _get_member_snapshot(party_ids[0])
		_party.add_child(_create_member_card(leader_data, false, -1))

	_party.add_child(_create_spacer())

	# === ACTIVE SECTION ===
	var active_header := Label.new()
	active_header.text = "=== ACTIVE ==="
	active_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	active_header.add_theme_font_size_override("font_size", 10)
	_party.add_child(active_header)

	for slot_idx in range(1, 3):  # Slots 1 and 2
		if party_ids.size() > slot_idx and party_ids[slot_idx] != "":
			var active_data := _get_member_snapshot(party_ids[slot_idx])
			_party.add_child(_create_member_card(active_data, true, slot_idx))
		else:
			_party.add_child(_create_empty_slot("Active", slot_idx))

	_party.add_child(_create_spacer())

	# === BENCH SECTION ===
	var bench_header := Label.new()
	bench_header.text = "=== BENCH ==="
	bench_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bench_header.add_theme_font_size_override("font_size", 10)
	_party.add_child(bench_header)

	# Only show bench slots that have members (hide empty slots)
	for bench_idx in range(bench_ids.size()):
		var bench_data := _get_member_snapshot(bench_ids[bench_idx])
		bench_data["_bench_idx"] = bench_idx
		bench_data["_member_id"] = bench_ids[bench_idx]
		_party.add_child(_create_member_card(bench_data, false, -1))

	await get_tree().process_frame
	_party.queue_sort()

func _create_spacer() -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8
	return spacer

func _create_empty_slot(slot_type: String, slot_idx: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	var label := Label.new()
	label.text = "[ Empty %s Slot ]" % slot_type
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	vbox.add_child(label)

	panel.add_child(vbox)
	return panel

func _create_member_card(member_data: Dictionary, show_switch: bool, active_slot: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	# Top row: Name + Switch button
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)

	var name_lbl := Label.new()
	name_lbl.text = String(member_data.get("name", "Member"))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 10)
	top_row.add_child(name_lbl)

	if show_switch:
		var switch_btn := Button.new()
		switch_btn.text = "Switch"
		switch_btn.custom_minimum_size.x = 60
		switch_btn.add_theme_font_size_override("font_size", 10)
		switch_btn.set_meta("active_slot", active_slot)
		switch_btn.pressed.connect(_on_switch_pressed.bind(active_slot))
		top_row.add_child(switch_btn)

	vbox.add_child(top_row)

	# HP/MP stats row (side by side)
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 12)
	stats_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# HP Section
	var hp_section := VBoxContainer.new()
	hp_section.add_theme_constant_override("separation", 2)
	hp_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hp_i: int = int(member_data.get("hp", -1))
	var hp_max_i: int = int(member_data.get("hp_max", -1))

	var hp_label_box := HBoxContainer.new()
	hp_label_box.add_theme_constant_override("separation", 4)
	var hp_lbl := Label.new()
	hp_lbl.text = "HP"
	hp_lbl.custom_minimum_size.x = 24
	hp_lbl.add_theme_font_size_override("font_size", 10)
	var hp_val := Label.new()
	hp_val.text = _fmt_pair(hp_i, hp_max_i)
	hp_val.add_theme_font_size_override("font_size", 10)
	hp_label_box.add_child(hp_lbl)
	hp_label_box.add_child(hp_val)
	hp_section.add_child(hp_label_box)

	if hp_i >= 0 and hp_max_i > 0:
		var hp_bar := ProgressBar.new()
		hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hp_bar.custom_minimum_size.y = 8  # Half height (was ~16px default)
		hp_bar.show_percentage = false  # Remove percentage text
		hp_bar.modulate = Color(0.5, 0.8, 1.0)  # Light blue
		hp_bar.min_value = 0.0
		hp_bar.max_value = float(hp_max_i)
		hp_bar.value = clamp(float(hp_i), 0.0, float(hp_max_i))
		hp_section.add_child(hp_bar)

	stats_row.add_child(hp_section)

	# MP Section
	var mp_section := VBoxContainer.new()
	mp_section.add_theme_constant_override("separation", 2)
	mp_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var mp_i: int = int(member_data.get("mp", -1))
	var mp_max_i: int = int(member_data.get("mp_max", -1))

	var mp_label_box := HBoxContainer.new()
	mp_label_box.add_theme_constant_override("separation", 4)
	var mp_lbl := Label.new()
	mp_lbl.text = "MP"
	mp_lbl.custom_minimum_size.x = 24
	mp_lbl.add_theme_font_size_override("font_size", 10)
	var mp_val := Label.new()
	mp_val.text = _fmt_pair(mp_i, mp_max_i)
	mp_val.add_theme_font_size_override("font_size", 10)
	mp_label_box.add_child(mp_lbl)
	mp_label_box.add_child(mp_val)
	mp_section.add_child(mp_label_box)

	if mp_i >= 0 and mp_max_i > 0:
		var mp_bar := ProgressBar.new()
		mp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mp_bar.custom_minimum_size.y = 8  # Half height (was ~16px default)
		mp_bar.show_percentage = false  # Remove percentage text
		mp_bar.modulate = Color(1.0, 0.7, 0.85)  # Light pink
		mp_bar.min_value = 0.0
		mp_bar.max_value = float(mp_max_i)
		mp_bar.value = clamp(float(mp_i), 0.0, float(mp_max_i))
		mp_section.add_child(mp_bar)

	stats_row.add_child(mp_section)
	vbox.add_child(stats_row)

	panel.add_child(vbox)
	return panel

func _get_member_snapshot(member_id: String) -> Dictionary:
	# Get roster to pass to _label_for_id for accurate name lookup
	var roster: Dictionary = _read_roster()
	# Always get display name from _label_for_id as primary source
	var display_name: String = _label_for_id(member_id, roster)

	# Try to get combat profile for HP/MP/level
	if _cps and _cps.has_method("get_profile"):
		var p_v: Variant = _cps.call("get_profile", member_id)
		if typeof(p_v) == TYPE_DICTIONARY:
			var p: Dictionary = p_v
			var lvl: int = int(p.get("level", 1))
			var hp_cur: int = int(p.get("hp", -1))
			var hp_max: int = int(p.get("hp_max", -1))
			var mp_cur: int = int(p.get("mp", -1))
			var mp_max: int = int(p.get("mp_max", -1))

			# Always use display_name from _label_for_id which has proper CSV/roster fallbacks
			return {
				"name": "%s  (Lv %d)" % [display_name, lvl],
				"hp": hp_cur,
				"hp_max": hp_max,
				"mp": mp_cur,
				"mp_max": mp_max,
				"_member_id": member_id
			}

	# Fallback: no profile data, use display name and compute stats
	var lvl: int = 1
	var hp_max: int = 150
	var mp_max: int = 20

	if _gs:
		lvl = _gs.call("get_member_level", member_id) if _gs.has_method("get_member_level") else 1
		if _gs.has_method("compute_member_pools"):
			var pools_v: Variant = _gs.call("compute_member_pools", member_id)
			if typeof(pools_v) == TYPE_DICTIONARY:
				var pools: Dictionary = pools_v
				hp_max = int(pools.get("hp_max", hp_max))
				mp_max = int(pools.get("mp_max", mp_max))

	return {
		"name": "%s  (Lv %d)" % [display_name, lvl],
		"hp": hp_max,
		"hp_max": hp_max,
		"mp": mp_max,
		"mp_max": mp_max,
		"_member_id": member_id
	}

func _on_switch_pressed(active_slot: int) -> void:
	# Show bench member picker popup
	_show_member_picker(active_slot)

func _show_member_picker(active_slot: int) -> void:
	if not _gs: return

	# Enforce limits before checking bench
	if _gs.has_method("_enforce_party_limits"):
		_gs.call("_enforce_party_limits")

	# Get bench members
	var bench_ids: Array = []
	if _gs.has_method("get"):
		var b_v: Variant = _gs.get("bench")
		if typeof(b_v) == TYPE_ARRAY:
			for id in (b_v as Array):
				bench_ids.append(String(id))

	# Debug output
	print("[_show_member_picker] Active slot: ", active_slot)
	print("[_show_member_picker] Bench IDs found: ", bench_ids)
	print("[_show_member_picker] Bench array from GameState: ", _gs.get("bench") if _gs.has_method("get") else "N/A")

	if bench_ids.is_empty():
		# Show message: no bench members available
		var msg_popup := AcceptDialog.new()
		msg_popup.dialog_text = "No members available on the bench to switch with."
		msg_popup.title = "No Bench Members"
		add_child(msg_popup)
		msg_popup.popup_centered()
		msg_popup.confirmed.connect(func(): msg_popup.queue_free())
		return

	# Create picker popup
	var picker := ConfirmationDialog.new()
	picker.title = "Select Bench Member"
	picker.max_size = Vector2(400, 500)  # Max height is 500px

	# Create content container
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)

	# Add instruction text as a separate label
	var instruction := Label.new()
	instruction.text = "Choose a member from the bench to swap into this active slot:"
	instruction.add_theme_font_size_override("font_size", 10)
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(instruction)

	# Add member list (scrollable, will fit within max dialog height)
	var item_list := ItemList.new()
	item_list.custom_minimum_size = Vector2(280, 150)
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Get roster for accurate name lookup
	var roster: Dictionary = _read_roster()

	for bench_id in bench_ids:
		var display_name: String = _label_for_id(bench_id, roster)
		var level: int = 1
		if _cps and _cps.has_method("get_profile"):
			var prof_v: Variant = _cps.call("get_profile", bench_id)
			if typeof(prof_v) == TYPE_DICTIONARY:
				level = int((prof_v as Dictionary).get("level", 1))
		item_list.add_item("%s (Lv %d)" % [display_name, level])
		item_list.set_item_metadata(item_list.item_count - 1, bench_id)

	vbox.add_child(item_list)
	picker.add_child(vbox)
	add_child(picker)

	picker.confirmed.connect(func():
		var selected_idx: int = item_list.get_selected_items()[0] if item_list.get_selected_items().size() > 0 else -1
		if selected_idx >= 0:
			var selected_id: String = String(item_list.get_item_metadata(selected_idx))
			_perform_swap(active_slot, selected_id)
		picker.queue_free()
	)
	picker.canceled.connect(func(): picker.queue_free())

	# Center the dialog (will auto-size within max_size constraint)
	picker.popup_centered()

func _perform_swap(active_slot: int, bench_member_id: String) -> void:
	if not _gs or not _gs.has_method("swap_active_bench"): return

	var success: bool = _gs.call("swap_active_bench", active_slot, bench_member_id)
	if success:
		_rebuild_party()  # Refresh display
	else:
		var error_popup := AcceptDialog.new()
		error_popup.dialog_text = "Failed to swap party members. Please try again."
		error_popup.title = "Swap Failed"
		add_child(error_popup)
		error_popup.popup_centered()
		error_popup.confirmed.connect(func(): error_popup.queue_free())

# Prefer CPS for real-time party pools
func _get_party_snapshot() -> Array:
	if _cps != null and _gs != null and _gs.has_method("get_active_party_ids"):
		var out: Array = []
		var ids_v: Variant = _gs.call("get_active_party_ids")
		var ids: Array = []
		if typeof(ids_v) == TYPE_ARRAY:
			ids = ids_v
		elif typeof(ids_v) == TYPE_PACKED_STRING_ARRAY:
			for s in (ids_v as PackedStringArray): ids.append(String(s))
		if ids.is_empty(): ids = ["hero"]

		for id_any in ids:
			var id: String = String(id_any)
			if not _cps.has_method("get_profile"):
				continue
			var p_v: Variant = _cps.call("get_profile", id)
			if typeof(p_v) != TYPE_DICTIONARY:
				continue
			var p: Dictionary = p_v
			var lvl: int = int(p.get("level", 1))
			var hp_cur: int = int(p.get("hp", -1))
			var hp_max: int = int(p.get("hp_max", -1))
			var mp_cur: int = int(p.get("mp", -1))
			var mp_max: int = int(p.get("mp_max", -1))
			var label: String = String(p.get("label", _label_for_id(id)))
			out.append({
				"name": "%s  (Lv %d)" % [label, lvl],
				"hp": hp_cur, "hp_max": hp_max,
				"mp": mp_cur, "mp_max": mp_max
			})
		if out.size() > 0:
			return out

	# Fallbacks
	if _resolver and _resolver.has_method("get_party_snapshots"):
		var r_v: Variant = _resolver.call("get_party_snapshots")
		if typeof(r_v) == TYPE_ARRAY:
			var out_rs: Array = []
			for d_v in (r_v as Array):
				if typeof(d_v) != TYPE_DICTIONARY: continue
				var d: Dictionary = d_v
				var label: String = String(d.get("label", String(d.get("name","Member"))))
				var lvl: int = int(d.get("level", 1))
				var hp_max_i: int = int(d.get("hp_max", -1))
				var mp_max_i: int = int(d.get("mp_max", -1))
				var hp_cur_i: int = (hp_max_i if hp_max_i >= 0 else -1)
				var mp_cur_i: int = (mp_max_i if mp_max_i >= 0 else -1)
				out_rs.append({
					"name": "%s  (Lv %d)" % [label, lvl],
					"hp": hp_cur_i, "hp_max": hp_max_i,
					"mp": mp_cur_i, "mp_max": mp_max_i
				})
			if out_rs.size() > 0:
				return out_rs
	return _build_snapshot_flexible()

# --------------------- Right column summary -------------------

func _update_summary() -> void:
	if _creds: _creds.text = _read_creds()
	if _perk:  _perk.text  = _read_perk_points()

	if _morality:
		_morality.text = _read_morality()
		# Color the morality text based on tier
		var morality_sys = get_node_or_null("/root/aMoralitySystem")
		if morality_sys and morality_sys.has_method("get_tier_color"):
			var color: Color = morality_sys.call("get_tier_color")
			_morality.add_theme_color_override("font_color", color)

	var dp: Dictionary = _read_date_phase()
	if _date:  _date.text  = String(dp.get("date_text", "—"))
	if _phase: _phase.text = String(dp.get("phase_text", "—"))

	if _hint:
		var h: String = _read_mission_hint()
		_hint.text = h if h != "" else "[i]TBD[/i]"

# --------------------- Character Preview ----------------------

func _rebuild_appearance() -> void:
	_update_character_preview()

func _update_character_preview() -> void:
	"""Update the character preview with saved variant data"""
	print("[StatusPanel] Updating character preview...")

	if not character_layers:
		print("[StatusPanel] ERROR: character_layers is null!")
		return

	# Get character variants from GameState
	var variants: Dictionary = {}
	if _gs and _gs.has_meta("hero_identity"):
		var id_v: Variant = _gs.get_meta("hero_identity")
		if typeof(id_v) == TYPE_DICTIONARY:
			var id: Dictionary = id_v
			print("[StatusPanel] hero_identity found: ", id.keys())
			if id.has("character_variants"):
				var cv: Variant = id.get("character_variants")
				if typeof(cv) == TYPE_DICTIONARY:
					variants = cv
					print("[StatusPanel] Loaded variants from GameState: ", variants)
			else:
				print("[StatusPanel] No character_variants in hero_identity")
		else:
			print("[StatusPanel] hero_identity is not a dictionary")
	else:
		print("[StatusPanel] No hero_identity meta found in GameState")

	# If no variants saved, try to load from CharacterData autoload
	if variants.is_empty():
		print("[StatusPanel] Trying CharacterData autoload...")
		var char_data = get_node_or_null("/root/aCharacterData")
		if char_data:
			print("[StatusPanel] CharacterData found")
			if char_data.has_method("get"):
				var sv: Variant = char_data.get("selected_variants")
				print("[StatusPanel] selected_variants type: ", typeof(sv))
				if typeof(sv) == TYPE_DICTIONARY:
					variants = sv
					print("[StatusPanel] Loaded variants from CharacterData: ", variants)
			elif char_data.get("selected_variants"):
				var sv2 = char_data.get("selected_variants")
				if typeof(sv2) == TYPE_DICTIONARY:
					variants = sv2
					print("[StatusPanel] Loaded variants from CharacterData (property): ", variants)
		else:
			print("[StatusPanel] CharacterData autoload not found")

	if variants.is_empty():
		print("[StatusPanel] WARNING: No character variants found!")
		return

	# Update each layer sprite
	for layer_key in LAYERS:
		var layer = LAYERS[layer_key]
		var sprite = character_layers.get_node(layer.node_name)

		if layer_key in variants and variants[layer_key] != "":
			var variant_code = variants[layer_key]
			print("[StatusPanel] Loading ", layer_key, " with variant: ", variant_code)
			var texture_path = _find_character_file(layer_key, variant_code)
			print("[StatusPanel]   -> Path: ", texture_path)
			if texture_path != "" and FileAccess.file_exists(texture_path):
				var texture = load(texture_path)
				sprite.texture = texture
				sprite.visible = true
				# Set to idle pose (south idle = sprite 1 = frame 0)
				sprite.frame = 0
				print("[StatusPanel]   -> Loaded successfully, frame set to ", sprite.frame)
			else:
				print("[StatusPanel]   -> ERROR: File not found!")
				sprite.texture = null
				sprite.visible = false
		else:
			sprite.texture = null
			sprite.visible = false

func _find_character_file(layer_key: String, variant_code: String) -> String:
	"""Find the character file for a given layer and variant code"""
	if not LAYERS.has(layer_key):
		print("[StatusPanel]     Layer key not found: ", layer_key)
		return ""

	var layer = LAYERS[layer_key]
	for variant in CHAR_VARIANTS:
		var base_path = CHAR_BASE_PATH + variant + "/"
		var layer_path = base_path + (layer.path + "/" if layer.path != "" else "")
		var filename = "%s_%s_%s.png" % [variant, layer.code, variant_code]
		var full_path = layer_path + filename

		print("[StatusPanel]     Trying: ", full_path)
		if FileAccess.file_exists(full_path):
			print("[StatusPanel]     FOUND!")
			return full_path

	print("[StatusPanel]     Not found in any variant")
	return ""

# --------------------- Small helpers -------------------------

func _read_creds() -> String:
	if _gs:
		if _gs.has_method("get_creds"): return str(int(_gs.call("get_creds")))
		if _gs.has_method("get"):
			var v: Variant = _gs.get("creds")
			if typeof(v) in [TYPE_INT, TYPE_FLOAT]: return str(int(v))
	return "0"

func _read_perk_points() -> String:
	if _st:
		if _st.has_method("get_perk_points"): return str(int(_st.call("get_perk_points")))
		if _st.has_method("get"):
			var v: Variant = _st.get("perk_points")
			if typeof(v) in [TYPE_INT, TYPE_FLOAT]: return str(int(v))
	if _gs and _gs.has_method("get"):
		var gv: Variant = _gs.get("perk_points")
		if typeof(gv) in [TYPE_INT, TYPE_FLOAT]: return str(int(gv))
	return "0"

func _read_morality() -> String:
	var morality_sys = get_node_or_null("/root/aMoralitySystem")
	if morality_sys:
		var meter: int = 0
		var tier_name: String = "Neutral"

		# Get morality meter value
		if morality_sys.has_method("get"):
			var m_v: Variant = morality_sys.get("morality_meter")
			if typeof(m_v) in [TYPE_INT, TYPE_FLOAT]:
				meter = int(m_v)

		# Get tier name
		if morality_sys.has_method("get_tier_name"):
			tier_name = String(morality_sys.call("get_tier_name"))

		return "%s (%+d)" % [tier_name, meter]
	return "Neutral (0)"

func _read_date_phase() -> Dictionary:
	var out: Dictionary = {}
	if _cal:
		if _cal.has_method("get_date_string"): out["date_text"] = String(_cal.call("get_date_string"))
		if _cal.has_method("get_phase_name"):   out["phase_text"] = String(_cal.call("get_phase_name"))
	if not out.has("date_text"): out["date_text"] = "—"
	if not out.has("phase_text"): out["phase_text"] = "—"
	return out

func _read_mission_hint() -> String:
	if _mes:
		if _mes.has_method("get_current_hint"):
			var h2: String = String(_mes.call("get_current_hint"))
			if h2 != "": return h2
		if _mes.has_method("get_current_title"):
			var t: String = String(_mes.call("get_current_title"))
			if t != "": return t
	if _gs:
		if _gs.has_method("get_mission_hint"): return String(_gs.call("get_mission_hint"))
		if _gs.has_method("get"):
			var v: Variant = _gs.get("mission_hint")
			if typeof(v) == TYPE_STRING: return String(v)
	return ""

func _on_event_changed(_id: String) -> void:
	if _hint:
		var h: String = _read_mission_hint()
		_hint.text = h if h != "" else "[i]TBD[/i]"

func _fmt_pair(a: int, b: int) -> String:
	return "%d / %d" % [a, b] if a >= 0 and b > 0 else "—"

# --------------------- Party snapshot fallbacks -------------------

func _build_snapshot_flexible() -> Array:
	var out: Array = []
	var roster: Dictionary = _read_roster()
	var entries: Array = _gather_active_entries(roster)

	for e_v in entries:
		if typeof(e_v) != TYPE_DICTIONARY: continue
		var e: Dictionary = e_v
		var pid: String = String(e.get("key",""))
		var label: String = String(e.get("label",""))

		var resolved: Dictionary = _resolve_member_stats(pid, label)
		var disp_name: String = String(resolved.get("name", (label if label != "" else pid)))
		var lvl: int = int(resolved.get("level", 1))
		var vtl: int = int(resolved.get("VTL", 1))
		var fcs: int = int(resolved.get("FCS", 1))

		var hp_max_i: int = _calc_max_hp(lvl, vtl)
		var mp_max_i: int = _calc_max_mp(lvl, fcs)
		var hp_cur_i: int = clamp(int(resolved.get("hp_cur", hp_max_i)), 0, hp_max_i)
		var mp_cur_i: int = clamp(int(resolved.get("mp_cur", mp_max_i)), 0, mp_max_i)

		out.append({
			"name": "%s  (Lv %d)" % [disp_name, lvl],
			"hp": hp_cur_i, "hp_max": hp_max_i,
			"mp": mp_cur_i, "mp_max": mp_max_i
		})

	if out.is_empty():
		var nm2: String = _safe_hero_name()
		var lvl2: int = _safe_hero_level()
		var mh: int = _calc_max_hp(lvl2, 1)
		var mm: int = _calc_max_mp(lvl2, 1)
		out.append({"name":"%s  (Lv %d)" % [nm2, lvl2], "hp": mh, "hp_max": mh, "mp": mm, "mp_max": mm})
	return out

# ---------- CSV cache + per-member resolution ----------------

func _load_party_csv_cache() -> void:
	_csv_by_id.clear()
	_name_to_id.clear()

	# Preferred: CSV autoload
	_csv = (_csv if _csv != null else get_node_or_null(CSV_PATH))
	if _csv and _csv.has_method("load_csv"):
		var defs_v: Variant = _csv.call("load_csv", PARTY_CSV, "actor_id")
		if typeof(defs_v) == TYPE_DICTIONARY:
			var defs: Dictionary = defs_v
			for id_any in defs.keys():
				var rid: String = String(id_any)
				var row: Dictionary = defs[rid]
				_csv_by_id[rid] = row
				var n_v: Variant = row.get("name", "")
				if typeof(n_v) == TYPE_STRING:
					var key: String = String(n_v).strip_edges().to_lower()
					if key != "": _name_to_id[key] = rid
			return

	# Manual fallback
	if not FileAccess.file_exists(PARTY_CSV):
		return
	var f := FileAccess.open(PARTY_CSV, FileAccess.READ)
	if f == null: return
	if f.eof_reached():
		f.close()
		return

	var header: PackedStringArray = f.get_csv_line()
	var idx_id: int = header.find("actor_id")
	var idx_name: int = header.find("name")
	while not f.eof_reached():
		var row_psa: PackedStringArray = f.get_csv_line()
		if row_psa.is_empty(): continue
		var rid2: String = (String(row_psa[idx_id]) if idx_id >= 0 and idx_id < row_psa.size() else "")
		var nm2: String  = (String(row_psa[idx_name]) if idx_name >= 0 and idx_name < row_psa.size() else "")
		var row_dict: Dictionary = {}
		for i in range(header.size()):
			row_dict[String(header[i])] = (row_psa[i] if i < row_psa.size() else "")
		if rid2 != "":
			_csv_by_id[rid2] = row_dict
		if nm2.strip_edges() != "":
			_name_to_id[nm2.strip_edges().to_lower()] = rid2
	f.close()

func _read_roster() -> Dictionary:
	var roster: Dictionary = {}
	if _party_sys:
		if _party_sys.has_method("get"):
			var r_v: Variant = _party_sys.get("roster")
			if typeof(r_v) == TYPE_DICTIONARY: roster = r_v as Dictionary
		if roster.is_empty() and _party_sys.has_method("get_roster"):
			var r2_v: Variant = _party_sys.call("get_roster")
			if typeof(r2_v) == TYPE_DICTIONARY: roster = r2_v as Dictionary
	return roster

func _label_for_id(pid: String, roster: Dictionary = {}) -> String:
	if pid == "hero": return _safe_hero_name()
	if roster.has(pid):
		var rec: Dictionary = roster[pid]
		if rec.has("name") and typeof(rec["name"]) == TYPE_STRING and String(rec["name"]).strip_edges() != "":
			return String(rec["name"])
	# CSV fallback
	if _csv_by_id.has(pid):
		var row: Dictionary = _csv_by_id[pid]
		var nm: String = String(row.get("name",""))
		if nm != "": return nm
	return (pid.capitalize() if pid != "" else "")

func _gather_active_entries(roster: Dictionary) -> Array:
	var entries: Array = []

	if _gs and _gs.has_method("get_active_party_ids"):
		var v: Variant = _gs.call("get_active_party_ids")
		for s in _array_from_any(v):
			var pid := String(s)
			entries.append({"key": pid, "label": _label_for_id(pid, roster)})
		if entries.size() > 0: return entries

	if _gs and _gs.has_method("get"):
		var p_v: Variant = _gs.get("party")
		for s3 in _array_from_any(p_v):
			var pid3 := String(s3)
			entries.append({"key": pid3, "label": _label_for_id(pid3, roster)})
		if entries.size() > 0: return entries

	if _party_sys:
		for m in ["get_active_party","get_party","list_active_members","list_party","get_active"]:
			if _party_sys.has_method(m):
				var r: Variant = _party_sys.call(m)
				for s4 in _array_from_any(r):
					var pid4 := String(s4)
					entries.append({"key": pid4, "label": _label_for_id(pid4, roster)})
				if entries.size() > 0: return entries
		for prop in ["active","party"]:
			if _party_sys.has_method("get"):
				var a_v: Variant = _party_sys.get(prop)
				for s5 in _array_from_any(a_v):
					var pid5 := String(s5)
					entries.append({"key": pid5, "label": _label_for_id(pid5, roster)})
				if entries.size() > 0: return entries

	entries.append({"key":"hero","label":_safe_hero_name()})
	return entries

func _array_from_any(v: Variant) -> Array:
	if typeof(v) == TYPE_ARRAY: return v as Array
	if typeof(v) == TYPE_PACKED_STRING_ARRAY:
		var out: Array = []
		for s in (v as PackedStringArray): out.append(String(s))
		return out
	return []

# ---- per-member resolution & misc ------------------------------------

func _resolve_member_stats(pid_in: String, label_in: String) -> Dictionary:
	if pid_in == "hero":
		var lvl: int = _safe_hero_level()
		var vtl: int = 1
		var fcs: int = 1
		if _st and _st.has_method("get_stat"):
			var v_v: Variant = _st.call("get_stat", "VTL")
			if typeof(v_v) in [TYPE_INT, TYPE_FLOAT]: vtl = int(v_v)
			var f_v: Variant = _st.call("get_stat", "FCS")
			if typeof(f_v) in [TYPE_INT, TYPE_FLOAT]: fcs = int(f_v)
		return {"name": _safe_hero_name(), "level": max(1,lvl), "VTL": max(1,vtl), "FCS": max(1,fcs)}

	var pid: String = pid_in
	if pid == "" and label_in.strip_edges() != "":
		var key: String = label_in.strip_edges().to_lower()
		if _name_to_id.has(key): pid = String(_name_to_id[key])

	var row: Dictionary = _csv_by_id.get(pid, {}) as Dictionary
	if row.is_empty() and label_in.strip_edges() != "":
		var key2: String = label_in.strip_edges().to_lower()
		if _name_to_id.has(key2):
			var pid2: String = String(_name_to_id[key2])
			row = _csv_by_id.get(pid2, {}) as Dictionary

	var lvl_csv: int = _to_int(row.get("level_start", 1))
	var vtl_csv: int = _to_int(row.get("start_vtl", 1))
	var fcs_csv: int = _to_int(row.get("start_fcs", 1))
	var nm: String = (String(row.get("name","")) if row.has("name") else (label_in if label_in != "" else pid_in))

	return {"name": (nm if nm != "" else (label_in if label_in != "" else pid_in)), "level": max(1,lvl_csv), "VTL": max(1,vtl_csv), "FCS": max(1,fcs_csv)}

func _to_int(v: Variant) -> int:
	match typeof(v):
		TYPE_INT: return int(v)
		TYPE_FLOAT: return int(round(float(v)))
		TYPE_STRING:
			var s := String(v).strip_edges()
			if s == "": return 0
			return int(s.to_int())
		_: return 0

func _calc_max_hp(level: int, vtl: int) -> int:
	return 150 + (max(1, vtl) * max(1, level) * 6)

func _calc_max_mp(level: int, fcs: int) -> int:
	return 20 + int(round(1.5 * float(max(1, fcs)) * float(max(1, level))))

func _safe_hero_name() -> String:
	if _gs and _gs.has_method("get"):
		var v: Variant = _gs.get("player_name")
		if typeof(v) == TYPE_STRING and String(v).strip_edges() != "":
			return String(v)
	return "Player"

func _safe_hero_level() -> int:
	if _st:
		if _st.has_method("get_stat"):
			var v: Variant = _st.call("get_stat","LVL")
			if typeof(v) in [TYPE_INT, TYPE_FLOAT]: return int(v)
		if _st.has_method("get_member_level"):
			var v2: Variant = _st.call("get_member_level","hero")
			if typeof(v2) in [TYPE_INT, TYPE_FLOAT]: return int(v2)
	return 1

# --------------------- Dev dump/hotkey ------------------------

func _on_visibility_changed() -> void:
	# Re-highlight first button when panel becomes visible
	if visible and _tab_buttons.size() > 0:
		_selected_button_index = 0
		_highlight_button(_selected_button_index)

	if not OS.is_debug_build(): return
	_dev_dump_profiles()

func _unhandled_input(event: InputEvent) -> void:
	"""Handle debug input only - controller navigation is now handled via ControllerManager signals"""
	# Debug key handling (F9 to dump profiles)
	if not OS.is_debug_build(): return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var ek := event as InputEventKey
		if ek.keycode == KEY_F9:
			_dev_dump_profiles()

func _dev_dump_profiles() -> void:
	print_rich("[b]=== Combat Profiles (StatusPanel) ===[/b]")
	var entries: Array = _gather_active_entries(_read_roster())
	var labels: Array = []
	for e_v in entries:
		if typeof(e_v) == TYPE_DICTIONARY:
			labels.append(String((e_v as Dictionary).get("label","")))
	print("[StatusPanel] active entries: %s" % [String(", ").join(labels)])

	if _cps and _cps.has_method("get_profile"):
		for e_v in entries:
			if typeof(e_v) != TYPE_DICTIONARY: continue
			var pid: String = String((e_v as Dictionary).get("key",""))
			var p_v: Variant = _cps.call("get_profile", pid)
			if typeof(p_v) != TYPE_DICTIONARY: continue
			var p: Dictionary = p_v
			var mind: Dictionary = p.get("mind", {}) as Dictionary
			var mind_str: String = String(mind.get("active", mind.get("base","—")))
			print("%s | Lv %d | HP %d/%d MP %d/%d | mind %s"
				% [ _label_for_id(pid), int(p.get("level",1)),
					int(p.get("hp",0)), int(p.get("hp_max",0)),
					int(p.get("mp",0)), int(p.get("mp_max",0)),
					mind_str ])
