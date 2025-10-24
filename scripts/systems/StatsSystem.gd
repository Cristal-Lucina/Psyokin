## ═══════════════════════════════════════════════════════════════════════════
## StatsSystem - Hero & Party Member Stat Progression Manager
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Manages stat progression for the hero and all party members using an SXP
##   (Stat Experience Points) system with daily automatic gains, fatigue
##   mechanics, and level-up thresholds.
##
## RESPONSIBILITIES:
##   • 5 core stats: BRW (Brawn), MND (Mind), TPO (Tempo), VTL (Vital), FCS (Focus)
##   • SXP accumulation and level calculation per stat
##   • Daily Stat Increment (DSI) system - automatic gains each day
##   • Fatigue system - halves gains after 60 SXP/week per stat
##   • Hero level & XP tracking
##   • Ally individual progression (separate SXP pools per member)
##   • Weekly reset for fatigue counters
##   • CSV-based party member definitions
##   • Save/load stat state
##
## STAT PROGRESSION:
##   Each stat has:
##   • Base level (1-10+)
##   • SXP pool (stat experience points)
##   • Weekly SXP counter (for fatigue)
##   • DSI (Daily Stat Increment) - auto-gains per day
##
## SXP THRESHOLDS (bonus levels):
##   [0, 59, 122, 189, 260, 336, 416, 500, 588, 680, 943]
##   Level = base + bonus from SXP thresholds
##
## FATIGUE SYSTEM:
##   Once a stat gains 60+ SXP in the current week, further gains are halved.
##   Resets each Sunday.
##
## DAILY STAT INCREMENT (DSI):
##   Default tenths per day:
##   • BRW: 10 (1.0 SXP/day)
##   • MND: 20 (2.0 SXP/day)
##   • TPO: 30 (3.0 SXP/day)
##   • VTL: 10 (1.0 SXP/day)
##   • FCS: 30 (3.0 SXP/day)
##
## CONNECTED SYSTEMS (Autoloads):
##   • CalendarSystem - Daily/weekly triggers for DSI and fatigue reset
##   • PartySystem - Member roster
##   • GameState - Save/load coordination, hero stat picks
##   • CSVLoader - Party member definitions (base stats, names, etc.)
##
## CSV DATA SOURCES:
##   • res://data/actors/party.csv - Member base stats, display names
##
## KEY METHODS:
##   • get_stat(stat_code: String) -> int - Get hero stat level
##   • get_member_stat(member_id, stat_code) -> int - Get member stat level
##   • add_hero_sxp(stat_code, amount) - Grant SXP to hero stat
##   • on_day_advanced() - Apply daily DSI to all stats
##   • on_week_reset() - Reset fatigue counters
##   • compute_pools(member_id) -> Dictionary - Calculate HP/MP pools
##
## ═══════════════════════════════════════════════════════════════════════════

extends Node
class_name StatsSystem

signal stat_leveled_up(stat_name: String, new_level: int)
signal stats_changed
signal perk_points_changed(new_value: int)

# ───────────────────────── Config / Keys ─────────────────────────
const CAL_PATH: String   = "/root/aCalendarSystem"
const PARTY_PATH: String = "/root/aPartySystem"
const GS_PATH: String    = "/root/aGameState"
const CSV_PATH: String   = "/root/aCSVLoader"

const PARTY_CSV: String = "res://data/actors/party.csv"
const STATS_KEYS: Array[String] = ["BRW", "MND", "TPO", "VTL", "FCS"]

# Default daily stat increment (DSI) table in tenths (e.g., 10 = 1.0 SXP/day)
const DSI_DEFAULT_TENTHS: Dictionary = {"BRW": 10, "MND": 20, "TPO": 30, "VTL": 10, "FCS": 30}

# Fatigue: once a stat gains this much SXP in the current week, further gains are halved
const FATIGUE_THRESHOLD_PER_WEEK: int = 60

# ───────────────────────── State ─────────────────────────
var stat_sxp:   Dictionary = {"BRW": 0, "MND": 0, "TPO": 0, "VTL": 0, "FCS": 0}
var stat_level: Dictionary = {"BRW": 1, "MND": 1, "TPO": 1, "VTL": 1, "FCS": 1}

# Legacy counter (kept for compatibility; not used by fatigue)
var weekly_actions: Dictionary = {"BRW": 0, "MND": 0, "TPO": 0, "VTL": 0, "FCS": 0}

# Hero progression
var hero_level: int = 1
var hero_xp: int = 0
var hero_weekly_sxp: Dictionary = {"BRW":0,"MND":0,"TPO":0,"VTL":0,"FCS":0} # drives fatigue for hero

