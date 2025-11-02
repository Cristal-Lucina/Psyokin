extends Panel
class_name FridayRAMailPopup

## ═══════════════════════════════════════════════════════════════════════════
## FridayRAMailPopup - Friday Relationship Reveal Popup
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Shows newly discovered neighbor relationships revealed on Friday from
##   last Saturday's room assignments. Displays Bestie/Rival pairs that
##   have been neighbors for 2+ weeks.
##
## DATA FORMAT (from DormSystem.friday_reveals_ready signal):
##   Array of { "a": String, "b": String, "a_name": String, "b_name": String, "status": String }
##
## USAGE:
##   var popup = FridayRAMailPopup.create(pairs)
##   parent.add_child(popup)
##   await popup.closed
##   popup.queue_free()
##
## ═══════════════════════════════════════════════════════════════════════════

signal closed

var _pairs: Array = []

static func create(pairs: Array) -> FridayRAMailPopup:
	var popup := FridayRAMailPopup.new()
	popup._pairs = pairs
	popup._build_ui()
	return popup

func _build_ui() -> void:
	custom_minimum_size = Vector2(600, 400)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 16)
	vbox.set_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 20
	vbox.offset_top = 20
	vbox.offset_right = -20
	vbox.offset_bottom = -20
	add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "RA MAIL - FRIDAY NEIGHBOR REPORT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	# Divider
	var sep1 := HSeparator.new()
	vbox.add_child(sep1)

	# Intro text
	var intro := Label.new()
	if _pairs.size() == 0:
		intro.text = "No new neighbor relationships discovered this week."
	else:
		intro.text = "The following neighbor relationships have been revealed after being neighbors for 2+ weeks:"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(intro)

	# Scroll container for pairs
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var pairs_vbox := VBoxContainer.new()
	pairs_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pairs_vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(pairs_vbox)

	# Display each pair
	for pair_v in _pairs:
		if typeof(pair_v) != TYPE_DICTIONARY:
			continue
		var pair: Dictionary = pair_v
		var a_name: String = String(pair.get("a_name", ""))
		var b_name: String = String(pair.get("b_name", ""))
		var status: String = String(pair.get("status", "Neutral"))

		var pair_label := Label.new()
		var status_color: String = "#FFFFFF"
		if status == "Bestie":
			status_color = "#4CAF50"  # Green
		elif status == "Rival":
			status_color = "#F44336"  # Red
		else:
			status_color = "#FFC107"  # Amber for neutral

		pair_label.text = "• %s and %s are [color=%s][b]%s[/b][/color]" % [a_name, b_name, status_color, status]
		pair_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		pair_label.use_bbcode = true
		pair_label.bbcode_enabled = true
		pairs_vbox.add_child(pair_label)

	# Divider
	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Acknowledge"
	close_btn.focus_mode = Control.FOCUS_ALL
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(close_btn)

	close_btn.pressed.connect(func() -> void:
		closed.emit()
		hide()
	)

	# Auto-position and show
	call_deferred("_position_center")
	close_btn.call_deferred("grab_focus")

func _position_center() -> void:
	if get_parent() == null:
		return
	var parent_rect: Rect2 = get_parent().get_viewport_rect()
	position = (parent_rect.size - size) / 2

func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Close on CANCEL
	if event.is_action_pressed("ui_cancel"):
		closed.emit()
		hide()
		accept_event()
