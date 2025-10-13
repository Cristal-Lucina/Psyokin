extends Node
class_name StatsSystem

signal stat_leveled_up(stat_name: String, new_level: int)

# ─────────────────────────────────────────────────────────────────────────────
# HERO (original behavior — unchanged)
# ─────────────────────────────────────────────────────────────────────────────
var stat_sxp: Dictionary   = {"FCS": 0, "MND": 0, "TPO": 0, "BRW": 0, "VTL": 0}
var stat_level: Dictionary = {"FCS": 1, "MND": 1, "TPO": 1, "BRW": 1, "VTL": 1}
var weekly_actions: Dictionary = {"FCS": 0, "MND": 0, "TPO": 0, "BRW": 0, "VTL": 0}
var _csv_loaded_once: bool = false
# CUMULATIVE thresholds to be AT each level (L1..L11).
var sxp_thresholds: Array[int] = [0, 59, 122, 189, 260, 336, 416, 500, 588, 680, 943]

func get_stats_dict() -> Dictionary:
	return {
		"BRW": int(stat_level.get("BRW", 1)),
		"VTL": int(stat_level.get("VTL", 1)),
		"TPO": int(stat_level.get("TPO", 1)),
		"FCS": int(stat_level.get("FCS", 1)),
		"MND": int(stat_level.get("MND", 1)),
	}

func get_stat(stat: String) -> int:
	return int(stat_level.get(stat, 1))

func get_stat_sxp(stat: String) -> int:
	return int(stat_sxp.get(stat, 0))

func get_weekly_actions_dict() -> Dictionary:
	return weekly_actions.duplicate()

func add_sxp(stat: String, base_amount: int) -> int:
	if not stat_sxp.has(stat):
		push_error("StatsSystem: unknown stat '%s'" % stat)
		return 0

	var action_count: int = int(weekly_actions.get(stat, 0))
	var gain: int = base_amount
	if action_count >= 7:
		gain = int(floor(float(base_amount) * 0.5))
	if gain < 1:
		gain = 1

	weekly_actions[stat] = action_count + 1
	stat_sxp[stat] = int(stat_sxp.get(stat, 0)) + gain

	var level: int = int(stat_level.get(stat, 1))
	while level <= sxp_thresholds.size() and int(stat_sxp[stat]) >= sxp_thresholds[level - 1]:
		level += 1
		stat_level[stat] = level
		emit_signal("stat_leveled_up", stat, level)

	return gain

func reset_week() -> void:
	for key in weekly_actions.keys():
		weekly_actions[key] = 0

func add_sxp_bulk(gains: Dictionary) -> void:
	for k in gains.keys():
		add_sxp(String(k), int(gains[k]))

func set_thresholds(new_thresholds: Array) -> void:
	var cleaned: Array[int] = []
	for v in new_thresholds:
		cleaned.append(int(v))
	sxp_thresholds = cleaned

func apply_creation_boosts(picks: Array) -> void:
	for p in picks:
		var k := String(p)
		if k == "": continue
		var cur := int(stat_level.get(k, 1))
		stat_level[k] = max(1, cur + 1)

# ---- Save module API (hero + party DSI progress) -----------------------------
func get_save_blob() -> Dictionary:
	return {
		"levels": stat_level.duplicate(true),
		"xp":      stat_sxp.duplicate(true),
		"weekly":  weekly_actions.duplicate(true),
		"party_dsi": _party_progress.duplicate(true)
	}

func apply_save_blob(blob: Dictionary) -> void:
	var lv_v: Variant = blob.get("levels", {})
	if typeof(lv_v) == TYPE_DICTIONARY:
		for k in (lv_v as Dictionary).keys():
			stat_level[String(k)] = int((lv_v as Dictionary)[k])

	var xp_v: Variant = blob.get("xp", {})
	if typeof(xp_v) == TYPE_DICTIONARY:
		for k in (xp_v as Dictionary).keys():
			stat_sxp[String(k)] = int((xp_v as Dictionary)[k])

	var w_v: Variant = blob.get("weekly", {})
	if typeof(w_v) == TYPE_DICTIONARY:
		for k in (w_v as Dictionary).keys():
			weekly_actions[String(k)] = int((w_v as Dictionary)[k])

	var pd_v: Variant = blob.get("party_dsi", {})
	if typeof(pd_v) == TYPE_DICTIONARY:
		_party_progress = (pd_v as Dictionary).duplicate(true)

func clear_all() -> void:
	reset_week()
	for k in ["FCS","MND","TPO","BRW","VTL"]:
		stat_level[k] = 1
		stat_sxp[k] = 0
	_party_progress.clear()

