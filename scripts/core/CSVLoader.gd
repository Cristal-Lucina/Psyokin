extends Node
class_name CSVLoader
# Simple CSV → Dictionary loader with a small in-memory cache.

## Cache: path → { key:String -> row_dict }
var _tables: Dictionary = {}   # path -> { key:String -> row_dict }

# NOTE: Dashes are intentionally NOT considered nullish.
const NULL_STRINGS: PackedStringArray = [
	"null", "none", "nil", "n/a", "na"
]

var _null_tokens: PackedStringArray = NULL_STRINGS.duplicate()

static func _is_empty(s: String) -> bool:
	return s.strip_edges().is_empty()

func _is_nullish_str(s: String) -> bool:
	if _is_empty(s):
		return true
	var t := s.strip_edges().to_lower()
	for mark in _null_tokens:
		if t == mark:
			return true
	return false

## Public: override which tokens are treated as null (optional).
func set_null_tokens(tokens: PackedStringArray) -> void:
	_null_tokens = tokens.duplicate()

## Loads a CSV from `path` and returns a Dictionary keyed by `key_field`.
## Cells equal to one of _null_tokens (or empty) are omitted from the row.
func load_csv(path: String, mind_type: String) -> Dictionary:
	var table: Dictionary = {}

	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("CSVLoader: Could not open %s" % path)
		return {}

	# Header
	if f.eof_reached():
		push_error("CSVLoader: Empty file %s" % path)
		f.close()
		return {}

	var header_any: Array = f.get_csv_line()  # Array[String]
	var header: Array[String] = []
	for h in header_any:
		header.append(String(h).strip_edges())

	var key_index: int = -1
	for i in range(header.size()):
		if header[i] == mind_type:
			key_index = i
			break
	if key_index == -1:
		push_error("CSVLoader: Key field '%s' not found in %s" % [mind_type, path])
		f.close()
		return {}

	# Rows — build a row Dictionary per line, keyed by the chosen field.
	while not f.eof_reached():
		var row_any: Array = f.get_csv_line()
		if row_any == null or row_any.is_empty():
			continue

		# normalize and trim
		var row: Array[String] = []
		for v in row_any:
			row.append(String(v).strip_edges())

		if key_index >= row.size():
			continue

		var key: String = row[key_index]
		if _is_nullish_str(key):
			continue

		var rec: Dictionary = {}
		for j in range(header.size()):
			var col_name: String = header[j]
			var value: String = (row[j] if j < row.size() else "")
			# Skip nullish cells (DO NOT write the key)
			if _is_nullish_str(value):
				continue
			rec[col_name] = value
		table[key] = rec
	f.close()

	_tables[path] = table

	# Helpful logging
	print("CSVLoader: loaded ", table.size(), " rows from ", path)
	if table.size() > 0:
		var any_key: String = String(table.keys()[0])
		print("CSVLoader: first key=", any_key, " row=", table[any_key])

	return table

## Retrieves a previously loaded table from the in-memory cache.
func get_table(path: String) -> Dictionary:
	return _tables.get(path, {})

## Forces a reload of a CSV (bypasses the cache).
func reload_csv(path: String, key_field: String) -> Dictionary:
	_tables.erase(path)
	return load_csv(path, key_field)
