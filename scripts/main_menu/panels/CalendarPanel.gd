extends PanelBase
class_name CalendarPanel

## CalendarPanel (MVP, timeless + current-month-only)
## - Renders current month from aCalendarSystem
## - No year in headers
## - Current day is highlighted (rounded border + subtle fill)
## - Rebuilds on phase/day/week signals
##
## ARCHITECTURE:
## - Extends PanelBase for lifecycle management
## - Pure display panel (no NavState needed)
## - No popups needed (read-only calendar display)
## - Reactive to CalendarSystem signals

var _label_month : Label
var _grid        : GridContainer
var _btn_prev    : Button
var _btn_next    : Button

const WEEKDAY_HEADERS : PackedStringArray = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]

func _ready() -> void:
	super()  # Call PanelBase._ready() for lifecycle management

	# Set up layout
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	_label_month = _find_label(["Header/MonthLabel","MonthLabel","Header/Title","Title"])
	_grid        = _find_grid (["Body/Grid","Grid","Root/Grid","MonthGrid"])
	_btn_prev    = _find_button(["Header/Prev","Prev","PrevBtn"])
	_btn_next    = _find_button(["Header/Next","Next","NextBtn"])

	# current-month-only
	if _btn_prev:
		_btn_prev.visible = false
		_btn_prev.disabled = true
	if _btn_next:
		_btn_next.visible = false
		_btn_next.disabled = true

	# build a grid if missing
	if _grid == null:
		_grid = GridContainer.new()
		_grid.columns = 7
		_grid.name = "Grid"
		_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_grid.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		add_child(_grid)

	# listen for calendar changes
	var cal: Node = get_node_or_null("/root/aCalendarSystem")
	if cal:
		if cal.has_signal("day_advanced"):   cal.connect("day_advanced",  Callable(self, "_on_cal_update"))
		if cal.has_signal("phase_advanced"): cal.connect("phase_advanced", Callable(self, "_on_cal_update"))
		if cal.has_signal("week_reset"):     cal.connect("week_reset",     Callable(self, "_on_cal_update"))

	_rebuild()

# --- PanelBase Lifecycle Overrides ---------------------------------------------

func _on_panel_gained_focus() -> void:
	super()
	print("[CalendarPanel] Gained focus - refreshing calendar display")
	# Refresh calendar when panel becomes active (in case date changed while away)
	_rebuild()

# --- node finders --------------------------------------------------------------

func _find_label(paths: PackedStringArray) -> Label:
	for p in paths:
		var n: Node = get_node_or_null(p)
		if n: return n as Label
	for p in paths:
		var f := find_child(p.get_file(), true, false)
		if f: return f as Label
	return null

func _find_button(paths: PackedStringArray) -> Button:
	for p in paths:
		var n: Node = get_node_or_null(p)
		if n: return n as Button
	for p in paths:
		var f := find_child(p.get_file(), true, false)
		if f: return f as Button
	return null

func _find_grid(paths: PackedStringArray) -> GridContainer:
	for p in paths:
		var n: Node = get_node_or_null(p)
		if n: return n as GridContainer
	for p in paths:
		var f := find_child(p.get_file(), true, false)
		if f: return f as GridContainer
	return null

# --- rebuild -------------------------------------------------------------------

func _on_cal_update(_a: Variant = null) -> void:
	_rebuild()

func _rebuild() -> void:
	# clear
	for c in _grid.get_children():
		c.queue_free()

	var cal: Node = get_node_or_null("/root/aCalendarSystem")
	var year: int = 2025
	var month: int = 5
	var day: int = 1

	if cal:
		var d_v: Variant = cal.get("current_date")
		if typeof(d_v) == TYPE_DICTIONARY:
			var d: Dictionary = d_v
			year  = int(d.get("year", year))
			month = int(d.get("month", month))
			day   = int(d.get("day", day))

	# month header (no year)
	if _label_month and cal and cal.has_method("get_month_name"):
		_label_month.text = cal.call("get_month_name", month)
	elif _label_month:
		_label_month.text = _month_name_local(month)

	# weekday header
	for i in range(7):
		var h: Label = Label.new()
		h.text = WEEKDAY_HEADERS[i]
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_theme_color_override("font_color", Color(1,1,1,0.8))
		_grid.add_child(h)

	# layout math
	var first_idx: int = _weekday_0_mon(year, month, 1) # 0=Mon..6=Sun
	var total_days: int = _days_in_month(year, month)

	# blanks before day 1
	for _i in range(first_idx):
		_grid.add_child(_blank_cell())

	# day cells
	for dnum in range(1, total_days + 1):
		var is_today: bool = (dnum == day)
		_grid.add_child(_make_day_cell(dnum, is_today))

	# pad to full rows (optional nicety)
	var cells_now: int = _grid.get_child_count()
	var rows_needed: int = int(ceil(float(cells_now) / 7.0))
	var target_cells: int = rows_needed * 7
	for _j in range(target_cells - cells_now):
		_grid.add_child(_blank_cell())

# --- cell builders -------------------------------------------------------------

func _make_day_cell(num: int, is_today: bool) -> Control:
	# PanelContainer with StyleBoxFlat so we can paint a highlight
	var wrapper: PanelContainer = PanelContainer.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical   = Control.SIZE_EXPAND_FILL

	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0,0,0,0)   # transparent by default
	sb.corner_radius_top_left     = 6
	sb.corner_radius_top_right    = 6
	sb.corner_radius_bottom_left  = 6
	sb.corner_radius_bottom_right = 6

	if is_today:
		# subtle fill + clear border so it reads as "today"
		sb.bg_color = Color(1, 1, 1, 0.10)
		sb.border_color = Color(1, 1, 1, 0.9)
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2

	wrapper.add_theme_stylebox_override("panel", sb)

	var lbl: Label = Label.new()
	lbl.text = str(num)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	lbl.add_theme_color_override("font_color", Color(1,1,1,1) if is_today else Color(1,1,1,0.85))

	wrapper.add_child(lbl)
	return wrapper

func _blank_cell() -> Control:
	var c: Control = Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	return c

# --- local helpers -------------------------------------------------------------

func _month_name_local(m: int) -> String:
	var names: PackedStringArray = ["January","February","March","April","May","June","July","August","September","October","November","December"]
	m = clampi(m, 1, 12)
	return names[m - 1]

static func _weekday_0_mon(y: int, m: int, d: int) -> int:
	# Sakamoto (0=Sunday..6=Saturday) -> 0=Mon..6=Sun (float divisions to avoid warnings)
	var t: PackedInt32Array = [0,3,2,5,0,3,5,1,4,6,2,4]
	var y2: int = y
	if m < 3:
		y2 -= 1
	var term_f: float = float(y2)
	term_f += floor(float(y2) / 4.0)
	term_f -= floor(float(y2) / 100.0)
	term_f += floor(float(y2) / 400.0)
	term_f += float(t[m - 1]) + float(d)
	var w0_sun: int = int(term_f) % 7
	return (w0_sun + 6) % 7

static func _days_in_month(y: int, m: int) -> int:
	match m:
		1,3,5,7,8,10,12: return 31
		4,6,9,11:        return 30
		2:
			var leap: bool = ((y % 4 == 0) and (y % 100 != 0)) or (y % 400 == 0)
			return 29 if leap else 28
		_: return 30