func compute_max_hp(level: int, vtl: int) -> int:
	return 150 + (max(1, vtl) * max(1, level) * 6)

func compute_max_mp(level: int, fcs: int) -> int:
	return 20 + int(round(float(max(1, fcs)) * float(max(1, level)) * 1.5))

# ─────────────────────────────────────────────────────────────────────────────
# PARTY DSI (NEW): daily stat drip for NON-hero members driven by calendar
# ─────────────────────────────────────────────────────────────────────────────

# Toggle this if you want per-day, per-stat prints in Output (debug only)
var DSI_VERBOSE: bool = true

const CAL_PATH    := "/root/aCalendarSystem"
const PARTY_PATH  := "/root/aPartySystem"
const GS_PATH     := "/root/aGameState"
const HERO_PATH   := "/root/aHeroSystem"
const CSV_PATH    := "/root/aCSVLoader"
const PARTY_CSV   := "res://data/actors/party.csv"

const STATS_KEYS := ["BRW","MND","TPO","VTL","FCS"]
const DSI_DEFAULT_TENTHS := { "BRW":10, "MND":20, "TPO":30, "VTL":10, "FCS":30 }

var _cal: Node = null
var _party: Node = null
var _gs: Node = null
var _hero: Node = null
var _csv: Node = null

var _csv_by_id  : Dictionary = {}
var _name_to_id : Dictionary = {}

# id -> { label, char_level, start{}, sxp{}, tenths{}, dsi_tenths{} }
var _party_progress : Dictionary = {}

func _ready() -> void:
	_cal   = get_node_or_null(CAL_PATH)
	_party = get_node_or_null(PARTY_PATH)
	_gs    = get_node_or_null(GS_PATH)
	_hero  = get_node_or_null(HERO_PATH); if _hero == null: _hero = get_node_or_null("/root/HeroSystem")
	_csv   = get_node_or_null(CSV_PATH)

	_load_party_csv_cache()
	_seed_known_members()

	if _cal and _cal.has_signal("day_advanced"):
		_cal.connect("day_advanced", Callable(self, "_on_day_advanced"))

	for src in [_gs, _party]:
		if src == null: continue
		for sig in ["party_changed","active_changed","roster_changed","changed"]:
			if src.has_signal(sig):
				src.connect(sig, Callable(self, "_on_party_changed"))

# Calendar / Party
func _on_day_advanced(_date_dict: Dictionary) -> void:
	# ensure members exist (if roster changed today)
	_seed_known_members()
	var ids: Array = _active_party_ids()
	for id_any in ids:
		var pid: String = String(id_any)
		if pid == "hero": continue
		_apply_daily_dsi(pid)

	if DSI_VERBOSE and OS.is_debug_build():
		debug_dump_party_dsi_progress()

func _on_party_changed(_a: Variant = null) -> void:
	_seed_known_members()

# Public
func get_member_stat_level(member: String, stat: String) -> int:
	var pid: String = _resolve_id(member)
	if pid == "hero":
		return int(stat_level.get(stat, 1))
	var info: Dictionary = _ensure_progress(pid)
	return _csv_start_level(pid, stat) + _bonus_levels_from_sxp(int(info["sxp"][stat]))

func get_party_snapshots() -> Array:
	var out: Array = []
	var ids: Array = _active_party_ids()
	for id_any in ids:
		var pid: String = String(id_any)
		if pid == "hero":
			var cl: int = _hero_get_int("level", 1)
			var vtl_h: int = get_stat("VTL")
			var fcs_h: int = get_stat("FCS")
			out.append({
				"name": "%s  (Lv %d)" % [_safe_hero_name(), cl],
				"hp_max": compute_max_hp(cl, vtl_h),
				"mp_max": compute_max_mp(cl, fcs_h)
			})
			continue
		var info: Dictionary = _ensure_progress(pid)
		var clvl: int = int(info["char_level"])
		var vtl: int = _csv_start_level(pid, "VTL") + _bonus_levels_from_sxp(int(info["sxp"]["VTL"]))
		var fcs: int = _csv_start_level(pid, "FCS") + _bonus_levels_from_sxp(int(info["sxp"]["FCS"]))
		out.append({
			"name": "%s  (Lv %d)" % [String(info["label"]), clvl],
			"hp_max": compute_max_hp(clvl, vtl),
			"mp_max": compute_max_mp(clvl, fcs)
		})
	return out

