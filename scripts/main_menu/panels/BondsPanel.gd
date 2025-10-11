extends Control
class_name BondsPanel

## BondsPanel (MVP)
## - Left list of bonds; right detail (name / level / CBXP / notes).
## - Reads from /root/aCircleBondDB (defs) and /root/aCircleBondSystem (levels/xp).
## - Defensive fallbacks so it never crashes if systems are missing.

const DB_PATH  : String = "/root/aCircleBondDB"
const SYS_PATH : String = "/root/aCircleBondSystem"

enum Filter { ALL, KNOWN, LOCKED, MAXED }

@onready var _filter   : OptionButton   = %Filter
@onready var _refresh  : Button         = %RefreshBtn
@onready var _list_box : VBoxContainer  = %List
@onready var _name_tv  : Label          = %Name
@onready var _lvl_tv   : Label          = %LevelValue
@onready var _xp_tv    : Label          = %CBXPValue
@onready var _notes    : RichTextLabel  = %Notes

var _db  : Node = null
var _sys : Node = null

# Typed collection fixes inference warnings.
var _rows     : Array[Dictionary] = []   # [{id:String, name:String}]
var _selected : String = ""              # bond_id

func _ready() -> void:
	"""Wire controls and build."""
	_db  = get_node_or_null(DB_PATH)
	_sys = get_node_or_null(SYS_PATH)

	# Populate filter with explicit ids that match enum values.
	if _filter != null and _filter.item_count == 0:
		_filter.add_item("All",    Filter.ALL)
		_filter.add_item("Known",  Filter.KNOWN)
		_filter.add_item("Locked", Filter.LOCKED)
		_filter.add_item("Maxed",  Filter.MAXED)

	if _filter != null and not _filter.item_selected.is_connected(_on_filter_changed):
		_filter.item_selected.connect(_on_filter_changed)

	if _refresh != null and not _refresh.pressed.is_connected(_rebuild):
		_refresh.pressed.connect(_rebuild)

	_rebuild()

# ------------------------------------------------------------------------------
# Build
# ------------------------------------------------------------------------------

func _rebuild() -> void:
	"""Re-read data, rebuild list & detail."""
	_rows = _read_defs()
	_build_list()
	_update_detail("")

func _build_list() -> void:
	"""Populate left list with the current filter applied."""
	for c in _list_box.get_children():
		c.queue_free()

	var f: int = _get_filter_id()
	for rec: Dictionary in _rows:
		var id: String = String(rec.get("id", ""))
		var disp_name: String = String(rec.get("name", id))  # avoid shadowing Node.name

		var lv: int = _read_level(id)
		var xp: int = _read_cbxp(id)
		var known: bool = (lv > 0 or xp > 0) or _read_known(id)
		var maxed: bool = _is_maxed(id, lv)

		if f == Filter.KNOWN and not known:
			continue
		if f == Filter.LOCKED and known:
			continue
		if f == Filter.MAXED and not maxed:
			continue

		var row := Button.new()
		row.text = disp_name
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.toggle_mode = true
		row.focus_mode = Control.FOCUS_ALL
		row.set_meta("id", id)

		# Grey unknowns; green-ish if maxed.
		if not known:
			row.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			row.tooltip_text = "Unknown"
		elif maxed:
			row.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
			row.tooltip_text = "Maxed"
		else:
			row.tooltip_text = "Level %d • CBXP %d" % [lv, xp]

		if not row.pressed.is_connected(_on_row_pressed):
			row.pressed.connect(_on_row_pressed.bind(row))

		_list_box.add_child(row)

	await get_tree().process_frame
	_list_box.queue_sort()

# ------------------------------------------------------------------------------
# Reads (defensive)
# ------------------------------------------------------------------------------

