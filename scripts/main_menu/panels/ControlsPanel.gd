extends Control

## ControlsPanel - UI for viewing and remapping controls
## Shows keyboard and controller bindings, allows remapping

var _action_labels: Array = []
var _action_buttons: Array[Array] = []  # Array of [keyboard_button, controller_button]
var _waiting_for_input: Button = null
var _waiting_action: String = ""
var _waiting_is_controller: bool = false

const ACTIONS = [
	{"name": "move_up", "display": "Move Up"},
	{"name": "move_down", "display": "Move Down"},
	{"name": "move_left", "display": "Move Left"},
	{"name": "move_right", "display": "Move Right"},
	{"name": "run", "display": "Run/Sprint"},
	{"name": "jump", "display": "Jump/Confirm"},
	{"name": "pull", "display": "Pull"},
	{"name": "push", "display": "Push"},
	{"name": "minigame_1", "display": "Minigame Button 1"},
	{"name": "minigame_2", "display": "Minigame Button 2"},
	{"name": "minigame_3", "display": "Minigame Button 3"},
	{"name": "minigame_4", "display": "Minigame Button 4"},
	{"name": "ui_menu", "display": "Open Menu"},
	{"name": "ui_phone", "display": "Open Phone"},
]

func _ready() -> void:
	_build_ui()
	_refresh_bindings()

func _build_ui() -> void:
	# Main container
	var scroll = ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	add_child(scroll)

	var main_vbox = VBoxContainer.new()
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(main_vbox)

	# Title
	var title = Label.new()
	title.text = "Controls Configuration"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	main_vbox.add_child(title)

	# Spacer
	var spacer1 = Control.new()
	spacer1.custom_minimum_size = Vector2(0, 20)
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
	header_action.add_theme_font_size_override("font_size", 18)
	header_action.custom_minimum_size.x = 200
	header_grid.add_child(header_action)

	var header_keyboard = Label.new()
	header_keyboard.text = "Keyboard"
	header_keyboard.add_theme_font_size_override("font_size", 18)
	header_keyboard.custom_minimum_size.x = 200
	header_grid.add_child(header_keyboard)

	var header_controller = Label.new()
	header_controller.text = "Controller"
	header_controller.add_theme_font_size_override("font_size", 18)
	header_controller.custom_minimum_size.x = 200
	header_grid.add_child(header_controller)

	# Controls grid
	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 10)
	main_vbox.add_child(grid)

	# Create rows for each action
	for action_def in ACTIONS:
		var action_name = action_def["name"]
		var display_name = action_def["display"]

		# Action label
		var label = Label.new()
		label.text = display_name
		label.custom_minimum_size.x = 200
		grid.add_child(label)
		_action_labels.append(label)

		# Keyboard binding button
		var kb_btn = Button.new()
		kb_btn.text = "..."
		kb_btn.custom_minimum_size = Vector2(200, 30)
		kb_btn.pressed.connect(_on_remap_pressed.bind(action_name, kb_btn, false))
		grid.add_child(kb_btn)

		# Controller binding button
		var ctrl_btn = Button.new()
		ctrl_btn.text = "..."
		ctrl_btn.custom_minimum_size = Vector2(200, 30)
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

func _refresh_bindings() -> void:
	"""Update all binding button labels"""
	for i in range(ACTIONS.size()):
		var action_name = ACTIONS[i]["name"]
		var buttons = _action_buttons[i]

		if not InputMap.has_action(action_name):
			buttons[0].text = "Not Found"
			buttons[1].text = "Not Found"
			continue

		var events = InputMap.action_get_events(action_name)
		var kb_text = "None"
		var ctrl_text = "None"

		for event in events:
			if event is InputEventKey:
				kb_text = OS.get_keycode_string(event.keycode)
			elif event is InputEventJoypadButton:
				ctrl_text = _get_joypad_button_name(event.button_index)
			elif event is InputEventJoypadMotion:
				ctrl_text = _get_joypad_axis_name(event.axis, event.axis_value)

		buttons[0].text = kb_text
		buttons[1].text = ctrl_text

