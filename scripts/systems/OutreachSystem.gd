extends Node
class_name OutreachSystem

## OutreachSystem
## Tracks player-facing tasks in three buckets:
##   - missions (main/side)
##   - nodes (VR quests)
##   - aid (mutual aid / overworld tasks)
##
## Each task record is a Dictionary:
## {
##   "id": String, "title": String, "desc": String,
##   "status": String,  # "new", "active", "blocked", "complete"
##   "hint": String,
## }

signal outreach_changed(category: String)

const CATS := ["missions", "nodes", "aid"]

var _data: Dictionary = {
	"missions": {},  # id -> rec
	"nodes":    {},
	"aid":      {},
}

# --- CRUD ----------------------------------------------------------------------

func upsert(cat: String, id: String, title: String, desc: String, status: String = "new", hint: String = "") -> void:
	"""Create or update a task record, then emit."""
	if not _data.has(cat):
		_data[cat] = {}
	var d: Dictionary = _data[cat]
	d[id] = {"id": id, "title": title, "desc": desc, "status": status, "hint": hint}
	_data[cat] = d
	outreach_changed.emit(cat)

func set_status(cat: String, id: String, status: String) -> void:
	"""Update the status of an existing task and emit."""
	if not _data.has(cat):
		return
	var d: Dictionary = _data[cat]
	if not d.has(id):
		return
	var rec: Dictionary = d[id]
	rec["status"] = status
	d[id] = rec
	_data[cat] = d
	outreach_changed.emit(cat)

func list_ids(cat: String) -> PackedStringArray:
	"""Return sorted ids for a given category."""
	if not _data.has(cat):
		return PackedStringArray()
	var out := PackedStringArray()
	for k in (_data[cat] as Dictionary).keys():
		out.append(String(k))
	out.sort()
	return out

func get_entry(cat: String, id: String) -> Dictionary:
	"""Safe accessor for a single record (renamed from get_entry to avoid Object.get() collision)."""
	if _data.has(cat) and (_data[cat] as Dictionary).has(id):
		return (_data[cat] as Dictionary)[id]
	return {}

func clear_category(cat: String) -> void:
	if _data.has(cat):
		_data[cat] = {}
		outreach_changed.emit(cat)

func clear_all() -> void:
	for c in CATS:
		_data[c] = {}
	outreach_changed.emit("*")

# --- Save blob ----------------------------------------------------------------

func get_save_blob() -> Dictionary:
	"""Deep copy for persistence."""
	return _data.duplicate(true)

func apply_save_blob(blob: Dictionary) -> void:
	"""Restore from a save blob (accepts partial/unknown keys)."""
	for k in blob.keys():
		var key: String = String(k)
		var v: Variant = blob.get(key)
		if typeof(v) == TYPE_DICTIONARY:
			_data[key] = (v as Dictionary).duplicate(true)
	outreach_changed.emit("*")
