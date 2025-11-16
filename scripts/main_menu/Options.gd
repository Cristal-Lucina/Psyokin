extends Control

## Options menu - accessible from Title screen and System panel
## Tabbed interface with Game Options, Controls, Display, and Sound

@onready var _background: ColorRect = $Background
@onready var _panel: Panel = $CenterContainer/Panel
@onready var _content_container: Control = null  # Will hold the tab content

# Tab management
enum Tab { GAME, CONTROLS, DISPLAY, SOUND }
var _current_tab: Tab = Tab.GAME
var _tab_buttons: Array[Button] = []
var _tab_content: Dictionary = {}  # Tab -> Control node

# Two-level navigation state
enum NavLevel { OPTIONS, TOGGLES }  # Navigate option labels vs toggle buttons
var _nav_level: NavLevel = NavLevel.OPTIONS
var _option_containers: Array[Control] = []  # Focusable option containers
var _current_option_index: int = 0
var _current_toggle_group: HBoxContainer = null

# Settings
var _control_type: String = "keyboard"  # keyboard, xbox, playstation, nintendo
var _language: String = "English"
var _text_speed: int = 1  # 0=Slow, 1=Normal, 2=Fast
var _vibration: bool = true
var _difficulty: int = 1  # 0=Easy, 1=Normal, 2=Hard
var _display_type: String = "stretch"  # stretch, constant
var _resolution: String = "1080p"  # 720p, 1080p
var _display_mode: String = "fullscreen"  # fullscreen, borderless, windowed
var _volume_voice: float = 100.0
var _volume_music: float = 100.0
var _volume_sfx: float = 100.0
var _volume_ambient: float = 100.0

# Remapping state (for Controls tab)
var _action_data: Array[Dictionary] = []
var _waiting_for_input: bool = false
var _waiting_action: String = ""
var _selected_action_index: int = 0
var _input_cooldown: float = 0.0
var _scroll_container: ScrollContainer = null

func _ready() -> void:
	print("[Options] _ready() called - building tabbed interface")

	# Ensure this overlay continues to process even when title is "paused"
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)

	# Debug: Check what's in ui_accept action
	if InputMap.has_action("ui_accept"):
		var events = InputMap.action_get_events("ui_accept")
		print("[Options] ui_accept has %d events:" % events.size())
		for e in events:
			if e is InputEventJoypadButton:
				print("  - JoypadButton %d" % e.button_index)
			elif e is InputEventKey:
				print("  - Key %d" % e.keycode)
	else:
		print("[Options] WARNING: ui_accept action does not exist!")

	# Disable ControllerManager to prevent it from consuming controller inputs
	if has_node("/root/aControllerManager"):
		var controller_mgr = get_node("/root/aControllerManager")
		controller_mgr.push_context(controller_mgr.InputContext.DISABLED)
		print("[Options] ControllerManager disabled")

	# Re-add joypad buttons to ui actions (InputManager removes them at startup)
	# We need them for controller navigation in the Options menu

	# Re-add button 0 to ui_accept
	var has_button_0 = false
	if InputMap.has_action("ui_accept"):
		for event in InputMap.action_get_events("ui_accept"):
			if event is InputEventJoypadButton and event.button_index == 0:
				has_button_0 = true
				break

	if not has_button_0:
		var joy_accept = InputEventJoypadButton.new()
		joy_accept.button_index = 0
		InputMap.action_add_event("ui_accept", joy_accept)
		print("[Options] Re-added button 0 to ui_accept for controller navigation")

	# Re-add button 1 to ui_cancel
	var has_button_1 = false
	if InputMap.has_action("ui_cancel"):
		for event in InputMap.action_get_events("ui_cancel"):
			if event is InputEventJoypadButton and event.button_index == 1:
				has_button_1 = true
				break

	if not has_button_1:
		var joy_cancel = InputEventJoypadButton.new()
		joy_cancel.button_index = 1
		InputMap.action_add_event("ui_cancel", joy_cancel)
		print("[Options] Re-added button 1 to ui_cancel for controller navigation")

	# Block all input from reaching the title screen behind this menu
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _background:
		_background.mouse_filter = Control.MOUSE_FILTER_STOP

	# Apply Core Vibe styling to panel
	if _panel:
		_style_panel(_panel)

	# Load settings from aSettings
	_load_settings()

	# Apply display and audio settings to ensure they're in effect
	_apply_display_settings()
	_apply_audio_settings()

	# Build the tabbed interface
	_build_tabbed_interface()

	print("[Options] Tabbed interface built successfully!")

func _process(delta: float) -> void:
	"""Handle input cooldown for remapping"""
	if _input_cooldown > 0:
		_input_cooldown -= delta

func _input(event: InputEvent) -> void:
	"""Handle input for menu navigation"""
	# Handle tab button acceptance
	if event.is_action_pressed("ui_accept"):
		var focused = get_viewport().gui_get_focus_owner()
		if focused and focused in _tab_buttons:
			var idx = _tab_buttons.find(focused)
			if idx >= 0:
				print("[Options] Switching to tab %d" % idx)
				_switch_tab(Tab.values()[idx])
				_move_focus_to_content()
				get_viewport().set_input_as_handled()
				return

	# Handle two-level navigation in content
	var focused = get_viewport().gui_get_focus_owner()
	var is_in_content = _is_focused_in_content(focused)

	if is_in_content:
		# Handle navigation within content panel
		if _nav_level == NavLevel.OPTIONS:
			# Navigate option containers
			if event.is_action_pressed("move_up"):
				_navigate_options(-1)
				get_viewport().set_input_as_handled()
				return
			elif event.is_action_pressed("move_down"):
				_navigate_options(1)
				get_viewport().set_input_as_handled()
				return
			elif event.is_action_pressed("ui_accept") or event.is_action_pressed("menu_accept"):
				_enter_toggle_selection()
				get_viewport().set_input_as_handled()
				return
			elif event.is_action_pressed("menu_cancel") or event.is_action_pressed("ui_cancel"):
				# Back from options: return to tab buttons
				_return_to_tabs()
				get_viewport().set_input_as_handled()
				return

		elif _nav_level == NavLevel.TOGGLES:
			# Navigate within toggle buttons
			if event.is_action_pressed("move_left"):
				_navigate_toggles(-1)
				get_viewport().set_input_as_handled()
				return
			elif event.is_action_pressed("move_right"):
				_navigate_toggles(1)
				get_viewport().set_input_as_handled()
				return
			elif event.is_action_pressed("ui_accept") or event.is_action_pressed("menu_accept"):
				_activate_current_toggle()
				get_viewport().set_input_as_handled()
				return
			elif event.is_action_pressed("menu_cancel") or event.is_action_pressed("ui_cancel"):
				# Back from toggles: return to option navigation
				_exit_toggle_selection()
				get_viewport().set_input_as_handled()
				return
	else:
		# Handle back button in tab panel - close menu
		if event.is_action_pressed("menu_cancel") or event.is_action_pressed("ui_cancel"):
			_on_close_pressed()
			get_viewport().set_input_as_handled()
			return

