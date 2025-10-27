## ═══════════════════════════════════════════════════════════════════════════
## Main - Primary Game Scene Controller
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   The main gameplay scene controller that manages the game menu overlay,
##   time advancement, header display (date/time), cheat tools, and integration
##   of all major systems. This is the hub scene players see during gameplay.
##
## RESPONSIBILITIES:
##   • Game menu overlay (open/close with ui_menu input)
##   • Phone menu overlay (open/close with ui_phone input)
##   • Time advancement controls (Advance Phase, Reset Week)
##   • Date/time header display (current day/phase)
##   • Cheat tool UI:
##     - Toggle ALL cheats with 'I' key (hides/shows entire cheat container)
##     - Toggle party/XP/SXP controls with 'C' key
##     - Toggle status effects cheat bar with 'O' key
##     - Party management (add/remove members)
##     - XP/Level cheats (hero and allies)
##     - SXP cheats (stat experience points)
##     - Item loading from CSV
##   • Save menu access button
##   • Training menu access button
##   • World spots status display
##
## HEADER DISPLAY:
##   • Current date (from CalendarSystem)
##   • Current time phase (Morning/Afternoon/Evening)
##   • Advance Phase button
##   • Reset Week button (for testing weekly systems)
##
## CHEAT TOOLS (Dev Mode):
##   Party Management:
##   • Add member to party/bench from roster
##   • Remove member from party
##   • Move member to bench
##
##   Level/XP:
##   • Add XP to selected member
##   • Set hero level directly
##   • Add XP to hero
##
##   Stats (SXP):
##   • Add SXP to specific stat (BRW/MND/TPO/VTL/FCS)
##   • Works for both hero and selected ally
##
## CONNECTED SYSTEMS (Autoloads):
##   • CalendarSystem - Time advancement, date/phase display
##   • GameState - Party roster, game state
##   • StatsSystem - XP/SXP management
##   • InventorySystem - Item loading from CSV
##   • SigilSystem - Sigil management
##   • PerkSystem - Perk unlocks
##   • WorldSpotsSystem - Location management
##   • CombatProfileSystem - HP/MP tracking
##
## OVERLAY SCENES:
##   • GameMenu - Main menu (Status, Loadout, Items, Perks, etc.)
##   • PhoneMenu - In-game phone interface
##   • SaveMenu - Save game interface
##   • TrainingMenu - Stat training interface
##
## CSV DATA SOURCES:
##   • res://data/items/items.csv - Item definitions (cheat load)
##   • res://data/actors/party.csv - Party roster (cheat dropdown)
##
## KEY METHODS:
##   • _on_advance_pressed() - Advance time phase
##   • _on_reset_week_pressed() - Reset weekly systems
##   • _toggle_game_menu() - Open/close game menu overlay
##   • _toggle_phone_menu() - Open/close phone menu overlay
##   • _on_add_party_pressed() - Cheat: add member to party
##   • _on_add_xp_pressed() - Cheat: grant XP to member
##   • _on_add_sxp_pressed() - Cheat: grant SXP to stat
##
## ═══════════════════════════════════════════════════════════════════════════

extends Control

# ---- Autoloads (PartySystem removed) ----
const CALENDAR_PATH      := "/root/aCalendarSystem"
const STATS_PATH         := "/root/aStatsSystem"
const CSV_PATH           := "/root/aCSVLoader"
const WORLD_SPOTS_PATH   := "/root/aWorldSpotsSystem"
const GS_PATH            := "/root/aGameState"
const PERK_PATH          := "/root/aPerkSystem"
const INV_PATH           := "/root/aInventorySystem"
const SIGIL_PATH         := "/root/aSigilSystem"

# Combat profiles (Status panel reads from here)
const CPS_CANDIDATE_PATHS := [
	"/root/aCombatProfileSystem",
	"/root/CombatProfileSystem",
	"/root/combatprofilesystem"
]

# ---- Optional overlay scenes ----
const GAME_MENU_SCENE  := "res://scenes/main_menu/GameMenu.tscn"
const PHONE_MENU_SCENE := "res://scenes/ui/phone/PhoneMenu.tscn"

# ---- Input actions ----
const INPUT_MENU_ACTION  := "ui_menu"
const INPUT_PHONE_ACTION := "ui_phone"

# ---- Data paths ----
const ITEMS_CSV    := "res://data/items/items.csv"
const ITEMS_KEY_ID := "item_id"

# Roster CSV (optional)
const PARTY_CSV_CANDIDATES := [
	"res://data/party/party.csv",
	"res://data/Party.csv",
	"res://data/party.csv",
	"res://data/characters/party.csv",
	"res://data/actors/party.csv",
	"res://data/actors.csv"
]
const PARTY_ID_KEYS   := ["actor_id","id","actor","member_id"]
const PARTY_NAME_KEYS := ["name","display_name","disp_name"]

# ---- Header refs ----
@onready var date_label: Label         = $MarginContainer/Root/DateLabel
@onready var phase_label: Label        = $MarginContainer/Root/PhaseLabel
@onready var cheat_container: VBoxContainer = $MarginContainer/Root/CheatContainer
@onready var advance_btn: Button       = $MarginContainer/Root/CheatContainer/HBoxContainer/AdvanceBtn
@onready var reset_btn: Button         = $MarginContainer/Root/CheatContainer/HBoxContainer/ResetWeekBtn
@onready var load_btn: Button          = $MarginContainer/Root/CheatContainer/HBoxContainer2/LoadItemsBtn
@onready var items_status: Label       = $MarginContainer/Root/CheatContainer/HBoxContainer2/ItemsStatus
@onready var open_training_btn: Button = $MarginContainer/Root/CheatContainer/HBoxContainer3/OpenTrainingBtn
@onready var spots_status: Label       = $MarginContainer/Root/CheatContainer/HBoxContainer3/SpotsStatus

# ---- Cheat area container (toggle with C) ----
var _cheat_root: VBoxContainer = null

# ---- Party / LXP / SXP refs ----
var _roster_pick: OptionButton = null
var _member_id_le: LineEdit = null
var _btn_add_party: Button = null
var _btn_rem_party: Button = null
var _btn_to_bench: Button = null

var _spin_xp: SpinBox = null
var _btn_add_xp: Button = null

var _stat_pick: OptionButton = null
var _spin_sxp: SpinBox = null
var _btn_add_sxp: Button = null

# -------- Hero row (runtime-built) --------
var _hero_lvl_spin: SpinBox       = null
var _btn_hero_set_lvl: Button     = null
var _hero_xp_spin: SpinBox        = null
var _btn_hero_add_xp: Button      = null
var _hero_stat_pick: OptionButton = null
var _hero_sxp_spin: SpinBox       = null
var _btn_hero_add_sxp: Button     = null

