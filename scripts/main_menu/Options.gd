extends Control

## Options menu - accessible from Title screen and System panel
## Displays game settings including controls configuration with remapping

@onready var _close_btn: Button = %CloseBtn
@onready var _controls_panel: Control = %ControlsContent
@onready var _background: ColorRect = $Background

# Remapping state
var _action_data: Array[Dictionary] = []  # Array of {name: String, kb_button: Button, ctrl_button: Button}
var _waiting_for_input: bool = false
var _waiting_action: String = ""

# Controller navigation - action-based
var _selected_action_index: int = 0
var _input_cooldown: float = 0.0
var _input_cooldown_duration: float = 0.2

func _ready() -> void:
	print("[Options] _ready() called")
	print("[Options] Close button: ", _close_btn)
	print("[Options] Controls panel: ", _controls_panel)

	# Ensure this overlay continues to process even when title is "paused"
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Block all input from reaching the title screen behind this menu
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _background:
		_background.mouse_filter = Control.MOUSE_FILTER_STOP

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
	print("[Options] Closing options menu")
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

	# Action definitions - Overworld
	var overworld_actions = [
		{"name": "move_up", "display": "Move Up"},
		{"name": "move_down", "display": "Move Down"},
		{"name": "move_left", "display": "Move Left"},
		{"name": "move_right", "display": "Move Right"},
		{"name": "action", "display": "Action (A)"},
		{"name": "jump", "display": "Jump (Y)"},
		{"name": "run", "display": "Run (X)"},
		{"name": "phone", "display": "Phone (B)"},
		{"name": "menu", "display": "Menu (Start)"},
		{"name": "save", "display": "Save (Select)"},
	]

	# Battle actions
	var battle_actions = [
		{"name": "battle_attack", "display": "Attack (B)"},
		{"name": "battle_skill", "display": "Skill (Y)"},
		{"name": "battle_capture", "display": "Capture (A)"},
		{"name": "battle_defend", "display": "Defend (X)"},
		{"name": "battle_burst", "display": "Burst (L)"},
		{"name": "battle_run", "display": "Run (R)"},
		{"name": "battle_items", "display": "Items (Start)"},
		{"name": "battle_status", "display": "Status (Select)"},
	]

	# Menu actions
	var menu_actions = [
		{"name": "menu_accept", "display": "Accept (A)"},
		{"name": "menu_back", "display": "Back (B)"},
	]

	# ========== OVERWORLD SECTION ==========

	# Overworld section header
	var overworld_header = Label.new()
	overworld_header.text = "━━━ OVERWORLD ━━━"
	overworld_header.add_theme_font_size_override("font_size", 16)
	overworld_header.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	var overworld_center = CenterContainer.new()
	overworld_center.add_child(overworld_header)
	main_vbox.add_child(overworld_center)

	# Spacer
	var spacer_ow = Control.new()
	spacer_ow.custom_minimum_size = Vector2(0, 5)
	main_vbox.add_child(spacer_ow)

	# Overworld grid header
	var ow_header_grid = GridContainer.new()
	ow_header_grid.columns = 3
	ow_header_grid.add_theme_constant_override("h_separation", 30)
	main_vbox.add_child(ow_header_grid)

	var ow_header_action = Label.new()
	ow_header_action.text = "Action"
	ow_header_action.add_theme_font_size_override("font_size", 14)
	ow_header_action.custom_minimum_size.x = 200
	ow_header_grid.add_child(ow_header_action)

	var ow_header_keyboard = Label.new()
	ow_header_keyboard.text = "Keyboard"
	ow_header_keyboard.add_theme_font_size_override("font_size", 14)
	ow_header_keyboard.custom_minimum_size.x = 200
	ow_header_grid.add_child(ow_header_keyboard)

	var ow_header_controller = Label.new()
	ow_header_controller.text = "Controller"
	ow_header_controller.add_theme_font_size_override("font_size", 14)
	ow_header_controller.custom_minimum_size.x = 200
	ow_header_grid.add_child(ow_header_controller)

	# Overworld controls grid
	var ow_grid = GridContainer.new()
	ow_grid.columns = 3
	ow_grid.add_theme_constant_override("h_separation", 30)
	ow_grid.add_theme_constant_override("v_separation", 5)
	main_vbox.add_child(ow_grid)

	# Create overworld controls
	for action_def in overworld_actions:
		var action_name = action_def["name"]
		var display_name = action_def["display"]

		# Action label
		var label = Label.new()
		label.text = display_name
		label.custom_minimum_size.x = 200
		label.add_theme_font_size_override("font_size", 13)
		ow_grid.add_child(label)

		# Keyboard binding button
		var kb_btn = Button.new()
		kb_btn.text = _get_keyboard_binding_text(action_name)
		kb_btn.custom_minimum_size = Vector2(200, 28)
		ow_grid.add_child(kb_btn)

		# Controller binding button
		var ctrl_btn = Button.new()
		ctrl_btn.text = _get_controller_binding_text(action_name)
		ctrl_btn.custom_minimum_size = Vector2(200, 28)
		ow_grid.add_child(ctrl_btn)

		# Store action data for navigation
		_action_data.append({"name": action_name, "kb_button": kb_btn, "ctrl_button": ctrl_btn})

	# ========== BATTLE SECTION ==========

	# Battle section spacer
	var spacer_battle_top = Control.new()
	spacer_battle_top.custom_minimum_size = Vector2(0, 20)
	main_vbox.add_child(spacer_battle_top)

	# Battle section header
	var battle_header = Label.new()
	battle_header.text = "━━━ BATTLE ━━━"
	battle_header.add_theme_font_size_override("font_size", 16)
	battle_header.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	var battle_center = CenterContainer.new()
	battle_center.add_child(battle_header)
	main_vbox.add_child(battle_center)

	# Spacer
	var spacer_b = Control.new()
	spacer_b.custom_minimum_size = Vector2(0, 5)
	main_vbox.add_child(spacer_b)

	# Battle grid header
	var battle_header_grid = GridContainer.new()
	battle_header_grid.columns = 3
	battle_header_grid.add_theme_constant_override("h_separation", 30)
	main_vbox.add_child(battle_header_grid)

	var battle_header_action = Label.new()
	battle_header_action.text = "Action"
	battle_header_action.add_theme_font_size_override("font_size", 14)
	battle_header_action.custom_minimum_size.x = 200
	battle_header_grid.add_child(battle_header_action)

	var battle_header_keyboard = Label.new()
	battle_header_keyboard.text = "Keyboard"
	battle_header_keyboard.add_theme_font_size_override("font_size", 14)
	battle_header_keyboard.custom_minimum_size.x = 200
	battle_header_grid.add_child(battle_header_keyboard)

	var battle_header_controller = Label.new()
	battle_header_controller.text = "Controller"
	battle_header_controller.add_theme_font_size_override("font_size", 14)
	battle_header_controller.custom_minimum_size.x = 200
	battle_header_grid.add_child(battle_header_controller)

	# Battle controls grid
	var battle_grid = GridContainer.new()
	battle_grid.columns = 3
	battle_grid.add_theme_constant_override("h_separation", 30)
	battle_grid.add_theme_constant_override("v_separation", 5)
	main_vbox.add_child(battle_grid)

	# Create battle controls
	for action_def in battle_actions:
		var action_name = action_def["name"]
		var display_name = action_def["display"]

		# Action label
		var label = Label.new()
		label.text = display_name
		label.custom_minimum_size.x = 200
		label.add_theme_font_size_override("font_size", 13)
		battle_grid.add_child(label)

		# Keyboard binding button
		var kb_btn = Button.new()
		kb_btn.text = _get_keyboard_binding_text(action_name)
		kb_btn.custom_minimum_size = Vector2(200, 28)
		battle_grid.add_child(kb_btn)

		# Controller binding button
		var ctrl_btn = Button.new()
		ctrl_btn.text = _get_controller_binding_text(action_name)
		ctrl_btn.custom_minimum_size = Vector2(200, 28)
		battle_grid.add_child(ctrl_btn)

		# Store action data for navigation
		_action_data.append({"name": action_name, "kb_button": kb_btn, "ctrl_button": ctrl_btn})

	# ========== MENUS SECTION ==========

	# Menus section spacer
	var spacer_menu_top = Control.new()
	spacer_menu_top.custom_minimum_size = Vector2(0, 20)
	main_vbox.add_child(spacer_menu_top)

	# Menus section header
	var menu_header = Label.new()
	menu_header.text = "━━━ MENUS ━━━"
	menu_header.add_theme_font_size_override("font_size", 16)
	menu_header.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
	var menu_center = CenterContainer.new()
	menu_center.add_child(menu_header)
	main_vbox.add_child(menu_center)

	# Spacer
	var spacer_m = Control.new()
	spacer_m.custom_minimum_size = Vector2(0, 5)
	main_vbox.add_child(spacer_m)

	# Menus grid header
	var menu_header_grid = GridContainer.new()
	menu_header_grid.columns = 3
	menu_header_grid.add_theme_constant_override("h_separation", 30)
	main_vbox.add_child(menu_header_grid)

	var menu_header_action = Label.new()
	menu_header_action.text = "Action"
	menu_header_action.add_theme_font_size_override("font_size", 14)
	menu_header_action.custom_minimum_size.x = 200
	menu_header_grid.add_child(menu_header_action)

	var menu_header_keyboard = Label.new()
	menu_header_keyboard.text = "Keyboard"
	menu_header_keyboard.add_theme_font_size_override("font_size", 14)
	menu_header_keyboard.custom_minimum_size.x = 200
	menu_header_grid.add_child(menu_header_keyboard)

	var menu_header_controller = Label.new()
	menu_header_controller.text = "Controller"
	menu_header_controller.add_theme_font_size_override("font_size", 14)
	menu_header_controller.custom_minimum_size.x = 200
	menu_header_grid.add_child(menu_header_controller)

	# Menus controls grid
	var menu_grid = GridContainer.new()
	menu_grid.columns = 3
	menu_grid.add_theme_constant_override("h_separation", 30)
	menu_grid.add_theme_constant_override("v_separation", 5)
	main_vbox.add_child(menu_grid)

	# Create menu controls
	for action_def in menu_actions:
		var action_name = action_def["name"]
		var display_name = action_def["display"]

		# Action label
		var label = Label.new()
		label.text = display_name
		label.custom_minimum_size.x = 200
		label.add_theme_font_size_override("font_size", 13)
		menu_grid.add_child(label)

		# Keyboard binding button
		var kb_btn = Button.new()
		kb_btn.text = _get_keyboard_binding_text(action_name)
		kb_btn.custom_minimum_size = Vector2(200, 28)
		menu_grid.add_child(kb_btn)

		# Controller binding button
		var ctrl_btn = Button.new()
		ctrl_btn.text = _get_controller_binding_text(action_name)
		ctrl_btn.custom_minimum_size = Vector2(200, 28)
		menu_grid.add_child(ctrl_btn)

		# Store action data for navigation
		_action_data.append({"name": action_name, "kb_button": kb_btn, "ctrl_button": ctrl_btn})

	# ========== FOOTER ==========

	# Spacer
	var spacer3 = Control.new()
	spacer3.custom_minimum_size = Vector2(0, 15)
	main_vbox.add_child(spacer3)

	# Reset button
	var reset_hbox = HBoxContainer.new()
	reset_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(reset_hbox)

	var reset_btn = Button.new()
	reset_btn.text = "Reset to Defaults"
	reset_btn.custom_minimum_size = Vector2(180, 35)
	reset_btn.pressed.connect(_on_reset_pressed)
	reset_hbox.add_child(reset_btn)

	# Spacer
	var spacer4 = Control.new()
	spacer4.custom_minimum_size = Vector2(0, 5)
	main_vbox.add_child(spacer4)

	# Info text
	var info_label = Label.new()
	info_label.text = "Click any button to remap • Press ESC to cancel"
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	info_label.add_theme_font_size_override("font_size", 12)
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.custom_minimum_size.x = 600
	var info_center = CenterContainer.new()
	info_center.add_child(info_label)
	main_vbox.add_child(info_center)

	print("[Options] Controls UI built successfully!")

	# Setup controller navigation
	_setup_controller_navigation()

