## ═══════════════════════════════════════════════════════════════════════════
## StatusPanel - Party Status & Appearance Display
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Main menu panel displaying party member HP/MP status, general game info
##   (money, perk points, date/time), and character appearance customization.
##
## RESPONSIBILITIES:
##   • Party member HP/MP display (with max values)
##   • Party member level and appearance preview
##   • Money and perk points display
##   • Current date/time display
##   • Hint/flavor text display
##   • Character appearance editor (skin, brow, eye, hair colors)
##   • Real-time status updates from combat/progression
##
## DISPLAY SECTIONS:
##   Left Panel:
##   • Party member list (name, level, HP/MP bars)
##   • Refresh button to update display
##
##   Right Panel:
##   • Money counter
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
##   • _refresh_party() - Update party member list display
##   • _refresh_summary() - Update money/perks/date/time
##   • _refresh_appearance() - Update appearance color swatches
##   • _on_color_changed(component, color) - Handle appearance edits
##
## ═══════════════════════════════════════════════════════════════════════════

extends Control
class_name StatusPanel

## Shows party HP/MP, summary info, and appearance.
## Prefers GameState meta + CombatProfileSystem; falls back to Stats/CSV.

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

@onready var _refresh : Button        = $Root/Left/PartyHeader/RefreshBtn
@onready var _party   : VBoxContainer = $Root/Left/PartyScroll/PartyList
@onready var _money   : Label         = $Root/Right/InfoGrid/MoneyValue
@onready var _perk    : Label         = $Root/Right/InfoGrid/PerkValue
@onready var _date    : Label         = $Root/Right/InfoGrid/DateValue
@onready var _phase   : Label         = $Root/Right/InfoGrid/PhaseValue
@onready var _hint    : RichTextLabel = $Root/Right/HintValue

var _gs        : Node = null
var _st        : Node = null
var _cal       : Node = null
var _mes       : Node = null
var _party_sys : Node = null
var _csv       : Node = null
var _resolver  : Node = null
var _sig       : Node = null
var _cps       : Node = null

# party.csv cache
var _csv_by_id   : Dictionary = {}      # "actor_id" -> row dict
var _name_to_id  : Dictionary = {}      # lowercase "name" -> "actor_id"

# Appearance UI
var _app_box    : VBoxContainer = null
var _app_grid   : GridContainer = null
var _app_labels : Dictionary = {}
var _sw_skin    : ColorRect = null
var _sw_brow    : ColorRect = null
var _sw_eye     : ColorRect = null
var _sw_hair    : ColorRect = null

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

	_resolve_event_system()
	_normalize_scroll_children()
	_connect_signals()
	_load_party_csv_cache()

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

	var members: Array = _get_party_snapshot()
	for it_v in members:
		if typeof(it_v) != TYPE_DICTIONARY: continue
		var it: Dictionary = it_v

		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 4)

		var disp := Label.new()
		disp.text = String(it.get("name", "Member"))
		row.add_child(disp)

		var hp_box := HBoxContainer.new(); hp_box.add_theme_constant_override("separation", 6)
		var hp_lbl := Label.new(); hp_lbl.custom_minimum_size.x = 36; hp_lbl.text = "HP"
		var hp_val := Label.new()
		var hp_i: int = int(it.get("hp", -1))
		var hp_max_i: int = int(it.get("hp_max", -1))
		hp_val.text = _fmt_pair(hp_i, hp_max_i)
		hp_box.add_child(hp_lbl); hp_box.add_child(hp_val)
		if hp_i >= 0 and hp_max_i > 0:
			var hp_bar := ProgressBar.new()
			hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hp_bar.min_value = 0.0
			hp_bar.max_value = float(hp_max_i)
			hp_bar.value     = clamp(float(hp_i), 0.0, float(hp_max_i))
			row.add_child(hp_bar)
		row.add_child(hp_box)

		var mp_box := HBoxContainer.new(); mp_box.add_theme_constant_override("separation", 6)
		var mp_lbl := Label.new(); mp_lbl.custom_minimum_size.x = 36; mp_lbl.text = "MP"
		var mp_val := Label.new()
		var mp_i: int = int(it.get("mp", -1))
		var mp_max_i: int = int(it.get("mp_max", -1))
		mp_val.text = _fmt_pair(mp_i, mp_max_i)
		mp_box.add_child(mp_lbl); mp_box.add_child(mp_val)
		if mp_i >= 0 and mp_max_i > 0:
			var mp_bar := ProgressBar.new()
			mp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			mp_bar.min_value = 0.0
			mp_bar.max_value = float(mp_max_i)
			mp_bar.value     = clamp(float(mp_i), 0.0, float(mp_max_i))
			row.add_child(mp_bar)
		row.add_child(mp_box)

		_party.add_child(row)

	await get_tree().process_frame
	_party.queue_sort()

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
	if _money: _money.text = _read_money()
	if _perk:  _perk.text  = _read_perk_points()

	var dp: Dictionary = _read_date_phase()
	if _date:  _date.text  = String(dp.get("date_text", "—"))
	if _phase: _phase.text = String(dp.get("phase_text", "—"))

	if _hint:
		var h: String = _read_mission_hint()
		_hint.text = h if h != "" else "[i]TBD[/i]"

