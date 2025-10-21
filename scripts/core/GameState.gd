extends Node
class_name GameState

signal party_changed
signal member_added(member_name: String)
signal member_removed(member_name: String)
signal roster_changed
signal perk_points_changed(new_value: int)
signal perk_unlocked(perk_id: String)
signal perks_changed
signal advance_blocked(reason: String)

# ─── Autoload paths ──────────────────────────────────────────
const CALENDAR_PATH: String = "/root/aCalendarSystem"
const STATS_PATH: String    = "/root/aStatsSystem"
const SAVELOAD_PATH: String = "/root/aSaveLoad"
const CSV_PATH: String      = "/root/aCSVLoader"
const CPS_PATH: String      = "/root/aCombatProfileSystem"
const INV_PATH: String      = "/root/aInventorySystem"
const EQUIP_PATH: String    = "/root/aEquipmentSystem"
const SIGIL_PATH: String    = "/root/aSigilSystem"

# Optional CSV with party metadata (names, etc.)
const PARTY_CSV: String   = "res://data/actors/party.csv"

const MAX_PARTY_SIZE: int = 4

# ─── Core state ──────────────────────────────────────────────
var player_name: String = "Player"
var difficulty: String = "Normal"
var money: int = 0
var perk_points: int = 0
var pacifist_score: int = 0
var bloodlust_score: int = 0

var party: Array[String] = []
var bench: Array[String] = []

var flags: Dictionary = {}
var index_blob: Dictionary = {"tutorials": [], "enemies": {}, "locations": {}, "lore": {}}
var member_data: Dictionary[String, Dictionary] = {}
var unlocked_perks: Array[String] = []

func _ready() -> void:
	var cal: Node = get_node_or_null(CALENDAR_PATH)
	if cal and cal.has_signal("advance_blocked") and not cal.is_connected("advance_blocked", Callable(self, "_on_cal_advance_blocked")):
		cal.connect("advance_blocked", Callable(self, "_on_cal_advance_blocked"))

func _on_cal_advance_blocked(reason: String) -> void:
	emit_signal("advance_blocked", reason)

# ─── New game bootstrap ──────────────────────────────────────
func new_game() -> void:
	player_name = "Player"
	difficulty = "Normal"
	money = 500
	perk_points = 0
	pacifist_score = 0
	bloodlust_score = 0
	party = ["hero"]
	bench = []
	flags.clear()
	unlocked_perks.clear()
	member_data.clear()

	# sensible defaults
	set_meta("hero_active_type", "Omega")

	# Seed hero runtime pools using StatsSystem when present
	var st: Node = get_node_or_null(STATS_PATH)
	var lvl: int = 1
	var vtl: int = 1
	var fcs: int = 1
	var hp_max: int = 150 + (max(1, vtl) * max(1, lvl) * 6)
	var mp_max: int = 20 + int(round(float(max(1, fcs)) * float(max(1, lvl)) * 1.5))
	if st:
		if st.has_method("compute_max_hp"):
			hp_max = int(st.call("compute_max_hp", lvl, vtl))
		if st.has_method("compute_max_mp"):
			mp_max = int(st.call("compute_max_mp", lvl, fcs))
	member_data["hero"] = {"hp": hp_max, "mp": mp_max, "buffs": [], "debuffs": []}

	# Reset calendar to a clean Monday Morning
	var cal: Node = get_node_or_null(CALENDAR_PATH)
	if cal:
		cal.set("current_date", {"year": 2025, "month": 5, "day": 5})
		cal.set("current_phase", 0)
		cal.set("current_weekday", 0)
		if cal.has_signal("day_advanced"):
			cal.emit_signal("day_advanced", cal.get("current_date"))
		if cal.has_signal("phase_advanced"):
			cal.emit_signal("phase_advanced", cal.get("current_phase"))

	# Reset week-based stats and refresh CPS
	if st and st.has_method("reset_week"):
		st.call("reset_week")
	var cps: Node = get_node_or_null(CPS_PATH)
	if cps and cps.has_method("refresh_all"):
		cps.call("refresh_all")

	emit_signal("party_changed")

# ─── Calendar helpers (respect Dorms blocking) ───────────────
func _anyone_in_common_room() -> bool:
	var dorm: Node = get_node_or_null("/root/aDormSystem")
	if dorm and dorm.has_method("get_common"):
		var v: Variant = dorm.call("get_common")
		if typeof(v) == TYPE_PACKED_STRING_ARRAY:
			return (v as PackedStringArray).size() > 0
		if typeof(v) == TYPE_ARRAY:
			return (v as Array).size() > 0
	return false