# Ally progression
var char_xp: Dictionary = {}  # member_id -> leftover XP pool
# member_id -> {label, char_level, start{}, sxp{}, tenths{}, dsi_tenths{}, weekly_sxp{}}
var _party_progress: Dictionary = {}

# CSV caches (party definitions)
var _csv_loaded_once: bool = false
var _csv_by_id: Dictionary = {}
var _name_to_id: Dictionary = {}

# SXP level thresholds (index == bonus levels unlocked)
var sxp_thresholds: Array[int] = [0, 59, 122, 189, 260, 336, 416, 500, 588, 680, 943]

# Pointers
var _cal: Node = null
var _gs: Node = null
var _party: Node = null
var _csv: Node = null

# ───────────────────────── Lifecycle ─────────────────────────
## Initializes the StatsSystem, connecting to calendar/party signals and loading party CSV data
func _ready() -> void:
	_cal = get_node_or_null(CAL_PATH)
	if _cal != null and _cal.has_signal("day_advanced"):
		_cal.connect("day_advanced", Callable(self, "_on_day_advanced"))
	if _cal != null and _cal.has_signal("week_reset"):
		_cal.connect("week_reset", Callable(self, "_on_week_reset"))

	_gs = get_node_or_null(GS_PATH)
	_party = get_node_or_null(PARTY_PATH)

	for src in [_gs, _party]:
		if src == null:
			continue
		for sig in ["party_changed", "active_changed", "roster_changed", "changed"]:
			if src.has_signal(sig) and not src.is_connected(sig, Callable(self, "_on_party_changed")):
				src.connect(sig, Callable(self, "_on_party_changed"))

	_csv = get_node_or_null(CSV_PATH)
	_load_party_csv_cache()
	_seed_known_members()

	if _gs != null and _gs.has_signal("perk_points_changed"):
		_gs.connect("perk_points_changed", Callable(self, "_on_perk_points_changed"))

## Compatibility method that allows external code to treat StatsSystem like a Dictionary without crashing
func has(prop: String) -> bool:
	var v: Variant = get(prop)
	return v != null

# ───────────────────────── Helpers ─────────────────────────
## Resolves a member name or ID to a canonical ID. Converts "hero" name to "hero" ID, and member names to IDs from CSV
func _resolve_id(name_in: String) -> String:
	var want: String = String(name_in).strip_edges().to_lower()
	if _gs != null:
		var pn_v: Variant = _gs.get("player_name")
		if typeof(pn_v) == TYPE_STRING and String(pn_v).strip_edges().to_lower() == want:
			return "hero"
	if _name_to_id.has(want):
		return String(_name_to_id[want])
	return name_in

## Safely converts any Variant to an integer (handles int, float, string types)
func _to_int(value: Variant) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return int(value)
	if typeof(value) == TYPE_STRING:
		return String(value).to_int()
	return 0

## Calculates maximum HP from level and VTL stat. Formula: 150 + (VTL × Level × 6)
func compute_max_hp(level: int, vtl: int) -> int:
	return 150 + (max(1, vtl) * max(1, level) * 6)

## Calculates maximum MP from level and FCS stat. Formula: 20 + (FCS × Level × 1.5)
func compute_max_mp(level: int, fcs: int) -> int:
	return 20 + int(round(float(max(1, fcs)) * float(max(1, level)) * 1.5))

