extends Panel
class_name ToastPopup

## ═══════════════════════════════════════════════════════════════════════════
## ToastPopup - Modal Toast/Notice Dialog
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Modal toast dialog that blocks all other input until user responds.
##   Supports gamepad and keyboard input (Accept/Back).
##
## USAGE:
##   var popup = ToastPopup.create("Something happened!")
##   parent.add_child(popup)
##   var result = await popup.confirmed
##   popup.queue_free()
##   if result:
##       # User pressed Accept
##   else:
##       # User pressed Cancel or Back
##
##   # With custom title:
##   var popup = ToastPopup.create("Details here", "Custom Title")
##
## ═══════════════════════════════════════════════════════════════════════════

signal confirmed(result: bool)

var _title: String = "Notice"
var _message: String = ""
var _accept_btn: Button = null
var _cancel_btn: Button = null

static func create(message: String, title: String = "Notice") -> ToastPopup:
	var popup := ToastPopup.new()
	popup._title = title
	popup._message = message
	popup._build_ui()
	return popup

func _build_ui() -> void:
	# Ensure popup processes even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS

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

	# Create margin container for padding
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.custom_minimum_size = Vector2(400, 0)  # Min width, height auto-sizes
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = _title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	# ScrollContainer for message (allows scrolling for long content)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	# Message
	var msg_label := Label.new()
	msg_label.text = _message
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.custom_minimum_size = Vector2(400, 0)  # Set width for wrapping
	vbox.add_child(msg_label)

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

	# Auto-position and show (deferred to allow size calculation)
	call_deferred("_finalize_size_and_position")
	_accept_btn.call_deferred("grab_focus")

func _finalize_size_and_position() -> void:
	# Force update to calculate proper size
	reset_size()
	_position_center()

func _position_center() -> void:
	if get_viewport() == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	position = (viewport_size - size) / 2

func _input(event: InputEvent) -> void:
	if not visible:
		print("[ToastPopup._input] Not visible, skipping input")
		return

	# Debug logging
	if event is InputEventJoypadButton and event.pressed:
		print("[ToastPopup._input] Joypad button %d pressed, visible=%s" % [event.button_index, visible])

	# Handle Accept
	if event.is_action_pressed("menu_accept"):
		var focused := get_viewport().gui_get_focus_owner()
		if focused == _accept_btn:
			_on_accept()
		elif focused == _cancel_btn:
			_on_cancel()
		else:
			# Default to accept if nothing focused
			_on_accept()
		get_viewport().set_input_as_handled()

	# Handle Back (cancel)
	elif event.is_action_pressed("menu_back"):
		_on_cancel()
		get_viewport().set_input_as_handled()

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
	print("[ToastPopup] Accept pressed")
	confirmed.emit(true)
	hide()

func _on_cancel() -> void:
	print("[ToastPopup] Cancel pressed")
	confirmed.emit(false)
	hide()
