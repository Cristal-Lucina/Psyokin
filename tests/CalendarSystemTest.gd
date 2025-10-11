extends Node

# This script creates a simple test UI to exercise the CalendarSystem. It adds
# a Label and a Button to the scene. The label displays the current date
# and phase using aCalendarSystem.get_date_string() and get_phase_name().
# Pressing the button calls aCalendarSystem.advance_phase() and updates
# the label. Register this script on a root node in a test scene or run it
# as the root of a standalone scene.  It assumes that aCalendarSystem is
# loaded as an autoload (singleton) and that aStatsSystem is also loaded
# for weekly resets.

var date_label : Label

func _ready() -> void:
	# Create and configure the date/phase label
	date_label = Label.new()
	date_label.position = Vector2(20, 20)
	date_label.text = _build_label_text()
	add_child(date_label)

	# Create and configure the advance button
	var advance_button = Button.new()
	advance_button.position = Vector2(20, 60)
	advance_button.text = "Advance Phase"
	# Connect the button's pressed signal using the new callable syntax (Godot 4)
	# "pressed" is a Signal on Button; we pass the method reference directly.
	advance_button.pressed.connect(self._on_advance_pressed)
	add_child(advance_button)

	# Optionally, listen to calendar signals to update the label automatically
	# Find the calendar singleton by searching the scene tree. Autoloads
	# appear as children of the root node under their autoload names. Check both
	# the preferred "aCalendarSystem" and the fallback "CalendarSystem".
	var cal = get_node_or_null("/root/aCalendarSystem")
	if cal != null:
		# Use the signal property to connect in Godot 4.  Check that the signal
		# exists before connecting.
		if cal.has_signal("day_advanced"):
			cal.day_advanced.connect(self._on_calendar_updated)
		if cal.has_signal("phase_advanced"):
			cal.phase_advanced.connect(self._on_calendar_updated)

func _on_advance_pressed() -> void:
	# Advance the phase via the calendar autoload and update the label
	# Attempt to get the calendar singleton and advance its phase.  Look up
	# by autoload name first and fall back to a non‑prefixed name if needed.
	var cal = get_node_or_null("/root/aCalendarSystem")
	if cal != null and cal.has_method("advance_phase"):
		cal.advance_phase()
	# Update label manually in case we didn't get a signal
	date_label.text = _build_label_text()

func _on_calendar_updated(_unused = null) -> void:
	# Update the label when the calendar signals that a day or phase advanced.
	# The signal may pass one or more arguments (e.g. the new phase index). We
	# accept an optional parameter to avoid errors about mismatched argument count.
	date_label.text = _build_label_text()

func _build_label_text() -> String:
	# Build the current date and phase string from the calendar system
	var date_str := "??"  # default placeholder
	var phase_str := "??"
	var cal = null
	# Try to find the calendar singleton in the scene tree. Autoloads are
	# children of the root node.  Check both "aCalendarSystem" and "CalendarSystem".
	cal = get_node_or_null("/root/aCalendarSystem")
	if cal != null:
		if cal.has_method("get_date_string"):
			date_str = cal.get_date_string()
		if cal.has_method("get_phase_name"):
			phase_str = cal.get_phase_name()
	return "%s - %s" % [date_str, phase_str]
