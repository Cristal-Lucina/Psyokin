# =======================
# ItemsCheatBar.gd (FULL)
# =======================
extends Control
class_name ItemsCheatBar

# --- Autoload paths ------------------------------------------------------------
const INV_PATH   := "/root/aInventorySystem"
const CSV_PATH   := "/root/aCSVLoader"
const SIG_PATH   := "/root/aSigilSystem"
const GS_PATH    := "/root/aGameState"
const STATS_PATH := "/root/aStatsSystem"
const PERK_PATH  := "/root/aPerkSystem"
const PARTY_PATH := "/root/aPartySystem"
const HERO_PATH  := "/root/aHeroSystem"
const DORM_PATH  := "/root/aDormSystem"
const AFF_PATH   := "/root/aAffinitySystem" # optional
const BONDS_PATH := "/root/aCircleBondSystem"

# --- CSV paths / keys ----------------------------------------------------------
const ITEMS_CSV := "res://data/items/items.csv"
const TEST_AILMENT_ITEMS_CSV := "res://data/combat/test_ailment_items.csv"
const KEY_ID    := "item_id"

const PARTY_CSV_CANDIDATES: Array[String] = [
	"res://data/party/party.csv",
	"res://data/Party.csv",
	"res://data/party.csv",
	"res://data/characters/party.csv",
	"res://data/actors/party.csv",
	"res://data/actors.csv"
]
const PARTY_ID_KEYS      : Array[String] = ["actor_id", "id", "actor", "member_id"]
const PARTY_NAME_KEYS    : Array[String] = ["name", "display_name", "disp_name"]
const PARTY_ACTIVE_KEYS  : Array[String] = ["active", "starter", "is_active", "start_in_party", "join_to_active", "active_flag"]
const PARTY_BESTIE_KEYS  : Array[String] = ["bestie_buff",  "besties", "bestie", "bestie_ids"]
const PARTY_RIVAL_KEYS   : Array[String] = ["rival_debuff", "rivals",  "rival",  "rival_ids"]

# --- Scene node refs (existing in your .tscn) ---------------------------------
@onready var _picker     : OptionButton = find_child("Picker", true, false) as OptionButton
@onready var _qty        : SpinBox      = find_child("Qty", true, false) as SpinBox
@onready var _give       : Button       = find_child("BtnGive", true, false) as Button
@onready var _rem        : Button       = find_child("BtnRemove", true, false) as Button
@onready var _give10     : Button       = find_child("BtnGive10", true, false) as Button
@onready var _reload     : Button       = find_child("BtnReloadCSV", true, false) as Button

@onready var _sig_inst_pick : OptionButton = find_child("InstPicker", true, false) as OptionButton
@onready var _btn_lv_up     : Button       = find_child("BtnLvUp", true, false) as Button
@onready var _btn_lv_down   : Button       = find_child("BtnLvDown", true, false) as Button
@onready var _btn_xp_25     : Button       = find_child("BtnXP25", true, false) as Button
@onready var _btn_xp_100    : Button       = find_child("BtnXP100", true, false) as Button
@onready var _chk_equipped  : CheckBox     = find_child("ChkEquipped", true, false) as CheckBox

@onready var _btn_lvl_m1    : Button       = find_child("BtnLvlM1", true, false) as Button
@onready var _btn_lvl_p1    : Button       = find_child("BtnLvlP1", true, false) as Button
@onready var _spin_lvl      : SpinBox      = find_child("SpinLvl", true, false) as SpinBox
@onready var _btn_set_level : Button       = find_child("BtnSetLvl", true, false) as Button

# --- Party UI (optional external) ---------------------------------------------
var _xp_amt      : SpinBox      = null
var _btn_add_xp  : Button       = null
var _stat_pick   : OptionButton = null
var _sxp_amt     : SpinBox      = null
var _btn_add_sxp : Button       = null

@onready var _roster_pick   : OptionButton = find_child("RosterPick", true, false) as OptionButton
@onready var _member_id_le  : LineEdit     = find_child("MemberId",  true, false) as LineEdit
@onready var _btn_add_party : Button       = find_child("BtnAddParty",    true, false) as Button
@onready var _btn_rem_party : Button       = find_child("BtnRemoveParty", true, false) as Button
@onready var _btn_to_bench  : Button       = find_child("BtnToBench",     true, false) as Button

# Runtime-added CSV import buttons
var _party_import_row : HBoxContainer = null
var _btn_import_all      : Button = null
var _btn_import_starters : Button = null

# Runtime-added test items button
var _test_items_row  : HBoxContainer = null
var _btn_test_items  : Button = null

# -------- Hero cheat widgets (runtime-built if missing) --------
var _hero_row         : HBoxContainer = null
var _hero_xp_spin     : SpinBox       = null
var _btn_hero_add_xp  : Button        = null
var _hero_stat_pick   : OptionButton  = null
var _hero_sxp_spin    : SpinBox       = null
var _btn_hero_add_sxp : Button        = null

# -------- Party cheat widgets (runtime-built if missing) -------
var _party_lxp_row  : HBoxContainer = null
var _party_sxp_row  : HBoxContainer = null

# -------- Sigil GXP cheat widgets (runtime-built if missing) ----
var _sigil_gxp_row   : HBoxContainer = null
var _sigil_gxp_pick  : OptionButton  = null
var _sigil_gxp_spin  : SpinBox       = null
var _btn_add_gxp     : Button        = null

# -------- Bond system cheat widgets (runtime-built if missing) ----
var _bond_row              : HBoxContainer = null
var _bond_pick             : OptionButton  = null
var _dialogue_score_spin   : SpinBox       = null
var _btn_complete_event    : Button        = null
var _gift_reaction_pick    : OptionButton  = null
var _btn_give_gift         : Button        = null
var _btn_side_meetup       : Button        = null
var _btn_mark_known        : Button        = null
var _btn_discover_like     : Button        = null
var _btn_add_points        : Button        = null  # Raw points adder for testing
var _points_spin           : SpinBox       = null

# --- Systems ------------------------------------------------------------------
var _inv   : Node = null
var _csv   : Node = null
var _sig   : Node = null
var _gs    : Node = null
var _stats : Node = null
var _perk  : Node = null
var _party : Node = null
var _hero  : Node = null
var _dorm  : Node = null
var _aff   : Node = null
var _bonds : Node = null

# --- Data caches ---------------------------------------------------------------
var _defs            : Dictionary = {}  # items
var _party_defs_by_id: Dictionary = {}
var _party_csv_path  : String     = ""

# --- Debug switch --------------------------------------------------------------
const DEBUG_ICB_SIG: bool = false

# --- Helper: find any node by exact name anywhere in the tree ------------------
func _find_anywhere(node_name: String) -> Node:
	var root: Node = get_tree().root
	var arr: Array = root.find_children(node_name, "", true, false)
	if arr.size() > 0:
		return arr[0] as Node
	return null

func _ds() -> Node:
	return _dorm