# -------- Sigil row (runtime-built) --------
var _sigil_pick: OptionButton = null
var _sigil_xp_spin: SpinBox   = null
var _btn_add_sigil_xp: Button = null

# ---- Systems ----
var calendar: Node = null
var stats: Node    = null
var csv: Node      = null
var gs: Node       = null
var perk: Node     = null
var inv: Node      = null
var _cps: Node     = null
var _sig: Node     = null

# ---- Local caches ----
var _party_defs_by_id: Dictionary = {}
var _party_csv_path: String = ""

# Overlays
var _game_menu: Control = null
var _phone_menu: Control = null
var _status_cheat_bar: Control = null

# ---------- helpers: canonical hero id ----------
func _hero_id() -> String:
	return "hero"

func _find_cps() -> Node:
	for p in CPS_CANDIDATE_PATHS:
		var n: Node = get_node_or_null(p)
		if n: return n
	return null

# --- Dorm hooks (new) ----------------------------------------------------------
var _prelock_layout: Dictionary = {}  # room_id -> aid (snapshot after Accept Plan)

func _reparent_ui_to_canvas_layers() -> void:
	"""Reparent UI elements to CanvasLayers so they stay fixed when camera moves"""
	# Get the UI elements that need to be fixed
	var margin_container: MarginContainer = get_node_or_null("MarginContainer") as MarginContainer
	var overlays: Control = get_node_or_null("Overlays") as Control

	if margin_container:
		# Create CanvasLayer for main UI
		var ui_layer := CanvasLayer.new()
		ui_layer.name = "UILayer"
		ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS  # Continue processing when paused
		add_child(ui_layer)

		# Reparent MarginContainer to UILayer
		margin_container.reparent(ui_layer)

	if overlays:
		# Create CanvasLayer for overlays (menus)
		var overlays_layer := CanvasLayer.new()
		overlays_layer.name = "OverlaysLayer"
		overlays_layer.process_mode = Node.PROCESS_MODE_ALWAYS  # Continue processing when paused
		add_child(overlays_layer)

		# Reparent Overlays to OverlaysLayer
		overlays.reparent(overlays_layer)

func _ready() -> void:
	# Allow input processing even when game is paused (for menu toggle)
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Fix UI to stay in place with camera movement
	_reparent_ui_to_canvas_layers()

	# Ensure GameWorld pauses when game is paused
	var game_world: Node2D = get_node_or_null("GameWorld") as Node2D
	if game_world:
		game_world.process_mode = Node.PROCESS_MODE_PAUSABLE

	# Systems
	calendar = get_node_or_null(CALENDAR_PATH)
	stats    = get_node_or_null(STATS_PATH)
	csv      = get_node_or_null(CSV_PATH)
	gs       = get_node_or_null(GS_PATH)
	perk     = get_node_or_null(PERK_PATH)
	inv      = get_node_or_null(INV_PATH)
	_cps     = _find_cps()
	_sig     = get_node_or_null(SIGIL_PATH)

	# Cheat menu nodes (optional - may not exist in scene)
	_cheat_root     = get_node_or_null("MarginContainer/Root/CheatContainer/ItemsCheatBar/CheatRoot")
	_roster_pick    = get_node_or_null("MarginContainer/Root/CheatContainer/ItemsCheatBar/CheatRoot/PartyRow/RosterPick")
	_member_id_le   = get_node_or_null("MarginContainer/Root/CheatContainer/ItemsCheatBar/CheatRoot/PartyRow/MemberId")
	_btn_add_party  = get_node_or_null("MarginContainer/Root/CheatContainer/ItemsCheatBar/CheatRoot/PartyRow/BtnAddParty")
	_btn_rem_party  = get_node_or_null("MarginContainer/Root/CheatContainer/ItemsCheatBar/CheatRoot/PartyRow/BtnRemoveParty")
	_btn_to_bench   = get_node_or_null("MarginContainer/Root/CheatContainer/ItemsCheatBar/CheatRoot/PartyRow/BtnToBench")
	_spin_xp        = get_node_or_null("MarginContainer/Root/CheatContainer/ItemsCheatBar/CheatRoot/LxpRow/SpinXP")
	_btn_add_xp     = get_node_or_null("MarginContainer/Root/CheatContainer/ItemsCheatBar/CheatRoot/LxpRow/BtnAddXP")
	_stat_pick      = get_node_or_null("MarginContainer/Root/CheatContainer/ItemsCheatBar/CheatRoot/SxpRow/StatPick")
	_spin_sxp       = get_node_or_null("MarginContainer/Root/CheatContainer/ItemsCheatBar/CheatRoot/SxpRow/SpinSXP")
	_btn_add_sxp    = get_node_or_null("MarginContainer/Root/CheatContainer/ItemsCheatBar/CheatRoot/SxpRow/BtnAddSXP")

	# Overlays shouldn't block input
	var overlays: Control = get_node_or_null("OverlaysLayer/Overlays") as Control
	if overlays:
		overlays.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Optional world-spots
	var wss: Node = get_node_or_null(WORLD_SPOTS_PATH)
	if wss and wss.has_method("load_spots"):
		wss.call("load_spots")

	# Header buttons
	if advance_btn:       advance_btn.pressed.connect(_on_advance_pressed)
	if reset_btn:         reset_btn.pressed.connect(_on_reset_week_pressed)
	if load_btn:          load_btn.pressed.connect(_on_load_items_pressed)
	if open_training_btn: open_training_btn.pressed.connect(_on_open_training)

	# Party / LXP / SXP signals
	if _btn_add_party: _btn_add_party.pressed.connect(_on_add_to_party)
	if _btn_rem_party: _btn_rem_party.pressed.connect(_on_remove_from_party)
	if _btn_to_bench:  _btn_to_bench.pressed.connect(_on_move_to_bench)
	if _roster_pick:   _roster_pick.item_selected.connect(_on_roster_pick_selected)
	if _btn_add_xp:    _btn_add_xp.pressed.connect(_on_add_xp)
	if _btn_add_sxp:   _btn_add_sxp.pressed.connect(_on_add_sxp)

	# Cosmetics
	_style_option_button(_roster_pick)
	_style_option_button(_stat_pick)

	# --- Build extra rows ---
	_ensure_hero_row()
	_style_option_button(_hero_stat_pick)
	_populate_hero_stat_picker()
	_refresh_hero_row()

	_ensure_sigil_row()
	_style_option_button(_sigil_pick)
	_refresh_sigil_picker()

	# Populate
	_populate_stat_picker()
	_refresh_roster_picker()
	_refresh_ui()
	_refresh_spots_status()

	# Calendar signals
	if calendar:
		if calendar.has_signal("phase_advanced"): calendar.connect("phase_advanced", Callable(self, "_on_calendar_updated"))
		if calendar.has_signal("day_advanced"):   calendar.connect("day_advanced",   Callable(self, "_on_calendar_updated"))
		if calendar.has_signal("week_reset"):     calendar.connect("week_reset",     Callable(self, "_on_week_reset"))
		if calendar.has_signal("advance_blocked") and not calendar.is_connected("advance_blocked", Callable(self, "_on_advance_blocked")):
			calendar.connect("advance_blocked", Callable(self, "_on_advance_blocked"))

	# Also listen to GS relay (cheats/UI might go through it)
	if gs and gs.has_signal("advance_blocked") and not gs.is_connected("advance_blocked", Callable(self, "_on_advance_blocked")):
		gs.connect("advance_blocked", Callable(self, "_on_advance_blocked"))

	# Shortcuts
	set_process_unhandled_input(true)

	# ---- Dorm hooks: auto-open, plan snapshot, saturday popup -----------------
	var ds := get_node_or_null("/root/aDormSystem")
	if ds:
		# Auto-open Dorms tab when a new Common occupant is added
		if ds.has_signal("common_added") and not ds.is_connected("common_added", Callable(self, "_on_dorms_common_added")):
			ds.connect("common_added", Callable(self, "_on_dorms_common_added"))
		# Snapshot layout right after plan is locked (for Saturday diff)
		if ds.has_signal("plan_changed") and not ds.is_connected("plan_changed", Callable(self, "_on_dorms_plan_changed")):
			ds.connect("plan_changed", Callable(self, "_on_dorms_plan_changed"))
		# Show results popup when DormsSystem applies moves on Saturday
		# Prefer v2 signal (includes explicit moves); fall back to legacy if v2 doesn't exist
		if ds.has_signal("saturday_applied_v2"):
			if not ds.is_connected("saturday_applied_v2", Callable(self, "_on_dorms_saturday_applied_v2")):
				ds.connect("saturday_applied_v2", Callable(self, "_on_dorms_saturday_applied_v2"))
		elif ds.has_signal("saturday_applied"):
			if not ds.is_connected("saturday_applied", Callable(self, "_on_dorms_saturday_applied")):
				ds.connect("saturday_applied", Callable(self, "_on_dorms_saturday_applied"))

	# DEBUG: Auto-give bind items for testing capture system
	_give_test_bind_items()