## Preserves HP/MP percentages after leveling up
## Called after character level or stat level increases to maintain HP/MP percentages
func _preserve_hp_mp_percentages(member_id: String, old_level: int = -1, old_vtl: int = -1, old_fcs: int = -1) -> void:
	var pid: String = _resolve_id(member_id)

	# Get GameState and CombatProfileSystem
	var gs: Node = get_node_or_null(GS_PATH)
	var cps: Node = get_node_or_null("/root/aCombatProfileSystem")

	if not gs or not cps:
		return

	# Get current HP/MP from CombatProfileSystem
	if not cps.has_method("get_profile"):
		return

	var profile_v: Variant = cps.call("get_profile", pid)
	if typeof(profile_v) != TYPE_DICTIONARY:
		return

	var profile: Dictionary = profile_v
	var current_hp: int = int(profile.get("hp", -1))
	var current_mp: int = int(profile.get("mp", -1))

	# Get NEW stats (after level/stat increase)
	var new_level: int = get_member_level(pid)
	var new_vtl: int = get_member_stat_level(pid, "VTL")
	var new_fcs: int = get_member_stat_level(pid, "FCS")

	# Use OLD stats passed as parameters, or fall back to current stats (no change scenario)
	var old_level_actual: int = old_level if old_level > 0 else new_level
	var old_vtl_actual: int = old_vtl if old_vtl > 0 else new_vtl
	var old_fcs_actual: int = old_fcs if old_fcs > 0 else new_fcs

	# Calculate OLD max HP/MP based on OLD stats
	var old_max_hp: int = compute_max_hp(old_level_actual, old_vtl_actual)
	var old_max_mp: int = compute_max_mp(old_level_actual, old_fcs_actual)

	# Calculate NEW max HP/MP based on NEW stats
	var new_max_hp: int = compute_max_hp(new_level, new_vtl)
	var new_max_mp: int = compute_max_mp(new_level, new_fcs)

	# Skip if no change in max values
	if old_max_hp == new_max_hp and old_max_mp == new_max_mp:
		return

	# Skip if no valid data
	if old_max_hp <= 0 or old_max_mp <= 0:
		return

	# Calculate current percentages based on OLD max values
	var hp_percentage: float = float(current_hp) / float(old_max_hp)
	var mp_percentage: float = float(current_mp) / float(old_max_mp)

	# Calculate new current values to preserve percentages
	var new_current_hp: int = int(round(hp_percentage * float(new_max_hp)))
	var new_current_mp: int = int(round(mp_percentage * float(new_max_mp)))

	# Clamp to valid ranges
	new_current_hp = clamp(new_current_hp, 0, new_max_hp)
	new_current_mp = clamp(new_current_mp, 0, new_max_mp)

	# Update GameState member_data
	if gs.has_method("get"):
		var member_data_v: Variant = gs.get("member_data")
		if typeof(member_data_v) == TYPE_DICTIONARY:
			var member_data: Dictionary = member_data_v
			if member_data.has(pid):
				var data: Dictionary = member_data[pid]
				data["hp"] = new_current_hp
				data["mp"] = new_current_mp

	# Update CombatProfileSystem _party_meta directly
	if cps.has_method("get"):
		var party_meta_v: Variant = cps.get("_party_meta")
		if typeof(party_meta_v) == TYPE_DICTIONARY:
			var party_meta: Dictionary = party_meta_v
			if not party_meta.has(pid):
				party_meta[pid] = {}
			var meta: Dictionary = party_meta[pid]
			meta["hp"] = new_current_hp
			meta["mp"] = new_current_mp

	# Force profile refresh to recalculate max values
	if cps.has_method("refresh_member"):
		cps.call("refresh_member", pid)

# ───────────────────────── Weekday helpers ─────────────────────────
## Calculates day of week using Sakamoto's algorithm (Gregorian calendar). Returns 0=Monday through 6=Sunday
func _dow_index_gregorian(y: int, m: int, d: int) -> int:
	var t: PackedInt32Array = PackedInt32Array([0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4])
	var yy: int = y
	if m < 3:
		yy -= 1

	var div4: int   = int(floor(float(yy) / 4.0))
	var div100: int = int(floor(float(yy) / 100.0))
	var div400: int = int(floor(float(yy) / 400.0))

	var sun0: int = (yy + div4 - div100 + div400 + t[m - 1] + d) % 7  # 0=Sun..6=Sat
	var mon0: int = (sun0 + 6) % 7                                    # shift so 0=Mon..6=Sun
	return mon0

## Extracts year/month/day from date Dictionary and returns day_index (0-6) and day_name
func _derive_day_info(date: Dictionary) -> Dictionary:
	var y: int = int(date.get("year", 0))
	var m: int = int(date.get("month", 0))
	var d: int = int(date.get("day", 0))
	if y <= 0 or m <= 0 or d <= 0:
		return {"ok": false}
	var idx: int = _dow_index_gregorian(y, m, d)  # 0=Mon..6=Sun
	var names: Array[String] = ["monday","tuesday","wednesday","thursday","friday","saturday","sunday"]
	return {"ok": true, "day_index": idx, "day_name": names[idx]}

# ───────────────────────── Calendar hooks ─────────────────────────
## Called when CalendarSystem advances a day. Applies daily DSI to all party members and resets fatigue on Mondays
func _on_day_advanced(date: Dictionary) -> void:
	_seed_known_members()

	# Compute weekday from supplied Y/M/D (no reliance on CalendarSystem names).
	var info: Dictionary = _derive_day_info(date)
	var is_monday: bool = info.get("ok", false) and int(info.get("day_index", 9)) == 0

	# Fallbacks to CalendarSystem helpers if available
	if not is_monday and _cal != null:
		if _cal.has_method("get_day_name"):
			var nm: String = String(_cal.call("get_day_name")).strip_edges().to_lower()
			is_monday = (nm == "monday" or nm.begins_with("mon"))
		elif _cal.has_method("get_day_of_week"):
			var dow_v: Variant = _cal.call("get_day_of_week")
			if typeof(dow_v) in [TYPE_INT, TYPE_FLOAT]:
				is_monday = (int(dow_v) == 1) # common convention

	# Debug: show what we computed
	print("[StatsSystem][MonCheck] payload=", date)
	if info.get("ok", false):
		print("[StatsSystem][MonCheck] computed day=", String(info["day_name"]), " (idx=", int(info["day_index"]), ")")

	# Reset fatigue trackers on Mondays only (stats/levels are untouched).
	if is_monday:
		print("[StatsSystem] Monday detected → resetting weekly fatigue (hero + allies).")
		reset_week()

	# Apply one day of passive DSI to ALL known non-hero members (even if not active).
	for pid_any in _party_progress.keys():
		var pid: String = String(pid_any)
		if pid == "hero":
			continue
		_apply_daily_dsi(pid)

	emit_signal("stats_changed")