func _is_focused_in_content(focused: Control) -> bool:
	"""Check if focused control is within content container"""
	if not focused:
		return false
	if focused in _tab_buttons:
		return false

	var parent = focused
	while parent != null:
		if parent == _content_container:
			return true
		parent = parent.get_parent()
	return false

func _navigate_options(direction: int) -> void:
	"""Navigate through option containers (Display Type, Resolution, etc.)"""
	if _option_containers.is_empty():
		return

	# Clear highlight from current option
	if _current_option_index >= 0 and _current_option_index < _option_containers.size():
		_unhighlight_option(_current_option_index)

	# Move to next option
	_current_option_index += direction
	if _current_option_index < 0:
		_current_option_index = _option_containers.size() - 1
	elif _current_option_index >= _option_containers.size():
		_current_option_index = 0

	# Highlight new option
	_highlight_option(_current_option_index)
	print("[Options] Navigated to option %d" % _current_option_index)

func _enter_toggle_selection() -> void:
	"""Enter toggle selection mode for current option"""
	if _current_option_index < 0 or _current_option_index >= _option_containers.size():
		return

	var container = _option_containers[_current_option_index]
	# Find the HBoxContainer with toggle buttons or sliders
	var toggle_group = _find_toggle_group(container)
	if toggle_group:
		_current_toggle_group = toggle_group
		_nav_level = NavLevel.TOGGLES

		# Focus first button or slider in toggle group
		if toggle_group.get_child_count() > 0:
			var first_child = toggle_group.get_child(0)
			if first_child is Button:
				first_child.grab_focus()
			elif first_child is HSlider:
				first_child.grab_focus()
			print("[Options] Entered toggle selection")

func _exit_toggle_selection() -> void:
	"""Exit toggle selection mode and return to option navigation"""
	_nav_level = NavLevel.OPTIONS
	_current_toggle_group = null

	# Restore highlight on current option
	if _current_option_index >= 0 and _current_option_index < _option_containers.size():
		_highlight_option(_current_option_index)
	print("[Options] Exited toggle selection")

func _navigate_toggles(direction: int) -> void:
	"""Navigate within toggle button group"""
	if not _current_toggle_group:
		return

	var focused = get_viewport().gui_get_focus_owner()
	if not focused or not focused is Button:
		return

	var buttons: Array[Button] = []
	for child in _current_toggle_group.get_children():
		if child is Button:
			buttons.append(child)

	if buttons.is_empty():
		return

	var current_idx = buttons.find(focused)
	if current_idx < 0:
		return

	# Navigate
	current_idx += direction
	if current_idx < 0:
		current_idx = buttons.size() - 1
	elif current_idx >= buttons.size():
		current_idx = 0

	buttons[current_idx].grab_focus()

func _activate_current_toggle() -> void:
	"""Activate the currently focused toggle button"""
	var focused = get_viewport().gui_get_focus_owner()
	if focused and focused is Button:
		focused.emit_signal("pressed")

func _return_to_tabs() -> void:
	"""Return focus to tab buttons"""
	_nav_level = NavLevel.OPTIONS
	if _current_tab >= 0 and _current_tab < _tab_buttons.size():
		_tab_buttons[_current_tab].grab_focus()

func _highlight_option(index: int) -> void:
	"""Highlight an option container"""
	if index < 0 or index >= _option_containers.size():
		return

	var container = _option_containers[index]
	# Add visual feedback - bright border
	if container.has_meta("panel"):
		var panel = container.get_meta("panel") as Panel
		if panel:
			var style = panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
			style.border_color = aCoreVibeTheme.COLOR_ELECTRIC_LIME
			style.border_width_left = 3
			style.border_width_right = 3
			style.border_width_top = 3
			style.border_width_bottom = 3
			panel.add_theme_stylebox_override("panel", style)

func _unhighlight_option(index: int) -> void:
	"""Remove highlight from an option container"""
	if index < 0 or index >= _option_containers.size():
		return

	var container = _option_containers[index]
	# Remove visual feedback - dim border
	if container.has_meta("panel"):
		var panel = container.get_meta("panel") as Panel
		if panel:
			var style = panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
			style.border_color = aCoreVibeTheme.COLOR_SKY_CYAN
			style.border_width_left = 2
			style.border_width_right = 2
			style.border_width_top = 2
			style.border_width_bottom = 2
			panel.add_theme_stylebox_override("panel", style)

func _find_toggle_group(container: Control) -> HBoxContainer:
	"""Find the HBoxContainer with toggle buttons or sliders in an option container"""
	for child in container.get_children():
		if child is HBoxContainer:
			# Check if it has Button or Slider children
			for subchild in child.get_children():
				if subchild is Button or subchild is HSlider:
					return child as HBoxContainer
	return null

func _unhandled_input(event: InputEvent) -> void:
	"""Block any unhandled input from reaching the game behind this menu"""
	# Consume all unhandled keyboard and controller inputs to prevent them from affecting the game
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion or event is InputEventMouseButton:
		get_viewport().set_input_as_handled()

func _remap_action(new_event: InputEvent) -> void:
	"""Apply a new input event to the waiting action"""
	if not _waiting_for_input or _waiting_action == "":
		return

	# Get all current events
	var current_events = InputMap.action_get_events(_waiting_action)

	# Remove only events of the same type (keyboard or joypad)
	var is_keyboard_remap = new_event is InputEventKey
	for event in current_events:
		if is_keyboard_remap:
			# Removing keyboard event
			if event is InputEventKey:
				InputMap.action_erase_event(_waiting_action, event)
		else:
			# Removing joypad events
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				InputMap.action_erase_event(_waiting_action, event)

	# Add the new event
	InputMap.action_add_event(_waiting_action, new_event)

	# Update the button to show the new binding
	if _selected_action_index >= 0 and _selected_action_index < _action_data.size():
		var btn = _action_data[_selected_action_index]["button"] as Button
		if btn:
			btn.text = _get_action_display_text(_waiting_action)

	# Stop waiting
	_waiting_for_input = false
	_waiting_action = ""

	print("[Options] Remapped action to: %s" % _get_action_display_text(_waiting_action))
	_save_settings()

