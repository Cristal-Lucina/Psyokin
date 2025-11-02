## ═══════════════════════════════════════════════════════════════════════════
## DormsSystem - Dormitory Room Assignment & Social Relationship Manager
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Manages dorm room assignments for party members across 8 rooms, tracking
##   social relationships (Bestie/Rival) based on room adjacency, and handling
##   weekly reassignments with a planning/staging system.
##
## RESPONSIBILITIES:
##   • Room assignment tracking (8 rooms: 301-308)
##   • Neighbor adjacency relationships (defines who lives next to whom)
##   • Bestie/Rival relationship detection (neighbors become Besties/Rivals)
##   • Common area management (unassigned members)
##   • Weekly Saturday reassignment system
##   • Midweek Common placement (immediate moves)
##   • Planning/staging system (preview moves before applying)
##   • Blocking state (prevents day advance until plan is accepted)
##   • Hidden relationship reveal queues (Friday/Saturday reveals)
##   • Hero stat pick integration (preferred stats for room assignments)
##
## ROOM LAYOUT:
##   8 rooms arranged in two rows:
##   [301] — [302] — [303] — [304]
##   [305] — [306] — [307] — [308]
##
##   Neighbors share walls or corners (e.g., 301 neighbors 302, 305)
##
## RELATIONSHIP SYSTEM:
##   • Neighbors become Besties or Rivals (based on CSV data)
##   • Hidden pairs queue for reveal on Friday (from Saturday moves)
##   • Hidden pairs queue for reveal on Saturday (from midweek Common)
##   • Once revealed, relationships persist
##
## WEEKLY CYCLE:
##   Saturday: Reassignment planning mode activates
##     - User can plan room swaps
##     - Blocks day advance until "Accept Plan" or "Cancel"
##     - On Accept: New layout applies, creates hidden pairs for Friday reveal
##
##   Midweek: Common placements
##     - Adding members to Common immediately places them
##     - Creates hidden pairs for Saturday reveal
##
##   Friday: Reveals pairs from prior Saturday reassignments
##
##   Saturday: Reveals pairs from midweek Common placements
##
## CONNECTED SYSTEMS (Autoloads):
##   • GameState - Member roster, hero picks, save/load coordination
##   • CalendarSystem - Saturday triggers, advance blocking
##   • CircleBondSystem - Likely bond unlocks from relationships
##
## CSV DATA SOURCES:
##   • Actor data CSVs for names, display names, stat preferences
##   • Relationship CSVs for Bestie/Rival mappings
##
## KEY METHODS:
##   • assign_room(actor_id, room_id) - Direct assignment
##   • add_to_common(actor_id) - Place in common area
##   • plan_reassignment_for_saturday(moves: Array) - Stage Saturday plan
##   • accept_plan() - Apply staged reassignments
##   • cancel_plan() - Discard staged reassignments
##   • reveal_friday_pairs() - Show Saturday-generated relationships
##   • reveal_saturday_pairs() - Show midweek-generated relationships
##   • get_room_occupant(room_id) -> String - Who lives in this room
##   • get_neighbors(actor_id) -> Array[String] - Adjacent room occupants
##   • get_pair_label(a, b) -> String - "Bestie"/"Rival"/"Neutral"
##
## ═══════════════════════════════════════════════════════════════════════════

extends Node
class_name DormsSystem

signal dorms_changed
signal plan_changed
signal saturday_applied(new_layout: Dictionary)
signal saturday_applied_v2(new_layout: Dictionary, moves: Array)
signal common_added(aid: String)

signal friday_reveals_ready(pairs: Array)
signal saturday_reveals_ready(pairs: Array)

signal blocking_state_changed(is_blocking: bool)

const ROOM_IDS := [
	"301","302","303","304",
	"305","306","307","308"
]

const NEIGHBORS := {
	"301": ["302","305"],
	"302": ["301","303","306"],
	"303": ["302","304","307"],
	"304": ["303","308"],
	"305": ["301","306"],
	"306": ["302","305","307"],
	"307": ["306","308","303"],
	"308": ["307","304"],
}

var _name_by_id: Dictionary = {}
var _id_norm_map: Dictionary = {}

# stat prefs
var _stat_by_actor: Dictionary = {}

# hero
var _hero_picks: Array[String] = []

# layout + common + staging
var _rooms: Dictionary = {}
var _common: Array[String] = []
var _staged_common: Array[String] = []
var _staged_prev_room: Dictionary = {}
var _staged_assign: Dictionary = {}
var _plan_locked: bool = false
var _locked_involved_rooms: Dictionary = {}

# move penalties (stacking affinity penalty with protagonist for 1 week after move)
var _move_penalties: Dictionary = {}  # { "actor_id": {"penalty": -2, "applied_week": int, "expires_week": int} }

# player relationship matrix (calculated from hero stat picks)
var _player_relationships: Dictionary = {}  # { "actor_id": "bestie"|"rival"|"neutral" }

# relationships
var _bestie_map: Dictionary = {}
var _rival_map : Dictionary = {}

# adjacency
var _pair_status: Dictionary = {}

# hidden queues (awaiting reveal)
var _hidden_pairs_friday: Dictionary = {}
var _hidden_pairs_saturday: Dictionary = {}

# NEW: revealed pairs persist
var _discovered_pairs: Dictionary = {} # "a|b" -> true

# reporting
var _last_applied_moves: Array = []

# calendar glue
const _CAL_PATHS := [
	"/root/aCalendarSystem",
	"/root/CalendarSystem",
	"/root/aCalendar",
	"/root/aTimeSystem",
	"/root/aGameTime",
	"/root/aClock",
	"/root/aDayNightSystem"
]
const _CAL_SIGNALS := [
	"day_changed","date_changed","weekday_changed","day_start",
	"new_day","on_day_changed","tick_day","day_advanced","week_reset"
]
var _calendar_node: Node = null
var _last_weekday_index: int = -1
var _last_weekday_name: String = ""
var _is_blocking_time_advance: bool = false

enum RoomVisual { EMPTY_GREEN, OCCUPIED_BLUE, STAGED_YELLOW, LOCKED_RED }

# CSV header aliases / paths
const _ID_KEYS      := ["actor_id","id","actor","member_id"]
const _NAME_KEYS    := ["name","display_name","disp_name"]
const _BESTIE_KEYS  := ["bestie_buff","besties","bestie","bestie_ids"]
const _RIVAL_KEYS   := ["rival_debuff","rivals","rival","rival_ids"]
const _NEIGH_KEYS   := ["hero_neighbors","hero_neighbours","neighbor_stat","neighbor","neigh","stat","pref_stat"]
const _PARTY_CANDIDATES := [
	"res://data/party/party.csv",
	"res://data/Party.csv",
	"res://data/party.csv",
	"res://data/characters/party.csv",
	"res://data/actors/party.csv",
	"res://data/actors.csv"
]

