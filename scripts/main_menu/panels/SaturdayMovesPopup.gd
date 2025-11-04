extends Panel
class_name SaturdayMovesPopup

## ═══════════════════════════════════════════════════════════════════════════
## SaturdayMovesPopup - Saturday Room Move Notifications
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Shows all room reassignments that executed on Saturday morning.
##   Displays who moved from which room to which room.
##
## DATA FORMAT (from DormSystem.saturday_applied_v2 signal):
##   new_layout: Dictionary { room_id: actor_id }
##   moves: Array of { "aid": String, "name": String, "from": String, "to": String }
##
## USAGE:
##   var popup = SaturdayMovesPopup.create(moves, pairs)
##   parent.add_child(popup)
##   await popup.closed
##   popup.queue_free()
##
## ═══════════════════════════════════════════════════════════════════════════

signal closed

var _moves: Array = []
var _reveal_pairs: Array = []  # New relationships revealed on Saturday

static func create(moves: Array, reveal_pairs: Array = []) -> SaturdayMovesPopup:
	var popup := SaturdayMovesPopup.new()
	popup._moves = moves
	popup._reveal_pairs = reveal_pairs
	popup._build_ui()
	return popup

func _build_ui() -> void:
	custom_minimum_size = Vector2(600, 450)

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
	title.text = "SATURDAY MORNING - ROOM REASSIGNMENTS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	# Divider
	var sep1 := HSeparator.new()
	vbox.add_child(sep1)

	# Scroll container for moves
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var content_vbox := VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_theme_constant_override("separation", 16)
	scroll.add_child(content_vbox)

	# Section 1: Room Moves
	var moves_title := RichTextLabel.new()
	moves_title.text = "[b]Room Moves Executed:[/b]"
	moves_title.bbcode_enabled = true
	moves_title.fit_content = true
	moves_title.scroll_active = false
	content_vbox.add_child(moves_title)

	if _moves.size() == 0:
		var no_moves := RichTextLabel.new()
		no_moves.text = "• No room reassignments this week."
		no_moves.fit_content = true
		no_moves.scroll_active = false
		content_vbox.add_child(no_moves)
	else:
		for move_v in _moves:
			if typeof(move_v) != TYPE_DICTIONARY:
				continue
			var move: Dictionary = move_v
			var member_name: String = String(move.get("name", "Unknown"))
			var from_room: String = String(move.get("from", ""))
			var to_room: String = String(move.get("to", ""))

			var move_label := RichTextLabel.new()
			if from_room != "" and to_room != "":
				move_label.text = "• [b]%s[/b] moved from [color=#2196F3]%s[/color] to [color=#4CAF50]%s[/color]" % [member_name, from_room, to_room]
			elif from_room != "":
				move_label.text = "• [b]%s[/b] moved from [color=#2196F3]%s[/color]" % [member_name, from_room]
			elif to_room != "":
				move_label.text = "• [b]%s[/b] moved to [color=#4CAF50]%s[/color]" % [member_name, to_room]
			else:
				move_label.text = "• [b]%s[/b] moved (details unavailable)" % member_name
			move_label.bbcode_enabled = true
			move_label.fit_content = true
			move_label.scroll_active = false
			content_vbox.add_child(move_label)

	# Section 2: New Neighbor Relationships (if any)
	if _reveal_pairs.size() > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 12)
		content_vbox.add_child(spacer)

		var reveals_title := RichTextLabel.new()
		reveals_title.text = "[b]New Neighbor Relationships:[/b]"
		reveals_title.bbcode_enabled = true
		reveals_title.fit_content = true
		reveals_title.scroll_active = false
		content_vbox.add_child(reveals_title)

		var reveals_note := RichTextLabel.new()
		reveals_note.text = "(These relationships are now 'Unknown Connection' until next Friday)"
		reveals_note.add_theme_font_size_override("normal_font_size", 11)
		reveals_note.fit_content = true
		reveals_note.scroll_active = false
		content_vbox.add_child(reveals_note)

		for pair_v in _reveal_pairs:
			if typeof(pair_v) != TYPE_DICTIONARY:
				continue
			var pair: Dictionary = pair_v
			var a_name: String = String(pair.get("a_name", ""))
			var b_name: String = String(pair.get("b_name", ""))

			var pair_label := RichTextLabel.new()
			pair_label.text = "• %s and %s are now neighbors" % [a_name, b_name]
			pair_label.fit_content = true
			pair_label.scroll_active = false
			content_vbox.add_child(pair_label)

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
	if event.is_action_pressed("menu_back"):
		closed.emit()
		hide()
		get_viewport().set_input_as_handled()