func _style_panel(panel: Panel) -> void:
	"""Apply Core Vibe neon-kawaii styling to main options panel"""
	var style = aCoreVibeTheme.create_panel_style(
		aCoreVibeTheme.COLOR_MILK_WHITE,          # White border
		aCoreVibeTheme.COLOR_NIGHT_NAVY,          # Black background
		1.0,                                       # Full opacity
		aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px rounded corners
		aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
		aCoreVibeTheme.SHADOW_SIZE_LARGE          # 12px glow
	)
	panel.add_theme_stylebox_override("panel", style)

func _style_tab_panel(panel: Panel) -> void:
	"""Apply Core Vibe styling to tab button panel"""
	var style = aCoreVibeTheme.create_panel_style(
		aCoreVibeTheme.COLOR_ELECTRIC_LIME,       # Electric Lime border
		aCoreVibeTheme.COLOR_NIGHT_NAVY,          # Black background
		0.8,                                       # 80% opacity
		aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px rounded corners
		aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
		aCoreVibeTheme.SHADOW_SIZE_MEDIUM         # 8px glow
	)
	panel.add_theme_stylebox_override("panel", style)

func _style_content_panel(panel: Panel) -> void:
	"""Apply Core Vibe styling to content panel"""
	var style = aCoreVibeTheme.create_panel_style(
		aCoreVibeTheme.COLOR_SKY_CYAN,            # Sky Cyan border
		aCoreVibeTheme.COLOR_NIGHT_NAVY,          # Black background
		0.8,                                       # 80% opacity
		aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px rounded corners
		aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
		aCoreVibeTheme.SHADOW_SIZE_MEDIUM         # 8px glow
	)
	panel.add_theme_stylebox_override("panel", style)

func _add_button_padding(button: Button) -> void:
	"""Add padding to button text so it doesn't touch edges"""
	# Get the current styleboxes and add content margins
	for state in ["normal", "hover", "pressed", "focus"]:
		var stylebox = button.get_theme_stylebox(state)
		if stylebox and stylebox is StyleBoxFlat:
			var style = stylebox as StyleBoxFlat
			style.content_margin_left = 12
			style.content_margin_right = 12
			style.content_margin_top = 8
			style.content_margin_bottom = 8

# ==============================================================================
# Settings Load/Save
# ==============================================================================

func _load_settings() -> void:
	"""Load settings from aSettings autoload"""
	if has_node("/root/aSettings"):
		_control_type = aSettings.get_value("control_type", "keyboard")
		_language = aSettings.get_value("language", "English")
		_text_speed = aSettings.get_value("text_speed", 1)
		_vibration = aSettings.get_value("vibration", true)
		_difficulty = aSettings.get_value("difficulty", 1)
		_display_type = aSettings.get_value("display_type", "stretch")
		_resolution = aSettings.get_value("resolution", "1080p")
		_display_mode = aSettings.get_value("display_mode", "fullscreen")
		_volume_voice = aSettings.get_value("volume_voice", 100.0)
		_volume_music = aSettings.get_value("volume_music", 100.0)
		_volume_sfx = aSettings.get_value("volume_sfx", 100.0)
		_volume_ambient = aSettings.get_value("volume_ambient", 100.0)

func _save_settings() -> void:
	"""Save settings to aSettings autoload"""
	if has_node("/root/aSettings"):
		aSettings.set_value("control_type", _control_type)
		aSettings.set_value("language", _language)
		aSettings.set_value("text_speed", _text_speed)
		aSettings.set_value("vibration", _vibration)
		aSettings.set_value("difficulty", _difficulty)
		aSettings.set_value("display_type", _display_type)
		aSettings.set_value("resolution", _resolution)
		aSettings.set_value("display_mode", _display_mode)
		aSettings.set_value("volume_voice", _volume_voice)
		aSettings.set_value("volume_music", _volume_music)
		aSettings.set_value("volume_sfx", _volume_sfx)
		aSettings.set_value("volume_ambient", _volume_ambient)

# ==============================================================================
# Tab Interface Builder
# ==============================================================================

