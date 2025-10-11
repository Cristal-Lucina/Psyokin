extends Control
class_name CharacterCreation

## CharacterCreation — Name / Pronoun / IDs (1..9) for Body, Face, Eyes, Hair
## Sliders: Skin Tone (0..100), Eyebrow Hue (0..360), Eye Color (0..100), Hair Hue (0..360)
## Pick exactly 3 stats: Brawn / Vitality / Tempo / Mind / Focus
## Battle Perk dropdown (filtered by the three picks).

# ---------------------- Palettes / tuning (vars to avoid const expression limits) ----------------------

var EYE_POS: PackedFloat32Array = PackedFloat32Array([0.0, 20.0, 40.0, 60.0, 80.0, 100.0])
var EYE_COL: PackedColorArray   = PackedColorArray([
	Color("#3b2a17"), Color("#6b4a2d"), Color("#8a6a3b"),
	Color("#3e6f48"), Color("#2e5a8a"), Color("#6d7a86")
])

var SKIN_POS: PackedFloat32Array = PackedFloat32Array([0.0, 15.0, 30.0, 50.0, 70.0, 85.0, 100.0])
var SKIN_COL: PackedColorArray   = PackedColorArray([
	Color("#FBE8D3"), Color("#F2D3B3"), Color("#E0B894"),
	Color("#C28E6B"), Color("#A16244"), Color("#7D452B"), Color("#4E2A17")
])

const HAIR_S: float = 0.75
const HAIR_V: float = 0.60
const BROW_S: float = 0.65
const BROW_V: float = 0.55

# ---------------------- UI (resolved at runtime) ----------------------

var _name_input    : LineEdit     = null
var _pronoun_input : OptionButton = null

var _body_input    : OptionButton = null
var _face_input    : OptionButton = null
var _eyes_input    : OptionButton = null
var _hair_input    : OptionButton = null

var _skin_slider   : HSlider      = null
var _skin_swatch   : ColorRect    = null

var _brow_slider   : HSlider      = null
var _brow_swatch   : ColorRect    = null

var _eye_slider    : HSlider      = null
var _eye_swatch    : ColorRect    = null

var _hair_slider   : HSlider      = null
var _hair_swatch   : ColorRect    = null

var _perk_input    : OptionButton = null
var _error_label   : Label        = null

# Stats
var _cb_brw: CheckButton = null
var _cb_vtl: CheckButton = null
var _cb_tpo: CheckButton = null
var _cb_mnd: CheckButton = null
var _cb_fcs: CheckButton = null

# Live colors
var _skin_color: Color = Color(1.0, 0.9, 0.8)
var _brow_color: Color = Color.from_hsv(0.0, BROW_S, BROW_V)
var _eye_color : Color = Color(0.4, 0.5, 0.6)
var _hair_color: Color = Color.from_hsv(0.0, HAIR_S, HAIR_V)

var _max_stat_picks: int = 3

# ---------------------- Lifecycle ----------------------

func _ready() -> void:
	_resolve_ui()
	_populate_pronouns()
	_populate_ids(_body_input)
	_populate_ids(_face_input)
	_populate_ids(_eyes_input)
	_populate_ids(_hair_input)

	_wire_stat_limiters()
	_wire_color_sliders()
	_wire_perk_tooltip()

	# sensible defaults
	if EYE_COL.size() > 1:
		_eye_color = EYE_COL[1]
	if SKIN_COL.size() > 2:
		_skin_color = SKIN_COL[2]

	_refresh_swatches()
	_rebuild_perk_dropdown()
	if _error_label:
		_error_label.text = ""

# ---------------------- Resolve nodes safely ----------------------------------

func _find(node_name: String) -> Node:
	# recursive search by node name anywhere under this Control
	return find_child(node_name, true, false)