# ---------- Input ----------
func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo(): return
	# Toggle ALL cheats with "i" key
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I:
		if cheat_container: cheat_container.visible = not cheat_container.visible
		get_viewport().set_input_as_handled()
		return
	# Toggle CheatRoot (party/XP/SXP controls) with "C" key
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_C:
		if _cheat_root: _cheat_root.visible = not _cheat_root.visible
		get_viewport().set_input_as_handled()
		return
	# Toggle StatusEffectCheatBar with "O" key
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_O:
		_toggle_status_cheat_bar()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(INPUT_MENU_ACTION):
		_toggle_game_menu()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(INPUT_PHONE_ACTION):
		_toggle_phone_menu()
		get_viewport().set_input_as_handled()
		return

func _toggle_game_menu() -> void:
	if _game_menu and is_instance_valid(_game_menu):
		# About to hide? block if Dorms has unplaced occupants
		if _game_menu.visible and not _menu_can_close():
			return
		_game_menu.visible = not _game_menu.visible
		# Pause/unpause the game based on menu visibility
		get_tree().paused = _game_menu.visible
		return
	if not ResourceLoader.exists(GAME_MENU_SCENE): return
	var ps: PackedScene = load(GAME_MENU_SCENE) as PackedScene
	if ps == null: return
	_game_menu = ps.instantiate() as Control
	_game_menu.name = "GameMenu"
	_game_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_game_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	var parent: Node = get_node_or_null("OverlaysLayer/Overlays")
	if parent == null: parent = self
	parent.add_child(_game_menu)
	_game_menu.visible = true
	_game_menu.move_to_front()
	# Pause the game when menu is opened
	get_tree().paused = true

func _toggle_phone_menu() -> void:
	if _phone_menu and is_instance_valid(_phone_menu):
		_phone_menu.visible = not _phone_menu.visible
		# Pause/unpause the game based on menu visibility
		get_tree().paused = _phone_menu.visible
		return
	if not ResourceLoader.exists(PHONE_MENU_SCENE): return
	var ps: PackedScene = load(PHONE_MENU_SCENE) as PackedScene
	if ps == null: return
	_phone_menu = ps.instantiate() as Control
	_phone_menu.name = "PhoneMenu"
	_phone_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_phone_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	_phone_menu.top_level = true
	_phone_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	var parent: Node = get_node_or_null("OverlaysLayer/Overlays")
	if parent == null: parent = self
	parent.add_child(_phone_menu)
	_phone_menu.visible = true
	_phone_menu.move_to_front()
	# Pause the game when menu is opened
	get_tree().paused = true

func _toggle_status_cheat_bar() -> void:
	if _status_cheat_bar and is_instance_valid(_status_cheat_bar):
		_status_cheat_bar.visible = not _status_cheat_bar.visible
		return
	# Create StatusEffectCheatBar instance (runtime-built UI)
	var script_path := "res://scripts/dev/StatusEffectCheatBar.gd"
	if not ResourceLoader.exists(script_path): return
	var script: Script = load(script_path) as Script
	if script == null: return
	_status_cheat_bar = (script.new() as Control)
	_status_cheat_bar.name = "StatusEffectCheatBar"
	_status_cheat_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_status_cheat_bar.process_mode = Node.PROCESS_MODE_ALWAYS
	# Center the panel (increased size to fit HP/MP controls)
	_status_cheat_bar.set_anchors_preset(Control.PRESET_CENTER)
	_status_cheat_bar.offset_left = -200
	_status_cheat_bar.offset_top = -250
	_status_cheat_bar.offset_right = 200
	_status_cheat_bar.offset_bottom = 250
	var parent: Node = get_node_or_null("OverlaysLayer/Overlays")
	if parent == null: parent = self
	parent.add_child(_status_cheat_bar)
	_status_cheat_bar.visible = true
	_status_cheat_bar.move_to_front()

