## ═══════════════════════════════════════════════════════════════════════════
## GameState - Central Game State Manager
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   The core singleton that manages all persistent game state including player
##   progression, party roster, inventory, equipment, and coordination of all
##   game systems. Acts as the central hub for save/load operations.
##
## RESPONSIBILITIES:
##   • Player data (name, difficulty, CREDS, perk points, alignment scores)
##   • Party/bench roster management (max 4 active party members)
##   • Global flags and index tracking (tutorials, enemies, locations, lore)
##   • Member runtime data (HP, MP, ailments, buffs, custom fields)
##   • Perk system integration (points, unlocks)
##   • Save/load orchestration across all systems
##   • Sigil snapshot management (equipment-aware save/restore)
##
## CONNECTED SYSTEMS (Autoloads):
##   • CalendarSystem - Time progression, advance blocking
##   • StatsSystem - Member base stats (BRW, MND, TPO, VTL, FCS)
##   • SaveLoad - File persistence system
##   • CSVLoader - CSV data loading
##   • CombatProfileSystem - Battle state (HP, MP, ailments, buffs)
##   • InventorySystem - Item storage and counts
##   • EquipmentSystem - Gear loadouts (weapon, armor, head, foot, bracelet)
##   • SigilSystem - Sigil instances and socket assignments
##
## OPTIONAL SYSTEMS (loaded if present):
##   • CircleBondSystem - Social bonds and relationship tracking
##   • DormSystem - Room assignments and dorm state
##   • RomanceSystem - Romance progression
##   • AffinitySystem - Affinity tracking
##   • PerkSystem - Perk unlocks and effects
##   • MainEventSystem - Story event progress
##
## SAVE/LOAD ARCHITECTURE:
##   1. Equipment loads FIRST (bracelets must exist before sigils)
##   2. Sigils load SECOND (needs bracelet capacity)
##   3. Other systems load in dependency order
##   4. Dual sigil save: system blob + v2 snapshot (XP, level, active skills)
##
## KEY METHODS:
##   • save() -> Dictionary - Collects state from all systems
##   • load(data: Dictionary) - Restores state to all systems
##   • save_to_slot(slot: int) - Saves to numbered slot via SaveLoad
##   • apply_loaded_save(data: Dictionary) - UI bridge for loading
##   • add_member(), remove_member(), swap_members() - Roster management
##   • unlock_perk(), add_perk_points() - Perk system
##
## ═══════════════════════════════════════════════════════════════════════════

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

const MAX_PARTY_SIZE: int = 3  # Hero + 2 active members

# ─── Core state ──────────────────────────────────────────────
var player_name: String = "Player"
var difficulty: String = "Normal"
var creds: int = 0
var perk_points: int = 0
var pacifist_score: int = 0
var bloodlust_score: int = 0
var time_played: float = 0.0  # Total playtime in seconds

var party: Array[String] = []
var bench: Array[String] = []

var flags: Dictionary = {}
var index_blob: Dictionary = {"tutorials": [], "enemies": {}, "locations": {}, "lore": {}}
var member_data: Dictionary[String, Dictionary] = {}
var unlocked_perks: Array[String] = []

## Initializes GameState and connects to CalendarSystem's advance_blocked signal
func _ready() -> void:
	var cal: Node = get_node_or_null(CALENDAR_PATH)
	if cal and cal.has_signal("advance_blocked") and not cal.is_connected("advance_blocked", Callable(self, "_on_cal_advance_blocked")):
		cal.connect("advance_blocked", Callable(self, "_on_cal_advance_blocked"))

	# Ensure party structure is correct on startup
	call_deferred("_enforce_party_limits")

## Tracks playtime by accumulating delta time each frame
func _process(delta: float) -> void:
	time_played += delta

## Forwards CalendarSystem's advance_blocked signal to GameState listeners
func _on_cal_advance_blocked(reason: String) -> void:
	emit_signal("advance_blocked", reason)

# ─── New game bootstrap ──────────────────────────────────────
## Resets all game state to default values for a new game. Sets hero as starting party
## member with default stats, resets calendar to Monday Morning, and initializes systems.
func new_game() -> void:
	player_name = "Player"
	difficulty = "Normal"
	creds = 500
	perk_points = 0
	pacifist_score = 0
	bloodlust_score = 0
	time_played = 0.0  # Reset playtime for new game
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
## Checks if anyone is waiting in the dorm's common room for room assignment
## Returns true if common room has occupants, false otherwise
func _anyone_in_common_room() -> bool:
	var dorm: Node = get_node_or_null("/root/aDormSystem")
	if dorm and dorm.has_method("get_common"):
		var v: Variant = dorm.call("get_common")
		if typeof(v) == TYPE_PACKED_STRING_ARRAY:
			return (v as PackedStringArray).size() > 0
		if typeof(v) == TYPE_ARRAY:
			return (v as Array).size() > 0
	return false

## Advances to the next phase of day (Morning -> Afternoon -> Evening).
## Blocked if people are waiting in common room for dorm assignments.
func try_advance_phase() -> void:
	if _anyone_in_common_room():
		emit_signal("advance_blocked", "There are people waiting in the Common Room for room assignments.")
		return
	var cal: Node = get_node_or_null(CALENDAR_PATH)
	if cal and cal.has_method("advance_phase"):
		cal.call("advance_phase")

## Advances the calendar by specified number of days.
## Blocked if people are waiting in common room for dorm assignments.
func try_advance_day(days: int = 1) -> void:
	if days > 0 and _anyone_in_common_room():
		emit_signal("advance_blocked", "There are people waiting in the Common Room for room assignments.")
		return
	var cal: Node = get_node_or_null(CALENDAR_PATH)
	if cal and cal.has_method("advance_day"):
		cal.call("advance_day", days)