# --- Ready ---------------------------------------------------------------------
func _ready() -> void:
	_inv   = get_node_or_null(INV_PATH)
	_csv   = get_node_or_null(CSV_PATH)
	_sig   = get_node_or_null(SIG_PATH)
	_gs    = get_node_or_null(GS_PATH)
	_stats = get_node_or_null(STATS_PATH)
	_perk  = get_node_or_null(PERK_PATH)
	_party = get_node_or_null(PARTY_PATH)
	_hero  = get_node_or_null(HERO_PATH)
	_dorm  = get_node_or_null(DORM_PATH)
	_aff   = get_node_or_null(AFF_PATH)
	_bonds = get_node_or_null(BONDS_PATH)

	# Listen to inventory signals so the picker stays fresh
	if _inv != null:
		if _inv.has_signal("items_loaded") and not _inv.is_connected("items_loaded", Callable(self, "_on_inv_defs_loaded")):
			_inv.connect("items_loaded", Callable(self, "_on_inv_defs_loaded"))
		if _inv.has_signal("inventory_changed") and not _inv.is_connected("inventory_changed", Callable(self, "_on_inv_counts_changed")):
			_inv.connect("inventory_changed", Callable(self, "_on_inv_counts_changed"))
		if _inv.has_signal("items_changed") and not _inv.is_connected("items_changed", Callable(self, "_on_inv_counts_changed")):
			_inv.connect("items_changed", Callable(self, "_on_inv_counts_changed"))

	_bind_optional_external_ui()

	_ensure_hero_row()
	_style_option_button(_hero_stat_pick, 8, 210)
	_populate_hero_stat_picker()

	_ensure_party_rows()
	_style_option_button(_stat_pick, 8, 210)
	_populate_stat_picker()

	# CSV import buttons (before Sigil GXP row)
	_ensure_party_import_row()

	# Test ailment items button
	_ensure_test_items_row()

	# Sigil GXP row
	_ensure_sigil_gxp_row()

	# Bond system cheat row
	_ensure_bond_row()

	# Row1 (Items)
	if _give and not _give.pressed.is_connected(_on_give):          _give.pressed.connect(_on_give)
	if _rem and not _rem.pressed.is_connected(_on_remove):           _rem.pressed.connect(_on_remove)
	if _give10 and not _give10.pressed.is_connected(_on_give10):     _give10.pressed.connect(_on_give10)
	if _reload and not _reload.pressed.is_connected(_on_reload):     _reload.pressed.connect(_on_reload)

	# Row2 (Sigils)
	if _btn_lv_up and not _btn_lv_up.pressed.is_connected(_on_sig_lv_up):     _btn_lv_up.pressed.connect(_on_sig_lv_up)
	if _btn_lv_down and not _btn_lv_down.pressed.is_connected(_on_sig_lv_dn): _btn_lv_down.pressed.connect(_on_sig_lv_dn)
	if _btn_xp_25 and not _btn_xp_25.pressed.is_connected(_on_sig_xp_25):     _btn_xp_25.pressed.connect(_on_sig_xp_25)
	if _btn_xp_100 and not _btn_xp_100.pressed.is_connected(_on_sig_xp_100):  _btn_xp_100.pressed.connect(_on_sig_xp_100)
	if _chk_equipped and not _chk_equipped.toggled.is_connected(_on_equipped_toggle):
		_chk_equipped.toggled.connect(_on_equipped_toggle)

	# Row3 (Level/SXP common controls)
	if _btn_lvl_m1 and not _btn_lvl_m1.pressed.is_connected(_on_lvl_m1): _btn_lvl_m1.pressed.connect(_on_lvl_m1)
	if _btn_lvl_p1 and not _btn_lvl_p1.pressed.is_connected(_on_lvl_p1): _btn_lvl_p1.pressed.connect(_on_lvl_p1)
	if _btn_set_level and not _btn_set_level.pressed.is_connected(_on_set_level):
		_btn_set_level.pressed.connect(_on_set_level)

	# Party LXP/SXP
	if _btn_add_sxp and not _btn_add_sxp.pressed.is_connected(_on_add_sxp): _btn_add_sxp.pressed.connect(_on_add_sxp)
	if _btn_add_xp  and not _btn_add_xp.pressed.is_connected(_on_add_xp):   _btn_add_xp.pressed.connect(_on_add_xp)

	# Row4 (Party roster)
	if _btn_add_party and not _btn_add_party.pressed.is_connected(_on_add_to_party):
		_btn_add_party.pressed.connect(_on_add_to_party)
	if _btn_rem_party and not _btn_rem_party.pressed.is_connected(_on_remove_from_party):
		_btn_rem_party.pressed.connect(_on_remove_from_party)
	if _btn_to_bench and not _btn_to_bench.pressed.is_connected(_on_move_to_bench):
		_btn_to_bench.pressed.connect(_on_move_to_bench)
	if _roster_pick and not _roster_pick.item_selected.is_connected(_on_roster_pick_selected):
		_roster_pick.item_selected.connect(_on_roster_pick_selected)

	# Style pickers that exist
	_style_option_button(_picker, 8, 210)
	_style_option_button(_sig_inst_pick, 8, 210)
	_style_option_button(_roster_pick, 8, 210)

	# Apply 8pt font to all scene buttons
	if _give: _give.add_theme_font_size_override("font_size", 8)
	if _rem: _rem.add_theme_font_size_override("font_size", 8)
	if _give10: _give10.add_theme_font_size_override("font_size", 8)
	if _reload: _reload.add_theme_font_size_override("font_size", 8)
	if _btn_lv_up: _btn_lv_up.add_theme_font_size_override("font_size", 8)
	if _btn_lv_down: _btn_lv_down.add_theme_font_size_override("font_size", 8)
	if _btn_xp_25: _btn_xp_25.add_theme_font_size_override("font_size", 8)
	if _btn_xp_100: _btn_xp_100.add_theme_font_size_override("font_size", 8)
	if _btn_lvl_m1: _btn_lvl_m1.add_theme_font_size_override("font_size", 8)
	if _btn_lvl_p1: _btn_lvl_p1.add_theme_font_size_override("font_size", 8)
	if _btn_set_level: _btn_set_level.add_theme_font_size_override("font_size", 8)
	if _btn_add_party: _btn_add_party.add_theme_font_size_override("font_size", 8)
	if _btn_rem_party: _btn_rem_party.add_theme_font_size_override("font_size", 8)
	if _btn_to_bench: _btn_to_bench.add_theme_font_size_override("font_size", 8)

	# Populate
	_refresh_defs()
	_refresh_sig_dropdown()
	_refresh_sigil_gxp_dropdown()
	_refresh_roster_picker()
	if _spin_lvl:
		_spin_lvl.value = _get_member_level()

	if _sig and _sig.has_signal("loadout_changed") and not _sig.is_connected("loadout_changed", Callable(self, "_on_loadout_changed")):
		_sig.connect("loadout_changed", Callable(self, "_on_loadout_changed"))
	if _sig and _sig.has_signal("instance_created") and not _sig.is_connected("instance_created", Callable(self, "_on_sigil_changed")):
		_sig.connect("instance_created", Callable(self, "_on_sigil_changed"))
	if _sig and _sig.has_signal("sigils_changed") and not _sig.is_connected("sigils_changed", Callable(self, "_on_sigil_changed")):
		_sig.connect("sigils_changed", Callable(self, "_on_sigil_changed"))

# --- Bind external cheat UI if it's not a child of this node -------------------
func _bind_optional_external_ui() -> void:
	if _xp_amt == null:
		_xp_amt = find_child("SpinXP", true, false) as SpinBox
		if _xp_amt == null:
			_xp_amt = _find_anywhere("SpinXP") as SpinBox

	if _btn_add_xp == null:
		_btn_add_xp = find_child("BtnAddXP", true, false) as Button
		if _btn_add_xp == null:
			_btn_add_xp = _find_anywhere("BtnAddXP") as Button

	if _stat_pick == null:
		_stat_pick = find_child("StatPick", true, false) as OptionButton
		if _stat_pick == null:
			_stat_pick = _find_anywhere("StatPick") as OptionButton

	if _sxp_amt == null:
		_sxp_amt = find_child("SpinSXP", true, false) as SpinBox
		if _sxp_amt == null:
			_sxp_amt = _find_anywhere("SpinSXP") as SpinBox

	if _btn_add_sxp == null:
		_btn_add_sxp = find_child("BtnAddSXP", true, false) as Button
		if _btn_add_sxp == null:
			_btn_add_sxp = _find_anywhere("BtnAddSXP") as Button

	if _roster_pick == null:
		_roster_pick = find_child("RosterPick", true, false) as OptionButton
		if _roster_pick == null:
			_roster_pick = _find_anywhere("RosterPick") as OptionButton

	if _member_id_le == null:
		_member_id_le = find_child("MemberId", true, false) as LineEdit
		if _member_id_le == null:
			_member_id_le = _find_anywhere("MemberId") as LineEdit

# CSV import buttons row
func _ensure_party_import_row() -> void:
	var parent := _attach_point()
	_party_import_row = parent.get_node_or_null("PartyImportRow") as HBoxContainer
	if _party_import_row == null:
		_party_import_row = HBoxContainer.new()
		_party_import_row.name = "PartyImportRow"
		_party_import_row.add_theme_constant_override("separation", 6)
		parent.add_child(_party_import_row)

	if _btn_import_all == null:
		_btn_import_all = Button.new()
		_btn_import_all.name = "BtnImportParty"
		_btn_import_all.text = "Import All (CSV) → Common"
		_btn_import_all.add_theme_font_size_override("font_size", 8)
		_party_import_row.add_child(_btn_import_all)
		_btn_import_all.pressed.connect(_on_import_all)

	if _btn_import_starters == null:
		_btn_import_starters = Button.new()
		_btn_import_starters.name = "BtnImportStarters"
		_btn_import_starters.text = "Import Starters Only"
		_btn_import_starters.add_theme_font_size_override("font_size", 8)
		_party_import_row.add_child(_btn_import_starters)
		_btn_import_starters.pressed.connect(_on_import_starters)

# Test ailment items button
func _ensure_test_items_row() -> void:
	var parent := _attach_point()
	_test_items_row = parent.get_node_or_null("TestItemsRow") as HBoxContainer
	if _test_items_row == null:
		_test_items_row = HBoxContainer.new()
		_test_items_row.name = "TestItemsRow"
		_test_items_row.add_theme_constant_override("separation", 6)
		parent.add_child(_test_items_row)

	if _btn_test_items == null:
		_btn_test_items = Button.new()
		_btn_test_items.name = "BtnGiveTestItems"
		_btn_test_items.text = "Give Test Ailment Items (x10)"
		_btn_test_items.add_theme_font_size_override("font_size", 8)
		_test_items_row.add_child(_btn_test_items)
		_btn_test_items.pressed.connect(_on_give_test_items)

# --- OptionButton UX tweaks ----------------------------------------------------
func _style_option_button(ob: OptionButton, font_px: int, popup_max_h: int, popup_max_w: int = 300) -> void:
	if ob == null:
		return
	ob.add_theme_font_size_override("font_size", font_px)
	var pm: PopupMenu = ob.get_popup()
	if pm:
		pm.add_theme_font_size_override("font_size", font_px)
		pm.max_size = Vector2i(popup_max_w, popup_max_h)

# --- Runtime rows: Hero + Party cheats ----------------------------------------
func _attach_point() -> Control:
	var host := find_child("CheatRoot", true, false) as Control
	if host != null:
		return host
	return self