# ---------- Header ----------
func _refresh_ui() -> void:
	var cal: Node = get_node_or_null("/root/aCalendarSystem")
	var date_text := "—"
	var phase_text := "—"
	if cal:
		if cal.has_method("hud_label"):
			date_text = String(cal.call("hud_label")) # "Monday — May 10 — Morning"
			phase_text = String(cal.call("get_phase_name"))
		elif cal.has_method("get_date_string"):
			date_text = String(cal.call("get_date_string"))
			phase_text = String(cal.call("get_phase_name"))

	date_label.text  = date_text
	phase_label.text = phase_text

func _refresh_spots_status() -> void:
	var count: int = 0
	var wss: Node = get_node_or_null(WORLD_SPOTS_PATH)
	if wss and wss.has_method("get_available_spots"):
		var v: Variant = wss.call("get_available_spots")
		if typeof(v) == TYPE_ARRAY:
			count = (v as Array).size()
	spots_status.text = "Spots: %d" % count

func _on_calendar_updated(_arg: Variant = null) -> void:
	_refresh_ui()
	_refresh_spots_status()

func _on_week_reset() -> void:
	_refresh_ui()

func _on_advance_pressed() -> void:
	# Route through GameState so it can block cleanly
	if gs and gs.has_method("try_advance_phase"):
		gs.call("try_advance_phase")
	elif calendar and calendar.has_method("advance_phase"): # fallback
		calendar.call("advance_phase")
	_refresh_ui()

func _on_reset_week_pressed() -> void:
	if stats and stats.has_method("reset_week"):
		stats.call("reset_week")
		items_status.text = "Week reset."

func _on_load_items_pressed() -> void:
	if csv and csv.has_method("load_csv"):
		var table: Dictionary = {}
		var v: Variant = csv.call("load_csv", ITEMS_CSV, ITEMS_KEY_ID)
		if typeof(v) == TYPE_DICTIONARY: table = (v as Dictionary)
		items_status.text = "Items: %s" % (str(table.size()) if not table.is_empty() else "(failed)")

func _on_open_training() -> void: pass

func _style_option_button(ob: OptionButton) -> void:
	if ob == null: return
	ob.add_theme_font_size_override("font_size", 11)
	var pm: PopupMenu = ob.get_popup()
	if pm:
		pm.add_theme_font_size_override("font_size", 11)
		pm.max_size = Vector2i(320, 300)

# ---------- Party ----------
func _on_roster_pick_selected(_index: int) -> void:
	_refresh_sigil_picker()

func _member_id_from_ui() -> String:
	if _roster_pick:
		var idx: int = _roster_pick.get_selected()
		if idx >= 0:
			var md: Variant = _roster_pick.get_item_metadata(idx)
			if md == null: return _hero_id()
			return str(md)
	if _member_id_le and _member_id_le.text.strip_edges() != "":
		return _member_id_le.text.strip_edges()
	return _hero_id()

func _on_add_to_party() -> void:
	var mid: String = _member_id_from_ui()
	if mid == "": return
	if gs and gs.has_method("add_member"):
		gs.call("add_member", mid)
	else:
		var party_arr: Array = []
		if gs and gs.has_method("get"):
			var v: Variant = gs.get("party")
			if typeof(v) == TYPE_ARRAY: party_arr = (v as Array)
		if not party_arr.has(mid):
			party_arr.append(mid)
			if gs and gs.has_method("set"): gs.set("party", party_arr)
	_emit_party_changed()
	_refresh_roster_picker()
	_refresh_sigil_picker()

func _on_remove_from_party() -> void:
	var mid: String = _member_id_from_ui()
	if mid == "": return
	if gs and gs.has_method("remove_member"):
		gs.call("remove_member", mid)
	else:
		if gs and gs.has_method("get") and gs.has_method("set"):
			var party_arr: Array = []
			var v: Variant = gs.get("party")
			if typeof(v) == TYPE_ARRAY: party_arr = (v as Array)
			if party_arr.has(mid):
				party_arr.erase(mid)
				gs.set("party", party_arr)
	_emit_party_changed()
	_refresh_roster_picker()
	_refresh_sigil_picker()

func _on_move_to_bench() -> void:
	var mid: String = _member_id_from_ui()
	if mid == "": return
	if gs and gs.has_method("get") and gs.has_method("set"):
		var party_arr: Array = []
		var v: Variant = gs.get("party")
		if typeof(v) == TYPE_ARRAY: party_arr = (v as Array)
		if party_arr.has(mid):
			party_arr.erase(mid)
			gs.set("party", party_arr)
		var bench_arr: Array = []
		var b: Variant = gs.get("bench")
		if typeof(b) == TYPE_ARRAY: bench_arr = (b as Array)
		if not bench_arr.has(mid): bench_arr.append(mid)
		gs.set("bench", bench_arr)
	_emit_party_changed()
	_refresh_roster_picker()
	_refresh_sigil_picker()

func _emit_party_changed() -> void:
	if gs and gs.has_signal("party_changed"):
		gs.emit_signal("party_changed")

func _refresh_roster_picker() -> void:
	if _roster_pick == null: return
	_roster_pick.clear()

	_party_defs_by_id.clear()
	_party_csv_path = ""
	for p in PARTY_CSV_CANDIDATES:
		if ResourceLoader.exists(p):
			_party_csv_path = p
			break

	# Prefer CSV roster if present (nice labels)
	if _party_csv_path != "" and csv and csv.has_method("load_csv"):
		for id_key in PARTY_ID_KEYS:
			var loaded_v: Variant = csv.call("load_csv", _party_csv_path, String(id_key))
			if typeof(loaded_v) == TYPE_DICTIONARY and (loaded_v as Dictionary).size() > 0:
				_party_defs_by_id = (loaded_v as Dictionary)
				break

	if not _party_defs_by_id.is_empty():
		var ids_any: Array = _party_defs_by_id.keys()
		ids_any.sort()
		for id_any in ids_any:
			var rid: String = String(id_any)
			var row: Dictionary = _party_defs_by_id.get(rid, {}) as Dictionary
			var disp: String = _extract_display_from_row(row, rid)
			_roster_pick.add_item(disp)
			_roster_pick.set_item_metadata(_roster_pick.get_item_count() - 1, rid)
		return

	# Otherwise show GameState-known members
	var list_ids: Array[String] = _collect_all_known_members()
	for rid2 in list_ids:
		_roster_pick.add_item(rid2.capitalize())
		_roster_pick.set_item_metadata(_roster_pick.get_item_count() - 1, rid2)

func _extract_display_from_row(row: Dictionary, rid: String) -> String:
	var disp: String = ""
	for k in PARTY_NAME_KEYS:
		if row.has(k) and typeof(row[k]) == TYPE_STRING:
			var s: String = String(row[k]).strip_edges()
			if s != "":
				disp = s
				break
	if disp == "": disp = rid
	return disp