func _read_defs() -> Array[Dictionary]:
	"""Return Array[{id,name}] from DB; fallback placeholders."""
	var out: Array[Dictionary] = []
	var d: Node = _db
	if d == null:
		for i in range(6):
			out.append({"id": "bond_%d" % i, "name": "Unknown %d" % (i + 1)})
		return out

	# Try common API shapes
	for m in ["get_all", "get_bonds", "get_defs", "get_all_bonds", "get_dict"]:
		if d.has_method(m):
			var v: Variant = d.call(m)
			if typeof(v) == TYPE_DICTIONARY:
				var vd: Dictionary = v as Dictionary
				for k_any in vd.keys():
					var key_str: String = String(k_any)
					var rec_v: Variant = vd.get(key_str)  # <-- explicit Variant fixes inference
					var nm: String = _extract_name(rec_v)
					out.append({"id": key_str, "name": nm})
				return out
			elif typeof(v) == TYPE_ARRAY:
				var va: Array = v as Array
				for item_v in va:
					var id_str: String = String(_extract_id(item_v))
					var nm2: String = _extract_name(item_v)
					if id_str != "":
						out.append({"id": id_str, "name": nm2})
				return out

	# Last resort: ids list
	for m2 in ["get_ids", "list_ids", "get_bond_ids"]:
		if d.has_method(m2):
			var v2: Variant = d.call(m2)
			if typeof(v2) == TYPE_ARRAY:
				for i in (v2 as Array):
					out.append({"id": String(i), "name": String(i)})
				return out

	return out


func _extract_id(v: Variant) -> String:
	"""Pull id from a dict-like record."""
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		if d.has("bond_id"): return String(d["bond_id"])
		if d.has("id"): return String(d["id"])
	return ""

func _extract_name(v: Variant) -> String:
	"""Pull display name; fall back to id/placeholder."""
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		for k in ["display_name", "name", "label", "title"]:
			if d.has(k) and typeof(d[k]) == TYPE_STRING and String(d[k]) != "":
				return String(d[k])
	return "Unknown"

func _read_level(id: String) -> int:
	"""Level from system; fallback 0."""
	var s: Node = _sys
	if s == null: return 0
	for m in ["get_level", "level_for", "get_bond_level"]:
		if s.has_method(m):
			return int(s.call(m, id))
	return 0

func _read_cbxp(id: String) -> int:
	"""CBXP from system; fallback 0."""
	var s: Node = _sys
	if s == null: return 0
	for m in ["get_cbxp", "get_xp", "xp_for", "cbxp_for"]:
		if s.has_method(m):
			return int(s.call(m, id))
	return 0

func _read_known(id: String) -> bool:
	"""Known flag if system/DB exposes it; fallback false."""
	for n in [_sys, _db]:
		if n != null:
			for m in ["is_known", "known", "has_met"]:
				if n.has_method(m):
					return bool(n.call(m, id))
	return false

func _read_max_level() -> int:
	"""Global max level if offered; default 10."""
	var s: Node = _sys
	if s != null:
		for m in ["get_max_level", "max_level"]:
			if s.has_method(m):
				return int(s.call(m))
	return 10

func _is_maxed(_id: String, lv: int) -> bool:
	"""True if at or above max level (id unused for now)."""
	return lv >= _read_max_level()

# ------------------------------------------------------------------------------
# UI events
# ------------------------------------------------------------------------------

func _on_filter_changed(_idx: int) -> void:
	"""Rebuild list when filter changes."""
	_build_list()

func _on_row_pressed(btn: Button) -> void:
	"""Select a bond from list."""
	var id_v: Variant = btn.get_meta("id")
	_selected = String(id_v)
	_update_detail(_selected)

func _update_detail(id: String) -> void:
	"""Fill right-hand summary."""
	if id == "":
		_name_tv.text = "—"
		_lvl_tv.text = "0"
		_xp_tv.text = "0"
		_notes.text = "[i]Select a bond to see details.[/i]"
		return

	var rec_arr: Array = _rows.filter(func(r): return String((r as Dictionary).get("id", "")) == id)
	var nm: String = String(((rec_arr[0] as Dictionary).get("name", ""))) if rec_arr.size() > 0 else id
	var lv: int = _read_level(id)
	var xp: int = _read_cbxp(id)

	_name_tv.text = nm
	_lvl_tv.text = str(lv)
	_xp_tv.text = str(xp)
	_notes.text = "[b]%s[/b]\nLevel %d • CBXP %d\n\n[i](Details and perks TBD.)[/i]" % [nm, lv, xp]

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

func _get_filter_id() -> int:
	"""Return the selected filter id (matches Filter enum)."""
	if _filter == null:
		return Filter.ALL
	return int(_filter.get_selected_id())