## Called when CalendarSystem triggers week_reset signal (usually Sunday->Monday). Resets fatigue counters
func _on_week_reset() -> void:
	reset_week()

## Called when PartySystem or GameState signals party roster changes. Re-seeds member progress data
func _on_party_changed(_a: Variant = null, _b: Variant = null) -> void:
	_seed_known_members()
	emit_signal("stats_changed")

## Forwards perk_points_changed signal from GameState to any listeners
func _on_perk_points_changed(new_value: int) -> void:
	emit_signal("perk_points_changed", new_value)

# ───────────────────────── CSV cache ─────────────────────────
## Loads party member definitions from CSV (actor_id, name, base stats, DSI values). Only runs once
func _load_party_csv_cache() -> void:
	if _csv_loaded_once:
		return
	_csv_by_id.clear()
	_name_to_id.clear()
	var loader: Node = get_node_or_null(CSV_PATH)
	if loader != null and loader.has_method("load_csv"):
		var defs_v: Variant = loader.call("load_csv", PARTY_CSV, "actor_id")
		if typeof(defs_v) == TYPE_DICTIONARY:
			var defs: Dictionary = defs_v
			for id_any in defs.keys():
				var rid: String = String(id_any)
				var row: Dictionary = defs[rid] as Dictionary
				_csv_by_id[rid] = row
				var name_val: Variant = row.get("name", "")
				if typeof(name_val) == TYPE_STRING:
					var key: String = String(name_val).strip_edges().to_lower()
					if key != "":
						_name_to_id[key] = rid
			_csv_loaded_once = true

# ───────────────────────── Progress seeds ─────────────────────────
## Ensures all known members (from CSV, roster, or previous progress) have initialized progress data
func _seed_known_members() -> void:
	# Always include everyone from the CSV (non-hero).
	for id_any in _csv_by_id.keys():
		var pid: String = String(id_any)
		if pid != "hero":
			_ensure_progress(pid)

	# Plus anyone we’ve already seen or who appears in progress.
	for pid_any in _party_progress.keys():
		var pid2: String = String(pid_any)
		if pid2 != "hero":
			_ensure_progress(pid2)

	# Plus active party / roster (harmless duplicates).
	var ids: Array = []
	if _gs != null and _gs.has_method("get_active_party_ids"):
		var v: Variant = _gs.call("get_active_party_ids")
		if typeof(v) == TYPE_ARRAY:
			ids = v as Array
	for id_any in ids:
		var pid3: String = String(id_any)
		if pid3 != "hero":
			_ensure_progress(pid3)

## Creates progress tracking data for a member if it doesn't exist. Returns the member's progress Dictionary
func _ensure_progress(pid: String) -> Dictionary:
	if _party_progress.has(pid):
		return _party_progress[pid] as Dictionary

	var row: Dictionary = _csv_by_id.get(pid, {}) as Dictionary
	var label: String = (String(row["name"]) if row.has("name") else pid.capitalize())

	var clvl: int = _to_int(row.get("level_start", row.get("level", 1)))
	clvl = max(1, clvl)

	var start: Dictionary = {}
	for stat in STATS_KEYS:
		var key: String = "start_" + stat.to_lower()
		start[stat] = _to_int(row.get(key, 1))

	var dsi: Dictionary = DSI_DEFAULT_TENTHS.duplicate()
	if not row.is_empty():
		for stat in STATS_KEYS:
			var dkey: String = "dsi_" + stat.to_lower()
			if row.has(dkey):
				var val_v: Variant = row[dkey]
				var tenths: int = 0
				if typeof(val_v) == TYPE_INT or typeof(val_v) == TYPE_FLOAT:
					tenths = int(round(float(val_v) * 10.0))
				elif typeof(val_v) == TYPE_STRING:
					var f_val: float = String(val_v).to_float()
					tenths = int(round(f_val * 10.0))
				dsi[stat] = tenths

	_party_progress[pid] = {
		"label": label,
		"char_level": clvl,
		"start": start,
		"sxp": {"BRW":0,"MND":0,"TPO":0,"VTL":0,"FCS":0},
		"tenths": {"BRW":0,"MND":0,"TPO":0,"VTL":0,"FCS":0},
		"dsi_tenths": dsi,
		"weekly_sxp": {"BRW":0,"MND":0,"TPO":0,"VTL":0,"FCS":0}
	}
	if not char_xp.has(pid):
		char_xp[pid] = 0
	return _party_progress[pid] as Dictionary

