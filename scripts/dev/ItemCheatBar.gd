extends Control
class_name ItemsCheatBar

const INV_PATH   := "/root/aInventorySystem"
const CSV_PATH   := "/root/aCSVLoader"
const SIG_PATH   := "/root/aSigilSystem"
const GS_PATH    := "/root/aGameState"
const HERO_PATH  := "/root/aHeroSystem"
const STATS_PATH := "/root/aStatsSystem"
const PERK_PATH  := "/root/aPerkSystem"
const PARTY_PATH := "/root/aPartySystem"

const ITEMS_CSV := "res://data/items/items.csv"
const KEY_ID    := "item_id"

# Candidate CSVs for party roster (first existing wins)
const PARTY_CSV_CANDIDATES: PackedStringArray = [
	"res://data/party/party.csv",
	"res://data/Party.csv",
	"res://data/party.csv",
	"res://data/characters/party.csv",
	"res://data/actors/party.csv",
	"res://data/actors.csv"
]

# Column name candidates in the Party CSV
const PARTY_ID_KEYS:   PackedStringArray = ["actor_id", "id", "actor", "member_id"]
const PARTY_NAME_KEYS: PackedStringArray = ["name", "display_name", "disp_name"]

# --- find-by-name (path agnostic)
func _ctl(node_name: String) -> Node:
	return find_child(node_name, true, false)

# Row1 (Items)
@onready var _picker : OptionButton = _ctl("Picker") as OptionButton
@onready var _qty    : SpinBox      = _ctl("Qty") as SpinBox
@onready var _give   : Button       = _ctl("BtnGive") as Button
@onready var _rem    : Button       = _ctl("BtnRemove") as Button
@onready var _give10 : Button       = _ctl("BtnGive10") as Button
@onready var _reload : Button       = _ctl("BtnReloadCSV") as Button

# Row2 (Sigils)
var _row2            : HBoxContainer = null
var _sig_inst_pick   : OptionButton  = null
var _btn_lv_up       : Button        = null
var _btn_lv_down     : Button        = null
var _btn_xp_25       : Button        = null
var _btn_xp_100      : Button        = null
var _chk_equipped    : CheckBox      = null

# Row3 (Level / Perk / SXP)
var _row3           : HBoxContainer = null
var _btn_lvl_m1     : Button        = null
var _btn_lvl_p1     : Button        = null
var _spin_lvl       : SpinBox       = null
var _btn_set_level  : Button        = null
var _btn_bpp_p1     : Button        = null
var _btn_bpp_p5     : Button        = null
var _stat_pick      : OptionButton  = null
var _sxp_amt        : SpinBox       = null
var _btn_add_sxp    : Button        = null

# Row4 (Party Cheats)
var _row4           : HBoxContainer = null
var _roster_pick    : OptionButton  = null
var _btn_add_party  : Button        = null

# Systems
var _inv   : Node = null
var _csv   : Node = null
var _sig   : Node = null
var _gs    : Node = null
var _hero  : Node = null
var _stats : Node = null
var _perk  : Node = null
var _party : Node = null

var _defs : Dictionary = {} # item id -> row dict
var _rows_vbox : VBoxContainer = null

# Cached Party CSV rows keyed by id ("actor_id")
var _party_defs_by_id: Dictionary = {}   # id -> row-dict
var _party_csv_path: String = ""

# ---------------- lifecycle ----------------

