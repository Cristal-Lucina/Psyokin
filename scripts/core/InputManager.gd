extends Node
## Centralized input manager for keyboard and controller support
## Handles input mapping, controller detection, and provides unified input API

signal controller_connected(device_id: int)
signal controller_disconnected(device_id: int)

# Movement actions (shared between Overworld and Battle)
const ACTION_MOVE_UP = "move_up"
const ACTION_MOVE_DOWN = "move_down"
const ACTION_MOVE_LEFT = "move_left"
const ACTION_MOVE_RIGHT = "move_right"

# Overworld actions
const ACTION_ACTION = "action"  # A button - accept/push/pull/interact
const ACTION_JUMP = "jump"      # Y button
const ACTION_RUN = "run"        # X button
const ACTION_PHONE = "phone"    # B button
const ACTION_MENU = "menu"      # Start button
const ACTION_SAVE = "save"      # Select button

# Battle actions
const ACTION_ATTACK = "battle_attack"   # B button
const ACTION_SKILL = "battle_skill"     # Y button
const ACTION_CAPTURE = "battle_capture" # A button
const ACTION_DEFEND = "battle_defend"   # X button
const ACTION_BURST = "battle_burst"     # L bumper
const ACTION_BATTLE_RUN = "battle_run"  # R bumper
const ACTION_ITEMS = "battle_items"     # Start button
const ACTION_STATUS = "battle_status"   # Select button

# Menu actions
const ACTION_ACCEPT = "menu_accept"  # A button
const ACTION_BACK = "menu_back"      # B button

# Legacy action names (for compatibility)
const ACTION_PULL = "action"  # Now maps to ACTION_ACTION
const ACTION_PUSH = "action"  # Now maps to ACTION_ACTION
const ACTION_INTERACT = "action"  # Now maps to ACTION_ACTION
const ACTION_CONFIRM = "action"  # Now maps to ACTION_ACTION
const ACTION_MINIGAME_1 = "action"  # Now maps to ACTION_ACTION (for minigames)
const ACTION_MINIGAME_2 = "battle_defend"  # X button
const ACTION_MINIGAME_3 = "battle_attack"  # B button
const ACTION_MINIGAME_4 = "battle_skill"   # Y button

var controller_connected_flag: bool = false
var active_controller_id: int = -1

func _ready() -> void:
	# CRITICAL: Remove joypad bindings from Godot's default ui_* actions
	# These interfere with ControllerManager by consuming controller input
	_clear_ui_action_joypad_bindings()

	# Register input actions if they don't exist
	_ensure_input_actions()

	# Check for connected controllers
	_check_controllers()

	# Connect to input device changes
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

	# Connect to controller type changes from ControllerIconLayout
	if has_node("/root/aControllerIconLayout"):
		var icon_layout = get_node("/root/aControllerIconLayout")
		icon_layout.controller_type_changed.connect(_on_controller_type_changed)
		# Apply initial controller type mapping
		_remap_buttons_for_controller_type(icon_layout.get_controller_type())

func _clear_ui_action_joypad_bindings() -> void:
	"""Remove joypad button bindings from Godot's default ui_* actions

	This prevents Godot's GUI system from automatically consuming controller
	inputs before our panels can process them. We keep ui_left/right/up/down
	for popup/dialog navigation, but clear ui_accept to prevent conflicts.
	"""
	# Clear these actions - they conflict with panel input
	var ui_actions_to_clear = [
		"ui_accept", "ui_select", "ui_cancel", "ui_focus_next", "ui_focus_prev",
		"ui_page_up", "ui_page_down", "ui_home", "ui_end"
	]

	for action in ui_actions_to_clear:
		if InputMap.has_action(action):
			var events_to_remove = []
			for event in InputMap.action_get_events(action):
				# Remove only joypad button events, keep keyboard events
				if event is InputEventJoypadButton or event is InputEventJoypadMotion:
					events_to_remove.append(event)

			for event in events_to_remove:
				InputMap.action_erase_event(action, event)
				print("[InputManager] Cleared joypad binding from %s: %s" % [action, event])

	# Keep ui_left/right/up/down for popup navigation - they shouldn't conflict
	print("[InputManager] Keeping ui_up/down/left/right for popup/dialog navigation")