func _build_tabbed_interface() -> void:
	"""Build vertical tabs on left, content on right"""
	# Clear existing content
	var margin = _panel.get_node_or_null("MarginContainer")
	if margin:
		for child in margin.get_children():
			child.queue_free()
	else:
		margin = MarginContainer.new()
		margin.name = "MarginContainer"
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		margin.add_theme_constant_override("margin_left", 20)
		margin.add_theme_constant_override("margin_top", 20)
		margin.add_theme_constant_override("margin_right", 20)
		margin.add_theme_constant_override("margin_bottom", 20)
		_panel.add_child(margin)

	# Main HBox: tabs on left, content on right
	var main_hbox = HBoxContainer.new()
	main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_theme_constant_override("separation", 20)
	margin.add_child(main_hbox)

	# Left side: Panel containing tab buttons
	var tab_panel = Panel.new()
	tab_panel.custom_minimum_size = Vector2(200, 0)
	_style_tab_panel(tab_panel)
	main_hbox.add_child(tab_panel)

	# Margin container inside tab panel
	var tab_margin = MarginContainer.new()
	tab_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	tab_margin.add_theme_constant_override("margin_left", 12)
	tab_margin.add_theme_constant_override("margin_top", 12)
	tab_margin.add_theme_constant_override("margin_right", 12)
	tab_margin.add_theme_constant_override("margin_bottom", 12)
	tab_panel.add_child(tab_margin)

	# Vertical tab bar inside margin
	var tab_vbox = VBoxContainer.new()
	tab_vbox.add_theme_constant_override("separation", 8)
	tab_margin.add_child(tab_vbox)

	# Tab buttons
	_create_tab_button(tab_vbox, "GAME OPTIONS", Tab.GAME, aCoreVibeTheme.COLOR_ELECTRIC_LIME)
	_create_tab_button(tab_vbox, "CONTROLS", Tab.CONTROLS, aCoreVibeTheme.COLOR_SKY_CYAN)
	_create_tab_button(tab_vbox, "DISPLAY", Tab.DISPLAY, aCoreVibeTheme.COLOR_CITRUS_YELLOW)
	_create_tab_button(tab_vbox, "SOUND", Tab.SOUND, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA)

	# Spacer to push Close button to bottom
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_vbox.add_child(spacer)

	# Close button at bottom of tab bar
	var close_btn = Button.new()
	close_btn.text = "CLOSE"
	close_btn.custom_minimum_size = Vector2(0, 50)
	close_btn.focus_mode = Control.FOCUS_ALL
	close_btn.pressed.connect(_on_close_pressed)
	aCoreVibeTheme.style_button_with_focus_invert(close_btn, aCoreVibeTheme.COLOR_GRAPE_VIOLET, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
	_add_button_padding(close_btn)
	tab_vbox.add_child(close_btn)

	# Right side: Panel containing content
	var content_panel = Panel.new()
	content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_style_content_panel(content_panel)
	main_hbox.add_child(content_panel)

	# Margin container inside content panel
	var content_margin = MarginContainer.new()
	content_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_margin.add_theme_constant_override("margin_left", 12)
	content_margin.add_theme_constant_override("margin_top", 12)
	content_margin.add_theme_constant_override("margin_right", 12)
	content_margin.add_theme_constant_override("margin_bottom", 12)
	content_panel.add_child(content_margin)

	# Content container inside margin
	_content_container = Control.new()
	_content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_margin.add_child(_content_container)

	# Build all tab content
	_tab_content[Tab.GAME] = _build_game_options_tab()
	_tab_content[Tab.CONTROLS] = _build_controls_tab()
	_tab_content[Tab.DISPLAY] = _build_display_tab()
	_tab_content[Tab.SOUND] = _build_sound_tab()

	# Add all tabs to container (initially hidden)
	for tab in _tab_content.values():
		_content_container.add_child(tab)
		tab.visible = false

	# Show first tab
	_switch_tab(Tab.GAME)

	# Set initial focus for controller navigation
	if _tab_buttons.size() > 0:
		_tab_buttons[0].grab_focus()

	# Set up focus chain for tab buttons after UI is built
	call_deferred("_setup_tab_focus_chain", close_btn)

func _create_tab_button(parent: Node, label: String, tab: Tab, color: Color) -> void:
	"""Create a tab button"""
	var btn = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 50)
	btn.focus_mode = Control.FOCUS_ALL

	# Handle both pressed and gui_input for controller support
	btn.pressed.connect(func():
		print("[Options] Tab button '%s' pressed!" % label)
		_switch_tab(tab)
		_move_focus_to_content()
	)

	# Add focus tracking
	btn.focus_entered.connect(func():
		print("[Options] Tab button '%s' focused" % label)
	)

	aCoreVibeTheme.style_button_with_focus_invert(btn, color, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
	_add_button_padding(btn)
	parent.add_child(btn)
	_tab_buttons.append(btn)

func _switch_tab(tab: Tab) -> void:
	"""Switch to a different tab"""
	_current_tab = tab

	# Hide all tabs
	for t in _tab_content.values():
		t.visible = false

	# Show selected tab
	if _tab_content.has(tab):
		_tab_content[tab].visible = true

	# Reset navigation state
	_nav_level = NavLevel.OPTIONS
	_current_option_index = 0
	_current_toggle_group = null

	# Rebuild option containers list for this tab
	_option_containers.clear()
	if _tab_content.has(tab):
		_collect_option_containers(_tab_content[tab], _option_containers)

	print("[Options] Switched to tab: %s with %d option containers" % [tab, _option_containers.size()])

func _move_focus_to_content() -> void:
	"""Move focus to the first option container in the current content"""
	if _option_containers.is_empty():
		return

	# Reset to first option
	_current_option_index = 0
	_nav_level = NavLevel.OPTIONS

	# Highlight first option
	_highlight_option(0)

func _collect_option_containers(node: Node, result: Array[Control]) -> void:
	"""Recursively collect option containers"""
	if node.has_meta("panel"):
		# This is an option container
		result.append(node as Control)
		return

	for child in node.get_children():
		_collect_option_containers(child, result)

func _find_first_focusable(node: Node) -> Control:
	"""Recursively find the first focusable control in a node tree"""
	if node is Control:
		var control = node as Control
		if control.focus_mode != Control.FOCUS_NONE and control.visible:
			return control

	for child in node.get_children():
		var result = _find_first_focusable(child)
		if result:
			return result

	return null

func _on_close_pressed() -> void:
	print("[Options] Closing options menu")
	_save_settings()

	# Remove joypad buttons from ui actions (restore InputManager's original state)
	if InputMap.has_action("ui_accept"):
		var events_to_remove = []
		for event in InputMap.action_get_events("ui_accept"):
			if event is InputEventJoypadButton and event.button_index == 0:
				events_to_remove.append(event)
		for event in events_to_remove:
			InputMap.action_erase_event("ui_accept", event)
			print("[Options] Removed button 0 from ui_accept (restoring InputManager state)")

	if InputMap.has_action("ui_cancel"):
		var events_to_remove = []
		for event in InputMap.action_get_events("ui_cancel"):
			if event is InputEventJoypadButton and event.button_index == 1:
				events_to_remove.append(event)
		for event in events_to_remove:
			InputMap.action_erase_event("ui_cancel", event)
			print("[Options] Removed button 1 from ui_cancel (restoring InputManager state)")

	# Restore ControllerManager's previous context
	if has_node("/root/aControllerManager"):
		var controller_mgr = get_node("/root/aControllerManager")
		controller_mgr.pop_context()
		print("[Options] ControllerManager context restored")

	queue_free()

# ==============================================================================
# Tab Content Builders
# ==============================================================================

func _build_game_options_tab() -> Control:
	"""Build Game Options tab: Language, Text Speed, Vibration, Difficulty"""
	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var container = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 12)
	scroll.add_child(container)

	# Title
	var title = Label.new()
	title.text = "GAME OPTIONS"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_ELECTRIC_LIME)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(title)

	_add_spacer(container, 10)

	# Language - option container with toggles
	var lang_hbox = _create_button_group(["English"], 0, func(_idx): _language = "English"; _save_settings())
	var lang_container = _create_option_container("Language", lang_hbox)
	container.add_child(lang_container)

	# Text Speed - option container with toggles
	var speed_hbox = _create_button_group(["Slow", "Normal", "Fast"], _text_speed, func(idx): _text_speed = idx; _save_settings())
	var speed_container = _create_option_container("Text Speed", speed_hbox)
	container.add_child(speed_container)

	# Vibration - option container with toggles
	var vib_hbox = _create_button_group(["Off", "On"], 1 if _vibration else 0, func(idx): _vibration = (idx == 1); _save_settings())
	var vib_container = _create_option_container("Vibration", vib_hbox)
	container.add_child(vib_container)

	# Difficulty - option container with toggles
	var diff_hbox = _create_button_group(["Easy", "Normal", "Hard"], _difficulty, func(idx): _difficulty = idx; _save_settings())
	var diff_container = _create_option_container("Difficulty", diff_hbox)
	container.add_child(diff_container)

	return scroll