const _STAT_ALIAS := {
	"BRW":"BRW","BRAWN":"BRW",
	"MND":"MND","MIND":"MND",
	"TPO":"TPO","TEMPO":"TPO",
	"VTL":"VTL","VITALITY":"VTL",
	"FCS":"FCS","FOCUS":"FCS",
	"NULL":"NULL","NONE":"NULL"
}
const _ALL_STATS := ["BRW","MND","TPO","VTL","FCS"]

func _ready() -> void:
	_bootstrap_rooms()
	_load_party_names_relationships_and_stats()
	_pull_gs_metadata()
	_bind_calendar()
	if get_tree() != null:
		get_tree().connect("node_added", Callable(self, "_on_tree_node_added"))
	_recompute_adjacency()
	_update_blocking_state()
	dorms_changed.emit()

# ───────────────── calendar glue ─────────────────
func set_calendar(node: Node) -> void:
	if node == null or node == _calendar_node: return
	_calendar_node = node
	_connect_calendar_signals()

func _on_tree_node_added(n: Node) -> void:
	if _calendar_node != null: return
	var looks_like_cal: bool = false
	for sig in _CAL_SIGNALS:
		if n.has_signal(sig):
			looks_like_cal = true
			break
	if not looks_like_cal:
		for m in ["get_weekday_name","get_weekday","day_of_week","weekday","dow"]:
			if n.has_method(m):
				looks_like_cal = true
				break
	if looks_like_cal:
		set_calendar(n)

func _bind_calendar() -> void:
	for path in _CAL_PATHS:
		if _calendar_node == null:
			_calendar_node = get_node_or_null(path)
	if _calendar_node == null and get_tree() != null:
		for child in get_tree().root.get_children():
			for m in ["get_weekday_name","get_day_name","weekday_name","day_name"]:
				if child.has_method(m):
					_calendar_node = child
					break
			if _calendar_node != null:
				break
	_connect_calendar_signals()

func _connect_calendar_signals() -> void:
	if _calendar_node == null: return
	for sig in _CAL_SIGNALS:
		if _calendar_node.has_signal(sig) and not _calendar_node.is_connected(sig, Callable(self, "_on_calendar_day_changed")):
			_calendar_node.connect(sig, Callable(self, "_on_calendar_day_changed").bind(sig))

func _weekday_name_to_index(s: String) -> int:
	if s == null: return -1
	var t: String = String(s).strip_edges().to_lower()
	if t.begins_with("mon") or t == "0": return 0
	if t.begins_with("tue") or t == "1": return 1
	if t.begins_with("wed") or t == "2": return 2
	if t.begins_with("thu") or t == "3": return 3
	if t.begins_with("fri") or t == "4": return 4
	if t.begins_with("sat") or t == "5": return 5
	if t.begins_with("sun") or t == "6": return 6
	return -1

func calendar_notify_weekday(weekday_name: String) -> void:
	_last_weekday_name = weekday_name
	_last_weekday_index = _weekday_name_to_index(weekday_name)
	if _compute_blocking(): return
	if _is_friday_name(weekday_name):
		_reveal_friday_now()
	elif _is_saturday_name(weekday_name):
		if _plan_locked: saturday_execute_changes()
		_reveal_saturday_now()

func _on_calendar_day_changed(a: Variant = null, _b: Variant = null, _c: Variant = null, _sig: String = "") -> void:
	var wd_name: String = ""
	var idx: int = -999
	if typeof(a) == TYPE_STRING:
		wd_name = String(a)
	elif typeof(a) == TYPE_DICTIONARY:
		var d: Dictionary = a
		for k in ["weekday_name","day_name","weekday","dow","day"]:
			if d.has(k):
				var v: Variant = d[k]
				if typeof(v) == TYPE_STRING:
					wd_name = String(v)
				elif typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
					idx = int(v)
				break
	if wd_name == "" and _calendar_node != null:
		for m in ["get_weekday_name","get_day_name","weekday_name","day_name"]:
			if _calendar_node.has_method(m):
				var got: Variant = _calendar_node.call(m)
				if typeof(got) == TYPE_STRING:
					wd_name = String(got)
					break
		if wd_name == "":
			for m2 in ["get_weekday","day_of_week","weekday","dow","current_weekday"]:
				if _calendar_node.has_method(m2):
					var got2: Variant = _calendar_node.call(m2)
					if typeof(got2) == TYPE_INT or typeof(got2) == TYPE_FLOAT:
						idx = int(got2)
						break
	var idx2: int = (idx if idx >= 0 else _weekday_name_to_index(wd_name))
	if idx2 >= 0: _last_weekday_index = idx2
	if wd_name != "": _last_weekday_name = wd_name

	# Cleanup expired move penalties on every day change
	cleanup_expired_move_penalties()

	if _compute_blocking(): return
	if _is_friday_name(wd_name) or _is_friday_index(idx2):
		_reveal_friday_now()
		return
	if _is_saturday_name(wd_name) or _is_saturday_index(idx2):
		if _plan_locked: saturday_execute_changes()
		_reveal_saturday_now()

func _weekday_index() -> int:
	if _calendar_node != null:
		for m in ["get_weekday","day_of_week","weekday","dow","current_weekday"]:
			if _calendar_node.has_method(m):
				var v: Variant = _calendar_node.call(m)
				if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
					return int(v)
				elif typeof(v) == TYPE_STRING:
					var idx: int = _weekday_name_to_index(String(v))
					if idx != -1: return idx
	for m2 in ["get_weekday_name","get_day_name","weekday_name","day_name"]:
		if _calendar_node != null and _calendar_node.has_method(m2):
			var s: String = String(_calendar_node.call(m2))
			var idx2: int = _weekday_name_to_index(s)
			if idx2 != -1: return idx2
	if _last_weekday_index != -1: return _last_weekday_index
	if _last_weekday_name != "":
		var idx3: int = _weekday_name_to_index(_last_weekday_name)
		if idx3 != -1: return idx3
	return -1

func _is_friday_name(s: String) -> bool:
	if s == null: return false
	var t: String = String(s).strip_edges().to_lower()
	return t.begins_with("fri") or t == "4"
func _is_friday_index(i: int) -> bool: return i == 4
func _is_saturday_name(s: String) -> bool:
	if s == null: return false
	var t: String = String(s).strip_edges().to_lower()
	return t.begins_with("sat") or t == "5"
func _is_saturday_index(i: int) -> bool: return i == 5

# ───────────── bootstrap / CSV / hero meta ─────────────
func _bootstrap_rooms() -> void:
	_rooms.clear()
	for rid in ROOM_IDS:
		_rooms[rid] = {"name": rid, "occupant": ""}
	_rooms["301"]["occupant"] = "hero" # RA room

