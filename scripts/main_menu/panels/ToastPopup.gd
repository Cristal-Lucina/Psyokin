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
## ═══════════════════════════════════════════════════════════════════════════

signal closed

var _message: String = ""
var _ok_btn: Button = null

static func create(message: String) -> ToastPopup:
	var popup := ToastPopup.new()
	popup._message = message
	popup._build_ui()
	return popup

func _build_ui() -> void:
	custom_minimum_size = Vector2(400, 150)

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
	title.text = "Notice"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)

	# Message
	var msg_label := Label.new()
	msg_label.text = _message
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vbox.add_child(msg_label)

	# OK Button
	_ok_btn = Button.new()
	_ok_btn.text = "OK"
	_ok_btn.focus_mode = Control.FOCUS_ALL
	_ok_btn.custom_minimum_size = Vector2(100, 40)
	_ok_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_ok_btn)

	# Connect button
	_ok_btn.pressed.connect(_on_ok)

	# Auto-position and show
	call_deferred("_position_center")
	_ok_btn.call_deferred("grab_focus")

func _position_center() -> void:
	if get_parent() == null:
		return
	var parent_rect: Rect2 = get_parent().get_viewport_rect()
	position = (parent_rect.size - size) / 2

func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Handle Accept or Back (both close the toast)
	if event.is_action_pressed("menu_accept") or event.is_action_pressed("menu_back"):
		_on_ok()
		get_viewport().set_input_as_handled()

func _on_ok() -> void:
	print("[ToastPopup] OK pressed")
	closed.emit()
	hide()
