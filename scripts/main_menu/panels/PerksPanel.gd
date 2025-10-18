extends Control
class_name PerksPanel

## PerksPanel (gated)
## - Buttons are disabled unless: stat meets tier threshold AND you have ≥1 perk point.
## - On click: spend point first; attempt unlock; if unlock fails, refund 1.

const STATS_PATH   : String = "/root/aStatsSystem"
const PERKSYS_PATH : String = "/root/aPerkSystem"  # optional; UI works without it

const MAX_ROWS : int = 5
const MAX_COLS : int = 5

## Default tier thresholds per row (stat-level gates). Override via systems if available.
const DEFAULT_THRESHOLDS : PackedInt32Array = [1, 3, 5, 7, 10]

@onready var _grid      : GridContainer = %Grid
@onready var _refresh   : Button        = %RefreshBtn
@onready var _points_tv : Label         = %PointsValue

var _stats : Node = null
var _perk  : Node = null

## Cached derived data for the current rebuild
var _stat_keys  : PackedStringArray = []     # 5 stat ids/names in display order
var _levels_map : Dictionary = {}            # {stat -> level:int}
var _cells      : Dictionary = {}            # {stat -> Array[Button]}
var _points     : int = 0                    # available perk points (from system if possible)

func _ready() -> void:
	_stats = get_node_or_null(STATS_PATH)
	_perk  = get_node_or_null(PERKSYS_PATH)

	if _refresh != null and not _refresh.pressed.is_connected(_rebuild_all):
		_refresh.pressed.connect(_rebuild_all)

	# If systems fire useful signals, listen and refresh
	if _stats != null:
		if _stats.has_signal("stats_changed"):
			_stats.connect("stats_changed", Callable(self, "_rebuild_all"))
		if _stats.has_signal("perk_points_changed"):
			_stats.connect("perk_points_changed", Callable(self, "_rebuild_all"))

	if _perk != null:
		if _perk.has_signal("perk_unlocked"):
			_perk.connect("perk_unlocked", Callable(self, "_rebuild_all"))
		if _perk.has_signal("perks_changed"):
			_perk.connect("perks_changed", Callable(self, "_rebuild_all"))

	_rebuild_all()

# ------------------------------------------------------------------------------

func _rebuild_all() -> void:
	_levels_map = _read_levels()
	_stat_keys  = _choose_rows(_levels_map.keys())
	_points     = _read_perk_points()
	_update_points_label()

	# clear grid
	for c in _grid.get_children():
		c.queue_free()
	_cells.clear()

	# header row: blank + T1..T5
	var blank: Label = Label.new()
	_grid.add_child(blank)
	for i in range(MAX_COLS):
		var h: Label = Label.new()
		h.text = "T%d" % (i + 1)
		h.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		_grid.add_child(h)

	# 5 rows (stats)
	for s in _stat_keys:
		var stat_id: String = String(s)

		# left label: stat name
		var name_lbl: Label = Label.new()
		name_lbl.text = _pretty_stat(stat_id)
		name_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
		name_lbl.custom_minimum_size.x = 140
		_grid.add_child(name_lbl)

		# 5 perk cells
		var row_buttons: Array = []
		for tier_i in range(MAX_COLS):
			var b: Button = Button.new()
			b.toggle_mode = true
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size.y = 32

			var threshold: int = _tier_threshold(stat_id, tier_i)
			var level: int = int(_levels_map.get(stat_id, 0))
			var is_unlocked: bool = _is_unlocked(stat_id, tier_i)
			var meets_stat: bool = level >= threshold
			var can_buy: bool = (not is_unlocked) and meets_stat and (_points > 0)

			# --- Names/descs from PerkSystem when available ---
			var display: String = "Perk T%d" % (tier_i + 1)
			var tip: String     = "Requires %s ≥ %d" % [_pretty_stat(stat_id), threshold]
			if _perk != null:
				if _perk.has_method("get_perk_name"):
					display = String(_perk.call("get_perk_name", stat_id, tier_i))
				if _perk.has_method("get_perk_desc"):
					var dsc := String(_perk.call("get_perk_desc", stat_id, tier_i))
					if dsc != "":
						tip = "%s\n%s" % [tip, dsc]
				if _perk.has_method("get_perk_id"):
					b.set_meta("perk_id", String(_perk.call("get_perk_id", stat_id, tier_i)))

			# visuals
			b.text = ("✔ " if is_unlocked else "") + display
			if not meets_stat:
				b.disabled = true
				b.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
				b.tooltip_text = "%s (yours: %d)" % [tip, level]
			elif is_unlocked:
				b.button_pressed = true
				b.disabled = true
				b.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
				b.tooltip_text = "Unlocked\n%s" % tip
			else:
				b.disabled = false
				b.tooltip_text = "Cost: 1 Perk Point • %s" % tip

			# metadata + connect
			b.set_meta("stat_id", stat_id)
			b.set_meta("tier", tier_i)

			# Only connect if the user can actually buy right now
			if can_buy and not b.pressed.is_connected(_on_cell_pressed):
				b.pressed.connect(_on_cell_pressed.bind(b))

			row_buttons.append(b)
			_grid.add_child(b)

		_cells[stat_id] = row_buttons

	await get_tree().process_frame
	_grid.queue_sort()

# ------------------------------------------------------------------------------

