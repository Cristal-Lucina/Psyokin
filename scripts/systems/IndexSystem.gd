extends Node
class_name IndexSystem

## Tracks discovered Index entries by category.
## Categories: tutorials, enemies, missions, locations, lore.
## Save-friendly via get_save_blob / apply_save_blob.

signal index_changed(category: String)

# Keep it simple: literal array so it's a true constant expression.
const CATS := ["tutorials", "enemies", "missions", "locations", "lore"]

# data model:
# {
#   "tutorials": { "<id>": {"title":"...", "body":"..."} , ... },
#   "enemies":   { "<id>": {...}, ... },
#   ...
# }
var _data: Dictionary = {
	"tutorials": {},
	"enemies": {},
	"missions": {},
	"locations": {},
	"lore": {},
}

# --- API ----------------------------------------------------------------------

func list_ids(cat: String) -> PackedStringArray:
	if not _data.has(cat):
		return PackedStringArray()
	var d: Dictionary = _data[cat]
	var out := PackedStringArray()
	for k in d.keys():
		out.append(String(k))
	return out

func has_entry(cat: String, id: String) -> bool:
	return _data.has(cat) and (_data[cat] as Dictionary).has(id)

func get_entry(cat: String, id: String) -> Dictionary:
	if has_entry(cat, id):
		return (_data[cat] as Dictionary)[id]
	return {}

func upsert_entry(cat: String, id: String, title: String, body: String) -> void:
	if not _data.has(cat):
		_data[cat] = {}
	var d: Dictionary = _data[cat]
	d[id] = { "title": title, "body": body }
	_data[cat] = d
	index_changed.emit(cat)

func clear_category(cat: String) -> void:
	if _data.has(cat):
		_data[cat] = {}
		index_changed.emit(cat)

func clear_all() -> void:
	for c in CATS:
		_data[c] = {}
	index_changed.emit("*")

# --- Save blob ----------------------------------------------------------------

func get_save_blob() -> Dictionary:
	return _data.duplicate(true)

func apply_save_blob(blob: Dictionary) -> void:
	# Accept partial blobs; keep unknown keys too (forward-compat).
	for k in blob.keys():
		var key: String = String(k)
		var v: Variant = blob.get(key)
		if typeof(v) == TYPE_DICTIONARY:
			_data[key] = (v as Dictionary).duplicate(true)
	index_changed.emit("*")
