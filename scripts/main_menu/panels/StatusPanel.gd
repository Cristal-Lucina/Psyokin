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

@onready var _vertical_menu_box : PanelContainer = %VerticalMenuBox
@onready var _root_container : HBoxContainer = $Root
@onready var _tab_column : VBoxContainer = $Root/TabColumn
@onready var _tab_list  : ItemList      = %TabList
@onready var _left_panel : VBoxContainer = $Root/Left
@onready var _right_panel : VBoxContainer = $Root/Right
@onready var _party     : VBoxContainer = $Root/Left/PartyScroll/PartyList
@onready var _creds     : Label         = $Root/Right/InfoGrid/MoneyValue
@onready var _perk      : Label         = $Root/Right/InfoGrid/PerkValue
@onready var _morality  : Label         = $Root/Right/InfoGrid/MoralityValue
@onready var _date      : Label         = $Root/Right/InfoGrid/DateValue
@onready var _phase     : Label         = $Root/Right/InfoGrid/PhaseValue
@onready var _hint      : RichTextLabel = $Root/Right/HintSection/HintValue

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

# Menu slide state
var _menu_visible : bool = true
var _menu_tween   : Tween = null

# party.csv cache
var _csv_by_id   : Dictionary = {}      # "actor_id" -> row dict
var _name_to_id  : Dictionary = {}      # lowercase "name" -> "actor_id"

# Tab metadata (maps item index to tab_id)
var _tab_ids: Array[String] = []

# Controller navigation state - Simple state machine (like LoadoutPanel)
enum NavState { MENU, CONTENT, POPUP_ACTIVE }
var _nav_state: NavState = NavState.MENU
var _active_popup: Control = null  # Currently open popup panel

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
	_load_party_csv_cache()
	_build_tab_buttons()

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
	"""Build the menu tab items in ItemList"""
	if not _tab_list:
		return

	# Clear existing items
	_tab_list.clear()
	_tab_ids.clear()

	# Add items for each tab
	var ids: Array = Array(TAB_ORDER)
	for tab_id_any in ids:
		var tab_id: String = String(tab_id_any)
		if not TAB_DEFS.has(tab_id):
			continue
		var meta: Dictionary = TAB_DEFS[tab_id]

		_tab_list.add_item(String(meta["title"]))
		_tab_ids.append(tab_id)

	# Select first item and connect signal
	if _tab_list.item_count > 0:
		_tab_list.select(0)
		# Grab focus if panel is visible
		if visible:
			call_deferred("_grab_tab_list_focus")

	# Connect item selection signal
	if not _tab_list.item_selected.is_connected(_on_tab_item_selected):
		_tab_list.item_selected.connect(_on_tab_item_selected)

	# Connect item activation signal (double-click or Enter)
	if not _tab_list.item_activated.is_connected(_on_tab_item_activated):
		_tab_list.item_activated.connect(_on_tab_item_activated)

	# Connect item clicked signal (single-click support)
	if not _tab_list.item_clicked.is_connected(_on_tab_item_clicked):
		_tab_list.item_clicked.connect(_on_tab_item_clicked)

func _on_tab_item_selected(index: int) -> void:
	"""Handle tab item selection (when navigating with UP/DOWN)"""
	# Just visual feedback - don't switch tabs yet
	print("[StatusPanel] Tab selected: index %d" % index)

func _on_tab_item_clicked(index: int, _at_position: Vector2, mouse_button_index: int) -> void:
	"""Handle tab item clicked (single left-click support)"""
	if mouse_button_index == MOUSE_BUTTON_LEFT:
		_on_tab_item_activated(index)