func _collect_all_known_members() -> Array[String]:
	var out: Array[String] = []
	# Party + bench from GameState
	if gs and gs.has_method("get"):
		var p: Variant = gs.get("party")
		if typeof(p) == TYPE_ARRAY:
			for s in (p as Array): out.append(String(s))
		var b: Variant = gs.get("bench")
		if typeof(b) == TYPE_ARRAY:
			for s2 in (b as Array):
				var t: String = String(s2)
				if not out.has(t): out.append(t)
	# Always include hero
	if not out.has("hero"):
		out.append("hero")
	out.sort()
	return out

# ---------- LXP ----------
func _on_add_xp() -> void:
	if _spin_xp == null: return
	var amount: int = int(_spin_xp.value)
	if amount <= 0: return
	_grant_xp_to_member(_member_id_from_ui(), amount)

func _xp_to_next_level(level: int) -> int:
	return 120 + 30 * level + 6 * level * level

func _grant_xp_to_member(member_id: String, amount: int) -> void:
	if amount <= 0: return
	# Prefer StatsSystem API
	if stats and stats.has_method("add_xp"):
		stats.call("add_xp", member_id, amount)
	else:
		# Fallback: simple local leveling (rarely used)
		var level: int = _get_member_level(member_id)
		var pool: int = amount
		while level < 99 and pool >= _xp_to_next_level(level):
			pool -= _xp_to_next_level(level)
			level += 1
		_set_member_level_exact(member_id, level)
	_emit_stats_changed()
	_refresh_cps(member_id)

# ---------- SXP ----------
func _populate_stat_picker() -> void:
	if _stat_pick == null: return
	_stat_pick.clear()
	for s in ["BRW","MND","TPO","VTL","FCS"]:
		_stat_pick.add_item(s)
		_stat_pick.set_item_metadata(_stat_pick.get_item_count() - 1, s)
	_stat_pick.select(0)

func _on_add_sxp() -> void:
	if _stat_pick == null or _spin_sxp == null: return
	var idx: int = _stat_pick.get_selected()
	if idx < 0: return
	var stat_id: String = String(_stat_pick.get_item_metadata(idx))
	var amount: int = int(_spin_sxp.value)
	if amount <= 0: return
	_add_sxp_to_member(_member_id_from_ui(), stat_id, amount)

func _party_progress() -> Dictionary:
	if stats == null: return {}
	var v: Variant = stats.get("_party_progress")
	return (v as Dictionary) if typeof(v) == TYPE_DICTIONARY else {}

func _save_party_progress(all: Dictionary) -> void:
	if stats and stats.has_method("set"):
		stats.set("_party_progress", all)

func _add_sxp_to_member(member_id: String, stat_id: String, amount: int) -> void:
	if amount <= 0: return
	stat_id = stat_id.strip_edges().to_upper()

	# Prefer StatsSystem API (handles fatigue + signals)
	if stats and (stats.has_method("add_sxp_to_member") or stats.has_method("add_member_sxp")):
		if stats.has_method("add_sxp_to_member"):
			stats.call("add_sxp_to_member", member_id, stat_id, amount)
		else:
			stats.call("add_member_sxp", member_id, stat_id, amount)
	else:
		# Fallback: write into StatsSystem._party_progress
		var prog: Dictionary = _ensure_member_progress(member_id)
		var sxp: Dictionary = prog.get("sxp", {}) as Dictionary
		if sxp.is_empty():
			sxp = {"BRW":0,"MND":0,"TPO":0,"VTL":0,"FCS":0}
		sxp[stat_id] = int(sxp.get(stat_id, 0)) + amount
		prog["sxp"] = sxp
		var all_dict: Dictionary = _party_progress()
		all_dict[member_id] = prog.duplicate(true)
		_save_party_progress(all_dict)

	_emit_stats_changed()
	_refresh_cps(member_id)

# ---------- Level helpers ----------
func _get_member_level(member_id: String) -> int:
	# Prefer StatsSystem API if present
	if stats and stats.has_method("get_member_level"):
		var v: Variant = stats.call("get_member_level", member_id)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			return int(v)
	# Fallback: read cached progress
	var all_dict: Dictionary = _party_progress()
	if all_dict.has(member_id):
		var prog: Dictionary = all_dict[member_id]
		if prog.has("char_level"):
			return int(prog["char_level"])
	# Fallback hero stat
	if member_id == _hero_id() and stats and stats.has_method("get_stat"):
		var lv: Variant = stats.call("get_stat", "LVL")
		if typeof(lv) == TYPE_INT or typeof(lv) == TYPE_FLOAT:
			return int(lv)
	return 1

func _set_member_level_exact(member_id: String, new_level: int) -> void:
	new_level = clamp(new_level, 1, 99)
	var old_level: int = _get_member_level(member_id)
	if new_level == old_level: return

	# Update our shared progress blob
	var prog: Dictionary = _ensure_member_progress(member_id)
	prog["char_level"] = new_level
	var all_dict: Dictionary = _party_progress()
	all_dict[member_id] = prog.duplicate(true)
	_save_party_progress(all_dict)

	# Keep StatsSystem in sync for hero explicitly
	var hid := _hero_id()
	if member_id == hid:
		if stats and stats.has_method("set_hero_level"):
			stats.call("set_hero_level", new_level)
		elif stats:
			stats.set("hero_level", new_level)

	# Perk bumps for hero every 3 levels
	if member_id == hid:
		var gained_bpp: int = int(floor(float(new_level)/3.0)) - int(floor(float(old_level)/3.0))
		if gained_bpp > 0: _add_perk_points(gained_bpp)

	_emit_stats_changed()
	_refresh_cps(member_id)

func _ensure_member_progress(member_id: String) -> Dictionary:
	var zeros: Dictionary = {"BRW":0,"MND":0,"TPO":0,"VTL":0,"FCS":0}
	if stats == null:
		return {"label":member_id,"char_level":1,"start":{"BRW":1,"MND":1,"TPO":1,"VTL":1,"FCS":1},"sxp":zeros.duplicate(true),"tenths":zeros.duplicate(true)}

	# If StatsSystem exposes a helper, use it
	if stats.has_method("_ensure_progress"):
		var v: Variant = stats.call("_ensure_progress", member_id)
		if typeof(v) == TYPE_DICTIONARY: return (v as Dictionary)

	# Otherwise, poke its _party_progress directly
	var all_dict: Dictionary = _party_progress()
	if all_dict.has(member_id): return all_dict[member_id] as Dictionary

	var seeded: Dictionary = {"label":member_id,"char_level":1,"start":{"BRW":1,"MND":1,"TPO":1,"VTL":1,"FCS":1},"sxp":zeros.duplicate(true),"tenths":zeros.duplicate(true)}
	all_dict[member_id] = seeded
	_save_party_progress(all_dict)
	return seeded