func _ready() -> void:
	# Systems
	_inv   = get_node_or_null(INV_PATH)
	_csv   = get_node_or_null(CSV_PATH)
	_sig   = get_node_or_null(SIG_PATH)
	_gs    = get_node_or_null(GS_PATH)
	_hero  = get_node_or_null(HERO_PATH)
	_stats = get_node_or_null(STATS_PATH)
	_perk  = get_node_or_null(PERK_PATH)
	_party = get_node_or_null(PARTY_PATH)

	# Ensure vertical stacking container; move existing Row into it
	_normalize_rows_layout()

	# Wire Row1
	if _give and not _give.pressed.is_connected(_on_give):       _give.pressed.connect(_on_give)
	if _rem and not _rem.pressed.is_connected(_on_remove):       _rem.pressed.connect(_on_remove)
	if _give10 and not _give10.pressed.is_connected(_on_give10): _give10.pressed.connect(_on_give10)
	if _reload and not _reload.pressed.is_connected(_on_reload): _reload.pressed.connect(_on_reload)

	# Ensure other rows (create if missing)
	_ensure_row2(); _bind_row2_signals()
	_ensure_row3(); _bind_row3_signals(); _populate_stat_picker()
	_ensure_row4(); _bind_row4_signals()

	# Data
	_refresh_defs()
	_refresh_sig_dropdown()
	_refresh_roster_picker()

	if _sig and _sig.has_signal("loadout_changed"):
		if not _sig.is_connected("loadout_changed", Callable(self, "_on_loadout_changed")):
			_sig.connect("loadout_changed", Callable(self, "_on_loadout_changed"))

# ---------------- Layout helpers ----------------

func _normalize_rows_layout() -> void:
	_rows_vbox = get_node_or_null("Rows") as VBoxContainer
	if _rows_vbox == null:
		_rows_vbox = VBoxContainer.new()
		_rows_vbox.name = "Rows"
		_rows_vbox.add_theme_constant_override("separation", 8)
		add_child(_rows_vbox)

	var existing_row: HBoxContainer = get_node_or_null("Row") as HBoxContainer
	if existing_row and existing_row.get_parent() == self:
		remove_child(existing_row)
		_rows_vbox.add_child(existing_row)

func _ensure_row2() -> void:
	_row2 = _ctl("SigilRow") as HBoxContainer
	if _row2 != null:
		_sig_inst_pick = _ctl("InstPicker") as OptionButton
		_btn_lv_up     = _ctl("BtnLvUp") as Button
		_btn_lv_down   = _ctl("BtnLvDown") as Button
		_btn_xp_25     = _ctl("BtnXP25") as Button
		_btn_xp_100    = _ctl("BtnXP100") as Button
		_chk_equipped  = _ctl("ChkEquipped") as CheckBox
		return

	_row2 = HBoxContainer.new()
	_row2.name = "SigilRow"
	_row2.add_theme_constant_override("separation", 8)
	_rows_vbox.add_child(_row2)

	var title := Label.new(); title.text = "Sigil Cheats:"; _row2.add_child(title)

	_sig_inst_pick = OptionButton.new(); _sig_inst_pick.name = "InstPicker"; _sig_inst_pick.custom_minimum_size = Vector2(260,0); _row2.add_child(_sig_inst_pick)
	_btn_lv_up     = Button.new(); _btn_lv_up.name = "BtnLvUp"; _btn_lv_up.text = "Lv +1"; _row2.add_child(_btn_lv_up)
	_btn_lv_down   = Button.new(); _btn_lv_down.name = "BtnLvDown"; _btn_lv_down.text = "Lv -1"; _row2.add_child(_btn_lv_down)
	_btn_xp_25     = Button.new(); _btn_xp_25.name = "BtnXP25"; _btn_xp_25.text = "XP +25"; _row2.add_child(_btn_xp_25)
	_btn_xp_100    = Button.new(); _btn_xp_100.name = "BtnXP100"; _btn_xp_100.text = "XP +100"; _row2.add_child(_btn_xp_100)
	_chk_equipped  = CheckBox.new(); _chk_equipped.name = "ChkEquipped"; _chk_equipped.text = "Equipped only"; _chk_equipped.button_pressed = true; _row2.add_child(_chk_equipped)