func _on_tab_item_activated(index: int) -> void:
	"""Handle tab item activation (A button or double-click)"""
	if index < 0 or index >= _tab_ids.size():
		return

	var tab_id: String = _tab_ids[index]
	print("[StatusPanel] Tab activated: %s" % tab_id)
	tab_selected.emit(tab_id)

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
	leader_header.text = "LEADER"
	leader_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leader_header.add_theme_font_size_override("font_size", 16)
	leader_header.add_theme_color_override("font_color", Color(1, 0.7, 0.75, 1))
	_party.add_child(leader_header)

	if party_ids.size() > 0:
		var leader_data := _get_member_snapshot(party_ids[0])
		_party.add_child(_create_member_card(leader_data, false, -1))

	_party.add_child(_create_spacer())

	# === ACTIVE SECTION ===
	var active_header := Label.new()
	active_header.text = "ACTIVE"
	active_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	active_header.add_theme_font_size_override("font_size", 16)
	active_header.add_theme_color_override("font_color", Color(1, 0.7, 0.75, 1))
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
	bench_header.text = "BENCH"
	bench_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bench_header.add_theme_font_size_override("font_size", 16)
	bench_header.add_theme_color_override("font_color", Color(1, 0.7, 0.75, 1))
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

	# Recovery button (always shown for all members)
	var recovery_btn := Button.new()
	recovery_btn.text = "Recovery"
	recovery_btn.custom_minimum_size.x = 70
	recovery_btn.add_theme_font_size_override("font_size", 10)
	recovery_btn.focus_mode = Control.FOCUS_ALL  # Make sure button can receive focus
	var member_id: String = String(member_data.get("_member_id", ""))
	recovery_btn.set_meta("member_id", member_id)
	recovery_btn.set_meta("member_name", String(member_data.get("name", "Member")))
	recovery_btn.set_meta("hp", int(member_data.get("hp", 0)))
	recovery_btn.set_meta("hp_max", int(member_data.get("hp_max", 0)))
	recovery_btn.set_meta("mp", int(member_data.get("mp", 0)))
	recovery_btn.set_meta("mp_max", int(member_data.get("mp_max", 0)))
	recovery_btn.pressed.connect(_on_recovery_pressed.bind(recovery_btn))
	top_row.add_child(recovery_btn)
	print("[StatusPanel] Created Recovery button for %s" % String(member_data.get("name", "Member")))

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

func _on_recovery_pressed(button: Button) -> void:
	"""Show recovery item selection popup"""
	var member_id: String = String(button.get_meta("member_id", ""))
	var member_name: String = String(button.get_meta("member_name", "Member"))
	var hp: int = int(button.get_meta("hp", 0))
	var hp_max: int = int(button.get_meta("hp_max", 0))
	var mp: int = int(button.get_meta("mp", 0))
	var mp_max: int = int(button.get_meta("mp_max", 0))

	print("[StatusPanel] Recovery button pressed for %s (ID: %s)" % [member_name, member_id])
	_show_recovery_popup(member_id, member_name, hp, hp_max, mp, mp_max)

func _show_no_bench_notice() -> void:
	"""Show 'no bench members' notice using Panel pattern"""
	# Prevent multiple popups
	if _active_popup and is_instance_valid(_active_popup):
		print("[StatusPanel] Popup already open, ignoring request")
		return

	# Create popup panel
	var popup_panel: Panel = Panel.new()
	popup_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	popup_panel.z_index = 100
	add_child(popup_panel)

	# Set active popup immediately
	_active_popup = popup_panel

	# Create content container
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	popup_panel.add_child(vbox)

	# Title label
	var title: Label = Label.new()
	title.text = "No Bench Members"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	# Message label
	var message: Label = Label.new()
	message.text = "No benched party members available."
	message.add_theme_font_size_override("font_size", 10)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(message)

	# Add OK button
	var ok_btn: Button = Button.new()
	ok_btn.text = "OK"
	ok_btn.pressed.connect(_popup_close_notice)
	vbox.add_child(ok_btn)

	# Auto-size panel - wait two frames
	await get_tree().process_frame
	await get_tree().process_frame
	popup_panel.size = vbox.size + Vector2(20, 20)
	vbox.position = Vector2(10, 10)

	# Center popup on screen
	var viewport_size: Vector2 = get_viewport_rect().size
	popup_panel.position = (viewport_size - popup_panel.size) / 2.0
	print("[StatusPanel] No-bench notice centered at: %s, size: %s" % [popup_panel.position, popup_panel.size])

	# Store metadata
	popup_panel.set_meta("_is_notice_popup", true)

	# Push popup to aPanelManager stack
	var panel_mgr = get_node_or_null("/root/aPanelManager")
	if panel_mgr:
		panel_mgr.push_panel(popup_panel)
		print("[StatusPanel] Pushed no-bench notice to aPanelManager stack")

	# Set state to POPUP_ACTIVE
	_nav_state = NavState.POPUP_ACTIVE

	# Grab focus on OK button
	await get_tree().process_frame
	ok_btn.grab_focus()

