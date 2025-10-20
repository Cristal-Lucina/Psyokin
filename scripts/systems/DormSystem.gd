extends Node
class_name DormsSystem

signal dorms_changed
signal plan_changed
signal saturday_applied(new_layout: Dictionary) # room_id -> actor_id (or "")

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

var _name_by_id: Dictionary = {}     # actor_id -> display name
var _id_norm_map: Dictionary = {}    # normalized token (id/display) -> actor_id

var _rooms: Dictionary = {}          # room_id -> {"name":rid, "occupant": String}
var _common: Array[String] = []      # unassigned

# weekly staging
var _staged_common: Array[String] = []
var _staged_prev_room: Dictionary = {}  # aid -> from_room
var _staged_assign: Dictionary = {}     # aid -> to_room
var _plan_locked: bool = false
var _locked_involved_rooms: Dictionary = {} # room_id -> true

# relationships
var _bestie_map: Dictionary = {} # aid -> Array[String] (actor_ids)
var _rival_map : Dictionary = {} # aid -> Array[String]

# adjacency cache
var _pair_status: Dictionary = {} # "a|b" -> "Bestie"/"Rival"/"Neutral"

enum RoomVisual { EMPTY_GREEN, OCCUPIED_BLUE, STAGED_YELLOW, LOCKED_RED }

# calendar discovery
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

# relationship header aliases (normalized)
const _ID_KEYS := ["actor_id","id","actor","member_id"]
const _NAME_KEYS := ["name","display_name","disp_name"]
const _BESTIE_KEYS := ["bestie_buff","besties","bestie","bestie_ids"]
const _RIVAL_KEYS  := ["rival_debuff","rivals","rival","rival_ids"]

# candidate CSV paths
const _PARTY_CANDIDATES := [
	"res://data/party/party.csv",
	"res://data/Party.csv",
	"res://data/party.csv",
	"res://data/characters/party.csv",
	"res://data/actors/party.csv",
	"res://data/actors.csv"
]

func _ready() -> void:
	_bootstrap_rooms()
	_load_party_names_and_relationships()
	_bind_calendar()
	if get_tree():
		get_tree().connect("node_added", Callable(self, "_on_tree_node_added"))
	_recompute_adjacency()
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
	var looks_like_cal := false
	for sig in _CAL_SIGNALS:
		if n.has_signal(sig):
			looks_like_cal = true; break
	if not looks_like_cal:
		for m in ["get_weekday_name","get_weekday","day_of_week","weekday","dow"]:
			if n.has_method(m):
				looks_like_cal = true; break
	if looks_like_cal:
		set_calendar(n)

func _bind_calendar() -> void:
	for path in _CAL_PATHS:
		if _calendar_node == null:
			_calendar_node = get_node_or_null(path)
	if _calendar_node == null and get_tree():
		for child in get_tree().root.get_children():
			for m in ["get_weekday_name","get_weekday","day_of_week","weekday","dow"]:
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

# manual nudge if needed
func calendar_notify_weekday(weekday_name: String) -> void:
	if _is_saturday_name(weekday_name):
		_try_execute_saturday()