# ─── Roster helpers ──────────────────────────────────────────
## Returns an array of active party member IDs. Always returns at least ["hero"] if party is empty.
func get_active_party_ids() -> Array:
	var out: Array = []
	for i in range(party.size()):
		out.append(String(party[i]))
	if out.is_empty():
		out.append("hero")
	return out

## Returns display names for all active party members by looking up their IDs
func get_party_names() -> PackedStringArray:
	var ids: Array = get_active_party_ids()
	var out := PackedStringArray()
	for i in range(ids.size()):
		out.append(_display_name_for_id(String(ids[i])))
	return out

## Converts a member ID to a display name. "hero" returns player_name, others lookup from party CSV.
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
## Returns the equipped items for a party member (weapon, armor, head, foot, bracelet)
func get_member_equip(member: String) -> Dictionary:
	var equip_sys: Node = get_node_or_null(EQUIP_PATH)
	if equip_sys and equip_sys.has_method("get_member_equip"):
		var d_v: Variant = equip_sys.call("get_member_equip", member)
		if typeof(d_v) == TYPE_DICTIONARY:
			return d_v as Dictionary
	return {}

# Derived pools (HP/MP) — mirrors StatSystem if present
## Calculates max HP and MP for a member based on level and stats (VTL for HP, FCS for MP)
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

## Gets the level of a party member from StatsSystem or CSV data. Defaults to 1 if not found.
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

## Gets a specific stat value (BRW, MND, TPO, VTL, FCS) for a member. Defaults to 1 if not found.
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

## Gets custom field data for a member. Currently supports "mind_type" and "identity" for hero.
func get_member_field(member: String, field: String) -> Variant:
	if _resolve_member_id(member) == "hero":
		if field == "mind_type":
			return (get_meta("hero_active_type") if has_meta("hero_active_type") else "Omega")
		if field == "identity":
			return (get_meta("hero_identity") if has_meta("hero_identity") else {})
	return null

## Converts a member name to their ID. Converts player_name to "hero" automatically.
func _resolve_member_id(name_in: String) -> String:
	var want: String = String(name_in).strip_edges().to_lower()
	if want == player_name.strip_edges().to_lower():
		return "hero"
	return name_in

## Looks up CSV data row for a party member from party.csv
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
## Adds a new member to the party (if space) or bench. Initializes their HP/MP pools.
## Returns false if member already exists or ID is empty.
func add_member(member_id: String) -> bool:
	var mem_name: String = String(member_id).strip_edges()
	if mem_name == "" || party.has(mem_name) || bench.has(mem_name):
		return false

	# Ensure party structure is correct (max 3: hero + 2 active)
	_enforce_party_limits()

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

## Ensures party doesn't exceed MAX_PARTY_SIZE by moving extras to bench
func _enforce_party_limits() -> void:
	if party.size() > MAX_PARTY_SIZE:
		for i in range(MAX_PARTY_SIZE, party.size()):
			var overflow: String = party[i]
			if overflow != "" and overflow != "hero" and not bench.has(overflow):
				bench.append(overflow)
		# Trim party to MAX_PARTY_SIZE
		party.resize(MAX_PARTY_SIZE)

## Removes a member from party or bench. Clears their member_data. Returns false if not found.
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

## Swaps positions of two party members by their array indices. Returns false if invalid indices.
func swap_members(a_index: int, b_index: int) -> bool:
	if a_index < 0 or a_index >= party.size() or b_index < 0 or b_index >= party.size():
		return false
	var temp: String = party[a_index]
	party[a_index] = party[b_index]
	party[b_index] = temp
	emit_signal("party_changed")
	return true

## Moves a bench member to an active party slot at specified index. Returns false if invalid.
## If slot already occupied, existing member is moved to bench.
func move_to_active(member_id: String, slot_index: int) -> bool:
	var mem_name: String = String(member_id).strip_edges()
	if mem_name == "" or mem_name == "hero":
		return false  # Hero cannot be moved
	if not bench.has(mem_name):
		return false  # Member not on bench
	if slot_index < 1 or slot_index > 2:
		return false  # Only slots 1-2 available (slot 0 is hero)

	# Ensure party array has enough slots
	while party.size() < slot_index + 1:
		party.append("")

	# If slot occupied, move existing member to bench
	if party[slot_index] != "" and party[slot_index] != "hero":
		var existing: String = party[slot_index]
		bench.append(existing)

	# Move member from bench to active
	bench.erase(mem_name)
	party[slot_index] = mem_name

	emit_signal("party_changed")
	emit_signal("roster_changed")
	return true

## Moves an active party member to the bench. Returns false if invalid or hero.
func move_to_bench(member_id: String) -> bool:
	var mem_name: String = String(member_id).strip_edges()
	if mem_name == "" or mem_name == "hero":
		return false  # Hero cannot be benched
	if not party.has(mem_name):
		return false  # Not in active party

	# Move to bench
	party.erase(mem_name)
	bench.append(mem_name)

	emit_signal("party_changed")
	emit_signal("roster_changed")
	return true