func _setup_controller_navigation() -> void:
	"""Setup controller navigation for action rows"""
	# Start with first action selected
	if _action_data.size() > 0:
		_selected_action_index = 0
		_highlight_action(_selected_action_index)

	print("[Options] Navigation setup complete. ", _action_data.size(), " actions")

func _process(delta: float) -> void:
	"""Handle input cooldown"""
	if _input_cooldown > 0:
		_input_cooldown -= delta

func _input(event: InputEvent) -> void:
	# Handle controller navigation and actions when not remapping
	if not _waiting_for_input:
		# Back button closes menu
		if event.is_action_pressed("menu_back") or (event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed):
			_on_close_pressed()
			get_viewport().set_input_as_handled()
			return

		# Controller navigation through ACTIONS (not individual buttons)
		if _input_cooldown <= 0 and _action_data.size() > 0:
			if event.is_action_pressed("move_up"):
				_navigate_actions(-1)
				_input_cooldown = _input_cooldown_duration
				get_viewport().set_input_as_handled()
				return
			elif event.is_action_pressed("move_down"):
				_navigate_actions(1)
				_input_cooldown = _input_cooldown_duration
				get_viewport().set_input_as_handled()
				return
			elif event.is_action_pressed("menu_accept"):
				# Start remapping for selected action
				_start_remapping()
				get_viewport().set_input_as_handled()
				return
		return

	# In remapping mode - auto-detect keyboard vs controller
	# Allow ESC to cancel remapping
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		_cancel_remapping()
		get_viewport().set_input_as_handled()
		return

	var is_controller = false
	var new_event: InputEvent = null

	# Auto-detect: controller input
	if event is InputEventJoypadButton and event.pressed:
		new_event = event
		is_controller = true
	elif event is InputEventJoypadMotion and abs(event.axis_value) > 0.5:
		new_event = event
		is_controller = true
	# Auto-detect: keyboard input (but not ESC since we handle that above)
	elif event is InputEventKey and event.pressed and event.keycode != KEY_ESCAPE:
		new_event = event
		is_controller = false

	# Remap if we got valid input
	if new_event != null:
		_remap_action(_waiting_action, new_event, is_controller)
		_complete_remapping(is_controller)
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
	for action in _action_data:
		action.kb_button.text = _get_keyboard_binding_text(action.name)
		action.ctrl_button.text = _get_controller_binding_text(action.name)

