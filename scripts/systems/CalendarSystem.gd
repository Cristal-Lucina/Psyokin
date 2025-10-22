## ═══════════════════════════════════════════════════════════════════════════
## CalendarSystem - In-Game Time & Date Manager
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Manages the in-game calendar (year, month, day, weekday) and time of day
##   (Morning/Afternoon/Evening phases). Handles time advancement and provides
##   blocking system for events that require user input before progressing.
##
## RESPONSIBILITIES:
##   • Calendar tracking (year, month, day, weekday)
##   • Time phase management (Morning, Afternoon, Evening)
##   • Time advancement (next phase, next day)
##   • Advance blocking system (prevents time skip during critical events)
##   • Weekday calculation (Monday=0 through Sunday=6)
##   • Formatted date/time labels for UI
##   • Save/load calendar state
##
## TIME PHASES:
##   0 = Morning
##   1 = Afternoon
##   2 = Evening
##   After Evening, advancing goes to next day's Morning
##
## WEEKDAY SYSTEM:
##   0 = Monday, 1 = Tuesday, ..., 6 = Sunday
##   Calculated using Zeller's congruence (accounts for leap years)
##
## BLOCKING SYSTEM:
##   Systems can block time advancement to force user interaction:
##   • DormSystem blocks on Saturday until reassignment plan is accepted
##   • Other systems can block for story events, choices, etc.
##   • Emits advance_blocked(reason) signal when blocked
##
## CONNECTED SYSTEMS (Autoloads):
##   • GameState - Save/load coordination, forwards advance_blocked signal
##   • DormSystem - Saturday triggers for weekly reassignments
##   • MainEventSystem - Story event scheduling
##   • Other time-sensitive systems
##
## KEY METHODS:
##   • advance_phase() - Move to next time phase (or next day if Evening)
##   • advance_day() - Skip to next day's Morning
##   • block_advance(reason: String) - Prevent time advancement
##   • unblock_advance() - Allow time advancement again
##   • hud_label() -> String - Formatted date/time for UI
##   • save_label() -> String - Save slot display format
##
## ═══════════════════════════════════════════════════════════════════════════

extends Node
class_name CalendarSystem

signal day_advanced(new_date: Dictionary)
signal phase_advanced(new_phase: int)
signal week_reset(new_weekday: int)
signal advance_blocked(reason: String)

enum Phase { MORNING, AFTERNOON, EVENING }

var year: int = 2025
var month: int = 5
var day: int = 10
## 0 = Monday … 6 = Sunday
var weekday: int = 0
var phase: int = Phase.MORNING

var current_date: Dictionary:
	get:
		return {"year": year, "month": month, "day": day}
	set(value):
		if typeof(value) == TYPE_DICTIONARY:
			var d: Dictionary = value
			year   = int(d.get("year",  year))
			month  = int(d.get("month", month))
			day    = int(d.get("day",   day))
			weekday = _weekday_0_mon(year, month, day)

var current_phase: int:
	get:
		return phase
	set(value):
		phase = clamp(int(value), Phase.MORNING, Phase.EVENING)

var current_weekday: int:
	get:
		return weekday
	set(value):
		weekday = clamp(int(value), 0, 6)

const WEEKDAY_NAMES: PackedStringArray = [
	"Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
]
const MONTH_NAMES: PackedStringArray = [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December"
]
const PHASE_NAMES: PackedStringArray = ["Morning", "Afternoon", "Evening"]

func get_weekday_name() -> String:
	return WEEKDAY_NAMES[clampi(weekday, 0, WEEKDAY_NAMES.size() - 1)]

func get_month_name(m: int = -1) -> String:
	var mm: int = (m if m >= 1 else month)
	return MONTH_NAMES[clampi(mm, 1, 12) - 1]

func get_phase_name() -> String:
	return PHASE_NAMES[clampi(phase, 0, PHASE_NAMES.size() - 1)]

func get_date_string() -> String:
	return "%s — %s %d" % [get_weekday_name(), get_month_name(), day]

func hud_label() -> String:
	return "%s — %s" % [get_date_string(), get_phase_name()]

func save_label() -> String:
	return hud_label()

# ─────────────────────────────────────────────────────────────
# Safe advance: block if Common Room has people waiting
# ─────────────────────────────────────────────────────────────
func _has_common_blockers() -> bool:
	var dorm: Node = get_node_or_null("/root/aDormSystem")
	if dorm and dorm.has_method("get_common"):
		var v: Variant = dorm.call("get_common")
		match typeof(v):
			TYPE_PACKED_STRING_ARRAY:
				return (v as PackedStringArray).size() > 0
			TYPE_ARRAY:
				return (v as Array).size() > 0
	return false

func _advance_block_msg() -> String:
	return "There are people waiting in the Common Room for room assignments."

func advance_phase() -> void:
	if _has_common_blockers():
		advance_blocked.emit(_advance_block_msg())
		return

	if phase < Phase.EVENING:
		phase += 1
		phase_advanced.emit(phase)
		return

	# roll to next day
	phase = Phase.MORNING
	_advance_day()
	phase_advanced.emit(phase)

func advance_day(days: int = 1) -> void:
	if days == 0:
		return
	if days > 0 and _has_common_blockers():
		advance_blocked.emit(_advance_block_msg())
		return

	var step: int = (1 if days > 0 else -1)
	for _i in range(abs(days)):
		_step_one_day(step)
		day_advanced.emit(current_date)
		_ping_dorms()
		if weekday == 0:
			week_reset.emit(weekday)

func _advance_day() -> void:
	_step_one_day(1)
	day_advanced.emit(current_date)
	_ping_dorms()
	if weekday == 0:
		week_reset.emit(weekday)

func _ping_dorms() -> void:
	var dorm: Node = get_node_or_null("/root/aDormSystem")
	if dorm and dorm.has_method("calendar_notify_weekday"):
		dorm.call("calendar_notify_weekday", get_weekday_name())

func _step_one_day(delta: int) -> void:
	weekday = (weekday + (1 if delta > 0 else -1) + 7) % 7

	var y: int = year
	var m: int = month
	var d: int = day

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

	year = y
	month = m
	day = d

func _days_in_month(y: int, m: int) -> int:
	match m:
		1,3,5,7,8,10,12: return 31
		4,6,9,11:        return 30
		2:               return 29 if _is_leap(y) else 28
		_:               return 30

func _is_leap(y: int) -> bool:
	return (y % 4 == 0 and (y % 100 != 0 or y % 400 == 0))

# 0=Monday..6=Sunday
static func _weekday_0_mon(y: int, m: int, d: int) -> int:
	var t: PackedInt32Array = [0,3,2,5,0,3,5,1,4,6,2,4]
	var y2: int = y
	if m < 3:
		y2 -= 1
	var y_div_4: int   = int(floor(float(y2) / 4.0))
	var y_div_100: int = int(floor(float(y2) / 100.0))
	var y_div_400: int = int(floor(float(y2) / 400.0))
	var w0_sun: int = int((y2 + y_div_4 - y_div_100 + y_div_400 + t[m - 1] + d) % 7) # 0=Sun..6=Sat
	return (w0_sun + 6) % 7
