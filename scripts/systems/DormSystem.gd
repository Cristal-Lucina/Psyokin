extends Node
class_name DormsSystem

signal dorms_changed
signal plan_changed
signal saturday_applied(new_layout: Dictionary)        # legacy: layout only (compat)
signal saturday_applied_v2(new_layout: Dictionary, moves: Array) # new: layout + moves
signal common_added(aid: String)

# NEW: results signals you can hook from Main/UI
signal friday_reveals_ready(pairs: Array)              # pairs revealed on Friday (from prior-Saturday reassignments)
signal saturday_reveals_ready(pairs: Array)            # pairs revealed on Saturday (from midweek Common placements)

# NEW: broadcast when reassignment is in-progress (blocks day-advance UX until Accept Plan)
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

# Names / normalization
var _name_by_id: Dictionary = {}     # actor_id -> display name
var _id_norm_map: Dictionary = {}    # normalized token (id/display) -> actor_id

# hero_neighbors stat map (from CSV, with hardcoded fallback)
# values are "BRW","MND","TPO","VTL","FCS" or "NULL"
var _stat_by_actor: Dictionary = {}  # actor_id -> String

# Hero picks (exactly 3) from CharacterCreation -> GameState meta/API
var _hero_picks: Array[String] = []

# Rooms + Common
var _rooms: Dictionary = {}          # room_id -> {"name":rid, "occupant": String}
var _common: Array[String] = []      # unassigned (true Common)
# Weekly staging (treated like "Common" for UI until placed)
var _staged_common: Array[String] = []
var _staged_prev_room: Dictionary = {}  # aid -> from_room
var _staged_assign: Dictionary = {}     # aid -> to_room
var _plan_locked: bool = false
var _locked_involved_rooms: Dictionary = {} # room_id -> true

# Relationships (optional CSV hints)
var _bestie_map: Dictionary = {} # aid -> Array[String]
var _rival_map : Dictionary = {} # aid -> Array[String]

# Adjacency cache (current true labels)
var _pair_status: Dictionary = {} # "a|b" -> "Bestie"/"Rival"/"Neutral"

# Hiding pools
# - Pairs created by Saturday reassignments → reveal next Friday
var _hidden_pairs_friday: Dictionary = {}   # "a|b" -> true
# - Pairs created by immediate Common placements → reveal next Saturday
var _hidden_pairs_saturday: Dictionary = {} # "a|b" -> true

# Saturday reporting cache
var _last_applied_moves: Array = []         # [{aid,name,from,to}...]

# Calendar discovery
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

# Cached weekday (shared by reveals + gating)
var _last_weekday_index: int = -1     # 0=Mon..6=Sun
var _last_weekday_name: String = ""

# Local blocking mirror (so external UI can query)
var _is_blocking_time_advance: bool = false

enum RoomVisual { EMPTY_GREEN, OCCUPIED_BLUE, STAGED_YELLOW, LOCKED_RED }

# CSV header aliases
const _ID_KEYS      := ["actor_id","id","actor","member_id"]
const _NAME_KEYS    := ["name","display_name","disp_name"]
const _BESTIE_KEYS  := ["bestie_buff","besties","bestie","bestie_ids"]
const _RIVAL_KEYS   := ["rival_debuff","rivals","rival","rival_ids"]
const _NEIGH_KEYS   := ["hero_neighbors","hero_neighbours","neighbor_stat","neighbor","neigh","stat","pref_stat"]

# candidate CSV paths
const _PARTY_CANDIDATES := [
	"res://data/party/party.csv",
	"res://data/Party.csv",
	"res://data/party.csv",
	"res://data/characters/party.csv",
	"res://data/actors/party.csv",
	"res://data/actors.csv"
]

# Stat aliases → 3-letter code (no blank→NULL mapping)
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
	_pull_gs_metadata() # <- hero name + picked stats
	_bind_calendar()
	if get_tree() != null:
		get_tree().connect("node_added", Callable(self, "_on_tree_node_added"))
	_recompute_adjacency()
	_update_blocking_state()
	dorms_changed.emit()

# ─────────────────────────────────────────────────────────────
# Calendar glue
# ─────────────────────────────────────────────────────────────
func set_calendar(node: Node) -> void:
	if node == null or node == _calendar_node:
		return
	_calendar_node = node
	_connect_calendar_signals()

