extends Node
class_name CalendarSystem

signal day_advanced(new_date: Dictionary)
signal phase_advanced(new_phase: int)
signal week_reset(new_weekday: int)

# 3-phase loop
enum Phase { MORNING, AFTERNOON, EVENING }

# ---- Internal state (year tracked for math/saves, not shown to player) ----
var year: int = 2025
var month: int = 5
var day: int = 10
## 0 = Monday … 6 = Sunday
var weekday: int = 0
## store phase as int (no enum function-calls)
var phase: int = Phase.MORNING

# ---- Compatibility properties (GameState uses these) ----
var current_date: Dictionary:
	get: return {"year": year, "month": month, "day": day}
	set(value):
		if typeof(value) == TYPE_DICTIONARY:
			var d: Dictionary = value
			year  = int(d.get("year",  year))
			month = int(d.get("month", month))
			day   = int(d.get("day",   day))
			# If nobody sets weekday explicitly, keep it consistent
			weekday = _weekday_0_mon(year, month, day)

var current_phase: int:
	get: return phase
	set(value):
		phase = clamp(int(value), Phase.MORNING, Phase.EVENING)

var current_weekday: int:
	get: return weekday
	set(value):
		weekday = clamp(int(value), 0, 6)

# ---- Pretty names ----
const WEEKDAY_NAMES: PackedStringArray = [
	"Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
]
const MONTH_NAMES: PackedStringArray = [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"
]
const PHASE_NAMES: PackedStringArray = ["Morning", "Afternoon", "Evening"]

# ─────────────────────────── Public API ───────────────────────────

func get_weekday_name() -> String:
	return WEEKDAY_NAMES[weekday]

# Accepts optional month param for callers like CalendarPanel
func get_month_name(m: int = -1) -> String:
	var mm := (m if m >= 1 else month)
	return MONTH_NAMES[clampi(mm, 1, 12) - 1]

func get_phase_name() -> String:
	return PHASE_NAMES[clampi(phase, 0, PHASE_NAMES.size() - 1)]

# For HUD (Status/Main top bar): "Monday — May 10"
func get_date_string() -> String:
	return "%s — %s %d" % [get_weekday_name(), get_month_name(), day]

# One-liner the HUD can use directly (date + phase)
func hud_label() -> String:
	return "%s — %s" % [get_date_string(), get_phase_name()]

# For save-slot text (same as HUD; no year)
func save_label() -> String:
	return hud_label()

# Advance Morning→Afternoon→Evening→(wrap) next day Morning
func advance_phase() -> void:
	if phase < Phase.EVENING:
		phase += 1
		phase_advanced.emit(phase)
		return
	# Wrap: Evening → next day Morning
	phase = Phase.MORNING
	_advance_day()
	phase_advanced.emit(phase)

# Optional external day jump (keeps week_reset behavior)
func advance_day(days: int = 1) -> void:
	if days == 0:
		return
	var step := (1 if days > 0 else -1)
	for _i in range(abs(days)):
		_step_one_day(step)
		day_advanced.emit(current_date)
		if weekday == 0:
			week_reset.emit(weekday)

# ─────────────────────────── Internals ───────────────────────────

func _advance_day() -> void:
	_step_one_day(1)
	day_advanced.emit(current_date)
	if weekday == 0:
		week_reset.emit(weekday)

func _step_one_day(delta: int) -> void:
	# weekday first
	weekday = (weekday + (1 if delta > 0 else -1) + 7) % 7

	var y := year
	var m := month
	var d := day

	if delta > 0:
		d += 1
		if d > _days_in_month(y, m):
			d = 1
			m += 1
			if m > 12:
				m = 1
				y += 1
	else:
		d -= 1
		if d < 1:
			m -= 1
			if m < 1:
				m = 12
				y -= 1
			d = _days_in_month(y, m)

	year = y; month = m; day = d

func _days_in_month(y: int, m: int) -> int:
	match m:
		1,3,5,7,8,10,12: return 31
		4,6,9,11:        return 30
		2:               return 29 if _is_leap(y) else 28
		_:               return 30

func _is_leap(y: int) -> bool:
	return (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0))

# 0=Monday..6=Sunday (Sakamoto variant)
static func _weekday_0_mon(y: int, m: int, d: int) -> int:
	var t: PackedInt32Array = [0,3,2,5,0,3,5,1,4,6,2,4]
	var y2 := y
	if m < 3: y2 -= 1
	var w0_sun := int(y2 + y2/4 - y2/100 + y2/400 + t[m-1] + d) % 7 # 0=Sun..6=Sat
	return (w0_sun + 6) % 7
