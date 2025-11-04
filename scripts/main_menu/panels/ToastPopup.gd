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

var _title: String = ""
var _message: String = ""
var _accept_btn: Button = null
var _cancel_btn: Button = null

static func create(message: String, title: String = "") -> ToastPopup:
	print("[ToastPopup.create] Creating popup with message: %s" % message)
	var popup := ToastPopup.new()
	popup.process_mode = Node.PROCESS_MODE_ALWAYS  # Set BEFORE building UI
	popup._title = title
	popup._message = message
	popup._build_ui()
	print("[ToastPopup.create] Created popup, visible=%s, in_tree=%s" % [popup.visible, popup.is_inside_tree()])
	return popup

func _ready() -> void:
	print("[ToastPopup._ready] Popup ready, visible=%s, has_focus=%s, paused=%s" % [visible, has_focus(), get_tree().paused])

func _build_ui() -> void:
	var paused_str := "unknown" if not is_inside_tree() else str(get_tree().paused)
	print("[ToastPopup._build_ui] Building UI, in_tree=%s, paused=%s" % [is_inside_tree(), paused_str])
	# Ensure popup processes even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Block all input from passing through
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Set minimum size for the panel
	custom_minimum_size = Vector2(400, 200)

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

	# Create VBox with full-rect anchors and padding
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	vbox.set_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 20
	vbox.offset_top = 20
	vbox.offset_right = -20
	vbox.offset_bottom = -20
	add_child(vbox)

	# Title (only show if not empty)
	if _title != "":
		var title := Label.new()
		title.text = _title
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 18)
		vbox.add_child(title)

	# Message - centered horizontally and vertically
	var msg_label := Label.new()
	msg_label.text = _message
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	_accept_btn.process_mode = Node.PROCESS_MODE_ALWAYS  # Process even when paused
	hbox.add_child(_accept_btn)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.focus_mode = Control.FOCUS_ALL
	_cancel_btn.custom_minimum_size = Vector2(100, 40)
	_cancel_btn.process_mode = Node.PROCESS_MODE_ALWAYS  # Process even when paused
	hbox.add_child(_cancel_btn)

	# Connect buttons
	_accept_btn.pressed.connect(_on_accept)
	_cancel_btn.pressed.connect(_on_cancel)

	# Show the popup and focus accept button
	show()
	call_deferred("_finalize_size_and_position")
	call_deferred("_grab_focus_and_log")

func _grab_focus_and_log() -> void:
	_accept_btn.grab_focus()
	print("[ToastPopup] Accept button grabbed focus, has_focus=%s, visible=%s" % [_accept_btn.has_focus(), _accept_btn.visible])

func _finalize_size_and_position() -> void:
	# Force update to calculate proper size
	reset_size()
	# Wait one frame to ensure we're properly in the tree before positioning
	await get_tree().process_frame
	_position_center()

func _position_center() -> void:
	# Safety check: ensure we're in the scene tree with a valid parent
	if not is_inside_tree():
		print("[ToastPopup._position_center] Not in tree yet, deferring...")
		await get_tree().process_frame

	if get_parent() == null:
		print("[ToastPopup._position_center] No parent, cannot center")
		return

	# Get viewport size with error handling
	var viewport_size: Vector2 = Vector2.ZERO
	var viewport := get_viewport()

	if viewport == null:
		print("[ToastPopup._position_center] No viewport, cannot center")
		return

	# Try to get viewport rect size
	viewport_size = viewport.get_visible_rect().size

	if viewport_size == Vector2.ZERO:
		print("[ToastPopup._position_center] Viewport size is zero, cannot center")
		return

	# Center the popup
	position = (viewport_size - size) / 2
	print("[ToastPopup._position_center] Centered at %v (viewport: %v, size: %v)" % [position, viewport_size, size])

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
