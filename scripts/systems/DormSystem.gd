extends Node
class_name DormsSystem

## DormsSystem
## Tracks dorm rooms (name/capacity/occupants) and move requests.
##
## save blob:
## {
##   "rooms": { room_id: { "name": String, "capacity": int, "occupants": Array[String] } },
##   "moves": [ { "who": String, "from": String, "to": String, "reason": String, "status": String } ]
## }

signal dorms_changed()

# room_id -> { name, capacity, occupants: Array[String] }
var _rooms: Dictionary = {}

# array of move requests
var _moves: Array[Dictionary] = []

func _ready() -> void:
	if _rooms.is_empty():
		_rooms = {
			"a101": {"name":"A-101","capacity":2,"occupants": ["hero"]},
			"a102": {"name":"A-102","capacity":2,"occupants": []},
			"b201": {"name":"B-201","capacity":3,"occupants": []},
		}

# --- queries ------------------------------------------------------------------

func list_rooms() -> PackedStringArray:
	var ids := PackedStringArray()
	for k in _rooms.keys():
		ids.append(String(k))
	ids.sort()
	return ids

func get_room(room_id: String) -> Dictionary:
	if _rooms.has(room_id):
		return _rooms[room_id] as Dictionary
	return {}

func get_moves() -> Array[Dictionary]:
	return _moves

# --- placement ops -------------------------------------------------------------

func assign(room_id: String, who: String) -> bool:
	var r := get_room(room_id)
	if r.is_empty():
		return false

	var occ: Array[String] = []
	var occ_v: Variant = r.get("occupants", [])
	if typeof(occ_v) == TYPE_ARRAY:
		for e in (occ_v as Array):
			occ.append(String(e))

	var cap: int = int(r.get("capacity", 0))
	if occ.has(who):
		return true
	if occ.size() >= cap:
		return false

	occ.append(who)
	r["occupants"] = occ
	_rooms[room_id] = r
	dorms_changed.emit()
	return true

func remove(room_id: String, who: String) -> bool:
	var r := get_room(room_id)
	if r.is_empty():
		return false

	var occ: Array[String] = []
	var occ_v: Variant = r.get("occupants", [])
	if typeof(occ_v) == TYPE_ARRAY:
		for e in (occ_v as Array):
			occ.append(String(e))

	if not occ.has(who):
		return false

	occ.erase(who)
	r["occupants"] = occ
	_rooms[room_id] = r
	dorms_changed.emit()
	return true

func move(who: String, from_id: String, to_id: String) -> bool:
	if from_id == to_id:
		return true
	if not remove(from_id, who):
		return false
	if not assign(to_id, who):
		# rollback if target full
		assign(from_id, who)
		return false
	return true

# --- requests ------------------------------------------------------------------

func request_move(who: String, from_id: String, to_id: String, reason: String) -> void:
	var rec: Dictionary = {
		"who": who, "from": from_id, "to": to_id,
		"reason": reason, "status": "pending"
	}
	_moves.append(rec)
	dorms_changed.emit()

func set_request_status(index: int, status: String) -> void:
	if index < 0 or index >= _moves.size():
		return
	var rec := _moves[index]
	rec["status"] = status
	_moves[index] = rec
	dorms_changed.emit()

# --- save blob -----------------------------------------------------------------

func get_save_blob() -> Dictionary:
	return {
		"rooms": _rooms.duplicate(true),
		"moves": _moves.duplicate(true),
	}

func apply_save_blob(blob: Dictionary) -> void:
	# rooms (simple deep duplicate)
	var r_v: Variant = blob.get("rooms", {})
	if typeof(r_v) == TYPE_DICTIONARY:
		_rooms = (r_v as Dictionary).duplicate(true)

	# moves (must rebuild as Array[Dictionary] to satisfy type)
	var m_v: Variant = blob.get("moves", [])
	if typeof(m_v) == TYPE_ARRAY:
		var new_moves: Array[Dictionary] = []
		for it in (m_v as Array):
			if typeof(it) == TYPE_DICTIONARY:
				new_moves.append((it as Dictionary).duplicate(true))
		_moves = new_moves
	else:
		_moves.clear()

	dorms_changed.emit()

func clear_all() -> void:
	_rooms = {}
	_moves = []
	dorms_changed.emit()
