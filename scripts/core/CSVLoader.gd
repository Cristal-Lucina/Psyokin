extends Node
class_name CSVLoader

# Simple, cached CSV loader: returns Dictionary keyed by the chosen column.

var _cache: Dictionary = {}   # path -> { key -> row_dict }
var _mru_key: Dictionary = {} # path -> key column used

## Clears the entire cache, forcing fresh reads on next load_csv calls
func clear_cache() -> void:
	_cache.clear()
	_mru_key.clear()
	print("[CSVLoader] Cache cleared")

## Clears cache for a specific path
func clear_cache_for_path(path: String) -> void:
	if _cache.has(path):
		_cache.erase(path)
		_mru_key.erase(path)
		print("[CSVLoader] Cache cleared for path: %s" % path)

func load_csv(path: String, key_column: String = "id") -> Dictionary:
	# Return cached if available and matching key.
	if _cache.has(path) and _mru_key.get(path, "") == key_column:
		return _cache[path] as Dictionary

	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}

	if f.eof_reached():
		f.close()
		return {}

	var header: PackedStringArray = f.get_csv_line()
	if header.is_empty():
		f.close()
		return {}

	# Build header index
	var idx: Dictionary = {}
	for i in range(header.size()):
		idx[String(header[i]).strip_edges()] = i

	if not idx.has(key_column):
		# Fallback: try lowercase or a few common ids
		var alt: String = key_column.strip_edges().to_lower()
		for k in idx.keys():
			if String(k).strip_edges().to_lower() == alt:
				key_column = String(k)
				break
		if not idx.has(key_column):
			# last ditch: if we see one of these in the header, pick it
			for probe in ["id","actor_id","code","key","name"]:
				if idx.has(probe):
					key_column = probe
					break
		if not idx.has(key_column):
			f.close()
			return {}

	var out: Dictionary = {}
	while not f.eof_reached():
		var row: PackedStringArray = f.get_csv_line()
		if row.is_empty():
			continue
		var r: Dictionary = {}
		for k in idx.keys():
			var col_i: int = int(idx[k])
			var raw: String = (String(row[col_i]) if (col_i >= 0 and col_i < row.size()) else "")
			r[String(k)] = _auto(raw)
		var key_val: String = String(r.get(key_column, "")).strip_edges()
		if key_val == "":
			continue
		out[key_val] = r
	f.close()

	_cache[path] = out
	_mru_key[path] = key_column
	return out

func _auto(s: String) -> Variant:
	var t := s.strip_edges()
	if t == "":
		return ""
	# Int?
	var i_val: int = t.to_int()
	if str(i_val) == t:
		return i_val
	# Float?
	var f_val: float = t.to_float()
	if str(f_val) == t or t.find(".") >= 0:
		# Godot prints floats without forcing decimals, that's fine.
		# We just ensure it's a number if it parsed.
		if not is_nan(f_val):
			return f_val
	return t