func _setup_vertical_focus_for_tab(container: Control) -> void:
	"""Set up vertical focus navigation for all focusable controls in a tab"""
	var focusable_controls: Array[Control] = []
	_collect_focusable_controls(container, focusable_controls)

	# Connect them vertically
	for i in range(focusable_controls.size()):
		if i > 0:
			focusable_controls[i].focus_neighbor_top = focusable_controls[i].get_path_to(focusable_controls[i - 1])
		if i < focusable_controls.size() - 1:
			focusable_controls[i].focus_neighbor_bottom = focusable_controls[i].get_path_to(focusable_controls[i + 1])

	print("[Options] Set up vertical focus chain with %d controls" % focusable_controls.size())

func _collect_focusable_controls(node: Node, result: Array[Control]) -> void:
	"""Recursively collect all focusable controls"""
	if node is Control:
		var ctrl = node as Control
		if ctrl.focus_mode != Control.FOCUS_NONE and ctrl.visible:
			result.append(ctrl)

	for child in node.get_children():
		_collect_focusable_controls(child, result)

func _build_controls_tab() -> Control:
	"""Build Controls tab with Control Type selector and remapping"""
	var main_container = VBoxContainer.new()
	main_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_container.add_theme_constant_override("separation", 20)

	# Title
	var title = Label.new()
	title.text = "CONTROLS"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_SKY_CYAN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_container.add_child(title)

	_add_spacer(main_container, 10)

	# Control Style selector
	_add_option_label(main_container, "Control Style")
	var type_idx = 0
	if _control_type == "keyboard":
		type_idx = 0
	elif _control_type == "xbox":
		type_idx = 1
	elif _control_type == "playstation":
		type_idx = 2
	else:  # nintendo
		type_idx = 3

	var type_hbox = _create_button_group(["Keyboard", "Xbox", "PlayStation", "Nintendo"], type_idx, func(idx):
		if idx == 0:
			_control_type = "keyboard"
		elif idx == 1:
			_control_type = "xbox"
		elif idx == 2:
			_control_type = "playstation"
		else:
			_control_type = "nintendo"
		_save_settings()
		# Rebuild tab to show new control type
		_rebuild_controls_tab()
	)
	main_container.add_child(type_hbox)

	_add_spacer(main_container, 20)

	# Scrollable remapping section
	_scroll_container = ScrollContainer.new()
	_scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_container.add_child(_scroll_container)

	var scroll_content = VBoxContainer.new()
	scroll_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_content.add_theme_constant_override("separation", 8)
	_scroll_container.add_child(scroll_content)

	# Build action rows for remapping
	_build_action_rows(scroll_content)

	# Restore Defaults button
	var restore_btn = Button.new()
	restore_btn.text = "RESTORE DEFAULTS"
	restore_btn.custom_minimum_size = Vector2(200, 45)
	restore_btn.focus_mode = Control.FOCUS_ALL
	restore_btn.pressed.connect(_restore_controls_defaults_and_rebuild)
	aCoreVibeTheme.style_button_with_focus_invert(restore_btn, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
	_add_button_padding(restore_btn)
	var restore_center = CenterContainer.new()
	restore_center.add_child(restore_btn)
	main_container.add_child(restore_center)

	# Set up focus chain after UI is built
	call_deferred("_setup_controls_focus_chain")

	return main_container

func _build_display_tab() -> Control:
	"""Build Display tab: Display Type, Resolution, Mode"""
	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var container = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 12)
	scroll.add_child(container)

	# Title
	var title = Label.new()
	title.text = "DISPLAY"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_CITRUS_YELLOW)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(title)

	_add_spacer(container, 10)

	# Display Type - option container with toggles
	var type_idx = 0 if _display_type == "stretch" else 1
	var type_hbox = _create_button_group(["Stretch", "Constant"], type_idx, func(idx):
		_display_type = "stretch" if idx == 0 else "constant"
		_apply_display_settings()
		_save_settings()
	)
	var type_container = _create_option_container("Display Type", type_hbox)
	container.add_child(type_container)

	# Resolution - option container with toggles
	var res_idx = 0 if _resolution == "720p" else 1
	var res_hbox = _create_button_group(["720p", "1080p"], res_idx, func(idx):
		_resolution = "720p" if idx == 0 else "1080p"
		_apply_display_settings()
		_save_settings()
	)
	var res_container = _create_option_container("Resolution", res_hbox)
	container.add_child(res_container)

	# Display Mode - option container with toggles
	var mode_idx = 0
	if _display_mode == "fullscreen":
		mode_idx = 0
	elif _display_mode == "borderless":
		mode_idx = 1
	else:
		mode_idx = 2
	var mode_hbox = _create_button_group(["Fullscreen", "Borderless", "Windowed"], mode_idx, func(idx):
		if idx == 0:
			_display_mode = "fullscreen"
		elif idx == 1:
			_display_mode = "borderless"
		else:
			_display_mode = "windowed"
		_apply_display_settings()
		_save_settings()
	)
	var mode_container = _create_option_container("Display Mode", mode_hbox)
	container.add_child(mode_container)

	return scroll

func _build_sound_tab() -> Control:
	"""Build Sound tab with volume sliders"""
	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var container = VBoxContainer.new()
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 12)
	scroll.add_child(container)

	# Title
	var title = Label.new()
	title.text = "SOUND"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_BUBBLE_MAGENTA)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(title)

	_add_spacer(container, 10)

	# Voice Volume - option container with slider
	var voice_slider = _create_volume_slider_row(_volume_voice, func(value):
		_volume_voice = value
		_apply_audio_settings()
		_save_settings()
	)
	var voice_container = _create_option_container("Voice Volume", voice_slider)
	container.add_child(voice_container)

	# Music Volume - option container with slider
	var music_slider = _create_volume_slider_row(_volume_music, func(value):
		_volume_music = value
		_apply_audio_settings()
		_save_settings()
	)
	var music_container = _create_option_container("Music Volume", music_slider)
	container.add_child(music_container)

	# SFX Volume - option container with slider
	var sfx_slider = _create_volume_slider_row(_volume_sfx, func(value):
		_volume_sfx = value
		_apply_audio_settings()
		_save_settings()
	)
	var sfx_container = _create_option_container("SFX Volume", sfx_slider)
	container.add_child(sfx_container)

	# Ambient Volume - option container with slider
	var ambient_slider = _create_volume_slider_row(_volume_ambient, func(value):
		_volume_ambient = value
		_apply_audio_settings()
		_save_settings()
	)
	var ambient_container = _create_option_container("Ambient Volume", ambient_slider)
	container.add_child(ambient_container)

	return scroll

# ==============================================================================
# UI Helper Functions
# ==============================================================================