## Swaps an active party member with a bench member. Returns false if invalid.
func swap_active_bench(active_index: int, bench_member_id: String) -> bool:
	if active_index < 1 or active_index > 2:
		return false  # Only allow swapping slots 1-2 (not hero at 0)

	var bench_mem: String = String(bench_member_id).strip_edges()
	if bench_mem == "" or not bench.has(bench_mem):
		return false  # Bench member not found

	# Ensure party array has enough slots
	while party.size() < active_index + 1:
		party.append("")

	var active_mem: String = party[active_index]
	if active_mem == "hero":
		return false  # Cannot swap hero

	# Perform swap
	if active_mem != "":
		bench.erase(bench_mem)
		bench.append(active_mem)
		party[active_index] = bench_mem
	else:
		# Empty slot, just move from bench
		bench.erase(bench_mem)
		party[active_index] = bench_mem

	emit_signal("party_changed")
	emit_signal("roster_changed")
	return true

# ─── Perks ───────────────────────────────────────────────────
## Unlocks a perk and deducts 1 perk point. Returns false if already unlocked,
## perk ID is empty, or insufficient points.
func unlock_perk(perk_id: String) -> bool:
	var pid: String = String(perk_id).strip_edges()
	if pid == "" || unlocked_perks.has(pid):
		return false
	if perk_points < 1:
		return false
	unlocked_perks.append(pid)
	perk_points = max(0, perk_points - 1)
	emit_signal("perk_unlocked", pid)
	emit_signal("perks_changed")
	emit_signal("perk_points_changed", perk_points)
	return true

## Returns the current number of unspent perk points
func get_perk_points() -> int:
	return perk_points

## Adds (or subtracts if negative) perk points and emits change signal
func add_perk_points(points: int) -> void:
	if points == 0:
		return
	perk_points = max(0, perk_points + points)
	emit_signal("perk_points_changed", perk_points)

# ─── CREDS (currency) ─────────────────────────────────────────
## Returns the current amount of CREDS (game currency)
func get_creds() -> int:
	return creds

## Adds (or subtracts if negative) CREDS. Cannot go below 0
func add_creds(amount: int) -> void:
	if amount == 0:
		return
	creds = max(0, creds + amount)
	print("[GameState] add_creds(%+d) -> total=%d" % [amount, creds])

# ─── Hero start picks (for DormsSystem) ──────────────────────
## Stores the hero's starting class picks as metadata for DormsSystem
func set_hero_start_picks(picks: PackedStringArray) -> void:
	var out := PackedStringArray()
	for i in range(picks.size()):
		out.append(String(picks[i]).strip_edges().to_upper())
	set_meta("hero_start_picks", out)

## Retrieves the hero's starting stat picks from metadata or StatsSystem
func get_hero_start_picks() -> PackedStringArray:
	if has_meta("hero_start_picks"):
		var m: Variant = get_meta("hero_start_picks")
		if typeof(m) == TYPE_PACKED_STRING_ARRAY:
			return m as PackedStringArray
	if has_meta("hero_picked_stats"):
		var m2: Variant = get_meta("hero_picked_stats")
		if typeof(m2) == TYPE_PACKED_STRING_ARRAY:
			return m2 as PackedStringArray
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
	if st and st.has_method("get_stat"):
		for code in ["BRW","MND","TPO","VTL","FCS"]:
			var lv: Variant = st.call("get_stat", code)
			if (typeof(lv) == TYPE_INT || typeof(lv) == TYPE_FLOAT) and int(lv) > 1:
				out.append(code)
			if out.size() >= 3:
				break
	return out

# ─── Save/Load ───────────────────────────────────────────────
## Resets all systems to clear any existing state before loading a save.
## This prevents data leakage between different save files or sessions.
func reset_all_systems() -> void:
	print("[GameState] Resetting all systems before load...")

	# Clear GameState core data
	party.clear()
	bench.clear()
	flags.clear()
	index_blob = {"tutorials": [], "enemies": {}, "locations": {}, "lore": {}}
	member_data.clear()
	unlocked_perks.clear()
	perk_points = 0
	creds = 0
	pacifist_score = 0
	bloodlust_score = 0

	# Clear metadata
	for key in get_meta_list():
		remove_meta(key)

	# Reset subsystems (call reset/clear if available)
	var stats_sys: Node = get_node_or_null(STATS_PATH)
	if stats_sys and stats_sys.has_method("reset"):
		stats_sys.call("reset")
	elif stats_sys and stats_sys.has_method("clear"):
		stats_sys.call("clear")

	var inv_sys: Node = get_node_or_null(INV_PATH)
	if inv_sys and inv_sys.has_method("reset"):
		inv_sys.call("reset")
	elif inv_sys and inv_sys.has_method("clear"):
		inv_sys.call("clear")

	var equip_sys: Node = get_node_or_null(EQUIP_PATH)
	if equip_sys and equip_sys.has_method("reset"):
		equip_sys.call("reset")
	elif equip_sys and equip_sys.has_method("clear"):
		equip_sys.call("clear")

	var sigil_sys: Node = get_node_or_null(SIGIL_PATH)
	if sigil_sys and sigil_sys.has_method("reset"):
		sigil_sys.call("reset")
	elif sigil_sys and sigil_sys.has_method("clear"):
		sigil_sys.call("clear")

	var cps: Node = get_node_or_null(CPS_PATH)
	if cps and cps.has_method("reset"):
		cps.call("reset")
	elif cps and cps.has_method("clear"):
		cps.call("clear")

	# Optional systems
	var cb_sys: Node = get_node_or_null("/root/aCircleBondSystem")
	if cb_sys and cb_sys.has_method("reset"):
		cb_sys.call("reset")

	var dorm_sys: Node = get_node_or_null("/root/aDormSystem")
	if dorm_sys and dorm_sys.has_method("reset"):
		dorm_sys.call("reset")

	var rom_sys: Node = get_node_or_null("/root/aRomanceSystem")
	if rom_sys and rom_sys.has_method("reset"):
		rom_sys.call("reset")

	var aff_sys: Node = get_node_or_null("/root/aAffinitySystem")
	if aff_sys and aff_sys.has_method("reset"):
		aff_sys.call("reset")

	var perk_sys: Node = get_node_or_null("/root/aPerkSystem")
	if perk_sys and perk_sys.has_method("reset"):
		perk_sys.call("reset")

	var me_sys: Node = get_node_or_null("/root/aMainEventSystem")
	if me_sys and me_sys.has_method("reset"):
		me_sys.call("reset")

	# Clear PanelManager stack to prevent stale panel references
	var pm: Node = get_node_or_null("/root/aPanelManager")
	if pm and pm.has_method("force_reset"):
		pm.call("force_reset")

	print("[GameState] System reset complete")