func try_advance_phase() -> void:
	if _anyone_in_common_room():
		emit_signal("advance_blocked", "There are people waiting in the Common Room for room assignments.")
		return
	var cal: Node = get_node_or_null(CALENDAR_PATH)
	if cal and cal.has_method("advance_phase"):
		cal.call("advance_phase")

func try_advance_day(days: int = 1) -> void:
	if days > 0 and _anyone_in_common_room():
		emit_signal("advance_blocked", "There are people waiting in the Common Room for room assignments.")
		return
	var cal: Node = get_node_or_null(CALENDAR_PATH)
	if cal and cal.has_method("advance_day"):
		cal.call("advance_day", days)

# ─── Roster helpers ──────────────────────────────────────────
func get_active_party_ids() -> Array:
	var out: Array = []
	for i in range(party.size()):
		out.append(String(party[i]))
	if out.is_empty():
		out.append("hero")
	return out

func get_party_names() -> PackedStringArray:
	var ids: Array = get_active_party_ids()
	var out := PackedStringArray()
	for i in range(ids.size()):
		out.append(_display_name_for_id(String(ids[i])))
	return out

func _display_name_for_id(id: String) -> String:
	if id == "hero":
		var nm: String = player_name.strip_edges()
		return (nm if nm != "" else "Player")

	var csv_loader: Node = get_node_or_null(CSV_PATH)
	if csv_loader and csv_loader.has_method("load_csv") and ResourceLoader.exists(PARTY_CSV):
		var defs_v: Variant = csv_loader.call("load_csv", PARTY_CSV, "actor_id")
		if typeof(defs_v) == TYPE_DICTIONARY:
			var defs: Dictionary = defs_v
			if defs.has(id):
				var row: Dictionary = defs[id]
				var nm2_v: Variant = row.get("name", "")
				if typeof(nm2_v) == TYPE_STRING:
					var nm2: String = String(nm2_v).strip_edges()
					if nm2 != "":
						return nm2
	return id.capitalize()

# Equipment snapshot (optional)
func get_member_equip(member: String) -> Dictionary:
	var equip_sys: Node = get_node_or_null(EQUIP_PATH)
	if equip_sys and equip_sys.has_method("get_member_equip"):
		var d_v: Variant = equip_sys.call("get_member_equip", member)
		if typeof(d_v) == TYPE_DICTIONARY:
			return d_v as Dictionary
	return {}

# Derived pools (HP/MP) — mirrors StatSystem if present
func compute_member_pools(member: String) -> Dictionary:
	var st: Node = get_node_or_null(STATS_PATH)
	var lvl: int = get_member_level(member)
	var vtl: int = get_member_stat(member, "VTL")
	var fcs: int = get_member_stat(member, "FCS")

	var hp_max: int = 150 + (max(1, vtl) * max(1, lvl) * 6)
	var mp_max: int = 20 + int(round(float(max(1, fcs)) * float(max(1, lvl)) * 1.5))
	if st:
		if st.has_method("compute_max_hp"):
			hp_max = int(st.call("compute_max_hp", lvl, vtl))
		if st.has_method("compute_max_mp"):
			mp_max = int(st.call("compute_max_mp", lvl, fcs))
	return {"level": lvl, "hp_max": hp_max, "mp_max": mp_max}

func get_member_level(member: String) -> int:
	var st: Node = get_node_or_null(STATS_PATH)
	var member_id: String = _resolve_member_id(member)
	if st and st.has_method("get_member_level"):
		var v: Variant = st.call("get_member_level", member_id)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			return int(v)

	var row: Dictionary = _row_for_member(member_id)
	for k in ["level", "lvl", "lv"]:
		if row.has(k):
			var rv: Variant = row[k]
			if typeof(rv) == TYPE_INT or typeof(rv) == TYPE_FLOAT or typeof(rv) == TYPE_STRING:
				return int(rv)
	return 1

func get_member_stat(member: String, stat: String) -> int:
	var st: Node = get_node_or_null(STATS_PATH)
	var member_id: String = _resolve_member_id(member)
	if st and st.has_method("get_member_stat_level"):
		var v: Variant = st.call("get_member_stat_level", member_id, stat)
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			return int(v)

	var row: Dictionary = _row_for_member(member_id)
	var cand: Array = [stat, stat + "_level", stat.to_lower(), stat.to_lower() + "_level", "stat_" + stat, "stat_" + stat.to_lower()]
	for i in range(cand.size()):
		var key: String = cand[i]
		if row.has(key):
			var rv: Variant = row[key]
			if typeof(rv) == TYPE_INT or typeof(rv) == TYPE_FLOAT or typeof(rv) == TYPE_STRING:
				return int(rv)
	return 1

