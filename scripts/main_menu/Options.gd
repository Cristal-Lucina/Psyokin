extends Control

## Options menu - accessible from Title screen and System panel
## Displays game settings including controls configuration with remapping

@onready var _close_btn: Button = %CloseBtn
@onready var _controls_panel: Control = %ControlsContent

# Remapping state
var _action_buttons: Array[Array] = []  # Array of [keyboard_button, controller_button]
var _waiting_for_input: Button = null
var _waiting_action: String = ""
var _waiting_is_controller: bool = false

func _ready() -> void:
	print("[Options] _ready() called")
	print("[Options] Close button: ", _close_btn)
	print("[Options] Controls panel: ", _controls_panel)

	if _close_btn:
		_close_btn.pressed.connect(_on_close_pressed)
		print("[Options] Close button connected")
	else:
		push_error("[Options] Close button not found!")

	if _controls_panel:
		# Create the controls UI
		_build_controls_ui()
	else:
		push_error("[Options] Controls panel not found!")

func _on_close_pressed() -> void:
	queue_free()

func _build_controls_ui() -> void:
	"""Build the controls configuration UI"""
	print("[Options] Building controls UI...")

	# Clear existing content
	for child in _controls_panel.get_children():
		child.queue_free()

	# Main scroll container - use proper container sizing, not anchors
	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_controls_panel.add_child(scroll)
	print("[Options] Added scroll container")

	var main_vbox = VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(main_vbox)

	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 10)
	main_vbox.add_child(spacer1)

	# Controller status
	var status_hbox = HBoxContainer.new()
	status_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(status_hbox)

	var status_label = Label.new()
	if aInputManager.is_controller_connected():
		status_label.text = "Controller: " + aInputManager.get_controller_name()
		status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	else:
		status_label.text = "Controller: Not Connected"
		status_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.3))
	status_hbox.add_child(status_label)

	# Spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	main_vbox.add_child(spacer2)

	# Grid header
	var header_grid = GridContainer.new()
	header_grid.columns = 3
	header_grid.add_theme_constant_override("h_separation", 20)
	main_vbox.add_child(header_grid)

	var header_action = Label.new()
	header_action.text = "Action"
	header_action.add_theme_font_size_override("font_size", 16)
	header_action.custom_minimum_size.x = 180
	header_grid.add_child(header_action)

	var header_keyboard = Label.new()
	header_keyboard.text = "Keyboard"
	header_keyboard.add_theme_font_size_override("font_size", 16)
	header_keyboard.custom_minimum_size.x = 180
	header_grid.add_child(header_keyboard)

	var header_controller = Label.new()
	header_controller.text = "Controller"
	header_controller.add_theme_font_size_override("font_size", 16)
	header_controller.custom_minimum_size.x = 180
	header_grid.add_child(header_controller)

	# Controls grid
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 8)
	main_vbox.add_child(grid)

	# Action definitions
	var actions = [
		{"name": "move_up", "display": "Move Up"},
		{"name": "move_down", "display": "Move Down"},
		{"name": "move_left", "display": "Move Left"},
		{"name": "move_right", "display": "Move Right"},
		{"name": "run", "display": "Run/Sprint"},
		{"name": "jump", "display": "Jump/Confirm"},
		{"name": "pull", "display": "Pull"},
		{"name": "push", "display": "Push"},
		{"name": "minigame_1", "display": "Minigame 1"},
		{"name": "minigame_2", "display": "Minigame 2"},
		{"name": "minigame_3", "display": "Minigame 3"},
		{"name": "minigame_4", "display": "Minigame 4"},
		{"name": "ui_menu", "display": "Menu"},
		{"name": "ui_phone", "display": "Phone"},
	]

	# Create rows for each action
	for action_def in actions:
		var action_name = action_def["name"]
		var display_name = action_def["display"]

		# Action label
		var label = Label.new()
		label.text = display_name
		label.custom_minimum_size.x = 180
		grid.add_child(label)

		# Keyboard binding button (clickable for remapping)
		var kb_btn = Button.new()
		kb_btn.text = _get_keyboard_binding_text(action_name)
		kb_btn.custom_minimum_size = Vector2(180, 30)
		kb_btn.pressed.connect(_on_remap_pressed.bind(action_name, kb_btn, false))
		grid.add_child(kb_btn)

		# Controller binding button (clickable for remapping)
		var ctrl_btn = Button.new()
		ctrl_btn.text = _get_controller_binding_text(action_name)
		ctrl_btn.custom_minimum_size = Vector2(180, 30)
		ctrl_btn.pressed.connect(_on_remap_pressed.bind(action_name, ctrl_btn, true))
		grid.add_child(ctrl_btn)

		_action_buttons.append([kb_btn, ctrl_btn])

	# Spacer
	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 20)
	main_vbox.add_child(spacer3)

	# Reset button
	var reset_hbox = HBoxContainer.new()
	reset_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(reset_hbox)

	var reset_btn = Button.new()
	reset_btn.text = "Reset to Defaults"
	reset_btn.custom_minimum_size = Vector2(200, 40)
	reset_btn.pressed.connect(_on_reset_pressed)
	reset_hbox.add_child(reset_btn)

	# Spacer
	var spacer4 = Control.new()
	spacer4.custom_minimum_size = Vector2(0, 10)
	main_vbox.add_child(spacer4)

	# Info text
	var info_label = Label.new()
	info_label.text = "Click any button to remap. Press ESC to cancel remapping."
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size.x = 540
	var info_center = CenterContainer.new()
	info_center.add_child(info_label)
	main_vbox.add_child(info_center)

	print("[Options] Controls UI built successfully!")