## Collects all game state into a Dictionary for saving. Calls save() on all connected systems
## (Calendar, Stats, Inventory, Equipment, Sigils, Bonds, Dorm, Romance, etc.). Returns the
## complete save payload. Note: Equipment loads BEFORE sigils to ensure bracelet capacity exists.
func save() -> Dictionary:
	var payload: Dictionary = {}

	payload["player_name"]     = player_name
	payload["difficulty"]      = difficulty
	payload["creds"]           = creds
	payload["perk_points"]     = perk_points
	payload["pacifist_score"]  = pacifist_score
	payload["bloodlust_score"] = bloodlust_score
	payload["time_played"]     = int(time_played)  # Save as integer seconds

	payload["party"] = party.duplicate()
	payload["bench"] = bench.duplicate()

	payload["flags"] = flags.duplicate(true)
	payload["index"] = index_blob.duplicate(true)

	payload["unlocked_perks"] = unlocked_perks.duplicate()
	payload["member_data"]    = member_data.duplicate(true)

	var cal: Node = get_node_or_null(CALENDAR_PATH)
	if cal:
		var cal_data: Dictionary = {}
		var d_val: Variant = (cal.get("current_date") if cal.has_method("get") else null)
		var p_val: Variant = (cal.get("current_phase") if cal.has_method("get") else null)
		var w_val: Variant = (cal.get("current_weekday") if cal.has_method("get") else null)
		cal_data["date"]    = (d_val if typeof(d_val) == TYPE_DICTIONARY else {})
		cal_data["phase"]   = (int(p_val) if typeof(p_val) == TYPE_INT || typeof(p_val) == TYPE_FLOAT else 0)
		cal_data["weekday"] = (int(w_val) if typeof(w_val) == TYPE_INT || typeof(w_val) == TYPE_FLOAT else 0)
		payload["calendar"] = cal_data

	var stats_sys: Node = get_node_or_null(STATS_PATH)
	if stats_sys and stats_sys.has_method("save"):
		var stats_data: Variant = stats_sys.call("save")
		if typeof(stats_data) == TYPE_DICTIONARY:
			payload["stats"] = stats_data as Dictionary

	var inv_sys: Node = get_node_or_null(INV_PATH)
	if inv_sys and inv_sys.has_method("get_save_blob"):
		var inv_blob: Variant = inv_sys.call("get_save_blob")
		if typeof(inv_blob) == TYPE_DICTIONARY:
			var inv_dict: Dictionary = inv_blob
			if inv_dict.has("items"):
				payload["items"] = inv_dict["items"]
			else:
				payload["inventory"] = inv_dict.duplicate(true)

	# SIGILS: keep system’s own blob AND our robust snapshot with owners/slots/xp/level/active skill
	var sigil_sys: Node = get_node_or_null(SIGIL_PATH)
	if sigil_sys:
		if sigil_sys.has_method("save"):
			var sig_data: Variant = sigil_sys.call("save")
			if typeof(sig_data) == TYPE_DICTIONARY:
				payload["sigils"] = sig_data as Dictionary
		var snap: Dictionary = _build_sigil_snapshot(sigil_sys)
		if not snap.is_empty():
			payload["sigils_v2"] = snap

	# Meta snapshot
	var meta_dict: Dictionary = {}
	var meta_keys: PackedStringArray = get_meta_list()
	for i in range(meta_keys.size()):
		var key: String = meta_keys[i]
		meta_dict[key] = get_meta(key)
	payload["meta"] = meta_dict

	# Optional systems (if present)
	var cb_sys: Node = get_node_or_null("/root/aCircleBondSystem")
	if cb_sys and cb_sys.has_method("save"):
		var cb_data: Variant = cb_sys.call("save")
		if typeof(cb_data) == TYPE_DICTIONARY:
			payload["circle_bonds"] = cb_data as Dictionary

	var dorm_sys: Node = get_node_or_null("/root/aDormSystem")
	if dorm_sys and dorm_sys.has_method("save"):
		var dorm_data: Variant = dorm_sys.call("save")
		if typeof(dorm_data) == TYPE_DICTIONARY:
			payload["dorms"] = dorm_data as Dictionary

	var equip_sys: Node = get_node_or_null(EQUIP_PATH)
	if equip_sys and equip_sys.has_method("save"):
		var equip_data: Variant = equip_sys.call("save")
		if typeof(equip_data) == TYPE_DICTIONARY:
			payload["equipment"] = equip_data as Dictionary

	var rom_sys: Node = get_node_or_null("/root/aRomanceSystem")
	if rom_sys and rom_sys.has_method("save"):
		var rom_data: Variant = rom_sys.call("save")
		if typeof(rom_data) == TYPE_DICTIONARY:
			payload["romance"] = rom_data as Dictionary

	var aff_sys: Node = get_node_or_null("/root/aAffinitySystem")
	if aff_sys and aff_sys.has_method("save"):
		var aff_data: Variant = aff_sys.call("save")
		if typeof(aff_data) == TYPE_DICTIONARY:
			payload["affinity"] = aff_data as Dictionary

	var perk_sys: Node = get_node_or_null("/root/aPerkSystem")
	if perk_sys and perk_sys.has_method("get_save_blob"):
		var perk_data: Variant = perk_sys.call("get_save_blob")
		if typeof(perk_data) == TYPE_DICTIONARY:
			payload["perk_system"] = perk_data as Dictionary

	var main_event_sys: Node = get_node_or_null("/root/aMainEventSystem")
	if main_event_sys and main_event_sys.has_method("get_save_blob"):
		var me_data: Variant = main_event_sys.call("get_save_blob")
		if typeof(me_data) == TYPE_DICTIONARY:
			payload["main_event"] = me_data as Dictionary

	return payload

