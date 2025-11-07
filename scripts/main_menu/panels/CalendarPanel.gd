extends PanelBase
class_name CalendarPanel

## CalendarPanel (MVP, timeless + current-month-only)
## - Renders current month from aCalendarSystem
## - No year in headers
## - Current day is highlighted (rounded border + subtle fill)
## - Rebuilds on phase/day/week signals
## - Supports keyboard/controller navigation for month buttons
##
## ARCHITECTURE:
## - Extends PanelBase for lifecycle management
## - Pure display panel with button navigation
## - No popups needed (read-only calendar display)
## - Reactive to CalendarSystem signals

var _label_month : Label
var _grid        : GridContainer
var _btn_prev    : Button
var _btn_next    : Button
var _btn_today   : Button
var _events_list : VBoxContainer  # For future Important Dates functionality

const WEEKDAY_HEADERS : PackedStringArray = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"]

# Month navigation state
var _current_year: int = 2025  # The actual current year/month from calendar system
var _current_month: int = 5
var _current_day: int = 1
var _view_year: int = 2025     # The year/month being viewed (can navigate)
var _view_month: int = 5
var _earliest_year: int = 2025  # Earliest experienced month (for now, same as current)
var _earliest_month: int = 5

# Button navigation state
enum FocusState { CALENDAR, BUTTONS }
var _focus_state: FocusState = FocusState.CALENDAR
var _button_index: int = 1  # 0=prev, 1=today, 2=next

func _ready() -> void:
	super()  # Call PanelBase._ready() for lifecycle management

	# Set up layout
	set_anchors_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Use unique names from scene (% syntax is most reliable)
	_label_month = get_node_or_null("%MonthLabel")
	_grid        = get_node_or_null("%Grid")
	_btn_prev    = get_node_or_null("%PrevBtn")
	_btn_next    = get_node_or_null("%NextBtn")
	_btn_today   = get_node_or_null("%TodayBtn")
	_events_list = get_node_or_null("%EventsList")

	# Debug: Check if critical nodes were found
	print("[CalendarPanel._ready] Node check:")
	print("  _label_month: ", _label_month != null)
	print("  _grid: ", _grid != null)
	print("  _btn_prev: ", _btn_prev != null)
	print("  _btn_next: ", _btn_next != null)
	print("  _btn_today: ", _btn_today != null)
	print("  _events_list: ", _events_list != null)

	if not _grid:
		push_error("[CalendarPanel._ready] CRITICAL: Grid container not found! Calendar will not display.")
		push_error("[CalendarPanel._ready] Scene structure may be incorrect. Expected paths: Body/Grid, Grid, Root/Grid, or MonthGrid")
		return

	# Wire up navigation buttons
	if _btn_prev:
		_btn_prev.pressed.connect(_on_prev_month)
	if _btn_next:
		_btn_next.pressed.connect(_on_next_month)
	if _btn_today:
		_btn_today.pressed.connect(_on_today_pressed)

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
	# Start in calendar view
	_focus_state = FocusState.CALENDAR

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
	# Check if grid exists
	if not _grid:
		push_error("[CalendarPanel] Grid container not found - cannot rebuild calendar")
		return

	# clear
	for c in _grid.get_children():
		c.queue_free()

	var cal: Node = get_node_or_null("/root/aCalendarSystem")

	# Get current date from calendar system (the "today" date)
	if cal:
		var d_v: Variant = cal.get("current_date")
		if typeof(d_v) == TYPE_DICTIONARY:
			var d: Dictionary = d_v
			_current_year  = int(d.get("year", 2025))
			_current_month = int(d.get("month", 5))
			_current_day   = int(d.get("day", 1))

	# Initialize view to current month if not set
	if _view_year == 0 or _view_month == 0:
		_view_year = _current_year
		_view_month = _current_month

	# For now, earliest is same as current (TODO: track earliest experienced month)
	_earliest_year = _current_year
	_earliest_month = _current_month

	# Update button states
	_update_navigation_buttons()

	# month header (uppercase for style consistency)
	if _label_month and cal and cal.has_method("get_month_name"):
		_label_month.text = String(cal.call("get_month_name", _view_month)).to_upper()
	elif _label_month:
		_label_month.text = _month_name_local(_view_month).to_upper()

	# weekday header
	for i in range(7):
		var h: Label = Label.new()
		h.text = WEEKDAY_HEADERS[i]
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.add_theme_color_override("font_color", Color(1,1,1,0.8))
		_grid.add_child(h)

	# layout math
	var first_idx: int = _weekday_0_mon(_view_year, _view_month, 1) # 0=Mon..6=Sun
	var total_days: int = _days_in_month(_view_year, _view_month)

	# blanks before day 1
	for _i in range(first_idx):
		_grid.add_child(_blank_cell())

	# day cells
	for dnum in range(1, total_days + 1):
		# Only highlight if viewing current month
		var is_today: bool = (_view_year == _current_year and _view_month == _current_month and dnum == _current_day)
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
		# Light blue highlight for current day (matching game style)
		sb.bg_color = Color(0.4, 0.7, 1.0, 0.25)  # Light blue with transparency
		sb.border_color = Color(0.4, 0.7, 1.0, 0.9)  # Light blue border
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

