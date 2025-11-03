extends Panel
class_name ToastPopup

## ═══════════════════════════════════════════════════════════════════════════
## ToastPopup - Modal Toast/Notice Dialog
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Modal toast dialog that blocks all other input until user acknowledges.
##   Supports gamepad and keyboard input (Accept/Back to close).
##
## USAGE:
##   var popup = ToastPopup.create("Something happened!")
##   parent.add_child(popup)
##   await popup.closed
##   popup.queue_free()
##
##   # With custom title:
##   var popup = ToastPopup.create("Details here", "Custom Title")
##
## ═══════════════════════════════════════════════════════════════════════════

signal closed

var _title: String = "Notice"
var _message: String = ""
var _custom_size: Vector2 = Vector2(400, 160)
var _ok_btn: Button = null

static func create(message: String, title: String = "Notice", custom_size: Vector2 = Vector2(400, 160)) -> ToastPopup:
	var popup := ToastPopup.new()
	popup._title = title
	popup._message = message
	popup._custom_size = custom_size
	popup._build_ui()
	return popup

func _build_ui() -> void:
	custom_minimum_size = _custom_size

	# Ensure popup processes even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Center the popup using anchors
	set_anchors_preset(Control.PRESET_CENTER)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH

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

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	vbox.set_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 20
	vbox.offset_top = 20
	vbox.offset_right = -20
	vbox.offset_bottom = -20
	add_child(vbox)

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
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(msg_label)

	# OK Button
	_ok_btn = Button.new()
	_ok_btn.text = "OK"
	_ok_btn.focus_mode = Control.FOCUS_ALL
	_ok_btn.custom_minimum_size = Vector2(100, 40)
	_ok_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_ok_btn)

	# Connect button
	_ok_btn.pressed.connect(_on_ok)

	# Grab focus when ready
	_ok_btn.call_deferred("grab_focus")

func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Handle Accept or Back (both close the toast)
	if event.is_action_pressed("menu_accept") or event.is_action_pressed("menu_back"):
		_on_ok()
		get_viewport().set_input_as_handled()

	# Block all directional navigation to keep focus in popup
	elif event.is_action_pressed("move_up") or event.is_action_pressed("move_down") or \
	     event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
		get_viewport().set_input_as_handled()

func _on_ok() -> void:
	print("[ToastPopup] OK pressed")
	closed.emit()
	hide()