func get_member_field(member: String, field: String) -> Variant:
	if _resolve_member_id(member) == "hero":
		if field == "mind_type":
			return (get_meta("hero_active_type") if has_meta("hero_active_type") else "Omega")
		if field == "identity":
			return (get_meta("hero_identity") if has_meta("hero_identity") else {})
	return null

func _resolve_member_id(name_in: String) -> String:
	var want: String = String(name_in).strip_edges().to_lower()
	if want == player_name.strip_edges().to_lower():
		return "hero"
	return name_in

func _row_for_member(member: String) -> Dictionary:
	var csv_loader: Node = get_node_or_null(CSV_PATH)
	if csv_loader and csv_loader.has_method("load_csv") and ResourceLoader.exists(PARTY_CSV):
		var v: Variant = csv_loader.call("load_csv", PARTY_CSV, "actor_id")
		if typeof(v) == TYPE_DICTIONARY:
			var defs: Dictionary = v
			if defs.has(member):
				return defs[member] as Dictionary
			var want: String = member.strip_edges().to_lower()
			for aid in defs.keys():
				var row: Dictionary = defs[aid] as Dictionary
				var nm_v: Variant = row.get("name", "")
				if typeof(nm_v) == TYPE_STRING and String(nm_v).strip_edges().to_lower() == want:
					return row
	return {}

# ─── Roster ops ──────────────────────────────────────────────
func add_member(member_id: String) -> bool:
	var mem_name: String = String(member_id).strip_edges()
	if mem_name == "" or party.has(mem_name) or bench.has(mem_name):
		return false

	if party.size() < MAX_PARTY_SIZE:
		party.append(mem_name)
		var pools: Dictionary = compute_member_pools(mem_name)
		var hp_max: int = int(pools.get("hp_max", 0))
		var mp_max: int = int(pools.get("mp_max", 0))
		member_data[mem_name] = {"hp": hp_max, "mp": mp_max, "buffs": [], "debuffs": []}
		emit_signal("member_added", mem_name)
		emit_signal("party_changed")
		return true
	else:
		bench.append(mem_name)
		var pools2: Dictionary = compute_member_pools(mem_name)
		var hp_max2: int = int(pools2.get("hp_max", 0))
		var mp_max2: int = int(pools2.get("mp_max", 0))
		member_data[mem_name] = {"hp": hp_max2, "mp": mp_max2, "buffs": [], "debuffs": []}
		emit_signal("roster_changed")
		return true

func remove_member(member_id: String) -> bool:
	var mem_name: String = String(member_id)
	if party.has(mem_name):
		party.erase(mem_name)
		member_data.erase(mem_name)
		emit_signal("member_removed", mem_name)
		emit_signal("party_changed")
		emit_signal("roster_changed")
		return true
	if bench.has(mem_name):
		bench.erase(mem_name)
		member_data.erase(mem_name)
		emit_signal("roster_changed")
		return true
	return false

func swap_members(a_index: int, b_index: int) -> bool:
	if a_index < 0 or a_index >= party.size() or b_index < 0 or b_index >= party.size():
		return false
	var temp: String = party[a_index]
	party[a_index] = party[b_index]
	party[b_index] = temp
	emit_signal("party_changed")
	return true

# ─── Perks ───────────────────────────────────────────────────
func unlock_perk(perk_id: String) -> bool:
	var pid: String = String(perk_id).strip_edges()
	if pid == "" or unlocked_perks.has(pid):
		return false
	if perk_points < 1:
		return false
	unlocked_perks.append(pid)
	perk_points = max(0, perk_points - 1)
	emit_signal("perk_unlocked", pid)
	emit_signal("perks_changed")
	emit_signal("perk_points_changed", perk_points)
	return true

func get_perk_points() -> int:
	return perk_points

func add_perk_points(points: int) -> void:
	if points == 0:
		return
	perk_points = max(0, perk_points + points)
	emit_signal("perk_points_changed", perk_points)

# ─── Hero start picks (for DormsSystem) ──────────────────────
func set_hero_start_picks(picks: PackedStringArray) -> void:
	# store in meta in canonical 3-letter uppercase
	var out := PackedStringArray()
	for i in range(picks.size()):
		out.append(String(picks[i]).strip_edges().to_upper())
	set_meta("hero_start_picks", out)