func _popup_close_notice() -> void:
	"""Close notice popup and return to content"""
	print("[StatusPanel] Notice popup closed")
	_popup_close_and_return_to_content()

func _show_member_picker(active_slot: int) -> void:
	"""Show bench member picker popup - LoadoutPanel pattern"""
	if not _gs: return

	# Prevent multiple popups
	if _active_popup and is_instance_valid(_active_popup):
		print("[StatusPanel] Popup already open, ignoring request")
		return

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
	print("[StatusPanel] Switch button - Active slot: %d, Bench IDs: %s" % [active_slot, bench_ids])

	if bench_ids.is_empty():
		# Show message: no bench members available (using Panel pattern)
		_show_no_bench_notice()
		return

	# Create popup panel using LoadoutPanel pattern
	var popup_panel: Panel = Panel.new()
	popup_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	popup_panel.z_index = 100
	add_child(popup_panel)

	# Set active popup immediately
	_active_popup = popup_panel

	# Create content container
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	popup_panel.add_child(vbox)

	# Title label
	var title: Label = Label.new()
	title.text = "Select Bench Member"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	# Instruction text
	var instruction: Label = Label.new()
	instruction.text = "Choose a member to swap into the active slot:"
	instruction.add_theme_font_size_override("font_size", 10)
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(instruction)

	# Item list
	var item_list: ItemList = ItemList.new()
	item_list.custom_minimum_size = Vector2(280, 150)
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(item_list)

	# Populate list with bench members
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

	# Add Back button
	var back_btn: Button = Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(_popup_cancel_switch)
	vbox.add_child(back_btn)

	# Auto-size panel - wait two frames for proper layout
	await get_tree().process_frame
	await get_tree().process_frame
	popup_panel.size = vbox.size + Vector2(20, 20)
	vbox.position = Vector2(10, 10)

	# Center popup on screen
	var viewport_size: Vector2 = get_viewport_rect().size
	popup_panel.position = (viewport_size - popup_panel.size) / 2.0
	print("[StatusPanel] Switch popup centered at: %s, size: %s" % [popup_panel.position, popup_panel.size])

	# Store metadata
	popup_panel.set_meta("_is_switch_popup", true)
	popup_panel.set_meta("_active_slot", active_slot)
	popup_panel.set_meta("_item_list", item_list)

	# Push popup to aPanelManager stack
	var panel_mgr = get_node_or_null("/root/aPanelManager")
	if panel_mgr:
		panel_mgr.push_panel(popup_panel)
		print("[StatusPanel] Pushed switch popup to aPanelManager stack")

	# Set state to POPUP_ACTIVE
	_nav_state = NavState.POPUP_ACTIVE

	# Select first item and grab focus
	if item_list.item_count > 0:
		item_list.select(0)
		await get_tree().process_frame
		item_list.grab_focus()

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

func _popup_accept_switch() -> void:
	"""User pressed A/Accept on switch popup - perform member swap"""
	if not _active_popup or not is_instance_valid(_active_popup):
		return

	var item_list = _active_popup.get_meta("_item_list", null)
	var active_slot = _active_popup.get_meta("_active_slot", -1)

	if not item_list or active_slot < 0:
		print("[StatusPanel] Switch popup missing metadata")
		_popup_cancel_switch()
		return

	var selected_items = item_list.get_selected_items()
	if selected_items.is_empty():
		print("[StatusPanel] No member selected")
		return

	var selected_idx = selected_items[0]
	var bench_member_id: String = String(item_list.get_item_metadata(selected_idx))

	print("[StatusPanel] Swapping slot %d with bench member: %s" % [active_slot, bench_member_id])

	# Close popup first
	_popup_close_and_return_to_content()

	# Perform swap
	_perform_swap(active_slot, bench_member_id)