func _norm_header(s: String) -> String:
	var t: String = String(s).to_lower().strip_edges()
	t = t.replace(",", "").replace("\t","")
	return t

func _norm_id_token(s: String) -> String:
	var t: String = String(s).to_lower().strip_edges()
	t = t.replace("-", "_").replace(" ", "_")
	while t.find("__") != -1:
		t = t.replace("__","_")
	return t

func _canon_id(token: String) -> String:
	var norm: String = _norm_id_token(token)
	return String(_id_norm_map.get(norm, token))

func _best_fit_party_csv() -> String:
	for p in _PARTY_CANDIDATES:
		if FileAccess.file_exists(p): return p
	return ""

func _ensure_hero_in_maps() -> void:
	if not _name_by_id.has("hero"): _name_by_id["hero"] = "Hero"
	_id_norm_map[_norm_id_token("hero")] = "hero"
	_id_norm_map[_norm_id_token("Hero")] = "hero"

func _load_party_names_relationships_and_stats() -> void:
	_name_by_id.clear()
	_id_norm_map.clear()
	_bestie_map.clear()
	_rival_map.clear()
	_stat_by_actor.clear()

	var path: String = _best_fit_party_csv()
	if path == "":
		_ensure_hero_in_maps()
		_seed_hardcoded_stat_map_if_missing()
		return

	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		_ensure_hero_in_maps()
		_seed_hardcoded_stat_map_if_missing()
		return

	var header: PackedStringArray = PackedStringArray()
	if not f.eof_reached():
		header = f.get_csv_line()

	var idx_id: int = -1
	var idx_nm: int = -1
	var idx_bestie: int = -1
	var idx_rival: int = -1
	var idx_neigh: int = -1

	for i in range(header.size()):
		var key: String = _norm_header(header[i])
		if idx_id == -1 and key in _ID_KEYS: idx_id = i
		if idx_nm == -1 and key in _NAME_KEYS: idx_nm = i
		if idx_bestie == -1 and key in _BESTIE_KEYS: idx_bestie = i
		if idx_rival  == -1 and key in _RIVAL_KEYS : idx_rival  = i
		if idx_neigh  == -1 and key in _NEIGH_KEYS: idx_neigh  = i

	while not f.eof_reached():
		var cols: PackedStringArray = f.get_csv_line()
		if cols.size() == 0:
			continue
		var aid: String = (cols[idx_id] if idx_id >= 0 and idx_id < cols.size() else "").strip_edges()
		if aid == "":
			continue
		var nm: String = (cols[idx_nm] if idx_nm >= 0 and idx_nm < cols.size() else "").strip_edges()
		_name_by_id[aid] = (nm if nm != "" else aid.capitalize())
		_id_norm_map[_norm_id_token(aid)] = aid
		if nm != "": _id_norm_map[_norm_id_token(nm)] = aid

		var bestie_val: String = (cols[idx_bestie] if idx_bestie >= 0 and idx_bestie < cols.size() else "")
		var rival_val : String = (cols[idx_rival]  if idx_rival  >= 0 and idx_rival  < cols.size() else "")
		_bestie_map[aid] = _parse_rel_list_val_to_ids(bestie_val)
		_rival_map[aid]  = _parse_rel_list_val_to_ids(rival_val)

		var raw_stat: String = (cols[idx_neigh] if idx_neigh >= 0 and idx_neigh < cols.size() else "").strip_edges().to_upper()
		var code: String = ""
		if raw_stat != "":
			if _STAT_ALIAS.has(raw_stat):
				code = String(_STAT_ALIAS[raw_stat])
			elif raw_stat.length() >= 3:
				var guess: String = raw_stat.substr(0,3)
				if _ALL_STATS.has(guess): code = guess
		if code != "": _stat_by_actor[aid] = code

	f.close()
	_ensure_hero_in_maps()
	_seed_hardcoded_stat_map_if_missing()

