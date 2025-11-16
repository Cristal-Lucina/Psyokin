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
	var lang_hbox = _create_button_group(["English"], 0, func(_idx): _language = "English"; _save_settings())
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
	title.text = "DISPLAY"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_CITRUS_YELLOW)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(title)

	_add_spacer(container, 10)

	# Display Type
	_add_option_label(container, "Display Type")
	var type_idx = 0 if _display_type == "stretch" else 1
	var type_hbox = _create_button_group(["Stretch", "Constant"], type_idx, func(idx):
		_display_type = "stretch" if idx == 0 else "constant"
		_apply_display_settings()
		_save_settings()
	)
	container.add_child(type_hbox)

	_add_spacer(container, 15)

	# Resolution
	_add_option_label(container, "Resolution")
	var res_idx = 0 if _resolution == "720p" else 1
	var res_hbox = _create_button_group(["720p", "1080p"], res_idx, func(idx):
		_resolution = "720p" if idx == 0 else "1080p"
		_apply_display_settings()
		_save_settings()
	)
	container.add_child(res_hbox)

	_add_spacer(container, 15)

	# Display Mode
	_add_option_label(container, "Display Mode")
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
	container.add_child(mode_hbox)

	# Spacer to push Restore Defaults to bottom
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(spacer)

	# Restore Defaults button
	var restore_btn = Button.new()
	restore_btn.text = "RESTORE DEFAULTS"
	restore_btn.custom_minimum_size = Vector2(200, 45)
	restore_btn.pressed.connect(_restore_display_defaults_and_rebuild)
	aCoreVibeTheme.style_button_with_focus_invert(restore_btn, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
	_add_button_padding(restore_btn)
	var restore_center = CenterContainer.new()
	restore_center.add_child(restore_btn)
	container.add_child(restore_center)

	return scroll

func _build_sound_tab() -> Control:
	"""Build Sound tab with volume sliders"""
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
	title.text = "SOUND"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", aCoreVibeTheme.COLOR_BUBBLE_MAGENTA)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(title)

	_add_spacer(container, 10)

	# Voice Volume
	_add_volume_slider(container, "Voice", _volume_voice, func(value):
		_volume_voice = value
		_apply_audio_settings()
		_save_settings()
	)

	_add_spacer(container, 15)

	# Music Volume
	_add_volume_slider(container, "Music", _volume_music, func(value):
		_volume_music = value
		_apply_audio_settings()
		_save_settings()
	)

	_add_spacer(container, 15)

	# SFX Volume
	_add_volume_slider(container, "SFX", _volume_sfx, func(value):
		_volume_sfx = value
		_apply_audio_settings()
		_save_settings()
	)

	_add_spacer(container, 15)

	# Ambient Volume
	_add_volume_slider(container, "Ambient", _volume_ambient, func(value):
		_volume_ambient = value
		_apply_audio_settings()
		_save_settings()
	)

	# Spacer to push Restore Defaults to bottom
	var spacer = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(spacer)

	# Restore Defaults button
	var restore_btn = Button.new()
	restore_btn.text = "RESTORE DEFAULTS"
	restore_btn.custom_minimum_size = Vector2(200, 45)
	restore_btn.pressed.connect(_restore_sound_defaults_and_rebuild)
	aCoreVibeTheme.style_button_with_focus_invert(restore_btn, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
	_add_button_padding(restore_btn)
	var restore_center = CenterContainer.new()
	restore_center.add_child(restore_btn)
	container.add_child(restore_center)

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

		# Style with Sky Cyan accent
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
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT_STRETCH
	else:  # constant
		get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT

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