func _popup_cancel_switch() -> void:
	"""User pressed Back on switch popup - close without swapping"""
	print("[StatusPanel] Switch popup cancelled")
	_popup_close_and_return_to_content()

func _popup_close_and_return_to_content() -> void:
	"""Close popup and return to CONTENT state"""
	if not _active_popup or not is_instance_valid(_active_popup):
		return

	print("[StatusPanel] Closing popup, returning to content mode")

	# Store popup reference and clear BEFORE popping
	var popup_to_close = _active_popup
	_active_popup = null

	# CRITICAL: Set state to CONTENT BEFORE popping
	_nav_state = NavState.CONTENT

	# Pop from panel manager
	var panel_mgr = get_node_or_null("/root/aPanelManager")
	if panel_mgr and panel_mgr.has_method("pop_panel"):
		panel_mgr.call("pop_panel")
		print("[StatusPanel] Popped switch popup from aPanelManager")

	# Free the popup
	if is_instance_valid(popup_to_close):
		popup_to_close.queue_free()

	# Restore focus to first button in content
	call_deferred("_navigate_to_content")

func _show_recovery_popup(member_id: String, member_name: String, hp: int, hp_max: int, mp: int, mp_max: int) -> void:
	"""Show recovery item selection popup - LoadoutPanel pattern"""
	# Prevent multiple popups
	if _active_popup and is_instance_valid(_active_popup):
		print("[StatusPanel] Popup already open, ignoring request")
		return

	# Get inventory system
	var inv_sys = get_node_or_null("/root/aInventorySystem")
	if not inv_sys:
		print("[StatusPanel] No inventory system found")
		return

	# Get recovery items from inventory by filtering item definitions
	var recovery_items: Array = []

	print("[StatusPanel] Using InventorySystem methods: get_item_defs, get_counts_dict, get_count")

	# Get all item definitions
	if inv_sys.has_method("get_item_defs"):
		var all_defs: Dictionary = inv_sys.call("get_item_defs")
		print("[StatusPanel] Total item definitions: %d" % all_defs.size())

		# Get item counts to check what we actually own
		var counts_dict: Dictionary = {}
		if inv_sys.has_method("get_counts_dict"):
			counts_dict = inv_sys.call("get_counts_dict")
			print("[StatusPanel] Total items in inventory: %d" % counts_dict.size())
			print("[StatusPanel] Inventory items: %s" % counts_dict.keys())

		# Filter by category "recovery" and check if we own the item
		for item_id in all_defs.keys():
			var def_data = all_defs[item_id]
			if typeof(def_data) == TYPE_DICTIONARY:
				var category = String(def_data.get("category", "")).to_lower()

				# Check if this is a recovery item
				if category == "recovery" or category.contains("recovery") or category.contains("heal") or category.contains("potion"):
					# Check if we own it
					var count = int(counts_dict.get(item_id, 0))
					if count > 0:
						recovery_items.append(item_id)
						print("[StatusPanel] ✓ Added recovery item: %s (category: '%s', count: %d)" % [item_id, category, count])
					else:
						print("[StatusPanel] - Found recovery def but not owned: %s (category: '%s')" % [item_id, category])

	print("[StatusPanel] Total recovery items found: %d" % recovery_items.size())

	# Create popup panel using LoadoutPanel pattern
	var popup_panel: Panel = Panel.new()
	popup_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	popup_panel.z_index = 100
	add_child(popup_panel)

	# Set active popup immediately
	_active_popup = popup_panel

	# Create content container
	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	popup_panel.add_child(vbox)

	# Title label
	var title: Label = Label.new()
	title.text = "Recovery - %s" % member_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	# Member status display
	var status_label: Label = Label.new()
	status_label.text = "HP: %d/%d  |  MP: %d/%d" % [hp, hp_max, mp, mp_max]
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)

	# Item list
	var item_list: ItemList = ItemList.new()
	item_list.custom_minimum_size = Vector2(280, 200)
	item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(item_list)

	# Populate list with recovery items
	if recovery_items.is_empty():
		item_list.add_item("No recovery items available")
		item_list.set_item_disabled(0, true)
	else:
		for item_id in recovery_items:
			if inv_sys.has_method("get_count") and inv_sys.has_method("get_item_def"):
				var count = inv_sys.call("get_count", item_id)
				var def_data = inv_sys.call("get_item_def", item_id)
				if typeof(def_data) == TYPE_DICTIONARY and count > 0:
					var item_name = String(def_data.get("name", item_id))
					var item_type = String(def_data.get("effect_type", "hp"))  # hp or mp
					item_list.add_item("%s (x%d)" % [item_name, count])
					item_list.set_item_metadata(item_list.item_count - 1, {"id": item_id, "type": item_type})
					print("[StatusPanel] Added to popup list: %s (x%d)" % [item_name, count])

	# Add Back button
	var back_btn: Button = Button.new()
	back_btn.text = "Back"
	back_btn.pressed.connect(_popup_cancel_recovery)
	vbox.add_child(back_btn)

	# Auto-size panel - wait two frames
	await get_tree().process_frame
	await get_tree().process_frame
	popup_panel.size = vbox.size + Vector2(20, 20)
	vbox.position = Vector2(10, 10)

	# Center popup on screen
	var viewport_size: Vector2 = get_viewport_rect().size
	popup_panel.position = (viewport_size - popup_panel.size) / 2.0
	print("[StatusPanel] Recovery popup centered at: %s, size: %s" % [popup_panel.position, popup_panel.size])

	# Store metadata
	popup_panel.set_meta("_is_recovery_popup", true)
	popup_panel.set_meta("_member_id", member_id)
	popup_panel.set_meta("_member_name", member_name)
	popup_panel.set_meta("_hp", hp)
	popup_panel.set_meta("_hp_max", hp_max)
	popup_panel.set_meta("_mp", mp)
	popup_panel.set_meta("_mp_max", mp_max)
	popup_panel.set_meta("_item_list", item_list)

	# Push popup to aPanelManager stack
	var panel_mgr = get_node_or_null("/root/aPanelManager")
	if panel_mgr:
		panel_mgr.push_panel(popup_panel)
		print("[StatusPanel] Pushed recovery popup to aPanelManager stack")

	# Set state to POPUP_ACTIVE
	_nav_state = NavState.POPUP_ACTIVE

	# Select first non-disabled item and grab focus
	if item_list.item_count > 0:
		var first_enabled = 0
		for i in range(item_list.item_count):
			if not item_list.is_item_disabled(i):
				first_enabled = i
				break
		item_list.select(first_enabled)
		await get_tree().process_frame
		item_list.grab_focus()

