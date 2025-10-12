extends Control
class_name StatusPanel

## Shows party HP/MP, summary info, and appearance. 
## Refreshes on time/stat/party changes. Fallbacks if a system is missing.

const GS_PATH    := "/root/aGameState"
const STATS_PATH := "/root/aStatsSystem"
const CAL_PATH   := "/root/aCalendarSystem"
const HERO_PATH  := "/root/aHeroSystem"
const PARTY_PATH := "/root/aPartySystem"

const MES_PATH        := "/root/aMainEventSystem"
const ALT_MES_PATHS   := [
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

var _gs  : Node = null
var _st  : Node = null
var _cal : Node = null
var _mes : Node = null
var _hero: Node = null
var _party_sys: Node = null

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

	_gs       = get_node_or_null(GS_PATH)
	_st       = get_node_or_null(STATS_PATH)
	_cal      = get_node_or_null(CAL_PATH)
	_hero     = get_node_or_null(HERO_PATH)
	if _hero == null: _hero = get_node_or_null("/root/HeroSystem")
	_party_sys = get_node_or_null(PARTY_PATH)

	_resolve_event_system()
	_normalize_scroll_children()
	_connect_signals()

	if _refresh and not _refresh.pressed.is_connected(_rebuild_all):
		_refresh.pressed.connect(_rebuild_all)

	# Defer first fill so systems have time to boot and emit party.
	call_deferred("_first_fill")

func _first_fill() -> void:
	# Late-bind in case systems spawned after our _ready
	if _gs == null:        _gs        = get_node_or_null(GS_PATH)
	if _st == null:        _st        = get_node_or_null(STATS_PATH)
	if _cal == null:       _cal       = get_node_or_null(CAL_PATH)
	if _hero == null:      _hero      = get_node_or_null(HERO_PATH)
	if _hero == null:      _hero      = get_node_or_null("/root/HeroSystem")
	if _party_sys == null: _party_sys = get_node_or_null(PARTY_PATH)
	_rebuild_all()

func _connect_signals() -> void:
	# Calendar
	if _cal:
		if _cal.has_signal("day_advanced"):   _cal.connect("day_advanced",   Callable(self, "_rebuild_all"))
		if _cal.has_signal("phase_advanced"): _cal.connect("phase_advanced", Callable(self, "_rebuild_all"))
		if _cal.has_signal("week_reset"):     _cal.connect("week_reset",     Callable(self, "_rebuild_all"))
	# Stats
	if _st and _st.has_signal("stats_changed"):
		_st.connect("stats_changed", Callable(self, "_rebuild_all"))
	# Hero
	if _hero and _hero.has_signal("creation_applied"):
		_hero.connect("creation_applied", Callable(self, "_rebuild_all"))
	# Party / GameState changes (try a few common names)
	for src in [_gs, _party_sys]:
		if src == null: continue
		for sig in ["party_changed","active_changed","roster_changed","changed"]:
			if src.has_signal(sig) and not src.is_connected(sig, Callable(self, "_on_party_changed")):
				src.connect(sig, Callable(self, "_on_party_changed"))

func _on_party_changed(_a: Variant = null) -> void:
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

		var name_lbl := Label.new()
		name_lbl.text = String(it.get("name", "Member"))
		row.add_child(name_lbl)

		# HP
		var hp_box := HBoxContainer.new(); hp_box.add_theme_constant_override("separation", 6)
		var hp_lbl := Label.new(); hp_lbl.custom_minimum_size.x = 36; hp_lbl.text = "HP"
		var hp_val := Label.new()
		var hp := int(it.get("hp", -1))
		var hp_max := int(it.get("hp_max", -1))
		hp_val.text = _fmt_pair(hp, hp_max)
		hp_box.add_child(hp_lbl); hp_box.add_child(hp_val)
		if hp >= 0 and hp_max > 0:
			var hp_bar := ProgressBar.new()
			hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hp_bar.min_value = 0.0
			hp_bar.max_value = float(hp_max)
			hp_bar.value     = clamp(float(hp), 0.0, float(hp_max))
			row.add_child(hp_bar)
		row.add_child(hp_box)

		# MP
		var mp_box := HBoxContainer.new(); mp_box.add_theme_constant_override("separation", 6)
		var mp_lbl := Label.new(); mp_lbl.custom_minimum_size.x = 36; mp_lbl.text = "MP"
		var mp_val := Label.new()
		var mp := int(it.get("mp", -1))
		var mp_max := int(it.get("mp_max", -1))
		mp_val.text = _fmt_pair(mp, mp_max)
		mp_box.add_child(mp_lbl); mp_box.add_child(mp_val)
		if mp >= 0 and mp_max > 0:
			var mp_bar := ProgressBar.new()
			mp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			mp_bar.min_value = 0.0
			mp_bar.max_value = float(mp_max)
			mp_bar.value     = clamp(float(mp), 0.0, float(mp_max))
			row.add_child(mp_bar)
		row.add_child(mp_box)

		_party.add_child(row)

	await get_tree().process_frame
	_party.queue_sort()

# --------------------- Right column summary -------------------

func _update_summary() -> void:
	if _money: _money.text = _read_money()
	if _perk:  _perk.text  = _read_perk_points()

	var dp := _read_date_phase()
	if _date:  _date.text  = String(dp.get("date_text", "—"))
	if _phase: _phase.text = String(dp.get("phase_text", "—"))

	if _hint:
		var h := _read_mission_hint()
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

	_app_box = VBoxContainer.new()
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
	var snap := _read_hero_identity()
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
	var out: Dictionary = {
		"name":"Player","pronoun":"they","body":"1","face":"1","eyes":"1","hair":"1",
		"body_color": Color(1.0, 0.9, 0.8),
		"brow_color": Color(0.2, 0.2, 0.2),
		"eye_color" : Color(0.4, 0.5, 0.6),
		"hair_color": Color(1, 1, 1)
	}
	var h := _hero
	if h == null: return out

	if h.has_method("get_save_blob"):
		var v: Variant = h.call("get_save_blob")
		if typeof(v) == TYPE_DICTIONARY:
			var blob: Dictionary = v
			var id_v: Variant = blob.get("identity", {})
			if typeof(id_v) == TYPE_DICTIONARY:
				var id: Dictionary = id_v
				out["name"] = String(id.get("name", out["name"]))
				out["pronoun"] = String(id.get("pronoun", out["pronoun"]))
				out["body"] = String(id.get("body", out["body"]))
				out["face"] = String(id.get("face", out["face"]))
				out["eyes"] = String(id.get("eyes", out["eyes"]))
				out["hair"] = String(id.get("hair", out["hair"]))
				out["body_color"] = _as_color(id.get("body_color", out["body_color"]))
				out["brow_color"] = _as_color(id.get("brow_color", out["brow_color"]))
				out["eye_color"]  = _as_color(id.get("eye_color",  out["eye_color"]))
				out["hair_color"] = _as_color(id.get("hair_color", out["hair_color"]))
			return out

	if h.has_method("get"):
		var props: Dictionary = {
			"hero_name":"name", "pronoun":"pronoun",
			"body_id":"body","face_id":"face","eyes_id":"eyes","hair_id":"hair",
			"body_color":"body_color","brow_color":"brow_color",
			"eye_color":"eye_color","hair_color":"hair_color"
		}
		for k in props.keys():
			var key_engine: String = String(k)
			var key_out: String = String(props[k])
			var vv: Variant = h.get(key_engine)
			if key_out in ["name","pronoun","body","face","eyes","hair"]:
				if typeof(vv) == TYPE_STRING: out[key_out] = String(vv)
			else:
				out[key_out] = _as_color(vv)
	return out

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
			var h := String(_mes.call("get_current_hint"))
			if h != "": return h
		if _mes.has_method("get_current_title"):
			var t := String(_mes.call("get_current_title"))
			if t != "": return t
	if _gs:
		if _gs.has_method("get_mission_hint"): return String(_gs.call("get_mission_hint"))
		if _gs.has_method("get"):
			var v: Variant = _gs.get("mission_hint")
			if typeof(v) == TYPE_STRING: return String(v)
	return ""

func _on_event_changed(_id: String) -> void:
	if _hint:
		var h := _read_mission_hint()
		_hint.text = h if h != "" else "[i]TBD[/i]"

func _fmt_pair(a: int, b: int) -> String:
	return "%d / %d" % [a, b] if a >= 0 and b > 0 else "—"

# --------------------- Party snapshot logic -------------------

func _get_party_snapshot() -> Array:
	# If GameState already exposes a ready-made snapshot, use it.
	if _gs and _gs.has_method("get_party_snapshot"):
		var res: Variant = _gs.call("get_party_snapshot")
		if typeof(res) == TYPE_ARRAY: return res as Array
	# Otherwise build one from whatever active/roster shape exists.
	return _build_snapshot_flexible()

func _build_snapshot_flexible() -> Array:
	var out: Array = []
	var roster := _read_roster()

	# Collect active as robust entries {key, label}
	var entries := _gather_active_entries(roster)

	for e_v in entries:
		if typeof(e_v) != TYPE_DICTIONARY: continue
		var e: Dictionary = e_v
		var pid: String = String(e.get("key",""))
		var label: String = String(e.get("label",""))

		# Try direct roster hit; if not, try by name
		var rec: Dictionary = {}
		if pid != "" and roster.has(pid):
			rec = roster[pid]
		elif label != "":
			for rk in roster.keys():
				var rr: Dictionary = roster[rk]
				if rr.has("name") and String(rr["name"]).strip_edges() == label.strip_edges():
					rec = rr; pid = String(rk); break

		# Name / level
		var char_name: String = (label if label != "" else pid)
		if pid == "hero" or char_name == "":
			char_name = _safe_hero_name()

		var level: int = 1
		if pid == "hero" and _hero and _hero.has_method("get"):
			level = int(_hero.get("level"))
		elif not rec.is_empty():
			level = int(rec.get("level", 1))

		# Stats to compute maxima
		var stats_d: Dictionary = {}
		if not rec.is_empty() and rec.has("stats") and typeof(rec["stats"]) == TYPE_DICTIONARY:
			stats_d = rec["stats"]
		var vtl: int = int(stats_d.get("VTL", 1))
		var fcs: int = int(stats_d.get("FCS", 1))

		var hp_max: int = _calc_max_hp(level, vtl)
		var mp_max: int = _calc_max_mp(level, fcs)

		# Current HP/MP if provided
		var hp_cur := hp_max
		var mp_cur := mp_max
		if not rec.is_empty() and rec.has("hp") and typeof(rec["hp"]) == TYPE_DICTIONARY:
			var hp_d: Dictionary = rec["hp"]
			hp_cur = int(hp_d.get("cur", hp_max))
			hp_max = int(hp_d.get("max", hp_max))
		if not rec.is_empty() and rec.has("mp") and typeof(rec["mp"]) == TYPE_DICTIONARY:
			var mp_d: Dictionary = rec["mp"]
			mp_cur = int(mp_d.get("cur", mp_max))
			mp_max = int(mp_d.get("max", mp_max))

		hp_cur = clamp(hp_cur, 0, hp_max)
		mp_cur = clamp(mp_cur, 0, mp_max)

		out.append({
			"name": "%s  (Lv %d)" % [char_name, level],
			"hp": hp_cur, "hp_max": hp_max,
			"mp": mp_cur, "mp_max": mp_max
		})

	# Last resort: show hero only
	if out.is_empty():
		var nm := _safe_hero_name()
		var lvl := _safe_hero_level()
		var mh := _calc_max_hp(lvl, 1)
		var mm := _calc_max_mp(lvl, 1)
		out.append({"name":"%s  (Lv %d)" % [nm, lvl], "hp": mh, "hp_max": mh, "mp": mm, "mp_max": mm})

	return out

# ---- Active/roster discovery helpers --------------------------------

func _array_from_any(v: Variant) -> Array:
	if typeof(v) == TYPE_ARRAY: return v as Array
	if typeof(v) == TYPE_PACKED_STRING_ARRAY:
		var out: Array = []
		for s in (v as PackedStringArray): out.append(String(s))
		return out
	return []

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

func _label_for_id(pid: String, roster: Dictionary) -> String:
	if pid == "hero": return _safe_hero_name()
	if roster.has(pid):
		var rec: Dictionary = roster[pid]
		if rec.has("name") and typeof(rec["name"]) == TYPE_STRING and String(rec["name"]).strip_edges() != "":
			return String(rec["name"])
	return (pid.capitalize() if pid != "" else "")

func _gather_active_entries(roster: Dictionary) -> Array:
	var entries: Array = []

	# 1) GameState: ids (some projects expose this)
	if _gs and _gs.has_method("get_active_party_ids"):
		var v: Variant = _gs.call("get_active_party_ids")
		for s in _array_from_any(v):
			var pid := String(s)
			entries.append({"key": pid, "label": _label_for_id(pid, roster)})
		if entries.size() > 0: return entries

	# 2) GameState: get_active (ids)
	if _gs and _gs.has_method("get_active"):
		var v2: Variant = _gs.call("get_active")
		for s2 in _array_from_any(v2):
			var pid2 := String(s2)
			entries.append({"key": pid2, "label": _label_for_id(pid2, roster)})
		if entries.size() > 0: return entries

	# 3) GameState: names only
	if _gs and _gs.has_method("get_party_names"):
		var n_v: Variant = _gs.call("get_party_names")
		for n in _array_from_any(n_v):
			var nm := String(n)
			if nm.strip_edges() != "":
				entries.append({"key": "", "label": nm})
		if entries.size() > 0: return entries

	# 4) GameState: party property (ids)
	if _gs and _gs.has_method("get"):
		var p_v: Variant = _gs.get("party")
		for s3 in _array_from_any(p_v):
			var pid3 := String(s3)
			entries.append({"key": pid3, "label": _label_for_id(pid3, roster)})
		if entries.size() > 0: return entries

	# 5) PartySystem: common method names
	if _party_sys:
		for m in ["get_active_party","get_party","list_active_members","list_party","get_active"]:
			if _party_sys.has_method(m):
				var r: Variant = _party_sys.call(m)
				for s4 in _array_from_any(r):
					var pid4 := String(s4)
					entries.append({"key": pid4, "label": _label_for_id(pid4, roster)})
				if entries.size() > 0: return entries
		# properties
		for prop in ["active","party"]:
			if _party_sys.has_method("get"):
				var a_v: Variant = _party_sys.get(prop)
				for s5 in _array_from_any(a_v):
					var pid5 := String(s5)
					entries.append({"key": pid5, "label": _label_for_id(pid5, roster)})
				if entries.size() > 0: return entries

	# 6) Fallback: hero only
	entries.append({"key":"hero","label":_safe_hero_name()})
	return entries

# ---- Stat helpers ----------------------------------------------------

func _calc_max_hp(level: int, vtl: int) -> int:
	return 150 + (max(1, vtl) * max(1, level) * 6)

func _calc_max_mp(level: int, fcs: int) -> int:
	return 20 + int(round(1.5 * float(max(1, fcs)) * float(max(1, level))))

func _safe_hero_name() -> String:
	if _hero and _hero.has_method("get"):
		var v: Variant = _hero.get("hero_name")
		if typeof(v) == TYPE_STRING and String(v).strip_edges() != "":
			return String(v)
	return "Player"

func _safe_hero_level() -> int:
	if _hero and _hero.has_method("get"):
		var v: Variant = _hero.get("level")
		if typeof(v) in [TYPE_INT, TYPE_FLOAT]: return int(v)
	return 1
