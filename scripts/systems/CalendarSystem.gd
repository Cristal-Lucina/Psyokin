extends Node
class_name CalendarSystem

## aCalendarSystem
## Date/phase tracker with bounds + timeless display (no year shown).
## Signals:
##  - day_advanced(date_dict)
##  - phase_advanced(phase_index)
##  - week_reset()
##
## Conventions:
##  - weekday index: 0=Mon .. 6=Sun
##  - phase index:   0=Morning, 1=Afternoon, 2=Evening

signal day_advanced(date: Dictionary)
signal phase_advanced(phase: int)
signal week_reset()

# ---- bounds (inclusive) -------------------------------------------------------

const START_YEAR  : int = 2025
const START_MONTH : int = 5   # May
const START_DAY   : int = 1

const END_YEAR    : int = 2026
const END_MONTH   : int = 1   # January
const END_DAY     : int = 31

# ---- live state ---------------------------------------------------------------

var current_date    : Dictionary = {"year": START_YEAR, "month": START_MONTH, "day": START_DAY}
var current_phase   : int = 0  # 0..2
var current_weekday : int = 0  # 0=Mon..6=Sun

# ---- lifecycle ----------------------------------------------------------------

func _ready() -> void:
	"""Initialize weekday from current_date."""
	current_weekday = get_weekday_index()

# ---- getters / labels (timeless) ---------------------------------------------

func get_date_string() -> String:
	"""Return MM/DD (year hidden)."""
	var m: int = int(current_date.get("month", START_MONTH))
	var d: int = int(current_date.get("day", START_DAY))
	return "%02d/%02d" % [m, d]

func get_weekday_name() -> String:
	"""Return weekday name with 0=Mon..6=Sun mapping."""
	var names: PackedStringArray = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]
	return names[clampi(current_weekday, 0, 6)]

func get_phase_name() -> String:
	"""Return current phase label."""
	match current_phase:
		0: return "Morning"
		1: return "Afternoon"
		2: return "Evening"
		_: return "Unknown"

func get_month_name(month: int) -> String:
	"""Month name helper (no year)."""
	var names: PackedStringArray = ["January","February","March","April","May","June","July","August","September","October","November","December"]
	month = clampi(month, 1, 12)
	return names[month - 1]

# ---- navigation (bounded) -----------------------------------------------------

func advance_phase() -> void:
	"""Advance phase; roll to next day after Evening; clamp at END date."""
	if current_phase < 2:
		current_phase += 1
		phase_advanced.emit(current_phase)
		return
	_advance_day_bounded()

func _advance_day_bounded() -> void:
	"""Advance day by +1 if within END bound; emit signals appropriately."""
	var y: int = int(current_date.get("year", START_YEAR))
	var m: int = int(current_date.get("month", START_MONTH))
	var d: int = int(current_date.get("day", START_DAY))

	var dim: int = _days_in_month(y, m)
	d += 1
	if d > dim:
		d = 1
		m += 1
		if m > 12:
			m = 1
			y += 1

	var next: Dictionary = {"year": y, "month": m, "day": d}
	if _is_after_end(next):
		# Clamp to END bound; do not advance beyond.
		current_phase = min(current_phase, 2)
		return

	current_date = next
	current_weekday = get_weekday_index()
	current_phase = 0
	day_advanced.emit(current_date)

	# Emit week_reset on Mondays
	if current_weekday == 0:
		week_reset.emit()

func set_date_clamped(date: Dictionary) -> void:
	"""External setter that clamps any incoming date to [START..END]."""
	var y: int = int(date.get("year", START_YEAR))
	var m: int = int(date.get("month", START_MONTH))
	var d: int = int(date.get("day", START_DAY))

	# clamp below start
	if _is_before_start({"year": y, "month": m, "day": d}):
		y = START_YEAR; m = START_MONTH; d = START_DAY
	# clamp above end
	if _is_after_end({"year": y, "month": m, "day": d}):
		y = END_YEAR; m = END_MONTH; d = END_DAY

	current_date = {"year": y, "month": m, "day": clampi(d, 1, _days_in_month(y, m))}
	current_weekday = get_weekday_index()

# ---- helpers / math -----------------------------------------------------------

func get_weekday_index() -> int:
	"""Sakamoto algorithm adapted to 0=Mon..6=Sun."""
	var y: int = int(current_date.get("year", START_YEAR))
	var m: int = int(current_date.get("month", START_MONTH))
	var d: int = int(current_date.get("day", START_DAY))
	return _weekday_0_mon(y, m, d)

static func _weekday_0_mon(y: int, m: int, d: int) -> int:
	# Sakamoto (0=Sunday..6=Saturday) -> convert to 0=Mon..6=Sun
	var t: PackedInt32Array = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
	var y2: int = y
	if m < 3:
		y2 -= 1
	# Use float division + floor to avoid integer-division warnings
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

static func _cmp_dates(a: Dictionary, b: Dictionary) -> int:
	# return -1 if a<b, 0 if equal, 1 if a>b (lexicographic Y/M/D)
	var ay: int = int(a.get("year", 0))
	var am: int = int(a.get("month", 0))
	var ad: int = int(a.get("day", 0))
	var by: int = int(b.get("year", 0))
	var bm: int = int(b.get("month", 0))
	var bd: int = int(b.get("day", 0))
	if ay != by: return -1 if ay < by else 1
	if am != bm: return -1 if am < bm else 1
	if ad != bd: return -1 if ad < bd else 1
	return 0

static func _is_before_start(d: Dictionary) -> bool:
	return _cmp_dates(d, {"year": START_YEAR, "month": START_MONTH, "day": START_DAY}) < 0

static func _is_after_end(d: Dictionary) -> bool:
	return _cmp_dates(d, {"year": END_YEAR, "month": END_MONTH, "day": END_DAY}) > 0