func _popup_accept_recovery() -> void:
	"""User pressed A/Accept on recovery popup - use selected item"""
	if not _active_popup or not is_instance_valid(_active_popup):
		return

	var item_list = _active_popup.get_meta("_item_list", null)
	var member_id = _active_popup.get_meta("_member_id", "")
	var member_name = _active_popup.get_meta("_member_name", "")
	var hp = _active_popup.get_meta("_hp", 0)
	var hp_max = _active_popup.get_meta("_hp_max", 0)
	var mp = _active_popup.get_meta("_mp", 0)
	var mp_max = _active_popup.get_meta("_mp_max", 0)

	if not item_list:
		print("[StatusPanel] Recovery popup missing item_list")
		_popup_cancel_recovery()
		return

	var selected_items = item_list.get_selected_items()
	if selected_items.is_empty():
		print("[StatusPanel] No item selected")
		return

	var selected_idx = selected_items[0]

	# Check if it's a disabled item (shouldn't happen but be safe)
	if item_list.is_item_disabled(selected_idx):
		print("[StatusPanel] Selected item is disabled")
		return

	var meta = item_list.get_item_metadata(selected_idx)
	if typeof(meta) != TYPE_DICTIONARY:
		print("[StatusPanel] Invalid metadata for selected item")
		return

	var item_id: String = String(meta.get("id", ""))
	var item_type: String = String(meta.get("type", "hp"))

	print("[StatusPanel] Using recovery item: %s (type: %s) on %s" % [item_id, item_type, member_name])

	# Close popup first
	_popup_close_and_return_to_content()

	# Use the item
	_use_recovery_item(member_id, member_name, item_id, item_type, hp, hp_max, mp, mp_max)

