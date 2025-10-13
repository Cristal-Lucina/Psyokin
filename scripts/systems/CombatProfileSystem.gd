extends Node
class_name CombatProfileSystem

# Paths
const STATS_PATH    := "/root/aStatsSystem"
const PARTY_PATH    := "/root/aPartySystem"
const GS_PATH       := "/root/aGameState"
const HERO_PATH     := "/root/aHeroSystem"
const CSV_PATH      := "/root/aCSVLoader"
const CAL_PATH      := "/root/aCalendarSystem"
const PARTY_CSV     := "res://data/actors/party.csv"

# Cached nodes
var _st: Node = null
var _party: Node = null
var _gs: Node = null
var _hero: Node = null
var _csv: Node = null
var _cal: Node = null

# CSV caches
var _csv_by_id  : Dictionary = {}   # id -> row
var _name_to_id : Dictionary = {}   # lower(name) -> id

func _ready() -> void:
	_st    = get_node_or_null(STATS_PATH)
	_party = get_node_or_null(PARTY_PATH)
	_gs    = get_node_or_null(GS_PATH)
	_hero  = get_node_or_null(HERO_PATH); if _hero == null: _hero = get_node_or_null("/root/HeroSystem")
	_csv   = get_node_or_null(CSV_PATH)
	_cal   = get_node_or_null(CAL_PATH)

	_load_party_csv_cache()

	# keep things fresh
	for src in [_gs, _party]:
		if src == null: continue
		for sig in ["party_changed","active_changed","roster_changed","changed"]:
			if src.has_signal(sig):
				src.connect(sig, Callable(self, "_on_roster_changed"))
	if _cal and _cal.has_signal("day_advanced"):
		_cal.connect("day_advanced", Callable(self, "_on_day"))

func _on_roster_changed(_v: Variant = null) -> void:
	_load_party_csv_cache()

func _on_day(_date: Variant = null) -> void:
	# optional: auto-dump each day tick during debug runs
	if OS.is_debug_build():
		debug_dump_active_party()

# ──────────────────────────────────────────────────────────────────────────────
# Public dev helper — prints to Output panel
# ──────────────────────────────────────────────────────────────────────────────
func debug_dump_active_party() -> void:
	print_rich("[b]=== Combat Profiles ===[/b]")
	var ids: Array = _active_party_ids()
	if ids.is_empty():
		print("No profiles available")
		return

	for id_any in ids:
		var member_id: String = String(id_any)
		var label: String = _label_for(member_id)

		var char_level: int = _char_level_for(member_id)
		var brw: int = _stat_level_for(member_id, "BRW")
		var mnd: int = _stat_level_for(member_id, "MND")
		var tpo: int = _stat_level_for(member_id, "TPO")
		var vtl: int = _stat_level_for(member_id, "VTL")
		var fcs: int = _stat_level_for(member_id, "FCS")

		var hp_max: int = _hp_max_for(member_id, char_level, vtl)
		var mp_max: int = _mp_max_for(member_id, char_level, fcs)
		var mind_txt: String = _mind_for(member_id)

		print("%s | Lv %d | BRW %d  MND %d  TPO %d  VTL %d  FCS %d | HPmax %d  MPmax %d | Mind %s" % [
			label, char_level, brw, mnd, tpo, vtl, fcs, hp_max, mp_max, mind_txt
		])

# ───────────────────────── helpers ─────────────────────────

func _active_party_ids() -> Array:
	# Try PartySystem first
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
	# GameState fallbacks
	if _gs:
		if _gs.has_method("get_active_party_ids"):
			var v3: Variant = _gs.call("get_active_party_ids")
			var arr3: Array = _array_from_any(v3)
			if not arr3.is_empty(): return arr3
		if _gs.has_method("get"):
			var p_v: Variant = _gs.get("party")
			var arr4: Array = _array_from_any(p_v)
			if not arr4.is_empty(): return arr4
	# Last resort: hero
	return ["hero"]

func _label_for(member_id: String) -> String:
	if member_id == "hero":
		return _safe_hero_name()
	if _csv_by_id.has(member_id):
		var row: Dictionary = _csv_by_id[member_id]
		var n_v: Variant = row.get("name", "")
		if typeof(n_v) == TYPE_STRING and String(n_v).strip_edges() != "":
			return String(n_v)
	return member_id.capitalize()

func _char_level_for(member_id: String) -> int:
	if member_id == "hero":
		return _hero_get_int("level", 1)
	if _csv_by_id.has(member_id):
		return _to_int((_csv_by_id[member_id] as Dictionary).get("level_start", 1))
	return 1

func _stat_level_for(member_id: String, stat: String) -> int:
	# Prefer StatsSystem DSI API if present (so you see live drip)
	if _st and _st.has_method("get_member_stat_level") and member_id != "hero":
		var v: Variant = _st.call("get_member_stat_level", member_id, stat)
		if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
			return int(v)

	# Hero → live hero stat level
	if member_id == "hero" and _st:
		var hv: Variant = _st.call("get_stat", stat)
		if typeof(hv) in [TYPE_INT, TYPE_FLOAT]:
			return int(hv)
		return 1

	# Fallback to CSV starting levels
	if _csv_by_id.has(member_id):
		var row: Dictionary = _csv_by_id[member_id]
		match stat:
			"BRW": return max(1, _to_int(row.get("start_brw", 1)))
			"MND": return max(1, _to_int(row.get("start_mnd", 1)))
			"TPO": return max(1, _to_int(row.get("start_tpo", 1)))
			"VTL": return max(1, _to_int(row.get("start_vtl", 1)))
			"FCS": return max(1, _to_int(row.get("start_fcs", 1)))
			_:     return 1
	return 1

func _hp_max_for(_member_id: String, char_level: int, vtl: int) -> int:
	if _st and _st.has_method("compute_max_hp"):
		return _st.call("compute_max_hp", char_level, vtl)
	# fallback mirrors your formula
	return 150 + (max(1, vtl) * max(1, char_level) * 6)

func _mp_max_for(_member_id: String, char_level: int, fcs: int) -> int:
	if _st and _st.has_method("compute_max_mp"):
		return _st.call("compute_max_mp", char_level, fcs)
	return 20 + int(round(float(max(1, fcs)) * float(max(1, char_level)) * 1.5))

func _mind_for(member_id: String) -> String:
	if member_id == "hero":
		# If hero has a field for mind/school, adapt here.
		if _hero and _hero.has_method("get"):
			var m_v: Variant = _hero.get("school_track")
			if typeof(m_v) == TYPE_STRING and String(m_v).strip_edges() != "":
				return String(m_v)
		return "—"
	if _csv_by_id.has(member_id):
		var row: Dictionary = _csv_by_id[member_id]
		var mv: Variant = row.get("mind_type", "")
		if typeof(mv) == TYPE_STRING and String(mv).strip_edges() != "":
			return String(mv)
	return "—"

# CSV cache
func _load_party_csv_cache() -> void:
	_csv_by_id.clear()
	_name_to_id.clear()
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

# Small utils
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