func _on_tree_node_added(n: Node) -> void:
	if _calendar_node != null:
		return
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
	if _calendar_node == null:
		return
	for sig in _CAL_SIGNALS:
		if _calendar_node.has_signal(sig) and not _calendar_node.is_connected(sig, Callable(self, "_on_calendar_day_changed")):
			_calendar_node.connect(sig, Callable(self, "_on_calendar_day_changed").bind(sig))

# Map weekday name/str → index
func _weekday_name_to_index(s: String) -> int:
	if s == null:
		return -1
	var t := String(s).strip_edges().to_lower()
	if t.begins_with("mon") or t == "0": return 0
	if t.begins_with("tue") or t == "1": return 1
	if t.begins_with("wed") or t == "2": return 2
	if t.begins_with("thu") or t == "3": return 3
	if t.begins_with("fri") or t == "4": return 4
	if t.begins_with("sat") or t == "5": return 5
	if t.begins_with("sun") or t == "6": return 6
	return -1

# manual nudge if needed (accepts weekday name)
func calendar_notify_weekday(weekday_name: String) -> void:
	_last_weekday_name = weekday_name
	_last_weekday_index = _weekday_name_to_index(weekday_name)
	# If we are blocking (unaccepted plan), swallow reveals/apply
	if _compute_blocking():
		return
	if _is_friday_name(weekday_name):
		_reveal_friday_now()
	elif _is_saturday_name(weekday_name):
		if _plan_locked:
			saturday_execute_changes()
		_reveal_saturday_now()

# NOTE: emitted args first, then bound sig name last
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
					if (typeof(got2) == TYPE_INT or typeof(got2) == TYPE_FLOAT):
						idx = int(got2)
						break

	# Cache what we learned (prefer numeric, fallback to name)
	var idx2 := idx
	if idx2 < 0:
		idx2 = _weekday_name_to_index(wd_name)
	if idx2 >= 0:
		_last_weekday_index = idx2
	if wd_name != "":
		_last_weekday_name = wd_name

	# If we are blocking (unaccepted plan), swallow weekday effects
	if _compute_blocking():
		return

	# Friday: reveal only the pairs created by last Saturday reassignments.
	if _is_friday_name(wd_name) or _is_friday_index(idx2):
		_reveal_friday_now()
		return

	# Saturday: apply plan (if any), then reveal pairs created by midweek Common placements.
	if _is_saturday_name(wd_name) or _is_saturday_index(idx2):
		if _plan_locked:
			saturday_execute_changes()
		_reveal_saturday_now()

func _weekday_index() -> int:
	# 0=Mon .. 6=Sun
	if _calendar_node != null:
		for m in ["get_weekday","day_of_week","weekday","dow","current_weekday"]:
			if _calendar_node.has_method(m):
				var v: Variant = _calendar_node.call(m)
				if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
					return int(v)
				elif typeof(v) == TYPE_STRING:
					var idx_from_str := _weekday_name_to_index(String(v))
					if idx_from_str != -1:
						return idx_from_str
	# Try name getters and map
	for m2 in ["get_weekday_name","get_day_name","weekday_name","day_name"]:
		if _calendar_node != null and _calendar_node.has_method(m2):
			var s := String(_calendar_node.call(m2))
			var idx2 := _weekday_name_to_index(s)
			if idx2 != -1:
				return idx2

	# Fall back to what we last saw through calendar signals/manual notify
	if _last_weekday_index != -1:
		return _last_weekday_index
	if _last_weekday_name != "":
		var idx3 := _weekday_name_to_index(_last_weekday_name)
		if idx3 != -1:
			return idx3
	return -1

func _is_friday_name(s: String) -> bool:
	if s == null:
		return false
	var t: String = String(s).strip_edges().to_lower()
	return t.begins_with("fri") or t == "4" # 0=Mon..6=Sun → Fri=4

func _is_friday_index(i: int) -> bool:
	return i == 4 # 0=Mon..6=Sun → Fri=4

func _is_saturday_name(s: String) -> bool:
	if s == null:
		return false
	var t: String = String(s).strip_edges().to_lower()
	return t.begins_with("sat") or t == "5" # 0=Mon..6=Sun → Sat=5

func _is_saturday_index(i: int) -> bool:
	return i == 5 # 0=Mon..6=Sun → Sat=5

