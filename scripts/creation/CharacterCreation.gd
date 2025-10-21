extends Control
class_name CharacterCreation

signal creation_applied

# ── Autoload paths ────────────────────────────────────────────────────────────
const GS_PATH      := "/root/aGameState"
const STATS_PATH   := "/root/aStatsSystem"
const PERK_PATH    := "/root/aPerkSystem"
const CPS_PATH     := "/root/aCombatProfileSystem"
const ROUTER_PATH  := "/root/aSceneRouter"

# ── UI: unique_name_in_owner nodes from your scene ───────────────────────────
@onready var _name_in     : LineEdit      = %NameInput
@onready var _pron_in     : OptionButton  = %PronounInput

@onready var _body_in     : OptionButton  = %BodyIdInput
@onready var _face_in     : OptionButton  = %FaceIdInput
@onready var _hair_in     : OptionButton  = %HairIdInput
@onready var _eyes_in     : OptionButton  = %EyesIdInput

@onready var _skin_sl     : HSlider       = %BodyColorInput
@onready var _skin_sw     : ColorRect     = %BodyColorSwatch
@onready var _brow_sl     : HSlider       = %EyebrowColorInput
@onready var _brow_sw     : ColorRect     = %EyebrowColorSwatch
@onready var _eye_sl      : HSlider       = %EyeColorInput
@onready var _eye_sw      : ColorRect     = %EyeColorSwatch
@onready var _hair_sl     : HSlider       = %HairColorInput
@onready var _hair_sw     : ColorRect     = %HairColorSwatch

@onready var _brw_cb      : CheckButton   = %StatBRW
@onready var _vtl_cb      : CheckButton   = %StatVTL
@onready var _tpo_cb      : CheckButton   = %StatTPO
@onready var _mnd_cb      : CheckButton   = %StatMND
@onready var _fcs_cb      : CheckButton   = %StatFCS

@onready var _perk_in     : OptionButton  = %PerkInput
@onready var _confirm_btn : Button        = %ConfirmBtn
@onready var _cancel_btn  : Button        = %CancelBtn   # may exist in .tscn; we’ll hide it

# ── state ────────────────────────────────────────────────────────────────────
var _selected_order : Array[String] = []       # keep order of picks (max 3)
var _perk_id_by_idx : Dictionary = {}          # index -> perk_id
var _perk_stat_by_idx : Dictionary = {}        # index -> stat_id (help text)

# ── ready ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_fill_basics()
	_wire_colors()
	_wire_stat_toggles()
	_rebuild_perk_dropdown() # starts empty until picks

	# Hide/disable back button completely (keeps scene compatible)
	if _cancel_btn:
		_cancel_btn.hide()
		_cancel_btn.disabled = true
		_cancel_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Perk selection change → update gating
	if _perk_in and not _perk_in.item_selected.is_connected(_on_perk_selected):
		_perk_in.item_selected.connect(_on_perk_selected)

	if _confirm_btn and not _confirm_btn.pressed.is_connected(_on_confirm_pressed):
		_confirm_btn.pressed.connect(_on_confirm_pressed)

	_update_confirm_enabled()

# ── UI fill / wiring ─────────────────────────────────────────────────────────
func _fill_basics() -> void:
	# Pronouns
	if _pron_in and _pron_in.item_count == 0:
		for p in ["they", "she", "he"]:
			_pron_in.add_item(p)
		_pron_in.select(0)

	# Simple placeholder IDs so the dropdowns actually work
	_fill_opt(_body_in, ["1","2","3","4"])
	_fill_opt(_face_in, ["1","2","3","4"])
	_fill_opt(_hair_in, ["1","2","3","4"])
	_fill_opt(_eyes_in, ["1","2","3","4"])

	# Reasonable slider ranges
	_set_slider_range(_skin_sl, 0.0, 1.0, 0.01)          # tone 0..1
	_set_slider_range(_brow_sl, 0.0, 360.0, 1.0)         # hue°
	_set_slider_range(_eye_sl,  0.0, 360.0, 1.0)         # hue°
	_set_slider_range(_hair_sl, 0.0, 360.0, 1.0)         # hue°
	# Initial swatches
	_update_color_swatches()

func _fill_opt(ob: OptionButton, items: Array) -> void:
	if ob == null: return
	if ob.item_count > 0: return
	for s in items:
		ob.add_item(String(s))
	ob.select(0)

func _set_slider_range(sl: HSlider, min_v: float, max_v: float, step: float) -> void:
	if sl == null: return
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step