func _resolve_ui() -> void:
	# Text inputs
	_name_input     = _find("NameInput") as LineEdit
	_pronoun_input  = _find("PronounInput") as OptionButton

	# ID dropdowns
	_body_input     = _find("BodyIdInput") as OptionButton
	_face_input     = _find("FaceIdInput") as OptionButton
	_eyes_input     = _find("EyesIdInput") as OptionButton
	_hair_input     = _find("HairIdInput") as OptionButton

	# Sliders + swatches
	_skin_slider    = _find("BodyColorInput") as HSlider
	_skin_swatch    = _find("BodyColorSwatch") as ColorRect

	_brow_slider    = _find("EyebrowColorInput") as HSlider
	_brow_swatch    = _find("EyebrowColorSwatch") as ColorRect

	_eye_slider     = _find("EyeColorInput") as HSlider
	_eye_swatch     = _find("EyeColorSwatch") as ColorRect

	_hair_slider    = _find("HairColorInput") as HSlider
	_hair_swatch    = _find("HairColorSwatch") as ColorRect

	# Perk + error label
	_perk_input     = _find("PerkInput") as OptionButton
	_error_label    = _find("ErrorLabel") as Label  # optional in your scene

	# Stat toggles
	_cb_brw = _find("StatBRW") as CheckButton
	_cb_vtl = _find("StatVTL") as CheckButton
	_cb_tpo = _find("StatTPO") as CheckButton
	_cb_mnd = _find("StatMND") as CheckButton
	_cb_fcs = _find("StatFCS") as CheckButton

# ---------------------- Populate / Wire --------------------------------------

func _populate_pronouns() -> void:
	if _pronoun_input == null: return
	_pronoun_input.clear()
	_pronoun_input.add_item("They / Them")  # 0 -> they
	_pronoun_input.add_item("She / Her")    # 1 -> she
	_pronoun_input.add_item("He / Him")     # 2 -> he
	_pronoun_input.add_item("Any (RND)")    # 3 -> rnd
	_pronoun_input.select(0)

func _populate_ids(ob: OptionButton) -> void:
	if ob == null: return
	ob.clear()
	for i in range(1, 10):
		var label: String = "ID %d" % i
		ob.add_item(label)
		ob.set_item_metadata(i - 1, str(i))
	ob.select(0)

func _wire_stat_limiters() -> void:
	var cbs: Array = [_cb_brw, _cb_vtl, _cb_tpo, _cb_mnd, _cb_fcs]
	for cb in cbs:
		if cb and not cb.toggled.is_connected(_on_stat_toggled):
			cb.toggled.connect(_on_stat_toggled)

func _on_stat_toggled(_pressed: bool) -> void:
	var selected: int = _selected_stat_count()
	var limit_reached: bool = selected >= _max_stat_picks
	for cb in [_cb_brw, _cb_vtl, _cb_tpo, _cb_mnd, _cb_fcs]:
		if cb and not cb.button_pressed:
			cb.disabled = limit_reached
	_rebuild_perk_dropdown()

func _wire_color_sliders() -> void:
	if _skin_slider and not _skin_slider.value_changed.is_connected(_on_skin_changed):
		_skin_slider.value_changed.connect(_on_skin_changed)
	if _brow_slider and not _brow_slider.value_changed.is_connected(_on_brow_changed):
		_brow_slider.value_changed.connect(_on_brow_changed)
	if _eye_slider and not _eye_slider.value_changed.is_connected(_on_eye_changed):
		_eye_slider.value_changed.connect(_on_eye_changed)
	if _hair_slider and not _hair_slider.value_changed.is_connected(_on_hair_changed):
		_hair_slider.value_changed.connect(_on_hair_changed)

	# kick defaults (also triggers handlers)
	if _skin_slider: _skin_slider.value = 30.0
	if _brow_slider: _brow_slider.value = 0.0
	if _eye_slider:  _eye_slider.value  = 20.0
	if _hair_slider: _hair_slider.value = 0.0

func _on_skin_changed(v: float) -> void:
	_skin_color = _gradient_sample(SKIN_POS, SKIN_COL, clamp(v, 0.0, 100.0))
	_refresh_swatches()

func _on_brow_changed(v: float) -> void:
	_brow_color = Color.from_hsv(clamp(v, 0.0, 360.0) / 360.0, BROW_S, BROW_V)
	_refresh_swatches()

func _on_eye_changed(v: float) -> void:
	_eye_color = _gradient_sample(EYE_POS, EYE_COL, clamp(v, 0.0, 100.0))
	_refresh_swatches()

func _on_hair_changed(v: float) -> void:
	_hair_color = Color.from_hsv(clamp(v, 0.0, 360.0) / 360.0, HAIR_S, HAIR_V)
	_refresh_swatches()

func _refresh_swatches() -> void:
	if _skin_swatch: _skin_swatch.color = _skin_color
	if _brow_swatch: _brow_swatch.color = _brow_color
	if _eye_swatch:  _eye_swatch.color  = _eye_color
	if _hair_swatch: _hair_swatch.color = _hair_color

# ---------------------- Perk dropdown (stat-dependent) ----------------------

