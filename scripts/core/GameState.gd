extends Node
class_name GameState

signal party_changed

var player_name: String = "Player"
var difficulty: String = "Normal"
var money: int = 0
var perk_points: int = 0
var pacifist_score: int = 0
var bloodlust_score: int = 0
var inventory: Dictionary = {}
var party: Array[String] = []
var bench: Array[String] = []
var flags: Dictionary = {}

var index_blob: Dictionary = {
	"tutorials": [],
	"enemies":   {},
	"locations": {},
	"lore":      {},
}

const CALENDAR_PATH := "/root/aCalendarSystem"
const STATS_PATH    := "/root/aStatsSystem"
const SAVELOAD_PATH := "/root/aSaveLoad"
const PERK_PATH     := "/root/aPerkSystem"
const CSV_PATH      := "/root/aCSVLoader"            # used for id<->name lookups
const PARTY_CSV     := "res://data/actors/party.csv" # your Party.csv

const SAVE_MODULES: Array = [
	{"id":"perks",    "path": PERK_PATH,                 "export":"get_save_blob", "import":"apply_save_blob", "reset":"clear_all"},
	{"id":"hero",     "path": "/root/aHeroSystem",       "export":"get_save_blob", "import":"apply_save_blob", "reset":"clear_all"},
	{"id":"stats",    "path": "/root/aStatsSystem",      "export":"get_save_blob", "import":"apply_save_blob", "reset":"clear_all"},
	{"id":"inventory","path": "/root/aInventorySystem",  "export":"get_save_blob", "import":"apply_save_blob", "reset":"clear_all"},
	{"id":"equipment","path": "/root/aEquipmentSystem",  "export":"get_save_blob", "import":"apply_save_blob", "reset":"clear_all"},
	{"id":"party",    "path": "/root/aPartySystem",      "export":"get_save_blob", "import":"apply_save_blob", "reset":"clear_all"},
	{"id":"effects",  "path": "/root/aStatusEffects",    "export":"get_save_blob", "import":"apply_save_blob", "reset":"clear_all"},
	{"id":"sigils",   "path": "/root/aSigilSystem",      "export":"get_save_blob", "import":"apply_save_blob", "reset":"clear_all"},
	{"id":"school",   "path": "/root/aSchoolSystem",     "export":"get_save_blob", "import":"apply_save_blob", "reset":"clear_all"},
	{"id":"bonds",    "path": "/root/aCircleBondSystem", "export":"get_save_blob", "import":"apply_save_blob", "reset":"clear_all"},
	{"id":"events",   "path": "/root/aMainEventSystem",  "export":"get_save_blob", "import":"apply_save_blob", "reset":"clear_all"},
	{"id":"dorms",    "path": "/root/aDormSystem",       "export":"get_save_blob", "import":"apply_save_blob", "reset":"clear_all"},
	{"id":"affinity", "path": "/root/aAffinitySystem",   "export":"get_save_blob", "import":"apply_save_blob", "reset":"clear_all"},
	{"id":"outreach", "path": "/root/aOutreachSystem",   "export":"get_save_blob", "import":"apply_save_blob", "reset":"clear_all"},
]

func new_game() -> void:
	player_name = "Player"
	difficulty = "Normal"
	money = 500
	perk_points = 3
	pacifist_score = 0
	bloodlust_score = 0
	inventory = {}
	party = ["hero"]
	bench = []
	flags = {}

	# Initialize hero active type default so UI/Combat have a value from the start.
	self.set_meta("hero_active_type", "Omega")

	index_blob = {
		"tutorials": [],
		"enemies":   {},
		"locations": {},
		"lore":      {},
	}

	var cal: Node = get_node_or_null(CALENDAR_PATH)
	if cal:
		cal.current_date = {"year": 2025, "month": 5, "day": 5}
		cal.current_phase = 0
		cal.current_weekday = 0
		if cal.has_signal("day_advanced"):   cal.emit_signal("day_advanced", cal.current_date)
		if cal.has_signal("phase_advanced"): cal.emit_signal("phase_advanced", cal.current_phase)

	var stats: Node = get_node_or_null(STATS_PATH)
	if stats and stats.has_method("reset_week"):
		stats.reset_week()

	_reset_modules_for_new_game()
	emit_signal("party_changed")

func save_to_slot(slot: int) -> bool:
	var saver: SaveLoad = get_node_or_null(SAVELOAD_PATH) as SaveLoad
	if saver == null:
		push_error("GameState: aSaveLoad not found.")
		return false
	return saver.save_game(slot, _to_payload())