# ───────────────────────── Daily DSI (allies) ─────────────────────────
## Applies one day of Daily Stat Increment (DSI) to a party member. Respects fatigue threshold (halves gains after 60 SXP/week)
func _apply_daily_dsi(pid: String) -> void:
	var info: Dictionary = _ensure_progress(pid)
	var dsi: Dictionary = info.get("dsi_tenths", {}) as Dictionary
	var tenths: Dictionary = info.get("tenths", {}) as Dictionary
	var sxp: Dictionary = info.get("sxp", {}) as Dictionary
	var weekly: Dictionary = info.get("weekly_sxp", {}) as Dictionary

	for s in STATS_KEYS:
		var key: String = String(s)
		var before_t: int = int(tenths.get(key, 0))
		var add_t: int = int(dsi.get(key, 0))
		var t_val: int = before_t + add_t

		var whole: int = int(floor(float(t_val) / 10.0))
		tenths[key] = t_val - whole * 10

		if whole > 0:
			var fatigued_now: bool = int(weekly.get(key, 0)) >= FATIGUE_THRESHOLD_PER_WEEK
			var applied: int = whole
			if fatigued_now:
				applied = max(1, int(floor(float(whole) * 0.5)))
			sxp[key] = int(sxp.get(key, 0)) + applied
			weekly[key] = int(weekly.get(key, 0)) + applied

	info["tenths"] = tenths
	info["sxp"] = sxp
	info["weekly_sxp"] = weekly
	_party_progress[pid] = info

# ───────────────────────── SXP → bonus levels (allies) ─────────────────────────
## Converts total SXP to bonus stat levels using threshold table. Returns number of bonus levels earned
func _bonus_levels_from_sxp(sxp: int) -> int:
	for i in range(sxp_thresholds.size() - 1, -1, -1):
		if sxp >= int(sxp_thresholds[i]):
			return i
	return 0

# ───────────────────────── Hero/Member XP ─────────────────────────
## Calculates XP required to reach next level. Formula: 120 + 30×level + 6×level²
func _xp_to_next_level(level: int) -> int:
	return 120 + 30 * level + 6 * level * level

## Grants XP to a member (hero or ally), processing level-ups and perk point gains. Emits stats_changed on level-up
func add_xp(member_id: String, amount: int) -> void:
	if amount <= 0:
		return

	var pid: String = _resolve_id(member_id)
	var level_before: int = get_member_level(pid)

	var pool: int = 0
	if pid == "hero":
		pool = hero_xp + amount
	else:
		pool = int(char_xp.get(pid, 0)) + amount

	var level: int = level_before
	while level < 99 and pool >= _xp_to_next_level(level):
		pool -= _xp_to_next_level(level)
		level += 1

	var gained_levels: int = level - level_before
	if gained_levels > 0:
		if pid == "hero":
			hero_level = level
		else:
			var info: Dictionary = _ensure_progress(pid)
			info["char_level"] = level
			_party_progress[pid] = info

		# Perk points: +1 per 4 hero levels crossed (3,6,9,...)
		if pid == "hero":
			var before_bucket: int = int(floor(float(level_before) / 4.0))
			var after_bucket: int  = int(floor(float(level) / 4.0))
			var delta_pp: int = max(0, after_bucket - before_bucket)
			if delta_pp > 0:
				add_perk_points(delta_pp)

		# Preserve HP/MP percentages after level up
		# Pass old level so we can calculate old max HP/MP correctly
		_preserve_hp_mp_percentages(pid, level_before)

		emit_signal("stats_changed")

	if pid == "hero":
		hero_xp = 0 if level >= 99 else pool
	else:
		char_xp[pid] = 0 if level >= 99 else pool

## Returns the current level of a member (hero or ally)
func get_member_level(member_id: String) -> int:
	var pid: String = _resolve_id(member_id)
	if pid == "hero":
		return hero_level
	var info: Dictionary = _ensure_progress(pid)
	return int(info.get("char_level", 1))

