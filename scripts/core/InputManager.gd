extends Node
## Centralized input manager for keyboard and controller support
## Handles input mapping, controller detection, and provides unified input API

signal controller_connected(device_id: int)
signal controller_disconnected(device_id: int)

# Input action names
const ACTION_MOVE_UP = "move_up"
const ACTION_MOVE_DOWN = "move_down"
const ACTION_MOVE_LEFT = "move_left"
const ACTION_MOVE_RIGHT = "move_right"
const ACTION_RUN = "run"
const ACTION_JUMP = "jump"
const ACTION_PULL = "pull"
const ACTION_PUSH = "push"
const ACTION_INTERACT = "interact"
const ACTION_MENU = "ui_menu"
const ACTION_PHONE = "ui_phone"
const ACTION_CONFIRM = "ui_accept"
const ACTION_CANCEL = "ui_cancel"

# Battle/Minigame actions
const ACTION_MINIGAME_1 = "minigame_1"  # Space
const ACTION_MINIGAME_2 = "minigame_2"  # Comma
const ACTION_MINIGAME_3 = "minigame_3"  # Period
const ACTION_MINIGAME_4 = "minigame_4"  # Slash

var controller_connected_flag: bool = false
var active_controller_id: int = -1

func _ready() -> void:
	# Register input actions if they don't exist
	_ensure_input_actions()

	# Check for connected controllers
	_check_controllers()

	# Connect to input device changes
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

func _ensure_input_actions() -> void:
	"""Ensure all required input actions are registered"""
	var actions = {
		ACTION_MOVE_UP: [KEY_W, KEY_UP, JOY_BUTTON_DPAD_UP],
		ACTION_MOVE_DOWN: [KEY_S, KEY_DOWN, JOY_BUTTON_DPAD_DOWN],
		ACTION_MOVE_LEFT: [KEY_A, KEY_LEFT, JOY_BUTTON_DPAD_LEFT],
		ACTION_MOVE_RIGHT: [KEY_D, KEY_RIGHT, JOY_BUTTON_DPAD_RIGHT],
		ACTION_RUN: [KEY_SHIFT, JOY_BUTTON_RIGHT_SHOULDER],
		ACTION_JUMP: [KEY_SPACE, JOY_BUTTON_A],
		ACTION_PULL: [KEY_COMMA, JOY_BUTTON_LEFT_SHOULDER],
		ACTION_PUSH: [KEY_PERIOD, JOY_BUTTON_RIGHT_SHOULDER],
		ACTION_INTERACT: [KEY_E, JOY_BUTTON_A],
		ACTION_MINIGAME_1: [KEY_SPACE, JOY_BUTTON_A],
		ACTION_MINIGAME_2: [KEY_COMMA, JOY_BUTTON_X],
		ACTION_MINIGAME_3: [KEY_PERIOD, JOY_BUTTON_B],
		ACTION_MINIGAME_4: [KEY_SLASH, JOY_BUTTON_Y],
	}

	for action_name in actions:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)

			# Add default bindings
			for key_or_button in actions[action_name]:
				if key_or_button is int:
					if key_or_button >= KEY_SPACE and key_or_button <= KEY_LAUNCHF:
						# Keyboard key
						var event = InputEventKey.new()
						event.keycode = key_or_button
						InputMap.action_add_event(action_name, event)
					else:
						# Controller button
						var event = InputEventJoypadButton.new()
						event.button_index = key_or_button
						InputMap.action_add_event(action_name, event)

	# Add analog stick support for movement
	_add_analog_stick_support()

func _add_analog_stick_support() -> void:
	"""Add left analog stick support for movement"""
	# Left stick horizontal
	var left_stick_left = InputEventJoypadMotion.new()
	left_stick_left.axis = JOY_AXIS_LEFT_X
	left_stick_left.axis_value = -1.0
	if InputMap.has_action(ACTION_MOVE_LEFT):
		InputMap.action_add_event(ACTION_MOVE_LEFT, left_stick_left)

	var left_stick_right = InputEventJoypadMotion.new()
	left_stick_right.axis = JOY_AXIS_LEFT_X
	left_stick_right.axis_value = 1.0
	if InputMap.has_action(ACTION_MOVE_RIGHT):
		InputMap.action_add_event(ACTION_MOVE_RIGHT, left_stick_right)

	# Left stick vertical
	var left_stick_up = InputEventJoypadMotion.new()
	left_stick_up.axis = JOY_AXIS_LEFT_Y
	left_stick_up.axis_value = -1.0
	if InputMap.has_action(ACTION_MOVE_UP):
		InputMap.action_add_event(ACTION_MOVE_UP, left_stick_up)

	var left_stick_down = InputEventJoypadMotion.new()
	left_stick_down.axis = JOY_AXIS_LEFT_Y
	left_stick_down.axis_value = 1.0
	if InputMap.has_action(ACTION_MOVE_DOWN):
		InputMap.action_add_event(ACTION_MOVE_DOWN, left_stick_down)