func _ensure_hero_row() -> void:
	var parent := _attach_point()
	_hero_row = parent.get_node_or_null("HeroRow") as HBoxContainer
	if _hero_row != null:
		return

	_hero_row = HBoxContainer.new()
	_hero_row.name = "HeroRow"
	_hero_row.add_theme_constant_override("separation", 6)
	parent.add_child(_hero_row)

	var title := Label.new()
	title.text = "Hero:"
	_hero_row.add_child(title)

	var xp_lbl := Label.new()
	xp_lbl.text = "LXP"
	_hero_row.add_child(xp_lbl)

	_hero_xp_spin = SpinBox.new()
	_hero_xp_spin.min_value = 1
	_hero_xp_spin.max_value = 99999
	_hero_xp_spin.step = 1
	_hero_xp_spin.value = 100
	_hero_xp_spin.custom_minimum_size = Vector2(56, 0)
	_hero_row.add_child(_hero_xp_spin)

	_btn_hero_add_xp = Button.new()
	_btn_hero_add_xp.text = "Add Hero XP"
	_btn_hero_add_xp.add_theme_font_size_override("font_size", 8)
	_hero_row.add_child(_btn_hero_add_xp)

	var sxp_lbl := Label.new()
	sxp_lbl.text = "SXP"
	_hero_row.add_child(sxp_lbl)

	_hero_stat_pick = OptionButton.new()
	_hero_stat_pick.custom_minimum_size = Vector2(84, 0)
	_hero_row.add_child(_hero_stat_pick)

	_hero_sxp_spin = SpinBox.new()
	_hero_sxp_spin.min_value = 1
	_hero_sxp_spin.max_value = 9999
	_hero_sxp_spin.step = 1
	_hero_sxp_spin.value = 10
	_hero_sxp_spin.custom_minimum_size = Vector2(49, 0)
	_hero_row.add_child(_hero_sxp_spin)

	_btn_hero_add_sxp = Button.new()
	_btn_hero_add_sxp.text = "Add Hero SXP"
	_btn_hero_add_sxp.add_theme_font_size_override("font_size", 8)
	_hero_row.add_child(_btn_hero_add_sxp)

	if _btn_hero_add_xp and not _btn_hero_add_xp.pressed.is_connected(_on_hero_add_xp):
		_btn_hero_add_xp.pressed.connect(_on_hero_add_xp)
	if _btn_hero_add_sxp and not _btn_hero_add_sxp.pressed.is_connected(_on_hero_add_sxp):
		_btn_hero_add_sxp.pressed.connect(_on_hero_add_sxp)

func _populate_hero_stat_picker() -> void:
	if _hero_stat_pick == null:
		return
	_hero_stat_pick.clear()
	for s in ["BRW","MND","TPO","VTL","FCS"]:
		_hero_stat_pick.add_item(s)
		_hero_stat_pick.set_item_metadata(_hero_stat_pick.get_item_count() - 1, s)
	_hero_stat_pick.select(0)

func _ensure_party_rows() -> void:
	if _xp_amt != null and _btn_add_xp != null and _stat_pick != null and _sxp_amt != null and _btn_add_sxp != null:
		return

	var parent := _attach_point()

	# LXP row
	_party_lxp_row = parent.get_node_or_null("PartyLxpRow") as HBoxContainer
	if _party_lxp_row == null:
		_party_lxp_row = HBoxContainer.new()
		_party_lxp_row.name = "PartyLxpRow"
		_party_lxp_row.add_theme_constant_override("separation", 6)
		parent.add_child(_party_lxp_row)

		var lbl := Label.new()
		lbl.text = "Party LXP:"
		_party_lxp_row.add_child(lbl)

		_xp_amt = SpinBox.new()
		_xp_amt.min_value = 1
		_xp_amt.max_value = 99999
		_xp_amt.value = 100
		_xp_amt.step = 1
		_xp_amt.custom_minimum_size = Vector2(56, 0)
		_party_lxp_row.add_child(_xp_amt)

		_btn_add_xp = Button.new()
		_btn_add_xp.text = "Add XP to Member"
		_btn_add_xp.add_theme_font_size_override("font_size", 8)
		_party_lxp_row.add_child(_btn_add_xp)
		if not _btn_add_xp.pressed.is_connected(_on_add_xp):
			_btn_add_xp.pressed.connect(_on_add_xp)

	# SXP row
	_party_sxp_row = parent.get_node_or_null("PartySxpRow") as HBoxContainer
	if _party_sxp_row == null:
		_party_sxp_row = HBoxContainer.new()
		_party_sxp_row.name = "PartySxpRow"
		_party_sxp_row.add_theme_constant_override("separation", 6)
		parent.add_child(_party_sxp_row)

		var sl := Label.new()
		sl.text = "Party SXP:"
		_party_sxp_row.add_child(sl)

		_stat_pick = OptionButton.new()
		_stat_pick.custom_minimum_size = Vector2(84, 0)
		_party_sxp_row.add_child(_stat_pick)

		_sxp_amt = SpinBox.new()
		_sxp_amt.min_value = 1
		_sxp_amt.max_value = 9999
		_sxp_amt.value = 10
		_sxp_amt.step = 1
		_sxp_amt.custom_minimum_size = Vector2(49, 0)
		_party_sxp_row.add_child(_sxp_amt)

		_btn_add_sxp = Button.new()
		_btn_add_sxp.text = "Add SXP to Member"
		_btn_add_sxp.add_theme_font_size_override("font_size", 8)
		_party_sxp_row.add_child(_btn_add_sxp)
		if not _btn_add_sxp.pressed.is_connected(_on_add_sxp):
			_btn_add_sxp.pressed.connect(_on_add_sxp)

func _ensure_sigil_gxp_row() -> void:
	var parent := _attach_point()
	_sigil_gxp_row = parent.get_node_or_null("SigilGxpRow") as HBoxContainer
	if _sigil_gxp_row == null:
		_sigil_gxp_row = HBoxContainer.new()
		_sigil_gxp_row.name = "SigilGxpRow"
		_sigil_gxp_row.add_theme_constant_override("separation", 6)
		parent.add_child(_sigil_gxp_row)

		var lbl := Label.new()
		lbl.text = "Sigil XP:"
		_sigil_gxp_row.add_child(lbl)

		_sigil_gxp_pick = OptionButton.new()
		_sigil_gxp_pick.custom_minimum_size = Vector2(140, 0)
		_sigil_gxp_row.add_child(_sigil_gxp_pick)

		var gxp_lbl := Label.new()
		gxp_lbl.text = "GXP"
		_sigil_gxp_row.add_child(gxp_lbl)

		_sigil_gxp_spin = SpinBox.new()
		_sigil_gxp_spin.min_value = 1
		_sigil_gxp_spin.max_value = 99999
		_sigil_gxp_spin.step = 1
		_sigil_gxp_spin.value = 100
		_sigil_gxp_spin.custom_minimum_size = Vector2(56, 0)
		_sigil_gxp_row.add_child(_sigil_gxp_spin)

		_btn_add_gxp = Button.new()
		_btn_add_gxp.text = "Add GXP"
		_btn_add_gxp.add_theme_font_size_override("font_size", 8)
		_sigil_gxp_row.add_child(_btn_add_gxp)
		if not _btn_add_gxp.pressed.is_connected(_on_add_sigil_gxp):
			_btn_add_gxp.pressed.connect(_on_add_sigil_gxp)

	# Style the dropdown
	_style_option_button(_sigil_gxp_pick, 8, 210)

func _ensure_bond_row() -> void:
	var parent := _attach_point()
	_bond_row = parent.get_node_or_null("BondRow") as HBoxContainer
	if _bond_row == null:
		_bond_row = HBoxContainer.new()
		_bond_row.name = "BondRow"
		_bond_row.add_theme_constant_override("separation", 3)
		parent.add_child(_bond_row)

		# Character picker
		var lbl := Label.new()
		lbl.text = "Bond:"
		_bond_row.add_child(lbl)

		_bond_pick = OptionButton.new()
		_bond_pick.custom_minimum_size = Vector2(70, 0)
		_bond_row.add_child(_bond_pick)

		# Complete Event (with dialogue score)
		var dlg_lbl := Label.new()
		dlg_lbl.text = "Dlg:"
		_bond_row.add_child(dlg_lbl)

		_dialogue_score_spin = SpinBox.new()
		_dialogue_score_spin.min_value = -3
		_dialogue_score_spin.max_value = 6
		_dialogue_score_spin.step = 1
		_dialogue_score_spin.value = 0
		_dialogue_score_spin.custom_minimum_size = Vector2(35, 0)
		_dialogue_score_spin.tooltip_text = "Dialogue score: -3 to +6 (3×Best = +6)"
		_bond_row.add_child(_dialogue_score_spin)

		_btn_complete_event = Button.new()
		_btn_complete_event.text = "Complete Event"
		_btn_complete_event.add_theme_font_size_override("font_size", 8)
		_btn_complete_event.tooltip_text = "Complete next event (E1-E9) with dialogue score"
		_bond_row.add_child(_btn_complete_event)
		_btn_complete_event.pressed.connect(_on_complete_event)

		# Give Gift
		_gift_reaction_pick = OptionButton.new()
		_gift_reaction_pick.add_item("Liked (+4)")
		_gift_reaction_pick.set_item_metadata(0, "liked")
		_gift_reaction_pick.add_item("Neutral (+1)")
		_gift_reaction_pick.set_item_metadata(1, "neutral")
		_gift_reaction_pick.add_item("Disliked (-2)")
		_gift_reaction_pick.set_item_metadata(2, "disliked")
		_gift_reaction_pick.custom_minimum_size = Vector2(56, 0)
		_bond_row.add_child(_gift_reaction_pick)

		_btn_give_gift = Button.new()
		_btn_give_gift.text = "Give Gift"
		_btn_give_gift.add_theme_font_size_override("font_size", 8)
		_btn_give_gift.tooltip_text = "Give gift (once per layer)"
		_bond_row.add_child(_btn_give_gift)
		_btn_give_gift.pressed.connect(_on_give_gift)

		# Side Meetup
		_btn_side_meetup = Button.new()
		_btn_side_meetup.text = "Side Meetup (+6)"
		_btn_side_meetup.add_theme_font_size_override("font_size", 8)
		_btn_side_meetup.tooltip_text = "Optional filler scene for +6 points"
		_bond_row.add_child(_btn_side_meetup)
		_btn_side_meetup.pressed.connect(_on_side_meetup)

		# Utility buttons
		_btn_mark_known = Button.new()
		_btn_mark_known.text = "Mark Known"
		_btn_mark_known.add_theme_font_size_override("font_size", 8)
		_bond_row.add_child(_btn_mark_known)
		_btn_mark_known.pressed.connect(_on_mark_bond_known)

		_btn_discover_like = Button.new()
		_btn_discover_like.text = "Discover Like"
		_btn_discover_like.add_theme_font_size_override("font_size", 8)
		_bond_row.add_child(_btn_discover_like)
		_btn_discover_like.pressed.connect(_on_discover_like)

		# Raw points adder for testing
		var pts_lbl := Label.new()
		pts_lbl.text = "Pts:"
		_bond_row.add_child(pts_lbl)

		_points_spin = SpinBox.new()
		_points_spin.min_value = -10
		_points_spin.max_value = 20
		_points_spin.step = 1
		_points_spin.value = 1
		_points_spin.custom_minimum_size = Vector2(35, 0)
		_bond_row.add_child(_points_spin)

		_btn_add_points = Button.new()
		_btn_add_points.text = "Add Pts"
		_btn_add_points.add_theme_font_size_override("font_size", 8)
		_btn_add_points.tooltip_text = "Directly add/remove points (cheat)"
		_bond_row.add_child(_btn_add_points)
		_btn_add_points.pressed.connect(_on_add_points)

	# Style the dropdown and populate
	_style_option_button(_bond_pick, 8, 210)
	_refresh_bond_dropdown()

