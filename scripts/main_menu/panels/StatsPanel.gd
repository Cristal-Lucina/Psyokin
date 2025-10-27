extends Control
class_name StatsPanel

## StatsPanel (party-aware)
## - Monday fatigue reset is handled by StatsSystem; we just refresh when stats change.
## - Shows hero SXP/Fatigue; hides those for non-hero.
## - Adds a simple member selector row (auto-created) without changing your .tscn.
## - Prints weekday debug on each day advance (computed from Y/M/D).

const STATS_AUTOLOAD_PATH : String = "/root/aStatsSystem"
const CAL_AUTOLOAD_PATH   : String = "/root/aCalendarSystem"
const GS_PATH             : String = "/root/aGameState"
const PARTY_PATH          : String = "/root/aPartySystem"

# Local stat keys (kept in sync with StatsSystem)
const STATS_KEYS: Array[String] = ["BRW","MND","TPO","VTL","FCS"]

# Fallback only (UI guess) if StatsSystem doesn't give us a 'fatigued' boolean
const FATIGUE_THRESHOLD_PER_WEEK := 60

@onready var _root_vb    : VBoxContainer = %Root
@onready var _list       : VBoxContainer = %List
@onready var _refresh    : Button        = %RefreshBtn
@onready var _title      : Label         = %Title
@onready var _member_bar : HBoxContainer = %MemberBar

# Radar chart for stat visualization
var _radar_chart : Control = null

var _stats : Node = null
var _cal   : Node = null
var _gs    : Node = null
var _party : Node = null

var _current_id : String = "hero"

func _ready() -> void:
	_stats = get_node_or_null(STATS_AUTOLOAD_PATH)
	_cal   = get_node_or_null(CAL_AUTOLOAD_PATH)
	_gs    = get_node_or_null(GS_PATH)
	_party = get_node_or_null(PARTY_PATH)

	if _refresh and not _refresh.pressed.is_connected(_rebuild_all):
		_refresh.pressed.connect(_rebuild_all)

	# Listen for stat changes
	if _stats:
		if _stats.has_signal("stat_leveled_up"): _stats.connect("stat_leveled_up", Callable(self, "_on_stats_changed"))
		if _stats.has_signal("stats_changed"):    _stats.connect("stats_changed", Callable(self, "_on_stats_changed"))
		if _stats.has_signal("level_up"):         _stats.connect("level_up", Callable(self, "_on_stats_changed"))

	# Calendar: listen so we can print weekday debug + refresh UI
	if _cal and _cal.has_signal("week_reset"):
		_cal.connect("week_reset", Callable(self, "_on_stats_changed"))
	if _cal and _cal.has_signal("day_advanced"):
		_cal.connect("day_advanced", Callable(self, "_on_cal_day_advanced"))

	# Party changes → refresh selector
	for src in [_gs, _party]:
		if src == null: continue
		for sig in ["party_changed","active_changed","roster_changed","changed"]:
			if src.has_signal(sig) and not src.is_connected(sig, Callable(self, "_on_party_changed")):
				src.connect(sig, Callable(self, "_on_party_changed"))

	# Creation screen may ping us
	for n in get_tree().root.get_children():
		if n.has_signal("creation_applied") and not n.is_connected("creation_applied", Callable(self, "_rebuild_all")):
			n.connect("creation_applied", Callable(self, "_rebuild_all"))

	# Create and add radar chart
	_create_radar_chart()

	# build
	_rebuild_member_bar()
	_rebuild_all()

# ---------- Calendar weekday debug ----------
func _on_cal_day_advanced(date: Dictionary) -> void:
	var info := _derive_day_info(date)
	print("[StatsPanel][Cal] payload=", date)
	if info.get("ok", false):
		print("[StatsPanel][Cal] computed day=", String(info["day_name"]), " (idx=", int(info["day_index"]), ")")
	else:
		print("[StatsPanel][Cal] could not compute weekday (need year/month/day).")
	_on_stats_changed()

# Sakamoto’s algorithm (Gregorian). Returns 0=Mon..6=Sun.
func _dow_index_gregorian(y: int, m: int, d: int) -> int:
	var t: PackedInt32Array = PackedInt32Array([0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4])
	var yy: int = y
	if m < 3:
		yy -= 1

	var div4: int   = int(floor(float(yy) / 4.0))
	var div100: int = int(floor(float(yy) / 100.0))
	var div400: int = int(floor(float(yy) / 400.0))

	var sun0: int = (yy + div4 - div100 + div400 + t[m - 1] + d) % 7  # 0=Sun..6=Sat
	var mon0: int = (sun0 + 6) % 7                                    # shift so 0=Mon..6=Sun
	return mon0

