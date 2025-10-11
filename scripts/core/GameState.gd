extends Node
class_name GameState

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

const SAVE_MODULES: Array = [
	{"id":"perks",    "path": PERK_PATH,                 "export":"get_save_blob", "import":"apply_save_blob", "reset":"clear_all"},
	{"id":"hero",     "path": "/root/aHeroSystem",       "export":"get_save_blob", "import":"apply_save_blob", "reset":"clear_all"},
	{"id":"stats",    "path": "/root/aStatsSystem",      "export":"get_save_blob", "import":"apply_save_blob", "reset":"clear_all"},
	{"id":"inventory","path": "/root/aInventorySystem",  "export":"get_save_blob", "import":"apply_save_blob", "reset":"clear_all"},
	{"id":"equipment","path": "/root/aEquipmentSystem",   "export":"get_save_blob", "import":"apply_save_blob", "reset":"clear_all"},
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
		# store current equip outside modules so we can restore before/after as needed
		"equipment": _snapshot_equipment(),
		"index": get_index_blob(),
		"modules": modules_blob,
		"perks": perks_legacy,
	}

func _from_payload(p: Dictionary) -> void:
	# Basic top-level fields
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
		for m in (bench_v as Array): bench.append(String(m))

	var flags_v: Variant = p.get("flags", {})
	flags = (flags_v as Dictionary).duplicate(true) if typeof(flags_v) == TYPE_DICTIONARY else {}

	# Defer equipment application until AFTER modules (Inventory/Sigils) are restored.
	var equip_snap: Variant = p.get("equipment", null)

	# Deterministic module import order
	var mods_v: Variant = p.get("modules", {})
	if typeof(mods_v) == TYPE_DICTIONARY:
		_import_modules_payload(mods_v as Dictionary)

	# Now apply equipment snapshot (Inventory is back, equip calls won't fail).
	if equip_snap != null:
		_apply_equipment_snapshot(equip_snap)
		# Ensure Sigil capacity matches the bracelet post-equip
		var sig := get_node_or_null("/root/aSigilSystem")
		if sig and sig.has_method("on_bracelet_changed"):
			for m in _list_party_members():
				sig.call("on_bracelet_changed", String(m))

	# Legacy perks block, if present
	var perks_v: Variant = p.get("perks", {})
	if typeof(perks_v) == TYPE_DICTIONARY:
		_import_perks_blob(perks_v as Dictionary)

	# Index blob
	var idx_v: Variant = p.get("index", {})
	if typeof(idx_v) == TYPE_DICTIONARY:
		apply_index_blob(idx_v as Dictionary)

	# Calendar
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
	# If EquipmentSystem isn't ready *right now*, try again next frame.
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