# --- Items (Row1) --------------------------------------------------------------
func _refresh_defs() -> void:
	_defs.clear()
	if _picker:
		_picker.clear()

	if _inv and _inv.has_method("get_item_defs"):
		var v: Variant = _inv.call("get_item_defs")
		if typeof(v) == TYPE_DICTIONARY:
			_defs = v as Dictionary

	if _defs.is_empty() and _csv and _csv.has_method("load_csv"):
		var loaded: Variant = _csv.call("load_csv", ITEMS_CSV, KEY_ID)
		if typeof(loaded) == TYPE_DICTIONARY:
			_defs = loaded as Dictionary

	if _picker == null:
		return

	var ids: Array = _defs.keys()
	ids.sort_custom(Callable(self, "_cmp_ids_by_name"))
	for id_any in ids:
		var item_id: String = String(id_any)
		var rec: Dictionary = _defs.get(item_id, {}) as Dictionary
		var disp: String = String(rec.get("name", item_id))
		var cat: String  = String(rec.get("category", "Other"))
		_picker.add_item("%s — %s [%s]" % [item_id, disp, cat])
		_picker.set_item_metadata(_picker.get_item_count() - 1, item_id)

	print("[ItemsCheatBar] defs refreshed: %d items" % _defs.size())

func _cmp_ids_by_name(a: Variant, b: Variant) -> bool:
	var da: Dictionary = _defs.get(a, {}) as Dictionary
	var db: Dictionary = _defs.get(b, {}) as Dictionary
	var na: String = String(da.get("name", String(a)))
	var nb: String = String(db.get("name", String(b)))
	return na < nb

func _selected_item_id() -> String:
	if _picker == null:
		return ""
	var i: int = _picker.get_selected()
	if i < 0:
		return ""
	return String(_picker.get_item_metadata(i))

func _on_give() -> void:
	var id: String = _selected_item_id()
	var n: int = int(_qty.value) if _qty != null else 0
	if id == "" or n <= 0:
		return
	if _inv and _inv.has_method("add_item"):
		_inv.call("add_item", id, n)
		print("[ItemsCheatBar] GIVE %s x%d" % [id, n])
	if _is_sigil_item(id):
		_draft_n_from_inventory(id, n)
	_refresh_sig_dropdown()
	_refresh_sigil_gxp_dropdown()

func _on_remove() -> void:
	var id: String = _selected_item_id()
	var n: int = int(_qty.value) if _qty != null else 0
	if id == "" or n <= 0:
		return
	if _inv and _inv.has_method("remove_item"):
		_inv.call("remove_item", id, n)
		print("[ItemsCheatBar] REMOVE %s x%d" % [id, n])
	_refresh_sig_dropdown()
	_refresh_sigil_gxp_dropdown()

func _on_give10() -> void:
	var id: String = _selected_item_id()
	if id == "":
		return
	if _inv and _inv.has_method("add_item"):
		_inv.call("add_item", id, 10)
		print("[ItemsCheatBar] GIVE10 %s x10" % [id])
	if _is_sigil_item(id):
		_draft_n_from_inventory(id, 10)
	_refresh_sig_dropdown()
	_refresh_sigil_gxp_dropdown()

func _on_reload() -> void:
	if _csv and _csv.has_method("reload_csv"):
		_csv.call("reload_csv", ITEMS_CSV, KEY_ID)
	if _inv and _inv.has_method("load_definitions"):
		_inv.call("load_definitions")
	print("[ItemsCheatBar] requested reload of item defs")
	_refresh_defs()
	_refresh_sig_dropdown()
	_refresh_sigil_gxp_dropdown()

# callbacks from InventorySystem signals
func _on_inv_defs_loaded() -> void:
	print("[ItemsCheatBar] signal: items_loaded -> refreshing item picker")
	_refresh_defs()

func _on_inv_counts_changed() -> void:
	print("[ItemsCheatBar] signal: inventory_changed")

# ─────────────────────────────────────────────────────────────
# Sigils
# ─────────────────────────────────────────────────────────────
func _log_s(msg: String) -> void:
	if DEBUG_ICB_SIG:
		print("[ItemsCheatBar] ", msg)

func _method_arity(obj: Object, method_name: String) -> int:
	if obj == null:
		return -1
	var lst: Array = obj.get_method_list()
	for m in lst:
		if typeof(m) == TYPE_DICTIONARY and String(m.get("name","")) == method_name:
			var args: Array = m.get("args", [])
			if typeof(args) == TYPE_ARRAY:
				return args.size()
			return 0
	return -1

func _call_list_all_instances(sig: Object, equipped_only: bool) -> Array[String]:
	var out: Array[String] = []
	if sig == null:
		return out

	for meth in ["list_all_instances","list_instances","get_all_instances","get_instances","enumerate_instances"]:
		if not sig.has_method(meth):
			continue

		var argc: int = _method_arity(sig, meth)
		var raw: Variant = null

		if argc == 1:
			raw = sig.call(meth, equipped_only)
		elif argc == 0:
			raw = sig.call(meth)
		else:
			raw = sig.call(meth, equipped_only)
			if raw == null:
				raw = sig.call(meth)

		match typeof(raw):
			TYPE_PACKED_STRING_ARRAY:
				for s in (raw as PackedStringArray):
					out.append(String(s))
			TYPE_ARRAY:
				for v in (raw as Array):
					match typeof(v):
						TYPE_STRING:
							out.append(String(v))
						TYPE_DICTIONARY:
							var d: Dictionary = v as Dictionary
							for k in ["id","instance_id","inst","sid","guid"]:
								if d.has(k) and typeof(d[k]) == TYPE_STRING:
									out.append(String(d[k]))
									break
						_:
							out.append(String(v))
			TYPE_DICTIONARY:
				for k in (raw as Dictionary).keys():
					out.append(String(k))
			_:
				pass

		if out.size() > 0:
			return out

	return out

func _collect_party_tokens() -> Array[String]:
	var out: Array[String] = []
	if _gs and _gs.has_method("get_active_party_ids"):
		var v: Variant = _gs.call("get_active_party_ids")
		if typeof(v) == TYPE_ARRAY:
			for t in (v as Array):
				out.append(String(t))
	if out.is_empty() and _party:
		for m in ["get_active","list_active_members","get_party","list_party","get_active_party"]:
			if _party.has_method(m):
				var pv: Variant = _party.call(m)
				if typeof(pv) == TYPE_ARRAY:
					for s in (pv as Array):
						out.append(String(s))
					break
				elif typeof(pv) == TYPE_PACKED_STRING_ARRAY:
					for s2 in (pv as PackedStringArray):
						out.append(String(s2))
					break
	if out.is_empty() and _gs and _gs.has_method("get"):
		var gpv: Variant = _gs.get("party")
		if typeof(gpv) == TYPE_ARRAY:
			for s3 in (gpv as Array):
				out.append(String(s3))
	if out.is_empty():
		out.append("hero")
	return out

func _append_ids_from_loadout(ids: Array[String], member: String) -> void:
	if _sig == null or not _sig.has_method("get_loadout"):
		return
	var l: Variant = _sig.call("get_loadout", member)
	if typeof(l) == TYPE_ARRAY:
		for s in (l as Array):
			var sid: String = String(s)
			if sid != "":
				ids.append(sid)
	elif typeof(l) == TYPE_PACKED_STRING_ARRAY:
		for s2 in (l as PackedStringArray):
			var sid2: String = String(s2)
			if sid2 != "":
				ids.append(sid2)

func _append_ids_free(ids: Array[String]) -> void:
	if _sig and _sig.has_method("list_free_instances"):
		var v: Variant = _sig.call("list_free_instances")
		if typeof(v) == TYPE_ARRAY:
			for s in (v as Array):
				var sid: String = String(s)
				if sid != "":
					ids.append(sid)
		elif typeof(v) == TYPE_PACKED_STRING_ARRAY:
			for s2 in (v as PackedStringArray):
				var sid2: String = String(s2)
				if sid2 != "":
					ids.append(sid2)