func load_from_slot(slot: int) -> bool:
	var loader: SaveLoad = get_node_or_null(SAVELOAD_PATH) as SaveLoad
	if loader == null:
		push_error("GameState: aSaveLoad not found.")
		return false
	var payload: Dictionary = loader.load_game(slot)
	if payload.is_empty():
		return false
	_from_payload(payload)
	return true

func apply_loaded_save(payload: Dictionary) -> void:
	if payload.is_empty():
		return
	_from_payload(payload)

func add_flag(key: String, value: Variant = true) -> void:
	flags[key] = value

func get_flag(key: String, default: Variant = null) -> Variant:
	return flags.get(key, default)

func index_add_tutorial(id: String, title: String, text: String) -> void:
	var arr: Array = index_blob.get("tutorials", [])
	var found := false
	for i in range(arr.size()):
		var it_v: Variant = arr[i]
		if typeof(it_v) == TYPE_DICTIONARY and String((it_v as Dictionary).get("id","")) == id:
			found = true
			break
	if not found:
		arr.append({"id": id, "title": title, "text": text, "seen": true})
	index_blob["tutorials"] = arr

func index_tag_enemy_seen(id: String, enemy_name: String, drops: Array = [], weaknesses: Array = []) -> void:
	var d: Dictionary = index_blob.get("enemies", {}) as Dictionary
	var cur_v: Variant = d.get(id, {})
	var cur: Dictionary = (cur_v as Dictionary) if typeof(cur_v) == TYPE_DICTIONARY else {}
	cur["name"] = enemy_name
	if typeof(drops) == TYPE_ARRAY:       cur["drops"] = drops.duplicate()
	if typeof(weaknesses) == TYPE_ARRAY:  cur["weaknesses"] = weaknesses.duplicate()
	cur["seen"] = true
	d[id] = cur
	index_blob["enemies"] = d

func index_tag_location_seen(id: String, location_name: String) -> void:
	var d: Dictionary = index_blob.get("locations", {}) as Dictionary
	var cur_v: Variant = d.get(id, {})
	var cur: Dictionary = (cur_v as Dictionary) if typeof(cur_v) == TYPE_DICTIONARY else {}
	cur["name"] = location_name
	cur["seen"]  = true
	d[id] = cur
	index_blob["locations"] = d

func index_add_lore(id: String, title: String, text: String) -> void:
	var d: Dictionary = index_blob.get("lore", {}) as Dictionary
	d[id] = {"title": title, "text": text, "seen": true}
	index_blob["lore"] = d

func get_index_blob() -> Dictionary:
	return index_blob.duplicate(true)

func apply_index_blob(blob: Dictionary) -> void:
	var out: Dictionary = {"tutorials": [], "enemies": {}, "locations": {}, "lore": {}}
	var t_v: Variant = blob.get("tutorials", [])
	if typeof(t_v) == TYPE_ARRAY: out["tutorials"] = (t_v as Array).duplicate(true)
	var e_v: Variant = blob.get("enemies", {})
	if typeof(e_v) == TYPE_DICTIONARY: out["enemies"] = (e_v as Dictionary).duplicate(true)
	var l_v: Variant = blob.get("locations", {})
	if typeof(l_v) == TYPE_DICTIONARY: out["locations"] = (l_v as Dictionary).duplicate(true)
	var w_v: Variant = blob.get("lore", {})
	if typeof(w_v) == TYPE_DICTIONARY: out["lore"] = (w_v as Dictionary).duplicate(true)
	index_blob = out

# ─────────────────────── BRIDGES FOR PARTY UI ───────────────────────

func get_party_names() -> PackedStringArray:
	var ids: Array[String] = _active_party_ids()
	var out: PackedStringArray = PackedStringArray()
	for id in ids:
		out.append(_display_name_for_id(String(id)))
	return out

func get_member_equip(member: String) -> Dictionary:
	var eq := get_node_or_null("/root/aEquipmentSystem")
	if eq == null or not eq.has_method("get_member_equip"):
		return {}
	var d1: Variant = eq.call("get_member_equip", member)
	if typeof(d1) == TYPE_DICTIONARY:
		return d1 as Dictionary
	var mid := _resolve_member_id(member)
	if mid != member:
		var d2: Variant = eq.call("get_member_equip", mid)
		if typeof(d2) == TYPE_DICTIONARY:
			return d2 as Dictionary
	return {}

