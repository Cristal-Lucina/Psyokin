extends Control
class_name StatsPanel

## StatsPanel (MVP)
## Shows core stat levels/SXP/fatigue pulled from /root/aStatsSystem.
## Defensive against API changes; refreshes on level-up and weekly reset.

const STATS_AUTOLOAD_PATH : String = "/root/aStatsSystem"
const CAL_AUTOLOAD_PATH   : String = "/root/aCalendarSystem"

@onready var _list    : VBoxContainer = %List
@onready var _refresh : Button        = %RefreshBtn

var _stats : Node = null
var _cal   : Node = null

func _ready() -> void:
	_stats = get_node_or_null(STATS_AUTOLOAD_PATH)
	_cal   = get_node_or_null(CAL_AUTOLOAD_PATH)

	if _refresh and not _refresh.pressed.is_connected(_rebuild):
		_refresh.pressed.connect(_rebuild)

	# Listen for stat changes (support both legacy and new)
	if _stats:
		if _stats.has_signal("stat_leveled_up"):
			_stats.connect("stat_leveled_up", Callable(self, "_on_stats_changed"))
		if _stats.has_signal("stats_changed"):
			_stats.connect("stats_changed", Callable(self, "_on_stats_changed"))
		if _stats.has_signal("level_up"):
			_stats.connect("level_up", Callable(self, "_on_stats_changed"))

	# Calendar weekly reset could affect fatigue, etc.
	if _cal and _cal.has_signal("week_reset"):
		_cal.connect("week_reset", Callable(self, "_on_stats_changed"))

	_rebuild()

func _on_stats_changed(_a: Variant = null, _b: Variant = null) -> void:
	_rebuild()

func _rebuild() -> void:
	for c in _list.get_children():
		c.queue_free()

	var data: Dictionary = _get_stats_dict()
	if data.is_empty():
		_add_row("No stats found.", "", "")
		return

	# stable sort of keys
	var keys: Array[String] = []
	for k in data.keys():
		keys.append(String(k))
	keys.sort()

	_add_header_row("Stat", "Level", "SXP / Fatigue")

	for key in keys:
		var entry_v: Variant = data.get(key)
		var level: int = 0
		var sxp: int = 0
		var fatigue: int = 0

		if typeof(entry_v) == TYPE_DICTIONARY:
			var entry: Dictionary = entry_v
			level   = int(entry.get("level", entry.get("lvl", 0)))
			sxp     = int(entry.get("sxp", entry.get("xp", 0)))
			fatigue = int(entry.get("fatigue", entry.get("fat", 0)))
		elif typeof(entry_v) == TYPE_INT:
			level = int(entry_v)

		var right: String = "%d / %d" % [sxp, fatigue]
		_add_row(String(key).capitalize(), str(level), right)

	await get_tree().process_frame
	_list.queue_sort()

func _get_stats_dict() -> Dictionary:
	if _stats == null:
		return {}
	if _stats.has_method("get_stats_dict"):
		var d: Variant = _stats.call("get_stats_dict")
		return (d as Dictionary) if typeof(d) == TYPE_DICTIONARY else {}
	if _stats.has_method("to_dict"):
		var d2: Variant = _stats.call("to_dict")
		return (d2 as Dictionary) if typeof(d2) == TYPE_DICTIONARY else {}
	return {}

# --- UI row builders -----------------------------------------------------------

func _add_header_row(col1: String, col2: String, col3: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var l1 := Label.new(); l1.text = col1; l1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l2 := Label.new(); l2.text = col2; l2.custom_minimum_size.x = 80
	var l3 := Label.new(); l3.text = col3; l3.custom_minimum_size.x = 160

	row.add_child(l1); row.add_child(l2); row.add_child(l3)
	_list.add_child(row)

func _add_row(stat_name: String, level: String, right: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var n := Label.new();  n.text = stat_name;  n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lv := Label.new(); lv.text = level;     lv.custom_minimum_size.x = 80
	var rv := Label.new(); rv.text = right;     rv.custom_minimum_size.x = 160

	row.add_child(n); row.add_child(lv); row.add_child(rv)
	_list.add_child(row)