# --- input handling ------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	"""Handle controller/keyboard input for button navigation"""
	if not is_active():
		return

	match _focus_state:
		FocusState.CALENDAR:
			# In calendar view, press up to enter button navigation
			if event.is_action_pressed("move_up") or event.is_action_pressed("ui_up"):
				_focus_state = FocusState.BUTTONS
				# Find first enabled button (prefer Today, then Prev, then Next)
				_button_index = 1  # Start with "Today"
				if not _is_button_enabled(_button_index):
					# Try Prev
					_button_index = 0
					if not _is_button_enabled(_button_index):
						# Try Next
						_button_index = 2
				_update_button_focus()
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("menu_back"):
				# Back button exits the calendar panel
				# Let PanelBase or GameMenu handle it (don't mark as handled)
				pass

		FocusState.BUTTONS:
			# In button navigation mode
			if event.is_action_pressed("move_down") or event.is_action_pressed("ui_down") or event.is_action_pressed("menu_back"):
				# Go back to calendar view
				_focus_state = FocusState.CALENDAR
				_clear_button_focus()
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("move_left") or event.is_action_pressed("ui_left"):
				# Move left through buttons, skipping disabled ones
				_navigate_buttons_left()
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("move_right") or event.is_action_pressed("ui_right"):
				# Move right through buttons, skipping disabled ones
				_navigate_buttons_right()
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed("menu_accept"):
				# Press the currently focused button
				_press_focused_button()
				get_viewport().set_input_as_handled()

func _navigate_buttons_left() -> void:
	"""Navigate left through buttons, skipping disabled ones"""
	var original_index = _button_index

	# Try to move left
	for i in range(3):  # Max 3 attempts to avoid infinite loop
		_button_index -= 1
		if _button_index < 0:
			_button_index = 2  # Wrap around to rightmost button

		# Check if this button is enabled
		if _is_button_enabled(_button_index):
			_update_button_focus()
			return

	# If we couldn't find an enabled button, stay where we were
	_button_index = original_index

func _navigate_buttons_right() -> void:
	"""Navigate right through buttons, skipping disabled ones"""
	var original_index = _button_index

	# Try to move right
	for i in range(3):  # Max 3 attempts to avoid infinite loop
		_button_index += 1
		if _button_index > 2:
			_button_index = 0  # Wrap around to leftmost button

		# Check if this button is enabled
		if _is_button_enabled(_button_index):
			_update_button_focus()
			return

	# If we couldn't find an enabled button, stay where we were
	_button_index = original_index

func _is_button_enabled(index: int) -> bool:
	"""Check if a button at given index is enabled"""
	match index:
		0:
			return _btn_prev and not _btn_prev.disabled
		1:
			return _btn_today and not _btn_today.disabled
		2:
			return _btn_next and not _btn_next.disabled
	return false

func _update_button_focus() -> void:
	"""Update which button has focus"""
	match _button_index:
		0:
			if _btn_prev:
				_btn_prev.grab_focus()
		1:
			if _btn_today:
				_btn_today.grab_focus()
		2:
			if _btn_next:
				_btn_next.grab_focus()

func _clear_button_focus() -> void:
	"""Clear button focus when returning to calendar"""
	if _btn_prev:
		_btn_prev.release_focus()
	if _btn_today:
		_btn_today.release_focus()
	if _btn_next:
		_btn_next.release_focus()

func _press_focused_button() -> void:
	"""Trigger the currently focused button"""
	match _button_index:
		0:
			if _btn_prev and not _btn_prev.disabled:
				_on_prev_month()
		1:
			if _btn_today and not _btn_today.disabled:
				_on_today_pressed()
		2:
			if _btn_next and not _btn_next.disabled:
				_on_next_month()

# --- navigation handlers -------------------------------------------------------

func _on_prev_month() -> void:
	"""Navigate to previous month"""
	_view_month -= 1
	if _view_month < 1:
		_view_month = 12
		_view_year -= 1
	_rebuild()
	# Keep button focus after navigation
	if _focus_state == FocusState.BUTTONS:
		call_deferred("_update_button_focus")

func _on_next_month() -> void:
	"""Navigate to next month"""
	_view_month += 1
	if _view_month > 12:
		_view_month = 1
		_view_year += 1
	_rebuild()
	# Keep button focus after navigation
	if _focus_state == FocusState.BUTTONS:
		call_deferred("_update_button_focus")

func _on_today_pressed() -> void:
	"""Jump back to current month"""
	_view_year = _current_year
	_view_month = _current_month
	_rebuild()
	# Keep button focus after navigation
	if _focus_state == FocusState.BUTTONS:
		call_deferred("_update_button_focus")

func _update_navigation_buttons() -> void:
	"""Update enabled/disabled state of navigation buttons"""
	# Can go back to earliest experienced month
	var at_earliest: bool = (_view_year == _earliest_year and _view_month == _earliest_month)

	# Can go forward 1 month from current
	var one_month_ahead_year: int = _current_year
	var one_month_ahead_month: int = _current_month + 1
	if one_month_ahead_month > 12:
		one_month_ahead_month = 1
		one_month_ahead_year += 1

	var at_max_future: bool = (_view_year == one_month_ahead_year and _view_month == one_month_ahead_month) or \
							  (_view_year > one_month_ahead_year) or \
							  (_view_year == one_month_ahead_year and _view_month > one_month_ahead_month)

	# Update button states
	if _btn_prev:
		_btn_prev.disabled = at_earliest

	if _btn_next:
		_btn_next.disabled = at_max_future

	# Today button is disabled if already viewing current month
	if _btn_today:
		_btn_today.disabled = (_view_year == _current_year and _view_month == _current_month)