func _on_remap_pressed(action_name: String, button: Button, is_controller: bool) -> void:
	"""Start waiting for input to remap an action"""
	if _waiting_for_input != null:
		# Cancel previous remap
		_waiting_for_input.text = _get_current_binding_text(_waiting_action, _waiting_is_controller)

	_waiting_for_input = button
	_waiting_action = action_name
	_waiting_is_controller = is_controller

	if is_controller:
		button.text = "Press controller button..."
	else:
		button.text = "Press any key..."

	button.grab_focus()

func _get_current_binding_text(action_name: String, is_controller: bool) -> String:
	"""Get the current binding text for an action"""
	if is_controller:
		return _get_controller_binding_text(action_name)
	else:
		return _get_keyboard_binding_text(action_name)

func _input(event: InputEvent) -> void:
	if _waiting_for_input == null:
		return

	# Allow ESC to cancel remapping
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		_waiting_for_input.text = _get_current_binding_text(_waiting_action, _waiting_is_controller)
		_waiting_for_input = null
		_waiting_action = ""
		_waiting_is_controller = false
		get_viewport().set_input_as_handled()
		return

	var should_remap = false
	var new_event: InputEvent = null

	if _waiting_is_controller:
		# Waiting for controller input
		if event is InputEventJoypadButton and event.pressed:
			new_event = event
			should_remap = true
		elif event is InputEventJoypadMotion and abs(event.axis_value) > 0.5:
			new_event = event
			should_remap = true
	else:
		# Waiting for keyboard input (but not ESC since we handle that above)
		if event is InputEventKey and event.pressed and event.keycode != KEY_ESCAPE:
			new_event = event
			should_remap = true

	if should_remap and new_event != null:
		_remap_action(_waiting_action, new_event, _waiting_is_controller)
		_waiting_for_input = null
		_waiting_action = ""
		_waiting_is_controller = false
		get_viewport().set_input_as_handled()