## Restores game state from a save Dictionary. Loads data into all connected systems in proper
## order: Equipment FIRST (for bracelet capacity), then Sigils, then other systems. Handles both
## legacy and v2 sigil snapshot formats. Emits party_changed signal when complete.
func load(data: Dictionary) -> void:
	if data.is_empty():
		return

	# Reset all systems first to prevent data leakage from previous sessions
	reset_all_systems()

	player_name     = String(data.get("player_name", player_name))
	difficulty      = String(data.get("difficulty", difficulty))
	# Support both "creds" (new) and "money" (legacy) for backward compatibility
	creds           = int(data.get("creds", data.get("money", creds)))
	perk_points     = int(data.get("perk_points", perk_points))
	pacifist_score  = int(data.get("pacifist_score", pacifist_score))
	bloodlust_score = int(data.get("bloodlust_score", bloodlust_score))
	time_played     = float(data.get("time_played", time_played))

	party.clear()
	var party_v: Variant = data.get("party", [])
	if typeof(party_v) == TYPE_ARRAY:
		for v in (party_v as Array):
			party.append(String(v))

	bench.clear()
	var bench_v: Variant = data.get("bench", [])
	if typeof(bench_v) == TYPE_ARRAY:
		for v2 in (bench_v as Array):
			bench.append(String(v2))

	flags          = (data.get("flags", flags) as Dictionary).duplicate(true)
	index_blob     = (data.get("index", index_blob) as Dictionary).duplicate(true)

	unlocked_perks.clear()
	var perks_v: Variant = data.get("unlocked_perks", [])
	if typeof(perks_v) == TYPE_ARRAY:
		for pv in (perks_v as Array):
			unlocked_perks.append(String(pv))

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

	# Equipment MUST load before sigils so bracelet capacity is known
	var equip_v: Variant = data.get("equipment", null)
	var equip_sys: Node = get_node_or_null(EQUIP_PATH)
	if equip_sys and typeof(equip_v) == TYPE_DICTIONARY:
		if equip_sys.has_method("load"):
			equip_sys.call("load", equip_v)

	# Sigils (system blob + robust snapshot with owners/slots/xp/level/active skill)
	var sig_v: Variant = data.get("sigils", null)
	var sigil_sys: Node = get_node_or_null(SIGIL_PATH)
	if sigil_sys and typeof(sig_v) == TYPE_DICTIONARY:
		if sigil_sys.has_method("load"):
			sigil_sys.call("load", sig_v)
		elif sigil_sys.has_method("apply_save_blob"):
			sigil_sys.call("apply_save_blob", sig_v)
	var sig_snap_v: Variant = data.get("sigils_v2", null)
	if sigil_sys and typeof(sig_snap_v) == TYPE_DICTIONARY:
		_apply_sigil_snapshot(sigil_sys, sig_snap_v as Dictionary)

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
			# Deep copy dictionary metadata to prevent reference sharing between saves
			if typeof(meta_in[mkey]) == TYPE_DICTIONARY:
				set_meta(String(mkey), (meta_in[mkey] as Dictionary).duplicate(true))
			else:
				set_meta(String(mkey), meta_in[mkey])

	# Optional systems
	var cb_v: Variant = data.get("circle_bonds", null)
	var cb_sys: Node = get_node_or_null("/root/aCircleBondSystem")
	if cb_sys and typeof(cb_v) == TYPE_DICTIONARY:
		if cb_sys.has_method("load"):
			cb_sys.call("load", cb_v)

	var dorm_v: Variant = data.get("dorms", null)
	var dorm_sys: Node = get_node_or_null("/root/aDormSystem")
	if dorm_sys and typeof(dorm_v) == TYPE_DICTIONARY:
		if dorm_sys.has_method("load"):
			dorm_sys.call("load", dorm_v)

	# Equipment already loaded above (before sigils)

	var rom_v: Variant = data.get("romance", null)
	var rom_sys: Node = get_node_or_null("/root/aRomanceSystem")
	if rom_sys and typeof(rom_v) == TYPE_DICTIONARY:
		if rom_sys.has_method("load"):
			rom_sys.call("load", rom_v)

	var aff_v: Variant = data.get("affinity", null)
	var aff_sys: Node = get_node_or_null("/root/aAffinitySystem")
	if aff_sys and typeof(aff_v) == TYPE_DICTIONARY:
		if aff_sys.has_method("load"):
			aff_sys.call("load", aff_v)

	var perk_v: Variant = data.get("perk_system", null)
	var perk_sys: Node = get_node_or_null("/root/aPerkSystem")
	if perk_sys and typeof(perk_v) == TYPE_DICTIONARY:
		if perk_sys.has_method("apply_save_blob"):
			perk_sys.call("apply_save_blob", perk_v)
		elif perk_sys.has_method("load"):
			perk_sys.call("load", perk_v)

	var me_v: Variant = data.get("main_event", null)
	var me_sys: Node = get_node_or_null("/root/aMainEventSystem")
	if me_sys and typeof(me_v) == TYPE_DICTIONARY:
		if me_sys.has_method("apply_save_blob"):
			me_sys.call("apply_save_blob", me_v)
		elif me_sys.has_method("load"):
			me_sys.call("load", me_v)

	# Enforce party limits after loading (in case save had 4+ members from old MAX_PARTY_SIZE)
	_enforce_party_limits()

	emit_signal("party_changed")
	emit_signal("roster_changed")
	emit_signal("perk_points_changed", perk_points)

