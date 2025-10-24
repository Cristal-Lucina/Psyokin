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

@onready var _skin_opt    : OptionButton  = %BodyColorInput
@onready var _skin_sw     : ColorRect     = %BodyColorSwatch
@onready var _brow_opt    : OptionButton  = %EyebrowColorInput
@onready var _brow_sw     : ColorRect     = %EyebrowColorSwatch
@onready var _eye_opt     : OptionButton  = %EyeColorInput
@onready var _eye_sw      : ColorRect     = %EyeColorSwatch
@onready var _hair_opt    : OptionButton  = %HairColorInput
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

# ── Color palettes ───────────────────────────────────────────────────────────
# Skin tones: specific discrete options from darkest to lightest
const SKIN_TONES := {
	"Tone 1": Color(0.227, 0.239, 0.212),  # #3A3D36 - Darkest
	"Tone 2": Color(0.400, 0.302, 0.282),  # #664D48 - Dark
	"Tone 3": Color(0.588, 0.388, 0.306),  # #96634E - Medium-Dark
	"Tone 4": Color(0.780, 0.553, 0.459),  # #C78D75 - Medium
	"Tone 5": Color(0.839, 0.667, 0.553),  # #D6AA8D - Light
	"Tone 6": Color(0.847, 0.733, 0.663)   # #D8BBA9 - Lightest
}

# Hair/Eyebrow: white, ROYGBIV, black
const HAIR_COLORS := {
	"White": Color(0.95, 0.95, 0.95),
	"Red": Color(0.8, 0.2, 0.2),
	"Orange": Color(0.9, 0.5, 0.2),
	"Yellow": Color(0.9, 0.85, 0.3),
	"Green": Color(0.3, 0.6, 0.3),
	"Blue": Color(0.2, 0.4, 0.7),
	"Indigo": Color(0.3, 0.2, 0.6),
	"Violet": Color(0.6, 0.3, 0.7),
	"Black": Color(0.15, 0.15, 0.15)
}

# Eye colors: Brown, Blue, Green, Hazel, Grey, White, Black, Yellow, Red, Pink
const EYE_COLORS := {
	"Brown": Color(0.4, 0.25, 0.15),
	"Blue": Color(0.3, 0.5, 0.8),
	"Green": Color(0.3, 0.6, 0.4),
	"Hazel": Color(0.5, 0.4, 0.25),
	"Grey": Color(0.6, 0.6, 0.65),
	"White": Color(0.9, 0.9, 0.95),
	"Black": Color(0.1, 0.1, 0.1),
	"Yellow": Color(0.85, 0.8, 0.3),
	"Red": Color(0.8, 0.2, 0.2),
	"Pink": Color(0.9, 0.5, 0.7)
}

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

	# Color dropdowns
	_fill_color_opt(_skin_opt, SKIN_TONES)
	_fill_color_opt(_eye_opt, EYE_COLORS)
	_fill_color_opt(_brow_opt, HAIR_COLORS)
	_fill_color_opt(_hair_opt, HAIR_COLORS)

	# Initial swatches
	_update_color_swatches()

func _fill_opt(ob: OptionButton, items: Array) -> void:
	if ob == null: return
	if ob.item_count > 0: return
	for s in items:
		ob.add_item(String(s))
	ob.select(0)

func _fill_color_opt(ob: OptionButton, colors: Dictionary) -> void:
	if ob == null: return
	if ob.item_count > 0: return
	for color_name in colors.keys():
		ob.add_item(String(color_name))
	ob.select(0)

func _wire_colors() -> void:
	if _skin_opt and not _skin_opt.item_selected.is_connected(_on_color_option_changed):
		_skin_opt.item_selected.connect(_on_color_option_changed)
	if _brow_opt and not _brow_opt.item_selected.is_connected(_on_color_option_changed):
		_brow_opt.item_selected.connect(_on_color_option_changed)
	if _eye_opt and not _eye_opt.item_selected.is_connected(_on_color_option_changed):
		_eye_opt.item_selected.connect(_on_color_option_changed)
	if _hair_opt and not _hair_opt.item_selected.is_connected(_on_color_option_changed):
		_hair_opt.item_selected.connect(_on_color_option_changed)

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
func _on_color_option_changed(_idx: int) -> void:
	_update_color_swatches()

func _update_color_swatches() -> void:
	if _skin_sw: _skin_sw.color = _get_color_from_option(_skin_opt, SKIN_TONES, Color(0.847, 0.733, 0.663))
	if _brow_sw: _brow_sw.color = _get_color_from_option(_brow_opt, HAIR_COLORS, Color(0.15, 0.15, 0.15))
	if _eye_sw:  _eye_sw.color  = _get_color_from_option(_eye_opt, EYE_COLORS, Color(0.4, 0.25, 0.15))
	if _hair_sw: _hair_sw.color = _get_color_from_option(_hair_opt, HAIR_COLORS, Color(0.15, 0.15, 0.15))

func _get_color_from_option(opt: OptionButton, palette: Dictionary, default: Color) -> Color:
	if opt == null: return default
	var idx: int = opt.get_selected()
	if idx < 0 or idx >= opt.item_count: return default
	var color_name: String = opt.get_item_text(idx)
	return palette.get(color_name, default)

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

	var c_skin: Color = _get_color_from_option(_skin_opt, SKIN_TONES, Color(0.847, 0.733, 0.663))
	var c_brow: Color = _get_color_from_option(_brow_opt, HAIR_COLORS, Color(0.15, 0.15, 0.15))
	var c_eye: Color  = _get_color_from_option(_eye_opt, EYE_COLORS, Color(0.4, 0.25, 0.15))
	var c_hair: Color = _get_color_from_option(_hair_opt, HAIR_COLORS, Color(0.15, 0.15, 0.15))

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