func _active_party_ids() -> Array[String]:
	var out: Array[String] = []
	var ps := get_node_or_null("/root/aPartySystem")
	if ps:
		for m in ["get_active_party", "get_party", "list_active_members", "list_party"]:
			if ps.has_method(m):
				var v: Variant = ps.call(m)
				if typeof(v) == TYPE_ARRAY:
					for s in (v as Array): out.append(String(s))
				elif typeof(v) == TYPE_PACKED_STRING_ARRAY:
					for s2 in (v as PackedStringArray): out.append(String(s2))
				if not out.is_empty(): return out
	for s3 in party: out.append(s3)
	if out.is_empty(): out.append("hero")
	return out

func _display_name_for_id(id: String) -> String:
	# Hero uses the runtime hero_name if set
	if id == "hero":
		var hs := get_node_or_null("/root/aHeroSystem")
		if hs:
			var nm: Variant = hs.get("hero_name")   # safe even if missing
			if typeof(nm) == TYPE_STRING and String(nm) != "":
				return String(nm)
	# PartySystem can provide a display name
	var ps := get_node_or_null("/root/aPartySystem")
	if ps:
		for m in ["get_display_name_for", "get_name_for", "name_for"]:
			if ps.has_method(m):
				var v: Variant = ps.call(m, id)
				if typeof(v) == TYPE_STRING and String(v) != "":
					return String(v)
	# CSV lookup fallback
	var csv := get_node_or_null(CSV_PATH)
	if csv and csv.has_method("load_csv"):
		var defs_v: Variant = csv.call("load_csv", PARTY_CSV, "actor_id")
		if typeof(defs_v) == TYPE_DICTIONARY:
			var defs: Dictionary = defs_v
			if defs.has(id):
				var row: Dictionary = defs[id]
				var nm2 := String(row.get("name",""))
				if nm2 != "": return nm2
	return id.capitalize()

func _resolve_member_id(name_in: String) -> String:
	var hs := get_node_or_null("/root/aHeroSystem")
	if hs:
		var hv: Variant = hs.get("hero_name")  # safe even if not defined
		if typeof(hv) == TYPE_STRING and String(hv).to_lower() == name_in.to_lower():
			return "hero"
	var ps := get_node_or_null("/root/aPartySystem")
	if ps:
		for m in ["id_for_name", "get_id_for_name", "resolve_id_for_name"]:
			if ps.has_method(m):
				var v: Variant = ps.call(m, name_in)
				if typeof(v) == TYPE_STRING and String(v) != "":
					return String(v)
	var csv := get_node_or_null(CSV_PATH)
	if csv and csv.has_method("load_csv"):
		var defs_v: Variant = csv.call("load_csv", PARTY_CSV, "actor_id")
		if typeof(defs_v) == TYPE_DICTIONARY:
			var defs: Dictionary = defs_v
			for id_any in defs.keys():
				var row: Dictionary = defs[id_any]
				if String(row.get("name","")).to_lower() == name_in.to_lower():
					return String(id_any)
	return name_in

# ────────────────────────────────────────────────────────────────────
# ---- Party CSV helpers (cache) -----------------------------------------------
var _party_defs_cached: Dictionary = {}   # actor_id -> row dict
const PARTY_NAME_KEYS := ["name","display_name","disp_name","character","alias"]

func _ensure_party_defs() -> void:
	if not _party_defs_cached.is_empty():
		return
	var csv := get_node_or_null(CSV_PATH)
	if csv and csv.has_method("load_csv"):
		var v: Variant = csv.call("load_csv", PARTY_CSV, "actor_id")
		if typeof(v) == TYPE_DICTIONARY:
			_party_defs_cached = (v as Dictionary)

func _row_for_member(member: String) -> Dictionary:
	_ensure_party_defs()
	if _party_defs_cached.is_empty():
		return {}
	# Prefer id lookup
	var id := _resolve_member_id(member)
	if _party_defs_cached.has(id):
		return _party_defs_cached[id]
	# Fallback: match by name-ish column
	var want := member.strip_edges().to_lower()
	for aid in _party_defs_cached.keys():
		var row: Dictionary = _party_defs_cached[aid]
		for k in PARTY_NAME_KEYS:
			if row.has(k) and typeof(row[k]) == TYPE_STRING:
				if String(row[k]).strip_edges().to_lower() == want:
					return row
	return {}

# ---- Public getters the Party UI can use -------------------------------------