func _ensure_input_actions() -> void:
	"""Ensure all required input actions are registered"""
	var actions = {
		# Movement (shared)
		ACTION_MOVE_UP: [KEY_W, KEY_UP, JOY_BUTTON_DPAD_UP],
		ACTION_MOVE_DOWN: [KEY_S, KEY_DOWN, JOY_BUTTON_DPAD_DOWN],
		ACTION_MOVE_LEFT: [KEY_A, KEY_LEFT, JOY_BUTTON_DPAD_LEFT],
		ACTION_MOVE_RIGHT: [KEY_D, KEY_RIGHT, JOY_BUTTON_DPAD_RIGHT],

		# Overworld
		ACTION_ACTION: [KEY_E, KEY_SPACE, JOY_BUTTON_A],  # A button (Xbox)
		ACTION_JUMP: [KEY_SPACE, JOY_BUTTON_Y],            # Y button (Xbox)
		ACTION_RUN: [KEY_SHIFT, JOY_BUTTON_X],             # X button (Xbox)
		ACTION_PHONE: [KEY_P, JOY_BUTTON_B],               # B button (Xbox)
		ACTION_MENU: [KEY_ESCAPE, JOY_BUTTON_START],       # Start button
		ACTION_SAVE: [KEY_F5, JOY_BUTTON_BACK],            # Select/Back button

		# Battle
		ACTION_ATTACK: [KEY_SPACE, JOY_BUTTON_B],          # B button (Xbox)
		ACTION_SKILL: [KEY_Q, JOY_BUTTON_Y],               # Y button (Xbox)
		ACTION_CAPTURE: [KEY_E, JOY_BUTTON_A],             # A button (Xbox)
		ACTION_DEFEND: [KEY_SHIFT, JOY_BUTTON_X],          # X button (Xbox)
		ACTION_BURST: [KEY_R, JOY_BUTTON_LEFT_SHOULDER],   # L bumper
		ACTION_BATTLE_RUN: [KEY_F, JOY_BUTTON_RIGHT_SHOULDER], # R bumper
		ACTION_ITEMS: [KEY_I, JOY_BUTTON_START],           # Start button
		ACTION_STATUS: [KEY_TAB, JOY_BUTTON_BACK],         # Select/Back button

		# Menus
		ACTION_ACCEPT: [KEY_ENTER, KEY_SPACE, JOY_BUTTON_A],
		ACTION_BACK: [KEY_ESCAPE, JOY_BUTTON_B],
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

	# Add legacy action mappings for ui_menu and ui_phone
	if not InputMap.has_action("ui_menu"):
		InputMap.add_action("ui_menu")
		var event = InputEventKey.new()
		event.keycode = KEY_ESCAPE
		InputMap.action_add_event("ui_menu", event)

	if not InputMap.has_action("ui_phone"):
		InputMap.add_action("ui_phone")
		var event = InputEventKey.new()
		event.keycode = KEY_P
		InputMap.action_add_event("ui_phone", event)

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

func _on_controller_type_changed(new_type: String) -> void:
	"""Handle controller type changes - remap buttons for Nintendo"""
	print("[InputManager] Controller type changed to: %s, remapping buttons..." % new_type)
	_remap_buttons_for_controller_type(new_type)

func _remap_buttons_for_controller_type(controller_type: String) -> void:
	"""Remap controller buttons based on controller type

	Nintendo controllers have A and B swapped compared to Xbox:
	- Nintendo: B (button 1) = accept, A (button 0) = back
	- Xbox/PlayStation: A (button 0) = accept, B (button 1) = back
	"""
	# Define button mappings based on controller type
	var accept_button: int
	var back_button: int

	if controller_type == "nintendo":
		# Nintendo swaps A and B
		accept_button = JOY_BUTTON_B  # Button 1
		back_button = JOY_BUTTON_A    # Button 0
	else:
		# Xbox and PlayStation use standard layout
		accept_button = JOY_BUTTON_A  # Button 0
		back_button = JOY_BUTTON_B    # Button 1

	# Actions that need remapping for accept/back buttons
	var actions_to_remap = {
		# Overworld
		ACTION_ACTION: accept_button,   # A/B button - accept/interact
		ACTION_PHONE: back_button,      # B/A button - back/phone

		# Battle
		ACTION_ATTACK: back_button,     # B/A button - fight
		ACTION_CAPTURE: accept_button,  # A/B button - capture

		# Menus
		ACTION_ACCEPT: accept_button,   # A/B button - menu accept
		ACTION_BACK: back_button,       # B/A button - menu back
	}

	# Remap each action
	for action in actions_to_remap:
		if InputMap.has_action(action):
			# Remove old joypad button events
			var events_to_remove = []
			for event in InputMap.action_get_events(action):
				if event is InputEventJoypadButton:
					events_to_remove.append(event)

			for event in events_to_remove:
				InputMap.action_erase_event(action, event)

			# Add new joypad button event
			var new_event = InputEventJoypadButton.new()
			new_event.button_index = actions_to_remap[action]
			InputMap.action_add_event(action, new_event)

			print("[InputManager] Remapped %s to button %d" % [action, actions_to_remap[action]])

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
		ACTION_ACTION, ACTION_JUMP, ACTION_RUN, ACTION_PHONE, ACTION_MENU, ACTION_SAVE,
		ACTION_ATTACK, ACTION_SKILL, ACTION_CAPTURE, ACTION_DEFEND,
		ACTION_BURST, ACTION_BATTLE_RUN, ACTION_ITEMS, ACTION_STATUS,
		ACTION_ACCEPT, ACTION_BACK
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