func _derive_day_info(date: Dictionary) -> Dictionary:
	var y: int = int(date.get("year", 0))
	var m: int = int(date.get("month", 0))
	var d: int = int(date.get("day", 0))
	if y <= 0 or m <= 0 or d <= 0:
		return {"ok": false}
	var idx: int = _dow_index_gregorian(y, m, d)  # 0=Mon..6=Sun
	var names: Array[String] = ["monday","tuesday","wednesday","thursday","friday","saturday","sunday"]
	return {"ok": true, "day_index": idx, "day_name": names[idx]}

# ---------- Signals ----------
func _on_stats_changed(_a: Variant = null, _b: Variant = null) -> void:
	_rebuild_list_only()

func _on_party_changed(_a: Variant = null, _b: Variant = null) -> void:
	_rebuild_member_bar()
	if not _in_party(_current_id) and not _active_party_ids().is_empty():
		_current_id = String(_active_party_ids()[0])
	_rebuild_all()

# ---------- Build / Rebuild ----------
func _rebuild_all() -> void:
	_update_title()
	_rebuild_list_only()

func _rebuild_list_only() -> void:
	for c in _list.get_children():
		c.queue_free()

	# Redraw radar chart with updated stats
	if _radar_chart:
		_radar_chart.queue_redraw()

	var is_hero := (_current_id == "hero")
	var data := ( _get_stats_for_hero() if is_hero else _get_stats_for_member(_current_id) )

	# Optional "overall level" row at the top
	var lvl := _get_member_level(_current_id)
	_add_header_row2("Info", "Value")
	_add_row2("Level", str(lvl))
	_add_spacer_row()

	# Stats header + rows
	if is_hero:
		_add_header_row3("Stat", "Level", "SXP / Fatigued")
	else:
		_add_header_row2("Stat", "Level")

	var keys: Array[String] = []
	for k in data.keys(): keys.append(String(k))
	keys.sort()

	for key in keys:
		var entry_v: Variant = data.get(key)
		var level: int = 0
		var sxp: int = 0
		var fatigue_txt := "false"  # default

		if typeof(entry_v) == TYPE_DICTIONARY:
			var entry: Dictionary = entry_v
			level = int(entry.get("level", entry.get("lvl", 0)))

			if is_hero:
				# Prefer the true boolean when present
				if entry.has("fatigued"):
					var fb: Variant = entry["fatigued"]
					fatigue_txt = "true" if (typeof(fb) == TYPE_BOOL and fb) else "false"
				elif entry.has("fatigue"):
					# Legacy alias is a number: weekly SXP (not the boolean state). Fall back to threshold.
					var fv: Variant = entry["fatigue"]
					if typeof(fv) in [TYPE_INT, TYPE_FLOAT]:
						fatigue_txt = "true" if int(fv) >= FATIGUE_THRESHOLD_PER_WEEK else "false"
				elif entry.has("weekly"):
					var wv: Variant = entry["weekly"]
					if typeof(wv) in [TYPE_INT, TYPE_FLOAT]:
						fatigue_txt = "true" if int(wv) >= FATIGUE_THRESHOLD_PER_WEEK else "false"

				# SXP for display (best-effort)
				sxp = int(entry.get("sxp", entry.get("xp", 0)))

		elif typeof(entry_v) in [TYPE_INT, TYPE_FLOAT]:
			level = int(entry_v)

		if is_hero:
			var right := "%d / %s" % [sxp, fatigue_txt]
			_add_row3(String(key).capitalize(), str(level), right)
		else:
			_add_row2(String(key).capitalize(), str(level))

	# Add Affinity (AXP) section
	_add_spacer_row()
	_add_affinity_section(_current_id)

	await get_tree().process_frame
	_list.queue_sort()