func get_member_level(member: String) -> int:
	# Hero: live level
	if member == "hero" or _display_name_for_id("hero").to_lower() == member.to_lower():
		var hs := get_node_or_null("/root/aHeroSystem")
		return int(hs.get("level")) if hs else 1

	# Others: try CSV fields
	var row := _row_for_member(member)
	for k in ["level","lvl","lv"]:
		if row.has(k) and typeof(row[k]) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			return int(row[k])
	return 1

func get_member_stat(member: String, stat: String) -> int:
	# Hero: live stats from StatsSystem
	if member == "hero" or _display_name_for_id("hero").to_lower() == member.to_lower():
		var stats := get_node_or_null(STATS_PATH)
		if stats and stats.has_method("get_stat"):
			return int(stats.call("get_stat", stat))
		return 1

	# Others: CSV columns (e.g., VTL, FCS, stat_vtl, vtl_level, etc.)
	var row := _row_for_member(member)
	var cand := [
		stat, stat + "_level",
		stat.to_lower(), stat.to_lower() + "_level",
		"stat_" + stat, "stat_" + stat.to_lower()
	]
	for k in cand:
		if row.has(k) and typeof(row[k]) in [TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			return int(row[k])
	return 1

func compute_member_pools(member: String) -> Dictionary:
	var lvl := get_member_level(member)
	var vtl := get_member_stat(member, "VTL")
	var fcs := get_member_stat(member, "FCS")

	var stats := get_node_or_null(STATS_PATH)
	var hp_max := 150 + (vtl * lvl * 6)
	var mp_max := 20 + int(round(float(fcs) * float(lvl) * 1.5))
	if stats and stats.has_method("compute_max_hp"):
		hp_max = int(stats.call("compute_max_hp", lvl, vtl))
	if stats and stats.has_method("compute_max_mp"):
		mp_max = int(stats.call("compute_max_mp", lvl, fcs))

	return {"level": lvl, "hp_max": hp_max, "mp_max": mp_max}

func _to_payload() -> Dictionary:
	var cal: Node = get_node_or_null(CALENDAR_PATH)
	var cal_date: Dictionary = {}
	var cal_phase: int = 0
	var cal_weekday: int = 0
	var label: String = ""
	if cal:
		var v_date: Variant = cal.get("current_date")
		if typeof(v_date) == TYPE_DICTIONARY:
			cal_date = v_date
		cal_phase   = int(cal.current_phase)
		cal_weekday = int(cal.current_weekday)

		var ds := ""
		if cal.has_method("get_date_string"):  ds = String(cal.get_date_string())
		var wd := ""
		if cal.has_method("get_weekday_name"): wd = String(cal.get_weekday_name())
		var ph := ""
		if cal.has_method("get_phase_name"):   ph = String(cal.get_phase_name())
		label = "%s %s %s" % [ds, wd, ph]

	var modules_blob: Dictionary = _export_modules_payload()

	var perks_legacy: Dictionary = {}
	if modules_blob.has("perks"):
		var pv: Variant = modules_blob["perks"]
		if typeof(pv) == TYPE_DICTIONARY:
			perks_legacy = pv as Dictionary

	# Pull hero active type from meta/property and include in save payload.
	var hero_active_type := "Omega"
	if self.has_meta("hero_active_type"):
		var mv: Variant = self.get_meta("hero_active_type")
		if typeof(mv) == TYPE_STRING:
			var s := String(mv).strip_edges()
			if s != "": hero_active_type = s
	elif self.has_method("get"):
		var v: Variant = self.get("hero_active_type")
		if typeof(v) == TYPE_STRING:
			var s2 := String(v).strip_edges()
			if s2 != "": hero_active_type = s2

	return {
		"scene": "Main",
		"label": label,
		"player_name": player_name,
		"difficulty": difficulty,
		"money": money,
		"perk_points": perk_points,
		"pacifist_score": pacifist_score,
		"bloodlust_score": bloodlust_score,
		"inventory": inventory.duplicate(true),
		"party": party.duplicate(),
		"bench": bench.duplicate(),
		"flags": flags.duplicate(true),
		"calendar": {
			"date": cal_date,
			"phase": cal_phase,
			"weekday": cal_weekday,
		},
		"equipment": _snapshot_equipment(),
		"index": get_index_blob(),
		"modules": modules_blob,
		"perks": perks_legacy,
		"hero_active_type": hero_active_type,   # ← persisted
	}

func _from_payload(p: Dictionary) -> void:
	player_name     = String(p.get("player_name", "Player"))
	difficulty      = String(p.get("difficulty", "Normal"))
	money           = int(p.get("money", 0))
	perk_points     = int(p.get("perk_points", 0))
	pacifist_score  = int(p.get("pacifist_score", 0))
	bloodlust_score = int(p.get("bloodlust_score", 0))

	var inv_v: Variant = p.get("inventory", {})
	inventory = (inv_v as Dictionary).duplicate(true) if typeof(inv_v) == TYPE_DICTIONARY else {}

	var party_v: Variant = p.get("party", [])
	party.clear()
	if typeof(party_v) == TYPE_ARRAY:
		for m in (party_v as Array): party.append(String(m))

	var bench_v: Variant = p.get("bench", [])
	bench.clear()
	if typeof(bench_v) == TYPE_ARRAY:
		for m2 in (bench_v as Array): bench.append(String(m2))

	var flags_v: Variant = p.get("flags", {})
	flags = (flags_v as Dictionary).duplicate(true) if typeof(flags_v) == TYPE_DICTIONARY else {}

	var equip_snap: Variant = p.get("equipment", null)

	var mods_v: Variant = p.get("modules", {})
	if typeof(mods_v) == TYPE_DICTIONARY:
		_import_modules_payload(mods_v as Dictionary)

	# Restore hero active type from payload (default Omega).
	var at_v: Variant = p.get("hero_active_type", null)
	var atype: String = "Omega"
	if typeof(at_v) == TYPE_STRING:
		var s := String(at_v).strip_edges()
		if s != "": atype = s
	self.set_meta("hero_active_type", atype)
	if self.has_method("set"):
		self.set("hero_active_type", atype)
	# Optionally notify listeners so UI/derived views refresh.
	var stats := get_node_or_null(STATS_PATH)
	if stats and stats.has_signal("stats_changed"):
		stats.emit_signal("stats_changed")

	if equip_snap != null:
		_apply_equipment_snapshot(equip_snap)
		var sig := get_node_or_null("/root/aSigilSystem")
		if sig and sig.has_method("on_bracelet_changed"):
			for m3 in _list_party_members():
				sig.call("on_bracelet_changed", String(m3))

	var perks_v: Variant = p.get("perks", {})
	if typeof(perks_v) == TYPE_DICTIONARY:
		_import_perks_blob(perks_v as Dictionary)

	var idx_v: Variant = p.get("index", {})
	if typeof(idx_v) == TYPE_DICTIONARY:
		apply_index_blob(idx_v as Dictionary)

	var cal: Node = get_node_or_null(CALENDAR_PATH)
	if cal:
		var set_any_date: bool = false
		var cal_block_v: Variant = p.get("calendar", {})
		if typeof(cal_block_v) == TYPE_DICTIONARY:
			var cb: Dictionary = cal_block_v
			var date_v: Variant = cb.get("date", {})
			if typeof(date_v) == TYPE_DICTIONARY and (date_v.has("month") or date_v.has("day")):
				cal.current_date = date_v
				set_any_date = true
			if cb.has("phase"):   cal.current_phase = int(cb["phase"])
			if cb.has("weekday"): cal.current_weekday = int(cb["weekday"])

		if not set_any_date and p.has("current_date") and typeof(p["current_date"]) == TYPE_DICTIONARY:
			cal.current_date = p["current_date"]
			set_any_date = true

		if not set_any_date:
			var lbl: String = String(p.get("label", ""))
			var ds: String  = String(p.get("date_string", ""))
			var md: Dictionary = _parse_mmdd(lbl)
			if md.is_empty() and ds != "":
				md = _parse_mmdd(ds)
			if not md.is_empty():
				var y: int = 2025
				var cur: Variant = cal.get("current_date")
				if typeof(cur) == TYPE_DICTIONARY:
					y = int((cur as Dictionary).get("year", y))
				cal.current_date = {"year": y, "month": int(md["month"]), "day": int(md["day"])}
				set_any_date = true

		if cal.has_method("get_weekday_index"):
			cal.current_weekday = cal.get_weekday_index()

		if cal.has_signal("day_advanced"):   cal.emit_signal("day_advanced", cal.current_date)
		if cal.has_signal("phase_advanced"): cal.emit_signal("phase_advanced", cal.current_phase)

	emit_signal("party_changed")

func _export_modules_payload() -> Dictionary:
	var out: Dictionary = {}
	for m_v in SAVE_MODULES:
		var md: Dictionary = m_v
		var id: String = String(md.get("id", ""))
		var path: String = String(md.get("path", ""))
		var export_fn: String = String(md.get("export", ""))
		if id == "" or path == "" or export_fn == "":
			continue
		var n: Node = get_node_or_null(path)
		if n != null and n.has_method(export_fn):
			var blob: Variant = n.call(export_fn)
			out[id] = blob
	return out

func _import_modules_payload(mods: Dictionary) -> void:
	for m_v in SAVE_MODULES:
		var md: Dictionary = m_v
		var id: String = String(md.get("id",""))
		if id == "" or not mods.has(id):
			continue
		var path: String = String(md.get("path", ""))
		var import_fn: String = String(md.get("import", ""))
		var n: Node = get_node_or_null(path)
		if n != null and import_fn != "" and n.has_method(import_fn):
			n.call(import_fn, mods[id])

func _reset_modules_for_new_game() -> void:
	for m_v in SAVE_MODULES:
		var md: Dictionary = m_v
		var path: String = String(md.get("path", ""))
		var reset_fn: String = String(md.get("reset", ""))
		if path == "" or reset_fn == "":
			continue
		var n: Node = get_node_or_null(path)
		if n != null and n.has_method(reset_fn):
			n.call(reset_fn)

func _export_perks_blob() -> Dictionary:
	var perk: Node = get_node_or_null(PERK_PATH)
	if perk and perk.has_method("get_save_blob"):
		var v: Variant = perk.call("get_save_blob")
		if typeof(v) == TYPE_DICTIONARY:
			return v as Dictionary
	return {}

func _import_perks_blob(blob: Dictionary) -> void:
	var perk: Node = get_node_or_null(PERK_PATH)
	if perk and perk.has_method("apply_save_blob"):
		perk.call("apply_save_blob", blob)

func get_mission_hint() -> String:
	var ms: Node = get_node_or_null("/root/aMainEventSystem")
	if ms and ms.has_method("get_current_hint"):
		return String(ms.call("get_current_hint"))
	return "—"

# ----- Equipment snapshot helpers ---------------------------------------------

func _snapshot_equipment() -> Dictionary:
	var out: Dictionary = {}
	var members := _list_party_members()
	var eq := get_node_or_null("/root/aEquipmentSystem")

	for m in members:
		var mem := String(m)
		var rec := {"weapon":"", "armor":"", "head":"", "foot":"", "bracelet":""}
		if eq and eq.has_method("get_member_equip"):
			var d: Variant = eq.call("get_member_equip", mem)
			if typeof(d) == TYPE_DICTIONARY:
				var dx: Dictionary = d
				for k in rec.keys():
					rec[k] = String(dx.get(k, rec[k]))
		out[mem] = rec
	return out

func _apply_equipment_snapshot(snap_v: Variant) -> void:
	if typeof(snap_v) != TYPE_DICTIONARY:
		return
	var eq := get_node_or_null("/root/aEquipmentSystem")
	if eq == null:
		call_deferred("_apply_equipment_snapshot", snap_v)
		return

	var snap: Dictionary = snap_v
	var sig := get_node_or_null("/root/aSigilSystem")

	for m in snap.keys():
		var mem := String(m)
		var rec_v: Variant = snap[m]
		if typeof(rec_v) != TYPE_DICTIONARY: continue
		var rec: Dictionary = rec_v

		if eq and eq.has_method("set_member_equip"):
			eq.call("set_member_equip", mem, rec.duplicate(true))
		else:
			for slot in ["weapon","armor","head","foot","bracelet"]:
				var id := String(rec.get(slot, ""))
				if id == "":
					if eq and eq.has_method("unequip_slot"):
						eq.call("unequip_slot", mem, slot)
				else:
					if eq and eq.has_method("equip_into_slot"):
						eq.call("equip_into_slot", mem, slot, id)

		if sig and sig.has_method("on_bracelet_changed"):
			sig.call("on_bracelet_changed", mem)

func _list_party_members() -> Array:
	var out := []
	for m in party: out.append(m)
	if out.is_empty(): out.append("hero")
	return out

func _parse_mmdd(s: String) -> Dictionary:
	var re: RegEx = RegEx.new()
	if re.compile("^\\s*(\\d{1,2})\\/(\\d{1,2})") != OK:
		return {}
	var m: RegExMatch = re.search(s)
	if m == null:
		return {}
	return {"month": int(m.get_string(1)), "day": int(m.get_string(2))}
