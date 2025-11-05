extends Panel
class_name ConfirmationPopup

## ═══════════════════════════════════════════════════════════════════════════
## ConfirmationPopup - Modal Confirmation Dialog
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Modal confirmation dialog that blocks all other input until user responds.
##   Supports gamepad and keyboard input (Accept/Back).
##
## USAGE:
##   var popup = ConfirmationPopup.create("Are you sure?")
##   parent.add_child(popup)
##   var result = await popup.confirmed
##   popup.queue_free()
##   if result:
##       # User pressed Accept
##   else:
##       # User pressed Cancel or Back
##
## ═══════════════════════════════════════════════════════════════════════════

signal confirmed(result: bool)

var _message: String = ""
var _accept_btn: Button = null
var _cancel_btn: Button = null

# Input cooldown to prevent multiple rapid presses
var _input_cooldown: float = 0.0
const INPUT_COOLDOWN_TIME: float = 0.3  # 300ms cooldown between inputs

# Animation state
var _is_animating: bool = false
const FADE_DURATION: float = 0.2  # 200ms fade animation

static func create(message: String) -> ConfirmationPopup:
	var popup := ConfirmationPopup.new()
	popup._message = message
	popup._build_ui()
	return popup

func _process(delta: float) -> void:
	# Update input cooldown timer
	if _input_cooldown > 0.0:
		_input_cooldown -= delta

func _build_ui() -> void:
	custom_minimum_size = Vector2(600, 300)

	# Add solid background (no transparency)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 1.0)  # Dark gray, fully opaque
	style.border_color = Color(1.0, 0.7, 0.75, 1.0)  # Pink border
	style.set_border_width_all(2)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "Confirm"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	# Message with ScrollContainer for long content
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(560, 180)  # Min height for scroll area
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)

	var msg_label := Label.new()
	msg_label.text = _message
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.custom_minimum_size = Vector2(560, 0)
	scroll.add_child(msg_label)

	# Buttons
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(hbox)

	_accept_btn = Button.new()
	_accept_btn.text = "Accept"
	_accept_btn.focus_mode = Control.FOCUS_ALL
	_accept_btn.custom_minimum_size = Vector2(100, 40)
	hbox.add_child(_accept_btn)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.focus_mode = Control.FOCUS_ALL
	_cancel_btn.custom_minimum_size = Vector2(100, 40)
	hbox.add_child(_cancel_btn)

	# Connect buttons
	_accept_btn.pressed.connect(_on_accept)
	_cancel_btn.pressed.connect(_on_cancel)

	# Start hidden for fade in animation
	modulate = Color(1, 1, 1, 0)
	show()  # Make popup visible (but transparent for fade in)
	# Auto-position and show
	call_deferred("_position_center")
	_accept_btn.call_deferred("grab_focus")
	call_deferred("_fade_in")

func _position_center() -> void:
	if not is_inside_tree():
		await get_tree().process_frame

	if get_viewport() == null:
		print("[ConfirmationPopup._position_center] No viewport, cannot center")
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	position = (viewport_size - size) / 2
	print("[ConfirmationPopup._position_center] Centered at %v (viewport: %v, size: %v)" % [position, viewport_size, size])

func _input(event: InputEvent) -> void:
	if not visible:
		print("[ConfirmationPopup._input] Not visible, skipping input")
		return

	# Block input during animations or cooldown
	if _is_animating or _input_cooldown > 0.0:
		print("[ConfirmationPopup._input] Blocked by animation or cooldown")
		get_viewport().set_input_as_handled()
		return

	# Debug logging
	if event is InputEventJoypadButton and event.pressed:
		print("[ConfirmationPopup._input] Joypad button %d pressed" % event.button_index)

	# Handle Accept
	if event.is_action_pressed("menu_accept"):
		_input_cooldown = INPUT_COOLDOWN_TIME  # Start cooldown
		var focused := get_viewport().gui_get_focus_owner()
		if focused == _accept_btn:
			_on_accept()
		elif focused == _cancel_btn:
			_on_cancel()
		else:
			# Default to accept if nothing focused
			_on_accept()
		# Note: input handling is done in _on_accept/_on_cancel

	# Handle Back (cancel)
	elif event.is_action_pressed("menu_back"):
		_input_cooldown = INPUT_COOLDOWN_TIME  # Start cooldown
		_on_cancel()
		# Note: input handling is done in _on_cancel

	# Handle left/right navigation between buttons
	elif event.is_action_pressed("move_left"):
		_accept_btn.grab_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		_cancel_btn.grab_focus()
		get_viewport().set_input_as_handled()

	# Block up/down navigation to keep focus in popup
	elif event.is_action_pressed("move_up"):
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		get_viewport().set_input_as_handled()

func _on_accept() -> void:
	if _is_animating:
		return
	print("[ConfirmationPopup] Accept pressed")
	# Mark input as handled before emitting signal (in case signal triggers scene change)
	if is_inside_tree() and get_viewport():
		get_viewport().set_input_as_handled()
	_fade_out_and_close(true)

func _on_cancel() -> void:
	if _is_animating:
		return
	print("[ConfirmationPopup] Cancel pressed")
	# Mark input as handled before emitting signal (in case signal triggers scene change)
	if is_inside_tree() and get_viewport():
		get_viewport().set_input_as_handled()
	_fade_out_and_close(false)

func _fade_in() -> void:
	"""Fade in the popup"""
	_is_animating = true
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), FADE_DURATION)
	await tween.finished
	_is_animating = false

func _fade_out_and_close(result: bool) -> void:
	"""Fade out the popup and emit result"""
	_is_animating = true
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 0), FADE_DURATION)
	await tween.finished
	_is_animating = false
	confirmed.emit(result)
	hide()
