extends Node
class_name WorldSpotsSystem

## WorldSpotsSystem
## Loads “world spots” from CSV and exposes:
## - Queries for which spots are available today/this phase (with or without gating context)
## - Training action that awards SXP and advances the day phase
## - A small parser for CSV rows (phases, gates, stat grants, date windows)
##
## CSV expectations (per row):
## - spot_id, name, location_id, track
## - phase: "M/A/E" mask (defaults to all)
## - base_sxp: int
## - stats: "RND" | "BRW=2;MND=1" | "BRW;VTL;FCS" (pairs/list)
## - tags: "tag1;tag2"
## - first_time_bonus, weekend_bonus, tournament_bonus: ints (not applied yet here)
## - cred_payout: "min;max"
## - gates: "stat_expr;item_ids;story_flags;weekday_mask"
##   * stat_expr example: "BRW>=2&FCS>=1|MND>=3"
##   * item_ids: "key1|key2"
##   * story_flags: "flag_a|flag_b"
##   * weekday_mask: "1110111" or "Mon,Wed,Fri"
## - start_date/end_date: "YYYYMMDD" or "MM/DD" (year inferred from Calendar)

const DEFAULT_SPOTS_PATH: String = "res://data/world/world_spots.csv"

# spot_id -> parsed record
var spots: Dictionary = {}

func _ready() -> void:
	## Load default CSV at boot.
	load_spots(DEFAULT_SPOTS_PATH)

# Load -------------------------------------------------------------------------

## Loads a CSV of spots and parses each row into a normalized Dictionary.
## @param path: String — CSV file path (defaults to DEFAULT_SPOTS_PATH)
func load_spots(path: String = DEFAULT_SPOTS_PATH) -> void:
	var loader: Node = get_node_or_null("/root/aCSVLoader")
	if loader == null:
		push_error("WorldSpotsSystem: CSVLoader not found.")
		return
	var table: Dictionary = loader.load_csv(path, "spot_id")
	if typeof(table) != TYPE_DICTIONARY:
		push_error("WorldSpotsSystem: failed to load spots from " + path)
		return

	spots.clear()
	for sid in table.keys():
		var raw: Dictionary = table[sid]
		spots[sid] = _parse_row(raw)

# Queries ----------------------------------------------------------------------

## Returns all spots available right now based on:
## - Current phase (from CalendarSystem)
## - Weekday mask (gates)
## - Optional date window (start_ymd/end_ymd)
## - No stat/item/flag gating (empty ctx)
func get_available_spots() -> Array:
	var cal: Node = get_node_or_null("/root/aCalendarSystem")
	if cal == null:
		return []

	var weekday_idx: int = int(cal.current_weekday)
	var phase_name: String = "Morning"
	if cal.has_method("get_phase_name"):
		phase_name = String(cal.get_phase_name())

	var today_ymd: int = _today_ymd()

	var out: Array = []
	for sid in spots.keys():
		var rec: Dictionary = spots[sid]
		if (
			_meets_phase(rec, phase_name)
			and _meets_weekday(rec, weekday_idx)
			and _meets_date(rec, today_ymd)
			and _passes_gates(rec.get("gates", {}), {})
		):
			out.append(rec)
	return out

## Same as get_available_spots(), but applies a gating context:
## ctx = { "stats": Dictionary, "items": Array[String], "flags": Array[String] }
func get_available_spots_with_ctx(ctx: Dictionary) -> Array:
	var cal: Node = get_node_or_null("/root/aCalendarSystem")

	var weekday_idx: int = 0
	var phase_name: String = "Morning"
	if cal:
		weekday_idx = int(cal.current_weekday)
		if cal.has_method("get_phase_name"):
			phase_name = String(cal.get_phase_name())

	var today_ymd: int = _today_ymd()

	var out: Array = []
	for sid in spots.keys():
		var rec: Dictionary = spots[sid]
		if (
			_meets_phase(rec, phase_name)
			and _meets_weekday(rec, weekday_idx)
			and _meets_date(rec, today_ymd)
			and _passes_gates(rec.get("gates", {}), ctx)
		):
			out.append(rec)
	return out

# Action -----------------------------------------------------------------------

## Trains at the given spot_id:
## - Resolves stat grants from the record (pairs/rnd/list)
## - Applies SXP via StatsSystem
## - Advances phase via CalendarSystem
## @return bool — true if training was applied
func train_at_spot(spot_id: String) -> bool:
	var rec: Dictionary = spots.get(spot_id, {})
	if rec.is_empty():
		return false

	var stats_sys: Node = get_node_or_null("/root/aStatsSystem")
	var cal: Node = get_node_or_null("/root/aCalendarSystem")
	if stats_sys == null or cal == null:
		return false

	var grants: Dictionary = _resolve_stat_grants(rec)
	for stat in grants.keys():
		var amt: int = int(grants[stat])
		if amt > 0:
			stats_sys.add_sxp(stat, amt)

	cal.advance_phase()
	return true