func _on_reset_pressed() -> void:
	"""Reset all controls to defaults"""
	# Clear all actions
	var actions = [
		"move_up", "move_down", "move_left", "move_right",
		"action", "jump", "run", "phone", "menu", "save",
		"battle_attack", "battle_skill", "battle_capture", "battle_defend",
		"battle_burst", "battle_run", "battle_items", "battle_status",
		"menu_accept", "menu_back"
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

# ------------------------------------------------------------------------------
# Controller Navigation Helpers
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Action Navigation Helpers
# ------------------------------------------------------------------------------

func _navigate_actions(direction: int) -> void:
	"""Navigate through action rows with controller"""
	if _action_data.is_empty():
		return

	_unhighlight_action(_selected_action_index)

	_selected_action_index += direction
	if _selected_action_index < 0:
		_selected_action_index = _action_data.size() - 1
	elif _selected_action_index >= _action_data.size():
		_selected_action_index = 0

	_highlight_action(_selected_action_index)

func _highlight_action(index: int) -> void:
	"""Highlight both keyboard and controller buttons for an action"""
	if index >= 0 and index < _action_data.size():
		var action = _action_data[index]
		action.kb_button.modulate = Color(1.2, 1.2, 0.8, 1.0)
		action.ctrl_button.modulate = Color(1.2, 1.2, 0.8, 1.0)
		action.kb_button.grab_focus()

func _unhighlight_action(index: int) -> void:
	"""Remove highlight from an action row"""
	if index >= 0 and index < _action_data.size():
		var action = _action_data[index]
		action.kb_button.modulate = Color(1.0, 1.0, 1.0, 1.0)
		action.ctrl_button.modulate = Color(1.0, 1.0, 1.0, 1.0)

# ------------------------------------------------------------------------------
# Remapping Helpers
# ------------------------------------------------------------------------------

func _start_remapping() -> void:
	"""Start remapping mode for selected action"""
	if _selected_action_index < 0 or _selected_action_index >= _action_data.size():
		return

	var action = _action_data[_selected_action_index]
	_waiting_for_input = true
	_waiting_action = action.name

	# Update both buttons to show waiting state
	action.kb_button.text = "Press key/button..."
	action.ctrl_button.text = "Press key/button..."

	print("[Options] Waiting for input to remap: ", action.name)

func _cancel_remapping() -> void:
	"""Cancel remapping and restore button text"""
	if _selected_action_index >= 0 and _selected_action_index < _action_data.size():
		var action = _action_data[_selected_action_index]
		action.kb_button.text = _get_keyboard_binding_text(action.name)
		action.ctrl_button.text = _get_controller_binding_text(action.name)

	_waiting_for_input = false
	_waiting_action = ""
	print("[Options] Remapping cancelled")

func _complete_remapping(is_controller: bool) -> void:
	"""Complete remapping and update button text"""
	if _selected_action_index >= 0 and _selected_action_index < _action_data.size():
		var action = _action_data[_selected_action_index]
		# Update button text to show new binding
		action.kb_button.text = _get_keyboard_binding_text(action.name)
		action.ctrl_button.text = _get_controller_binding_text(action.name)

	_waiting_for_input = false
	_waiting_action = ""
	print("[Options] Remapping complete (", "controller" if is_controller else "keyboard", ")")