func _ensure_row3() -> void:
	_row3 = _ctl("HeroRow") as HBoxContainer
	if _row3 != null:
		_btn_lvl_m1    = _ctl("BtnLvlM1") as Button
		_btn_lvl_p1    = _ctl("BtnLvlP1") as Button
		_spin_lvl      = _ctl("SpinLvl") as SpinBox
		_btn_set_level = _ctl("BtnSetLvl") as Button
		_btn_bpp_p1    = _ctl("BtnBPPp1") as Button
		_btn_bpp_p5    = _ctl("BtnBPPp5") as Button
		_stat_pick     = _ctl("StatPick") as OptionButton
		_sxp_amt       = _ctl("SpinSXP") as SpinBox
		_btn_add_sxp   = _ctl("BtnAddSXP") as Button
		return

	_row3 = HBoxContainer.new()
	_row3.name = "HeroRow"
	_row3.add_theme_constant_override("separation", 8)
	_rows_vbox.add_child(_row3)

	var title := Label.new(); title.text = "Hero / SXP Cheats:"; _row3.add_child(title)

	_btn_lvl_m1 = Button.new(); _btn_lvl_m1.name = "BtnLvlM1"; _btn_lvl_m1.text = "Lv -1"; _row3.add_child(_btn_lvl_m1)
	_btn_lvl_p1 = Button.new(); _btn_lvl_p1.name = "BtnLvlP1"; _btn_lvl_p1.text = "Lv +1"; _row3.add_child(_btn_lvl_p1)

	_spin_lvl = SpinBox.new(); _spin_lvl.name = "SpinLvl"; _spin_lvl.min_value = 1; _spin_lvl.max_value = 99; _spin_lvl.step = 1; _row3.add_child(_spin_lvl)

	_btn_set_level = Button.new(); _btn_set_level.name = "BtnSetLvl"; _btn_set_level.text = "Set Lv"; _row3.add_child(_btn_set_level)

	var sep1 := HSeparator.new(); sep1.custom_minimum_size = Vector2(6,0); _row3.add_child(sep1)

	_btn_bpp_p1 = Button.new(); _btn_bpp_p1.name = "BtnBPPp1"; _btn_bpp_p1.text = "BPP +1"; _row3.add_child(_btn_bpp_p1)
	_btn_bpp_p5 = Button.new(); _btn_bpp_p5.name = "BtnBPPp5"; _btn_bpp_p5.text = "BPP +5"; _row3.add_child(_btn_bpp_p5)

	var sep2 := HSeparator.new(); sep2.custom_minimum_size = Vector2(6,0); _row3.add_child(sep2)

	_stat_pick = OptionButton.new(); _stat_pick.name = "StatPick"; _stat_pick.custom_minimum_size = Vector2(120,0); _row3.add_child(_stat_pick)
	_sxp_amt = SpinBox.new(); _sxp_amt.name = "SpinSXP"; _sxp_amt.min_value = 1; _sxp_amt.max_value = 999; _sxp_amt.step = 1; _sxp_amt.value = 10; _sxp_amt.custom_minimum_size = Vector2(70,0); _row3.add_child(_sxp_amt)
	_btn_add_sxp = Button.new(); _btn_add_sxp.name = "BtnAddSXP"; _btn_add_sxp.text = "Add SXP"; _row3.add_child(_btn_add_sxp)

	if _spin_lvl: _spin_lvl.value = _get_hero_level()

func _ensure_row4() -> void:
	_row4 = _ctl("PartyRow") as HBoxContainer
	if _row4 != null:
		_roster_pick   = _ctl("RosterPick") as OptionButton
		_btn_add_party = _ctl("BtnAddParty") as Button
		return

	_row4 = HBoxContainer.new()
	_row4.name = "PartyRow"
	_row4.add_theme_constant_override("separation", 8)
	_rows_vbox.add_child(_row4)

	var title := Label.new(); title.text = "Party Cheats:"; _row4.add_child(title)

	_roster_pick = OptionButton.new()
	_roster_pick.name = "RosterPick"
	_roster_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row4.add_child(_roster_pick)

	_btn_add_party = Button.new()
	_btn_add_party.name = "BtnAddParty"
	_btn_add_party.text = "Add to Party"
	_row4.add_child(_btn_add_party)

# ---------------- Items (Row1) ----------------