# ---------- Perks & broadcast ----------
func _add_perk_points(points: int) -> void:
	if points == 0: return
	if gs and gs.has_method("get") and gs.has_method("set"):
		var cur: int = int(gs.get("perk_points"))
		gs.set("perk_points", max(0, cur + points))
	if perk:
		if perk.has_method("add_points"):     perk.call("add_points", points)
		elif perk.has_method("grant_points"): perk.call("grant_points", points)
	_emit_stats_changed()

func _emit_stats_changed() -> void:
	if stats and stats.has_signal("stats_changed"):
		stats.emit_signal("stats_changed")

# ---------- Perk/XP helpers ----------
func _refresh_cps(member_id: String = "") -> void:
	var cps: Object = _cps
	if cps == null or not is_instance_valid(cps):
		cps = _find_cps()
		_cps = cps
	if cps == null or not is_instance_valid(cps):
		return

	# Prefer targeted refresh; fall back to refresh_all.
	if cps.has_method("refresh_member"):
		var id_to_use := member_id
		if id_to_use == "" and has_method("_hero_id"):
			id_to_use = _hero_id()
		cps.call("refresh_member", id_to_use)
	elif cps.has_method("refresh_all"):
		cps.call("refresh_all")

# ---------- Hero row (build + actions) ----------
func _ensure_hero_row() -> void:
	if _cheat_root == null:
		return
	var row: HBoxContainer = _cheat_root.get_node_or_null("HeroRow") as HBoxContainer
	if row == null:
		row = HBoxContainer.new()
		row.name = "HeroRow"
		row.add_theme_constant_override("separation", 8)
		_cheat_root.add_child(row)

		var title := Label.new(); title.text = "Hero:"; row.add_child(title)

		var lvl_lbl := Label.new(); lvl_lbl.text = "Lvl"; row.add_child(lvl_lbl)
		_hero_lvl_spin = SpinBox.new(); _hero_lvl_spin.name = "HeroLvlSpin"
		_hero_lvl_spin.min_value = 1; _hero_lvl_spin.max_value = 99; _hero_lvl_spin.step = 1
		_hero_lvl_spin.custom_minimum_size = Vector2(70, 0); row.add_child(_hero_lvl_spin)

		_btn_hero_set_lvl = Button.new(); _btn_hero_set_lvl.name = "BtnHeroSetLvl"; _btn_hero_set_lvl.text = "Set Lvl"; row.add_child(_btn_hero_set_lvl)

		var xp_lbl := Label.new(); xp_lbl.text = "LXP"; row.add_child(xp_lbl)
		_hero_xp_spin = SpinBox.new(); _hero_xp_spin.name = "HeroXPSpin"
		_hero_xp_spin.min_value = 1; _hero_xp_spin.max_value = 9999; _hero_xp_spin.step = 1; _hero_xp_spin.value = 100
		_hero_xp_spin.custom_minimum_size = Vector2(80, 0); row.add_child(_hero_xp_spin)

		_btn_hero_add_xp = Button.new(); _btn_hero_add_xp.name = "BtnHeroAddXP"; _btn_hero_add_xp.text = "Add XP"; row.add_child(_btn_hero_add_xp)

		var sxp_lbl := Label.new(); sxp_lbl.text = "SXP"; row.add_child(sxp_lbl)
		_hero_stat_pick = OptionButton.new(); _hero_stat_pick.name = "HeroStatPick"; _hero_stat_pick.custom_minimum_size = Vector2(120, 0); row.add_child(_hero_stat_pick)
		_hero_sxp_spin = SpinBox.new(); _hero_sxp_spin.name = "HeroSXPAmt"
		_hero_sxp_spin.min_value = 1; _hero_sxp_spin.max_value = 999; _hero_sxp_spin.step = 1; _hero_sxp_spin.value = 10
		_hero_sxp_spin.custom_minimum_size = Vector2(70, 0); row.add_child(_hero_sxp_spin)

		_btn_hero_add_sxp = Button.new(); _btn_hero_add_sxp.name = "BtnHeroAddSXP"; _btn_hero_add_sxp.text = "Add SXP"; row.add_child(_btn_hero_add_sxp)

	if _hero_lvl_spin == null:     _hero_lvl_spin = row.get_node_or_null("HeroLvlSpin") as SpinBox
	if _btn_hero_set_lvl == null:  _btn_hero_set_lvl = row.get_node_or_null("BtnHeroSetLvl") as Button
	if _hero_xp_spin == null:      _hero_xp_spin = row.get_node_or_null("HeroXPSpin") as SpinBox
	if _btn_hero_add_xp == null:   _btn_hero_add_xp = row.get_node_or_null("BtnHeroAddXP") as Button
	if _hero_stat_pick == null:    _hero_stat_pick = row.get_node_or_null("HeroStatPick") as OptionButton
	if _hero_sxp_spin == null:     _hero_sxp_spin = row.get_node_or_null("HeroSXPAmt") as SpinBox
	if _btn_hero_add_sxp == null:  _btn_hero_add_sxp = row.get_node_or_null("BtnHeroAddSXP") as Button

	if _btn_hero_set_lvl and not _btn_hero_set_lvl.pressed.is_connected(_on_hero_set_level):
		_btn_hero_set_lvl.pressed.connect(_on_hero_set_level)
	if _btn_hero_add_xp and not _btn_hero_add_xp.pressed.is_connected(_on_hero_add_xp):
		_btn_hero_add_xp.pressed.connect(_on_hero_add_xp)
	if _btn_hero_add_sxp and not _btn_hero_add_sxp.pressed.is_connected(_on_hero_add_sxp):
		_btn_hero_add_sxp.pressed.connect(_on_hero_add_sxp)

func _populate_hero_stat_picker() -> void:
	if _hero_stat_pick == null: return
	_hero_stat_pick.clear()
	for s in ["BRW","MND","TPO","VTL","FCS"]:
		_hero_stat_pick.add_item(s)
		_hero_stat_pick.set_item_metadata(_hero_stat_pick.get_item_count() - 1, s)
	_hero_stat_pick.select(0)

func _refresh_hero_row() -> void:
	if _hero_lvl_spin:
		_hero_lvl_spin.value = _get_member_level(_hero_id())

func _on_hero_set_level() -> void:
	if _hero_lvl_spin == null: return
	_set_member_level_exact(_hero_id(), int(_hero_lvl_spin.value))
	_refresh_hero_row()