## Sets the hero's level to a specific value (clamped 1-99). Emits stats_changed
func set_hero_level(new_level: int) -> void:
	hero_level = clamp(new_level, 1, 99)
	emit_signal("stats_changed")

## Returns the total level for a specific stat of a member (base + SXP bonus levels)
func get_member_stat_level(member_id: String, stat: String) -> int:
	var pid: String = _resolve_id(member_id)
	if pid == "hero":
		return int(stat_level.get(stat, 1))
	var info: Dictionary = _ensure_progress(pid)
	var base: int = int((info.get("start", {}) as Dictionary).get(stat, 1))
	var total_xp: int = int((info.get("sxp", {}) as Dictionary).get(stat, 0))
	var bonus: int = _bonus_levels_from_sxp(total_xp)
	return base + bonus

## Returns the display name for a member (from CSV or capitalized ID). For hero, returns player_name from GameState
func get_member_display_name(member_id: String) -> String:
	var pid: String = _resolve_id(member_id)
	if pid == "hero":
		# Check for player's custom name from character creation
		if _gs != null:
			var pn_v: Variant = _gs.get("player_name")
			if typeof(pn_v) == TYPE_STRING and String(pn_v).strip_edges() != "":
				return String(pn_v)
		return "Hero"  # Fallback if no custom name set
	var info: Dictionary = _ensure_progress(pid)
	var label_v: Variant = info.get("label", "")
	if typeof(label_v) == TYPE_STRING and String(label_v).strip_edges() != "":
		return String(label_v)
	return pid.capitalize()

# ───────────────────────── Perk points passthrough ─────────────────────────
## Internal helper to emit perk_points_changed signal with current value from GameState
func _emit_pp_changed() -> void:
	emit_signal("perk_points_changed", get_perk_points())

## Returns the current perk points value from GameState
func get_perk_points() -> int:
	var gs_node: Node = get_node_or_null(GS_PATH)
	if gs_node != null:
		var v: Variant = gs_node.get("perk_points")
		if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
			return int(v)
	return 0

## Adds perk points to GameState (can be negative to subtract). Emits perk_points_changed signal
func add_perk_points(points: int) -> void:
	if points == 0:
		return
	var gs_node: Node = get_node_or_null(GS_PATH)
	if gs_node != null and gs_node.has_method("add_perk_points"):
		gs_node.call("add_perk_points", points)
	else:
		# fallback if GS exposes a raw field only
		if gs_node != null:
			var cur_v: Variant = gs_node.get("perk_points")
			var cur: int = (int(cur_v) if typeof(cur_v) in [TYPE_INT, TYPE_FLOAT] else 0)
			if gs_node.has_method("set"):
				gs_node.set("perk_points", max(0, cur + points))
	_emit_pp_changed()

## Spends up to the specified amount of perk points. Returns the actual number spent (limited by available points)
func spend_perk_point(amount: int) -> int:
	if amount <= 0:
		return 0
	var gs_node: Node = get_node_or_null(GS_PATH)
	if gs_node != null:
		var cur_v: Variant = gs_node.get("perk_points")
		var current: int = (int(cur_v) if typeof(cur_v) == TYPE_INT or typeof(cur_v) == TYPE_FLOAT else 0)
		if current <= 0:
			return 0
		var to_spend: int = min(current, amount)
		if gs_node.has_method("add_perk_points"):
			gs_node.call("add_perk_points", -to_spend)
		elif gs_node.has_method("set"):
			gs_node.set("perk_points", max(0, current - to_spend))
		_emit_pp_changed()
		return to_spend
	return 0

# ───────────────────────── Stat views ─────────────────────────
## Returns the hero's current level for a specific stat (e.g., "BRW", "MND")
func get_stat(stat: String) -> int:
	return int(stat_level.get(stat, 1))

## Checks if a member's stat is fatigued (has gained 60+ SXP this week, causing halved gains)
func is_fatigued(stat: String, member_id: String = "hero") -> bool:
	var s: String = String(stat).strip_edges().to_upper()
	if member_id == "hero":
		return int(hero_weekly_sxp.get(s, 0)) >= FATIGUE_THRESHOLD_PER_WEEK
	var info: Dictionary = _ensure_progress(_resolve_id(member_id))
	var w: Dictionary = info.get("weekly_sxp", {}) as Dictionary
	return int(w.get(s, 0)) >= FATIGUE_THRESHOLD_PER_WEEK

## Returns an array of stat keys in canonical order: ["BRW", "MND", "TPO", "VTL", "FCS"]
func get_stats_order() -> Array[String]:
	return STATS_KEYS.duplicate()