func _popup_cancel_recovery() -> void:
	"""User pressed Back on recovery popup - close without using item"""
	print("[StatusPanel] Recovery popup cancelled")
	_popup_close_and_return_to_content()

func _use_recovery_item(member_id: String, member_name: String, item_id: String, item_type: String, hp: int, hp_max: int, mp: int, mp_max: int) -> void:
	"""Use a recovery item on a party member"""
	# Check if already at max
	if item_type == "hp" and hp >= hp_max:
		var msg_popup := AcceptDialog.new()
		msg_popup.dialog_text = "%s is already at max HP." % member_name
		msg_popup.title = "Already at Max"
		add_child(msg_popup)
		msg_popup.popup_centered()
		msg_popup.confirmed.connect(func(): msg_popup.queue_free())
		return
	elif item_type == "mp" and mp >= mp_max:
		var msg_popup := AcceptDialog.new()
		msg_popup.dialog_text = "%s is already at max MP." % member_name
		msg_popup.title = "Already at Max"
		add_child(msg_popup)
		msg_popup.popup_centered()
		msg_popup.confirmed.connect(func(): msg_popup.queue_free())
		return

	# Use the item
	var inv_sys = get_node_or_null("/root/aInventorySystem")
	if inv_sys and inv_sys.has_method("use_item"):
		# Try to use item with target parameter
		var success = inv_sys.call("use_item", item_id, member_id)
		if success:
			print("[StatusPanel] Used %s on %s" % [item_id, member_name])
			_rebuild_party()  # Refresh display
		else:
			var error_popup := AcceptDialog.new()
			error_popup.dialog_text = "Failed to use item."
			error_popup.title = "Use Item Failed"
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
	# Select first tab when panel becomes visible
	if visible and _tab_list:
		# Defer to ensure ItemList is ready
		call_deferred("_grab_tab_list_focus")

	if not OS.is_debug_build(): return
	_dev_dump_profiles()

func _grab_tab_list_focus() -> void:
	"""Helper to grab focus on tab list"""
	if _tab_list and _tab_list.item_count > 0:
		_tab_list.select(0)
		_tab_list.grab_focus()

func _navigate_to_content() -> void:
	"""Navigate from tab list to first focusable button in content area"""
	print("[StatusPanel] _navigate_to_content called, current state: %s" % NavState.keys()[_nav_state])

	if not _party:
		print("[StatusPanel] ERROR: _party is null!")
		return

	# Find all buttons in the content area (recursively search children)
	var buttons: Array[Button] = []
	_find_buttons_recursive(_party, buttons)

	print("[StatusPanel] Found %d buttons in content area" % buttons.size())
	for i in range(buttons.size()):
		print("[StatusPanel]   Button %d: %s" % [i, buttons[i].text])

	# Focus the first button found
	if buttons.size() > 0:
		buttons[0].grab_focus()
		print("[StatusPanel] ✓ Navigated to content - focused first button: %s" % buttons[0].text)
	else:
		print("[StatusPanel] WARNING: No buttons found in content area")

func _find_buttons_recursive(node: Node, buttons: Array[Button]) -> void:
	"""Recursively find all Button nodes in a tree"""
	if node is Button:
		buttons.append(node as Button)

	for child in node.get_children():
		_find_buttons_recursive(child, buttons)