func _on_hero_add_xp() -> void:
	if _hero_xp_spin == null: return
	_grant_xp_to_member(_hero_id(), int(_hero_xp_spin.value))
	_refresh_hero_row()

func _on_hero_add_sxp() -> void:
	if _hero_stat_pick == null or _hero_sxp_spin == null: return
	var idx: int = _hero_stat_pick.get_selected()
	if idx < 0: return
	var stat_id: String = String(_hero_stat_pick.get_item_metadata(idx))
	_add_sxp_to_member(_hero_id(), stat_id, int(_hero_sxp_spin.value))

# ---------- Sigil row (build + actions) ----------
func _ensure_sigil_row() -> void:
	if _cheat_root == null: return
	var row: HBoxContainer = _cheat_root.get_node_or_null("SigilRow") as HBoxContainer
	if row == null:
		row = HBoxContainer.new()
		row.name = "SigilRow"
		row.add_theme_constant_override("separation", 8)
		_cheat_root.add_child(row)

		var lbl := Label.new(); lbl.text = "Sigil:"; row.add_child(lbl)

		_sigil_pick = OptionButton.new(); _sigil_pick.name = "SigilPick"
		_sigil_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_sigil_pick.custom_minimum_size = Vector2(180, 0)
		row.add_child(_sigil_pick)

		_sigil_xp_spin = SpinBox.new(); _sigil_xp_spin.name = "SigilXPAmt"
		_sigil_xp_spin.min_value = 1; _sigil_xp_spin.max_value = 9999; _sigil_xp_spin.step = 1; _sigil_xp_spin.value = 25
		_sigil_xp_spin.custom_minimum_size = Vector2(80, 0)
		row.add_child(_sigil_xp_spin)

		_btn_add_sigil_xp = Button.new(); _btn_add_sigil_xp.name = "BtnAddSigilXP"; _btn_add_sigil_xp.text = "Add Sigil XP"
		row.add_child(_btn_add_sigil_xp)

	if _sigil_pick == null:       _sigil_pick = row.get_node_or_null("SigilPick") as OptionButton
	if _sigil_xp_spin == null:    _sigil_xp_spin = row.get_node_or_null("SigilXPAmt") as SpinBox
	if _btn_add_sigil_xp == null: _btn_add_sigil_xp = row.get_node_or_null("BtnAddSigilXP") as Button

	if _btn_add_sigil_xp and not _btn_add_sigil_xp.pressed.is_connected(_on_add_sigil_xp):
		_btn_add_sigil_xp.pressed.connect(_on_add_sigil_xp)

func _refresh_sigil_picker() -> void:
	if _sigil_pick == null: return
	_sigil_pick.clear()

	var member: String = _member_id_from_ui()
	var ids: Array[String] = []

	# First: whatever SigilSystem says is equipped.
	if _sig and _sig.has_method("get_loadout"):
		var lv: Variant = _sig.call("get_loadout", member)
		if typeof(lv) == TYPE_ARRAY:
			for s in (lv as Array): ids.append(String(s))
		elif typeof(lv) == TYPE_PACKED_STRING_ARRAY:
			for s2 in (lv as PackedStringArray): ids.append(String(s2))

	# If empty, try broad instance listings.
	if ids.is_empty() and _sig:
		var method_names := [
			"list_free_instances","list_owned_instances","get_owned_instances",
			"list_all_instances","list_all_sigils","get_all_ids","get_sigil_ids"
		]
		for m in method_names:
			if _sig.has_method(m):
				var v2: Variant = _sig.call(m)
				if typeof(v2) == TYPE_ARRAY:
					for s3 in (v2 as Array): ids.append(String(s3))
				elif typeof(v2) == TYPE_PACKED_STRING_ARRAY:
					for s4 in (v2 as PackedStringArray): ids.append(String(s4))
				if not ids.is_empty():
					break

	if ids.is_empty():
		_sigil_pick.add_item("— no sigils —")
		_sigil_pick.set_item_metadata(0, "")
		_sigil_pick.select(0)
		return

	ids.sort()
	for sid in ids:
		_sigil_pick.add_item(sid)
		_sigil_pick.set_item_metadata(_sigil_pick.get_item_count() - 1, sid)
	_sigil_pick.select(0)

func _selected_sigil_id() -> String:
	if _sigil_pick == null: return ""
	var i: int = _sigil_pick.get_selected()
	if i < 0: return ""
	var md: Variant = _sigil_pick.get_item_metadata(i)
	if md == null: return ""
	return str(md)

func _on_add_sigil_xp() -> void:
	if _sigil_pick == null or _sigil_xp_spin == null: return
	var member: String = _member_id_from_ui()
	var sid: String = _selected_sigil_id()
	var amount: int = int(_sigil_xp_spin.value)
	if sid == "" or amount <= 0: return
	_try_add_sigil_xp(member, sid, amount)
	_refresh_cps(member)

# ---- tiny reflection helpers ----
func _method_argc(obj: Object, method_name: String) -> int:
	if obj == null: return -1
	var list: Array = obj.get_method_list()
	for d_any in list:
		var d: Dictionary = d_any
		if String(d.get("name","")) == method_name:
			var args: Array = d.get("args", [])
			return args.size()
	return -1

func _call_sigil_xp_fn(fn: String, member_id: String, sigil_id: String, amount: int) -> bool:
	var argc := _method_argc(_sig, fn)
	# Special-case the cheat function so we never pass member_id to it.
	if fn == "cheat_add_xp_to_instance":
		if argc == 3:
			_sig.call(fn, sigil_id, amount, false)
			return true
		elif argc == 2:
			_sig.call(fn, sigil_id, amount)
			return true
		elif argc == 1:
			_sig.call(fn, amount)
			return true
		return false

	if argc == 3:
		_sig.call(fn, member_id, sigil_id, amount)
		return true
	elif argc == 2:
		_sig.call(fn, sigil_id, amount)
		return true
	elif argc == 1:
		_sig.call(fn, amount)
		return true
	return false

func _try_add_sigil_xp(member_id: String, sigil_id: String, amount: int) -> void:
	if _sig == null: return

	# Prefer names that usually require (member, id, amount)
	var prefer_three := ["add_xp_to_sigil", "add_member_sigil_xp", "grant_sigil_xp"]
	for fn in prefer_three:
		if _sig.has_method(fn) and _call_sigil_xp_fn(fn, member_id, sigil_id, amount):
			return

	# Common helpers: (id, amount) and cheat helper
	var prefer_two := ["add_sigil_xp", "cheat_add_xp_to_instance"]
	for fn2 in prefer_two:
		if _sig.has_method(fn2) and _call_sigil_xp_fn(fn2, member_id, sigil_id, amount):
			return

	# Last resort: generic "add_xp"
	if _sig.has_method("add_xp"):
		var n := _method_argc(_sig, "add_xp")
		if n == 3: _sig.call("add_xp", member_id, sigil_id, amount)
		elif n == 2: _sig.call("add_xp", sigil_id, amount)