func _add_spacer(parent: Node, height: float) -> void:
	"""Add a vertical spacer"""
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	parent.add_child(spacer)

func _add_option_label(parent: Node, text: String) -> void:
	"""Add a section label"""
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
	parent.add_child(label)

func _create_option_container(label_text: String, toggle_group: HBoxContainer) -> Control:
	"""Create a focusable container for an option with its label and toggles"""
	# Main container
	var container = Control.new()
	container.custom_minimum_size = Vector2(0, 80)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Panel for visual feedback
	var panel = Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Initial style - subtle border
	var style = aCoreVibeTheme.create_panel_style(
		aCoreVibeTheme.COLOR_SKY_CYAN,
		Color(aCoreVibeTheme.COLOR_NIGHT_NAVY.r, aCoreVibeTheme.COLOR_NIGHT_NAVY.g, aCoreVibeTheme.COLOR_NIGHT_NAVY.b, 0.5),
		0.5,
		aCoreVibeTheme.CORNER_RADIUS_SMALL,
		2,
		aCoreVibeTheme.SHADOW_SIZE_SMALL
	)
	panel.add_theme_stylebox_override("panel", style)
	container.add_child(panel)

	# Store panel reference for highlighting
	container.set_meta("panel", panel)

	# Content margin
	var margin = MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	container.add_child(margin)

	# VBox for label and toggles
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Label
	var label = Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
	vbox.add_child(label)

	# Toggle group
	vbox.add_child(toggle_group)

	return container

func _add_section_header(parent: Node, text: String) -> void:
	"""Add a styled section header for control categories"""
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_SKY_CYAN)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)

func _add_volume_slider(parent: Node, label_text: String, initial_value: float, on_change: Callable) -> void:
	"""Add a volume slider with label and percentage display"""
	# Container for slider row
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 15)
	parent.add_child(row)

	# Label (e.g., "Voice")
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(100, 0)
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
	row.add_child(label)

	# Slider
	var slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = initial_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(300, 30)
	slider.focus_mode = Control.FOCUS_ALL
	row.add_child(slider)

	# Percentage label
	var percent_label = Label.new()
	percent_label.text = "%d%%" % int(initial_value)
	percent_label.custom_minimum_size = Vector2(50, 0)
	percent_label.add_theme_font_size_override("font_size", 16)
	percent_label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
	row.add_child(percent_label)

	# Update percentage label and call callback when slider changes
	slider.value_changed.connect(func(value):
		percent_label.text = "%d%%" % int(value)
		on_change.call(value)
	)

func _create_volume_slider_row(initial_value: float, on_change: Callable) -> HBoxContainer:
	"""Create a volume slider row (without label) for use in option containers"""
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 15)
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	# Slider
	var slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 100.0
	slider.step = 1.0
	slider.value = initial_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(300, 30)
	slider.focus_mode = Control.FOCUS_ALL
	row.add_child(slider)

	# Percentage label
	var percent_label = Label.new()
	percent_label.text = "%d%%" % int(initial_value)
	percent_label.custom_minimum_size = Vector2(60, 0)
	percent_label.add_theme_font_size_override("font_size", 16)
	percent_label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
	row.add_child(percent_label)

	# Update percentage label and call callback when slider changes
	slider.value_changed.connect(func(value):
		percent_label.text = "%d%%" % int(value)
		on_change.call(value)
	)

	return row