func _wire_colors() -> void:
	if _skin_sl and not _skin_sl.value_changed.is_connected(_on_color_changed):
		_skin_sl.value_changed.connect(_on_color_changed)
	if _brow_sl and not _brow_sl.value_changed.is_connected(_on_color_changed):
		_brow_sl.value_changed.connect(_on_color_changed)
	if _eye_sl and not _eye_sl.value_changed.is_connected(_on_color_changed):
		_eye_sl.value_changed.connect(_on_color_changed)
	if _hair_sl and not _hair_sl.value_changed.is_connected(_on_color_changed):
		_hair_sl.value_changed.connect(_on_color_changed)

func _wire_stat_toggles() -> void:
	_wire_stat_toggle(_brw_cb, "BRW")
	_wire_stat_toggle(_vtl_cb, "VTL")
	_wire_stat_toggle(_tpo_cb, "TPO")
	_wire_stat_toggle(_mnd_cb, "MND")
	_wire_stat_toggle(_fcs_cb, "FCS")

func _wire_stat_toggle(btn: CheckButton, stat_id: String) -> void:
	if btn and not btn.toggled.is_connected(_on_stat_toggled):
		btn.toggled.connect(_on_stat_toggled.bind(stat_id, btn))

func _on_stat_toggled(pressed: bool, stat_id: String, btn: CheckButton) -> void:
	if pressed:
		if not _selected_order.has(stat_id):
			_selected_order.append(stat_id)
		if _selected_order.size() > 3:
			# too many – undo this one
			_selected_order.erase(stat_id)
			btn.set_pressed_no_signal(false)
	else:
		_selected_order.erase(stat_id)

	_rebuild_perk_dropdown()
	_update_confirm_enabled()

# ── colors ───────────────────────────────────────────────────────────────────
func _on_color_changed(_v: float) -> void:
	_update_color_swatches()

func _update_color_swatches() -> void:
	if _skin_sw: _skin_sw.color = _skin_from_value(float(_skin_sl.value if _skin_sl else 0.5))
	if _brow_sw: _brow_sw.color = Color.from_hsv(_deg_to_unit(_brow_sl), 0.65, 0.35)
	if _eye_sw:  _eye_sw.color  = Color.from_hsv(_deg_to_unit(_eye_sl),  0.55, 0.85)
	if _hair_sw: _hair_sw.color = Color.from_hsv(_deg_to_unit(_hair_sl), 0.75, 0.60)

func _deg_to_unit(sl: HSlider) -> float:
	if sl == null: return 0.0
	var h: float = float(sl.value)
	return clamp(h / 360.0, 0.0, 1.0)

func _skin_from_value(t: float) -> Color:
	var v: float = clamp(t, 0.0, 1.0)
	var r: float = 1.0 - 0.35 * v
	var g: float = 0.88 - 0.45 * v
	var b: float = 0.80 - 0.55 * v
	return Color(r, g, b)

# ── perks (based on selected stats; only T1 options) ─────────────────────────
func _rebuild_perk_dropdown() -> void:
	if _perk_in == null:
		return
	_perk_in.clear()
	_perk_id_by_idx.clear()
	_perk_stat_by_idx.clear()

	# Build the offer list
	var picks: Array[String] = []
	for i in range(_selected_order.size()):
		picks.append(String(_selected_order[i]))
	var offers: Array = []

	var perk: Node = get_node_or_null(PERK_PATH)
	if perk and perk.has_method("get_starting_options"):
		var v: Variant = perk.call("get_starting_options", picks)
		if typeof(v) == TYPE_ARRAY:
			offers = v as Array
	elif picks.size() > 0:
		# Fallback: synthesize simple placeholder perks
		for i2 in range(picks.size()):
			var s2: String = picks[i2]
			offers.append({
				"stat": s2,
				"tier": 0,
				"id": "%s_t1" % s2.to_lower(),
				"name": "%s T1" % s2,
				"desc": "Tier-1 perk for %s." % s2
			})

	# Fill the dropdown
	_perk_in.add_item("— choose starting perk —")
	_perk_id_by_idx[0] = ""
	_perk_stat_by_idx[0] = ""

	var idx: int = 1
	for j in range(offers.size()):
		var it_v: Variant = offers[j]
		if typeof(it_v) != TYPE_DICTIONARY:
			continue
		var it: Dictionary = it_v
		var line: String = "%s — %s" % [
			String(it.get("stat","")),
			String(it.get("name","Perk"))
		]
		_perk_in.add_item(line)
		_perk_id_by_idx[idx] = String(it.get("id",""))
		_perk_stat_by_idx[idx] = String(it.get("stat",""))
		idx += 1

	_perk_in.select(0)