func _refresh_sig_dropdown() -> void:
	if _sig_inst_pick == null:
		_log_s("InstPicker not found. Ensure the node is named 'InstPicker'.")
		return
	_sig_inst_pick.clear()

	if _sig == null:
		_sig_inst_pick.add_item("(No SigilSystem)")
		_sig_inst_pick.disabled = true
		_log_s("aSigilSystem not found at %s" % SIG_PATH)
		_refresh_sigil_gxp_dropdown()
		return

	var equipped_only: bool = (_chk_equipped != null and _chk_equipped.button_pressed)

	var ids: Array[String] = _call_list_all_instances(_sig, equipped_only)

	if ids.is_empty():
		if equipped_only:
			for member in _collect_party_tokens():
				_append_ids_from_loadout(ids, member)
		else:
			_append_ids_free(ids)
			for member2 in _collect_party_tokens():
				_append_ids_from_loadout(ids, member2)

	if ids.is_empty():
		if _auto_seed_one_instance_from_inventory():
			ids = _call_list_all_instances(_sig, false)
			if ids.is_empty():
				_append_ids_free(ids)

	var seen: Dictionary = {}
	var list: Array[String] = []
	for sid in ids:
		if sid == "":
			continue
		if not seen.has(sid):
			seen[sid] = true
			list.append(sid)
	list.sort()

	if list.size() == 0:
		_sig_inst_pick.add_item("— no sigils —")
		_sig_inst_pick.disabled = true
		_refresh_sigil_gxp_dropdown()
		return

	_sig_inst_pick.disabled = false
	for sid2 in list:
		var disp: String = sid2
		if _sig.has_method("get_display_name_for"):
			var nm_v: Variant = _sig.call("get_display_name_for", sid2)
			if typeof(nm_v) == TYPE_STRING:
				disp = String(nm_v)
		_sig_inst_pick.add_item(disp)
		_sig_inst_pick.set_item_metadata(_sig_inst_pick.get_item_count() - 1, sid2)

	# Also refresh the GXP dropdown
	_refresh_sigil_gxp_dropdown()

func _refresh_sigil_gxp_dropdown() -> void:
	if _sigil_gxp_pick == null:
		print("[ItemsCheatBar][GXP] Dropdown not created yet")
		return
	_sigil_gxp_pick.clear()

	if _sig == null:
		_sigil_gxp_pick.add_item("(No SigilSystem)")
		_sigil_gxp_pick.disabled = true
		print("[ItemsCheatBar][GXP] No SigilSystem found")
		return

	# Get all sigils (not just equipped)
	var ids: Array[String] = _call_list_all_instances(_sig, false)
	print("[ItemsCheatBar][GXP] Initial list_all_instances returned: %d sigils" % ids.size())

	# Always try to get free and equipped sigils
	if ids.is_empty():
		print("[ItemsCheatBar][GXP] No sigils from list_all_instances, trying free + loadout")
		_append_ids_free(ids)
		print("[ItemsCheatBar][GXP] After append_ids_free: %d sigils" % ids.size())
		for member in _collect_party_tokens():
			_append_ids_from_loadout(ids, member)
		print("[ItemsCheatBar][GXP] After loadout scan: %d sigils" % ids.size())

	# Try to auto-seed if still empty
	if ids.is_empty():
		print("[ItemsCheatBar][GXP] Still empty, trying auto-seed")
		if _auto_seed_one_instance_from_inventory():
			ids = _call_list_all_instances(_sig, false)
			if ids.is_empty():
				_append_ids_free(ids)
			print("[ItemsCheatBar][GXP] After auto-seed: %d sigils" % ids.size())

	# Deduplicate
	var seen: Dictionary = {}
	var list: Array[String] = []
	for sid in ids:
		if sid == "":
			continue
		if not seen.has(sid):
			seen[sid] = true
			list.append(sid)
	list.sort()

	print("[ItemsCheatBar][GXP] Final unique list: %d sigils" % list.size())

	if list.size() == 0:
		_sigil_gxp_pick.add_item("— no sigils —")
		_sigil_gxp_pick.disabled = true
		print("[ItemsCheatBar][GXP] No sigils to display")
		return

	_sigil_gxp_pick.disabled = false
	for sid2 in list:
		var disp: String = sid2
		if _sig.has_method("get_display_name_for"):
			var nm_v: Variant = _sig.call("get_display_name_for", sid2)
			if typeof(nm_v) == TYPE_STRING:
				disp = String(nm_v)
		_sigil_gxp_pick.add_item(disp)
		_sigil_gxp_pick.set_item_metadata(_sigil_gxp_pick.get_item_count() - 1, sid2)

	print("[ItemsCheatBar][GXP] Dropdown populated with %d items" % _sigil_gxp_pick.get_item_count())

func _selected_sig_inst() -> String:
	if _sig_inst_pick == null:
		return ""
	var i: int = _sig_inst_pick.get_selected()
	if i < 0:
		return ""
	return String(_sig_inst_pick.get_item_metadata(i))

func _selected_sigil_gxp() -> String:
	if _sigil_gxp_pick == null:
		return ""
	var i: int = _sigil_gxp_pick.get_selected()
	if i < 0:
		return ""
	return String(_sigil_gxp_pick.get_item_metadata(i))

func _on_equipped_toggle(_pressed: bool) -> void:
	_refresh_sig_dropdown()
	_refresh_sigil_gxp_dropdown()

func _on_loadout_changed(_member: String) -> void:
	_refresh_sig_dropdown()
	_refresh_sigil_gxp_dropdown()

func _on_sigil_changed(_arg: Variant = null) -> void:
	_refresh_sig_dropdown()
	_refresh_sigil_gxp_dropdown()

func _grant_xp_to_sigil(amount: int) -> void:
	if _sig == null:
		return
	var id: String = _selected_sig_inst()
	if id == "":
		return
	var require_equipped: bool = (_chk_equipped != null and _chk_equipped.button_pressed)
	if _sig.has_method("cheat_add_xp_to_instance"):
		_sig.call("cheat_add_xp_to_instance", id, amount, require_equipped)
	_refresh_sig_dropdown()
	_refresh_sigil_gxp_dropdown()

func _on_sig_lv_up() -> void:
	if _sig == null:
		return
	var id: String = _selected_sig_inst()
	if id == "":
		return
	var lvl: int = 1
	if _sig.has_method("get_instance_level"):
		var got: Variant = _sig.call("get_instance_level", id)
		if typeof(got) == TYPE_INT or typeof(got) == TYPE_FLOAT:
			lvl = int(got)
	var new_lvl: int = clampi(lvl + 1, 1, 4)
	if _sig.has_method("cheat_set_instance_level"):
		_sig.call("cheat_set_instance_level", id, new_lvl)
	_refresh_sig_dropdown()
	_refresh_sigil_gxp_dropdown()

func _on_sig_lv_dn() -> void:
	if _sig == null:
		return
	var id: String = _selected_sig_inst()
	if id == "":
		return
	var lvl: int = 1
	if _sig.has_method("get_instance_level"):
		var got: Variant = _sig.call("get_instance_level", id)
		if typeof(got) == TYPE_INT or typeof(got) == TYPE_FLOAT:
			lvl = int(got)
	var new_lvl: int = clampi(lvl - 1, 1, 4)
	if _sig.has_method("cheat_set_instance_level"):
		_sig.call("cheat_set_instance_level", id, new_lvl)
	_refresh_sig_dropdown()
	_refresh_sigil_gxp_dropdown()

func _on_sig_xp_25() -> void:
	_grant_xp_to_sigil(25)

func _on_sig_xp_100() -> void:
	_grant_xp_to_sigil(100)

func _on_add_sigil_gxp() -> void:
	if _sigil_gxp_spin == null or _sig == null:
		return
	var sigil_id: String = _selected_sigil_gxp()
	if sigil_id == "":
		print("[ItemsCheatBar][GXP] No sigil selected for GXP")
		return
	var amount: int = int(_sigil_gxp_spin.value)

	# Call the correct SigilSystem method: cheat_add_xp_to_instance
	# Note: require_equipped is set to false since we're cheating
	if _sig.has_method("cheat_add_xp_to_instance"):
		_sig.call("cheat_add_xp_to_instance", sigil_id, amount, false)
		print("[ItemsCheatBar][GXP] Added %d GXP to sigil %s" % [amount, sigil_id])
	elif _sig.has_method("add_xp_to_instance"):
		_sig.call("add_xp_to_instance", sigil_id, amount, false)
		print("[ItemsCheatBar][GXP] Added %d GXP to sigil %s (via add_xp_to_instance)" % [amount, sigil_id])
	else:
		print("[ItemsCheatBar][GXP] ERROR: No XP method found on SigilSystem!")
		print("[ItemsCheatBar][GXP] Available methods: %s" % str(_sig.get_method_list().map(func(m): return m.get("name", ""))))

	_refresh_sig_dropdown()
	_refresh_sigil_gxp_dropdown()

# ─────────────────────────────────────────────────────────────
# Character Level / Perk / SXP
# ─────────────────────────────────────────────────────────────
func _populate_stat_picker() -> void:
	if _stat_pick == null:
		return
	_stat_pick.clear()
	var stats: Array[String] = ["BRW","MND","TPO","VTL","FCS"]
	for s in stats:
		_stat_pick.add_item(s)
		_stat_pick.set_item_metadata(_stat_pick.get_item_count() - 1, s)
	_stat_pick.select(0)

func _current_member_id() -> String:
	if _roster_pick:
		var idx: int = _roster_pick.get_selected()
		if idx >= 0:
			return String(_roster_pick.get_item_metadata(idx))
	if _member_id_le and _member_id_le.text.strip_edges() != "":
		return _member_id_le.text.strip_edges()
	return "hero"

func _get_member_level() -> int:
	var member_id: String = _current_member_id()
	return _get_member_level_of(member_id)