# ---------- Data pulls ----------
func _get_stats_for_hero() -> Dictionary:
	# Prefer purpose-built payload from StatsSystem
	if _stats != null and _stats.has_method("get_stats_panel_dict"):
		var d1: Variant = _stats.call("get_stats_panel_dict")
		if typeof(d1) == TYPE_DICTIONARY and not (d1 as Dictionary).is_empty():
			return d1 as Dictionary

	# Next: their existing get_stats_dict()/to_dict() already returns {stat:{level,sxp,weekly/fatigued/fatigue}}
	if _stats != null:
		if _stats.has_method("get_stats_dict"):
			var d2_v: Variant = _stats.call("get_stats_dict")
			if typeof(d2_v) == TYPE_DICTIONARY and not (d2_v as Dictionary).is_empty():
				return d2_v as Dictionary
		if _stats.has_method("to_dict"):
			var d3_v: Variant = _stats.call("to_dict")
			if typeof(d3_v) == TYPE_DICTIONARY and not (d3_v as Dictionary).is_empty():
				return d3_v as Dictionary

	# Fallback: picked stats (still show as level 1)
	if _gs != null and _gs.has_meta("hero_picked_stats"):
		var out: Dictionary = {}
		var ps_v: Variant = _gs.get_meta("hero_picked_stats")
		if typeof(ps_v) == TYPE_PACKED_STRING_ARRAY:
			for s in (ps_v as PackedStringArray): out[String(s)] = {"level":1,"sxp":0,"fatigued":false}
		elif typeof(ps_v) == TYPE_ARRAY:
			for v in (ps_v as Array): out[String(v)] = {"level":1,"sxp":0,"fatigued":false}
		return out

	# Final fallback: all keys at level 1
	var out2: Dictionary = {}
	for s in STATS_KEYS: out2[s] = {"level":1,"sxp":0,"fatigued":false}
	return out2

func _get_stats_for_member(pid: String) -> Dictionary:
	var out: Dictionary = {}
	if _stats == null:
		for s in STATS_KEYS: out[s] = {"level":1}
		return out

	for s in STATS_KEYS:
		var lv := 1
		if _stats.has_method("get_member_stat_level"):
			var v: Variant = _stats.call("get_member_stat_level", pid, s)
			if typeof(v) in [TYPE_INT, TYPE_FLOAT]: lv = int(v)
		out[s] = {"level": lv}
	return out

func _get_member_level(pid: String) -> int:
	if _stats and _stats.has_method("get_member_level"):
		var v: Variant = _stats.call("get_member_level", pid)
		if typeof(v) in [TYPE_INT, TYPE_FLOAT]: return int(v)
	return 1

# ---------- Member bar ----------
func _rebuild_member_bar() -> void:
	if _member_bar == null: return
	for c in _member_bar.get_children(): c.queue_free()

	var group := ButtonGroup.new()
	for id_any in _active_party_ids():
		var pid := String(id_any)
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_group = group
		btn.text = _label_for(pid)
		btn.pressed.connect(_on_pick_member.bind(pid))
		if pid == _current_id: btn.button_pressed = true
		_member_bar.add_child(btn)

	# Fallback “hero” if no party
	if _member_bar.get_child_count() == 0:
		var b := Button.new()
		b.toggle_mode = true
		b.text = _label_for("hero")
		b.button_group = group
		b.button_pressed = true
		b.pressed.connect(_on_pick_member.bind("hero"))
		_member_bar.add_child(b)

func _on_pick_member(pid: String) -> void:
	_current_id = pid
	_update_title()
	_rebuild_list_only()

# ---------- Helpers ----------
func _active_party_ids() -> Array:
	var combined: Array = []

	# Get active party members
	if _gs and _gs.has_method("get_active_party_ids"):
		var v: Variant = _gs.call("get_active_party_ids")
		if typeof(v) == TYPE_ARRAY:
			combined.append_array(v as Array)
		elif typeof(v) == TYPE_PACKED_STRING_ARRAY:
			for s in (v as PackedStringArray): combined.append(String(s))

	# Get benched members
	if _gs and _gs.has_method("get"):
		var bench_v: Variant = _gs.get("bench")
		if typeof(bench_v) == TYPE_ARRAY:
			combined.append_array(bench_v as Array)
		elif typeof(bench_v) == TYPE_PACKED_STRING_ARRAY:
			for s in (bench_v as PackedStringArray): combined.append(String(s))

	# Fallback to hero if nothing found
	if combined.is_empty():
		return ["hero"]

	return combined

func _in_party(pid: String) -> bool:
	for id_any in _active_party_ids():
		if String(id_any) == pid: return true
	return (pid == "hero")