# --------------------- Appearance -----------------------------

func _rebuild_appearance() -> void:
	_ensure_appearance_ui()
	_update_appearance_values()

func _ensure_appearance_ui() -> void:
	var right_parent: Control = (_hint.get_parent() as Control) if _hint else self

	_app_box = null
	for c in right_parent.get_children():
		if c is VBoxContainer and (c as VBoxContainer).name == "AppearanceBox":
			_app_box = c; break
	if _app_box != null: return

	var vb := VBoxContainer.new()
	_app_box = vb
	_app_box.name = "AppearanceBox"
	_app_box.add_theme_constant_override("separation", 6)
	right_parent.add_child(_app_box)

	var header := Label.new()
	header.text = "Appearance"
	_app_box.add_child(header)

	_app_grid = GridContainer.new()
	_app_grid.columns = 2
	_app_grid.add_theme_constant_override("hseparation", 8)
	_app_grid.add_theme_constant_override("vseparation", 4)
	_app_box.add_child(_app_grid)

	_appearance_add_row(_app_grid, _app_labels, "name", "Name")
	_appearance_add_row(_app_grid, _app_labels, "pronoun", "Pronoun")
	_appearance_add_row(_app_grid, _app_labels, "body", "Body ID")
	_appearance_add_row(_app_grid, _app_labels, "face", "Face ID")
	_appearance_add_row(_app_grid, _app_labels, "eyes", "Eyes ID")
	_appearance_add_row(_app_grid, _app_labels, "hair", "Hair ID")

	var sw := HBoxContainer.new()
	sw.add_theme_constant_override("separation", 8)
	_app_box.add_child(sw)

	_sw_skin = _make_swatch(sw, "Skin")
	_sw_brow = _make_swatch(sw, "Brows")
	_sw_eye  = _make_swatch(sw, "Eyes")
	_sw_hair = _make_swatch(sw, "Hair")

func _appearance_add_row(grid: GridContainer, labels_store: Dictionary, key: String, display: String) -> void:
	var l := Label.new(); l.text = display
	var v := Label.new(); v.name = key + "Value"
	grid.add_child(l); grid.add_child(v)
	labels_store[key] = v

func _make_swatch(parent_box: HBoxContainer, label_text: String) -> ColorRect:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var lb := Label.new(); lb.text = label_text; box.add_child(lb)
	var cr := ColorRect.new(); cr.custom_minimum_size = Vector2(42, 14); box.add_child(cr)
	parent_box.add_child(box)
	return cr