func _refresh_defs() -> void:
	_defs.clear()
	if _picker: _picker.clear()

	if _inv and _inv.has_method("get_item_defs"):
		var v: Variant = _inv.call("get_item_defs")
		if typeof(v) == TYPE_DICTIONARY:
			_defs = v as Dictionary

	if _defs.is_empty() and _csv and _csv.has_method("load_csv"):
		var loaded: Variant = _csv.call("load_csv", ITEMS_CSV, KEY_ID)
		if typeof(loaded) == TYPE_DICTIONARY:
			_defs = loaded as Dictionary

	if not _picker: return

	var ids_any: Array = _defs.keys()
	ids_any.sort_custom(Callable(self, "_cmp_ids_by_name"))

	var idx: int = 0
	for id_any in ids_any:
		var item_id: String = String(id_any)
		var rec: Dictionary = _defs.get(item_id, {}) as Dictionary
		var disp: String = String(rec.get("name", item_id))
		var cat: String = String(rec.get("category","Other"))
		_picker.add_item("%s — %s [%s]" % [item_id, disp, cat])
		_picker.set_item_metadata(idx, item_id)
		idx += 1

func _cmp_ids_by_name(a: Variant, b: Variant) -> bool:
	var da: Dictionary = _defs.get(a, {}) as Dictionary
	var db: Dictionary = _defs.get(b, {}) as Dictionary
	var na: String = String(da.get("name", String(a)))
	var nb: String = String(db.get("name", String(b)))
	return na < nb

func _selected_id() -> String:
	if _picker == null: return ""
	var i: int = _picker.get_selected()
	if i < 0: return ""
	return String(_picker.get_item_metadata(i))

func _on_give() -> void:
	var id: String = _selected_id()
	var n: int = (int(_qty.value) if _qty != null else 0)
	if id == "" or n <= 0: return
	if _inv and _inv.has_method("add_item"):
		_inv.call("add_item", id, n)

func _on_remove() -> void:
	var id: String = _selected_id()
	var n: int = (int(_qty.value) if _qty != null else 0)
	if id == "" or n <= 0: return
	if _inv and _inv.has_method("remove_item"):
		_inv.call("remove_item", id, n)

func _on_give10() -> void:
	var id: String = _selected_id()
	if id == "": return
	if _inv and _inv.has_method("add_item"):
		_inv.call("add_item", id, 10)

func _on_reload() -> void:
	if _csv and _csv.has_method("reload_csv"):
		_csv.call("reload_csv", ITEMS_CSV, KEY_ID)
	if _inv and _inv.has_method("load_definitions"):
		_inv.call("load_definitions")
	_refresh_defs()

# ---------------- Sigil cheats (Row2) ----------------

func _bind_row2_signals() -> void:
	if _btn_lv_up and not _btn_lv_up.pressed.is_connected(_on_lv_up):        _btn_lv_up.pressed.connect(_on_lv_up)
	if _btn_lv_down and not _btn_lv_down.pressed.is_connected(_on_lv_down):  _btn_lv_down.pressed.connect(_on_lv_down)
	if _btn_xp_25 and not _btn_xp_25.pressed.is_connected(_on_xp_25):        _btn_xp_25.pressed.connect(_on_xp_25)
	if _btn_xp_100 and not _btn_xp_100.pressed.is_connected(_on_xp_100):     _btn_xp_100.pressed.connect(_on_xp_100)
	if _chk_equipped and not _chk_equipped.toggled.is_connected(_on_equipped_toggle):
		_chk_equipped.toggled.connect(_on_equipped_toggle)

func _collect_party_names() -> Array[String]:
	var out: Array[String] = []
	if _gs and _gs.has_method("get_party_names"):
		var pn_v: Variant = _gs.call("get_party_names")
		if typeof(pn_v) == TYPE_PACKED_STRING_ARRAY:
			for s in (pn_v as PackedStringArray): out.append(String(s))
		elif typeof(pn_v) == TYPE_ARRAY:
			for s2 in (pn_v as Array): out.append(String(s2))
	return out