# Award logic ------------------------------------------------------------------

## Resolves a record’s stat-grant into a Dictionary: { "BRW": int, ... }
## Modes:
## - "pairs": exact map from CSV
## - "rnd": one stat per week, amount = base_sxp
## - "list": split base_sxp across names in stats_list (min 1 each)
func _resolve_stat_grants(rec: Dictionary) -> Dictionary:
	var mode: String = String(rec.get("stats_mode", "list"))

	if mode == "pairs":
		# e.g. "BRW=3;MND=1"
		return Dictionary(rec.get("stats_map", {})).duplicate()

	if mode == "rnd":
		# pick one stat for this week, give base_sxp
		var stat: String = _weekly_random_stat(String(rec.get("spot_id", "")))
		if stat == "":
			return {}
		return {stat: max(1, int(rec.get("base_sxp", 0)))}

	# default: list mode — split base_sxp evenly across listed stats
	var lst: Array = rec.get("stats_list", [])
	if lst.is_empty():
		return {}
	var base_val: int = int(rec.get("base_sxp", 0))
	var per: int = 1
	if lst.size() > 0:
		per = int(max(1, round(float(base_val) / float(lst.size()))))
	var out: Dictionary = {}
	for s in lst:
		out[String(s)] = per
	return out

## Deterministic weekly choice for "rnd" mode:
## Uses (spot_id.hash XOR week_index) % stats.size() to pick a stat.
func _weekly_random_stat(spot_id: String) -> String:
	# deterministic per week so the “rnd” spot feels consistent for 7 days
	var cal: Node = get_node_or_null("/root/aCalendarSystem")
	if cal == null:
		return "MND"
	var cd: Variant = cal.get("current_date")
	var week: int = 0
	if typeof(cd) == TYPE_DICTIONARY:
		var dd: int = int(cd.get("day", 1))
		week = int(floor(float(dd - 1) / 7.0))

	var stats: Array = ["BRW", "VTL", "TPO", "FCS", "MND"]
	var h: int = (spot_id.hash() ^ week) % stats.size()
	if h < 0:
		h = -h
	return String(stats[h])

# Parse ------------------------------------------------------------------------

## Converts one CSV row into a normalized record with parsed fields.
func _parse_row(raw: Dictionary) -> Dictionary:
	var rec: Dictionary = {}

	rec["spot_id"] = String(raw.get("spot_id", ""))
	rec["name"] = String(raw.get("name", ""))
	rec["location_id"] = String(raw.get("location_id", ""))
	rec["track"] = String(raw.get("track", ""))

	rec["phase_set"] = _parse_phases(String(raw.get("phase", "M/A/E")))
	rec["base_sxp"] = int(raw.get("base_sxp", 0))

	rec["stats_raw"] = String(raw.get("stats", ""))
	rec["stats_mode"] = _detect_stats_mode(String(rec["stats_raw"]))
	rec["stats_map"] = _parse_stats_map(String(rec["stats_raw"]))
	rec["stats_list"] = _parse_stats_list(String(rec["stats_raw"]))

	rec["tags"] = _split_semicolon(String(raw.get("tags", "")))

	rec["first_time_bonus"] = int(raw.get("first_time_bonus", 0))
	rec["weekend_bonus"] = int(raw.get("weekend_bonus", 0))
	rec["tournament_bonus"] = int(raw.get("tournament_bonus", 0))

	rec["cred_payout"] = _parse_min_max(String(raw.get("cred_payout", "0;0")))
	rec["gates"] = _parse_gates(String(raw.get("gates", "-;-;-;1111111")))
	rec["notes"] = String(raw.get("notes", ""))

	rec["start_ymd"] = _parse_date_ymd(String(raw.get("start_date", "")))
	rec["end_ymd"] = _parse_date_ymd(String(raw.get("end_date", "")))

	return rec

## Parses "M/A/E" into a dict like { "M": true, "A": true, "E": true }.
func _parse_phases(s: String) -> Dictionary:
	var out: Dictionary = {}
	for part in s.split("/", false):
		var p: String = String(part).strip_edges()
		if p == "M" or p == "A" or p == "E":
			out[p] = true
	if out.is_empty():
		out["M"] = true
		out["A"] = true
		out["E"] = true
	return out

