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

static func create(message: String) -> ConfirmationPopup:
	var popup := ConfirmationPopup.new()
	popup._message = message
	popup._build_ui()
	return popup

func _build_ui() -> void:
	custom_minimum_size = Vector2(400, 200)

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
	title.text = "Confirm"
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

	# Auto-position and show
	call_deferred("_position_center")
	_accept_btn.call_deferred("grab_focus")

func _position_center() -> void:
	if get_parent() == null:
		return
	var parent_rect: Rect2 = get_parent().get_viewport_rect()
	position = (parent_rect.size - size) / 2

func _input(event: InputEvent) -> void:
	if not visible:
		return

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

func _on_accept() -> void:
	print("[ConfirmationPopup] Accept pressed")
	confirmed.emit(true)
	hide()

func _on_cancel() -> void:
	print("[ConfirmationPopup] Cancel pressed")
	confirmed.emit(false)
	hide()