func _input(event: InputEvent) -> void:
	"""Handle controller input - LoadoutPanel pattern with state machine

	State Flow:
	  MENU → (Right) → CONTENT → (Recovery/Switch btn) → POPUP_ACTIVE
	  POPUP_ACTIVE → (Accept/Back) → CONTENT
	  CONTENT → (Left) → MENU
	  MENU → (Back) → Pop panel (exit StatusPanel)
	"""

	# STATE 1: POPUP_ACTIVE - Handle even when not visible (popup is on top in panel stack)
	if _nav_state == NavState.POPUP_ACTIVE:
		_handle_popup_input(event)
		# NOTE: _handle_popup_input decides which inputs to mark as handled
		return

	# Only handle other states when visible
	if not visible or not _tab_list:
		return

	# Check if we're in MENU_MAIN context
	if _ctrl_mgr and _ctrl_mgr.get_current_context() != _ctrl_mgr.InputContext.MENU_MAIN:
		return

	# STATE 2: MENU - Tab list navigation
	if _nav_state == NavState.MENU:
		_handle_menu_input(event)
		return

	# STATE 3: CONTENT - Content buttons navigation
	if _nav_state == NavState.CONTENT:
		_handle_content_input(event)
		return

## ─────────────────────── STATE 1: POPUP_ACTIVE ───────────────────────

func _handle_popup_input(event: InputEvent) -> void:
	"""Handle input when popup is active (switch, recovery, or notice popup)"""
	if event.is_action_pressed("menu_accept"):
		# Route to appropriate handler based on popup type
		if _active_popup and _active_popup.get_meta("_is_recovery_popup", false):
			_popup_accept_recovery()
		elif _active_popup and _active_popup.get_meta("_is_switch_popup", false):
			_popup_accept_switch()
		elif _active_popup and _active_popup.get_meta("_is_notice_popup", false):
			_popup_close_notice()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_back"):
		# Cancel popup - all popups can be cancelled with back
		if _active_popup and _active_popup.get_meta("_is_recovery_popup", false):
			_popup_cancel_recovery()
		elif _active_popup and _active_popup.get_meta("_is_switch_popup", false):
			_popup_cancel_switch()
		elif _active_popup and _active_popup.get_meta("_is_notice_popup", false):
			_popup_close_notice()
		get_viewport().set_input_as_handled()
	# UP/DOWN navigation is NOT handled - let ItemList/Button handle it

## ─────────────────────── STATE 2: MENU ───────────────────────

func _handle_menu_input(event: InputEvent) -> void:
	"""Handle input in MENU state - tab list navigation"""
	# Handle RIGHT: navigate to content (and hide menu)
	if event.is_action_pressed("move_right"):
		# If tab list has focus, navigate to first button in content area
		if _tab_list.has_focus():
			print("[StatusPanel] MENU → CONTENT transition (hiding menu)")
			_nav_state = NavState.CONTENT
			# Hide menu when transitioning to content
			if _menu_visible:
				_hide_menu()
			_navigate_to_content()
			get_viewport().set_input_as_handled()
			return

	# Handle LEFT: show menu if hidden
	elif event.is_action_pressed("move_left"):
		if not _menu_visible:
			print("[StatusPanel] Showing menu (MENU state, LEFT pressed)")
			_show_menu()
			get_viewport().set_input_as_handled()
			return

## ─────────────────────── STATE 3: CONTENT ───────────────────────

func _handle_content_input(event: InputEvent) -> void:
	"""Handle input in CONTENT state - button navigation"""
	# Handle LEFT: navigate back to menu (and show menu)
	if event.is_action_pressed("move_left"):
		print("[StatusPanel] CONTENT → MENU transition (showing menu)")
		_nav_state = NavState.MENU
		# Show menu when transitioning back to menu
		if not _menu_visible:
			_show_menu()
		_tab_list.grab_focus()
		get_viewport().set_input_as_handled()
		return