## Converts a stat key to its display name (e.g., "BRW" -> "Brawn")
func get_stat_display_name(id_str: String) -> String:
	var s: String = String(id_str)
	match s:
		"BRW": return "Brawn"
		"MND": return "Mind"
		"TPO": return "Tempo"
		"VTL": return "Vitality"
		"FCS": return "Focus"
		_:     return s

## Returns a Dictionary with all hero stats containing level, SXP, weekly SXP, and fatigue status for each stat
func get_stats_dict() -> Dictionary:
	var out: Dictionary = {}
	for s in STATS_KEYS:
		var total_sxp: int = int(stat_sxp.get(s, 0))
		var weekly_amt: int = int(hero_weekly_sxp.get(s, 0))
		var fatigued_b: bool = weekly_amt >= FATIGUE_THRESHOLD_PER_WEEK
		out[s] = {
			"level":    int(stat_level.get(s, 1)),
			"sxp":      total_sxp,
			"weekly":   weekly_amt,
			"fatigued": fatigued_b,
			"fatigue":  weekly_amt   # legacy numeric alias for old UIs
		}
	return out

## Alias for get_stats_dict(). Returns hero stats Dictionary
func to_dict() -> Dictionary:
	return get_stats_dict()

## Returns the hero's total accumulated SXP for a specific stat
func get_stat_sxp(stat: String) -> int:
	return int(stat_sxp.get(stat, 0))

## Returns the legacy weekly_actions Dictionary (kept for compatibility, not used by fatigue system)
func get_weekly_actions_dict() -> Dictionary:
	return weekly_actions.duplicate()

# ───────────────────────── Hero SXP gain (fatigue-aware) ───────────────────────
## Grants SXP to hero's stat, applying fatigue rules (halves gains after 60 SXP/week). Returns actual SXP gained. Emits stat_leveled_up and stats_changed
func add_sxp(stat: String, base_amount: int) -> int:
	var k: String = String(stat).strip_edges().to_upper()
	if not stat_sxp.has(k):
		push_error("StatsSystem: unknown stat '%s'" % k)
		return 0
	if base_amount <= 0:
		return 0

	var used_this_week: int = int(hero_weekly_sxp.get(k, 0))
	var fatigued_now: bool = used_this_week >= FATIGUE_THRESHOLD_PER_WEEK

	var gain: int = base_amount
	if fatigued_now:
		gain = max(1, int(floor(float(base_amount) * 0.5)))

	# Track + apply
	hero_weekly_sxp[k] = used_this_week + gain
	stat_sxp[k] = int(stat_sxp.get(k, 0)) + gain

	# Level check
	var level_before: int = int(stat_level.get(k, 1))
	var level: int = level_before
	while level <= sxp_thresholds.size() and int(stat_sxp[k]) >= int(sxp_thresholds[level - 1]):
		level += 1
		stat_level[k] = level
		emit_signal("stat_leveled_up", k, level)

	# Preserve HP/MP percentages if VTL or FCS leveled up
	if level > level_before and (k == "VTL" or k == "FCS"):
		# Pass old VTL or FCS level so we can calculate old max HP/MP correctly
		if k == "VTL":
			_preserve_hp_mp_percentages("hero", -1, level_before, -1)
		elif k == "FCS":
			_preserve_hp_mp_percentages("hero", -1, -1, level_before)

	emit_signal("stats_changed")
	return gain

# ───────────────────────── Member SXP (hero or ally) ──────────────────────────
## Grants SXP to any member's stat (hero or ally), applying fatigue rules. Returns actual SXP gained. Emits stats_changed
func add_sxp_to_member(member_id: String, stat: String, base_amount: int) -> int:
	if base_amount <= 0:
		return 0
	var pid: String = _resolve_id(member_id)
	var k: String = String(stat).strip_edges().to_upper()

	if pid == "hero":
		return add_sxp(k, base_amount)

	var info: Dictionary = _ensure_progress(pid)
	var sxp: Dictionary = info.get("sxp", {}) as Dictionary
	var weekly: Dictionary = info.get("weekly_sxp", {}) as Dictionary

	var used_this_week: int = int(weekly.get(k, 0))
	var fatigued_now: bool = used_this_week >= FATIGUE_THRESHOLD_PER_WEEK

	var gain: int = base_amount
	if fatigued_now:
		gain = max(1, int(floor(float(base_amount) * 0.5)))

	var sxp_before: int = int(sxp.get(k, 0))
	sxp[k] = sxp_before + gain
	weekly[k] = used_this_week + gain

	info["sxp"] = sxp
	info["weekly_sxp"] = weekly
	_party_progress[pid] = info

	# Preserve HP/MP percentages if VTL or FCS gained SXP (stat level may have changed)
	if gain > 0 and (k == "VTL" or k == "FCS"):
		var level_before: int = _bonus_levels_from_sxp(sxp_before)
		var level_after: int = _bonus_levels_from_sxp(int(sxp[k]))
		if level_after > level_before:
			# Pass old VTL or FCS level so we can calculate old max HP/MP correctly
			# Get current stat level and subtract the gained levels to get old level
			var current_stat_level: int = get_member_stat_level(pid, k)
			var levels_gained: int = level_after - level_before
			var old_stat_level: int = current_stat_level - levels_gained
			if k == "VTL":
				_preserve_hp_mp_percentages(pid, -1, old_stat_level, -1)
			elif k == "FCS":
				_preserve_hp_mp_percentages(pid, -1, -1, old_stat_level)

	emit_signal("stats_changed")
	return gain