## Detects stats mode from the raw string.
## - "RND" → rnd
## - contains "=" → pairs
## - else → list
func _detect_stats_mode(s: String) -> String:
	var u: String = s.to_upper()
	if u == "RND":
		return "rnd"
	if s.find("=") != -1:
		return "pairs"
	return "list"

## Parses "BRW=2;MND=1" into a Dictionary.
func _parse_stats_map(s: String) -> Dictionary:
	var out: Dictionary = {}
	for token in _split_semicolon(s):
		var eq: int = String(token).find("=")
		if eq > 0:
			var key: String = String(token).substr(0, eq).strip_edges()
			var val: String = String(token).substr(eq + 1).strip_edges()
			if key != "":
				out[key] = int(val)
	return out

## Parses "BRW;VTL;FCS" into an Array[String]. Returns [] if "RND".
func _parse_stats_list(s: String) -> Array:
	if s.to_upper() == "RND":
		return []
	var out: Array = []
	for token in _split_semicolon(s):
		var t: String = String(token).strip_edges()
		if t != "" and t.find("=") == -1:
			out.append(t)
	return out

## Split helper for semicolon-delimited fields. Returns [] for "" or "-".
func _split_semicolon(s: String) -> Array:
	if s == "" or s == "-":
		return []
	return s.split(";", false)

## Parses "min;max" into a Dictionary {min:int, max:int} with max >= min.
func _parse_min_max(s: String) -> Dictionary:
	var p: Array = s.split(";", false)
	var mn: int = 0
	var mx: int = 0
	if p.size() > 0:
		mn = int(p[0])
	if p.size() > 1:
		mx = int(p[1])
	if mx < mn:
		mx = mn
	return {"min": mn, "max": mx}

# Gates ------------------------------------------------------------------------

## Parses the gates field: "stat_expr;item_ids;story_flags;weekday_mask".
## Returns a normalized dictionary used by _passes_gates().
func _parse_gates(s: String) -> Dictionary:
	var p: Array = s.split(";", false)

	var stat_expr: String = "-"
	if p.size() > 0:
		stat_expr = String(p[0]).strip_edges()

	var item_ids: String = "-"
	if p.size() > 1:
		item_ids = String(p[1]).strip_edges()

	var flags: String = "-"
	if p.size() > 2:
		flags = String(p[2]).strip_edges()

	var wmask_raw: String = "1111111"
	if p.size() > 3:
		wmask_raw = String(p[3]).strip_edges()

	var item_arr: Array = []
	if item_ids != "-":
		for it in item_ids.split("|", false):
			var k: String = String(it).strip_edges()
			if k != "":
				item_arr.append(k)

	var flag_arr: Array = []
	if flags != "-":
		for fl in flags.split("|", false):
			var f: String = String(fl).strip_edges()
			if f != "":
				flag_arr.append(f)

	var final_mask: String = _normalize_weekday_mask(wmask_raw)

	return {
		"stat_expr": stat_expr,
		"item_ids": item_arr,
		"story_flags": flag_arr,
		"weekday_mask": final_mask
	}

## Accepts "1110111", "1"/"0", or names like "Mon,Wed,Fri"; returns 7-char mask.
func _normalize_weekday_mask(s: String) -> String:
	var t: String = String(s).strip_edges()
	if t == "" or t == "-":
		return "1111111"
	if t == "1":
		return "1111111"
	if t == "0":
		return "0000000"

	var re: RegEx = RegEx.new()
	if re.compile("^[01]{7}$") == OK:
		var m := re.search(t)
		if m:
			return t

	var name_to_idx: Dictionary = {
		"MON": 0, "MONDAY": 0,
		"TUE": 1, "TUES": 1, "TUESDAY": 1,
		"WED": 2, "WEDNESDAY": 2,
		"THU": 3, "THUR": 3, "THURS": 3, "THURSDAY": 3,
		"FRI": 4, "FRIDAY": 4,
		"SAT": 5, "SATURDAY": 5,
		"SUN": 6, "SUNDAY": 6
	}
	var picks: Dictionary = {}
	for raw in t.split(",", false):
		var key: String = String(raw).strip_edges().to_upper()
		if name_to_idx.has(key):
			picks[name_to_idx[key]] = true

	var mask: String = ""
	for i in range(7):
		if picks.has(i):
			mask += "1"
		else:
			mask += "0"

	if mask.find("1") == -1:
		return "0000000"
	return mask

# Checks -----------------------------------------------------------------------

## Phase gate — returns true if the record allows the current phase.
func _meets_phase(rec: Dictionary, phase_name: String) -> bool:
	var key: String = "M"
	match phase_name:
		"Morning":
			key = "M"
		"Afternoon":
			key = "A"
		"Evening":
			key = "E"
		_:
			key = "M"
	return bool(rec.get("phase_set", {}).get(key, false))