func _label_for(pid: String) -> String:
	# First try StatsSystem's get_member_display_name (gets name from CSV)
	if _stats and _stats.has_method("get_member_display_name"):
		var name_v: Variant = _stats.call("get_member_display_name", pid)
		if typeof(name_v) == TYPE_STRING and String(name_v).strip_edges() != "":
			return String(name_v)

	# Fallback for hero: check player_name in GameState
	if pid == "hero" and _gs and _gs.has_method("get"):
		var nm_v: Variant = _gs.get("player_name")
		if typeof(nm_v) == TYPE_STRING and String(nm_v).strip_edges() != "":
			return String(nm_v)

	# Last resort: capitalize the ID
	return pid.capitalize()

func _update_title() -> void:
	if _title:
		_title.text = "%s Stats" % _label_for(_current_id)

# ---------- Row builders ----------
func _add_header_row3(col1: String, col2: String, col3: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	var l1 := Label.new(); l1.text = col1; l1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l2 := Label.new(); l2.text = col2; l2.custom_minimum_size.x = 80
	var l3 := Label.new(); l3.text = col3; l3.custom_minimum_size.x = 160
	row.add_child(l1); row.add_child(l2); row.add_child(l3)
	_list.add_child(row)

func _add_header_row2(col1: String, col2: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	var l1 := Label.new(); l1.text = col1; l1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var l2 := Label.new(); l2.text = col2; l2.custom_minimum_size.x = 100
	row.add_child(l1); row.add_child(l2)
	_list.add_child(row)

func _add_row3(stat_name: String, level: String, right: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)
	var n := Label.new();  n.text = stat_name;  n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var lv := Label.new(); lv.text = level;     lv.custom_minimum_size.x = 80
	var rv := Label.new(); rv.text = right;     rv.custom_minimum_size.x = 160
	row.add_child(n); row.add_child(lv); row.add_child(rv)
	_list.add_child(row)

func _add_row2(label_text: String, val: String) -> void:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 8)

	var n := Label.new()
	n.text = label_text
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var v := Label.new()
	v.text = val
	v.custom_minimum_size.x = 100

	row.add_child(n)
	row.add_child(v)
	_list.add_child(row)

func _add_spacer_row() -> void:
	var sep := HSeparator.new()
	_list.add_child(sep)

func _add_affinity_section(member_id: String) -> void:
	"""Add AXP/Affinity relationships section for the current member"""
	var affinity_sys = get_node_or_null("/root/aAffinitySystem")
	if not affinity_sys or not affinity_sys.has_method("get_all_pair_data"):
		return

	var all_pairs: Array = affinity_sys.call("get_all_pair_data")
	var relationships: Array = []

	# Find all pairs involving this member
	for pair_data in all_pairs:
		if typeof(pair_data) != TYPE_DICTIONARY:
			continue

		var pair_dict: Dictionary = pair_data
		var member_a: String = String(pair_dict.get("member_a", ""))
		var member_b: String = String(pair_dict.get("member_b", ""))

		# Check if this member is in this pair
		var partner_id: String = ""
		if member_a == member_id:
			partner_id = member_b
		elif member_b == member_id:
			partner_id = member_a
		else:
			continue  # This pair doesn't involve this member

		# Get partner's display name
		var partner_name: String = _label_for(partner_id)

		relationships.append({
			"partner_id": partner_id,
			"partner_name": partner_name,
			"tier": int(pair_dict.get("tier", 0)),
			"weekly_axp": int(pair_dict.get("weekly_axp", 0)),
			"lifetime_axp": int(pair_dict.get("lifetime_axp", 0))
		})

	# Only show section if there are relationships
	if relationships.is_empty():
		return

	# Add header
	_add_header_row2("Affinity", "Tier (Lifetime)")

	# Add each relationship
	for rel in relationships:
		var partner_name: String = String(rel.get("partner_name", "???"))
		var tier: int = int(rel.get("tier", 0))
		var lifetime: int = int(rel.get("lifetime_axp", 0))

		var tier_text: String = "AT%d (%d)" % [tier, lifetime]
		_add_row2(partner_name, tier_text)

# ---------- Radar Chart ----------
func _create_radar_chart() -> void:
	_radar_chart = Control.new()
	_radar_chart.custom_minimum_size = Vector2(300, 300)
	_radar_chart.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_radar_chart.set_process(false)  # No need for _process, we'll redraw manually

	# Insert chart after MemberBar, before Scroll
	var member_bar_idx := _member_bar.get_index()
	_root_vb.add_child(_radar_chart)
	_root_vb.move_child(_radar_chart, member_bar_idx + 1)

	# Connect draw callback
	_radar_chart.draw.connect(_on_radar_draw)

func _on_radar_draw() -> void:
	if _radar_chart == null:
		return

	# Get current member stats
	var is_hero := (_current_id == "hero")
	var data := (_get_stats_for_hero() if is_hero else _get_stats_for_member(_current_id))

	# Extract stat levels in order: BRW, MND, TPO, VTL, FCS
	var stat_levels: Array[float] = []
	for key in STATS_KEYS:
		var entry_v: Variant = data.get(key)
		var level: float = 0.0
		if typeof(entry_v) == TYPE_DICTIONARY:
			level = float((entry_v as Dictionary).get("level", (entry_v as Dictionary).get("lvl", 0)))
		elif typeof(entry_v) in [TYPE_INT, TYPE_FLOAT]:
			level = float(entry_v)
		stat_levels.append(level)

	_draw_pentagon_radar(_radar_chart, stat_levels)

func _draw_pentagon_radar(control: Control, stat_levels: Array[float]) -> void:
	var chart_size: Vector2 = control.size
	var center: Vector2 = chart_size / 2.0
	var max_radius: float = min(chart_size.x, chart_size.y) / 2.0 - 20.0  # Padding

	# Draw 10 concentric pentagons (grid layers)
	for layer in range(1, 11):
		var radius := max_radius * (float(layer) / 10.0)
		var points := _get_pentagon_points(center, radius)
		var color := Color(0.3, 0.3, 0.3, 0.3)  # Dark gray for grid
		_draw_pentagon_outline(control, points, color, 1.0)

	# Draw axis lines from center to each vertex
	for i in range(5):
		var angle := -PI / 2.0 + (TAU / 5.0) * float(i)  # Start from top
		var end_point := center + Vector2(cos(angle), sin(angle)) * max_radius
		control.draw_line(center, end_point, Color(0.4, 0.4, 0.4, 0.5), 1.0)

	# Draw stat labels at each point
	var label_names: Array[String] = ["BRW", "MND", "TPO", "VTL", "FCS"]
	for i in range(5):
		var angle := -PI / 2.0 + (TAU / 5.0) * float(i)
		var label_pos := center + Vector2(cos(angle), sin(angle)) * (max_radius + 15.0)
		# Offset label based on position so it doesn't overlap
		label_pos.x -= 15.0  # Rough centering
		label_pos.y -= 5.0
		control.draw_string(ThemeDB.fallback_font, label_pos, label_names[i],
							HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)

	# Calculate stat polygon points (normalized to 0-10 range)
	var stat_points: PackedVector2Array = PackedVector2Array()
	for i in range(5):
		var stat_level: float = clamp(stat_levels[i], 0.0, 10.0)
		var normalized: float = stat_level / 10.0  # Normalize to 0-1
		var angle: float = -PI / 2.0 + (TAU / 5.0) * float(i)
		var point: Vector2 = center + Vector2(cos(angle), sin(angle)) * max_radius * normalized
		stat_points.append(point)

	# Draw filled stat polygon (light blue)
	if stat_points.size() >= 3:
		control.draw_colored_polygon(stat_points, Color(0.3, 0.6, 1.0, 0.4))

	# Draw stat polygon outline (brighter blue)
	if stat_points.size() >= 2:
		for i in range(stat_points.size()):
			var start := stat_points[i]
			var end := stat_points[(i + 1) % stat_points.size()]
			control.draw_line(start, end, Color(0.4, 0.7, 1.0, 0.8), 2.0)

func _get_pentagon_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(5):
		var angle := -PI / 2.0 + (TAU / 5.0) * float(i)  # Start from top
		var point := center + Vector2(cos(angle), sin(angle)) * radius
		points.append(point)
	return points

func _draw_pentagon_outline(control: Control, points: PackedVector2Array, color: Color, width: float) -> void:
	for i in range(points.size()):
		var start := points[i]
		var end := points[(i + 1) % points.size()]
		control.draw_line(start, end, color, width)