func _get_member_level_of(member_id: String) -> int:
	if _stats and _stats.has_method("get_member_level"):
		var v: Variant = _stats.call("get_member_level", member_id)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			return int(v)
	if member_id == "hero" and _hero:
		var lv_v: Variant = _hero.get("level")
		if typeof(lv_v) == TYPE_INT or typeof(lv_v) == TYPE_FLOAT:
			return int(lv_v)
	if _stats and _stats.has("_party_progress"):
		var all_v: Variant = _stats.get("_party_progress")
		if typeof(all_v) == TYPE_DICTIONARY:
			var all: Dictionary = all_v as Dictionary
			if all.has(member_id):
				var prog: Dictionary = all[member_id]
				if prog.has("char_level"):
					return int(prog["char_level"])
	return 1

func _on_lvl_m1() -> void:
	_set_member_level_delta(-1)

func _on_lvl_p1() -> void:
	_set_member_level_delta(1)

func _on_set_level() -> void:
	if _spin_lvl == null:
		return
	_set_member_level_exact(int(_spin_lvl.value))

func _on_bpp_p1() -> void:
	_add_perk_points(1)

func _on_bpp_p5() -> void:
	_add_perk_points(5)

func _on_add_sxp() -> void:
	if _stat_pick == null or _sxp_amt == null:
		return
	var i: int = _stat_pick.get_selected()
	if i < 0:
		return
	var stat_id: String = String(_stat_pick.get_item_metadata(i))
	var amt: int = int(_sxp_amt.value)
	_add_sxp_to_member(stat_id, amt)

func _on_add_xp() -> void:
	if _xp_amt == null:
		return
	_grant_xp_to_member(int(_xp_amt.value))

# --- Hero handlers -------------------------------------------------------------
func _on_hero_add_xp() -> void:
	if _hero_xp_spin == null:
		return
	_grant_xp_to_member_id("hero", int(_hero_xp_spin.value))

func _on_hero_add_sxp() -> void:
	if _hero_stat_pick == null or _hero_sxp_spin == null:
		return
	var idx: int = _hero_stat_pick.get_selected()
	if idx < 0:
		return
	var stat_id: String = String(_hero_stat_pick.get_item_metadata(idx))
	_add_sxp_to_member_id("hero", stat_id, int(_hero_sxp_spin.value))

# --- Level helpers ---
func _set_member_level_delta(delta: int) -> void:
	var cur: int = _get_member_level()
	_set_member_level_exact(cur + delta)

func _set_member_level_exact(new_level: int) -> void:
	var member_id: String = _current_member_id()
	new_level = clampi(new_level, 1, 99)
	var old_level: int = _get_member_level()
	if new_level == old_level:
		return

	if member_id != "hero":
		var prog: Dictionary = _ensure_member_progress(member_id)
		if prog.size() > 0:
			prog["char_level"] = new_level
			if _stats and _stats.has("_party_progress"):
				var all_v: Variant = _stats.get("_party_progress")
				if typeof(all_v) == TYPE_DICTIONARY:
					var d: Dictionary = all_v
					d[member_id] = prog.duplicate(true)
					_stats.set("_party_progress", d)
	else:
		if _hero:
			_hero.set("level", new_level)
		_recalc_hero_hp_mp(new_level)

	if member_id == "hero":
		var gained_bpp: int = int(floor(new_level / 3.0)) - int(floor(old_level / 3.0))
		if gained_bpp > 0:
			_add_perk_points(gained_bpp)

	if _spin_lvl and member_id == _current_member_id():
		_spin_lvl.value = new_level

	print("[ItemsCheatBar] Set Level -> %s | Lv %d → %d" % [member_id, old_level, new_level])
	_emit_refresh()

# --- Character XP --------------------------------------------------------------
func _xp_to_next_level(level: int) -> int:
	return 120 + 30 * level + 6 * level * level

func _grant_xp_to_member(amount: int) -> void:
	_grant_xp_to_member_id(_current_member_id(), amount)

func _grant_xp_to_member_id(member_id: String, amount: int) -> void:
	if amount <= 0 or _stats == null:
		return
	var before: int = _get_member_level_of(member_id)
	if _stats.has_method("add_xp"):
		_stats.call("add_xp", member_id, amount)
	var after: int = _get_member_level_of(member_id)
	print("[ItemsCheatBar] +%d LXP -> %s | Lv %d → %d" % [amount, member_id, before, after])
	_emit_refresh()

# --- SXP (stat XP) -------------------------------------------------------------
func _add_sxp_to_member(stat_id: String, amount: int) -> void:
	_add_sxp_to_member_id(_current_member_id(), stat_id, amount)

func _add_sxp_to_member_id(member_id: String, stat_id: String, amount: int) -> void:
	if amount <= 0:
		return
	stat_id = stat_id.strip_edges().to_upper()

	var applied: int = amount
	if _stats and (_stats.has_method("add_sxp_to_member") or _stats.has_method("add_member_sxp")):
		if _stats.has_method("add_sxp_to_member"):
			var ret: Variant = _stats.call("add_sxp_to_member", member_id, stat_id, amount)
			if typeof(ret) == TYPE_INT or typeof(ret) == TYPE_FLOAT:
				applied = int(ret)
		else:
			var ret2: Variant = _stats.call("add_member_sxp", member_id, stat_id, amount)
			if typeof(ret2) == TYPE_INT or typeof(ret2) == TYPE_FLOAT:
				applied = int(ret2)
	else:
		var prog: Dictionary = _ensure_member_progress(member_id)
		if prog.size() == 0:
			return
		var sxp: Dictionary = prog.get("sxp", {}) as Dictionary
		if sxp.is_empty():
			sxp = {"BRW":0,"MND":0,"TPO":0,"VTL":0,"FCS":0}
		sxp[stat_id] = int(sxp.get(stat_id, 0)) + amount
		prog["sxp"] = sxp
		if _stats and _stats.has("_party_progress"):
			var all_v: Variant = _stats.get("_party_progress")
			if typeof(all_v) == TYPE_DICTIONARY:
				var d: Dictionary = all_v
				d[member_id] = prog.duplicate(true)
				_stats.set("_party_progress", d)

	var new_stat_lv: int = 1
	if _stats and _stats.has_method("get_member_stat_level"):
		var lv_v: Variant = _stats.call("get_member_stat_level", member_id, stat_id)
		if typeof(lv_v) == TYPE_INT or typeof(lv_v) == TYPE_FLOAT:
			new_stat_lv = int(lv_v)

	print("[ItemsCheatBar] +%d SXP (%s) -> %s | Stat Lv now %d (applied %d)" % [amount, stat_id, member_id, new_stat_lv, applied])
	_emit_refresh()

# --- Perk points (hero) --------------------------------------------------------
func _add_perk_points(points: int) -> void:
	if points == 0:
		return
	if _gs and _gs.has_method("get") and _gs.has_method("set"):
		var cur_v: Variant = _gs.get("perk_points")
		var cur: int = 0
		if typeof(cur_v) == TYPE_INT or typeof(cur_v) == TYPE_FLOAT:
			cur = int(cur_v)
		_gs.set("perk_points", max(0, cur + points))
	if _perk:
		if _perk.has_method("add_points"):
			_perk.call("add_points", points)
		elif _perk.has_method("grant_points"):
			_perk.call("grant_points", points)
	_emit_refresh()

# ─────────────────────────────────────────────────────────────
# Party (Row4) + CSV import → Dorms Common + Relationships
# ─────────────────────────────────────────────────────────────
func _on_roster_pick_selected(_index: int) -> void:
	if _spin_lvl:
		_spin_lvl.value = _get_member_level()
	_refresh_sig_dropdown()

func _selected_roster_id() -> String:
	if _roster_pick == null:
		return ""
	var i: int = _roster_pick.get_selected()
	if i < 0:
		return ""
	return String(_roster_pick.get_item_metadata(i))

func _member_id_from_ui_row4() -> String:
	var id: String = _selected_roster_id()
	if id != "":
		return id
	if _member_id_le and _member_id_le.text.strip_edges() != "":
		return _member_id_le.text.strip_edges()
	return ""

func _on_add_to_party() -> void:
	var id: String = _member_id_from_ui_row4()
	if id == "":
		return
	var _added := false
	if _party:
		for m in ["add_member","add_to_party","recruit","try_add_member"]:
			if _party.has_method(m):
				_party.call(m, id)
				_added = true
				break
	elif _gs:
		var cur: Array = []
		if _gs.has_method("get"):
			var v: Variant = _gs.get("party")
			if typeof(v) == TYPE_ARRAY:
				cur = v
		if not cur.has(id):
			cur.append(id)
			_added = true
			if _gs.has_method("set"):
				_gs.set("party", cur)

	# Also push to Dorms Common & seed relationships from CSV (if available)
	_push_to_dorm_common([id])
	_apply_relationships_from_csv([id])

	_emit_party_changed()
	_refresh_roster_picker()

func _on_remove_from_party() -> void:
	var id: String = _member_id_from_ui_row4()
	if id == "":
		return
	if _party and _party.has_method("remove_member"):
		_party.call("remove_member", id)
	elif _gs and _gs.has_method("get") and _gs.has_method("set"):
		var cur: Array = []
		var v: Variant = _gs.get("party")
		if typeof(v) == TYPE_ARRAY:
			cur = v
		if cur.has(id):
			cur.erase(id)
			_gs.set("party", cur)
	_emit_party_changed()
	_refresh_roster_picker()

func _on_move_to_bench() -> void:
	var id: String = _member_id_from_ui_row4()
	if id == "":
		return
	if _gs and _gs.has_method("get") and _gs.has_method("set"):
		var cur: Array = []
		var v: Variant = _gs.get("party")
		if typeof(v) == TYPE_ARRAY:
			cur = v
		if cur.has(id):
			cur.erase(id)
			_gs.set("party", cur)
		var bench: Array = []
		var b: Variant = _gs.get("bench")
		if typeof(b) == TYPE_ARRAY:
			bench = b
		if not bench.has(id):
			bench.append(id)
		_gs.set("bench", bench)
	_emit_party_changed()
	_refresh_roster_picker()

