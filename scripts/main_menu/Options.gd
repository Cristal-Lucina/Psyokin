extends Control

## Options menu - accessible from Title screen and System panel
## Tabbed interface with Game Options, Controls, Display, and Sound

@onready var _close_btn: Button = %CloseBtn
@onready var _background: ColorRect = $Background
@onready var _panel: Panel = $CenterContainer/Panel
@onready var _content_container: Control = null  # Will hold the tab content

# Tab management
enum Tab { GAME, CONTROLS, DISPLAY, SOUND }
var _current_tab: Tab = Tab.GAME
var _tab_buttons: Array[Button] = []
var _tab_content: Dictionary = {}  # Tab -> Control node

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
var _input_cooldown_duration: float = 0.2
var _scroll_container: ScrollContainer = null

func _ready() -> void:
	print("[Options] _ready() called - building tabbed interface")

	# Ensure this overlay continues to process even when title is "paused"
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Block all input from reaching the title screen behind this menu
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _background:
		_background.mouse_filter = Control.MOUSE_FILTER_STOP

	# Apply Core Vibe styling to panel
	if _panel:
		_style_panel(_panel)

	# Load settings from aSettings
	_load_settings()

	# Build the tabbed interface
	_build_tabbed_interface()

	print("[Options] Tabbed interface built successfully!")

func _style_panel(panel: Panel) -> void:
	"""Apply Core Vibe neon-kawaii styling to options panel"""
	var style = aCoreVibeTheme.create_panel_style(
		aCoreVibeTheme.COLOR_MILK_WHITE,          # White border
		aCoreVibeTheme.COLOR_NIGHT_NAVY,          # Black background
		1.0,                                       # Full opacity
		aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px rounded corners
		aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
		aCoreVibeTheme.SHADOW_SIZE_LARGE          # 12px glow
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
		_control_type = aSettings.get_setting("control_type", "keyboard")
		_language = aSettings.get_setting("language", "English")
		_text_speed = aSettings.get_setting("text_speed", 1)
		_vibration = aSettings.get_setting("vibration", true)
		_difficulty = aSettings.get_setting("difficulty", 1)
		_display_type = aSettings.get_setting("display_type", "stretch")
		_resolution = aSettings.get_setting("resolution", "1080p")
		_display_mode = aSettings.get_setting("display_mode", "fullscreen")
		_volume_voice = aSettings.get_setting("volume_voice", 100.0)
		_volume_music = aSettings.get_setting("volume_music", 100.0)
		_volume_sfx = aSettings.get_setting("volume_sfx", 100.0)
		_volume_ambient = aSettings.get_setting("volume_ambient", 100.0)

func _save_settings() -> void:
	"""Save settings to aSettings autoload"""
	if has_node("/root/aSettings"):
		aSettings.set_setting("control_type", _control_type)
		aSettings.set_setting("language", _language)
		aSettings.set_setting("text_speed", _text_speed)
		aSettings.set_setting("vibration", _vibration)
		aSettings.set_setting("difficulty", _difficulty)
		aSettings.set_setting("display_type", _display_type)
		aSettings.set_setting("resolution", _resolution)
		aSettings.set_setting("display_mode", _display_mode)
		aSettings.set_setting("volume_voice", _volume_voice)
		aSettings.set_setting("volume_music", _volume_music)
		aSettings.set_setting("volume_sfx", _volume_sfx)
		aSettings.set_setting("volume_ambient", _volume_ambient)
		aSettings.save_settings()

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

	# Left side: Vertical tab bar
	var tab_vbox = VBoxContainer.new()
	tab_vbox.custom_minimum_size = Vector2(180, 0)
	tab_vbox.add_theme_constant_override("separation", 8)
	main_hbox.add_child(tab_vbox)

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
	close_btn.pressed.connect(_on_close_pressed)
	aCoreVibeTheme.style_button_with_focus_invert(close_btn, aCoreVibeTheme.COLOR_GRAPE_VIOLET, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
	_add_button_padding(close_btn)
	tab_vbox.add_child(close_btn)

	# Right side: Content container
	_content_container = Control.new()
	_content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_child(_content_container)

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

func _create_tab_button(parent: Node, label: String, tab: Tab, color: Color) -> void:
	"""Create a tab button"""
	var btn = Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(0, 50)
	btn.pressed.connect(func(): _switch_tab(tab))
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

	print("[Options] Switched to tab: ", tab)

func _on_close_pressed() -> void:
	print("[Options] Closing options menu")
	_save_settings()
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
	container.add_theme_constant_override("separation", 20)
	scroll.add_child(container)

	# Title
	var title = Label.new()
	title.text = "GAME OPTIONS"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_ELECTRIC_LIME)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(title)

	_add_spacer(container, 10)

	# Language
	_add_option_label(container, "Language")
	var lang_hbox = _create_button_group(["English"], 0, func(idx): _language = "English"; _save_settings())
	container.add_child(lang_hbox)

	_add_spacer(container, 15)

	# Text Speed
	_add_option_label(container, "Text Speed")
	var speed_hbox = _create_button_group(["Slow", "Normal", "Fast"], _text_speed, func(idx): _text_speed = idx; _save_settings())
	container.add_child(speed_hbox)

	_add_spacer(container, 15)

	# Vibration
	_add_option_label(container, "Vibration")
	var vib_hbox = _create_button_group(["Off", "On"], 1 if _vibration else 0, func(idx): _vibration = (idx == 1); _save_settings())
	container.add_child(vib_hbox)

	_add_spacer(container, 15)

	# Difficulty
	_add_option_label(container, "Difficulty")
	var diff_hbox = _create_button_group(["Easy", "Normal", "Hard"], _difficulty, func(idx): _difficulty = idx; _save_settings())
	container.add_child(diff_hbox)

	# Spacer to push Restore Defaults to bottom
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(spacer)

	# Restore Defaults button
	var restore_btn = Button.new()
	restore_btn.text = "RESTORE DEFAULTS"
	restore_btn.custom_minimum_size = Vector2(200, 45)
	restore_btn.pressed.connect(_restore_game_defaults)
	aCoreVibeTheme.style_button_with_focus_invert(restore_btn, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
	_add_button_padding(restore_btn)
	var restore_center = CenterContainer.new()
	restore_center.add_child(restore_btn)
	container.add_child(restore_center)

	return scroll

func _build_controls_tab() -> Control:
	"""Build Controls tab with Control Type selector and remapping"""
	var container = VBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 15)

	# TODO: Build controls content
	var label = Label.new()
	label.text = "CONTROLS (Coming Soon)"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(label)

	return container

func _build_display_tab() -> Control:
	"""Build Display tab: Display Type, Resolution, Mode"""
	var container = VBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 15)

	# TODO: Build display content
	var label = Label.new()
	label.text = "DISPLAY (Coming Soon)"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(label)

	return container