func _append_ids_from_loadout(ids: Array[String], member: String) -> void:
	if _sig == null or not _sig.has_method("get_loadout"):
		return
	var l_v: Variant = _sig.call("get_loadout", member)
	if typeof(l_v) == TYPE_PACKED_STRING_ARRAY:
		for s in (l_v as PackedStringArray):
			var sid := String(s)
			if sid != "": ids.append(sid)
	elif typeof(l_v) == TYPE_ARRAY:
		for s2 in (l_v as Array):
			var sid2 := String(s2)
			if sid2 != "": ids.append(sid2)

func _append_ids_free(ids: Array[String]) -> void:
	if _sig and _sig.has_method("list_free_instances"):
		var v_free: Variant = _sig.call("list_free_instances")
		if typeof(v_free) == TYPE_PACKED_STRING_ARRAY:
			for s in (v_free as PackedStringArray):
				var sid := String(s); if sid != "": ids.append(sid)
		elif typeof(v_free) == TYPE_ARRAY:
			for s2 in (v_free as Array):
				var sid2 := String(s2); if sid2 != "": ids.append(sid2)

func _refresh_sig_dropdown() -> void:
	if _sig_inst_pick == null:
		return
	_sig_inst_pick.clear()

	if _sig == null:
		_sig_inst_pick.add_item("(No SigilSystem)")
		_sig_inst_pick.disabled = true
		if _btn_lv_up:   _btn_lv_up.disabled   = true
		if _btn_lv_down: _btn_lv_down.disabled = true
		if _btn_xp_25:   _btn_xp_25.disabled   = true
		if _btn_xp_100:  _btn_xp_100.disabled  = true
		return

	var ids: Array[String] = []
	var equipped_only: bool = (_chk_equipped != null and _chk_equipped.button_pressed)

	if equipped_only:
		for member in _collect_party_names():
			_append_ids_from_loadout(ids, member)
	else:
		_append_ids_free(ids)
		for member2 in _collect_party_names():
			_append_ids_from_loadout(ids, member2)

	# dedup + sort by display name
	var uniq: Dictionary = {}
	var id_list: Array[String] = []
	for id_any in ids:
		var sid: String = String(id_any)
		if not uniq.has(sid):
			uniq[sid] = true
			id_list.append(sid)

	id_list.sort_custom(Callable(self, "_cmp_sig_by_name"))

	var idx: int = 0
	for sid in id_list:
		var disp: String = sid
		if _sig.has_method("get_display_name_for"):
			var nm_v: Variant = _sig.call("get_display_name_for", sid)
			if typeof(nm_v) == TYPE_STRING: disp = String(nm_v)
		_sig_inst_pick.add_item(disp, idx)
		_sig_inst_pick.set_item_metadata(idx, sid)
		idx += 1

	var has_any: bool = idx > 0
	_sig_inst_pick.disabled = not has_any
	if _btn_lv_up:   _btn_lv_up.disabled   = not has_any
	if _btn_lv_down: _btn_lv_down.disabled = not has_any
	if _btn_xp_25:   _btn_xp_25.disabled   = not has_any
	if _btn_xp_100:  _btn_xp_100.disabled  = not has_any

func _cmp_sig_by_name(a: Variant, b: Variant) -> bool:
	var sa: String = String(a)
	var sb: String = String(b)
	var na: String = sa
	var nb: String = sb
	if _sig and _sig.has_method("get_display_name_for"):
		var va: Variant = _sig.call("get_display_name_for", sa)
		var vb: Variant = _sig.call("get_display_name_for", sb)
		if typeof(va) == TYPE_STRING: na = String(va)
		if typeof(vb) == TYPE_STRING: nb = String(vb)
	return na < nb

func _selected_inst_id() -> String:
	if _sig_inst_pick == null: return ""
	var i: int = _sig_inst_pick.get_selected()
	if i < 0: return ""
	return String(_sig_inst_pick.get_item_metadata(i))