func _emit_party_changed() -> void:
	if _party and _party.has_signal("party_changed"):
		_party.emit_signal("party_changed")
	elif _gs and _gs.has_signal("party_changed"):
		_gs.emit_signal("party_changed")

func _refresh_roster_picker() -> void:
	if _roster_pick == null:
		return
	_roster_pick.clear()

	_party_defs_by_id.clear()
	_party_csv_path = ""
	for p in PARTY_CSV_CANDIDATES:
		if ResourceLoader.exists(p):
			_party_csv_path = p
			break

	if _party_csv_path != "" and _csv and _csv.has_method("load_csv"):
		for id_key in PARTY_ID_KEYS:
			var loaded: Variant = _csv.call("load_csv", _party_csv_path, String(id_key))
			if typeof(loaded) == TYPE_DICTIONARY and (loaded as Dictionary).size() > 0:
				_party_defs_by_id = loaded as Dictionary
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

	var list: Array[String] = _collect_all_known_members()
	for rid2 in list:
		_roster_pick.add_item(String(rid2).capitalize())
		_roster_pick.set_item_metadata(_roster_pick.get_item_count() - 1, String(rid2))

func _extract_display_from_row(row: Dictionary, rid: String) -> String:
	var disp: String = ""
	for k in PARTY_NAME_KEYS:
		if row.has(k) and typeof(row[k]) == TYPE_STRING:
			var s: String = String(row[k]).strip_edges()
			if s != "":
				disp = s
				break
	if disp == "":
		disp = rid
	return disp

func _collect_all_known_members() -> Array[String]:
	var out: Array[String] = []

	# Ask the PartySystem (if present)
	if _party:
		var methods: Array[String] = [
			"list_all_member_ids", "get_party", "list_party",
			"get_active_party", "list_active_members"
		]
		for m in methods:
			if _party.has_method(m):
				var v: Variant = _party.call(m)
				if typeof(v) == TYPE_ARRAY:
					for val in (v as Array):
						out.append(String(val))
				elif typeof(v) == TYPE_PACKED_STRING_ARRAY:
					for val2 in (v as PackedStringArray):
						out.append(String(val2))
				if out.size() > 0:
					break

	# Also merge anything the GameState knows about (party + bench)
	if _gs and _gs.has_method("get"):
		var p_v: Variant = _gs.get("party")
		if typeof(p_v) == TYPE_ARRAY:
			for s3 in (p_v as Array):
				var a: String = String(s3)
				if not out.has(a):
					out.append(a)

		var b_v: Variant = _gs.get("bench")
		if typeof(b_v) == TYPE_ARRAY:
			for s4 in (b_v as Array):
				var t: String = String(s4)
				if not out.has(t):
					out.append(t)

	out.sort()
	return out

# --- CSV Import helpers --------------------------------------------------------
func _load_party_csv_defs() -> void:
	if not _party_defs_by_id.is_empty():
		return
	_party_csv_path = ""
	for p in PARTY_CSV_CANDIDATES:
		if ResourceLoader.exists(p):
			_party_csv_path = p
			break
	if _party_csv_path == "" or _csv == null or not _csv.has_method("load_csv"):
		return
	for id_key in PARTY_ID_KEYS:
		var loaded: Variant = _csv.call("load_csv", _party_csv_path, String(id_key))
		if typeof(loaded) == TYPE_DICTIONARY and (loaded as Dictionary).size() > 0:
			_party_defs_by_id = loaded as Dictionary
			break

func _row_flag_is_active(row: Dictionary) -> bool:
	for k in PARTY_ACTIVE_KEYS:
		if row.has(k):
			var v: Variant = row[k]
			match typeof(v):
				TYPE_BOOL:
					if bool(v):
						return true
				TYPE_INT, TYPE_FLOAT:
					if int(v) != 0:
						return true
				TYPE_STRING:
					var s: String = String(v).strip_edges().to_lower()
					if s == "1" or s == "true" or s == "yes" or s == "y" or s == "on" or s == "start" or s == "starter" or s == "active":
						return true
	return false