func _read_levels() -> Dictionary:
	var out: Dictionary = {}
	var st: Node = _stats
	if st == null:
		return out

	# Preferred: a dict map
	if st.has_method("get_stats_dict"):
		var res: Variant = st.call("get_stats_dict")
		if typeof(res) == TYPE_DICTIONARY:
			var d: Dictionary = res
			for k in d.keys():
				var rec_v: Variant = d[k]
				if typeof(rec_v) == TYPE_DICTIONARY:
					var rec: Dictionary = rec_v
					out[String(k)] = int(rec.get("level", int(rec.get("lvl", 0))))
				else:
					out[String(k)] = int(rec_v)
			return out

	# Alt: parallel arrays (names + levels)
	if st.has_method("get_stat_names") and st.has_method("get_stat_levels"):
		var names_v: Variant = st.call("get_stat_names")
		var levels_v: Variant = st.call("get_stat_levels")
		if typeof(names_v) == TYPE_ARRAY and typeof(levels_v) == TYPE_ARRAY:
			var names: Array = names_v
			var levels: Array = levels_v
			for i in range(min(names.size(), levels.size())):
				out[String(names[i])] = int(levels[i])
			return out

	# Last resort
	if out.is_empty():
		var lvl: int = 0
		if st.has_method("get"):
			var v: Variant = st.get("level")
			if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
				lvl = int(v)
		out["Stat"] = lvl
	return out

func _read_perk_points() -> int:
	var st: Node = _stats
	if st != null:
		if st.has_method("get_perk_points"):
			return int(st.call("get_perk_points"))
		if st.has_method("get"):
			var v: Variant = st.get("perk_points")
			if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
				return int(v)
	return 0

func _choose_rows(keys: Array) -> PackedStringArray:
	var order: PackedStringArray = []
	var st: Node = _stats
	if st != null and st.has_method("get_stats_order"):
		var v: Variant = st.call("get_stats_order")
		if typeof(v) == TYPE_ARRAY:
			for x in (v as Array):
				order.append(String(x))
	for k in keys:
		var ks: String = String(k)
		if not order.has(ks):
			order.append(ks)
	while order.size() > MAX_ROWS:
		order.remove_at(order.size() - 1)
	return order

func _tier_threshold(_stat_id: String, tier_index: int) -> int:
	if _perk != null:
		if _perk.has_method("get_threshold"):
			return int(_perk.call("get_threshold", _stat_id, tier_index))
		if _perk.has_method("get_thresholds"):
			var v: Variant = _perk.call("get_thresholds", _stat_id)
			if typeof(v) == TYPE_ARRAY:
				var arr: Array = v
				if tier_index >= 0 and tier_index < arr.size():
					return int(arr[tier_index])
	return DEFAULT_THRESHOLDS[min(tier_index, DEFAULT_THRESHOLDS.size() - 1)]

func _is_unlocked(stat_id: String, tier_index: int) -> bool:
	if _perk != null:
		if _perk.has_method("is_unlocked"):
			return bool(_perk.call("is_unlocked", stat_id, tier_index))
		if _perk.has_method("has_perk"):
			return bool(_perk.call("has_perk", "%s:%d" % [stat_id, tier_index]))
	return false

# ------------------------------------------------------------------------------

func _on_cell_pressed(btn: Button) -> void:
	# Gate: stat threshold and points are rechecked here (defense)
	var stat_id: String = String(btn.get_meta("stat_id"))
	var tier_i : int    = int(btn.get_meta("tier"))

	var threshold: int = _tier_threshold(stat_id, tier_i)
	var level: int = int(_levels_map.get(stat_id, 0))
	if level < threshold:
		return

	# Spend 1 point FIRST; if you don’t have it, bail.
	var spent: int = 0
	if _stats != null and _stats.has_method("spend_perk_point"):
		spent = int(_stats.call("spend_perk_point", 1))
	if spent < 1:
		return

	# Try to unlock the perk.
	var unlocked: bool = false
	if _perk != null:
		if _perk.has_method("unlock_by_id") and btn.has_meta("perk_id"):
			unlocked = bool(_perk.call("unlock_by_id", String(btn.get_meta("perk_id"))))
		elif _perk.has_method("unlock_perk"):
			unlocked = bool(_perk.call("unlock_perk", stat_id, tier_i))
		elif _perk.has_method("unlock"):
			unlocked = bool(_perk.call("unlock", stat_id, tier_i))
	else:
		# No PerkSystem? treat as UI-only “success”
		unlocked = true

	# If unlock FAILED, refund the point.
	if not unlocked:
		if _stats != null and _stats.has_method("add_perk_points"):
			_stats.call("add_perk_points", 1)

	_rebuild_all()

# ------------------------------------------------------------------------------

func _update_points_label() -> void:
	if _points_tv != null:
		_points_tv.text = str(_points)

func _pretty_stat(id_str: String) -> String:
	if _stats != null:
		if _stats.has_method("get_stat_display_name"):
			var v: Variant = _stats.call("get_stat_display_name", id_str)
			if typeof(v) == TYPE_STRING and String(v) != "":
				return String(v)
	var s: String = id_str.replace("_", " ").strip_edges()
	if s.length() == 0:
		return "Stat"
	return s.substr(0,1).to_upper() + s.substr(1, s.length() - 1)