# ─── Sigil snapshot helpers ──────────────────────────────────
func _sigil_get_loadout(sys: Node, member: String) -> Array[String]:
	var out: Array[String] = []
	# common names
	if sys.has_method("get_loadout"):
		var v: Variant = sys.call("get_loadout", member)
		if typeof(v) == TYPE_PACKED_STRING_ARRAY:
			var psa: PackedStringArray = v
			for i in range(psa.size()):
				out.append(String(psa[i]))
		elif typeof(v) == TYPE_ARRAY:
			var arr: Array = v
			for j in range(arr.size()):
				out.append(String(arr[j]))
	elif sys.has_method("list_loadout"):
		var v2: Variant = sys.call("list_loadout", member)
		if typeof(v2) == TYPE_ARRAY:
			var arr2: Array = v2
			for k in range(arr2.size()): out.append(String(arr2[k]))
	return out

func _sigil_get_capacity(sys: Node, member: String) -> int:
	if sys.has_method("get_capacity"):
		return int(sys.call("get_capacity", member))
	if sys.has_method("get_member_capacity"):
		return int(sys.call("get_member_capacity", member))
	return 0

func _sigil_inst_level(sys: Node, inst: String) -> int:
	if sys.has_method("get_instance_level"):
		return int(sys.call("get_instance_level", inst))
	if sys.has_method("get_level"):
		return int(sys.call("get_level", inst))
	return 1

func _sigil_inst_xp(sys: Node, inst: String) -> int:
	if sys.has_method("get_instance_xp"):
		return int(sys.call("get_instance_xp", inst))
	if sys.has_method("get_xp"):
		return int(sys.call("get_xp", inst))
	return 0

func _sigil_inst_base(sys: Node, inst: String) -> String:
	if sys.has_method("get_base_from_instance"):
		return String(sys.call("get_base_from_instance", inst))
	if sys.has_method("get_instance_base"):
		return String(sys.call("get_instance_base", inst))
	if sys.has_method("get_base_id"):
		return String(sys.call("get_base_id", inst))
	return inst

func _sigil_inst_active_skill(sys: Node, inst: String) -> Dictionary:
	var out: Dictionary = {"id":"", "name":""}
	if sys.has_method("get_active_skill_id_for_instance"):
		out["id"] = String(sys.call("get_active_skill_id_for_instance", inst))
	if out["id"] == "" and sys.has_method("get_active_skill_for_instance"):
		out["id"] = String(sys.call("get_active_skill_for_instance", inst))
	if sys.has_method("get_active_skill_name_for_instance"):
		out["name"] = String(sys.call("get_active_skill_name_for_instance", inst))
	return out

func _sigil_list_free(sys: Node) -> Array[String]:
	var out: Array[String] = []
	if sys.has_method("list_free_instances"):
		var v: Variant = sys.call("list_free_instances")
		if typeof(v) == TYPE_PACKED_STRING_ARRAY:
			var psa: PackedStringArray = v
			for i in range(psa.size()):
				out.append(String(psa[i]))
		elif typeof(v) == TYPE_ARRAY:
			var arr: Array = v
			for j in range(arr.size()):
				out.append(String(arr[j]))
	return out

func _sigil_is_instance_id(sys: Node, s: String) -> bool:
	if sys.has_method("is_instance_id"):
		return bool(sys.call("is_instance_id", s))
	return false

func _sigil_find_owner(sys: Node, inst: String, fallback_loadouts: Dictionary) -> String:
	if sys.has_method("get_owner_of_instance"):
		var v: Variant = sys.call("get_owner_of_instance", inst)
		if typeof(v) == TYPE_STRING:
			return String(v)
	# fallback: scan snapshot loadouts
	for mk in fallback_loadouts.keys():
		var m: String = String(mk)
		var lv: Variant = fallback_loadouts[mk]
		if typeof(lv) == TYPE_ARRAY:
			var arr: Array = lv
			for item in arr:
				if String(item) == inst:
					return m
		elif typeof(lv) == TYPE_PACKED_STRING_ARRAY:
			var psa: PackedStringArray = lv
			for i in range(psa.size()):
				if String(psa[i]) == inst:
					return m
	return ""

func _sigil_set_owner(sys: Node, inst: String, member: String) -> void:
	if member == "":
		return
	if sys.has_method("set_owner_of_instance"):
		sys.call("set_owner_of_instance", inst, member); return
	if sys.has_method("assign_instance_to_member"):
		sys.call("assign_instance_to_member", member, inst); return
	if sys.has_method("give_instance_to_member"):
		sys.call("give_instance_to_member", member, inst); return
	if sys.has_method("transfer_instance_to_member"):
		sys.call("transfer_instance_to_member", inst, member); return
	if sys.has_method("set_owner"):
		sys.call("set_owner", inst, member)