func _check_controllers() -> void:
	"""Check for connected controllers"""
	var devices = Input.get_connected_joypads()
	if devices.size() > 0:
		active_controller_id = devices[0]
		controller_connected_flag = true
		print("Controller detected: ", Input.get_joy_name(active_controller_id))

func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	"""Handle controller connection/disconnection"""
	if connected:
		active_controller_id = device_id
		controller_connected_flag = true
		controller_connected.emit(device_id)
		print("Controller connected: ", Input.get_joy_name(device_id))
	else:
		if device_id == active_controller_id:
			var devices = Input.get_connected_joypads()
			if devices.size() > 0:
				active_controller_id = devices[0]
			else:
				active_controller_id = -1
				controller_connected_flag = false
		controller_disconnected.emit(device_id)
		print("Controller disconnected")

# Input checking methods
func is_action_pressed(action: String) -> bool:
	"""Check if an action is currently pressed"""
	return Input.is_action_pressed(action)

func is_action_just_pressed(action: String) -> bool:
	"""Check if an action was just pressed this frame"""
	return Input.is_action_just_pressed(action)

func is_action_just_released(action: String) -> bool:
	"""Check if an action was just released this frame"""
	return Input.is_action_just_released(action)

func get_action_strength(action: String) -> float:
	"""Get the strength of an action (0.0 to 1.0, useful for analog inputs)"""
	return Input.get_action_strength(action)

func get_movement_vector() -> Vector2:
	"""Get normalized movement vector from input"""
	var vector = Vector2.ZERO
	vector.x = get_action_strength(ACTION_MOVE_RIGHT) - get_action_strength(ACTION_MOVE_LEFT)
	vector.y = get_action_strength(ACTION_MOVE_DOWN) - get_action_strength(ACTION_MOVE_UP)
	return vector.normalized() if vector.length() > 0 else vector

func is_controller_connected() -> bool:
	"""Check if any controller is connected"""
	return controller_connected_flag

func get_controller_name() -> String:
	"""Get the name of the active controller"""
	if active_controller_id >= 0:
		return Input.get_joy_name(active_controller_id)
	return ""

# Settings integration
func save_input_mapping() -> Dictionary:
	"""Save current input mapping to a dictionary"""
	var mapping = {}
	var actions = [
		ACTION_MOVE_UP, ACTION_MOVE_DOWN, ACTION_MOVE_LEFT, ACTION_MOVE_RIGHT,
		ACTION_RUN, ACTION_JUMP, ACTION_PULL, ACTION_PUSH, ACTION_INTERACT,
		ACTION_MENU, ACTION_PHONE, ACTION_CONFIRM, ACTION_CANCEL,
		ACTION_MINIGAME_1, ACTION_MINIGAME_2, ACTION_MINIGAME_3, ACTION_MINIGAME_4
	]

	for action in actions:
		if InputMap.has_action(action):
			var events = InputMap.action_get_events(action)
			var event_data = []
			for event in events:
				if event is InputEventKey:
					event_data.append({"type": "key", "keycode": event.keycode})
				elif event is InputEventJoypadButton:
					event_data.append({"type": "joy_button", "button": event.button_index})
				elif event is InputEventJoypadMotion:
					event_data.append({"type": "joy_motion", "axis": event.axis, "value": event.axis_value})
			mapping[action] = event_data

	return mapping

func load_input_mapping(mapping: Dictionary) -> void:
	"""Load input mapping from a dictionary"""
	for action in mapping:
		if InputMap.has_action(action):
			# Clear existing events
			InputMap.action_erase_events(action)

			# Add saved events
			for event_data in mapping[action]:
				match event_data.get("type"):
					"key":
						var event = InputEventKey.new()
						event.keycode = event_data.get("keycode", 0)
						InputMap.action_add_event(action, event)
					"joy_button":
						var event = InputEventJoypadButton.new()
						event.button_index = event_data.get("button", 0)
						InputMap.action_add_event(action, event)
					"joy_motion":
						var event = InputEventJoypadMotion.new()
						event.axis = event_data.get("axis", 0)
						event.axis_value = event_data.get("value", 0.0)
						InputMap.action_add_event(action, event)