func _parse_rel_list_val_to_ids(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(v) == TYPE_STRING:
		var s: String = String(v).replace(";", ",").replace("|", ",")
		var parts: PackedStringArray = s.split(",", false)
		for raw_any in parts:
			var raw: String = String(raw_any).strip_edges()
			if raw == "":
				continue
			var norm: String = _norm_id_token(raw)
			out.append(String(_id_norm_map.get(norm, raw)))
	return out

func _seed_hardcoded_stat_map_if_missing() -> void:
	var CANON := {
		"red_girl":     ["Risa",    "BRW"],
		"secret_girl":  ["Tessa",   "MND"],
		"blue_girl":    ["Skye",    "TPO"],
		"green_friend": ["Matcha",  "VTL"],
		"scientist":    ["Douglas", "FCS"],
		"best_friend":  ["Kai",     "NULL"],
		"ai_friend":    ["Sev",     "NULL"],
	}
	for id_key in CANON.keys():
		var disp: String = String(CANON[id_key][0])
		var stat: String = String(CANON[id_key][1])
		if not _stat_by_actor.has(id_key): _stat_by_actor[id_key] = stat
		_id_norm_map[_norm_id_token(id_key)] = id_key
		_id_norm_map[_norm_id_token(disp)] = id_key
		if not _name_by_id.has(id_key): _name_by_id[id_key] = disp

func _pull_gs_metadata() -> void:
	var gs: Node = get_node_or_null("/root/aGameState")
	if gs != null:
		var nm_v: Variant = gs.get("player_name")
		var nm_use: String = "Hero"
		if typeof(nm_v) == TYPE_STRING:
			var t: String = String(nm_v).strip_edges()
			if t != "":
				nm_use = t
		_name_by_id["hero"] = nm_use
		_id_norm_map[_norm_id_token(nm_use)] = "hero"
		_id_norm_map[_norm_id_token("hero")] = "hero"
		_id_norm_map[_norm_id_token("Hero")] = "hero"

	_hero_picks.clear()
	if gs != null and gs.has_method("get_hero_start_picks"):
		var hv: Variant = gs.call("get_hero_start_picks")
		match typeof(hv):
			TYPE_PACKED_STRING_ARRAY:
				for x in (hv as PackedStringArray): _hero_picks.append(String(x).to_upper())
			TYPE_ARRAY:
				for x2 in (hv as Array): _hero_picks.append(String(x2).to_upper())
	if _hero_picks.size() == 0:
		if gs and gs.has_meta("hero_start_picks"):
			var m: Variant = gs.get_meta("hero_start_picks")
			if typeof(m) == TYPE_PACKED_STRING_ARRAY:
				for x3 in (m as PackedStringArray): _hero_picks.append(String(x3).to_upper())
		elif gs and gs.has_meta("hero_picked_stats"):
			var m2: Variant = gs.get_meta("hero_picked_stats")
			if typeof(m2) == TYPE_PACKED_STRING_ARRAY:
				for x4 in (m2 as PackedStringArray): _hero_picks.append(String(x4).to_upper())
	if _hero_picks.size() == 0:
		var st: Node = get_node_or_null("/root/aStatsSystem")
		if st and st.has_method("get_hero_start_picks"):
			var sv: Variant = st.call("get_hero_start_picks")
			match typeof(sv):
				TYPE_PACKED_STRING_ARRAY:
					for s in (sv as PackedStringArray): _hero_picks.append(String(s).to_upper())
				TYPE_ARRAY:
					for s2 in (sv as Array): _hero_picks.append(String(s2).to_upper())
	if _hero_picks.size() == 0:
		var st2: Node = get_node_or_null("/root/aStatsSystem")
		if st2 and st2.has_method("get_stat"):
			for code in ["BRW","MND","TPO","VTL","FCS"]:
				var lv: Variant = st2.call("get_stat", code)
				if (typeof(lv) == TYPE_INT or typeof(lv) == TYPE_FLOAT) and int(lv) > 1:
					_hero_picks.append(code)
				if _hero_picks.size() >= 3:
					break

func recompute_now() -> void:
	_pull_gs_metadata()
	_apply_hero_stat_relationships()
	_recompute_adjacency()
	dorms_changed.emit()

func display_name(aid: String) -> String:
	if aid == "hero":
		var gs: Node = get_node_or_null("/root/aGameState")
		if gs != null:
			var nm_v: Variant = (gs.get("player_name") if gs.has_method("get") else "")
			var nm: String = String(nm_v)
			if nm.strip_edges() != "":
				return nm
	return String(_name_by_id.get(aid, aid.capitalize()))

# ───────────── queries ─────────────
func list_rooms() -> PackedStringArray:
	var out := PackedStringArray()
	for rid in ROOM_IDS:
		out.append(rid)
	return out

func get_room(room_id: String) -> Dictionary:
	return (_rooms.get(room_id, {}) as Dictionary).duplicate(true)

func occupants_of(room_id: String) -> PackedStringArray:
	var r: Dictionary = get_room(room_id)
	var out := PackedStringArray()
	var who: String = String(r.get("occupant","")).strip_edges()
	if who != "":
		out.append(who)
	return out

func get_common() -> PackedStringArray:
	var merged: Array[String] = _common.duplicate()
	for aid in _staged_common:
		if not _staged_assign.has(aid) and not merged.has(aid):
			merged.append(aid)
	var out := PackedStringArray()
	for a in merged:
		out.append(a)
	return out

func room_neighbors(room_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var arr_v: Variant = NEIGHBORS.get(room_id, [])
	if typeof(arr_v) == TYPE_ARRAY:
		for any in (arr_v as Array):
			out.append(String(any))
	return out

func room_in_locked_plan(room_id: String) -> bool:
	return _plan_locked and _locked_involved_rooms.has(room_id)

func get_locked_warning_for(room_id: String) -> String:
	return "(Room Reassignments happening on Saturday)" if room_in_locked_plan(room_id) else ""

func get_staged_prev_room_for(aid: String) -> String:
	return String(_staged_prev_room.get(aid, ""))

func get_room_visual(room_id: String) -> int:
	if _plan_locked:
		var r_locked: Dictionary = get_room(room_id)
		var who_locked: String = String(r_locked.get("occupant",""))
		return (RoomVisual.EMPTY_GREEN if who_locked == "" else RoomVisual.OCCUPIED_BLUE)
	for aid_k in _staged_prev_room.keys():
		var aid: String = String(aid_k)
		if String(_staged_prev_room[aid]) == room_id:
			return RoomVisual.STAGED_YELLOW
	for aid2_k in _staged_assign.keys():
		var aid2: String = String(aid2_k)
		if String(_staged_assign[aid2]) == room_id:
			return RoomVisual.STAGED_YELLOW
	var r: Dictionary = get_room(room_id)
	var who: String = String(r.get("occupant",""))
	return (RoomVisual.EMPTY_GREEN if who == "" else RoomVisual.OCCUPIED_BLUE)

func has_pending_plan() -> bool:
	return _staged_common.size() > 0 or _staged_assign.size() > 0

func is_staged(aid: String) -> bool: return _staged_common.has(aid)
func staged_size() -> int: return _staged_common.size()
func staged_assign_size() -> int: return _staged_assign.size()

func is_pair_hidden(a: String, b: String) -> bool:
	var key: String = _pair_key(a, b)
	return (_hidden_pairs_friday.has(key) or _hidden_pairs_saturday.has(key)) and not _discovered_pairs.has(key)

func list_current_placements() -> Array:
	var out: Array = []
	for rid in ROOM_IDS:
		var who: String = String((_rooms[rid] as Dictionary).get("occupant",""))
		out.append({"room": rid, "aid": who, "name": (display_name(who) if who != "" else "— empty —")})
	return out

func list_upcoming_reassignments() -> Array:
	var out: Array = []
	for aid_k in _staged_assign.keys():
		var aid: String = String(aid_k)
		var to_r: String = String(_staged_assign[aid])
		var from_r: String = String(_staged_prev_room.get(aid, ""))
		out.append({"aid": aid, "name": display_name(aid), "from": from_r, "to": to_r})
	return out

func get_staged_target_for(aid: String) -> String:
	return String(_staged_assign.get(aid, ""))
func get_staged_assignments() -> Dictionary: return _staged_assign.duplicate(true)
func staged_target_for(aid: String) -> String: return get_staged_target_for(aid)
func staged_assignments() -> Dictionary:       return get_staged_assignments()
func get_all_staged_members() -> PackedStringArray:
	var out := PackedStringArray()
	for a in _staged_common: out.append(a)
	return out
func list_staged_members() -> PackedStringArray: return get_all_staged_members()

# ───────────── cheats / immediate placement ─────────────
func cheat_add_to_common(actor_id: String) -> void:
	if _is_in_any_room(actor_id): return
	if _common.has(actor_id): return
	if actor_id == "hero": return
	_common.append(actor_id)
	dorms_changed.emit()
	common_added.emit(actor_id)

func assign_now_from_common(actor_id: String, to_room: String) -> Dictionary:
	if not _common.has(actor_id): return {"ok": false, "reason": "Character is not in Common Room."}
	if not ROOM_IDS.has(to_room): return {"ok": false, "reason": "Unknown room."}
	if to_room == "301" and actor_id != "hero": return {"ok": false, "reason": "RA room (301) is reserved."}
	for k_any in _staged_assign.keys():
		if String(_staged_assign[k_any]) == to_room:
			return {"ok": false, "reason":"Room is reserved for reassignment."}
	var occ: String = String((_rooms[to_room] as Dictionary).get("occupant",""))
	if occ != "": return {"ok": false, "reason": "Room not empty."}

	var prev_neigh: Array[String] = _current_neighbors_of_actor(actor_id)
	_rooms[to_room]["occupant"] = actor_id
	_common.erase(actor_id)
	var new_neigh: Array[String] = _current_neighbors_of_actor(actor_id)
	_mark_new_pairs_hidden(actor_id, prev_neigh, new_neigh, "common")

	_recompute_adjacency()
	_update_blocking_state()
	dorms_changed.emit()
	return {"ok": true}

func _is_in_any_room(actor_id: String) -> bool:
	for rid in ROOM_IDS:
		if String((_rooms[rid] as Dictionary).get("occupant","")) == actor_id: return true
	return false

# ───────────── staging / plan ─────────────
func can_start_reassignment_today() -> bool:
	var wd: int = _weekday_index()
	return wd == 6 # Sunday only

func begin_reassignment_for_room(room_id: String) -> Dictionary:
	if not ROOM_IDS.has(room_id): return {"ok": false, "reason": "Unknown room."}
	if not can_start_reassignment_today(): return {"ok": false, "reason": "Reassignment can only start on Sunday."}
	if room_id == "301": return {"ok": false, "reason": "RA room (301) cannot be cleared."}
	var who: String = String((_rooms[room_id] as Dictionary).get("occupant",""))
	if who == "": return {"ok": false, "reason": "Room is already empty."}
	if who == "hero": return {"ok": false, "reason": "Hero cannot be reassigned."}
	if _staged_common.has(who):
		_update_blocking_state()
		return {"ok": true}

	_staged_common.append(who)
	_staged_prev_room[who] = room_id
	_rooms[room_id]["occupant"] = ""
	_staged_assign.erase(who)

	_update_blocking_state()
	dorms_changed.emit()
	plan_changed.emit()
	return {"ok": true}

func cancel_reassignment_for(aid: String) -> void:
	if not _staged_common.has(aid): return
	var from_r: String = String(_staged_prev_room.get(aid, ""))
	if from_r != "": _rooms[from_r]["occupant"] = aid
	_staged_common.erase(aid)
	_staged_prev_room.erase(aid)
	_staged_assign.erase(aid)
	_locked_involved_rooms.clear()
	_plan_locked = false
	_update_blocking_state()
	dorms_changed.emit()
	plan_changed.emit()

func pick_room_for(aid: String, to_room: String) -> Dictionary:
	if not _staged_common.has(aid): return {"ok": false, "reason": "Character is not in reassignment staging."}
	if not ROOM_IDS.has(to_room): return {"ok": false, "reason": "Unknown room."}
	if to_room == "301": return {"ok": false, "reason": "RA room (301) is reserved."}
	var origin: String = String(_staged_prev_room.get(aid, ""))
	if origin != "" and origin == to_room: return {"ok": false, "reason": "That’s their current room; no reassignment needed."}
	var is_free: bool = (String((_rooms[to_room] as Dictionary).get("occupant","")) == "")
	for k_any in _staged_assign.keys():
		if String(_staged_assign[k_any]) == to_room and String(k_any) != aid:
			is_free = false
			break
	if not is_free: return {"ok": false, "reason": "Room is occupied or targeted by another reassignment."}
	_staged_assign[aid] = to_room
	_update_blocking_state()
	dorms_changed.emit()
	plan_changed.emit()
	return {"ok": true}

func reset_placement() -> void:
	for aid_k in _staged_prev_room.keys():
		var aid: String = String(aid_k)
		var r: String = String(_staged_prev_room[aid])
		if r != "" and String((_rooms[r] as Dictionary).get("occupant","")) == "":
			_rooms[r]["occupant"] = aid
	_staged_common.clear()
	_staged_prev_room.clear()
	_staged_assign.clear()
	_locked_involved_rooms.clear()
	_plan_locked = false
	_update_blocking_state()
	dorms_changed.emit()
	plan_changed.emit()

func accept_plan_for_saturday() -> Dictionary:
	if _staged_assign.size() == 0: return {"ok": false, "reason": "No reassignment selected."}
	_locked_involved_rooms.clear()
	for aid_k in _staged_assign.keys():
		var aid: String = String(aid_k)
		var from_r: String = String(_staged_prev_room.get(aid, ""))
		var to_r: String = String(_staged_assign.get(aid, ""))
		if from_r != "": _locked_involved_rooms[from_r] = true
		if to_r   != "": _locked_involved_rooms[to_r]   = true
	for aid2_k in _staged_prev_room.keys():
		var aid2: String = String(aid2_k)
		var fr: String = String(_staged_prev_room[aid2])
		if fr != "" and String((_rooms[fr] as Dictionary).get("occupant","")) == "": _rooms[fr]["occupant"] = aid2
	_plan_locked = true
	_update_blocking_state()
	dorms_changed.emit()
	plan_changed.emit()
	return {"ok": true}

func saturday_execute_changes() -> void:
	if not _plan_locked: return
	var moves: Array = []
	for aid_k in _staged_assign.keys():
		var aid: String = String(aid_k)
		var from_r: String = String(_staged_prev_room.get(aid, ""))
		var to_r: String = String(_staged_assign[aid])
		if from_r != "" and to_r != "" and from_r != to_r:
			moves.append({"aid": aid, "name": display_name(aid), "from": from_r, "to": to_r})
			# Apply move penalty: -2 affinity with protagonist for 1 week
			apply_move_penalty(aid)
	for aid_k2 in _staged_assign.keys():
		var aid2: String = String(aid_k2)
		var from_r2: String = String(_staged_prev_room.get(aid2, ""))
		var to_r2: String = String(_staged_assign[aid2])
		var prev_neigh: Array[String] = _current_neighbors_of_actor(aid2)
		if from_r2 != "" and String((_rooms[from_r2] as Dictionary).get("occupant","")) == aid2:
			_rooms[from_r2]["occupant"] = ""
		_rooms[to_r2]["occupant"] = aid2
		var new_neigh: Array[String] = _current_neighbors_of_actor(aid2)
		_mark_new_pairs_hidden(aid2, prev_neigh, new_neigh, "reassign")

	_staged_common.clear()
	_staged_prev_room.clear()
	_staged_assign.clear()
	_locked_involved_rooms.clear()
	_plan_locked = false

	_last_applied_moves = moves.duplicate(true)

	_recompute_adjacency()
	_update_blocking_state()
	dorms_changed.emit()
	plan_changed.emit()

	var snap: Dictionary = current_layout()
	saturday_applied.emit(snap)
	saturday_applied_v2.emit(snap, moves)

func current_layout() -> Dictionary:
	var d: Dictionary = {}
	for rid in ROOM_IDS:
		d[rid] = String((_rooms[rid] as Dictionary).get("occupant",""))
	return d

# ───────────── reveals ─────────────
func _reveal_friday_now() -> void:
	if _hidden_pairs_friday.size() == 0: return
	var pairs: Array = _collect_hidden_pairs(_hidden_pairs_friday, true)
	_hidden_pairs_friday.clear()
	_mark_pairs_discovered(pairs)
	dorms_changed.emit()
	friday_reveals_ready.emit(pairs)

func _reveal_saturday_now() -> void:
	if _hidden_pairs_saturday.size() == 0: return
	var pairs: Array = _collect_hidden_pairs(_hidden_pairs_saturday, true)
	_hidden_pairs_saturday.clear()
	_mark_pairs_discovered(pairs)
	dorms_changed.emit()
	saturday_reveals_ready.emit(pairs)

func _collect_hidden_pairs(pool: Dictionary, reveal_true: bool) -> Array:
	var out: Array = []
	for key in pool.keys():
		var k: String = String(key)
		var parts: PackedStringArray = k.split("|")
		if parts.size() != 2: continue
		var a: String = String(parts[0])
		var b: String = String(parts[1])
		var status: String = get_pair_status(a, b, reveal_true)
		out.append({"a": a, "b": b, "a_name": display_name(a), "b_name": display_name(b), "status": status})
	return out

func _mark_pairs_discovered(pairs: Array) -> void:
	for p_any in pairs:
		if typeof(p_any) == TYPE_DICTIONARY:
			var p: Dictionary = p_any
			var a: String = String(p.get("a",""))
			var b: String = String(p.get("b",""))
			if a != "" and b != "":
				_discovered_pairs[_pair_key(a,b)] = true

# ───────────── relationships / adjacency ─────────────
func _pair_key(a: String, b: String) -> String:
	var a2: String = String(a)
	var b2: String = String(b)
	return (a2 + "|" + b2) if a2 < b2 else (b2 + "|" + a2)

func _set_pair_status(a: String, b: String, status: String) -> void:
	_pair_status[_pair_key(a,b)] = status

func _get_base_relationship(a: String, b: String) -> String:
	if _bestie_map.has(a) and (_bestie_map[a] as Array).has(b): return "Bestie"
	if _bestie_map.has(b) and (_bestie_map[b] as Array).has(a): return "Bestie"
	if _rival_map.has(a) and (_rival_map[a] as Array).has(b):  return "Rival"
	if _rival_map.has(b) and (_rival_map[b] as Array).has(a):  return "Rival"
	if a == "hero" and b != "hero": return _hero_vs_npc_status(b)
	if b == "hero" and a != "hero": return _hero_vs_npc_status(a)
	return "Neutral"

func _hero_vs_npc_status(npc_id: String) -> String:
	var code: String = String(_stat_by_actor.get(npc_id, ""))
	if code == "NULL": return "Bestie"
	if code == "": return "Neutral"
	var picked: Dictionary = {}
	for p in _hero_picks: picked[String(p)] = true
	if picked.has(code): return "Bestie"
	if _hero_picks.size() == 3 and _ALL_STATS.has(code) and not picked.has(code): return "Rival"
	return "Neutral"

func _apply_hero_stat_relationships() -> void:
	for id_any in _name_by_id.keys():
		var aid: String = String(id_any)
		if aid == "hero": continue
		_set_pair_status("hero", aid, _hero_vs_npc_status(aid))

func _recompute_adjacency() -> void:
	_pair_status.clear()
	_apply_hero_stat_relationships()
	var seen: Dictionary = {}
	for rid in ROOM_IDS:
		var occ: String = String((_rooms[rid] as Dictionary).get("occupant",""))
		if occ == "": continue
		var neigh: PackedStringArray = room_neighbors(rid)
		for nr in neigh:
			var n_r: String = String(nr)
			var occ2: String = String((_rooms[n_r] as Dictionary).get("occupant",""))
			if occ2 == "": continue
			var key: String = _pair_key(occ, occ2)
			if seen.has(key): continue
			seen[key] = true
			var base_status: String = _get_base_relationship(occ, occ2)
			_set_pair_status(occ, occ2, base_status)

func _mark_new_pairs_hidden(aid: String, before_list: Array[String], after_list: Array[String], source: String) -> void:
	var before: Dictionary = {}
	for v in before_list: before[String(v)] = true
	for nb in after_list:
		var b: String = String(nb)
		if not before.has(b):
			var key: String = _pair_key(aid, b)
			if source == "reassign":
				_hidden_pairs_friday[key] = true
			else:
				_hidden_pairs_saturday[key] = true

func _current_neighbors_of_actor(aid: String) -> Array[String]:
	var out: Array[String] = []
	var room_of: String = ""
	for rid_val in ROOM_IDS:
		var rid: String = String(rid_val)
		if not _rooms.has(rid):
			continue
		var room_variant: Variant = _rooms[rid]
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room_data: Dictionary = room_variant as Dictionary
		if String(room_data.get("occupant","")) == aid:
			room_of = rid
			break
	if room_of == "":
		return out
	var neigh: PackedStringArray = room_neighbors(room_of)
	for nr in neigh:
		var rid2: String = String(nr)
		var who: String = String((_rooms[rid2] as Dictionary).get("occupant",""))
		if who != "":
			out.append(who)
	return out

# ───────────── UI helpers ─────────────
func get_pair_status(a: String, b: String, reveal_hidden: bool = false) -> String:
	var key: String = _pair_key(a, b)
	if not reveal_hidden and (_hidden_pairs_friday.has(key) or _hidden_pairs_saturday.has(key)) and not _discovered_pairs.has(key):
		return "Unknown"
	return String(_pair_status.get(key, _get_base_relationship(a, b)))

func neighbors_summary(room_id: String) -> Array:
	var out: Array = []
	var occ: String = String((_rooms[room_id] as Dictionary).get("occupant",""))
	if occ == "":
		return out
	var neigh: PackedStringArray = room_neighbors(room_id)
	for nr in neigh:
		var rid2: String = String(nr)
		var who: String = String((_rooms[rid2] as Dictionary).get("occupant",""))
		if who == "":
			continue
		var status: String = get_pair_status(occ, who, false)
		out.append({"room": rid2, "status": status, "aid": who, "name": display_name(who)})
	return out

# ───────────── misc / blocking ─────────────
func occupant_of(room_id: String) -> String:
	return String((_rooms.get(room_id, {}) as Dictionary).get("occupant",""))

func put_occupant(room_id: String, aid: String) -> void:
	if ROOM_IDS.has(room_id):
		_rooms[room_id]["occupant"] = aid

func reveal_all_pairs_now() -> void:
	_hidden_pairs_friday.clear()
	_hidden_pairs_saturday.clear()
	dorms_changed.emit()

func get_last_applied_moves() -> Array: return _last_applied_moves.duplicate(true)
func is_blocking_time_advance() -> bool: return _is_blocking_time_advance

func _compute_blocking() -> bool:
	return (_staged_common.size() > 0 or _staged_assign.size() > 0) and not _plan_locked

func _update_blocking_state() -> void:
	var b: bool = _compute_blocking()
	if b != _is_blocking_time_advance:
		_is_blocking_time_advance = b
		blocking_state_changed.emit(_is_blocking_time_advance)

# ───────────── compat for older UI ─────────────
func stage_vacate_room(room_id: String) -> Dictionary: return begin_reassignment_for_room(room_id)

func unstage_vacate_room(room_id: String) -> Dictionary:
	var aid: String = ""
	for k in _staged_prev_room.keys():
		var a: String = String(k)
		if String(_staged_prev_room[a]) == room_id:
			aid = a
			break
	if aid == "":
		return {"ok": false, "reason": "No staged reassignment for this room."}
	cancel_reassignment_for(aid)
	return {"ok": true}

func stage_set_target(aid: String, to_room: String) -> Dictionary: return pick_room_for(aid, to_room)
func stage_assign(aid: String, to_room: String) -> Dictionary: return pick_room_for(aid, to_room)
func stage_place(aid: String, to_room: String) -> Dictionary: return pick_room_for(aid, to_room)

func stage_clear_target(aid: String) -> void:
	_staged_assign.erase(aid)
	_update_blocking_state()
	dorms_changed.emit()
	plan_changed.emit()

func stage_accept_plan() -> Dictionary: return accept_plan_for_saturday()
func lock_plan_for_saturday() -> Dictionary: return accept_plan_for_saturday()
func stage_reset_plan() -> void: reset_placement()
func stage_reset() -> void:      reset_placement()

func is_plan_locked() -> bool: return _plan_locked

func get_locked_involved_rooms() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _locked_involved_rooms.keys(): out.append(String(k))
	return out

func can_accept_reassignment() -> Dictionary: return {"ok": has_pending_plan()}
func accept_reassignment_selection() -> Dictionary: return {"ok": _staged_common.size() > 0}

func can_lock_plan() -> Dictionary:
	if _staged_assign.size() == 0: return {"ok": false, "reason": "No reassignment selected."}
	for a in _staged_common:
		if not _staged_assign.has(String(a)): return {"ok": false, "reason": "Place everyone before accepting."}
	return {"ok": true}

func reset_only_assignments() -> void: reset_placement()

# ───────────── SAVE / LOAD (persistent dorms + discovery) ─────────────
func save() -> Dictionary:
	var blob: Dictionary = {}
	blob["rooms"] = current_layout()
	blob["common"] = _as_string_array(_common)
	blob["staged_common"] = _as_string_array(_staged_common)
	blob["staged_prev_room"] = _as_string_dict(_staged_prev_room)
	blob["staged_assign"] = _as_string_dict(_staged_assign)
	blob["plan_locked"] = _plan_locked

	var locked_keys := PackedStringArray()
	for k in _locked_involved_rooms.keys(): locked_keys.append(String(k))
	blob["locked_rooms"] = locked_keys

	var fri := PackedStringArray()
	for k2 in _hidden_pairs_friday.keys(): fri.append(String(k2))
	blob["hidden_friday"] = fri

	var sat := PackedStringArray()
	for k3 in _hidden_pairs_saturday.keys(): sat.append(String(k3))
	blob["hidden_saturday"] = sat

	var disc := PackedStringArray()
	for dk in _discovered_pairs.keys(): disc.append(String(dk))
	blob["discovered_pairs"] = disc

	# move penalties
	blob["move_penalties"] = _move_penalties.duplicate(true)

	return blob

func load(blob: Dictionary) -> void:
	if blob.is_empty(): return

	# layout
	if blob.has("rooms") and typeof(blob["rooms"]) == TYPE_DICTIONARY:
		_apply_rooms_from_layout(blob["rooms"] as Dictionary)
	else:
		_bootstrap_rooms()

	# common + staging
	_common = []
	for a in _as_string_array(blob.get("common", [])): _common.append(a)

	_staged_common.clear()
	for a2 in _as_string_array(blob.get("staged_common", [])): _staged_common.append(a2)

	_staged_prev_room = _as_string_dict(blob.get("staged_prev_room", {}))
	_staged_assign    = _as_string_dict(blob.get("staged_assign", {}))

	_plan_locked = bool(blob.get("plan_locked", false))

	_locked_involved_rooms.clear()
	for rid in _as_string_array(blob.get("locked_rooms", [])):
		_locked_involved_rooms[String(rid)] = true

	_hidden_pairs_friday.clear()
	for kf in _as_string_array(blob.get("hidden_friday", [])):
		_hidden_pairs_friday[String(kf)] = true

	_hidden_pairs_saturday.clear()
	for ks in _as_string_array(blob.get("hidden_saturday", [])):
		_hidden_pairs_saturday[String(ks)] = true

	_discovered_pairs.clear()
	for dk in _as_string_array(blob.get("discovered_pairs", [])):
		_discovered_pairs[String(dk)] = true

	# move penalties
	_move_penalties.clear()
	if blob.has("move_penalties") and typeof(blob["move_penalties"]) == TYPE_DICTIONARY:
		_move_penalties = (blob["move_penalties"] as Dictionary).duplicate(true)

	# sanity: ensure hero exists somewhere
	var hero_found: bool = false
	for rid2 in ROOM_IDS:
		if occupant_of(rid2) == "hero":
			hero_found = true
			break
	if not hero_found:
		if occupant_of("301") == "":
			put_occupant("301", "hero")
		else:
			for rid3 in ROOM_IDS:
				if occupant_of(rid3) == "":
					put_occupant(rid3, "hero")
					break

	_recompute_adjacency()
	_update_blocking_state()
	dorms_changed.emit()
	plan_changed.emit()

# helpers for save/load
func _as_string_array(v: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	match typeof(v):
		TYPE_PACKED_STRING_ARRAY:
			return v as PackedStringArray
		TYPE_ARRAY:
			for it in (v as Array): out.append(String(it))
	return out

func _as_string_dict(v: Variant) -> Dictionary:
	var out: Dictionary = {}
	if typeof(v) == TYPE_DICTIONARY:
		for k in (v as Dictionary).keys():
			out[String(k)] = String((v as Dictionary)[k])
	return out

func _apply_rooms_from_layout(layout: Dictionary) -> void:
	for rid in ROOM_IDS: _rooms[rid]["occupant"] = ""
	for k in layout.keys():
		var rid: String = String(k)
		if ROOM_IDS.has(rid):
			_rooms[rid]["occupant"] = String(layout[k])

func _set_dict_keys_true(dst: Dictionary, keys: PackedStringArray) -> void:
	for k in keys: dst[String(k)] = true

## ═══════════════════════════════════════════════════════════════════════════
## MOVE PENALTY SYSTEM
## ═══════════════════════════════════════════════════════════════════════════

func apply_move_penalty(actor_id: String) -> void:
	"""Apply -2 affinity penalty with protagonist for 1 week after room reassignment"""
	var current_week = _get_current_week_number()
	_move_penalties[actor_id] = {
		"penalty": -2,
		"applied_week": current_week,
		"expires_week": current_week + 1
	}
	print("[DormSystem] Applied move penalty to %s (expires week %d)" % [actor_id, current_week + 1])

func get_move_penalty(actor_id: String) -> int:
	"""Get current move penalty for actor (0 if none/expired)"""
	if not _move_penalties.has(actor_id):
		return 0

	var penalty_data: Dictionary = _move_penalties[actor_id]
	var current_week = _get_current_week_number()
	var expires_week = penalty_data.get("expires_week", 0)

	if current_week >= expires_week:
		# Penalty expired
		_move_penalties.erase(actor_id)
		return 0

	return penalty_data.get("penalty", 0)

func cleanup_expired_move_penalties() -> void:
	"""Remove all expired move penalties (called on day change)"""
	var current_week = _get_current_week_number()
	var to_remove: Array[String] = []

	for actor_id in _move_penalties.keys():
		var penalty_data: Dictionary = _move_penalties[actor_id]
		var expires_week = penalty_data.get("expires_week", 0)
		if current_week >= expires_week:
			to_remove.append(actor_id)

	for actor_id in to_remove:
		_move_penalties.erase(actor_id)
		print("[DormSystem] Removed expired move penalty for %s" % actor_id)

func _get_current_week_number() -> int:
	"""Get current week number from CalendarSystem"""
	if _calendar_node == null:
		return 0

	# Try to get week number from calendar
	for method in ["get_week", "get_week_number", "week", "week_number"]:
		if _calendar_node.has_method(method):
			var result = _calendar_node.call(method)
			if typeof(result) == TYPE_INT:
				return result

	# Fallback: calculate from day number
	for method in ["get_day", "get_day_number", "day", "day_number", "total_days"]:
		if _calendar_node.has_method(method):
			var result = _calendar_node.call(method)
			if typeof(result) == TYPE_INT:
				return int(result / 7)  # Weeks = days / 7

	return 0

## ═══════════════════════════════════════════════════════════════════════════
## AFFINITY POWER CALCULATION
## ═══════════════════════════════════════════════════════════════════════════

func calculate_affinity_power(actor_id: String) -> Dictionary:
	"""
	Calculate total affinity power for an actor

	Affinity Power = Neighbor Score + Battle Affinity Bonus + Move Penalty
	Capped at -3 to +5

	Returns: {
		"neighbor_score": int,      # -3 to +3 from dorm neighbors
		"battle_affinity": int,     # 0 to +2 from active party AT level
		"move_penalty": int,        # -2 if moved this week, else 0
		"total_affinity": int,      # Sum, capped at -3 to +5
		"roll_bonus": int           # Final roll bonus: -4 to +10
	}
	"""
	var neighbor_score: int = _calculate_neighbor_score(actor_id)
	var battle_bonus: int = _get_battle_affinity_bonus(actor_id)
	var move_pen: int = get_move_penalty(actor_id)

	# Calculate total (neighbor + battle + penalty)
	var total: int = neighbor_score + battle_bonus + move_pen

	# Cap at -3 to +5 (max affinity power)
	total = clampi(total, -3, 5)

	# Convert to roll bonus
	var roll_bonus: int = _affinity_to_roll_bonus(total)

	return {
		"neighbor_score": neighbor_score,
		"battle_affinity": battle_bonus,
		"move_penalty": move_pen,
		"total_affinity": total,
		"roll_bonus": roll_bonus
	}

func _calculate_neighbor_score(actor_id: String) -> int:
	"""
	Count besties/rivals among neighbors, return -3 to +3

	Each bestie neighbor: +1
	Each rival neighbor: -1
	Neutral neighbors: 0
	"""
	var neighbors: Array[String] = _current_neighbors_of_actor(actor_id)
	var bestie_count: int = 0
	var rival_count: int = 0

	for neighbor_id in neighbors:
		var status: String = get_pair_status(actor_id, neighbor_id)
		if status == "Bestie":
			bestie_count += 1
		elif status == "Rival":
			rival_count += 1
		# Neutral = 0, don't count

	var score: int = bestie_count - rival_count
	return clampi(score, -3, 3)  # Cap at -3 to +3

func _get_battle_affinity_bonus(actor_id: String) -> int:
	"""
	Get battle affinity bonus if actor is in active party with appropriate AT levels

	AT2 with another active party member = +1
	AT3 with another active party member = +2

	Returns highest bonus from any active party pairing
	"""
	var aff_sys = get_node_or_null("/root/aAffinitySystem")
	if not aff_sys:
		return 0

	var gs = get_node_or_null("/root/aGameState")
	if not gs or not gs.has_method("get"):
		return 0

	# Get active party (should be 3 members)
	var party_v = gs.get("party")
	var active_party: Array[String] = []
	if typeof(party_v) == TYPE_ARRAY:
		for member in party_v:
			active_party.append(String(member))
	elif typeof(party_v) == TYPE_PACKED_STRING_ARRAY:
		for member in (party_v as PackedStringArray):
			active_party.append(String(member))

	# Check if actor is in active party
	if not active_party.has(actor_id):
		return 0  # Not in active party, no battle bonus

	# Check affinity tiers with other active party members
	var highest_bonus = 0

	for other_member in active_party:
		if other_member == actor_id:
			continue  # Skip self

		# Get affinity tier for this pair
		var tier = 0
		if aff_sys.has_method("get_affinity_tier"):
			tier = aff_sys.call("get_affinity_tier", actor_id, other_member)

		# Convert tier to bonus
		# AT2 = +1, AT3 = +2
		var bonus = 0
		if tier >= 3:  # AT3
			bonus = 2
		elif tier >= 2:  # AT2
			bonus = 1

		highest_bonus = max(highest_bonus, bonus)

	return highest_bonus

func _affinity_to_roll_bonus(affinity: int) -> int:
	"""
	Convert affinity level to roll bonus

	Based on affinity_power_config.csv:
	-3 → -4 (three rivals)
	-2 → -2 (two rivals, one neutral)
	-1 → -1 (one rival, two neutrals)
	 0 →  0 (all neutral)
	 1 →  1 (mixed or one bestie)
	 2 →  2 (two besties, one neutral)
	 3 →  4 (three besties)
	 4 →  8 (three besties + AT2)
	 5 → 10 (three besties + AT3) [MAX]
	"""
	match affinity:
		-3: return -4
		-2: return -2
		-1: return -1
		0: return 0
		1: return 1
		2: return 2
		3: return 4
		4: return 8
		5: return 10
		_: return 0