func _sigil_find_slot_of_member_instance(sys: Node, member: String, inst: String) -> int:
	var load_arr: Array[String] = _sigil_get_loadout(sys, member)
	for i in range(load_arr.size()):
		if String(load_arr[i]) == inst:
			return i
	return -1

func _sigil_unequip_slot(sys: Node, member: String, slot_idx: int) -> void:
	if slot_idx < 0:
		return
	if sys.has_method("remove_sigil_at"):
		sys.call("remove_sigil_at", member, slot_idx)
	elif sys.has_method("unequip_slot"):
		sys.call("unequip_slot", member, slot_idx)
	elif sys.has_method("clear_slot"):
		sys.call("clear_slot", member, slot_idx)

func _sigil_equip_instance(sys: Node, member: String, slot_idx: int, inst: String) -> String:
	# Try various signatures; return the live instance id found in that slot after equip (may equal or differ)
	var live: String = ""
	# prefer explicit by instance id
	if sys.has_method("equip_into_socket"):
		sys.call("equip_into_socket", member, slot_idx, inst)
		var now: Array[String] = _sigil_get_loadout(sys, member)
		if slot_idx >= 0 and slot_idx < now.size():
			live = String(now[slot_idx])
			if live != "":
				return live
	# alt signatures
	if sys.has_method("equip_member_instance"):
		sys.call("equip_member_instance", member, inst, slot_idx)
		var now2: Array[String] = _sigil_get_loadout(sys, member)
		if slot_idx >= 0 and slot_idx < now2.size():
			live = String(now2[slot_idx])
			if live != "":
				return live
	if sys.has_method("equip_instance"):
		sys.call("equip_instance", member, inst, slot_idx)
		var now3: Array[String] = _sigil_get_loadout(sys, member)
		if slot_idx >= 0 and slot_idx < now3.size():
			live = String(now3[slot_idx])
			if live != "":
				return live
	# last resort: if system only supports base-equip path, caller should use equip_from_inventory
	return ""

func _build_sigil_snapshot(sys: Node) -> Dictionary:
	var out: Dictionary = {}
	if sys == null:
		return out

	# members = party ∪ bench ∪ hero
	var members: Array[String] = []
	var seen_mem: Dictionary = {}
	for i in range(party.size()):
		var pid: String = String(party[i])
		if not seen_mem.has(pid):
			members.append(pid)
			seen_mem[pid] = true
	for j in range(bench.size()):
		var bid: String = String(bench[j])
		if not seen_mem.has(bid):
			members.append(bid)
			seen_mem[bid] = true
	if not seen_mem.has("hero"):
		members.append("hero")

	var loadouts: Dictionary = {}
	var capacities: Dictionary = {}
	var instances: Dictionary = {}
	var owners: Dictionary = {}
	var seen_inst: Dictionary = {}

	for m in members:
		var cap: int = _sigil_get_capacity(sys, m)
		capacities[m] = cap
		var arr: Array[String] = _sigil_get_loadout(sys, m)
		loadouts[m] = arr.duplicate()
		for s in arr:
			var inst: String = String(s)
			if inst == "":
				continue
			if not seen_inst.has(inst):
				seen_inst[inst] = true
				var rec: Dictionary = {}
				rec["base"]  = _sigil_inst_base(sys, inst)
				rec["level"] = _sigil_inst_level(sys, inst)
				rec["xp"]    = _sigil_inst_xp(sys, inst)
				var act: Dictionary = _sigil_inst_active_skill(sys, inst)
				rec["active_skill_id"]   = String(act.get("id",""))
				rec["active_skill_name"] = String(act.get("name",""))
				instances[inst] = rec
				# owner
				var owner_id: String = _sigil_find_owner(sys, inst, loadouts)
				owners[inst] = owner_id

	# free inventory instances
	var free_list: Array[String] = _sigil_list_free(sys)
	for inst2 in free_list:
		var iid: String = String(inst2)
		if iid == "":
			continue
		if not seen_inst.has(iid):
			seen_inst[iid] = true
			var rec2: Dictionary = {}
			rec2["base"]  = _sigil_inst_base(sys, iid)
			rec2["level"] = _sigil_inst_level(sys, iid)
			rec2["xp"]    = _sigil_inst_xp(sys, iid)
			var act2: Dictionary = _sigil_inst_active_skill(sys, iid)
			rec2["active_skill_id"]   = String(act2.get("id",""))
			rec2["active_skill_name"] = String(act2.get("name",""))
			instances[iid] = rec2
			owners[iid] = ""  # free

	out["capacities"] = capacities
	out["loadouts"]   = loadouts
	out["instances"]  = instances
	out["owners"]     = owners
	out["free"]       = free_list.duplicate()
	return out