func _on_lv_up() -> void:
	var id: String = _selected_inst_id()
	if id == "" or _sig == null: return
	var lvl: int = 1
	if _sig.has_method("get_instance_level"):
		lvl = int(_sig.call("get_instance_level", id))
	var new_lvl: int = clamp(lvl + 1, 1, 4)
	if _sig.has_method("cheat_set_instance_level"):
		_sig.call("cheat_set_instance_level", id, new_lvl)
	_refresh_sig_dropdown()

func _on_lv_down() -> void:
	var id: String = _selected_inst_id()
	if id == "" or _sig == null: return
	var lvl: int = 1
	if _sig.has_method("get_instance_level"):
		lvl = int(_sig.call("get_instance_level", id))
	var new_lvl: int = clamp(lvl - 1, 1, 4)
	if _sig.has_method("cheat_set_instance_level"):
		_sig.call("cheat_set_instance_level", id, new_lvl)
	_refresh_sig_dropdown()

func _on_xp_25() -> void: _grant_xp(25)
func _on_xp_100() -> void: _grant_xp(100)

func _grant_xp(amount: int) -> void:
	var id: String = _selected_inst_id()
	if id == "" or _sig == null: return
	var require_equipped: bool = (_chk_equipped != null and _chk_equipped.button_pressed)
	if _sig.has_method("cheat_add_xp_to_instance"):
		_sig.call("cheat_add_xp_to_instance", id, amount, require_equipped)
	_refresh_sig_dropdown()

func _on_equipped_toggle(_pressed: bool) -> void:
	_refresh_sig_dropdown()

func _on_loadout_changed(_member: String) -> void:
	_refresh_sig_dropdown()

# ---------------- Level / Perk / SXP (Row3) ----------------

func _bind_row3_signals() -> void:
	if _btn_lvl_m1 and not _btn_lvl_m1.pressed.is_connected(_on_lvl_m1):    _btn_lvl_m1.pressed.connect(_on_lvl_m1)
	if _btn_lvl_p1 and not _btn_lvl_p1.pressed.is_connected(_on_lvl_p1):    _btn_lvl_p1.pressed.connect(_on_lvl_p1)
	if _btn_set_level and not _btn_set_level.pressed.is_connected(_on_set_level): _btn_set_level.pressed.connect(_on_set_level)
	if _btn_bpp_p1 and not _btn_bpp_p1.pressed.is_connected(_on_bpp_p1):    _btn_bpp_p1.pressed.connect(_on_bpp_p1)
	if _btn_bpp_p5 and not _btn_bpp_p5.pressed.is_connected(_on_bpp_p5):    _btn_bpp_p5.pressed.connect(_on_bpp_p5)
	if _btn_add_sxp and not _btn_add_sxp.pressed.is_connected(_on_add_sxp): _btn_add_sxp.pressed.connect(_on_add_sxp)

func _populate_stat_picker() -> void:
	if _stat_pick == null: return
	_stat_pick.clear()
	var stats: Array = ["BRW","VTL","TPO","FCS","MND"]
	for i in range(stats.size()):
		_stat_pick.add_item(stats[i], i)
		_stat_pick.set_item_metadata(i, stats[i])
	if _spin_lvl: _spin_lvl.value = _get_hero_level()

func _on_lvl_m1() -> void: _set_hero_level_delta(-1)
func _on_lvl_p1() -> void: _set_hero_level_delta(+1)
func _on_set_level() -> void: _set_hero_level_exact(int(_spin_lvl.value))
func _on_bpp_p1() -> void: _add_perk_points(1)
func _on_bpp_p5() -> void: _add_perk_points(5)

func _on_add_sxp() -> void:
	if _stat_pick == null or _sxp_amt == null: return
	var i: int = _stat_pick.get_selected()
	if i < 0: return
	var stat_id: String = String(_stat_pick.get_item_metadata(i))
	var amt: int = int(_sxp_amt.value)
	_add_sxp(stat_id, amt)