func _build_sound_tab() -> Control:
	"""Build Sound tab with volume sliders"""
	var container = VBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_theme_constant_override("separation", 15)

	# TODO: Build sound content
	var label = Label.new()
	label.text = "SOUND (Coming Soon)"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(label)

	return container

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

func _create_button_group(options: Array, selected_idx: int, on_select: Callable) -> HBoxContainer:
	"""Create a horizontal group of toggle buttons"""
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 8)

	for i in range(options.size()):
		var btn = Button.new()
		btn.text = str(options[i])
		btn.custom_minimum_size = Vector2(120, 40)
		btn.toggle_mode = true
		btn.button_pressed = (i == selected_idx)

		# Color based on state
		var color = aCoreVibeTheme.COLOR_SKY_CYAN if i == selected_idx else aCoreVibeTheme.COLOR_INK_CHARCOAL
		aCoreVibeTheme.style_button_with_focus_invert(btn, aCoreVibeTheme.COLOR_SKY_CYAN, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
		_add_button_padding(btn)

		# When pressed, update all buttons in group
		btn.pressed.connect(func():
			for j in range(hbox.get_child_count()):
				var other_btn = hbox.get_child(j) as Button
				other_btn.button_pressed = (j == i)
			on_select.call(i)
		)

		hbox.add_child(btn)

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
	# TODO: Reset input mappings
	_save_settings()
	print("[Options] Controls restored to defaults")

func _restore_display_defaults() -> void:
	"""Restore Display tab to defaults"""
	_display_type = "stretch"
	_resolution = "1080p"
	_display_mode = "fullscreen"
	_save_settings()
	print("[Options] Display settings restored to defaults")

func _restore_sound_defaults() -> void:
	"""Restore Sound tab to defaults"""
	_volume_voice = 100.0
	_volume_music = 100.0
	_volume_sfx = 100.0
	_volume_ambient = 100.0
	_save_settings()
	print("[Options] Sound settings restored to defaults")

# OLD CODE TO BE REMOVED BELOW
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
	_scroll_container = scroll  # Store reference for auto-scrolling
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
		{"name": "run", "display": "Inspect Item (X)"},
		{"name": "jump", "display": "Discard Item (Y)"},
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
	"""Simple input handling - just close on back button for now"""
	# Back button closes menu
	if event.is_action_pressed("menu_back") or (event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed):
		_on_close_pressed()
		get_viewport().set_input_as_handled()
		return

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

		# Auto-scroll to keep selected action visible
		if _scroll_container:
			await get_tree().process_frame  # Wait for layout update
			var button_pos = action.kb_button.global_position.y - _scroll_container.global_position.y
			var button_height = action.kb_button.size.y
			var scroll_height = _scroll_container.size.y
			var current_scroll = _scroll_container.scroll_vertical

			# Calculate if we need to scroll
			var visible_top = current_scroll
			var visible_bottom = current_scroll + scroll_height

			# If button is above visible area, scroll up to it
			if button_pos < visible_top:
				_scroll_container.scroll_vertical = int(button_pos)
			# If button is below visible area, scroll down to it
			elif button_pos + button_height > visible_bottom:
				_scroll_container.scroll_vertical = int(button_pos + button_height - scroll_height)

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