func get_hero_start_picks() -> PackedStringArray:
	# 1) explicit meta (preferred)
	if has_meta("hero_start_picks"):
		var m: Variant = get_meta("hero_start_picks")
		if typeof(m) == TYPE_PACKED_STRING_ARRAY:
			return m as PackedStringArray
	# legacy key
	if has_meta("hero_picked_stats"):
		var m2: Variant = get_meta("hero_picked_stats")
		if typeof(m2) == TYPE_PACKED_STRING_ARRAY:
			return m2 as PackedStringArray
	# 2) ask StatsSystem if it exposes it
	var out := PackedStringArray()
	var st: Node = get_node_or_null(STATS_PATH)
	if st and st.has_method("get_hero_start_picks"):
		var hv: Variant = st.call("get_hero_start_picks")
		if typeof(hv) == TYPE_PACKED_STRING_ARRAY:
			return hv as PackedStringArray
		if typeof(hv) == TYPE_ARRAY:
			var a: Array = hv
			for i in range(a.size()):
				out.append(String(a[i]).to_upper())
			return out
	# 3) infer from stats > 1
	if st and st.has_method("get_stat"):
		for code in ["BRW","MND","TPO","VTL","FCS"]:
			var lv: Variant = st.call("get_stat", code)
			if (typeof(lv) == TYPE_INT or typeof(lv) == TYPE_FLOAT) and int(lv) > 1:
				out.append(code)
			if out.size() >= 3:
				break
	return out

# ─── Save/Load ───────────────────────────────────────────────
func save() -> Dictionary:
	var payload: Dictionary = {}

	# Basic state
	payload["player_name"]     = player_name
	payload["difficulty"]      = difficulty
	payload["money"]           = money
	payload["perk_points"]     = perk_points
	payload["pacifist_score"]  = pacifist_score
	payload["bloodlust_score"] = bloodlust_score

	# Party
	payload["party"] = party.duplicate()
	payload["bench"] = bench.duplicate()

	# Flags & index
	payload["flags"] = flags.duplicate(true)
	payload["index"] = index_blob.duplicate(true)

	# Perks & member runtime
	payload["unlocked_perks"] = unlocked_perks.duplicate()
	payload["member_data"]    = member_data.duplicate(true)

	# Calendar
	var cal: Node = get_node_or_null(CALENDAR_PATH)
	if cal:
		var cal_data: Dictionary = {}
		var d_val: Variant = (cal.get("current_date") if cal.has_method("get") else null)
		var p_val: Variant = (cal.get("current_phase") if cal.has_method("get") else null)
		var w_val: Variant = (cal.get("current_weekday") if cal.has_method("get") else null)
		cal_data["date"]    = (d_val if typeof(d_val) == TYPE_DICTIONARY else {})
		cal_data["phase"]   = (int(p_val) if typeof(p_val) == TYPE_INT or typeof(p_val) == TYPE_FLOAT else 0)
		cal_data["weekday"] = (int(w_val) if typeof(w_val) == TYPE_INT or typeof(w_val) == TYPE_FLOAT else 0)
		payload["calendar"] = cal_data

	# Stats
	var stats_sys: Node = get_node_or_null(STATS_PATH)
	if stats_sys and stats_sys.has_method("save"):
		var stats_data: Variant = stats_sys.call("save")
		if typeof(stats_data) == TYPE_DICTIONARY:
			payload["stats"] = stats_data as Dictionary

	# Inventory
	var inv_sys: Node = get_node_or_null(INV_PATH)
	if inv_sys and inv_sys.has_method("get_save_blob"):
		var inv_blob: Variant = inv_sys.call("get_save_blob")
		if typeof(inv_blob) == TYPE_DICTIONARY:
			var inv_dict: Dictionary = inv_blob
			if inv_dict.has("items"):
				payload["items"] = inv_dict["items"]
			else:
				payload["inventory"] = inv_dict.duplicate(true)

	# Sigils
	var sigil_sys: Node = get_node_or_null(SIGIL_PATH)
	if sigil_sys and sigil_sys.has_method("save"):
		var sig_data: Variant = sigil_sys.call("save")
		if typeof(sig_data) == TYPE_DICTIONARY:
			payload["sigils"] = sig_data as Dictionary

	# Meta snapshot
	var meta_dict: Dictionary = {}
	var meta_keys: PackedStringArray = get_meta_list()
	for i in range(meta_keys.size()):
		var key: String = meta_keys[i]
		meta_dict[key] = get_meta(key)
	payload["meta"] = meta_dict

	return payload