func _on_perk_selected(_index: int) -> void:
	_update_confirm_enabled()

# ── confirm ──────────────────────────────────────────────────────────────────
func _on_confirm_pressed() -> void:
	# Hard gate: must have exactly 3 stats + a chosen perk
	if _selected_order.size() != 3 or _chosen_perk_id() == "":
		OS.alert("Pick 3 stats and 1 perk to continue.", "Character Creation")
		return

	var name_text: String = (_name_in.text if _name_in else "Player").strip_edges()
	if name_text == "":
		name_text = "Player"
	var pron_text: String = _opt_text(_pron_in)

	var body_id: String = _opt_text(_body_in)
	var face_id: String = _opt_text(_face_in)
	var hair_id: String = _opt_text(_hair_in)
	var eyes_id: String = _opt_text(_eyes_in)

	var c_skin: Color = _skin_from_value(float(_skin_sl.value if _skin_sl else 0.5))
	var c_brow: Color = Color.from_hsv(_deg_to_unit(_brow_sl), 0.65, 0.35)
	var c_eye: Color  = Color.from_hsv(_deg_to_unit(_eye_sl),  0.55, 0.85)
	var c_hair: Color = Color.from_hsv(_deg_to_unit(_hair_sl), 0.75, 0.60)

	var gs: Node = get_node_or_null(GS_PATH)
	if gs:
		if gs.has_method("set"):
			gs.set("player_name", name_text)
		gs.set_meta("hero_identity", {
			"name": name_text, "pronoun": pron_text,
			"body": body_id, "face": face_id, "eyes": eyes_id, "hair": hair_id,
			"body_color": c_skin, "brow_color": c_brow, "eye_color": c_eye, "hair_color": c_hair
		})
		var picked := PackedStringArray()
		for i in range(_selected_order.size()):
			picked.append(_selected_order[i])
		gs.set_meta("hero_picked_stats", picked)
		# ensure hero in party
		if gs.has_method("get"):
			var pv: Variant = gs.get("party")
			var arr: Array = []
			if typeof(pv) == TYPE_ARRAY:
				arr = pv as Array
			if arr.is_empty() and gs.has_method("set"):
				gs.set("party", ["hero"])
		# default mind type
		if not gs.has_meta("hero_active_type"):
			gs.set_meta("hero_active_type", "Omega")

	# apply +1 level to chosen stats
	var st: Node = get_node_or_null(STATS_PATH)
	if st and st.has_method("apply_creation_boosts"):
		var picks_arr: Array = []
		for i2 in range(_selected_order.size()):
			picks_arr.append(_selected_order[i2])
		st.call("apply_creation_boosts", picks_arr)

	# unlock chosen starting perk
	var chosen_perk_id: String = _chosen_perk_id()
	if chosen_perk_id != "":
		var ps: Node = get_node_or_null(PERK_PATH)
		if ps:
			if ps.has_method("unlock_by_id"):
				ps.call("unlock_by_id", chosen_perk_id)
			elif ps.has_method("unlock"):
				var idx2: int = (_perk_in.get_selected() if _perk_in else 0)
				ps.call("unlock", String(_perk_stat_by_idx.get(idx2,"")), 0)

	# refresh combat profiles
	var cps: Node = get_node_or_null(CPS_PATH)
	if cps and cps.has_method("refresh_all"):
		cps.call("refresh_all")

	# Nudge dorms to recompute bestie/rival from all THREE selected stats
	var dorms := get_node_or_null("/root/aDormSystem")
	if dorms and dorms.has_method("recompute_now"):
		dorms.call("recompute_now")

	creation_applied.emit()

	# optional routing forward only (no back)
	var router: Node = get_node_or_null(ROUTER_PATH)
	if router and router.has_method("goto_main"):
		router.call("goto_main")

# ── gating helpers ───────────────────────────────────────────────────────────
func _chosen_perk_id() -> String:
	if _perk_in == null:
		return ""
	var sel: int = _perk_in.get_selected()
	return String(_perk_id_by_idx.get(sel, ""))

func _update_confirm_enabled() -> void:
	if _confirm_btn == null: return
	var ready_stats: bool = (_selected_order.size() == 3)
	var ready_perk: bool = (_chosen_perk_id() != "")
	_confirm_btn.disabled = not (ready_stats and ready_perk)

# ── small helpers ─────────────────────────────────────────────────────────────
func _opt_text(ob: OptionButton) -> String:
	if ob == null: return ""
	var i: int = ob.get_selected()
	if i < 0: i = 0
	return ob.get_item_text(i)