# ---------- Dorm hooks (handlers) ---------------------------------------------
func _on_dorms_common_added(_aid: String) -> void:
	# Ensure the Game Menu is visible and on Dorms
	_toggle_game_menu() # creates if needed
	if _game_menu and not _game_menu.visible:
		_game_menu.visible = true
	_game_menu.move_to_front()
	# Try to switch its tab if it exposes the helper
	if _game_menu and (_game_menu as Control).has_method("_open_dorms_tab"):
		(_game_menu as Control).call("_open_dorms_tab")

func _on_dorms_plan_changed() -> void:
	var ds := get_node_or_null("/root/aDormSystem")
	if ds and ds.has_method("is_plan_locked") and bool(ds.call("is_plan_locked")):
		# snapshot current layout once the plan is locked
		if ds.has_method("current_layout"):
			var snap_v: Variant = ds.call("current_layout")
			if typeof(snap_v) == TYPE_DICTIONARY:
				_prelock_layout = (snap_v as Dictionary).duplicate(true)
	else:
		_prelock_layout.clear()

# v2 signal (preferred): we get explicit moves [{aid,name,from,to}, ...]
func _on_dorms_saturday_applied_v2(new_layout: Dictionary, moves: Array) -> void:
	_show_reassignments_summary(new_layout, moves)

# Legacy signal: we only get the new layout; build moves from snapshot or DS helper.
func _on_dorms_saturday_applied(new_layout: Dictionary) -> void:
	_show_reassignments_summary(new_layout, [])

# Build and show the final popup text with only actual reassignees.
func _show_reassignments_summary(new_layout: Dictionary, moves_in: Array) -> void:
	var ds := get_node_or_null("/root/aDormSystem")

	# Prefer explicit moves from signal or DS cache.
	var moves: Array = []
	if moves_in.size() > 0:
		moves = moves_in
	elif ds and ds.has_method("get_last_applied_moves"):
		var mv: Variant = ds.call("get_last_applied_moves")
		if typeof(mv) == TYPE_ARRAY:
			moves = (mv as Array)

	var lines := PackedStringArray()

	if moves.size() > 0:
		for entry_any in moves:
			if typeof(entry_any) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = entry_any
			var nm: String = String(entry.get("name","")).strip_edges()
			var aid: String = String(entry.get("aid","")).strip_edges()
			var fr:  String = String(entry.get("from","")).strip_edges()
			var to:  String = String(entry.get("to","")).strip_edges()
			if nm == "" and ds and aid != "":
				nm = String(ds.call("display_name", aid))
			if fr != "" and to != "" and fr != to and nm != "":
				lines.append("\"%s\" moved from \"%s\" to \"%s\"" % [nm, fr, to])
	else:
		# Fallback: derive moves from pre-lock snapshot vs new layout
		var old_pos: Dictionary = {}
		for k in _prelock_layout.keys():
			var rid := String(k)
			var aid_old := String(_prelock_layout.get(rid, ""))
			if aid_old != "":
				old_pos[aid_old] = rid
		var new_pos: Dictionary = {}
		for k2 in new_layout.keys():
			var rid2 := String(k2)
			var aid_new := String(new_layout.get(rid2, ""))
			if aid_new != "":
				new_pos[aid_new] = rid2

		for aid_key in old_pos.keys():
			var aid3: String = String(aid_key)
			var fr2: String = String(old_pos.get(aid3, ""))
			var to2: String = String(new_pos.get(aid3, ""))
			if fr2 != "" and to2 != "" and fr2 != to2:
				var nm2: String = (String(ds.call("display_name", aid3)) if ds else aid3)
				lines.append("\"%s\" moved from \"%s\" to \"%s\"" % [nm2, fr2, to2])

	# Dialog (unchanged behavior when nothing to report)
	var dlg := AcceptDialog.new()
	dlg.title = "Reassignments Applied"
	dlg.dialog_text = ("Room changes have been applied." if lines.size() == 0 else _join_lines(lines))
	add_child(dlg)
	dlg.popup_centered()
	await dlg.confirmed
	dlg.queue_free()

	_prelock_layout.clear()

func _join_lines(arr: PackedStringArray) -> String:
	var out := ""
	for i in range(arr.size()):
		if i > 0: out += "\n"
		out += arr[i]
	return out

# Prevent closing menu while Common has people to place
func _menu_can_close() -> bool:
	var ds := get_node_or_null("/root/aDormSystem")
	if ds == null:
		return true
	var list_v: Variant = ds.call("get_common") # merged Common + staged-to-place
	var count := 0
	if typeof(list_v) == TYPE_PACKED_STRING_ARRAY:
		count = (list_v as PackedStringArray).size()
	elif typeof(list_v) == TYPE_ARRAY:
		count = (list_v as Array).size()
	if count > 0:
		_main_toast("Finish placing everyone from the Common Room before closing the menu.")
		return false
	return true

func _main_toast(msg: String) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Notice"
	dlg.dialog_text = msg
	add_child(dlg)
	dlg.popup_centered()
	await dlg.confirmed
	dlg.queue_free()

## ═══════════════════════════════════════════════════════════════
## TEST/DEBUG HELPERS - Battle System
## ═══════════════════════════════════════════════════════════════

## DEV: Give player test items for testing battle systems
## Call this from console or add to _ready() for automatic testing
func _give_test_bind_items() -> void:
	"""Give player test items for testing the capture and item systems"""
	if not inv:
		print("[Main] Cannot give test items - inventory system not available")
		return

	# Give a variety of bind items for testing capture
	inv.add_item("BIND_001", 5)  # Weak Bind (+10 capture)
	inv.add_item("BIND_002", 3)  # Standard Bind (+25 capture)
	inv.add_item("BIND_003", 2)  # Strong Bind (+40 capture)

	# Give consumable items for testing
	inv.add_item("CON_001", 10)  # Health Drink (50 HP)
	inv.add_item("CON_002", 10)  # Mind Drink (30 MP)

	print("[Main] DEBUG: Added test items to inventory")
	print("  Bind Items:")
	print("    - Weak Bind x5")
	print("    - Standard Bind x3")
	print("    - Strong Bind x2")
	print("  Consumables:")
	print("    - Health Drink x10")
	print("    - Mind Drink x10")