func _remap_action(action_name: String, new_event: InputEvent, is_controller: bool) -> void:
	"""Remap an action to a new input event"""
	if not InputMap.has_action(action_name):
		push_error("[Options] Action not found: " + action_name)
		return

	# Remove old events of the same type
	var events = InputMap.action_get_events(action_name)
	for event in events:
		if is_controller and (event is InputEventJoypadButton or event is InputEventJoypadMotion):
			InputMap.action_erase_event(action_name, event)
		elif not is_controller and event is InputEventKey:
			InputMap.action_erase_event(action_name, event)

	# Add new event
	InputMap.action_add_event(action_name, new_event)

	# Save to settings
	aSettings.save_input_mapping()

	# Refresh all button displays
	_refresh_bindings()

	print("[Options] Remapped %s to %s" % [action_name, new_event])

func _refresh_bindings() -> void:
	"""Update all binding button labels"""
	for buttons in _action_buttons:
		var kb_btn = buttons[0] as Button
		var ctrl_btn = buttons[1] as Button

		# Find which action this button pair represents
		var action_idx = _action_buttons.find(buttons)
		if action_idx >= 0:
			var actions = [
				"move_up", "move_down", "move_left", "move_right",
				"run", "jump", "pull", "push",
				"minigame_1", "minigame_2", "minigame_3", "minigame_4",
				"ui_menu", "ui_phone"
			]
			if action_idx < actions.size():
				var action_name = actions[action_idx]
				kb_btn.text = _get_keyboard_binding_text(action_name)
				ctrl_btn.text = _get_controller_binding_text(action_name)

func _on_reset_pressed() -> void:
	"""Reset all controls to defaults"""
	# Clear all actions
	var actions = [
		"move_up", "move_down", "move_left", "move_right",
		"run", "jump", "pull", "push",
		"minigame_1", "minigame_2", "minigame_3", "minigame_4",
		"ui_menu", "ui_phone"
	]

	for action_name in actions:
		if InputMap.has_action(action_name):
			InputMap.action_erase_events(action_name)

	# Re-initialize defaults from InputManager
	aInputManager._ensure_input_actions()

	# Save to settings
	aSettings.save_input_mapping()

	# Refresh display
	_refresh_bindings()

	print("[Options] Reset all controls to defaults")

func _get_keyboard_binding_text(action_name: String) -> String:
	"""Get keyboard binding text for an action"""
	if not InputMap.has_action(action_name):
		return "None"

	var events = InputMap.action_get_events(action_name)
	for event in events:
		if event is InputEventKey:
			return OS.get_keycode_string(event.keycode)

	return "None"

func _get_controller_binding_text(action_name: String) -> String:
	"""Get controller binding text for an action"""
	if not InputMap.has_action(action_name):
		return "None"

	var events = InputMap.action_get_events(action_name)
	for event in events:
		if event is InputEventJoypadButton:
			return _get_joypad_button_name(event.button_index)
		elif event is InputEventJoypadMotion:
			return _get_joypad_axis_name(event.axis, event.axis_value)

	return "None"

func _get_joypad_button_name(button_index: int) -> String:
	"""Get human-readable name for joypad button"""
	match button_index:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_LEFT_STICK: return "L3"
		JOY_BUTTON_RIGHT_STICK: return "R3"
		JOY_BUTTON_DPAD_UP: return "D-Up"
		JOY_BUTTON_DPAD_DOWN: return "D-Down"
		JOY_BUTTON_DPAD_LEFT: return "D-Left"
		JOY_BUTTON_DPAD_RIGHT: return "D-Right"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_BACK: return "Select"
		_: return "Btn %d" % button_index

func _get_joypad_axis_name(axis: int, value: float) -> String:
	"""Get human-readable name for joypad axis"""
	match axis:
		JOY_AXIS_LEFT_X: return "LS " + ("→" if value > 0 else "←")
		JOY_AXIS_LEFT_Y: return "LS " + ("↓" if value > 0 else "↑")
		JOY_AXIS_RIGHT_X: return "RS " + ("→" if value > 0 else "←")
		JOY_AXIS_RIGHT_Y: return "RS " + ("↓" if value > 0 else "↑")
		JOY_AXIS_TRIGGER_LEFT: return "LT"
		JOY_AXIS_TRIGGER_RIGHT: return "RT"
		_: return "Axis %d" % axis