func _apply_sigil_snapshot(sys: Node, snap: Dictionary) -> void:
	if sys == null or snap.is_empty():
		return

	var capacities: Dictionary = (snap.get("capacities", {}) as Dictionary)
	var loadouts:   Dictionary = (snap.get("loadouts",   {}) as Dictionary)
	var instances:  Dictionary = (snap.get("instances",  {}) as Dictionary)
	var owners:     Dictionary = (snap.get("owners",     {}) as Dictionary)

	# Map original instance id -> live instance id (when recreated from base)
	var id_remap: Dictionary = {}

	# 1) ensure ownership + equip per member/slot
	for mk in loadouts.keys():
		var member: String = String(mk)
		var want_v: Variant = loadouts[mk]
		var want: Array = []
		if typeof(want_v) == TYPE_ARRAY:
			want = (want_v as Array).duplicate()
		elif typeof(want_v) == TYPE_PACKED_STRING_ARRAY:
			want = Array(want_v)

		# optional: normalize capacity (if system supports)
		if capacities.has(member) and sys.has_method("set_capacity"):
			sys.call("set_capacity", member, int(capacities[member]))

		# walk desired slots in order
		for idx in range(want.size()):
			var desired_key: String = String(want[idx])  # snapshot’s instance id (or base if older saves)
			if desired_key == "":
				_sigil_unequip_slot(sys, member, idx)
				continue

			# If this exact instance is already in the right slot for this member, keep it.
			var cur_load: Array[String] = _sigil_get_loadout(sys, member)
			if idx < cur_load.size() and String(cur_load[idx]) == desired_key:
				id_remap[desired_key] = desired_key
				continue

			# If the instance is on the same member but wrong slot → move it.
			var have_slot: int = _sigil_find_slot_of_member_instance(sys, member, desired_key)
			if have_slot >= 0 and have_slot != idx:
				# try move/swap, fallback to unequip+equip
				if sys.has_method("move_slot"):
					sys.call("move_slot", member, have_slot, idx)
				elif sys.has_method("swap_slots"):
					sys.call("swap_slots", member, have_slot, idx)
				else:
					_sigil_unequip_slot(sys, member, have_slot)
					var moved_live: String = _sigil_equip_instance(sys, member, idx, desired_key)
					if moved_live != "":
						id_remap[desired_key] = moved_live
						continue
				# verify post-move
				var post: Array[String] = _sigil_get_loadout(sys, member)
				if idx < post.size() and String(post[idx]) != "":
					id_remap[desired_key] = String(post[idx])
					continue

			# If the instance belongs to someone else, take ownership back.
			var owner_id: String = ""
			if owners.has(desired_key):
				owner_id = String(owners[desired_key])
			else:
				owner_id = _sigil_find_owner(sys, desired_key, loadouts)
			if owner_id != "" and owner_id != member:
				_sigil_set_owner(sys, desired_key, member)

			# Try to equip this exact instance id
			var live_id: String = _sigil_equip_instance(sys, member, idx, desired_key)
			if live_id == "":
				# Fallback: equip from base id, then map new instance id
				var base_id: String = desired_key
				if instances.has(desired_key):
					var rec: Dictionary = instances[desired_key] as Dictionary
					base_id = String(rec.get("base", desired_key))
				if sys.has_method("equip_from_inventory"):
					var ok: bool = bool(sys.call("equip_from_inventory", member, idx, base_id))
					if ok:
						var now: Array[String] = _sigil_get_loadout(sys, member)
						if idx < now.size():
							live_id = String(now[idx])
			if live_id != "":
				id_remap[desired_key] = live_id
			else:
				# give up on this slot silently (keeps game running)
				_sigil_unequip_slot(sys, member, idx)

		# let system react if needed
		if sys.has_method("on_bracelet_changed"):
			sys.call("on_bracelet_changed", member)

	# 2) apply per-instance XP/level and active-skill to whatever live ids we ended with
	for key in instances.keys():
		var rec2: Dictionary = instances[key] as Dictionary
		var live: String = String(id_remap.get(key, ""))
		if live == "":
			# maybe the instance id survived intact
			live = String(key)
		if live == "":
			continue
		var want_lvl: int = int(rec2.get("level", 1))
		var want_xp:  int = int(rec2.get("xp", 0))
		if sys.has_method("set_instance_level"):
			sys.call("set_instance_level", live, want_lvl)
		if sys.has_method("set_instance_xp"):
			sys.call("set_instance_xp", live, want_xp)
		var sk_id: String = String(rec2.get("active_skill_id",""))
		var sk_nm: String = String(rec2.get("active_skill_name",""))
		if sk_id != "" and sys.has_method("set_active_skill_for_instance"):
			sys.call("set_active_skill_for_instance", live, sk_id)
		elif sk_nm != "" and sys.has_method("set_active_skill_for_instance_by_name"):
			sys.call("set_active_skill_for_instance_by_name", live, sk_nm)

	# 3) emit loadout-changed per member if the system exposes it
	if sys.has_signal("loadout_changed"):
		for mk2 in loadouts.keys():
			sys.emit_signal("loadout_changed", String(mk2))

# ─── UI Bridge Methods (optional helpers) ────────────────────
## Saves the current game state to a numbered slot via SaveLoad system. Adds scene name
## to the save data. Label is generated by SaveLoad from payload data.
## Returns true if save successful.
func save_to_slot(slot: int) -> bool:
	var payload: Dictionary = save()
	payload["scene"] = "Main"
	# Note: Label is generated by SaveLoad._label_from_payload() from player name and calendar data
	var save_sys: Node = get_node_or_null(SAVELOAD_PATH)
	if save_sys and save_sys.has_method("save_game"):
		return bool(save_sys.call("save_game", slot, payload))
	else:
		push_error("[GameState] aSaveLoad system not found! Cannot save.")
		return false

## UI bridge method for loading a save. Calls load() with the provided payload Dictionary.
## Shows warning if payload is empty.
func apply_loaded_save(payload: Dictionary) -> void:
	if payload.is_empty():
		push_warning("[GameState] Attempted to load empty save data.")
		return
	self.load(payload)
	#save