## Legacy alias for add_sxp_to_member(). Grants SXP to a member's stat
func add_member_sxp(member_id: String, stat: String, amount: int) -> int:
	return add_sxp_to_member(member_id, stat, amount)

## Legacy alias for add_sxp_to_member(). Grants SXP to a member's stat
func add_stat_xp_to_member(member_id: String, stat: String, amount: int) -> int:
	return add_sxp_to_member(member_id, stat, amount)

# ───────────────────────── Week reset ─────────────────────────
## Resets weekly fatigue counters for hero and all allies (called every Monday). Emits stats_changed
func reset_week() -> void:
	# Legacy counter (harmless to clear)
	for key in weekly_actions.keys():
		weekly_actions[key] = 0

	# Hero fatigue tracker
	for k in hero_weekly_sxp.keys():
		hero_weekly_sxp[k] = 0

	# Allies fatigue trackers
	for pid_any in _party_progress.keys():
		var pid: String = String(pid_any)
		var info: Dictionary = _ensure_progress(pid)
		var w: Dictionary = info.get("weekly_sxp", {}) as Dictionary
		for s in STATS_KEYS:
			w[s] = 0
		info["weekly_sxp"] = w
		_party_progress[pid] = info

	emit_signal("stats_changed")

# ───────────────────────── Creation + Save/Load ─────────────────────────
## Applies stat boosts from character creation (increments stat_level for each pick). Emits stats_changed
func apply_creation_boosts(picks: Array) -> void:
	for p in picks:
		var k: String = String(p)
		if k == "":
			continue
		var cur: int = int(stat_level.get(k, 1))
		stat_level[k] = max(1, cur + 1)
	emit_signal("stats_changed")

## Returns save data Dictionary containing hero stats, SXP, levels, fatigue, party progress, and hero XP
func save() -> Dictionary:
	return {
		"levels": stat_level.duplicate(true),
		"xp": stat_sxp.duplicate(true),
		"weekly": weekly_actions.duplicate(true),                 # legacy
		"weekly_sxp_hero": hero_weekly_sxp.duplicate(true),       # fatigue driver
		"party_dsi": _party_progress.duplicate(true),
		"hero": {"level": hero_level, "xp": hero_xp}
	}

## Restores stats from save data Dictionary, loading hero stats, SXP, levels, fatigue, and party progress. Emits stats_changed
func load(data: Dictionary) -> void:
	var lv_v: Variant = data.get("levels", {})
	if typeof(lv_v) == TYPE_DICTIONARY:
		for k in (lv_v as Dictionary).keys():
			stat_level[String(k)] = int((lv_v as Dictionary)[k])

	var xp_v: Variant = data.get("xp", {})
	if typeof(xp_v) == TYPE_DICTIONARY:
		for k in (xp_v as Dictionary).keys():
			stat_sxp[String(k)] = int((xp_v as Dictionary)[k])

	# legacy weekly (not used by fatigue logic)
	var w_v: Variant = data.get("weekly", {})
	if typeof(w_v) == TYPE_DICTIONARY:
		for k in (w_v as Dictionary).keys():
			weekly_actions[String(k)] = int((w_v as Dictionary)[k])

	# hero weekly SXP for fatigue
	var hw_v: Variant = data.get("weekly_sxp_hero", {})
	if typeof(hw_v) == TYPE_DICTIONARY:
		for k in (hw_v as Dictionary).keys():
			hero_weekly_sxp[String(k)] = int((hw_v as Dictionary)[k])

	var pd_v: Variant = data.get("party_dsi", {})
	if typeof(pd_v) == TYPE_DICTIONARY:
		_party_progress = (pd_v as Dictionary).duplicate(true)

	var hero_v: Variant = data.get("hero", {})
	if typeof(hero_v) == TYPE_DICTIONARY:
		var hero_d: Dictionary = hero_v
		hero_level = int(hero_d.get("level", hero_level))
		hero_xp    = int(hero_d.get("xp", hero_xp))

	emit_signal("stats_changed")