func _parse_id_list_field(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(v) == TYPE_STRING:
		var s: String = String(v)
		s = s.replace(";", ",").replace("|", ",")
		var parts: PackedStringArray = s.split(",", false)
		for part in parts:
			var t: String = String(part).strip_edges()
			if t != "":
				out.append(t)
	return out

func _get_ids_from_row(row: Dictionary, keys: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for k in keys:
		if row.has(k):
			var v: Variant = row[k]
			var parsed: Array[String] = _parse_id_list_field(v)
			for idv in parsed:
				if not out.has(idv):
					out.append(idv)
	return out

func _on_import_all() -> void:
	_load_party_csv_defs()
	if _party_defs_by_id.is_empty():
		print("[ItemsCheatBar] party.csv not found.")
		return
	var ids_any: Array = _party_defs_by_id.keys()
	var ids: Array[String] = []
	for any_id in ids_any:
		ids.append(String(any_id))
	_push_to_dorm_common(ids)
	_apply_relationships_from_csv(ids)
	print("[ItemsCheatBar] Imported %d members to Dorm Common." % ids.size())

func _on_import_starters() -> void:
	_load_party_csv_defs()
	if _party_defs_by_id.is_empty():
		print("[ItemsCheatBar] party.csv not found.")
		return
	var ids: Array[String] = []
	for id_any in _party_defs_by_id.keys():
		var rid: String = String(id_any)
		var row: Dictionary = _party_defs_by_id.get(rid, {}) as Dictionary
		if _row_flag_is_active(row):
			ids.append(rid)
	_push_to_dorm_common(ids)
	_apply_relationships_from_csv(ids)
	print("[ItemsCheatBar] Imported starters (%d) to Dorm Common." % ids.size())

func _on_give_test_items() -> void:
	if _csv == null or _inv == null:
		print("[ItemsCheatBar] CSV or Inventory system not available")
		return

	var test_items: Variant = _csv.call("load_csv", TEST_AILMENT_ITEMS_CSV, KEY_ID)
	if typeof(test_items) != TYPE_DICTIONARY:
		print("[ItemsCheatBar] Failed to load test items from %s" % TEST_AILMENT_ITEMS_CSV)
		return

	var test_items_dict: Dictionary = test_items as Dictionary
	if test_items_dict.is_empty():
		print("[ItemsCheatBar] No test items found in CSV")
		return

	# Register each test item in inventory definitions and add 10 to inventory
	for item_id in test_items_dict.keys():
		var item_data: Dictionary = test_items_dict[item_id] as Dictionary
		_inv.item_defs[item_id] = item_data
		_inv.call("add_item", item_id, 10)

	# Emit signal to refresh inventory UI
	if _inv.has_signal("items_changed"):
		_inv.emit_signal("items_changed")

	print("[ItemsCheatBar] Added %d test items (x10 each)" % test_items_dict.size())
	_refresh_defs()

func _push_to_dorm_common(member_ids: Array[String]) -> void:
	if member_ids.size() == 0:
		return
	if _dorm and _dorm.has_method("cheat_add_to_common"):
		for idv in member_ids:
			_dorm.call("cheat_add_to_common", idv)

func _apply_relationships_from_csv(member_ids: Array[String]) -> void:
	# Build bestie/rival maps from CSV rows (only for given ids if provided)
	_load_party_csv_defs()
	if _party_defs_by_id.is_empty():
		return

	var bestie_map: Dictionary = {}  # actor_id -> Array[String]
	var rival_map : Dictionary = {}

	var consider_all: bool = (member_ids.size() == 0)

	for id_any in _party_defs_by_id.keys():
		var aid: String = String(id_any)
		if not consider_all and not member_ids.has(aid):
			continue
		var row: Dictionary = _party_defs_by_id.get(aid, {}) as Dictionary
		var besties: Array[String] = _get_ids_from_row(row, PARTY_BESTIE_KEYS)
		var rivals : Array[String] = _get_ids_from_row(row, PARTY_RIVAL_KEYS)
		if besties.size() > 0:
			bestie_map[aid] = besties
		if rivals.size() > 0:
			rival_map[aid] = rivals

	# Pass to an Affinity/Dorm system if available (method names are probed)
	if _aff:
		if _aff.has_method("register_bestie_rival_map"):
			_aff.call("register_bestie_rival_map", bestie_map, rival_map)
		elif _aff.has_method("set_pair_hints"):
			_aff.call("set_pair_hints", bestie_map, rival_map)
	elif _dorm:
		# If DormsSystem exposes any hint method, use it; otherwise just log.
		if _dorm.has_method("register_bestie_rival_map"):
			_dorm.call("register_bestie_rival_map", bestie_map, rival_map)
		elif _dorm.has_method("set_pair_hints"):
			_dorm.call("set_pair_hints", bestie_map, rival_map)
		else:
			print("[ItemsCheatBar] Relationship hints built but no system accepted them (ok).")

# --- Internals -----------------------------------------------------------------
func _ensure_member_progress(member_id: String) -> Dictionary:
	if _stats == null:
		return {}
	if _stats.has_method("_ensure_progress"):
		var prog_v: Variant = _stats.call("_ensure_progress", member_id)
		if typeof(prog_v) == TYPE_DICTIONARY:
			return prog_v as Dictionary

	var all_v: Variant = _stats.get("_party_progress")
	var all: Dictionary = {}
	if typeof(all_v) == TYPE_DICTIONARY:
		all = all_v as Dictionary
	if all.has(member_id):
		return all[member_id] as Dictionary

	var zeros: Dictionary = {"BRW":0,"MND":0,"TPO":0,"VTL":0,"FCS":0}
	var seeded: Dictionary = {
		"label": member_id,
		"char_level": 1,
		"start": {"BRW":1,"MND":1,"TPO":1,"VTL":1,"FCS":1},
		"sxp": zeros.duplicate(),
		"tenths": zeros.duplicate(),
		"dsi_tenths": {"BRW":10,"MND":20,"TPO":30,"VTL":10,"FCS":30}
	}
	all[member_id] = seeded
	_stats.set("_party_progress", all)
	return seeded

func _recalc_hero_hp_mp(new_level: int) -> void:
	var vtl: int = 1
	var fcs: int = 1
	if _stats and _stats.has_method("get_stat"):
		var vtl_v: Variant = _stats.call("get_stat", "VTL")
		if typeof(vtl_v) == TYPE_INT or typeof(vtl_v) == TYPE_FLOAT:
			vtl = int(vtl_v)
		var fcs_v: Variant = _stats.call("get_stat", "FCS")
		if typeof(fcs_v) == TYPE_INT or typeof(fcs_v) == TYPE_FLOAT:
			fcs = int(fcs_v)

	var new_hp_max: int = 150 + (max(1, vtl) * max(1, new_level) * 6)
	var new_mp_max: int = 20 + int(round(float(max(1, fcs)) * float(max(1, new_level)) * 1.5))

	if _hero:
		_hero.set("level", new_level)
		_hero.set("hp_max", new_hp_max)
		_hero.set("hp", new_hp_max)
		_hero.set("mp_max", new_mp_max)
		_hero.set("mp", new_mp_max)

func _emit_refresh() -> void:
	if _stats and _stats.has_signal("stats_changed"):
		_stats.emit_signal("stats_changed")

# ---------- Sigil helpers: detect + draft from inventory -----------------------
func _is_sigil_item(item_id: String) -> bool:
	if item_id == "":
		return false
	var rec: Dictionary = _defs.get(item_id, {}) as Dictionary
	for k in ["equip_slot","slot","equip","equip_to","category","cat","type"]:
		if rec.has(k) and typeof(rec[k]) == TYPE_STRING:
			var tag: String = String(rec[k]).strip_edges().to_lower()
			if tag == "sigil" or tag == "sigils":
				return true
	return false

func _draft_n_from_inventory(base_id: String, n: int) -> int:
	if _sig == null or n <= 0:
		return 0
	var made: int = 0
	for i in range(n):
		if _sig.has_method("draft_from_inventory"):
			var inst_v: Variant = _sig.call("draft_from_inventory", base_id)
			if typeof(inst_v) == TYPE_STRING and String(inst_v) != "":
				made += 1
			else:
				break
		elif _sig.has_method("create_instance"):
			var inst2: Variant = _sig.call("create_instance", base_id)
			if typeof(inst2) == TYPE_STRING and String(inst2) != "":
				made += 1
				if _inv:
					if _inv.has_method("dec"):
						_inv.call("dec", base_id, 1)
					elif _inv.has_method("consume"):
						_inv.call("consume", base_id, 1)
					elif _inv.has_method("decrement"):
						_inv.call("decrement", base_id, 1)
					elif _inv.has_method("add"):
						_inv.call("add", base_id, -1)
			else:
				break
	return made

func _auto_seed_one_instance_from_inventory() -> bool:
	if _inv == null or _sig == null:
		return false
	var counts: Dictionary = {}
	if _inv.has_method("get_counts_dict"):
		var c_v: Variant = _inv.call("get_counts_dict")
		if typeof(c_v) == TYPE_DICTIONARY:
			counts = c_v as Dictionary
	if counts.is_empty():
		return false

	for id_v in counts.keys():
		var id: String = String(id_v)
		var n: int = int(counts.get(id, 0))
		if n <= 0:
			continue
		if _is_sigil_item(id):
			return _draft_n_from_inventory(id, 1) > 0
	return false

# ─────────────────────────────────────────────────────────────
# Bond System Cheats
# ─────────────────────────────────────────────────────────────

func _refresh_bond_dropdown() -> void:
	if _bond_pick == null or _bonds == null:
		return
	_bond_pick.clear()

	var ids: PackedStringArray = PackedStringArray()
	if _bonds.has_method("get_ids"):
		ids = _bonds.call("get_ids")

	if ids.is_empty():
		_bond_pick.add_item("— no bonds —")
		_bond_pick.disabled = true
		return

	_bond_pick.disabled = false
	for bond_id in ids:
		var disp_name: String = bond_id
		if _bonds.has_method("get_display_name"):
			var nm_v: Variant = _bonds.call("get_display_name", bond_id)
			if typeof(nm_v) == TYPE_STRING:
				disp_name = String(nm_v)
		_bond_pick.add_item(disp_name)
		_bond_pick.set_item_metadata(_bond_pick.get_item_count() - 1, bond_id)

func _selected_bond_id() -> String:
	if _bond_pick == null:
		return ""
	var idx: int = _bond_pick.get_selected()
	if idx < 0:
		return ""
	return String(_bond_pick.get_item_metadata(idx))

## Complete next event with dialogue score
func _on_complete_event() -> void:
	if _bonds == null or _dialogue_score_spin == null:
		return
	var bond_id: String = _selected_bond_id()
	if bond_id == "":
		print("[ItemsCheatBar][Bonds] No bond selected")
		return

	var dialogue_score: int = int(_dialogue_score_spin.value)

	if _bonds.has_method("complete_event"):
		_bonds.call("complete_event", bond_id, dialogue_score)
		var event_idx: int = 0
		if _bonds.has_method("get_event_index"):
			event_idx = int(_bonds.call("get_event_index", bond_id))
		print("[ItemsCheatBar][Bonds] Completed event E%d for %s (dialogue: %+d)" % [event_idx, bond_id, dialogue_score])
	else:
		print("[ItemsCheatBar][Bonds] ERROR: complete_event method not found")

## Give gift with reaction
func _on_give_gift() -> void:
	if _bonds == null or _gift_reaction_pick == null:
		return
	var bond_id: String = _selected_bond_id()
	if bond_id == "":
		print("[ItemsCheatBar][Bonds] No bond selected")
		return

	var idx: int = _gift_reaction_pick.get_selected()
	var reaction: String = String(_gift_reaction_pick.get_item_metadata(idx))

	if _bonds.has_method("give_gift"):
		var success: bool = bool(_bonds.call("give_gift", bond_id, reaction))
		if success:
			print("[ItemsCheatBar][Bonds] Gave %s gift to %s" % [reaction, bond_id])
		else:
			print("[ItemsCheatBar][Bonds] Gift failed (already used this layer?)")
	else:
		print("[ItemsCheatBar][Bonds] ERROR: give_gift method not found")

## Do side meetup
func _on_side_meetup() -> void:
	if _bonds == null:
		return
	var bond_id: String = _selected_bond_id()
	if bond_id == "":
		print("[ItemsCheatBar][Bonds] No bond selected")
		return

	if _bonds.has_method("do_side_meetup"):
		_bonds.call("do_side_meetup", bond_id)
		print("[ItemsCheatBar][Bonds] Did side meetup with %s (+6 points)" % bond_id)
	else:
		print("[ItemsCheatBar][Bonds] ERROR: do_side_meetup method not found")

## Add points directly (cheat/testing)
func _on_add_points() -> void:
	if _bonds == null or _points_spin == null:
		return
	var bond_id: String = _selected_bond_id()
	if bond_id == "":
		print("[ItemsCheatBar][Bonds] No bond selected")
		return
	var amount: int = int(_points_spin.value)

	# Use internal _add_points or fallback to add_bxp
	if _bonds.has_method("add_bxp"):
		_bonds.call("add_bxp", bond_id, amount)
		print("[ItemsCheatBar][Bonds] Added %d points to %s" % [amount, bond_id])
	else:
		print("[ItemsCheatBar][Bonds] ERROR: add_bxp method not found")

func _on_mark_bond_known() -> void:
	if _bonds == null:
		return
	var bond_id: String = _selected_bond_id()
	if bond_id == "":
		print("[ItemsCheatBar][Bonds] No bond selected")
		return

	if _bonds.has_method("set_known"):
		_bonds.call("set_known", bond_id, true)
		print("[ItemsCheatBar][Bonds] Marked %s as known" % bond_id)
	else:
		print("[ItemsCheatBar][Bonds] ERROR: set_known method not found")

func _on_discover_like() -> void:
	if _bonds == null:
		return
	var bond_id: String = _selected_bond_id()
	if bond_id == "":
		print("[ItemsCheatBar][Bonds] No bond selected")
		return

	# Discover first like from their gift_likes list
	if _bonds.has_method("get_likes"):
		var likes: PackedStringArray = PackedStringArray()
		var likes_v: Variant = _bonds.call("get_likes", bond_id)
		if typeof(likes_v) == TYPE_PACKED_STRING_ARRAY:
			likes = likes_v
		elif typeof(likes_v) == TYPE_ARRAY:
			for item in (likes_v as Array):
				likes.append(String(item))

		if likes.size() > 0:
			var first_like: String = likes[0]
			if _bonds.has_method("mark_gift_discovered"):
				_bonds.call("mark_gift_discovered", bond_id, first_like, "liked")
				print("[ItemsCheatBar][Bonds] Discovered like: %s for %s" % [first_like, bond_id])
			else:
				print("[ItemsCheatBar][Bonds] ERROR: mark_gift_discovered method not found")
		else:
			print("[ItemsCheatBar][Bonds] No likes defined for %s" % bond_id)
	else:
		print("[ItemsCheatBar][Bonds] ERROR: get_likes method not found")
