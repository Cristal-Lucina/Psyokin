extends Node
class_name MainEventSystem

## MainEventSystem (with hooks)
## - Linear/branched event list with title + hint
## - Public API: get_current_*(), set_current(), advance(), mark_step_completed()
## - Hooks: listens to Calendar day_advanced and can auto-advance on dates
## - Emits: event_changed(id)

signal event_changed(id: String)

const CAL_PATH := "/root/aCalendarSystem"

# Event record: { title: String, hint: String, next?: String }
var _events: Dictionary = {
	"track_selection": {
		"title": "Picking School Tracks",
		"hint":  "Meet with your counselor to choose your school track.",
		"next":  "garage"
	},
	"garage": {
		"title": "Resolve the Mystery of the Abandoned Garage",
		"hint":  "Search the old garage after classes. Bring a flashlight.",
		"next":  "wait_june14"
	},
	"wait_june14": {
		"title": "Wait for more information",
		"hint":  "Kill some time. Someone will text you around 6/14.",
		# when calendar reaches 6/14, we'll auto-advance to the step below:
		"next":  "post_june14"
	},
	# Safe placeholder so auto-advance has somewhere to land
	"post_june14": {
		"title": "Follow the new lead",
		"hint":  "You received a message. Check your phone and head out."
	}
}

var _current_id: String = "track_selection"

# Auto-advance rules (month/day are 1-based). Add more as your story grows.
# Each rule: {month:int, day:int, require_current:String, set:String}
var _date_triggers: Array = [
	{"month": 6, "day": 14, "require_current": "wait_june14", "set": "post_june14"},
]

func _ready() -> void:
	var cal := get_node_or_null(CAL_PATH)
	if cal:
		if cal.has_signal("day_advanced"):
			cal.connect("day_advanced", Callable(self, "_on_day_advanced"))
		if cal.has_signal("phase_advanced"):
			cal.connect("phase_advanced", Callable(self, "_on_phase_advanced"))

# --- basic API -----------------------------------------------------------------

func get_current_id() -> String:
	return _current_id

func get_current_title() -> String:
	var r := get_event(_current_id)
	return String(r.get("title", ""))

func get_current_hint() -> String:
	var r := get_event(_current_id)
	return String(r.get("hint", ""))

func list_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _events.keys():
		out.append(String(k))
	out.sort()
	return out

func get_event(id: String) -> Dictionary:
	var v: Variant = _events.get(id, {})
	return (v as Dictionary) if typeof(v) == TYPE_DICTIONARY else {}

func set_current(id: String) -> void:
	if id == _current_id: return
	if not _events.has(id): return
	_current_id = id
	event_changed.emit(_current_id)

func advance() -> void:
	var next_id := String(get_event(_current_id).get("next", ""))
	if next_id != "" and _events.has(next_id):
		set_current(next_id)

# “Complete a specific step” helper (useful if an action finishes a known step)
# If step_id is empty, just advance() the current step.
func mark_step_completed(step_id: String = "") -> void:
	if step_id == "" or step_id == _current_id:
		advance()
		return
	if not _events.has(step_id):
		return
	var nx := String((_events[step_id] as Dictionary).get("next", ""))
	if nx != "" and _events.has(nx):
		set_current(nx)

# --- calendar hooks ------------------------------------------------------------

func _on_day_advanced(date: Dictionary) -> void:
	# Expecting {year:int, month:int, day:int}
	var m: int = int(date.get("month", 0))
	var d: int = int(date.get("day", 0))
	_maybe_auto_advance_by_date(m, d)

# We don’t gate on phase today, but this lets you add phase-based rules later.
func _on_phase_advanced(_phase: int) -> void:
	pass

func _maybe_auto_advance_by_date(month: int, day: int) -> void:
	for t_v in _date_triggers:
		var t: Dictionary = t_v
		var req: String = String(t.get("require_current", ""))
		var set_to: String = String(t.get("set", ""))
		var tm: int = int(t.get("month", 0))
		var td: int = int(t.get("day", 0))
		if req != "" and set_to != "" and _current_id == req:
			if _is_on_or_after(month, day, tm, td) and _events.has(set_to):
				set_current(set_to)
				return  # one auto-advance per day tick

func _is_on_or_after(m: int, d: int, tm: int, td: int) -> bool:
	if m > tm: return true
	if m < tm: return false
	return d >= td

# --- save/load blob ------------------------------------------------------------

func get_save_blob() -> Dictionary:
	return {
		"current": _current_id,
		"events": _events.duplicate(true),
		"date_triggers": _date_triggers.duplicate(true),
	}

func apply_save_blob(blob: Dictionary) -> void:
	if typeof(blob) != TYPE_DICTIONARY: return
	var cur := String(blob.get("current", _current_id))
	if cur != "" and _events.has(cur):
		_current_id = cur
	var ev_v: Variant = blob.get("events", {})
	if typeof(ev_v) == TYPE_DICTIONARY:
		_events = (ev_v as Dictionary).duplicate(true)
	var tr_v: Variant = blob.get("date_triggers", _date_triggers)
	if typeof(tr_v) == TYPE_ARRAY:
		_date_triggers = (tr_v as Array).duplicate(true)
	event_changed.emit(_current_id)

func clear_all() -> void:
	_current_id = "track_selection"
	event_changed.emit(_current_id)