# --- hero ops
func _get_hero_level() -> int:
	if _hero and _hero.has_method("get"):
		return int(_hero.get("level"))
	return 1

func _set_hero_level_delta(delta: int) -> void:
	var cur: int = _get_hero_level()
	_set_hero_level_exact(cur + delta)

func _set_hero_level_exact(new_level: int) -> void:
	if _hero == null:
		push_warning("Cheat: aHeroSystem not found.")
		return
	var old: int = _get_hero_level()
	new_level = clamp(new_level, 1, 99)
	if new_level == old: return

	_hero.set("level", new_level)

	var gained_bpp: int = int(floor(new_level / 3.0)) - int(floor(old / 3.0))
	if gained_bpp > 0: _add_perk_points(gained_bpp)

	_recalc_hp_mp()
	if _spin_lvl: _spin_lvl.value = new_level
	_emit_refresh()

func _add_perk_points(points: int) -> void:
	if points == 0: return
	if _gs and _gs.has_method("get") and _gs.has_method("set"):
		var cur: int = int(_gs.get("perk_points"))
		_gs.set("perk_points", max(0, cur + points))
	if _perk:
		if _perk.has_method("add_points"): _perk.call("add_points", points)
		elif _perk.has_method("grant_points"): _perk.call("grant_points", points)
	_emit_refresh()

func _add_sxp(stat_id: String, amount: int) -> void:
	if amount <= 0: return
	if _stats == null:
		push_warning("Cheat: aStatsSystem not found.")
		return

	if _stats.has_method("add_sxp"):
		_stats.call("add_sxp", stat_id, amount)
	else:
		if _stats.has_method("add_stat_xp"):
			_stats.call("add_stat_xp", stat_id, amount)
		elif _stats.has_method("set_stat_level"):
			if amount >= 50:
				var cur_lv: int = _read_stat_level(stat_id)
				_stats.call("set_stat_level", stat_id, cur_lv + 1)

	_recalc_hp_mp()
	_emit_refresh()

func _read_stat_level(stat_id: String) -> int:
	if _stats == null: return 1
	if _stats.has_method("get_stats_dict"):
		var v: Variant = _stats.call("get_stats_dict")
		if typeof(v) == TYPE_DICTIONARY:
			var d: Dictionary = v
			if d.has(stat_id):
				var row_v: Variant = d[stat_id]
				if typeof(row_v) == TYPE_INT: return int(row_v)
				if typeof(row_v) == TYPE_DICTIONARY:
					var row: Dictionary = row_v
					if row.has("level"): return int(row["level"])
					if row.has("lvl"):   return int(row["lvl"])
	return 1

func _recalc_hp_mp() -> void:
	if _hero == null: return
	var lvl: int = _get_hero_level()
	var vtl: int = _read_stat_level("VTL")
	var fcs: int = _read_stat_level("FCS")

	var new_hp_max: int = 150 + (vtl * lvl * 6)
	var new_mp_max: int = 20 + int(round(float(fcs) * float(lvl) * 1.5))

	_hero.set("hp_max", new_hp_max)
	_hero.set("hp", new_hp_max)
	_hero.set("mp_max", new_mp_max)
	_hero.set("mp", new_mp_max)

func _emit_refresh() -> void:
	if _stats and _stats.has_signal("stats_changed"):
		_stats.emit_signal("stats_changed")
	if _hero and _hero.has_signal("creation_applied"):
		_hero.emit_signal("creation_applied")

# ---------------- Party Cheats (Row4) ----------------

func _bind_row4_signals() -> void:
	if _btn_add_party and not _btn_add_party.pressed.is_connected(_on_add_to_party):
		_btn_add_party.pressed.connect(_on_add_to_party)