func load(data: Dictionary) -> void:
	if data.is_empty():
		return

	player_name     = String(data.get("player_name", player_name))
	difficulty      = String(data.get("difficulty", difficulty))
	money           = int(data.get("money", money))
	perk_points     = int(data.get("perk_points", perk_points))
	pacifist_score  = int(data.get("pacifist_score", pacifist_score))
	bloodlust_score = int(data.get("bloodlust_score", bloodlust_score))

	party          = (data.get("party", []) as Array).duplicate()
	bench          = (data.get("bench", []) as Array).duplicate()
	flags          = (data.get("flags", flags) as Dictionary).duplicate(true)
	index_blob     = (data.get("index", index_blob) as Dictionary).duplicate(true)
	unlocked_perks = (data.get("unlocked_perks", unlocked_perks) as Array).duplicate()

	member_data.clear()
	var md_v: Variant = data.get("member_data", {})
	if typeof(md_v) == TYPE_DICTIONARY:
		var md_in: Dictionary = md_v
		for k in md_in.keys():
			var key: String = String(k)
			var val_v: Variant = md_in[k]
			if typeof(val_v) == TYPE_DICTIONARY:
				member_data[key] = (val_v as Dictionary).duplicate(true)

	# Calendar
	var cal: Node = get_node_or_null(CALENDAR_PATH)
	var cal_v: Variant = data.get("calendar", {})
	if cal and typeof(cal_v) == TYPE_DICTIONARY:
		var cal_d: Dictionary = cal_v
		if cal_d.has("date"):
			cal.set("current_date", cal_d["date"])
		if cal_d.has("phase"):
			cal.set("current_phase", cal_d["phase"])
		if cal_d.has("weekday"):
			cal.set("current_weekday", cal_d["weekday"])

	# Stats
	var stats_sys: Node = get_node_or_null(STATS_PATH)
	var stats_v: Variant = data.get("stats", null)
	if stats_sys and typeof(stats_v) == TYPE_DICTIONARY:
		if stats_sys.has_method("load"):
			stats_sys.call("load", stats_v)
		elif stats_sys.has_method("apply_save_blob"):
			stats_sys.call("apply_save_blob", stats_v)

	# Inventory
	var items_v: Variant = data.get("items", null)
	if items_v == null:
		items_v = data.get("inventory", null)
	var inv_sys: Node = get_node_or_null(INV_PATH)
	if inv_sys and typeof(items_v) == TYPE_DICTIONARY:
		if inv_sys.has_method("apply_save_blob"):
			inv_sys.call("apply_save_blob", items_v)
		elif inv_sys.has_method("load"):
			inv_sys.call("load", items_v)

	# Sigils
	var sig_v: Variant = data.get("sigils", null)
	var sigil_sys: Node = get_node_or_null(SIGIL_PATH)
	if sigil_sys and typeof(sig_v) == TYPE_DICTIONARY:
		if sigil_sys.has_method("load"):
			sigil_sys.call("load", sig_v)
		elif sigil_sys.has_method("apply_save_blob"):
			sigil_sys.call("apply_save_blob", sig_v)

	# Refresh CPS
	var cps: Node = get_node_or_null(CPS_PATH)
	if cps and cps.has_method("refresh_all"):
		cps.call("refresh_all")

	# Push member runtime to CPS if it wants it
	if cps and cps.has_method("apply_save_blob"):
		var cp_blob: Dictionary = {"party": {}, "enemies": {}}
		for id_key in member_data.keys():
			var rec: Dictionary = member_data[id_key] as Dictionary
			var entry: Dictionary = {
				"hp": int(rec.get("hp", 0)),
				"mp": int(rec.get("mp", 0)),
				"ailment": String(rec.get("ailment", "")),
				"flags": (rec.get("flags", {}) as Dictionary).duplicate(true),
				"buffs": (rec.get("buffs", []) as Array).duplicate(true),
				"debuffs": (rec.get("debuffs", []) as Array).duplicate(true)
			}
			cp_blob["party"][id_key] = entry
		cps.call("apply_save_blob", cp_blob)

	# Meta
	var meta_v: Variant = data.get("meta", null)
	if typeof(meta_v) == TYPE_DICTIONARY:
		var meta_in: Dictionary = meta_v
		for mkey in meta_in.keys():
			set_meta(String(mkey), meta_in[mkey])

	emit_signal("party_changed")
	emit_signal("roster_changed")
	emit_signal("perk_points_changed", perk_points)