func _on_calendar_day_changed(_sig: String, a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
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

	if _is_saturday_name(wd_name) or _is_saturday_index(idx):
		_try_execute_saturday()

func _is_saturday_name(s: String) -> bool:
	if s == null:
		return false
	var t := String(s).strip_edges().to_lower()
	# 0=Mon..6=Sun → Sat=5 (we also accept the char "5")
	return t.begins_with("sat") or t == "5"

func _is_saturday_index(i: int) -> bool:
	return i == 5 # 0=Mon..6=Sun → Sat=5

func _try_execute_saturday() -> void:
	if _plan_locked:
		saturday_execute_changes()

# ─────────────────────────────────────────────────────────────
# Bootstrap + CSV (names & relationships)
# ─────────────────────────────────────────────────────────────
func _bootstrap_rooms() -> void:
	_rooms.clear()
	for rid in ROOM_IDS:
		_rooms[rid] = {"name": rid, "occupant": ""}
	_rooms["301"]["occupant"] = "hero" # RA room

func _norm_header(s: String) -> String:
	var t := String(s).to_lower().strip_edges()
	t = t.replace(",", "")
	t = t.replace("\t", "")
	return t

func _norm_id_token(s: String) -> String:
	var t := String(s).to_lower().strip_edges()
	t = t.replace("-", "_")
	t = t.replace(" ", "_")
	while t.find("__") != -1:
		t = t.replace("__","_")
	return t

func _ensure_hero_in_maps() -> void:
	if not _name_by_id.has("hero"):
		_name_by_id["hero"] = "Hero"
	_id_norm_map[_norm_id_token("hero")] = "hero"
	_id_norm_map[_norm_id_token("Hero")] = "hero"

func _best_fit_party_csv() -> String:
	for p in _PARTY_CANDIDATES:
		if FileAccess.file_exists(p):
			return p
	return ""

func _parse_rel_list_val_to_ids(v: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(v) == TYPE_STRING:
		var s := String(v).replace(";", ",").replace("|", ",")
		for part in s.split(",", false):
			var raw := String(part).strip_edges()
			if raw == "":
				continue
			var norm := _norm_id_token(raw)
			if _id_norm_map.has(norm):
				out.append(String(_id_norm_map[norm]))
			else:
				# assume author typed actor_id already
				out.append(raw)
	return out

func _load_party_names_and_relationships() -> void:
	_name_by_id.clear()
	_id_norm_map.clear()
	_bestie_map.clear()
	_rival_map.clear()

	var path := _best_fit_party_csv()
	if path == "":
		_ensure_hero_in_maps()
		return

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_ensure_hero_in_maps()
		return

	var header: PackedStringArray = PackedStringArray()
	if not f.eof_reached():
		header = f.get_csv_line()

	var idx_id := -1
	var idx_nm := -1
	var idx_bestie := -1
	var idx_rival  := -1

	for i in range(header.size()):
		var key := _norm_header(header[i])
		if idx_id == -1 and key in _ID_KEYS: idx_id = i
		if idx_nm == -1 and key in _NAME_KEYS: idx_nm = i
		if idx_bestie == -1 and key in _BESTIE_KEYS: idx_bestie = i
		if idx_rival  == -1 and key in _RIVAL_KEYS:  idx_rival  = i

	# read rows
	while not f.eof_reached():
		var cols: PackedStringArray = f.get_csv_line()
		if cols.size() == 0:
			continue

		var aid := (cols[idx_id] if idx_id >= 0 and idx_id < cols.size() else "").strip_edges()
		if aid == "":
			continue

		var nm  := (cols[idx_nm] if idx_nm >= 0 and idx_nm < cols.size() else "").strip_edges()
		_name_by_id[aid] = (nm if nm != "" else aid.capitalize())

		# build normalization map for both id and display name
		_id_norm_map[_norm_id_token(aid)] = aid
		if nm != "":
			_id_norm_map[_norm_id_token(nm)] = aid

		# relationships
		var bestie_val := (cols[idx_bestie] if idx_bestie >= 0 and idx_bestie < cols.size() else "")
		var rival_val  := (cols[idx_rival]  if idx_rival  >= 0 and idx_rival  < cols.size() else "")
		_bestie_map[aid] = _parse_rel_list_val_to_ids(bestie_val)
		_rival_map[aid]  = _parse_rel_list_val_to_ids(rival_val)

	f.close()

	_ensure_hero_in_maps()

func display_name(aid: String) -> String:
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
		for n in (arr_v as Array):
			out.append(String(n))
	return out

func room_in_locked_plan(room_id: String) -> bool:
	return _plan_locked and _locked_involved_rooms.has(room_id)

func get_locked_warning_for(room_id: String) -> String:
	return "(Room Reassignments happening on Saturday)" if room_in_locked_plan(room_id) else ""

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

func is_staged(aid: String) -> bool:
	return _staged_common.has(aid)

func staged_size() -> int:
	return _staged_common.size()

func staged_assign_size() -> int:
	return _staged_assign.size()

# ─────────────────────────────────────────────────────────────
# Cheats & immediate placement
# ─────────────────────────────────────────────────────────────
func cheat_add_to_common(actor_id: String) -> void:
	if _is_in_any_room(actor_id):
		return
	if _common.has(actor_id):
		return
	if actor_id == "hero":
		return
	_common.append(actor_id)
	dorms_changed.emit()

func assign_now_from_common(actor_id: String, to_room: String) -> Dictionary:
	if not _common.has(actor_id):
		return {"ok": false, "reason": "Character is not in Common Room."}
	if not ROOM_IDS.has(to_room):
		return {"ok": false, "reason": "Unknown room."}
	if to_room == "301" and actor_id != "hero":
		return {"ok": false, "reason": "RA room (301) is reserved."}
	# don’t allow assigning into a room already reserved by the current plan
	for k_any in _staged_assign.keys():
		if String(_staged_assign[k_any]) == to_room:
			return {"ok": false, "reason":"Room is reserved for reassignment."}
	var occ: String = String((_rooms[to_room] as Dictionary).get("occupant",""))
	if occ != "":
		return {"ok": false, "reason": "Room not empty."}
	_rooms[to_room]["occupant"] = actor_id
	_common.erase(actor_id)
	_recompute_adjacency()
	dorms_changed.emit()
	return {"ok": true}

func _is_in_any_room(actor_id: String) -> bool:
	for rid in ROOM_IDS:
		if String((_rooms[rid] as Dictionary).get("occupant","")) == actor_id:
			return true
	return false

# ─────────────────────────────────────────────────────────────
# Reassignment (weekly)
# ─────────────────────────────────────────────────────────────
func clear_staged_all() -> void:
	_staged_common.clear()
	_staged_prev_room.clear()
	_staged_assign.clear()
	_plan_locked = false
	_locked_involved_rooms.clear()
	plan_changed.emit()

func stage_vacate_room(room_id: String) -> Dictionary:
	var who: String = String((_rooms[room_id] as Dictionary).get("occupant",""))
	if who == "":
		return {"ok": false, "reason":"Room is empty."}
	if room_id == "301":
		return {"ok": false, "reason":"Cannot vacate the RA room."}
	if _staged_common.has(who):
		return {"ok": true}
	_staged_common.append(who)
	_staged_prev_room[who] = room_id
	plan_changed.emit()
	return {"ok": true}

func unstage_vacate_room(room_id: String) -> void:
	var who: String = String((_rooms[room_id] as Dictionary).get("occupant",""))
	if who == "":
		return
	_staged_common.erase(who)
	_staged_prev_room.erase(who)
	_staged_assign.erase(who)
	plan_changed.emit()

func can_accept_reassignment() -> Dictionary:
	var needed: int = _staged_common.size()
	if needed == 0:
		return {"ok": false, "reason":"No one selected to move."}
	var free_rooms: int = 0
	for rid in ROOM_IDS:
		if rid == "301":
			continue
		var occ: String = String((_rooms[rid] as Dictionary).get("occupant",""))
		# free if empty OR occupant is also staged to move out
		if occ == "" or _staged_common.has(occ):
			free_rooms += 1
	if free_rooms < needed:
		return {"ok": false, "reason":"Not enough available rooms for reassignment."}
	return {"ok": true}

func accept_reassignment_selection() -> Dictionary:
	var chk: Dictionary = can_accept_reassignment()
	if not bool(chk.get("ok", false)):
		return chk
	plan_changed.emit()
	return {"ok": true}

func stage_place(aid: String, to_room: String) -> Dictionary:
	if not _staged_common.has(aid):
		return {"ok": false, "reason":"Select from Common Room (staged) first."}
	if not ROOM_IDS.has(to_room):
		return {"ok": false, "reason":"Unknown room."}
	var prev: String = String(_staged_prev_room.get(aid,""))
	if prev != "" and prev == to_room:
		return {"ok": false, "reason":"Cannot return to the same room."}
	if to_room == "301" and aid != "hero":
		return {"ok": false, "reason":"RA room (301) is reserved."}
	# prevent two people targeting the same room
	for other_k in _staged_assign.keys():
		if String(_staged_assign[other_k]) == to_room and String(other_k) != aid:
			return {"ok": false, "reason":"That room is already targeted by another member."}
	var occ: String = String((_rooms[to_room] as Dictionary).get("occupant",""))
	var allowed: bool = (occ == "") or _staged_common.has(occ)
	if not allowed:
		return {"ok": false, "reason":"Target room will not be free."}
	_staged_assign[aid] = to_room
	plan_changed.emit()
	return {"ok": true}

func reset_only_assignments() -> void:
	_staged_assign.clear()
	plan_changed.emit()

func can_lock_plan() -> Dictionary:
	if _staged_common.size() == 0:
		return {"ok": false, "reason":"No one staged for reassignment."}
	for aid in _staged_common:
		if not _staged_assign.has(aid):
			return {"ok": false, "reason":"Place everyone before accepting."}
	var seen: Dictionary = {}
	for k in _staged_assign.keys():
		var tgt: String = String(_staged_assign[k])
		if seen.has(tgt):
			return {"ok": false, "reason":"Two people target the same room."}
		seen[tgt] = true
	for aid2 in _staged_assign.keys():
		if String(_staged_assign[aid2]) == "301" and String(aid2) != "hero":
			return {"ok": false, "reason":"RA room (301) is reserved."}
	return {"ok": true}

func lock_plan_for_saturday() -> Dictionary:
	var chk: Dictionary = can_lock_plan()
	if not bool(chk.get("ok", false)):
		return chk
	_plan_locked = true
	_locked_involved_rooms.clear()
	for k in _staged_assign.keys():
		_locked_involved_rooms[String(_staged_assign[k])] = true
	for k2 in _staged_prev_room.keys():
		_locked_involved_rooms[String(_staged_prev_room[k2])] = true
	plan_changed.emit()
	return {"ok": true}

# Two-phase Saturday apply (prevents losing anyone)
func saturday_execute_changes() -> void:
	if not _plan_locked:
		return

	# Phase 1: clear all source rooms
	var to_clear: Dictionary = {}
	for aid_k in _staged_assign.keys():
		var aid: String = String(aid_k)
		var from_r: String = String(_staged_prev_room.get(aid, ""))
		if from_r != "":
			to_clear[from_r] = true
	for rid_any in to_clear.keys():
		var rid: String = String(rid_any)
		_rooms[rid]["occupant"] = ""

	# Phase 2: place everyone into their targets
	for aid_k2 in _staged_assign.keys():
		var aid2: String = String(aid_k2)
		var to_r: String   = String(_staged_assign.get(aid2,""))
		if to_r != "":
			_rooms[to_r]["occupant"] = aid2

	# clean up
	_staged_common.clear()
	_staged_prev_room.clear()
	_staged_assign.clear()
	_plan_locked = false
	_locked_involved_rooms.clear()

	_recompute_adjacency()
	_award_weekly_dorm_axp()

	dorms_changed.emit()
	saturday_applied.emit(_snapshot_layout())

func _snapshot_layout() -> Dictionary:
	var d := {}
	for rid in ROOM_IDS:
		d[rid] = String((_rooms[rid] as Dictionary).get("occupant",""))
	return d

# ─────────────────────────────────────────────────────────────
# Relationships (Bestie/Rival/Neutral)
# ─────────────────────────────────────────────────────────────
func register_bestie_rival_map(bestie_map: Dictionary, rival_map: Dictionary) -> void:
	_bestie_map = bestie_map.duplicate(true)
	_rival_map  = rival_map.duplicate(true)
	_recompute_adjacency()

func _ids_from_map_value(v: Variant) -> Array[String]:
	var out: Array[String] = []
	match typeof(v):
		TYPE_PACKED_STRING_ARRAY:
			for s in (v as PackedStringArray): out.append(String(s))
		TYPE_ARRAY:
			for s2 in (v as Array): out.append(String(s2))
		TYPE_STRING:
			var s3 := String(v).replace(";", ",").replace("|", ",")
			for part in s3.split(",", false):
				var t := String(part).strip_edges()
				if t != "": out.append(t)
		_:
			pass
	return out

func _same_actor(a: String, b: String) -> bool:
	return _norm_id_token(a) == _norm_id_token(b)

func _recompute_adjacency() -> void:
	_pair_status.clear()
	for rid in ROOM_IDS:
		var a: String = String((_rooms[rid] as Dictionary).get("occupant","")).strip_edges()
		if a == "":
			continue
		var neigh_v: Variant = NEIGHBORS.get(rid, [])
		if typeof(neigh_v) != TYPE_ARRAY:
			continue
		for nid_v in (neigh_v as Array):
			var nid: String = String(nid_v)
			var b: String = String((_rooms[nid] as Dictionary).get("occupant","")).strip_edges()
			if b == "" or a == b:
				continue
			var k: String = _pair_key(a, b)
			if _pair_status.has(k):
				continue
			var st: String = _status_from_hints(a, b)
			_pair_status[k] = st

func _status_from_hints(a: String, b: String) -> String:
	# Check Bestie (either side lists the other)
	var ab: Array[String] = _ids_from_map_value(_bestie_map.get(a, []))
	for t in ab:
		if _same_actor(t, b): return "Bestie"
	var bb: Array[String] = _ids_from_map_value(_bestie_map.get(b, []))
	for t2 in bb:
		if _same_actor(t2, a): return "Bestie"

	# Check Rival
	var ar: Array[String] = _ids_from_map_value(_rival_map.get(a, []))
	for r1 in ar:
		if _same_actor(r1, b): return "Rival"
	var br: Array[String] = _ids_from_map_value(_rival_map.get(b, []))
	for r2 in br:
		if _same_actor(r2, a): return "Rival"

	return "Neutral"

func _pair_key(a: String, b: String) -> String:
	return (a + "|" + b) if a < b else (b + "|" + a)

func set_pair_status(a: String, b: String, status: String) -> void:
	var k: String = _pair_key(a,b)
	_pair_status[k] = status

func get_pair_status(a: String, b: String) -> String:
	var k: String = _pair_key(a,b)
	return String(_pair_status.get(k, "Neutral"))

func _award_weekly_dorm_axp() -> void:
	var aff: Node = get_node_or_null("/root/aAffinitySystem")
	if aff == null:
		return
	for k_any in _pair_status.keys():
		var k: String = String(k_any)
		var status: String = String(_pair_status[k])
		var parts: PackedStringArray = k.split("|", false)
		if parts.size() != 2:
			continue
		var a: String = parts[0]
		var b: String = parts[1]
		var amt: int = 0
		if status == "Bestie":
			amt = 5
		elif status == "Rival":
			amt = -4
		if amt != 0 and aff.has_method("add_dorm_bonus"):
			aff.call("add_dorm_bonus", a, b, amt)
