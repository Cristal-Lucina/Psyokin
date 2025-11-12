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

# Input cooldown to prevent multiple rapid presses
var _input_cooldown: float = 0.0
const INPUT_COOLDOWN_TIME: float = 0.3  # 300ms cooldown between inputs

# Animation state
var _is_animating: bool = false
const FADE_DURATION: float = 0.2  # 200ms fade animation

static func create(moves: Array, reveal_pairs: Array = []) -> SaturdayMovesPopup:
	var popup := SaturdayMovesPopup.new()
	popup._moves = moves
	popup._reveal_pairs = reveal_pairs
	popup._build_ui()
	return popup

func _process(delta: float) -> void:
	# Update input cooldown timer
	if _input_cooldown > 0.0:
		_input_cooldown -= delta

func _build_ui() -> void:
	custom_minimum_size = Vector2(600, 450)

	# Core Vibe: Pill capsule panel with neon border
	var panel_style := aCoreVibeTheme.create_panel_style(
		aCoreVibeTheme.COLOR_CITRUS_YELLOW,       # Yellow border for attention
		aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
		aCoreVibeTheme.PANEL_OPACITY_FULL,        # Fully opaque
		aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
		aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
		aCoreVibeTheme.SHADOW_SIZE_LARGE          # 12px glow
	)
	add_theme_stylebox_override("panel", panel_style)

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
	# Core Vibe: Citrus Yellow title
	aCoreVibeTheme.style_label(title, aCoreVibeTheme.COLOR_CITRUS_YELLOW, 20)
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
	# Core Vibe: Milk White text
	moves_title.add_theme_color_override("default_color", aCoreVibeTheme.COLOR_MILK_WHITE)
	moves_title.add_theme_font_size_override("normal_font_size", 16)
	content_vbox.add_child(moves_title)

	if _moves.size() == 0:
		var no_moves := RichTextLabel.new()
		no_moves.text = "• No room reassignments this week."
		no_moves.fit_content = true
		no_moves.scroll_active = false
		no_moves.add_theme_color_override("default_color", aCoreVibeTheme.COLOR_MILK_WHITE)
		content_vbox.add_child(no_moves)
	else:
		# Core Vibe: Use Sky Cyan for "from" and Electric Lime for "to"
		var from_color = "#4DE9FF"  # Sky Cyan
		var to_color = "#C8FF3D"    # Electric Lime

		for move_v in _moves:
			if typeof(move_v) != TYPE_DICTIONARY:
				continue
			var move: Dictionary = move_v
			var member_name: String = String(move.get("name", "Unknown"))
			var from_room: String = String(move.get("from", ""))
			var to_room: String = String(move.get("to", ""))

			var move_label := RichTextLabel.new()
			if from_room != "" and to_room != "":
				move_label.text = "• [b]%s[/b] moved from [color=%s]%s[/color] to [color=%s]%s[/color]" % [member_name, from_color, from_room, to_color, to_room]
			elif from_room != "":
				move_label.text = "• [b]%s[/b] moved from [color=%s]%s[/color]" % [member_name, from_color, from_room]
			elif to_room != "":
				move_label.text = "• [b]%s[/b] moved to [color=%s]%s[/color]" % [member_name, to_color, to_room]
			else:
				move_label.text = "• [b]%s[/b] moved (details unavailable)" % member_name
			move_label.bbcode_enabled = true
			move_label.fit_content = true
			move_label.scroll_active = false
			move_label.add_theme_color_override("default_color", aCoreVibeTheme.COLOR_MILK_WHITE)
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
		# Core Vibe: Milk White text
		reveals_title.add_theme_color_override("default_color", aCoreVibeTheme.COLOR_MILK_WHITE)
		reveals_title.add_theme_font_size_override("normal_font_size", 16)
		content_vbox.add_child(reveals_title)

		var reveals_note := RichTextLabel.new()
		reveals_note.text = "(These relationships are now 'Unknown Connection' until next Friday)"
		reveals_note.fit_content = true
		reveals_note.scroll_active = false
		# Core Vibe: Dimmed Milk White for note
		reveals_note.add_theme_color_override("default_color", Color(aCoreVibeTheme.COLOR_MILK_WHITE.r, aCoreVibeTheme.COLOR_MILK_WHITE.g, aCoreVibeTheme.COLOR_MILK_WHITE.b, 0.7))
		reveals_note.add_theme_font_size_override("normal_font_size", 12)
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
			# Core Vibe: Plasma Teal for relationship text
			pair_label.add_theme_color_override("default_color", aCoreVibeTheme.COLOR_PLASMA_TEAL)
			content_vbox.add_child(pair_label)

	# Divider
	var sep2 := HSeparator.new()
	vbox.add_child(sep2)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "Acknowledge"
	close_btn.focus_mode = Control.FOCUS_ALL
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.custom_minimum_size = Vector2(160, 44)
	# Core Vibe: Citrus Yellow button
	aCoreVibeTheme.style_button(close_btn, aCoreVibeTheme.COLOR_CITRUS_YELLOW, aCoreVibeTheme.CORNER_RADIUS_LARGE)
	vbox.add_child(close_btn)

	close_btn.pressed.connect(func() -> void:
		if not _is_animating:
			_fade_out_and_close()
	)

	# Start hidden for fade in animation
	modulate = Color(1, 1, 1, 0)
	# Auto-position and show
	call_deferred("_position_center")
	close_btn.call_deferred("grab_focus")
	call_deferred("_fade_in")

func _position_center() -> void:
	if not is_inside_tree():
		await get_tree().process_frame

	if get_viewport() == null:
		print("[SaturdayMovesPopup._position_center] No viewport, cannot center")
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	position = (viewport_size - size) / 2
	print("[SaturdayMovesPopup._position_center] Centered at %v (viewport: %v, size: %v)" % [position, viewport_size, size])

func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Block input during animations or cooldown
	if _is_animating or _input_cooldown > 0.0:
		get_viewport().set_input_as_handled()
		return

	# Close on CANCEL or ACCEPT
	if event.is_action_pressed("menu_back") or event.is_action_pressed("menu_accept"):
		_input_cooldown = INPUT_COOLDOWN_TIME  # Start cooldown
		_fade_out_and_close()
		get_viewport().set_input_as_handled()

func _fade_in() -> void:
	"""Fade in the popup"""
	_is_animating = true
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), FADE_DURATION)
	await tween.finished
	_is_animating = false

func _fade_out_and_close() -> void:
	"""Fade out the popup and close"""
	_is_animating = true
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), FADE_DURATION)
	await tween.finished
	_is_animating = false
	closed.emit()
	hide()