func _update_appearance_values() -> void:
	var snap: Dictionary = _read_hero_identity()
	var name_lbl: Label = _app_labels.get("name", null)
	var p_lbl: Label    = _app_labels.get("pronoun", null)
	var b_lbl: Label    = _app_labels.get("body", null)
	var f_lbl: Label    = _app_labels.get("face", null)
	var e_lbl: Label    = _app_labels.get("eyes", null)
	var h_lbl: Label    = _app_labels.get("hair", null)

	if name_lbl: name_lbl.text = String(snap.get("name", "Player"))
	if p_lbl:    p_lbl.text    = String(snap.get("pronoun", "they"))
	if b_lbl:    b_lbl.text    = String(snap.get("body", "1"))
	if f_lbl:    f_lbl.text    = String(snap.get("face", "1"))
	if e_lbl:    e_lbl.text    = String(snap.get("eyes", "1"))
	if h_lbl:    h_lbl.text    = String(snap.get("hair", "1"))

	if _sw_skin: _sw_skin.color = _as_color(snap.get("body_color", Color(1.0, 0.9, 0.8)))
	if _sw_brow: _sw_brow.color = _as_color(snap.get("brow_color", Color(0.2, 0.2, 0.2)))
	if _sw_eye:  _sw_eye.color  = _as_color(snap.get("eye_color",  Color(0.4, 0.5, 0.6)))
	if _sw_hair: _sw_hair.color = _as_color(snap.get("hair_color", Color(1, 1, 1)))

func _read_hero_identity() -> Dictionary:
	# First: GameState meta blob written by CharacterCreation
	if _gs:
		if _gs.has_meta("hero_identity"):
			var id_v: Variant = _gs.get_meta("hero_identity")
			if typeof(id_v) == TYPE_DICTIONARY:
				var id: Dictionary = id_v
				return {
					"name": String(id.get("name","Player")),
					"pronoun": String(id.get("pronoun","they")),
					"body": String(id.get("body","1")),
					"face": String(id.get("face","1")),
					"eyes": String(id.get("eyes","1")),
					"hair": String(id.get("hair","1")),
					"body_color": _as_color(id.get("body_color", Color(1.0,0.9,0.8))),
					"brow_color": _as_color(id.get("brow_color", Color(0.2,0.2,0.2))),
					"eye_color":  _as_color(id.get("eye_color",  Color(0.4,0.5,0.6))),
					"hair_color": _as_color(id.get("hair_color", Color(1,1,1))),
				}
		# Soft fallback: properties
		if _gs.has_method("get"):
			var out: Dictionary = {
				"name": String(_gs.get("player_name")) if _gs.get("player_name") != null else "Player",
				"pronoun":"they","body":"1","face":"1","eyes":"1","hair":"1",
				"body_color": Color(1.0,0.9,0.8),
				"brow_color": Color(0.2,0.2,0.2),
				"eye_color":  Color(0.4,0.5,0.6),
				"hair_color": Color(1,1,1),
			}
			return out
	# Default
	return {
		"name":"Player","pronoun":"they","body":"1","face":"1","eyes":"1","hair":"1",
		"body_color": Color(1.0, 0.9, 0.8),
		"brow_color": Color(0.2, 0.2, 0.2),
		"eye_color" : Color(0.4, 0.5, 0.6),
		"hair_color": Color(1, 1, 1)
	}

func _as_color(v: Variant) -> Color:
	if typeof(v) == TYPE_COLOR: return v as Color
	if typeof(v) == TYPE_STRING: return Color(String(v))
	return Color(1,1,1)

# --------------------- Small helpers -------------------------

func _read_money() -> String:
	if _gs:
		if _gs.has_method("get_money"): return str(int(_gs.call("get_money")))
		if _gs.has_method("get"):
			var v: Variant = _gs.get("money")
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
	if not OS.is_debug_build(): return
	_dev_dump_profiles()

func _unhandled_input(event: InputEvent) -> void:
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