func _create_button_group(options: Array, selected_idx: int, on_select: Callable) -> HBoxContainer:
	"""Create a horizontal group of toggle buttons with focus navigation"""
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)

	var buttons: Array[Button] = []

	for i in range(options.size()):
		var btn = Button.new()
		btn.text = str(options[i])
		btn.custom_minimum_size = Vector2(120, 40)
		btn.toggle_mode = true
		btn.button_pressed = (i == selected_idx)
		btn.focus_mode = Control.FOCUS_ALL

		# Style with Sky Cyan accent
		aCoreVibeTheme.style_button_with_focus_invert(btn, aCoreVibeTheme.COLOR_SKY_CYAN, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
		_add_button_padding(btn)

		buttons.append(btn)
		hbox.add_child(btn)

	# Set up button behavior (no horizontal navigation - disabled in content panel)
	for i in range(buttons.size()):
		var btn = buttons[i]

		# Disable left/right neighbors - no horizontal navigation in content panel
		btn.focus_neighbor_left = NodePath()
		btn.focus_neighbor_right = NodePath()

		# When pressed, update all buttons in group
		btn.pressed.connect(func():
			for j in range(hbox.get_child_count()):
				var other_btn = hbox.get_child(j) as Button
				other_btn.button_pressed = (j == i)
			on_select.call(i)
		)

	return hbox

# ==============================================================================
# Restore Defaults Functions
# ==============================================================================

func _restore_game_defaults() -> void:
	"""Restore Game Options tab to defaults"""
	_language = "English"
	_text_speed = 1
	_vibration = true
	_difficulty = 1
	_save_settings()

	# Rebuild the tab to show new values
	if _tab_content.has(Tab.GAME):
		_tab_content[Tab.GAME].queue_free()
		_tab_content[Tab.GAME] = _build_game_options_tab()
		_content_container.add_child(_tab_content[Tab.GAME])
		_switch_tab(Tab.GAME)

	print("[Options] Game options restored to defaults")

func _restore_controls_defaults() -> void:
	"""Restore Controls tab to defaults"""
	_control_type = "keyboard"
	# Reset all input mappings to Godot defaults
	_reset_input_mappings()
	_save_settings()
	print("[Options] Controls restored to defaults")

func _restore_controls_defaults_and_rebuild() -> void:
	"""Restore Controls defaults and rebuild the tab"""
	_restore_controls_defaults()

	# Rebuild the tab to show new values
	if _tab_content.has(Tab.CONTROLS):
		_tab_content[Tab.CONTROLS].queue_free()
		_tab_content[Tab.CONTROLS] = _build_controls_tab()
		_content_container.add_child(_tab_content[Tab.CONTROLS])
		_switch_tab(Tab.CONTROLS)

func _rebuild_controls_tab() -> void:
	"""Rebuild the Controls tab (used when control type changes)"""
	if _tab_content.has(Tab.CONTROLS):
		_tab_content[Tab.CONTROLS].queue_free()
		_tab_content[Tab.CONTROLS] = _build_controls_tab()
		_content_container.add_child(_tab_content[Tab.CONTROLS])
		_switch_tab(Tab.CONTROLS)

func _reset_input_mappings() -> void:
	"""Reset all input action mappings to their defaults"""
	# This is a placeholder - in a real implementation you'd restore from project settings
	# For now we just clear any custom mappings
	print("[Options] Input mappings reset to defaults")

func _build_action_rows(parent: VBoxContainer) -> void:
	"""Build rows for each remappable action, organized by category"""
	_action_data.clear()

	# Define action categories matching original setup
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

	var menu_actions = [
		{"name": "menu_accept", "display": "Accept (A)"},
		{"name": "menu_back", "display": "Back (B)"},
		{"name": "run", "display": "Inspect Item (X)"},
		{"name": "jump", "display": "Discard Item (Y)"},
	]

	# Overworld Controls Section
	_add_section_header(parent, "OVERWORLD")
	var overworld_count = 0
	for action_def in overworld_actions:
		# Create the action if it doesn't exist
		if not InputMap.has_action(action_def["name"]):
			InputMap.add_action(action_def["name"])
		var row = _create_action_row(action_def["name"], action_def["display"])
		parent.add_child(row)
		overworld_count += 1

	if overworld_count > 0:
		_add_spacer(parent, 20)

	# Battle Controls Section
	_add_section_header(parent, "BATTLE")
	var battle_count = 0
	for action_def in battle_actions:
		# Create the action if it doesn't exist
		if not InputMap.has_action(action_def["name"]):
			InputMap.add_action(action_def["name"])
		var row = _create_action_row(action_def["name"], action_def["display"])
		parent.add_child(row)
		battle_count += 1

	if battle_count > 0:
		_add_spacer(parent, 20)

	# Menu Controls Section
	_add_section_header(parent, "MENU")
	var menu_count = 0
	for action_def in menu_actions:
		# Create the action if it doesn't exist
		if not InputMap.has_action(action_def["name"]):
			InputMap.add_action(action_def["name"])
		var row = _create_action_row(action_def["name"], action_def["display"])
		parent.add_child(row)
		menu_count += 1

	print("[Options] Built %d control rows across 3 sections" % _action_data.size())

func _create_action_row(action: String, display_name: String = "") -> HBoxContainer:
	"""Create a row showing an action and its current binding"""
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 15)

	# Action name (use provided display name or format the action name)
	var action_label = Label.new()
	action_label.text = display_name if display_name != "" else _format_action_name(action)
	action_label.custom_minimum_size = Vector2(250, 0)
	action_label.add_theme_font_size_override("font_size", 14)
	action_label.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_MILK_WHITE)
	row.add_child(action_label)

	# Current binding button (locked/view-only)
	var bind_btn = Button.new()
	bind_btn.text = _get_action_display_text(action)
	bind_btn.custom_minimum_size = Vector2(200, 35)
	bind_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bind_btn.focus_mode = Control.FOCUS_NONE  # Disable focus
	bind_btn.disabled = true  # Disable interaction
	aCoreVibeTheme.style_button_with_focus_invert(bind_btn, aCoreVibeTheme.COLOR_SKY_CYAN, aCoreVibeTheme.CORNER_RADIUS_SMALL)
	_add_button_padding(bind_btn)

	# Apply greyed-out styling
	bind_btn.modulate = Color(0.6, 0.6, 0.6, 0.7)  # Grey out the button

	# Store action data for reference (but no remapping)
	var action_idx = _action_data.size()
	_action_data.append({
		"action": action,
		"button": bind_btn,
		"row": row
	})

	# No click handler - buttons are locked

	row.add_child(bind_btn)

	return row

func _format_action_name(action: String) -> String:
	"""Format action name for display (e.g., move_up -> Move Up)"""
	return action.replace("_", " ").capitalize()

func _get_action_display_text(action: String) -> String:
	"""Get display text for current action binding based on control type"""
	var events = InputMap.action_get_events(action)
	if events.size() == 0:
		return "Click to Bind"

	# Filter events based on control type
	var target_event: InputEvent = null

	if _control_type == "keyboard":
		# Look for keyboard event
		for event in events:
			if event is InputEventKey:
				target_event = event
				break
	else:
		# Look for joypad event (any controller type)
		for event in events:
			if event is InputEventJoypadButton or event is InputEventJoypadMotion:
				target_event = event
				break

	# If no event found for selected type, show "Click to Bind"
	if not target_event:
		return "Click to Bind"

	# Display the event
	if target_event is InputEventKey:
		var keycode = target_event.physical_keycode if target_event.physical_keycode != 0 else target_event.keycode
		if keycode == 0:
			return "Click to Bind"
		return OS.get_keycode_string(keycode)
	elif target_event is InputEventJoypadButton:
		return _get_joypad_button_name(target_event.button_index)
	elif target_event is InputEventJoypadMotion:
		return _get_joypad_axis_name(target_event.axis, target_event.axis_value)
	else:
		return "Unknown"

func _get_joypad_button_name(button_index: int) -> String:
	"""Get friendly name for joypad button based on control type"""
	# Xbox naming as default
	match button_index:
		JOY_BUTTON_A: return "A" if _control_type != "playstation" else "X"
		JOY_BUTTON_B: return "B" if _control_type != "playstation" else "Circle"
		JOY_BUTTON_X: return "X" if _control_type != "playstation" else "Square"
		JOY_BUTTON_Y: return "Y" if _control_type != "playstation" else "Triangle"
		JOY_BUTTON_LEFT_SHOULDER: return "LB" if _control_type == "xbox" else "L1"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB" if _control_type == "xbox" else "R1"
		JOY_BUTTON_BACK: return "Back" if _control_type == "xbox" else "Select"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_LEFT_STICK: return "LS"
		JOY_BUTTON_RIGHT_STICK: return "RS"
		JOY_BUTTON_DPAD_UP: return "D-Pad Up"
		JOY_BUTTON_DPAD_DOWN: return "D-Pad Down"
		JOY_BUTTON_DPAD_LEFT: return "D-Pad Left"
		JOY_BUTTON_DPAD_RIGHT: return "D-Pad Right"
		_: return "Button %d" % button_index

func _get_joypad_axis_name(axis: int, value: float) -> String:
	"""Get friendly name for joypad axis"""
	var direction = "+" if value > 0 else "-"
	match axis:
		JOY_AXIS_LEFT_X: return "Left Stick %s X" % direction
		JOY_AXIS_LEFT_Y: return "Left Stick %s Y" % direction
		JOY_AXIS_RIGHT_X: return "Right Stick %s X" % direction
		JOY_AXIS_RIGHT_Y: return "Right Stick %s Y" % direction
		JOY_AXIS_TRIGGER_LEFT: return "LT" if _control_type == "xbox" else "L2"
		JOY_AXIS_TRIGGER_RIGHT: return "RT" if _control_type == "xbox" else "R2"
		_: return "Axis %d %s" % [axis, direction]