# ─────────────────────────────────────────────────────────────
# Bootstrap + CSV (names & relationships & hero_neighbors)
# ─────────────────────────────────────────────────────────────
func _bootstrap_rooms() -> void:
	_rooms.clear()
	for rid in ROOM_IDS:
		_rooms[rid] = {"name": rid, "occupant": ""}
	_rooms["301"]["occupant"] = "hero" # RA room

func _norm_header(s: String) -> String:
	var t: String = String(s).to_lower().strip_edges()
	t = t.replace(",", "")
	t = t.replace("\t", "")
	return t

func _norm_id_token(s: String) -> String:
	var t: String = String(s).to_lower().strip_edges()
	t = t.replace("-", "_")
	t = t.replace(" ", "_")
	while t.find("__") != -1:
		t = t.replace("__","_")
	return t

func _canon_id(token: String) -> String:
	var norm: String = _norm_id_token(token)
	if _id_norm_map.has(norm):
		return String(_id_norm_map[norm])
	return token

func _best_fit_party_csv() -> String:
	for p in _PARTY_CANDIDATES:
		if FileAccess.file_exists(p):
			return p
	return ""

func _ensure_hero_in_maps() -> void:
	if not _name_by_id.has("hero"):
		_name_by_id["hero"] = "Hero"
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

	var f := FileAccess.open(path, FileAccess.READ)
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
		if nm != "":
			_id_norm_map[_norm_id_token(nm)] = aid

		var bestie_val: Variant = (cols[idx_bestie] if idx_bestie >= 0 and idx_bestie < cols.size() else "")
		var rival_val : Variant = (cols[idx_rival]  if idx_rival  >= 0 and idx_rival  < cols.size() else "")
		_bestie_map[aid] = _parse_rel_list_val_to_ids(bestie_val)
		_rival_map[aid]  = _parse_rel_list_val_to_ids(rival_val)

		# hero_neighbors stat — only store if we actually resolve something (no blank->NULL mapping)
		var raw_stat: String = (cols[idx_neigh] if idx_neigh >= 0 and idx_neigh < cols.size() else "").strip_edges().to_upper()
		var code: String = ""
		if raw_stat != "":
			if _STAT_ALIAS.has(raw_stat):
				code = String(_STAT_ALIAS[raw_stat])
			elif raw_stat.length() >= 3:
				var guess: String = raw_stat.substr(0,3)
				if _ALL_STATS.has(guess):
					code = guess
		if code != "":
			_stat_by_actor[aid] = code

	f.close()
	_ensure_hero_in_maps()
	_seed_hardcoded_stat_map_if_missing()