func _on_add_to_party() -> void:
	var id := _selected_roster_id()
	if id == "": return

	# Try party system first
	if _party:
		if _party.has_method("add_member"):
			_party.call("add_member", id)
		elif _party.has_method("add_to_party"):
			_party.call("add_to_party", id)
		elif _party.has_method("recruit"):
			_party.call("recruit", id)
		elif _party.has_method("try_add_member"):
			_party.call("try_add_member", id)
	# Fallback: GameState list
	elif _gs:
		var cur: Array = []
		if _gs.has_method("get") and typeof(_gs.get("party")) == TYPE_ARRAY:
			cur = _gs.get("party")
		if not cur.has(id):
			cur.append(id)
			if _gs.has_method("set"):
				_gs.set("party", cur)

	# Let interested UIs react
	if _party and _party.has_signal("party_changed"):
		_party.emit_signal("party_changed")
	elif _gs and _gs.has_signal("party_changed"):
		_gs.emit_signal("party_changed")

	_refresh_roster_picker()

func _selected_roster_id() -> String:
	if _roster_pick == null: return ""
	var i := _roster_pick.get_selected()
	if i < 0: return ""
	return String(_roster_pick.get_item_metadata(i))

func _refresh_roster_picker() -> void:
	if _roster_pick == null:
		return
	_roster_pick.clear()

	_party_defs_by_id.clear()
	_party_csv_path = _guess_party_csv_path()
	if _party_csv_path != "" and _csv and _csv.has_method("load_csv"):
		# Try id candidates until loader returns non-empty dict
		for id_key in PARTY_ID_KEYS:
			var loaded_v: Variant = _csv.call("load_csv", _party_csv_path, String(id_key))
			if typeof(loaded_v) == TYPE_DICTIONARY and (loaded_v as Dictionary).size() > 0:
				_party_defs_by_id = (loaded_v as Dictionary)
				break

	var list_ids: Array[String] = []

	if not _party_defs_by_id.is_empty():
		# Build nicely labeled entries from CSV rows
		var idx := 0
		var ids_any := _party_defs_by_id.keys()
		ids_any.sort()
		for id_any in ids_any:
			var rid: String = String(id_any)
			var row: Dictionary = _party_defs_by_id.get(rid, {}) as Dictionary
			var disp := _extract_display_from_row(row, rid)
			_roster_pick.add_item(disp)
			_roster_pick.set_item_metadata(idx, rid)
			idx += 1
		return  # prefer CSV; no fallback clutter
	else:
		# Fallback: any known members from systems
		list_ids = _collect_all_known_members()

	var idx2 := 0
	for rid2 in list_ids:
		_roster_pick.add_item(rid2)
		_roster_pick.set_item_metadata(idx2, rid2)
		idx2 += 1

func _guess_party_csv_path() -> String:
	for p in PARTY_CSV_CANDIDATES:
		if ResourceLoader.exists(p):
			return p
	return ""

func _extract_display_from_row(row: Dictionary, rid: String) -> String:
	var disp := ""
	for k in PARTY_NAME_KEYS:
		if row.has(k) and typeof(row[k]) == TYPE_STRING:
			disp = String(row[k])
			break
	if disp == "": disp = rid
	return disp

func _collect_all_known_members() -> Array[String]:
	var out: Array[String] = []
	# Party system might expose its own catalog
	if _party and _party.has_method("list_all_member_ids"):
		var v: Variant = _party.call("list_all_member_ids")
		if typeof(v) == TYPE_ARRAY:
			for s in (v as Array): out.append(String(s))
		elif typeof(v) == TYPE_PACKED_STRING_ARRAY:
			for s2 in (v as PackedStringArray): out.append(String(s2))
	# GameState known party + bench (fallback)
	if _gs:
		if _gs.has_method("get"):
			var p_v: Variant = _gs.get("party")
			if typeof(p_v) == TYPE_ARRAY:
				for s3 in (p_v as Array):
					var a := String(s3); if not out.has(a): out.append(a)
			var b_v: Variant = _gs.get("bench")
			if typeof(b_v) == TYPE_ARRAY:
				for s4 in (b_v as Array):
					var b := String(s4); if not out.has(b): out.append(b)
	# Ensure stable order
	out.sort()
	return out