## Weekday mask gate — returns true if today’s weekday bit is 1.
func _meets_weekday(rec: Dictionary, weekday_idx: int) -> bool:
	var mask: String = String(rec.get("gates", {}).get("weekday_mask", "1111111"))
	if mask.length() != 7:
		return false
	return mask.substr(weekday_idx, 1) == "1"

## Date window gate — returns true if today is within [start_ymd, end_ymd].
func _meets_date(rec: Dictionary, today_ymd: int) -> bool:
	if today_ymd == 0:
		return true
	var start: int = int(rec.get("start_ymd", 0))
	var finish: int = int(rec.get("end_ymd", 0))
	if start > 0 and today_ymd < start:
		return false
	if finish > 0 and today_ymd > finish:
		return false
	return true

## Context gate — checks required items, flags, and stat expression.
func _passes_gates(g: Dictionary, ctx: Dictionary) -> bool:
	if g.is_empty():
		return true

	var items_need: Array = g.get("item_ids", [])
	if items_need.size() > 0:
		var have: Array = ctx.get("items", [])
		for it in items_need:
			if not have.has(String(it)):
				return false

	var flags_need: Array = g.get("story_flags", [])
	if flags_need.size() > 0:
		var f_have: Array = ctx.get("flags", [])
		for fl in flags_need:
			if not f_have.has(String(fl)):
				return false

	var expr: String = String(g.get("stat_expr", ""))
	if expr != "" and expr != "-":
		if not _eval_stat_expr(expr, ctx.get("stats", {})):
			return false

	return true

## Evaluates a simple AND/OR expression over stat levels.
## Example: "BRW>=2&FCS>=1|MND>=3"
func _eval_stat_expr(expr: String, stats: Dictionary) -> bool:
	var or_groups: Array = expr.split("|", false)
	for grp_raw in or_groups:
		var and_ok: bool = true
		var and_parts: Array = String(grp_raw).split("&", false)
		for clause_raw in and_parts:
			var clause: String = String(clause_raw).strip_edges()
			if clause == "":
				continue
			var re: RegEx = RegEx.new()
			if re.compile("(\\w+)\\s*(>=|<=|==|>|<)\\s*(\\d+)") != OK:
				return false
			var m := re.search(clause)
			if m == null or m.get_group_count() < 3:
				and_ok = false
				break
			var stat: String = m.get_string(1)
			var op: String = m.get_string(2)
			var need: int = int(m.get_string(3))
			var have: int = int(stats.get(stat, 0))
			var ok: bool = false
			match op:
				">=": ok = have >= need
				"<=": ok = have <= need
				">": ok = have > need
				"<": ok = have < need
				"==": ok = have == need
				_: ok = false
			if not ok:
				and_ok = false
				break
		if and_ok:
			return true
	return false

# Date helpers -----------------------------------------------------------------

## Parses "YYYYMMDD" or "MM/DD" to an int YYYYMMDD (0 if none).
func _parse_date_ymd(s: String) -> int:
	var t: String = String(s).strip_edges()
	if t == "" or t == "-":
		return 0

	var re: RegEx = RegEx.new()
	if re.compile("^(\\d{4})(\\d{2})(\\d{2})$") == OK:
		var m := re.search(t)
		if m:
			var y: int = int(m.get_string(1))
			var mo: int = int(m.get_string(2))
			var d: int = int(m.get_string(3))
			return y * 10000 + mo * 100 + d

	if re.compile("^(\\d{1,2})[/-](\\d{1,2})$") == OK:
		var m2 := re.search(t)
		if m2:
			var yy: int = 2025
			var cal: Node = get_node_or_null("/root/aCalendarSystem")
			if cal:
				var cd2: Variant = cal.get("current_date")
				if typeof(cd2) == TYPE_DICTIONARY:
					yy = int(cd2.get("year", yy))
			var mo2: int = int(m2.get_string(1))
			var d2: int = int(m2.get_string(2))
			return yy * 10000 + mo2 * 100 + d2

	return 0

## Builds today’s YYYYMMDD from CalendarSystem (0 if unavailable).
func _today_ymd() -> int:
	var cal: Node = get_node_or_null("/root/aCalendarSystem")
	if cal == null:
		return 0
	var cd: Variant = cal.get("current_date")
	if typeof(cd) != TYPE_DICTIONARY:
		return 0
	var y: int = int(cd.get("year", 2025))
	var m: int = int(cd.get("month", 1))
	var d: int = int(cd.get("day", 1))
	return y * 10000 + m * 100 + d