func _parse_rel_list_val_to_ids(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(v) == TYPE_STRING:
		var s: String = String(v).replace(";", ",").replace("|", ",")
		var parts: PackedStringArray = s.split(",", false)
		for i in range(parts.size()):
			var raw: String = String(parts[i]).strip_edges()
			if raw == "":
				continue
			var norm: String = _norm_id_token(raw)
			if _id_norm_map.has(norm):
				out.append(String(_id_norm_map[norm]))
			else:
				out.append(raw)
	return out

func _seed_hardcoded_stat_map_if_missing() -> void:
	# Canonical IDs (from party.csv) → [DisplayName, StatCode]
	var CANON := {
		"red_girl":     ["Risa",    "BRW"],
		"secret_girl":  ["Tessa",   "MND"],
		"blue_girl":    ["Skye",    "TPO"],
		"green_friend": ["Matcha",  "VTL"],
		"scientist":    ["Douglas", "FCS"],
		"best_friend":  ["Kai",     "NULL"],
		"ai_friend":    ["Sev",     "NULL"],
	}

	# Fill missing stat prefs only (CSV still wins when present)
	for id_key in CANON.keys():
		var disp: String = String(CANON[id_key][0])
		var stat: String = String(CANON[id_key][1])

		if not _stat_by_actor.has(id_key):
			_stat_by_actor[id_key] = stat

		# Ensure normalization tokens resolve even without CSV
		_id_norm_map[_norm_id_token(id_key)] = id_key
		_id_norm_map[_norm_id_token(disp)] = id_key

		# Seed a friendly name if one isn't already set
		if not _name_by_id.has(id_key):
			_name_by_id[id_key] = disp

# Pull hero name + 3 starting picks from GameState/StatsSystem
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

	if gs != null:
		if gs.has_method("get_hero_start_picks"):
			var hv: Variant = gs.call("get_hero_start_picks")
			match typeof(hv):
				TYPE_PACKED_STRING_ARRAY:
					var psa: PackedStringArray = hv
					for i in range(psa.size()): _hero_picks.append(String(psa[i]).to_upper())
				TYPE_ARRAY:
					var arr: Array = hv
					for j in range(arr.size()): _hero_picks.append(String(arr[j]).to_upper())
		if _hero_picks.size() == 0:
			if gs.has_meta("hero_start_picks"):
				var m: Variant = gs.get_meta("hero_start_picks")
				if typeof(m) == TYPE_PACKED_STRING_ARRAY:
					var psa2: PackedStringArray = m
					for i2 in range(psa2.size()): _hero_picks.append(String(psa2[i2]).to_upper())
			elif gs.has_meta("hero_picked_stats"):
				var m2: Variant = gs.get_meta("hero_picked_stats")
				if typeof(m2) == TYPE_PACKED_STRING_ARRAY:
					var psa3: PackedStringArray = m2
					for i3 in range(psa3.size()): _hero_picks.append(String(psa3[i3]).to_upper())

	if _hero_picks.size() == 0:
		var st: Node = get_node_or_null("/root/aStatsSystem")
		if st != null and st.has_method("get_hero_start_picks"):
			var sv: Variant = st.call("get_hero_start_picks")
			match typeof(sv):
				TYPE_PACKED_STRING_ARRAY:
					var ps: PackedStringArray = sv
					for k in range(ps.size()): _hero_picks.append(String(ps[k]).to_upper())
				TYPE_ARRAY:
					var ar: Array = sv
					for k2 in range(ar.size()): _hero_picks.append(String(ar[k2]).to_upper())

	if _hero_picks.size() == 0:
		var st2: Node = get_node_or_null("/root/aStatsSystem")
		if st2 != null and st2.has_method("get_stat"):
			for code in ["BRW","MND","TPO","VTL","FCS"]:
				var lv: Variant = st2.call("get_stat", code)
				if (typeof(lv) in [TYPE_INT, TYPE_FLOAT]) and int(lv) > 1:
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

# ─────────────────────────────────────────────────────────────
# Queries
# ─────────────────────────────────────────────────────────────
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
	# Merge: true Common + staged people not yet assigned
	var merged_list: Array[String] = _common.duplicate()
	for aid in _staged_common:
		if not _staged_assign.has(aid) and not merged_list.has(aid):
			merged_list.append(aid)
	var out := PackedStringArray()
	for a in merged_list:
		out.append(a)
	return out

func room_neighbors(room_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	var arr_v: Variant = NEIGHBORS.get(room_id, [])
	if typeof(arr_v) == TYPE_ARRAY:
		var arr: Array = arr_v
		for i in range(arr.size()):
			out.append(String(arr[i]))
	return out

func room_in_locked_plan(room_id: String) -> bool:
	return _plan_locked and _locked_involved_rooms.has(room_id)

func get_locked_warning_for(room_id: String) -> String:
	return "(Room Reassignments happening on Saturday)" if room_in_locked_plan(room_id) else ""

func get_staged_prev_room_for(aid: String) -> String:
	return String(_staged_prev_room.get(aid, ""))

func get_room_visual(room_id: String) -> int:
	# After Accept Plan (plan locked), tiles should look normal (no red/yellow),
	# but the right panel still shows a banner for involved rooms.
	if _plan_locked:
		var r_locked: Dictionary = get_room(room_id)
		var who_locked: String = String(r_locked.get("occupant",""))
		return (RoomVisual.EMPTY_GREEN if who_locked == "" else RoomVisual.OCCUPIED_BLUE)

	# During staging, paint yellow for origin and targets
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

func is_staged(aid: String) -> bool:
	return _staged_common.has(aid)

func staged_size() -> int:
	return _staged_common.size()

func staged_assign_size() -> int:
	return _staged_assign.size()

func is_pair_hidden(a: String, b: String) -> bool:
	var key := _pair_key(a, b)
	return _hidden_pairs_friday.has(key) or _hidden_pairs_saturday.has(key)

func list_current_placements() -> Array:
	var out: Array = []
	for rid in ROOM_IDS:
		var who: String = String((_rooms[rid] as Dictionary).get("occupant",""))
		out.append({
			"room": rid,
			"aid": who,
			"name": (display_name(who) if who != "" else "— empty —")
		})
	return out

func list_upcoming_reassignments() -> Array:
	var out: Array = []
	for aid_k in _staged_assign.keys():
		var aid: String = String(aid_k)
		var to_r: String = String(_staged_assign[aid])
		var from_r: String = String(_staged_prev_room.get(aid, ""))
		out.append({
			"aid": aid,
			"name": display_name(aid),
			"from": from_r,
			"to": to_r
		})
	return out

func get_staged_target_for(aid: String) -> String:
	return String(_staged_assign.get(aid, ""))

func get_staged_assignments() -> Dictionary:
	return _staged_assign.duplicate(true)

func staged_target_for(aid: String) -> String: return get_staged_target_for(aid)
func staged_assignments() -> Dictionary:       return get_staged_assignments()
func get_all_staged_members() -> PackedStringArray:
	var out := PackedStringArray()
	for i in range(_staged_common.size()):
		out.append(_staged_common[i])
	return out
func list_staged_members() -> PackedStringArray: return get_all_staged_members()

# ─────────────────────────────────────────────────────────────
# Cheats & immediate placement
# ─────────────────────────────────────────────────────────────
func cheat_add_to_common(actor_id: String) -> void:
	if _is_in_any_room(actor_id): return
	if _common.has(actor_id): return
	if actor_id == "hero": return
	_common.append(actor_id)
	dorms_changed.emit()
	common_added.emit(actor_id) # <-- tell the menu to auto-open Dorms

func assign_now_from_common(actor_id: String, to_room: String) -> Dictionary:
	if not _common.has(actor_id):
		return {"ok": false, "reason": "Character is not in Common Room."}
	if not ROOM_IDS.has(to_room):
		return {"ok": false, "reason": "Unknown room."}
	if to_room == "301" and actor_id != "hero":
		return {"ok": false, "reason": "RA room (301) is reserved."}
	for k_any in _staged_assign.keys():
		if String(_staged_assign[k_any]) == to_room:
			return {"ok": false, "reason":"Room is reserved for reassignment."}
	var occ: String = String((_rooms[to_room] as Dictionary).get("occupant",""))
	if occ != "":
		return {"ok": false, "reason": "Room not empty."}

	var prev_neigh: Array[String] = _current_neighbors_of_actor(actor_id)
	_rooms[to_room]["occupant"] = actor_id
	_common.erase(actor_id)
	var new_neigh: Array[String] = _current_neighbors_of_actor(actor_id)
	_mark_new_pairs_hidden(actor_id, prev_neigh, new_neigh, "common") # SATURDAY bucket

	_recompute_adjacency()
	_update_blocking_state()
	dorms_changed.emit()
	return {"ok": true}

func _is_in_any_room(actor_id: String) -> bool:
	for rid in ROOM_IDS:
		if String((_rooms[rid] as Dictionary).get("occupant","")) == actor_id:
			return true
	return false

# ─────────────────────────────────────────────────────────────
# Staging flow (weekly plan)
# ─────────────────────────────────────────────────────────────
func can_start_reassignment_today() -> bool:
	var wd: int = _weekday_index()
	# Sunday-only (0=Mon..6=Sun)
	return wd == 6

func begin_reassignment_for_room(room_id: String) -> Dictionary:
	if not ROOM_IDS.has(room_id):
		return {"ok": false, "reason": "Unknown room."}
	if not can_start_reassignment_today():
		return {"ok": false, "reason": "Reassignment can only start on Sunday."}
	if room_id == "301":
		return {"ok": false, "reason": "RA room (301) cannot be cleared."}
	var who: String = String((_rooms[room_id] as Dictionary).get("occupant",""))
	if who == "":
		return {"ok": false, "reason": "Room is already empty."}
	if who == "hero":
		return {"ok": false, "reason": "Hero cannot be reassigned."}
	if _staged_common.has(who):
		_update_blocking_state()
		return {"ok": true}

	_staged_common.append(who)
	_staged_prev_room[who] = room_id
	_rooms[room_id]["occupant"] = ""    # turn the tile yellow via visual
	_staged_assign.erase(who)

	_update_blocking_state()
	dorms_changed.emit()
	plan_changed.emit()
	return {"ok": true}

func cancel_reassignment_for(aid: String) -> void:
	if not _staged_common.has(aid):
		return
	var from_r: String = String(_staged_prev_room.get(aid, ""))
	if from_r != "":
		_rooms[from_r]["occupant"] = aid
	_staged_common.erase(aid)
	_staged_prev_room.erase(aid)
	_staged_assign.erase(aid)
	_locked_involved_rooms.clear()
	_plan_locked = false
	_update_blocking_state()
	dorms_changed.emit()
	plan_changed.emit()

func pick_room_for(aid: String, to_room: String) -> Dictionary:
	if not _staged_common.has(aid):
		return {"ok": false, "reason": "Character is not in reassignment staging."}
	if not ROOM_IDS.has(to_room):
		return {"ok": false, "reason": "Unknown room."}
	if to_room == "301":
		return {"ok": false, "reason": "RA room (301) is reserved."}

	# Don’t allow placing them back to their origin room
	var origin: String = String(_staged_prev_room.get(aid, ""))
	if origin != "" and origin == to_room:
		return {"ok": false, "reason": "That’s their current room; no reassignment needed."}

	var is_empty_preview: bool = (String((_rooms[to_room] as Dictionary).get("occupant","")) == "")
	for k_any in _staged_assign.keys():
		if String(_staged_assign[k_any]) == to_room and String(k_any) != aid:
			is_empty_preview = false
			break
	if not is_empty_preview:
		return {"ok": false, "reason": "Room is occupied or targeted by another reassignment."}

	_staged_assign[aid] = to_room
	_update_blocking_state() # still blocking until Accept Plan
	dorms_changed.emit()
	plan_changed.emit()
	return {"ok": true}

func reset_placement() -> void:
	# restore live layout back to before staging (safe no-op if already restored)
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
	if _staged_assign.size() == 0:
		return {"ok": false, "reason": "No reassignment selected."}

	# Compute involved rooms for banner visibility
	_locked_involved_rooms.clear()
	for aid_k in _staged_assign.keys():
		var aid: String = String(aid_k)
		var from_r: String = String(_staged_prev_room.get(aid, ""))
		var to_r: String = String(_staged_assign.get(aid, ""))
		if from_r != "": _locked_involved_rooms[from_r] = true
		if to_r   != "": _locked_involved_rooms[to_r]   = true

	# IMPORTANT: After accepting, live layout reverts to pre-staging (no yellow/red tiles).
	for aid2_k in _staged_prev_room.keys():
		var aid2: String = String(aid2_k)
		var fr: String = String(_staged_prev_room[aid2])
		if fr != "":
			_rooms[fr]["occupant"] = aid2

	_plan_locked = true

	_update_blocking_state() # accepting clears the "block day" guard
	dorms_changed.emit()
	plan_changed.emit()
	return {"ok": true}

func saturday_execute_changes() -> void:
	if not _plan_locked:
		return

	# Capture moves (only where from != to)
	var moves: Array = []
	for aid_k in _staged_assign.keys():
		var aid: String = String(aid_k)
		var from_r: String = String(_staged_prev_room.get(aid, ""))
		var to_r: String = String(_staged_assign[aid])
		if from_r != "" and to_r != "" and from_r != to_r:
			moves.append({
				"aid": aid,
				"name": display_name(aid),
				"from": from_r,
				"to": to_r
			})

	# Apply the layout
	for aid_k2 in _staged_assign.keys():
		var aid2: String = String(aid_k2)
		var from_r2: String = String(_staged_prev_room.get(aid2, ""))
		var to_r2: String = String(_staged_assign[aid2])

		var prev_neigh: Array[String] = _current_neighbors_of_actor(aid2)

		if from_r2 != "" and String((_rooms[from_r2] as Dictionary).get("occupant","")) == aid2:
			_rooms[from_r2]["occupant"] = ""
		_rooms[to_r2]["occupant"] = aid2

		var new_neigh: Array[String] = _current_neighbors_of_actor(aid2)
		# Reassignments create Friday-reveal pairs
		_mark_new_pairs_hidden(aid2, prev_neigh, new_neigh, "reassign")

	# Clean staging state
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

	# Signals: legacy and extended
	var snap := current_layout()
	saturday_applied.emit(snap)                 # legacy (panel will catch this)
	saturday_applied_v2.emit(snap, moves)       # new (optional)

func current_layout() -> Dictionary:
	var d: Dictionary = {}
	for rid in ROOM_IDS:
		d[rid] = String((_rooms[rid] as Dictionary).get("occupant",""))
	return d

# ─────────────────────────────────────────────────────────────
# Friday/Saturday reveal drivers
# ─────────────────────────────────────────────────────────────
func _reveal_friday_now() -> void:
	if _hidden_pairs_friday.size() == 0:
		return
	var pairs := _collect_hidden_pairs(_hidden_pairs_friday, true) # reveal true status
	_hidden_pairs_friday.clear()
	dorms_changed.emit()
	friday_reveals_ready.emit(pairs)

func _reveal_saturday_now() -> void:
	if _hidden_pairs_saturday.size() == 0:
		return
	var pairs := _collect_hidden_pairs(_hidden_pairs_saturday, true)
	_hidden_pairs_saturday.clear()
	dorms_changed.emit()
	saturday_reveals_ready.emit(pairs)

func _collect_hidden_pairs(pool: Dictionary, reveal_true: bool) -> Array:
	var out: Array = []
	for key in pool.keys():
		var k: String = String(key)
		var parts := k.split("|")
		if parts.size() != 2:
			continue
		var a := String(parts[0])
		var b := String(parts[1])
		var status := get_pair_status(a, b, reveal_true)
		out.append({
			"a": a,
			"b": b,
			"a_name": display_name(a),
			"b_name": display_name(b),
			"status": status
		})
	return out

# ─────────────────────────────────────────────────────────────
# Relationships & adjacency
# ─────────────────────────────────────────────────────────────
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

	if a == "hero" and b != "hero":
		return _hero_vs_npc_status(b)
	if b == "hero" and a != "hero":
		return _hero_vs_npc_status(a)

	return "Neutral"

func _hero_vs_npc_status(npc_id: String) -> String:
	var code: String = String(_stat_by_actor.get(npc_id, ""))

	# Explicit always-bestie bucket
	if code == "NULL":
		return "Bestie"

	# Unknown/missing stat → neutral
	if code == "":
		return "Neutral"

	# Fast lookup for picks
	var picked := {}
	for p in _hero_picks:
		picked[String(p)] = true

	# Stat match with a pick → Bestie
	if picked.has(code):
		return "Bestie"

	# Exactly three picks → the two not picked are Rivals
	if _hero_picks.size() == 3 and _ALL_STATS.has(code) and not picked.has(code):
		return "Rival"

	# Otherwise, no strong feeling
	return "Neutral"

func _apply_hero_stat_relationships() -> void:
	for id_any in _name_by_id.keys():
		var aid: String = String(id_any)
		if aid == "hero":
			continue
		_set_pair_status("hero", aid, _hero_vs_npc_status(aid))

func _recompute_adjacency() -> void:
	_pair_status.clear()
	_apply_hero_stat_relationships()

	var seen: Dictionary = {}
	for rid in ROOM_IDS:
		var occ: String = String((_rooms[rid] as Dictionary).get("occupant",""))
		if occ == "":
			continue
		var neigh := room_neighbors(rid)
		for i in range(neigh.size()):
			var n_r: String = neigh[i]
			var occ2: String = String((_rooms[n_r] as Dictionary).get("occupant",""))
			if occ2 == "":
				continue
			var key: String = _pair_key(occ, occ2)
			if seen.has(key):
				continue
			seen[key] = true
			var base_status: String = _get_base_relationship(occ, occ2)
			_set_pair_status(occ, occ2, base_status)

func _mark_new_pairs_hidden(aid: String, before_list: Array[String], after_list: Array[String], source: String) -> void:
	var before: Dictionary = {}
	for v in before_list: before[String(v)] = true
	for nb in after_list:
		var b: String = String(nb)
		if not before.has(b):
			var key := _pair_key(aid, b)
			if source == "reassign":
				_hidden_pairs_friday[key] = true     # Friday reveal (prior-Sat reassignments)
			else:
				_hidden_pairs_saturday[key] = true   # Saturday reveal (midweek Common placements)

func _current_neighbors_of_actor(aid: String) -> Array[String]:
	var out: Array[String] = []
	var room_of: String = ""
	for rid in ROOM_IDS:
		if String((_rooms[rid] as Dictionary).get("occupant","")) == aid:
			room_of = rid
			break
	if room_of == "":
		return out
	var neigh := room_neighbors(room_of)
	for i in range(neigh.size()):
		var nr: String = neigh[i]
		var who: String = String((_rooms[nr] as Dictionary).get("occupant",""))
		if who != "":
			out.append(who)
	return out

# ─────────────────────────────────────────────────────────────
# Public pair/neighbor helpers for UI
# ─────────────────────────────────────────────────────────────
func get_pair_status(a: String, b: String, reveal_hidden: bool = false) -> String:
	var key: String = _pair_key(a, b)
	if not reveal_hidden and (_hidden_pairs_friday.has(key) or _hidden_pairs_saturday.has(key)):
		return "Unknown"
	return String(_pair_status.get(key, _get_base_relationship(a, b)))

func neighbors_summary(room_id: String) -> Array:
	var out: Array = []
	var occ: String = String((_rooms[room_id] as Dictionary).get("occupant",""))
	if occ == "":
		return out
	var neigh := room_neighbors(room_id)
	for i in range(neigh.size()):
		var nr: String = neigh[i]
		var who: String = String((_rooms[nr] as Dictionary).get("occupant",""))
		if who == "":
			continue
		var status: String = get_pair_status(occ, who, false)
		out.append({
			"room": nr,
			"status": status,
			"aid": who,
			"name": display_name(who)
		})
	return out

# ─────────────────────────────────────────────────────────────
# Small utilities & blocking guard
# ─────────────────────────────────────────────────────────────
func occupant_of(room_id: String) -> String:
	return String((_rooms.get(room_id, {}) as Dictionary).get("occupant",""))

func put_occupant(room_id: String, aid: String) -> void:
	if ROOM_IDS.has(room_id):
		_rooms[room_id]["occupant"] = aid

func reveal_all_pairs_now() -> void:
	_hidden_pairs_friday.clear()
	_hidden_pairs_saturday.clear()
	dorms_changed.emit()

func get_last_applied_moves() -> Array:
	return _last_applied_moves.duplicate(true)

func is_blocking_time_advance() -> bool:
	return _is_blocking_time_advance

func _compute_blocking() -> bool:
	# Block while there is any in-progress reassignment (before Accept Plan)
	return (_staged_common.size() > 0 or _staged_assign.size() > 0) and not _plan_locked

func _update_blocking_state() -> void:
	var b := _compute_blocking()
	if b != _is_blocking_time_advance:
		_is_blocking_time_advance = b
		blocking_state_changed.emit(_is_blocking_time_advance)

# ─────────────────────────────────────────────────────────────
# Compat layer for older/newer UI
# ─────────────────────────────────────────────────────────────
func stage_vacate_room(room_id: String) -> Dictionary:
	return begin_reassignment_for_room(room_id)

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

func stage_set_target(aid: String, to_room: String) -> Dictionary:
	return pick_room_for(aid, to_room)

func stage_assign(aid: String, to_room: String) -> Dictionary:
	return pick_room_for(aid, to_room)

func stage_place(aid: String, to_room: String) -> Dictionary:
	return pick_room_for(aid, to_room)

func stage_clear_target(aid: String) -> void:
	_staged_assign.erase(aid)
	_update_blocking_state()
	dorms_changed.emit()
	plan_changed.emit()

func stage_accept_plan() -> Dictionary:
	return accept_plan_for_saturday()

func lock_plan_for_saturday() -> Dictionary:
	return accept_plan_for_saturday()

func stage_reset_plan() -> void:
	reset_placement()

func stage_reset() -> void:
	reset_placement()

func is_plan_locked() -> bool:
	return _plan_locked

func get_locked_involved_rooms() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _locked_involved_rooms.keys():
		out.append(String(k))
	return out

# UI helpers
func can_accept_reassignment() -> Dictionary:
	return {"ok": has_pending_plan()}

func accept_reassignment_selection() -> Dictionary:
	return {"ok": _staged_common.size() > 0}

func can_lock_plan() -> Dictionary:
	if _staged_assign.size() == 0:
		return {"ok": false, "reason": "No reassignment selected."}
	# Require all staged members to have a target
	for i in range(_staged_common.size()):
		var aid: String = _staged_common[i]
		if not _staged_assign.has(aid):
			return {"ok": false, "reason": "Place everyone before accepting."}
	return {"ok": true}

func reset_only_assignments() -> void:
	reset_placement()