func _start_remapping(action_idx: int) -> void:
	"""Start waiting for input to remap an action"""
	if action_idx < 0 or action_idx >= _action_data.size():
		return

	_waiting_for_input = true
	_waiting_action = _action_data[action_idx]["action"]
	_selected_action_index = action_idx

	# Update button text to show we're waiting
	var btn = _action_data[action_idx]["button"] as Button
	if btn:
		btn.text = "Press any key..."

	print("[Options] Waiting for input to remap: %s" % _waiting_action)

func _setup_tab_focus_chain(close_btn: Button) -> void:
	"""Set up vertical-only focus navigation for tab buttons"""
	if _tab_buttons.size() == 0:
		return

	# Connect all tab buttons in a vertical chain
	for i in range(_tab_buttons.size()):
		var current_btn = _tab_buttons[i] as Button
		if not current_btn:
			continue

		# Set up vertical navigation
		if i > 0:
			var prev_btn = _tab_buttons[i - 1] as Button
			if prev_btn:
				current_btn.focus_neighbor_top = current_btn.get_path_to(prev_btn)
				prev_btn.focus_neighbor_bottom = prev_btn.get_path_to(current_btn)

		# Disable horizontal navigation (stay in left panel)
		current_btn.focus_neighbor_left = NodePath()
		current_btn.focus_neighbor_right = NodePath()

	# Connect last tab button to close button
	if _tab_buttons.size() > 0 and close_btn:
		var last_tab_btn = _tab_buttons[_tab_buttons.size() - 1] as Button
		if last_tab_btn:
			last_tab_btn.focus_neighbor_bottom = last_tab_btn.get_path_to(close_btn)
			close_btn.focus_neighbor_top = close_btn.get_path_to(last_tab_btn)

		# Connect close button back to first tab button
		var first_tab_btn = _tab_buttons[0] as Button
		if first_tab_btn:
			close_btn.focus_neighbor_bottom = close_btn.get_path_to(first_tab_btn)
			first_tab_btn.focus_neighbor_top = first_tab_btn.get_path_to(close_btn)

		# Disable horizontal navigation for close button
		close_btn.focus_neighbor_left = NodePath()
		close_btn.focus_neighbor_right = NodePath()

	print("[Options] Tab focus chain set up with %d buttons + close button" % _tab_buttons.size())

func _setup_controls_focus_chain() -> void:
	"""Set up focus navigation chain for control buttons"""
	# Button configs are now disabled/locked, so no focus chain needed
	# Focus will go directly to the Control Style toggle buttons and Restore Defaults button
	print("[Options] Skipping focus chain setup - button configs are disabled")

func _restore_display_defaults() -> void:
	"""Restore Display tab to defaults"""
	_display_type = "stretch"
	_resolution = "1080p"
	_display_mode = "fullscreen"
	_save_settings()
	_apply_display_settings()
	print("[Options] Display settings restored to defaults")

func _restore_display_defaults_and_rebuild() -> void:
	"""Restore Display defaults and rebuild the tab"""
	_restore_display_defaults()

	# Rebuild the tab to show new values
	if _tab_content.has(Tab.DISPLAY):
		_tab_content[Tab.DISPLAY].queue_free()
		_tab_content[Tab.DISPLAY] = _build_display_tab()
		_content_container.add_child(_tab_content[Tab.DISPLAY])
		_switch_tab(Tab.DISPLAY)

func _apply_display_settings() -> void:
	"""Apply display settings to the game window"""
	var window = get_window()
	if not window:
		push_warning("[Options] Could not get window reference")
		return

	# Apply resolution
	var target_size = Vector2i(1920, 1080) if _resolution == "1080p" else Vector2i(1280, 720)

	# Apply display mode
	if _display_mode == "fullscreen":
		window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
	elif _display_mode == "borderless":
		window.mode = Window.MODE_FULLSCREEN
	else:  # windowed
		window.mode = Window.MODE_WINDOWED
		window.size = target_size

	# Apply display type (viewport stretch mode)
	if _display_type == "stretch":
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	else:  # constant
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED

	print("[Options] Applied display settings: %s, %s, %s" % [_display_type, _resolution, _display_mode])

func _restore_sound_defaults() -> void:
	"""Restore Sound tab to defaults"""
	_volume_voice = 100.0
	_volume_music = 100.0
	_volume_sfx = 100.0
	_volume_ambient = 100.0
	_save_settings()
	_apply_audio_settings()
	print("[Options] Sound settings restored to defaults")

func _restore_sound_defaults_and_rebuild() -> void:
	"""Restore Sound defaults and rebuild the tab"""
	_restore_sound_defaults()

	# Rebuild the tab to show new values
	if _tab_content.has(Tab.SOUND):
		_tab_content[Tab.SOUND].queue_free()
		_tab_content[Tab.SOUND] = _build_sound_tab()
		_content_container.add_child(_tab_content[Tab.SOUND])
		_switch_tab(Tab.SOUND)

func _apply_audio_settings() -> void:
	"""Apply audio volume settings to audio buses"""
	# Convert 0-100 percentage to decibel scale
	# 100% = 0 dB (max volume)
	# 0% = -80 dB (effectively silent)
	var voice_db = linear_to_db(_volume_voice / 100.0) if _volume_voice > 0 else -80.0
	var music_db = linear_to_db(_volume_music / 100.0) if _volume_music > 0 else -80.0
	var sfx_db = linear_to_db(_volume_sfx / 100.0) if _volume_sfx > 0 else -80.0
	var ambient_db = linear_to_db(_volume_ambient / 100.0) if _volume_ambient > 0 else -80.0

	# Apply to audio buses if they exist
	var voice_idx = AudioServer.get_bus_index("Voice")
	if voice_idx >= 0:
		AudioServer.set_bus_volume_db(voice_idx, voice_db)

	var music_idx = AudioServer.get_bus_index("Music")
	if music_idx >= 0:
		AudioServer.set_bus_volume_db(music_idx, music_db)

	var sfx_idx = AudioServer.get_bus_index("SFX")
	if sfx_idx >= 0:
		AudioServer.set_bus_volume_db(sfx_idx, sfx_db)

	var ambient_idx = AudioServer.get_bus_index("Ambient")
	if ambient_idx >= 0:
		AudioServer.set_bus_volume_db(ambient_idx, ambient_db)

	print("[Options] Applied audio settings: Voice=%d%%, Music=%d%%, SFX=%d%%, Ambient=%d%%" % [_volume_voice, _volume_music, _volume_sfx, _volume_ambient])