func _unhandled_input(event: InputEvent) -> void:
	"""Handle A button activation for tabs and buttons"""
	# Don't handle if in popup state
	if _nav_state == NavState.POPUP_ACTIVE:
		return

	# Only handle when visible
	if not visible or not _tab_list:
		return

	# Check if we're in MENU_MAIN context
	if _ctrl_mgr and _ctrl_mgr.get_current_context() != _ctrl_mgr.InputContext.MENU_MAIN:
		return

	# Handle A button
	if event.is_action_pressed("menu_accept"):
		print("[StatusPanel] A button pressed, state: %s" % NavState.keys()[_nav_state])

		# STATE: CONTENT - Activate focused button (Recovery/Switch)
		if _nav_state == NavState.CONTENT:
			var focused_control = get_viewport().gui_get_focus_owner()
			print("[StatusPanel] Focused control: %s (is Button: %s)" % [
				focused_control.name if focused_control else "null",
				focused_control is Button
			])
			if focused_control is Button:
				print("[StatusPanel] ✓ Activating focused button: %s" % (focused_control as Button).text)
				(focused_control as Button).emit_signal("pressed")
				get_viewport().set_input_as_handled()
				return
			else:
				print("[StatusPanel] WARNING: A pressed but no button has focus")

		# STATE: MENU - Activate selected tab
		elif _nav_state == NavState.MENU:
			if _tab_list.has_focus():
				var selected_items = _tab_list.get_selected_items()
				if selected_items.size() > 0:
					var index = selected_items[0]
					print("[StatusPanel] A button - confirming tab selection: %d" % index)
					_on_tab_item_activated(index)
					get_viewport().set_input_as_handled()

	# Debug key handling (F9 to dump profiles)
	if not OS.is_debug_build(): return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var ek := event as InputEventKey
		if ek.keycode == KEY_F9:
			_dev_dump_profiles()

func _hide_menu() -> void:
	"""Slide menu to the left (hide it) and show vertical MENU label"""
	if not _tab_column or not _menu_visible:
		return

	_menu_visible = false

	# Cancel any ongoing tween
	if _menu_tween and _menu_tween.is_running():
		_menu_tween.kill()

	# Create new tween for smooth slide-out animation
	_menu_tween = create_tween()
	_menu_tween.set_ease(Tween.EASE_OUT)
	_menu_tween.set_trans(Tween.TRANS_CUBIC)

	# Slide menu column to the left (hide it)
	# custom_minimum_size.x is 160, so we move it -176 (160 + 16 separation)
	_menu_tween.tween_property(_tab_column, "position:x", -176.0, 0.3)
	_menu_tween.parallel().tween_property(_tab_column, "modulate:a", 0.0, 0.3)

	# Show vertical MENU box (fade in)
	if _vertical_menu_box:
		_menu_tween.parallel().tween_property(_vertical_menu_box, "modulate:a", 1.0, 0.3)

	# Center the status panels by shifting root container left
	# Move left by 88 pixels (half of 176) to center: offset_left from 16 to -72
	if _root_container:
		_menu_tween.parallel().tween_property(_root_container, "position:x", -88.0, 0.3)

	# After animation completes, make menu non-interactive
	_menu_tween.tween_callback(func():
		_tab_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	)

	print("[StatusPanel] Menu hidden, vertical label shown, panels centered")

func _show_menu() -> void:
	"""Slide menu back from the left (show it) and hide vertical MENU label"""
	if not _tab_column or _menu_visible:
		return

	_menu_visible = true

	# Make interactive immediately
	_tab_column.mouse_filter = Control.MOUSE_FILTER_STOP

	# Cancel any ongoing tween
	if _menu_tween and _menu_tween.is_running():
		_menu_tween.kill()

	# Create new tween for smooth slide-in animation
	_menu_tween = create_tween()
	_menu_tween.set_ease(Tween.EASE_OUT)
	_menu_tween.set_trans(Tween.TRANS_CUBIC)

	# Slide menu column back to original position (x = 0)
	_menu_tween.tween_property(_tab_column, "position:x", 0.0, 0.3)
	_menu_tween.parallel().tween_property(_tab_column, "modulate:a", 1.0, 0.3)

	# Hide vertical MENU box (fade out)
	if _vertical_menu_box:
		_menu_tween.parallel().tween_property(_vertical_menu_box, "modulate:a", 0.0, 0.3)

	# Restore status panels to original position
	# Move root container back to position x = 0
	if _root_container:
		_menu_tween.parallel().tween_property(_root_container, "position:x", 0.0, 0.3)

	# After animation completes, restore focus to tab list
	_menu_tween.tween_callback(func():
		call_deferred("_grab_tab_list_focus")
	)

	print("[StatusPanel] Menu shown, vertical label hidden, panels restored")

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