func _wire_perk_tooltip() -> void:
	if _perk_input and not _perk_input.item_selected.is_connected(_on_perk_item_selected):
		_perk_input.item_selected.connect(_on_perk_item_selected)

func _on_perk_item_selected(_idx: int) -> void:
	_update_perk_tooltip()

func _selected_stat_count() -> int:
	var n: int = 0
	for cb in [_cb_brw, _cb_vtl, _cb_tpo, _cb_mnd, _cb_fcs]:
		if cb and cb.button_pressed:
			n += 1
	return n

func _selected_stats_array() -> Array:
	var arr: Array = []
	if _cb_brw and _cb_brw.button_pressed: arr.append("BRW")
	if _cb_vtl and _cb_vtl.button_pressed: arr.append("VTL")
	if _cb_tpo and _cb_tpo.button_pressed: arr.append("TPO")
	if _cb_mnd and _cb_mnd.button_pressed: arr.append("MND")
	if _cb_fcs and _cb_fcs.button_pressed: arr.append("FCS")
	return arr

func _rebuild_perk_dropdown() -> void:
	if _perk_input == null: return
	_perk_input.clear()

	var options: Array = []
	var ps: Node = get_node_or_null("/root/aPerkSystem")
	if ps != null and ps.has_method("get_starting_options"):
		options = ps.call("get_starting_options", _selected_stats_array())

	if options.is_empty() and ps != null and ps.has_method("get_starting_options"):
		options = ps.call("get_starting_options", ["BRW","VTL","TPO","MND","FCS"])

	var idx: int = 0
	for opt_v in options:
		if typeof(opt_v) != TYPE_DICTIONARY:
			continue
		var opt: Dictionary = opt_v
		var label: String = "%s — %s" % [String(opt.get("stat","")), String(opt.get("name","Perk"))]
		_perk_input.add_item(label)
		_perk_input.set_item_metadata(idx, {"id": String(opt.get("id","")), "desc": String(opt.get("desc",""))})
		idx += 1

	if _perk_input.item_count == 0:
		_perk_input.add_item("Starter Perk")
		_perk_input.set_item_metadata(0, {"id":"starter","desc":""})

	_perk_input.select(0)
	_update_perk_tooltip()

func _update_perk_tooltip() -> void:
	if _perk_input == null:
		return
	var sel: int = _perk_input.get_selected()
	if sel < 0:
		_perk_input.tooltip_text = ""
		return
	var md_v: Variant = _perk_input.get_item_metadata(sel)
	var tip: String = ""
	if typeof(md_v) == TYPE_DICTIONARY:
		tip = String((md_v as Dictionary).get("desc",""))
	_perk_input.tooltip_text = tip

# ---------------------- Confirm / Cancel -------------------------------------

func _gather_config() -> Dictionary:
	var pronoun_key: String = "they"
	if _pronoun_input != null:
		match _pronoun_input.get_selected():
			1: pronoun_key = "she"
			2: pronoun_key = "he"
			3: pronoun_key = "rnd"
			_: pronoun_key = "they"

	# Convert selected stats to Array[StringName] (no lambdas)
	var picks_arr: Array = _selected_stats_array()
	var picks_sn: Array[StringName] = []
	for s in picks_arr:
		picks_sn.append(StringName(String(s)))

	return {
		"name": _name_input.text if _name_input else "Player",
		"pronoun": pronoun_key,
		"body_id": _current_id(_body_input),
		"face_id": _current_id(_face_input),
		"eyes_id": _current_id(_eyes_input),
		"hair_id": _current_id(_hair_input),
		"body_color": _skin_color,
		"brow_color": _brow_color,
		"eye_color": _eye_color,
		"hair_color": _hair_color,
		"starting_stats": picks_sn,
		"starting_perk_id": _current_perk_id(),
	}

