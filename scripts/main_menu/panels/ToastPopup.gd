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

static func create(message: String, title: String = "Notice") -> ToastPopup:
	var popup := ToastPopup.new()
	popup._title = title
	popup._message = message
	popup._custom_size = custom_size
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

	# OK Button
	_ok_btn = Button.new()
	_ok_btn.text = "OK"
	_ok_btn.focus_mode = Control.FOCUS_ALL
	_ok_btn.custom_minimum_size = Vector2(100, 40)
	_ok_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(_ok_btn)

	# Connect button
	_ok_btn.pressed.connect(_on_ok)

	# Auto-position and show (deferred to allow size calculation)
	call_deferred("_finalize_size_and_position")
	_ok_btn.call_deferred("grab_focus")

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
		return

	# Handle Back to close (buttons don't handle Back by default)
	if event.is_action_pressed("menu_back"):
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