func debug_dump_party_dsi_progress() -> void:
	print_rich("[b]=== Party DSI Progress ===[/b]")
	var ids: Array = _active_party_ids()
	if ids.is_empty():
		print("No active party.")
		return
	for id_any in ids:
		var pid: String = String(id_any)
		if pid == "hero":
			var cl: int = _hero_get_int("level", 1)
			print("%s | Lv %d | HERO BRW %d MND %d TPO %d VTL %d FCS %d" % [
				_safe_hero_name(), cl,
				get_stat("BRW"), get_stat("MND"), get_stat("TPO"), get_stat("VTL"), get_stat("FCS")
			])
			continue
		var info: Dictionary = _ensure_progress(pid)
		var brw: int = _csv_start_level(pid,"BRW") + _bonus_levels_from_sxp(int(info["sxp"]["BRW"]))
		var mnd: int = _csv_start_level(pid,"MND") + _bonus_levels_from_sxp(int(info["sxp"]["MND"]))
		var tpo: int = _csv_start_level(pid,"TPO") + _bonus_levels_from_sxp(int(info["sxp"]["TPO"]))
		var vtl: int = _csv_start_level(pid,"VTL") + _bonus_levels_from_sxp(int(info["sxp"]["VTL"]))
		var fcs: int = _csv_start_level(pid,"FCS") + _bonus_levels_from_sxp(int(info["sxp"]["FCS"]))
		print("%s | Lv %d | BRW %d MND %d TPO %d VTL %d FCS %d | SXP=%s | tenths=%s" % [
			String(info["label"]), int(info["char_level"]), brw, mnd, tpo, vtl, fcs,
			str(info["sxp"]), str(info["tenths"])
		])

# Internals
func _apply_daily_dsi(pid: String) -> void:
	var info: Dictionary = _ensure_progress(pid)
	var dsi: Dictionary = info["dsi_tenths"]
	for s in STATS_KEYS:
		var key: String = String(s)
		var before_t: int = int(info["tenths"][key])
		var add_t: int    = int(dsi.get(key, 0))
		var t: int        = before_t + add_t
		var gain_whole: int = floori(float(t) / 10.0)
		var remainder: int  = t - gain_whole * 10
		info["tenths"][key] = remainder
		if gain_whole > 0:
			info["sxp"][key] = int(info["sxp"][key]) + gain_whole
		if DSI_VERBOSE and OS.is_debug_build():
			print("DSI %s: +%d tenths (%d→%d) => +%d SXP (total %d), rem %d" % [
				key, add_t, before_t, t, gain_whole, int(info["sxp"][key]), remainder
			])

func _seed_known_members() -> void:
	var ids: Array = _active_party_ids()
	for id_any in ids:
		var pid: String = String(id_any)
		if pid == "hero": continue
		_ensure_progress(pid)

func _ensure_progress(pid: String) -> Dictionary:
	if _party_progress.has(pid):
		return _party_progress[pid]

	var row: Dictionary = _csv_by_id.get(pid, {}) as Dictionary
	var label: String = (String(row.get("name", "")) if not row.is_empty() else pid.capitalize())
	var clvl: int = _to_int(row.get("level_start", 1)) if not row.is_empty() else 1

	var start: Dictionary = (
		{
			"BRW": _to_int(row.get("start_brw", 1)),
			"MND": _to_int(row.get("start_mnd", 1)),
			"TPO": _to_int(row.get("start_tpo", 1)),
			"VTL": _to_int(row.get("start_vtl", 1)),
			"FCS": _to_int(row.get("start_fcs", 1)),
		} if not row.is_empty() else {"BRW":1,"MND":1,"TPO":1,"VTL":1,"FCS":1}
	)

	var dsi: Dictionary = (
		_read_dsi_tenths_from_row(row) if not row.is_empty() else DSI_DEFAULT_TENTHS.duplicate()
	) as Dictionary

	_party_progress[pid] = {
		"label": label,
		"char_level": max(1, clvl),
		"start": start,
		"sxp": {"BRW":0,"MND":0,"TPO":0,"VTL":0,"FCS":0},
		"tenths": {"BRW":0,"MND":0,"TPO":0,"VTL":0,"FCS":0},
		"dsi_tenths": dsi
	}
	return _party_progress[pid]

func _read_dsi_tenths_from_row(row: Dictionary) -> Dictionary:
	var out: Dictionary = {"BRW":0,"MND":0,"TPO":0,"VTL":0,"FCS":0}
	var keys: Dictionary = {"BRW":"dsi_brw","MND":"dsi_mnd","TPO":"dsi_tpo","VTL":"dsi_vtl","FCS":"dsi_fcs"}
	var any_found: bool = false
	for k in keys.keys():
		var csv_key: String = String(keys[k])
		if row.has(csv_key):
			any_found = true
			out[k] = _to_tenths(row[csv_key])  # supports "0.4" etc.
	if not any_found:
		return DSI_DEFAULT_TENTHS.duplicate()
	return out

