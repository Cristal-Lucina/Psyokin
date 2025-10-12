extends Node
class_name MindTypeSystem

const CSV_PATH   : String = "/root/aCSVLoader"
const TYPES_CSV  : String = "res://data/combat/mind_types.csv"
const KEY_ID     : String = "mind_type_id"

var _defs : Dictionary = {}  # mind_type_id -> row dict

func _ready() -> void:
	_reload()

func _reload() -> void:
	_defs.clear()
	var csv := get_node_or_null(CSV_PATH)
	if csv == null or not FileAccess.file_exists(TYPES_CSV):
		push_warning("[MindTypeSystem] CSV missing at %s" % TYPES_CSV)
		return
	var table_v: Variant = csv.call("load_csv", TYPES_CSV, KEY_ID)
	if typeof(table_v) == TYPE_DICTIONARY:
		_defs = table_v

func get_display_name(id: String) -> String:
	var row: Dictionary = _defs.get(id, {}) as Dictionary
	return String(row.get("name", id))

func list_all_types() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _defs.keys(): out.append(String(k))
	out.sort()
	return out

func allowed_schools(mind_type: String) -> PackedStringArray:
	if mind_type == "Omega":
		# Omega can use everything listed in the CSV
		var all := PackedStringArray()
		for k in _defs.keys():
			var row: Dictionary = _defs[k]
			var s := String(row.get("allowed_schools",""))
			for token in s.split(";"):
				var t := String(token).strip_edges()
				if t != "" and all.find(t) < 0:
					all.append(t)
		return all
	var row2: Dictionary = _defs.get(mind_type, {}) as Dictionary
	var raw := String(row2.get("allowed_schools",""))
	var out := PackedStringArray()
	for token in raw.split(";"):
		var t := String(token).strip_edges()
		if t != "" and out.find(t) < 0:
			out.append(t)
	return out

func is_school_allowed(mind_type: String, school: String) -> bool:
	if mind_type == "Omega":
		return true
	var allowed := allowed_schools(mind_type)
	return allowed.find(school) >= 0