func _get_joypad_button_name(button_index: int) -> String:
	"""Get human-readable name for joypad button"""
	match button_index:
		JOY_BUTTON_A: return "A Button"
		JOY_BUTTON_B: return "B Button"
		JOY_BUTTON_X: return "X Button"
		JOY_BUTTON_Y: return "Y Button"
		JOY_BUTTON_LEFT_SHOULDER: return "L Shoulder"
		JOY_BUTTON_RIGHT_SHOULDER: return "R Shoulder"
		JOY_BUTTON_LEFT_STICK: return "L Stick Press"
		JOY_BUTTON_RIGHT_STICK: return "R Stick Press"
		JOY_BUTTON_DPAD_UP: return "D-Pad Up"
		JOY_BUTTON_DPAD_DOWN: return "D-Pad Down"
		JOY_BUTTON_DPAD_LEFT: return "D-Pad Left"
		JOY_BUTTON_DPAD_RIGHT: return "D-Pad Right"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_BACK: return "Select"
		_: return "Button %d" % button_index

func _get_joypad_axis_name(axis: int, value: float) -> String:
	"""Get human-readable name for joypad axis"""
	var direction = "+" if value > 0 else "-"
	match axis:
		JOY_AXIS_LEFT_X: return "L-Stick " + ("Right" if value > 0 else "Left")
		JOY_AXIS_LEFT_Y: return "L-Stick " + ("Down" if value > 0 else "Up")
		JOY_AXIS_RIGHT_X: return "R-Stick " + ("Right" if value > 0 else "Left")
		JOY_AXIS_RIGHT_Y: return "R-Stick " + ("Down" if value > 0 else "Up")
		JOY_AXIS_TRIGGER_LEFT: return "L Trigger"
		JOY_AXIS_TRIGGER_RIGHT: return "R Trigger"
		_: return "Axis %d%s" % [axis, direction]

func _on_remap_pressed(action_name: String, button: Button, is_controller: bool) -> void:
	"""Start waiting for input to remap an action"""
	if _waiting_for_input != null:
		# Cancel previous remap
		_waiting_for_input.text = _get_current_binding_text(_waiting_action, _waiting_is_controller)

	_waiting_for_input = button
	_waiting_action = action_name
	_waiting_is_controller = is_controller

	if is_controller:
		button.text = "Press any button..."
	else:
		button.text = "Press any key..."

	# Set focus to this button
	button.grab_focus()

func _get_current_binding_text(action_name: String, is_controller: bool) -> String:
	"""Get the current binding text for an action"""
	if not InputMap.has_action(action_name):
		return "Not Found"

	var events = InputMap.action_get_events(action_name)
	for event in events:
		if is_controller and (event is InputEventJoypadButton or event is InputEventJoypadMotion):
			if event is InputEventJoypadButton:
				return _get_joypad_button_name(event.button_index)
			else:
				return _get_joypad_axis_name(event.axis, event.axis_value)
		elif not is_controller and event is InputEventKey:
			return OS.get_keycode_string(event.keycode)

	return "None"

func _input(event: InputEvent) -> void:
	if _waiting_for_input == null:
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
		# Waiting for keyboard input
		if event is InputEventKey and event.pressed:
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
		push_error("Action not found: " + action_name)
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

	# Refresh display
	_refresh_bindings()

	print("[ControlsPanel] Remapped %s to %s" % [action_name, new_event])

func _on_reset_pressed() -> void:
	"""Reset all controls to defaults"""
	# Clear all actions
	for action_def in ACTIONS:
		var action_name = action_def["name"]
		if InputMap.has_action(action_name):
			InputMap.action_erase_events(action_name)

	# Re-initialize defaults from InputManager
	aInputManager._ensure_input_actions()

	# Save to settings
	aSettings.save_input_mapping()

	# Refresh display
	_refresh_bindings()

	print("[ControlsPanel] Reset all controls to defaults")