func _bonus_levels_from_sxp(sxp: int) -> int:
	for i in range(sxp_thresholds.size() - 1, -1, -1):
		if sxp >= sxp_thresholds[i]:
			return i
	return 0

# CSV (load once; stops spam in Output)
func _load_party_csv_cache() -> void:
	if _csv_loaded_once:
		return

	_csv_by_id.clear()
	_name_to_id.clear()

	if _csv and _csv.has_method("load_csv"):
		var defs_v: Variant = _csv.call("load_csv", PARTY_CSV, "actor_id")
		if typeof(defs_v) == TYPE_DICTIONARY:
			var defs: Dictionary = defs_v
			for id_any in defs.keys():
				var rid := String(id_any)
				var row: Dictionary = defs[rid]
				_csv_by_id[rid] = row
				var n_v: Variant = row.get("name", "")
				if typeof(n_v) == TYPE_STRING:
					var key := String(n_v).strip_edges().to_lower()
					if key != "":
						_name_to_id[key] = rid
			_csv_loaded_once = true


# Roster
func _active_party_ids() -> Array:
	if _party:
		for m in ["get_active_party","get_party","list_active_members","list_party","get_active"]:
			if _party.has_method(m):
				var v: Variant = _party.call(m)
				var arr: Array = _array_from_any(v)
				if not arr.is_empty(): return arr
		for prop in ["active","party"]:
			if _party.has_method("get"):
				var pv: Variant = _party.get(prop)
				var arr2: Array = _array_from_any(pv)
				if not arr2.is_empty(): return arr2
	if _gs:
		if _gs.has_method("get_active_party_ids"):
			var v3: Variant = _gs.call("get_active_party_ids")
			var arr3: Array = _array_from_any(v3)
			if not arr3.is_empty(): return arr3
		if _gs.has_method("get"):
			var p_v: Variant = _gs.get("party")
			var arr4: Array = _array_from_any(p_v)
			if not arr4.is_empty(): return arr4
	return ["hero"]

func _resolve_id(name_or_id: String) -> String:
	if name_or_id == "hero": return "hero"
	if _csv_by_id.has(name_or_id): return name_or_id
	var key: String = name_or_id.strip_edges().to_lower()
	if _name_to_id.has(key): return String(_name_to_id[key])
	return name_or_id

# Utils
func _array_from_any(v: Variant) -> Array:
	if typeof(v) == TYPE_ARRAY: return v as Array
	if typeof(v) == TYPE_PACKED_STRING_ARRAY:
		var out: Array = []
		for s in (v as PackedStringArray): out.append(String(s))
		return out
	return []

func _to_int(v: Variant) -> int:
	match typeof(v):
		TYPE_INT: return int(v)
		TYPE_FLOAT: return int(floor(float(v)))
		TYPE_STRING:
			var s: String = String(v).strip_edges()
			if s == "": return 0
			return int(s.to_int())
		_: return 0

func _to_float(v: Variant) -> float:
	match typeof(v):
		TYPE_INT: return float(int(v))
		TYPE_FLOAT: return float(v)
		TYPE_STRING:
			var s: String = String(v).strip_edges()
			if s == "": return 0.0
			return float(s.to_float())
		_: return 0.0

func _to_tenths(v: Variant) -> int:
	var f: float = max(0.0, _to_float(v))
	return int(round(f * 10.0))

func _csv_start_level(pid: String, stat: String) -> int:
	var row: Dictionary = _csv_by_id.get(pid, {}) as Dictionary
	if row.is_empty(): return 1
	match stat:
		"BRW": return max(1, _to_int(row.get("start_brw", 1)))
		"MND": return max(1, _to_int(row.get("start_mnd", 1)))
		"TPO": return max(1, _to_int(row.get("start_tpo", 1)))
		"VTL": return max(1, _to_int(row.get("start_vtl", 1)))
		"FCS": return max(1, _to_int(row.get("start_fcs", 1)))
		_: return 1

func _safe_hero_name() -> String:
	if _hero and _hero.has_method("get"):
		var v: Variant = _hero.get("hero_name")
		if typeof(v) == TYPE_STRING and String(v).strip_edges() != "":
			return String(v)
	return "Player"

func _hero_get_int(prop: String, def: int) -> int:
	if _hero and _hero.has_method("get"):
		var v: Variant = _hero.get(prop)
		if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
			return int(v)
	return def