func _on_confirm_pressed() -> void:
	if _error_label: _error_label.text = ""
	if _selected_stat_count() != 3:
		if _error_label: _error_label.text = "Pick exactly three starting stats."
		return

	var hero: HeroSystem = _find_hero()
	if hero == null:
		if _error_label: _error_label.text = "HeroSystem not found. Check autoloads."
		return

	hero.clear_all()
	var cfg: Dictionary = _gather_config()
	hero.apply_creation(cfg)

	# --- Make the three chosen stats level 2 at game start (robust across APIs)
	var stats_system: Node = get_node_or_null("/root/aStatsSystem")
	if stats_system != null:
		var picks_v: Variant = cfg.get("starting_stats", [])
		if typeof(picks_v) == TYPE_ARRAY:
			var picks_str: Array[String] = []
			for x in (picks_v as Array):
				picks_str.append(String(x))

			# Preferred API(s)
			var handled: bool = false
			if stats_system.has_method("apply_starting_picks"):
				stats_system.call("apply_starting_picks", picks_str)
				handled = true
			elif stats_system.has_method("apply_creation_boosts"):
				stats_system.call("apply_creation_boosts", picks_str)
				handled = true

			# Fallback: directly bump stat_level[...] to 2 and emit signals
			if not handled and stats_system.has_method("get") and stats_system.has_method("set"):
				var sl_v: Variant = stats_system.get("stat_level")
				if typeof(sl_v) == TYPE_DICTIONARY:
					var sl: Dictionary = sl_v
					for sid in picks_str:
						var cur: int = int(sl.get(sid, 1))
						if cur < 2:
							sl[sid] = 2
					stats_system.set("stat_level", sl)
					# Fire any signals the system exposes so UIs refresh
					if stats_system.has_signal("stats_changed"):
						stats_system.emit_signal("stats_changed")
					for sid2 in picks_str:
						var lvl: int = int(sl.get(sid2, 2))
						if stats_system.has_signal("stat_leveled_up"):
							stats_system.emit_signal("stat_leveled_up", sid2, lvl)
						if stats_system.has_signal("level_up"):
							stats_system.emit_signal("level_up", sid2, lvl)

	# Unlock the chosen starter perk (if supported)
	var perk_id: String = String(cfg.get("starting_perk_id",""))
	var perk_sys: Node = get_node_or_null("/root/aPerkSystem")
	if perk_sys != null and perk_id != "" and perk_sys.has_method("unlock_by_id"):
		perk_sys.call("unlock_by_id", perk_id)

	# Optional: spend the one starting perk point if your Stats exposes it
	if stats_system != null and stats_system.has_method("spend_perk_point"):
		stats_system.call("spend_perk_point", 1)

	# Give & equip starter kit if present
	if has_node("/root/aStarterLoadout"):
		aStarterLoadout.apply_for_new_game()

	_route_to_main()

func _on_cancel_pressed() -> void:
	_route_to_title()

# ---------------------- Helpers ----------------------------------------------

func _current_id(ob: OptionButton) -> String:
	if ob == null:
		return "1"
	var idx: int = ob.get_selected()
	if idx < 0:
		idx = 0
	var md: Variant = ob.get_item_metadata(idx)
	if typeof(md) == TYPE_STRING or typeof(md) == TYPE_INT:
		return String(md)
	# Fallback to visible text "ID X"
	return ob.get_item_text(idx).replace("ID ", "")

func _current_perk_id() -> String:
	if _perk_input == null:
		return ""
	var idx: int = _perk_input.get_selected()
	var md: Variant = _perk_input.get_item_metadata(idx)
	if typeof(md) == TYPE_DICTIONARY:
		return String((md as Dictionary).get("id",""))
	return String(md)

func _find_hero() -> HeroSystem:
	var n: Node = get_node_or_null("/root/aHeroSystem")
	if n == null: n = get_node_or_null("/root/HeroSystem")
	return n as HeroSystem

func _route_to_main() -> void:
	var router: Node = get_node_or_null("/root/aSceneRouter")
	if router != null and router.has_method("goto_main"):
		router.call("goto_main")
		return
	if ResourceLoader.exists("res://scenes/main/Main.tscn"):
		get_tree().change_scene_to_file("res://scenes/main/Main.tscn")

func _route_to_title() -> void:
	var router: Node = get_node_or_null("/root/aSceneRouter")
	if router != null and router.has_method("goto_title"):
		router.call("goto_title")
		return
	if ResourceLoader.exists("res://scenes/main_menu/Title.tscn"):
		get_tree().change_scene_to_file("res://scenes/main_menu/Title.tscn")

# gradient sampler (positions asc, colors same length)
func _gradient_sample(pos: PackedFloat32Array, cols: PackedColorArray, t: float) -> Color:
	var n: int = pos.size()
	if n == 0:
		return Color.WHITE
	if t <= pos[0]:
		return cols[0]
	if t >= pos[n - 1]:
		return cols[n - 1]
	for i in range(n - 1):
		var a: float = pos[i]
		var b: float = pos[i + 1]
		if t >= a and t <= b:
			var denom: float = max(0.0001, (b - a))
			var k: float = (t - a) / denom
			return cols[i].lerp(cols[i + 1], k)
	return cols[n - 1]
