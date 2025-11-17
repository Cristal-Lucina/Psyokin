extends Control
class_name Battle

## Battle Scene - Main battle screen controller
## Handles UI, combatant display, and player input for combat

@onready var battle_mgr = get_node("/root/aBattleManager")
@onready var gs = get_node("/root/aGameState")
@onready var combat_resolver: CombatResolver = CombatResolver.new()
@onready var csv_loader = get_node("/root/aCSVLoader")
@onready var burst_system = get_node("/root/aBurstSystem")
@onready var minigame_mgr = get_node("/root/aMinigameManager")

## Neon Orchard Color Palette
const COLOR_ELECTRIC_LIME = Color(0.78, 1.0, 0.24)      # #C8FF3D
const COLOR_BUBBLE_MAGENTA = Color(1.0, 0.29, 0.85)     # #FF4AD9
const COLOR_SKY_CYAN = Color(0.30, 0.91, 1.0)           # #4DE9FF
const COLOR_CITRUS_YELLOW = Color(1.0, 0.91, 0.30)      # #FFE84D
const COLOR_PLASMA_TEAL = Color(0.13, 0.89, 0.70)       # #20E3B2
const COLOR_GRAPE_VIOLET = Color(0.54, 0.25, 0.99)      # #8A3FFC
const COLOR_NIGHT_NAVY = Color(0.04, 0.06, 0.10)        # #0A0F1A
const COLOR_INK_CHARCOAL = Color(0.07, 0.09, 0.15)      # #111827
const COLOR_MILK_WHITE = Color(0.96, 0.97, 0.98)        # #F4F7FB

## UI References
@onready var action_menu: Control = %ActionMenu
@onready var battle_log: RichTextLabel = %BattleLog
@onready var burst_gauge_bar: ProgressBar = %BurstGauge
@onready var turn_order_display: VBoxContainer = %TurnOrderDisplay
@onready var switch_button: Button = %SwitchButton

## Combatant display containers
@onready var ally_slots: VBoxContainer = %AllySlots
@onready var enemy_slots: VBoxContainer = %EnemySlots

## Dynamic background elements
var diagonal_bands: ColorRect = null
var grid_overlay: ColorRect = null
var particle_layer: Node2D = null

## Action menu panel state
var is_panel_1_active: bool = true  # Panel 1: GUARD/SKILL/CAPTURE/FIGHT, Panel 2: RUN/BURST/ITEMS/STATUS
var is_panel_switching: bool = false  # True during panel switch animation

## State
var is_battle_ready: bool = false  # True when battle is fully initialized
var current_combatant: Dictionary = {}
var awaiting_target_selection: bool = false
var target_candidates: Array = []
var selected_target_index: int = 0  # Currently selected target in navigation
var skill_definitions: Dictionary = {}  # skill_id -> skill data
var awaiting_skill_selection: bool = false
var awaiting_capture_target: bool = false  # True when selecting target for capture
var awaiting_item_target: bool = false  # True when selecting target for item usage
var skill_to_use: Dictionary = {}  # Selected skill data
var skill_menu_panel: PanelContainer = null  # Skill selection menu
var skill_menu_buttons: Array = []  # Buttons in skill menu for controller navigation
var selected_skill_index: int = 0  # Currently selected skill in menu
var type_menu_panel: PanelContainer = null  # Type selection menu
var type_menu_buttons: Array = []  # Buttons in type menu for controller navigation
var selected_type_index: int = 0  # Currently selected type in menu
var item_menu_panel: PanelContainer = null  # Item selection menu
var item_menu_buttons: Array = []  # Buttons in current item tab for controller navigation
var selected_item_index: int = 0  # Currently selected item in menu
var item_tab_container: TabContainer = null  # Reference to tab container for switching
var confirmation_panel: PanelContainer = null  # Yes/No confirmation dialog
var confirmation_callback: Callable = Callable()  # Callback when user confirms
var awaiting_confirmation: bool = false  # True when confirmation dialog is shown
var confirmation_yes_button: Button = null  # Yes button reference
var confirmation_no_button: Button = null  # No button reference
var item_scroll_container: ScrollContainer = null  # Current tab's scroll container for auto-scrolling
var item_description_label: Label = null  # Item description display
var capture_menu_panel: PanelContainer = null  # Capture selection menu
var capture_menu_buttons: Array = []  # Buttons in capture menu for controller navigation
var selected_capture_index: int = 0  # Currently selected capture item in menu
var burst_menu_panel: PanelContainer = null  # Burst selection menu
var burst_menu_buttons: Array = []  # Buttons in burst menu for controller navigation
var selected_burst_index: int = 0  # Currently selected burst ability in menu
var status_picker_panel: PanelContainer = null  # Status character picker panel
var status_picker_modal: ColorRect = null  # Status picker modal background
var status_picker_buttons: Array = []  # Buttons in status picker for controller navigation
var status_picker_data: Array = []  # Character data for status picker
var selected_status_index: int = 0  # Currently selected character in status picker
var status_details_popup: PanelContainer = null  # Status details popup panel
var status_details_modal: ColorRect = null  # Status details modal background
var current_skill_menu: Array = []  # Current skills in menu
var selected_item: Dictionary = {}  # Selected item data
var selected_burst: Dictionary = {}  # Selected burst ability data
var victory_panel: PanelContainer = null  # Victory screen panel
var victory_scroll: ScrollContainer = null  # Victory screen scroll container for controller scrolling
var is_in_round_transition: bool = false  # True during round transition animations
var combatant_panels: Dictionary = {}  # combatant_id -> PanelContainer for shake animations
var instruction_popup: PanelContainer = null  # Instruction message popup
var instruction_label: Label = null  # Label inside instruction popup

# Input debouncing for joystick sensitivity
var input_cooldown: float = 0.0  # Current cooldown timer
var input_cooldown_duration: float = 0.15  # 150ms between inputs
var action_cooldown: float = 0.0  # Cooldown for action button presses (FIGHT/SKILL/etc)
var action_cooldown_duration: float = 1.0  # 1 second between action button presses

# Message queue system (Pokemon-style message display)
var message_queue: Array[String] = []  # Queue of messages to display
var is_displaying_message: bool = false  # True when waiting for player to continue
var continue_indicator: Label = null  # Visual indicator for "Press A to continue"
var continue_indicator_tween: Tween = null  # Tween for blinking animation
var typewriter_tween: Tween = null  # Tween for character-by-character reveal
var current_message_full: String = ""  # Full message being displayed
var is_typewriter_active: bool = false  # True while text is being revealed

# Turn message builder (accumulate lines for full turn display)
var turn_message_lines: Array[String] = []  # Lines of current turn message

func _ready() -> void:
	print("[Battle] Battle scene loaded")

	# CRITICAL: Disable input processing until fully initialized
	set_process_input(false)

	# Add combat resolver to scene tree
	add_child(combat_resolver)

	# Wait for next frame to ensure all autoloads are ready
	await get_tree().process_frame

	# Create neon-kawaii background elements
	_create_diagonal_background()

	# Update action button labels with mapped keys/buttons
	_update_action_button_labels()

	# Apply neon-kawaii style to action buttons
	_style_action_buttons()
	_update_button_icons()

	# Connect to controller type changed signal to update icons dynamically
	if has_node("/root/aControllerIconLayout"):
		var icon_layout = get_node("/root/aControllerIconLayout")
		if not icon_layout.controller_type_changed.is_connected(_on_controller_type_changed):
			icon_layout.controller_type_changed.connect(_on_controller_type_changed)

	# Apply neon-kawaii style to panels
	_style_panels()

	# Create instruction popup
	_create_instruction_popup()

	# Create continue indicator for message queue
	_create_continue_indicator()

	# Load skill definitions
	_load_skills()

	# Connect to battle manager signals
	battle_mgr.battle_started.connect(_on_battle_started)
	battle_mgr.turn_started.connect(_on_turn_started)
	battle_mgr.turn_ended.connect(_on_turn_ended)
	battle_mgr.round_started.connect(_on_round_started)
	battle_mgr.battle_ended.connect(_on_battle_ended)
	battle_mgr.log_message_requested.connect(log_message)

	# Connect to turn order display signals
	if turn_order_display and turn_order_display.has_signal("animation_completed"):
		turn_order_display.animation_completed.connect(_on_turn_order_animation_completed)

	# Disable and dim action menu initially (but keep it visible)
	_disable_action_menu()

	# Initialize battle with party and enemies
	_initialize_battle()

	# Mark battle as ready for input
	is_battle_ready = true

	# CRITICAL: Now enable input processing
	set_process_input(true)
	print("[Battle] Input processing enabled")

func _update_action_button_labels() -> void:
	"""Update action button labels to show action name + mapped key/button"""
	var button_mappings = [
		{"button": "AttackButton", "name": "Attack", "action": aInputManager.ACTION_ATTACK},
		{"button": "SkillButton", "name": "Skill", "action": aInputManager.ACTION_SKILL},
		{"button": "CaptureButton", "name": "Capture", "action": aInputManager.ACTION_CAPTURE},
		{"button": "DefendButton", "name": "Defend", "action": aInputManager.ACTION_DEFEND},
		{"button": "BurstButton", "name": "Burst", "action": aInputManager.ACTION_BURST},
		{"button": "RunButton", "name": "Run", "action": aInputManager.ACTION_BATTLE_RUN},
		{"button": "ItemButton", "name": "Items", "action": aInputManager.ACTION_ITEMS},
		{"button": "StatusButton", "name": "Status", "action": aInputManager.ACTION_STATUS},
	]

	for mapping in button_mappings:
		var btn = action_menu.get_node_or_null(mapping["button"])
		if btn:
			var key_text = _get_primary_binding_text(mapping["action"])
			btn.text = "%s (%s)" % [mapping["name"], key_text]

func _get_primary_binding_text(action_name: String) -> String:
	"""Get the primary binding text for an action (controller preferred if connected)"""
	if not InputMap.has_action(action_name):
		return "?"

	var events = InputMap.action_get_events(action_name)
	var is_controller_connected = aInputManager.is_controller_connected()

	# Prefer controller button if controller is connected
	if is_controller_connected:
		for event in events:
			if event is InputEventJoypadButton:
				return _get_joypad_button_short_name(event.button_index)

	# Otherwise use keyboard
	for event in events:
		if event is InputEventKey:
			return OS.get_keycode_string(event.keycode)

	return "?"

func _get_joypad_button_short_name(button_index: int) -> String:
	"""Get short name for joypad button"""
	match button_index:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_BACK: return "Select"
		_: return "Btn%d" % button_index

func _style_action_buttons() -> void:
	"""Apply neon-kawaii pill capsule style to action buttons"""
	var button_styles = [
		{"button": "AttackButton", "neon": COLOR_BUBBLE_MAGENTA, "label": "FIGHT"},      # Magenta for damage
		{"button": "SkillButton", "neon": COLOR_SKY_CYAN, "label": "SKILL"},             # Cyan for skills
		{"button": "CaptureButton", "neon": COLOR_GRAPE_VIOLET, "label": "CAPTURE"},     # Violet for special
		{"button": "DefendButton", "neon": COLOR_PLASMA_TEAL, "label": "GUARD"},         # Teal for defense
		{"button": "BurstButton", "neon": COLOR_CITRUS_YELLOW, "label": "BURST"},        # Yellow for burst
		{"button": "RunButton", "neon": COLOR_INK_CHARCOAL, "label": "RUN"},             # Dark for run
		{"button": "ItemButton", "neon": COLOR_ELECTRIC_LIME, "label": "ITEMS"},         # Lime for items
		{"button": "StatusButton", "neon": COLOR_MILK_WHITE, "label": "STATUS"},         # White for status
	]

	for style_data in button_styles:
		var btn = action_menu.get_node_or_null(style_data["button"])
		if btn and btn is Button:
			# Pill capsule shape with high corner radius (20px per design spec)
			var corner_radius = 20

			# Normal state: Dark fill with inner neon stroke
			var style_normal = StyleBoxFlat.new()
			style_normal.bg_color = COLOR_NIGHT_NAVY  # Dark glass fill
			style_normal.border_width_left = 2
			style_normal.border_width_right = 2
			style_normal.border_width_top = 2
			style_normal.border_width_bottom = 2
			style_normal.border_color = style_data["neon"]  # Inner neon stroke
			style_normal.corner_radius_top_left = corner_radius
			style_normal.corner_radius_top_right = corner_radius
			style_normal.corner_radius_bottom_left = corner_radius
			style_normal.corner_radius_bottom_right = corner_radius
			style_normal.shadow_size = 4
			style_normal.shadow_color = Color(style_data["neon"].r, style_data["neon"].g, style_data["neon"].b, 0.4)  # Soft glow

			# Hover state: Brighter fill + thicker border + stronger glow
			var style_hover = StyleBoxFlat.new()
			style_hover.bg_color = COLOR_INK_CHARCOAL.lightened(0.15)  # Slightly brighter
			style_hover.border_width_left = 3
			style_hover.border_width_right = 3
			style_hover.border_width_top = 3
			style_hover.border_width_bottom = 3
			style_hover.border_color = style_data["neon"].lightened(0.2)  # Brighter neon
			style_hover.corner_radius_top_left = corner_radius
			style_hover.corner_radius_top_right = corner_radius
			style_hover.corner_radius_bottom_left = corner_radius
			style_hover.corner_radius_bottom_right = corner_radius
			style_hover.shadow_size = 8  # Stronger glow on hover
			style_hover.shadow_color = Color(style_data["neon"].r, style_data["neon"].g, style_data["neon"].b, 0.6)

			# Pressed state: Darker fill with maintained border
			var style_pressed = StyleBoxFlat.new()
			style_pressed.bg_color = COLOR_NIGHT_NAVY.darkened(0.2)
			style_pressed.border_width_left = 2
			style_pressed.border_width_right = 2
			style_pressed.border_width_top = 2
			style_pressed.border_width_bottom = 2
			style_pressed.border_color = style_data["neon"]
			style_pressed.corner_radius_top_left = corner_radius
			style_pressed.corner_radius_top_right = corner_radius
			style_pressed.corner_radius_bottom_left = corner_radius
			style_pressed.corner_radius_bottom_right = corner_radius
			style_pressed.shadow_size = 2
			style_pressed.shadow_color = Color(style_data["neon"].r, style_data["neon"].g, style_data["neon"].b, 0.3)

			# Apply styles
			btn.add_theme_stylebox_override("normal", style_normal)
			btn.add_theme_stylebox_override("hover", style_hover)
			btn.add_theme_stylebox_override("pressed", style_pressed)
			btn.add_theme_stylebox_override("focus", style_hover)

			# Text in Milk White, all caps
			btn.text = "%s" % style_data["label"]
			btn.add_theme_color_override("font_color", COLOR_MILK_WHITE)
			btn.add_theme_color_override("font_hover_color", COLOR_MILK_WHITE)
			btn.add_theme_color_override("font_pressed_color", COLOR_MILK_WHITE)
			btn.add_theme_color_override("font_focus_color", COLOR_MILK_WHITE)

			# Apply diagonal tilt (10-18 degrees) using rotation
			btn.rotation_degrees = randf_range(-3, 3)  # Subtle variation per button

func _update_button_icons() -> void:
	"""Add controller button icons to the left of each battle action button"""
	var icon_layout = get_node_or_null("/root/aControllerIconLayout")
	if not icon_layout:
		print("[Battle] aControllerIconLayout not found, skipping button icons")
		return

	var controller_type = icon_layout.get_controller_type()
	print("[Battle] Updating button icons for controller type: %s" % controller_type)

	# Map each battle button to its controller button action
	# Different layouts for different controllers due to button position differences
	var button_icon_mappings = []

	if controller_type == "nintendo":
		# Nintendo layout: Fight/Status=(A), Capture/Item=(B), Guard/Run=(Y), Skill/Burst=(X)
		# Note: Nintendo swaps A/B compared to Xbox, so "back" gives A and "accept" gives B
		button_icon_mappings = [
			{"button": "AttackButton", "icon_action": "back"},          # A (right) - Fight
			{"button": "StatusButton", "icon_action": "back"},          # A (right) - Status
			{"button": "CaptureButton", "icon_action": "accept"},       # B (bottom) - Capture
			{"button": "ItemButton", "icon_action": "accept"},          # B (bottom) - Item
			{"button": "DefendButton", "icon_action": "special_1"},     # Y (left) - Guard
			{"button": "RunButton", "icon_action": "special_1"},        # Y (left) - Run
			{"button": "SkillButton", "icon_action": "special_2"},      # X (top) - Skill
			{"button": "BurstButton", "icon_action": "special_2"},      # X (top) - Burst
		]
	else:
		# Xbox/PlayStation layout: Fight/Status=(B), Capture/Item=(A), Guard/Run=(X), Skill/Burst=(Y)
		button_icon_mappings = [
			{"button": "AttackButton", "icon_action": "back"},          # B / Circle - Fight
			{"button": "StatusButton", "icon_action": "back"},          # B / Circle - Status
			{"button": "CaptureButton", "icon_action": "accept"},       # A / Cross - Capture
			{"button": "ItemButton", "icon_action": "accept"},          # A / Cross - Item
			{"button": "DefendButton", "icon_action": "special_1"},     # X / Square - Guard
			{"button": "RunButton", "icon_action": "special_1"},        # X / Square - Run
			{"button": "SkillButton", "icon_action": "special_2"},      # Y / Triangle - Skill
			{"button": "BurstButton", "icon_action": "special_2"},      # Y / Triangle - Burst
		]

	for mapping in button_icon_mappings:
		var btn = action_menu.get_node_or_null(mapping["button"])
		if btn and btn is Button:
			# Clear existing icon to force refresh
			btn.icon = null

			var icon_texture = icon_layout.get_button_icon(mapping["icon_action"])
			if icon_texture:
				# Resize icon to 25x25 pixels
				var image = icon_texture.get_image()
				image.resize(25, 25, Image.INTERPOLATE_LANCZOS)
				var scaled_texture = ImageTexture.create_from_image(image)

				btn.icon = scaled_texture
				btn.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
				btn.expand_icon = false
				# Add some spacing between icon and text
				btn.add_theme_constant_override("h_separation", 8)

	# Add RB icon to switch button
	if switch_button and switch_button is Button:
		# Clear existing icon to force refresh
		switch_button.icon = null

		var icon_texture = icon_layout.get_button_icon("r_bumper")  # RB / R1
		if icon_texture:
			# Resize icon to 25x25 pixels
			var image = icon_texture.get_image()
			image.resize(25, 25, Image.INTERPOLATE_LANCZOS)
			var scaled_texture = ImageTexture.create_from_image(image)

			switch_button.icon = scaled_texture
			switch_button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
			switch_button.expand_icon = false
			# Add some spacing between icon and text
			switch_button.add_theme_constant_override("h_separation", 8)

func _on_controller_type_changed(new_type: String) -> void:
	"""Update button icons when controller type changes"""
	print("[Battle] Controller type changed to: %s, updating button icons..." % new_type)
	_update_button_icons()

func _create_diagonal_background() -> void:
	"""Create neon-kawaii diagonal band background with grid overlay"""
	var background = get_node_or_null("Background")
	if not background:
		return

	# Create diagonal bands using a shader
	diagonal_bands = ColorRect.new()
	diagonal_bands.set_anchors_preset(Control.PRESET_FULL_RECT)
	diagonal_bands.z_index = -10
	diagonal_bands.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Create shader for diagonal bands
	var shader_code = """
shader_type canvas_item;

uniform vec3 color1 = vec3(0.04, 0.06, 0.10);  // Night Navy
uniform vec3 color2 = vec3(0.07, 0.09, 0.15);  // Ink Charcoal
uniform float angle = 0.21;  // ~12 degrees in radians
uniform float band_width = 150.0;

void fragment() {
	vec2 uv = FRAGCOORD.xy;
	float rotated = uv.x * cos(angle) - uv.y * sin(angle);
	float band = mod(rotated, band_width * 2.0);
	float t = smoothstep(0.0, band_width, band) * (1.0 - smoothstep(band_width, band_width * 2.0, band));
	COLOR = vec4(mix(color1, color2, t), 1.0);
}
"""

	var shader = Shader.new()
	shader.code = shader_code
	var shader_material = ShaderMaterial.new()
	shader_material.shader = shader
	diagonal_bands.material = shader_material

	# Insert after the solid black background
	background.add_sibling(diagonal_bands)

	# Create grid overlay
	grid_overlay = ColorRect.new()
	grid_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid_overlay.z_index = -9
	grid_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Create shader for grid pattern
	var grid_shader_code = """
shader_type canvas_item;

uniform float grid_size = 12.0;
uniform float line_width = 1.0;
uniform vec4 grid_color = vec4(0.3, 0.91, 1.0, 0.06);  // Sky Cyan at 6% opacity

void fragment() {
	vec2 uv = FRAGCOORD.xy;
	vec2 grid = mod(uv, grid_size);
	float line = step(grid_size - line_width, grid.x) + step(grid_size - line_width, grid.y);
	COLOR = vec4(grid_color.rgb, grid_color.a * min(line, 1.0));
}
"""

	var grid_shader = Shader.new()
	grid_shader.code = grid_shader_code
	var grid_material = ShaderMaterial.new()
	grid_material.shader = grid_shader
	grid_overlay.material = grid_material

	background.add_sibling(grid_overlay)

	# Create particle layer for ambient stars and dots
	particle_layer = Node2D.new()
	particle_layer.z_index = -8
	add_child(particle_layer)

	# Spawn some ambient particles
	_spawn_ambient_particles()

func _spawn_ambient_particles() -> void:
	"""Spawn slow-drifting star and dot particles"""
	if not particle_layer:
		return

	var viewport_size = get_viewport_rect().size
	var particle_count = 20

	for i in range(particle_count):
		var particle = Control.new()
		particle.custom_minimum_size = Vector2(2, 2)

		# Random position
		particle.position = Vector2(
			randf() * viewport_size.x,
			randf() * viewport_size.y
		)

		# Create a small colored rect
		var rect = ColorRect.new()
		rect.custom_minimum_size = Vector2(2, 2)

		# Random color from palette
		var colors = [COLOR_SKY_CYAN, COLOR_ELECTRIC_LIME, COLOR_CITRUS_YELLOW]
		rect.color = colors[randi() % colors.size()]
		rect.modulate.a = randf_range(0.3, 0.7)

		particle.add_child(rect)
		particle_layer.add_child(particle)

		# Animate slow drift
		var tween = create_tween()
		tween.set_loops()
		var drift_x = randf_range(-50, 50)
		var drift_y = randf_range(20, 60)
		var duration = randf_range(8.0, 15.0)
		tween.tween_property(particle, "position", particle.position + Vector2(drift_x, drift_y), duration)
		tween.tween_property(particle, "position", particle.position, duration)

func _style_panels() -> void:
	"""Apply neon-kawaii style to UI panels"""
	# Style Turn Order Panel with soft rectangle and neon border
	var turn_order_panel = get_node_or_null("TurnOrderPanel")
	if turn_order_panel and turn_order_panel is PanelContainer:
		var style = StyleBoxFlat.new()
		style.bg_color = COLOR_INK_CHARCOAL  # Dark glass fill
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = COLOR_SKY_CYAN  # Cyan neon border
		style.corner_radius_top_left = 12
		style.corner_radius_top_right = 12
		style.corner_radius_bottom_left = 12
		style.corner_radius_bottom_right = 12
		style.shadow_size = 4
		style.shadow_color = Color(COLOR_SKY_CYAN.r, COLOR_SKY_CYAN.g, COLOR_SKY_CYAN.b, 0.3)
		turn_order_panel.add_theme_stylebox_override("panel", style)

		# Style title label in Milk White all caps
		var title_label = turn_order_panel.get_node_or_null("VBox/Title")
		if title_label and title_label is Label:
			title_label.text = "TURN ORDER"
			title_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
			title_label.add_theme_font_size_override("font_size", 12)

	# Style Battle Log Panel (flavor text box)
	var battle_log_panel = get_node_or_null("BattleLogPanel")
	if battle_log_panel and battle_log_panel is PanelContainer:
		var style = StyleBoxFlat.new()
		style.bg_color = COLOR_INK_CHARCOAL  # Dark glass fill
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = COLOR_ELECTRIC_LIME  # Lime neon border
		style.corner_radius_top_left = 12
		style.corner_radius_top_right = 12
		style.corner_radius_bottom_left = 12
		style.corner_radius_bottom_right = 12
		style.shadow_size = 4
		style.shadow_color = Color(COLOR_ELECTRIC_LIME.r, COLOR_ELECTRIC_LIME.g, COLOR_ELECTRIC_LIME.b, 0.3)
		# Add 10px internal padding
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 10
		style.content_margin_bottom = 10
		battle_log_panel.add_theme_stylebox_override("panel", style)

		# Style battle log text in Milk White
		var battle_log_text = battle_log
		if battle_log_text:
			battle_log_text.add_theme_color_override("default_color", COLOR_MILK_WHITE)

	# Style Burst Gauge Panel (Bottom of screen)
	var burst_panel = get_node_or_null("BurstGaugePanel")
	if burst_panel and burst_panel is PanelContainer:
		var style = StyleBoxFlat.new()
		style.bg_color = COLOR_INK_CHARCOAL
		style.border_width_left = 4
		style.border_width_right = 4
		style.border_width_top = 4
		style.border_width_bottom = 4
		style.border_color = COLOR_SKY_CYAN  # Cyan neon border to match minigames
		style.corner_radius_top_left = 12
		style.corner_radius_top_right = 12
		style.corner_radius_bottom_left = 12
		style.corner_radius_bottom_right = 12
		style.shadow_size = 4
		style.shadow_color = Color(COLOR_CITRUS_YELLOW.r, COLOR_CITRUS_YELLOW.g, COLOR_CITRUS_YELLOW.b, 0.3)
		burst_panel.add_theme_stylebox_override("panel", style)

		# Style burst label in Milk White all caps
		var burst_label = burst_panel.get_node_or_null("VBox/BurstLabel")
		if burst_label and burst_label is Label:
			burst_label.text = "BURST GAUGE"
			burst_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)

		# Style burst gauge as pill with gradient fill
		var burst_gauge = burst_gauge_bar
		if burst_gauge:
			var gauge_bg = StyleBoxFlat.new()
			gauge_bg.bg_color = COLOR_INK_CHARCOAL.lightened(0.2)  # Lighter charcoal background for visibility
			gauge_bg.corner_radius_top_left = 8
			gauge_bg.corner_radius_top_right = 8
			gauge_bg.corner_radius_bottom_left = 8
			gauge_bg.corner_radius_bottom_right = 8
			gauge_bg.border_width_left = 1
			gauge_bg.border_width_right = 1
			gauge_bg.border_width_top = 1
			gauge_bg.border_width_bottom = 1
			gauge_bg.border_color = COLOR_SKY_CYAN.darkened(0.3)  # Subtle cyan inner border
			burst_gauge.add_theme_stylebox_override("background", gauge_bg)

			var gauge_fill = StyleBoxFlat.new()
			gauge_fill.bg_color = COLOR_BUBBLE_MAGENTA  # Pink magenta fill
			gauge_fill.corner_radius_top_left = 8
			gauge_fill.corner_radius_top_right = 8
			gauge_fill.corner_radius_bottom_left = 8
			gauge_fill.corner_radius_bottom_right = 8
			burst_gauge.add_theme_stylebox_override("fill", gauge_fill)

func _load_skills() -> void:
	"""Load skill definitions from skills.csv"""
	skill_definitions = csv_loader.load_csv("res://data/skills/skills.csv", "skill_id")
	if skill_definitions and not skill_definitions.is_empty():
		print("[Battle] Loaded %d skill definitions" % skill_definitions.size())
	else:
		push_error("[Battle] Failed to load skills.csv")

func _process(delta: float) -> void:
	"""Update battle state each frame"""
	# Update input cooldown timer
	if input_cooldown > 0:
		input_cooldown -= delta

	# Update action cooldown timer
	if action_cooldown > 0:
		action_cooldown -= delta

func _input(event: InputEvent) -> void:
	"""Handle keyboard/controller input for battle actions and target selection"""
	# Note: Input processing is disabled until battle is fully initialized
	# This function only runs after set_process_input(true) is called in _ready()

	# CRITICAL: Handle message queue continuation FIRST (Pokemon-style)
	# This blocks all other input while messages are displaying
	if is_displaying_message:
		if event.is_action_pressed(aInputManager.ACTION_ACCEPT):
			_continue_to_next_message()
			get_viewport().set_input_as_handled()
		return

	# If victory screen is showing, handle scrolling and accept
	if victory_panel != null:
		# Check cooldown to prevent rapid inputs
		if input_cooldown > 0:
			return

		# Scroll with directional buttons
		if victory_scroll:
			var scroll_speed = 30.0  # Pixels to scroll per input
			if event.is_action_pressed(aInputManager.ACTION_MOVE_UP):
				victory_scroll.scroll_vertical -= scroll_speed
				input_cooldown = input_cooldown_duration
				get_viewport().set_input_as_handled()
				return
			elif event.is_action_pressed(aInputManager.ACTION_MOVE_DOWN):
				victory_scroll.scroll_vertical += scroll_speed
				input_cooldown = input_cooldown_duration
				get_viewport().set_input_as_handled()
				return

		# Accept button to exit
		if event.is_action_pressed(aInputManager.ACTION_ACCEPT):
			_on_victory_accept_pressed()
			get_viewport().set_input_as_handled()
		return

	# CRITICAL: Block ALL input if a minigame is active
	if minigame_mgr.current_minigame != null:
		return

	# CRITICAL: If confirmation dialog is showing, only allow Yes/No navigation
	if awaiting_confirmation and confirmation_panel != null:
		if event.is_action_pressed(aInputManager.ACTION_MOVE_LEFT) or event.is_action_pressed(aInputManager.ACTION_MOVE_RIGHT):
			# Toggle focus between Yes and No buttons
			if confirmation_yes_button and confirmation_no_button:
				if confirmation_yes_button.has_focus():
					confirmation_no_button.grab_focus()
				else:
					confirmation_yes_button.grab_focus()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_ACCEPT):
			# Trigger the focused button
			if confirmation_yes_button and confirmation_yes_button.has_focus():
				_on_confirmation_yes()
			elif confirmation_no_button and confirmation_no_button.has_focus():
				_on_confirmation_no()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_BACK):
			# Back button acts as "No"
			_on_confirmation_no()
			get_viewport().set_input_as_handled()
			return
		# Block all other input
		get_viewport().set_input_as_handled()
		return

	# Check for back button to close any open menus
	if event.is_action_pressed(aInputManager.ACTION_BACK):
		# Check if any menu is open and close it
		if type_menu_panel != null:
			_on_type_menu_cancel()
			get_viewport().set_input_as_handled()
			return
		elif skill_menu_panel != null:
			_close_skill_menu()
			get_viewport().set_input_as_handled()
			return
		elif item_menu_panel != null:
			_close_item_menu()
			get_viewport().set_input_as_handled()
			return
		elif capture_menu_panel != null:
			_close_capture_menu()
			get_viewport().set_input_as_handled()
			return
		elif burst_menu_panel != null:
			_close_burst_menu()
			get_viewport().set_input_as_handled()
			return
		elif status_details_popup != null:
			_close_status_details()
			get_viewport().set_input_as_handled()
			return
		elif status_picker_panel != null:
			_close_status_picker()
			get_viewport().set_input_as_handled()
			return
		# If in target selection, cancel it
		elif awaiting_target_selection and not target_candidates.is_empty():
			_cancel_target_selection()
			get_viewport().set_input_as_handled()
			return

	# If type menu is open, handle controller navigation
	if type_menu_panel != null and not type_menu_buttons.is_empty():
		# Check cooldown to prevent rapid inputs
		if input_cooldown > 0:
			return

		if event.is_action_pressed(aInputManager.ACTION_MOVE_UP):
			_navigate_type_menu(-1)
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_MOVE_DOWN):
			_navigate_type_menu(1)
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_ACCEPT):
			_confirm_type_selection()
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_BACK):
			_on_type_menu_cancel()
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return

	# If skill menu is open, handle controller navigation
	if skill_menu_panel != null and not skill_menu_buttons.is_empty():
		# Check cooldown to prevent rapid inputs
		if input_cooldown > 0:
			return

		if event.is_action_pressed(aInputManager.ACTION_MOVE_UP):
			_navigate_skill_menu(-1)
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_MOVE_DOWN):
			_navigate_skill_menu(1)
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_ACCEPT):
			_confirm_skill_selection()
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return

	# If capture menu is open, handle controller navigation (2D grid)
	if capture_menu_panel != null and not capture_menu_buttons.is_empty():
		# Check cooldown to prevent rapid inputs
		if input_cooldown > 0:
			return

		if event.is_action_pressed(aInputManager.ACTION_MOVE_UP):
			_navigate_capture_menu_vertical(-2)  # Move up one row (2 columns)
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_MOVE_DOWN):
			_navigate_capture_menu_vertical(2)  # Move down one row (2 columns)
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_MOVE_LEFT):
			_navigate_capture_menu_horizontal(-1)  # Move left one column
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_MOVE_RIGHT):
			_navigate_capture_menu_horizontal(1)  # Move right one column
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_ACCEPT):
			_confirm_capture_selection()
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return

	# If burst menu is open, handle controller navigation
	if burst_menu_panel != null and not burst_menu_buttons.is_empty():
		# Check cooldown to prevent rapid inputs
		if input_cooldown > 0:
			return

		if event.is_action_pressed(aInputManager.ACTION_MOVE_UP):
			_navigate_burst_menu(-1)
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_MOVE_DOWN):
			_navigate_burst_menu(1)
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_ACCEPT):
			_confirm_burst_selection()
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return

	# If item menu is open, handle controller navigation
	if item_menu_panel != null:
		# Check cooldown to prevent rapid inputs
		if input_cooldown > 0:
			return

		if event.is_action_pressed(aInputManager.ACTION_MOVE_UP):
			_navigate_item_menu(-1)
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_MOVE_DOWN):
			_navigate_item_menu(1)
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_MOVE_LEFT):
			_navigate_item_menu_horizontal(-1)
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_MOVE_RIGHT):
			_navigate_item_menu_horizontal(1)
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_BURST):  # L bumper
			_switch_item_tab(-1)
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_BATTLE_RUN):  # R bumper
			_switch_item_tab(1)
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_ACCEPT):
			_confirm_item_selection()
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return

	# If status details popup is open, handle B button to close (PRIORITY CHECK - must come before status picker)
	if status_details_popup != null:
		if event.is_action_pressed(aInputManager.ACTION_BACK):
			_close_status_details()
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_ACCEPT):
			_close_status_details()
			get_viewport().set_input_as_handled()
			return
		# Block ALL other input when status details are open
		get_viewport().set_input_as_handled()
		return

	# If status picker is open, handle controller navigation
	if status_picker_panel != null and not status_picker_buttons.is_empty():
		# Check cooldown to prevent rapid inputs
		if input_cooldown > 0:
			return

		if event.is_action_pressed(aInputManager.ACTION_MOVE_UP):
			_navigate_status_picker(-1)
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_MOVE_DOWN):
			_navigate_status_picker(1)
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_ACCEPT):
			_confirm_status_selection()
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return
		elif event.is_action_pressed(aInputManager.ACTION_BACK):
			_close_status_picker()
			input_cooldown = input_cooldown_duration
			get_viewport().set_input_as_handled()
			return

	# If awaiting target selection, handle navigation
	if awaiting_target_selection and not target_candidates.is_empty():
		if event.is_action_pressed(aInputManager.ACTION_MOVE_LEFT):
			_navigate_targets(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(aInputManager.ACTION_MOVE_RIGHT):
			_navigate_targets(1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed(aInputManager.ACTION_ACCEPT):
			_confirm_target_selection()
			get_viewport().set_input_as_handled()
		return

	# If action menu is visible, handle direct button presses
	if action_menu and action_menu.visible and not is_in_round_transition:
		# Check for panel switching with L1/R1 shoulder buttons
		# L1 = button index 9, R1 = button index 10
		# Block input during panel switch animation
		if event is InputEventJoypadButton:
			if event.pressed and (event.button_index == 9 or event.button_index == 10):  # L1 or R1
				if not is_panel_switching:  # Only allow if not currently animating
					_toggle_action_panel()
				get_viewport().set_input_as_handled()
				return

		# Handle diamond button inputs based on active panel
		# Panel 1: GUARD/SKILL/CAPTURE/FIGHT
		# Panel 2: RUN/BURST/ITEMS/STATUS
		# Button mapping: Y=SKILL, X=DEFEND, B=ATTACK, A=CAPTURE

		# Check action cooldown to prevent button spam
		if action_cooldown > 0:
			return

		if is_panel_1_active:
			# Panel 1 active
			if event.is_action_pressed(aInputManager.ACTION_SKILL):  # Y button -> Skill
				_on_skill_pressed()
				action_cooldown = action_cooldown_duration  # Set cooldown
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed(aInputManager.ACTION_DEFEND):  # X button -> Guard
				_on_defend_pressed()
				action_cooldown = action_cooldown_duration  # Set cooldown
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed(aInputManager.ACTION_ATTACK):  # B button -> Fight
				_on_attack_pressed()
				action_cooldown = action_cooldown_duration  # Set cooldown
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed(aInputManager.ACTION_CAPTURE):  # A button -> Capture
				_on_capture_pressed()
				action_cooldown = action_cooldown_duration  # Set cooldown
				get_viewport().set_input_as_handled()
		else:
			# Panel 2 active
			if event.is_action_pressed(aInputManager.ACTION_SKILL):  # Y button -> Burst
				_on_burst_pressed()
				action_cooldown = action_cooldown_duration  # Set cooldown
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed(aInputManager.ACTION_DEFEND):  # X button -> Run
				_on_run_pressed()
				action_cooldown = action_cooldown_duration  # Set cooldown
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed(aInputManager.ACTION_ATTACK):  # B button -> Status
				_on_status_pressed()
				action_cooldown = action_cooldown_duration  # Set cooldown
				get_viewport().set_input_as_handled()
			elif event.is_action_pressed(aInputManager.ACTION_CAPTURE):  # A button -> Items
				_on_item_pressed()
				action_cooldown = action_cooldown_duration  # Set cooldown
				get_viewport().set_input_as_handled()

func _navigate_targets(direction: int) -> void:
	"""Navigate through target candidates"""
	if target_candidates.is_empty():
		return

	# Update selected index
	selected_target_index += direction

	# Wrap around
	if selected_target_index < 0:
		selected_target_index = target_candidates.size() - 1
	elif selected_target_index >= target_candidates.size():
		selected_target_index = 0

	# Update visual highlights
	_highlight_target_candidates()

	# Log current target
	var target = target_candidates[selected_target_index]
	log_message("→ %s" % target.display_name)

func _confirm_target_selection() -> void:
	"""Confirm the currently selected target"""
	if target_candidates.is_empty() or selected_target_index < 0 or selected_target_index >= target_candidates.size():
		return

	var target = target_candidates[selected_target_index]

	# Determine what action to execute based on state
	if awaiting_capture_target:
		# Show CAPTURE! instruction
		_show_instruction("CAPTURE!")
		# Attempting capture
		await _execute_capture(target)
	elif awaiting_item_target:
		# Using an item
		_execute_item_usage(target)
	elif awaiting_skill_selection:
		# Using a skill
		_hide_instruction()
		_clear_target_highlights()
		awaiting_target_selection = false
		awaiting_skill_selection = false
		await _execute_skill_single(target)

		# Check if battle is over
		var battle_ended = await battle_mgr._check_battle_end()
		if not battle_ended:
			battle_mgr.end_turn()
	elif not selected_burst.is_empty():
		# Using a burst ability (single target)
		_clear_target_highlights()
		awaiting_target_selection = false
		await _execute_burst_on_target(target)

		# Check if battle is over
		var battle_ended = await battle_mgr._check_battle_end()
		if not battle_ended:
			battle_mgr.end_turn()
	else:
		# Regular attack
		_execute_attack(target)

func _cancel_target_selection() -> void:
	"""Cancel target selection and return to action menu"""
	awaiting_target_selection = false
	awaiting_capture_target = false
	awaiting_item_target = false
	selected_target_index = 0
	_clear_target_highlights()
	log_message("Target selection cancelled.")

func _initialize_battle() -> void:
	"""Initialize the battle from encounter data"""
	log_message("Battle Start!")

	# Get party from GameState
	var party = gs.party.duplicate()
	if party.is_empty():
		# Fallback: use hero
		party = ["hero"]

	# Get enemies from encounter data
	var enemies = battle_mgr.encounter_data.get("enemy_ids", ["slime"])

	# Initialize battle
	battle_mgr.initialize_battle(party, enemies)

## ═══════════════════════════════════════════════════════════════
## BATTLE MANAGER SIGNAL HANDLERS
## ═══════════════════════════════════════════════════════════════

func _on_battle_started() -> void:
	"""Called when battle initializes"""
	print("[Battle] Battle started")
	_display_combatants()
	_update_burst_gauge()

func _on_round_started(round_number: int) -> void:
	"""Called at start of each round"""
	log_message("=== Round %d ===" % round_number)

	# Disable all input during round transition
	_disable_all_input()

func _on_turn_started(combatant_id: String) -> void:
	"""Called when a combatant's turn starts"""
	current_combatant = battle_mgr.get_combatant_by_id(combatant_id)

	if current_combatant.is_empty():
		return

	# Reset action cooldown at start of turn
	action_cooldown = 0.0

	# Queue turn announcement message
	log_message("%s's turn!" % current_combatant.display_name)

	# Wait for player to press continue before proceeding
	await _wait_for_message_queue()

	# Check if combatant is asleep - skip turn entirely
	var ailment = str(current_combatant.get("ailment", ""))
	if ailment == "sleep":
		log_message("%s is fast asleep..." % current_combatant.display_name)
		# Wait a moment for readability
		await _wait_for_message_queue()
		# End turn immediately
		battle_mgr.end_turn()
		return

	# Check for Berserk - attack random target (including allies)
	if ailment == "berserk":
		if current_combatant.is_ally:
			log_message("%s is berserk and attacks wildly!" % current_combatant.display_name)
			await _wait_for_message_queue()
			await _execute_berserk_action()
			return
		else:
			# Enemies with berserk just attack normally (already random)
			await _execute_enemy_ai()
			return

	# Check for Charm - use heal/buff items on enemy
	if ailment == "charm":
		if current_combatant.is_ally:
			log_message("%s is charmed and aids the enemy!" % current_combatant.display_name)
			await _wait_for_message_queue()
			await _execute_charm_action()
			return
		else:
			# Enemies with charm do nothing (have no heal items to use on player)
			log_message("%s is charmed but has no way to help!" % current_combatant.display_name)
			await _wait_for_message_queue()
			battle_mgr.end_turn()
			return

	if current_combatant.is_ally:
		# Player's turn - show action menu
		_show_action_menu()
	else:
		# Enemy turn - execute AI (after player continues)
		await _execute_enemy_ai()

func _on_turn_ended(_combatant_id: String) -> void:
	"""Called when a combatant's turn ends"""
	# Disable and dim action menu
	_disable_action_menu()

func _on_turn_order_animation_completed() -> void:
	"""Called when turn order display animation completes (e.g., round transitions)"""
	# Re-enable input after round transition animation completes
	if is_in_round_transition:
		_enable_all_input()

func _on_battle_ended(victory: bool) -> void:
	"""Called when battle ends"""
	if victory:
		log_message("*** VICTORY ***")
		log_message("All enemies have been defeated!")
		_show_victory_screen()
	else:
		log_message("*** DEFEAT ***")
		log_message("Your party has been wiped out!")
		log_message("GAME OVER")
		# TODO: Show game over screen with retry/load options
		await get_tree().create_timer(3.0).timeout
		# For now, return to main menu or reload
		get_tree().change_scene_to_file("res://scenes/main/Main.tscn")

func _show_victory_screen() -> void:
	"""Display victory screen with Accept button"""
	# Create black background overlay (covers entire viewport)
	var black_bg = ColorRect.new()
	black_bg.color = Color(0, 0, 0, 0)  # Start transparent
	black_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	black_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(black_bg)

	# Fade in black background to fully opaque
	var bg_tween = create_tween()
	bg_tween.set_ease(Tween.EASE_OUT)
	bg_tween.set_trans(Tween.TRANS_CUBIC)
	bg_tween.tween_property(black_bg, "color:a", 1.0, 0.5)  # Fade to 100% opacity (fully black)

	# Create victory panel
	victory_panel = PanelContainer.new()
	victory_panel.name = "VictoryPanel"

	# Set up styling with Core vibe
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_INK_CHARCOAL
	style.border_width_left = 3
	style.border_width_top = 3
	style.border_width_right = 3
	style.border_width_bottom = 3
	style.border_color = COLOR_SKY_CYAN  # Cyan neon border
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_size = 6
	style.shadow_color = Color(COLOR_SKY_CYAN.r, COLOR_SKY_CYAN.g, COLOR_SKY_CYAN.b, 0.4)  # Cyan glow
	victory_panel.add_theme_stylebox_override("panel", style)

	# Position it in center of screen (200px wider)
	victory_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	victory_panel.custom_minimum_size = Vector2(700, 450)  # Increased width by 200px
	victory_panel.size = Vector2(700, 450)
	victory_panel.position = Vector2(-350, -225)  # Center the 700x450 panel
	victory_panel.modulate.a = 0.0  # Start transparent for fade-in

	# Create vertical box for content
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	victory_panel.add_child(vbox)

	# Add some padding
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	vbox.add_child(margin)

	var content_vbox = VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 15)
	margin.add_child(content_vbox)

	# Title label
	var title_label = Label.new()
	title_label.text = "VICTORY!"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32)
	title_label.add_theme_color_override("font_color", COLOR_BUBBLE_MAGENTA)  # Pink magenta title
	content_vbox.add_child(title_label)

	# Get rewards data from battle manager
	var rewards = battle_mgr.battle_rewards

	# Rewards display (scrollable) - increased width for 2 columns
	var rewards_scroll = ScrollContainer.new()
	rewards_scroll.custom_minimum_size = Vector2(660, 200)  # Wider for 2 columns
	rewards_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rewards_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	content_vbox.add_child(rewards_scroll)

	# Store reference for controller scrolling
	victory_scroll = rewards_scroll

	# Create HBox for 2 columns
	var rewards_hbox = HBoxContainer.new()
	rewards_hbox.add_theme_constant_override("separation", 20)
	rewards_scroll.add_child(rewards_hbox)

	# Column 1: CREDS, Level Growth, Enemies
	var column1 = VBoxContainer.new()
	column1.add_theme_constant_override("separation", 5)
	column1.custom_minimum_size = Vector2(320, 0)
	rewards_hbox.add_child(column1)

	# Column 2: Sigil Growth, Affinity Growth, Items
	var column2 = VBoxContainer.new()
	column2.add_theme_constant_override("separation", 5)
	column2.custom_minimum_size = Vector2(320, 0)
	rewards_hbox.add_child(column2)

	# CREDS (changed from Credits) - Column 1
	if rewards.get("creds", 0) > 0:
		var creds_label = Label.new()
		creds_label.text = "CREDS: +%d" % rewards.creds
		creds_label.add_theme_color_override("font_color", COLOR_CITRUS_YELLOW)  # Yellow for creds
		column1.add_child(creds_label)

	# Level Growth - Show LXP for all members who received it
	var lxp_awarded = rewards.get("lxp_awarded", {})
	print("[Battle] lxp_awarded: %s" % lxp_awarded)

	if not lxp_awarded.is_empty():
		var lxp_header = Label.new()
		lxp_header.text = "\nLevel Growth:"
		lxp_header.add_theme_color_override("font_color", COLOR_ELECTRIC_LIME)  # Lime green header
		column1.add_child(lxp_header)

		# Show all members who got XP (they were in the battle)
		for member_id in lxp_awarded.keys():
			var xp_amount = lxp_awarded[member_id]
			var display_name = _get_member_display_name(member_id)
			var member_label = Label.new()
			member_label.text = "  %s: +%d LXP" % [display_name, xp_amount]
			member_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
			column1.add_child(member_label)

	# Sigil Growth - Show each sigil individually with names - Column 2
	var gxp_awarded = rewards.get("gxp_awarded", {})
	if not gxp_awarded.is_empty():
		var gxp_header = Label.new()
		gxp_header.text = "\nSigil Growth:"
		gxp_header.add_theme_color_override("font_color", COLOR_SKY_CYAN)  # Cyan header
		column2.add_child(gxp_header)

		var sigil_sys = get_node_or_null("/root/aSigilSystem")
		for sigil_inst_id in gxp_awarded.keys():
			var gxp_amount = gxp_awarded[sigil_inst_id]
			var sigil_name = "Unknown Sigil"
			if sigil_sys and sigil_sys.has_method("get_display_name_for"):
				sigil_name = sigil_sys.get_display_name_for(sigil_inst_id)

			var sigil_label = Label.new()
			sigil_label.text = "  %s: +%d GXP" % [sigil_name, gxp_amount]
			sigil_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
			column2.add_child(sigil_label)

	# Affinity Growth - Show AXP for each pair - Column 2
	var axp_awarded = rewards.get("axp_awarded", {})
	if not axp_awarded.is_empty():
		var axp_header = Label.new()
		axp_header.text = "\nAffinity Growth:"
		axp_header.add_theme_color_override("font_color", COLOR_BUBBLE_MAGENTA)  # Pink magenta header
		column2.add_child(axp_header)

		for pair_key in axp_awarded.keys():
			var axp_amount = axp_awarded[pair_key]

			# Split pair key back into member IDs
			var members = pair_key.split("|")
			if members.size() != 2:
				continue

			var name_a = _get_member_display_name(members[0])
			var name_b = _get_member_display_name(members[1])

			var axp_label = Label.new()
			axp_label.text = "  %s ↔ %s: +%d AXP" % [name_a, name_b, axp_amount]
			axp_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
			column2.add_child(axp_label)

	# Items - Column 2
	var items = rewards.get("items", [])
	if not items.is_empty():
		var items_header = Label.new()
		items_header.text = "\nItems Dropped:"
		items_header.add_theme_color_override("font_color", COLOR_GRAPE_VIOLET)  # Violet header
		column2.add_child(items_header)

		for item_id in items:
			var item_label = Label.new()
			item_label.text = "  %s" % item_id
			item_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
			column2.add_child(item_label)

	# Battle stats - Column 1
	var stats_label = Label.new()
	var captured = rewards.get("captured_count", 0)
	var killed = rewards.get("killed_count", 0)
	stats_label.text = "\nEnemies: %d captured, %d defeated" % [captured, killed]
	stats_label.add_theme_font_size_override("font_size", 14)
	stats_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
	column1.add_child(stats_label)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	content_vbox.add_child(spacer)

	# Accept button with Core vibe styling
	var accept_button = Button.new()
	accept_button.text = "Accept"
	accept_button.custom_minimum_size = Vector2(200, 50)
	accept_button.pressed.connect(_on_victory_accept_pressed)

	# Style the button
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = COLOR_SKY_CYAN.darkened(0.3)  # Dark cyan background
	btn_style.border_width_left = 2
	btn_style.border_width_right = 2
	btn_style.border_width_top = 2
	btn_style.border_width_bottom = 2
	btn_style.border_color = COLOR_SKY_CYAN  # Bright cyan border
	btn_style.corner_radius_top_left = 8
	btn_style.corner_radius_top_right = 8
	btn_style.corner_radius_bottom_left = 8
	btn_style.corner_radius_bottom_right = 8
	accept_button.add_theme_stylebox_override("normal", btn_style)

	var btn_style_hover = StyleBoxFlat.new()
	btn_style_hover.bg_color = COLOR_SKY_CYAN.darkened(0.1)  # Brighter on hover
	btn_style_hover.border_width_left = 3
	btn_style_hover.border_width_right = 3
	btn_style_hover.border_width_top = 3
	btn_style_hover.border_width_bottom = 3
	btn_style_hover.border_color = COLOR_SKY_CYAN.lightened(0.2)
	btn_style_hover.corner_radius_top_left = 8
	btn_style_hover.corner_radius_top_right = 8
	btn_style_hover.corner_radius_bottom_left = 8
	btn_style_hover.corner_radius_bottom_right = 8
	accept_button.add_theme_stylebox_override("hover", btn_style_hover)
	accept_button.add_theme_stylebox_override("focus", btn_style_hover)

	accept_button.add_theme_color_override("font_color", COLOR_MILK_WHITE)
	accept_button.add_theme_font_size_override("font_size", 18)

	# Center the button
	var button_center = CenterContainer.new()
	button_center.add_child(accept_button)
	content_vbox.add_child(button_center)

	# Add to scene
	add_child(victory_panel)

	# Fade in victory panel
	var panel_tween = create_tween()
	panel_tween.set_ease(Tween.EASE_OUT)
	panel_tween.set_trans(Tween.TRANS_CUBIC)
	panel_tween.tween_property(victory_panel, "modulate:a", 1.0, 0.5).set_delay(0.3)  # Slight delay after background

func _on_victory_accept_pressed() -> void:
	"""Handle Accept button press on victory screen"""
	print("[Battle] Victory accepted - returning to overworld")
	if victory_panel:
		victory_panel.queue_free()
		victory_panel = null
	victory_scroll = null
	battle_mgr.return_to_overworld()

func _get_member_display_name(member_id: String) -> String:
	"""Get display name for a party member"""
	# Special case for hero - get player name
	if member_id == "hero":
		return _get_hero_display_name()

	# Check combatants first for display names from battle
	for combatant in battle_mgr.combatants:
		if combatant.get("id", "") == member_id:
			return combatant.get("display_name", member_id)

	# Fallback to member_id
	return member_id

func _get_hero_display_name() -> String:
	"""Get the hero/player character's first name"""
	# Try to get from GameState
	if gs and gs.has_method("get"):
		var player_name_var = gs.get("player_name")
		if player_name_var and typeof(player_name_var) == TYPE_STRING:
			var player_name = String(player_name_var).strip_edges()
			if player_name != "":
				# Extract first name only
				var space_index: int = player_name.find(" ")
				if space_index > 0:
					return player_name.substr(0, space_index)
				return player_name

	# Try current combatant (already has first name from BattleManager)
	if current_combatant.get("id", "") == "hero":
		var display = current_combatant.get("display_name", "")
		if display != "":
			return display

	# Fallback
	return "Hero"

func _check_freeze_action_allowed() -> bool:
	"""Check if a frozen/malaise combatant's action can proceed (30% chance)"""
	var ailment = str(current_combatant.get("ailment", ""))

	if ailment not in ["freeze", "malaise"]:
		return true  # Not frozen or malaise, action always allowed

	# Frozen/Malaise: 30% chance to act
	var success_chance = 30
	var roll = randi() % 100

	var ailment_name = "freeze" if ailment == "freeze" else "malaise"

	if roll < success_chance:
		log_message("  → %s struggles through the %s! (%d%% chance, rolled %d)" % [
			current_combatant.display_name, ailment_name, success_chance, roll
		])
		return true
	else:
		log_message("  → %s is unable to act due to %s! (%d%% chance, rolled %d)" % [
			current_combatant.display_name, ailment_name, success_chance, roll
		])
		# End turn without acting
		battle_mgr.end_turn()
		return false

func _wake_if_asleep(target: Dictionary) -> void:
	"""Wake up a target if they're asleep (called when taking damage)"""
	var ailment = str(target.get("ailment", ""))

	if ailment == "sleep":
		target.ailment = ""
		target.ailment_turn_count = 0
		log_message("  → %s woke up from the hit!" % target.display_name)
		# Refresh turn order to remove sleep indicator
		if battle_mgr:
			battle_mgr.refresh_turn_order()

func _set_fainted(target: Dictionary) -> void:
	"""Mark a combatant as fainted (KO'd) and set Fainted status ailment"""
	target.is_ko = true
	target.ailment = "fainted"
	target.ailment_turn_count = 0
	# Refresh turn order to show fainted status
	if battle_mgr:
		battle_mgr.refresh_turn_order()

func _set_captured(target: Dictionary) -> void:
	"""Mark a combatant as captured and set Captured status ailment"""
	target.is_ko = true
	target.is_captured = true
	target.ailment = "captured"
	target.ailment_turn_count = 0
	# Refresh turn order to show captured status
	if battle_mgr:
		battle_mgr.refresh_turn_order()

## ═══════════════════════════════════════════════════════════════
## COMBATANT DISPLAY
## ═══════════════════════════════════════════════════════════════

func _display_combatants() -> void:
	"""Display all combatants in their slots"""
	# Clear existing displays
	for child in ally_slots.get_children():
		child.queue_free()
	for child in enemy_slots.get_children():
		child.queue_free()

	# Clear panel references
	combatant_panels.clear()

	# Display allies
	var allies = battle_mgr.get_ally_combatants()
	for ally in allies:
		var slot = _create_combatant_slot(ally, true)
		ally_slots.add_child(slot)
		combatant_panels[ally.id] = slot

	# Display enemies
	var enemies = battle_mgr.get_enemy_combatants()
	for enemy in enemies:
		var slot = _create_combatant_slot(enemy, false)
		enemy_slots.add_child(slot)
		combatant_panels[enemy.id] = slot

func _create_combatant_slot(combatant: Dictionary, is_ally: bool) -> PanelContainer:
	"""Create a UI slot for a combatant with neon-kawaii sticker aesthetic"""
	var panel = PanelContainer.new()

	# Hide KO'd enemies - move off screen and make invisible
	if not is_ally and combatant.get("is_ko", false):
		panel.visible = false
		panel.position = Vector2(-1000, -1000)  # Move off screen

	# Apply neon-kawaii sticker style for allies
	if is_ally:
		panel.custom_minimum_size = Vector2(220, 110)

		# Sticker style: Dark fill with thick white keyline (2px per design spec)
		var style = StyleBoxFlat.new()
		style.bg_color = COLOR_INK_CHARCOAL  # Dark glass fill
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = COLOR_MILK_WHITE  # Thick white keyline
		style.corner_radius_top_left = 12  # Soft rectangle
		style.corner_radius_top_right = 12
		style.corner_radius_bottom_left = 12
		style.corner_radius_bottom_right = 12
		style.shadow_size = 4
		style.shadow_color = Color(COLOR_SKY_CYAN.r, COLOR_SKY_CYAN.g, COLOR_SKY_CYAN.b, 0.3)  # Subtle cyan glow
		panel.add_theme_stylebox_override("panel", style)

		# Apply subtle diagonal tilt
		panel.rotation_degrees = randf_range(-2, 2)

		# Horizontal layout for icon + info
		var hbox = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 10)
		panel.add_child(hbox)

		# Character icon with thick white keyline (sticker edges)
		var icon_container = PanelContainer.new()
		icon_container.custom_minimum_size = Vector2(40, 40)

		var icon_style = StyleBoxFlat.new()
		# Assign a neon color based on character index for variety
		var icon_colors = [COLOR_BUBBLE_MAGENTA, COLOR_SKY_CYAN, COLOR_ELECTRIC_LIME, COLOR_CITRUS_YELLOW]
		var hash_val = combatant.display_name.hash()
		var icon_color = icon_colors[abs(hash_val) % icon_colors.size()]

		icon_style.bg_color = icon_color
		icon_style.border_width_left = 2
		icon_style.border_width_right = 2
		icon_style.border_width_top = 2
		icon_style.border_width_bottom = 2
		icon_style.border_color = COLOR_MILK_WHITE  # White keyline around icon
		icon_style.corner_radius_top_left = 8
		icon_style.corner_radius_top_right = 8
		icon_style.corner_radius_bottom_left = 8
		icon_style.corner_radius_bottom_right = 8
		icon_container.add_theme_stylebox_override("panel", icon_style)

		hbox.add_child(icon_container)

		# Info column (name + HP bar)
		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(vbox)

		# Name label (Milk White, all caps)
		var name_label = Label.new()
		name_label.text = combatant.display_name.to_upper()
		name_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
		name_label.add_theme_font_size_override("font_size", 11)
		vbox.add_child(name_label)

		# HP bar as pill shape with gradient fill
		var hp_bar = ProgressBar.new()
		hp_bar.max_value = combatant.hp_max
		hp_bar.value = combatant.hp
		hp_bar.show_percentage = false
		hp_bar.custom_minimum_size = Vector2(0, 10)

		# Pill background
		var hp_bar_bg = StyleBoxFlat.new()
		hp_bar_bg.bg_color = COLOR_NIGHT_NAVY
		hp_bar_bg.corner_radius_top_left = 8
		hp_bar_bg.corner_radius_top_right = 8
		hp_bar_bg.corner_radius_bottom_left = 8
		hp_bar_bg.corner_radius_bottom_right = 8
		hp_bar.add_theme_stylebox_override("background", hp_bar_bg)

		# Pill fill with gradient (Cyan to Milk White gradient)
		var hp_bar_fill = StyleBoxFlat.new()
		# Create two-tone effect: use cyan for >25%, transition to magenta for low HP
		var hp_percent = float(combatant.hp) / float(combatant.hp_max) if combatant.hp_max > 0 else 1.0
		var fill_color = COLOR_SKY_CYAN if hp_percent > 0.25 else COLOR_BUBBLE_MAGENTA
		hp_bar_fill.bg_color = fill_color
		hp_bar_fill.corner_radius_top_left = 8
		hp_bar_fill.corner_radius_top_right = 8
		hp_bar_fill.corner_radius_bottom_left = 8
		hp_bar_fill.corner_radius_bottom_right = 8
		hp_bar.add_theme_stylebox_override("fill", hp_bar_fill)

		vbox.add_child(hp_bar)

		# HP text (current/max in small monospace)
		var hp_label = Label.new()
		hp_label.text = "%d/%d HP" % [combatant.hp, combatant.hp_max]
		hp_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
		hp_label.add_theme_font_size_override("font_size", 8)
		vbox.add_child(hp_label)

		# MP bar (if character has MP)
		if combatant.mp_max > 0:
			var mp_bar = ProgressBar.new()
			mp_bar.max_value = combatant.mp_max
			mp_bar.value = combatant.mp
			mp_bar.show_percentage = false
			mp_bar.custom_minimum_size = Vector2(0, 8)

			# Pill background
			var mp_bar_bg = StyleBoxFlat.new()
			mp_bar_bg.bg_color = COLOR_NIGHT_NAVY
			mp_bar_bg.corner_radius_top_left = 8
			mp_bar_bg.corner_radius_top_right = 8
			mp_bar_bg.corner_radius_bottom_left = 8
			mp_bar_bg.corner_radius_bottom_right = 8
			mp_bar.add_theme_stylebox_override("background", mp_bar_bg)

			# Pill fill - use Grape Violet for MP
			var mp_bar_fill = StyleBoxFlat.new()
			mp_bar_fill.bg_color = COLOR_GRAPE_VIOLET
			mp_bar_fill.corner_radius_top_left = 8
			mp_bar_fill.corner_radius_top_right = 8
			mp_bar_fill.corner_radius_bottom_left = 8
			mp_bar_fill.corner_radius_bottom_right = 8
			mp_bar.add_theme_stylebox_override("fill", mp_bar_fill)

			vbox.add_child(mp_bar)

			# MP text
			var mp_label = Label.new()
			mp_label.text = "%d/%d MP" % [combatant.mp, combatant.mp_max]
			mp_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
			mp_label.add_theme_font_size_override("font_size", 8)
			vbox.add_child(mp_label)

	else:
		# Enemies: Simpler sticker style
		panel.custom_minimum_size = Vector2(140, 90)

		var style = StyleBoxFlat.new()
		style.bg_color = COLOR_NIGHT_NAVY
		style.border_width_left = 2
		style.border_width_right = 2
		style.border_width_top = 2
		style.border_width_bottom = 2
		style.border_color = COLOR_BUBBLE_MAGENTA  # Magenta for enemies
		style.corner_radius_top_left = 12
		style.corner_radius_top_right = 12
		style.corner_radius_bottom_left = 12
		style.corner_radius_bottom_right = 12
		style.shadow_size = 4
		style.shadow_color = Color(COLOR_BUBBLE_MAGENTA.r, COLOR_BUBBLE_MAGENTA.g, COLOR_BUBBLE_MAGENTA.b, 0.3)
		panel.add_theme_stylebox_override("panel", style)

		var vbox = VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		panel.add_child(vbox)

		# Name label
		var name_label = Label.new()
		name_label.text = combatant.display_name.to_upper()
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
		name_label.add_theme_font_size_override("font_size", 11)
		vbox.add_child(name_label)

		# HP bar
		var hp_bar = ProgressBar.new()
		hp_bar.max_value = combatant.hp_max
		hp_bar.value = combatant.hp
		hp_bar.show_percentage = false
		hp_bar.custom_minimum_size = Vector2(0, 10)

		var hp_bar_bg = StyleBoxFlat.new()
		hp_bar_bg.bg_color = COLOR_NIGHT_NAVY.darkened(0.2)
		hp_bar_bg.corner_radius_top_left = 8
		hp_bar_bg.corner_radius_top_right = 8
		hp_bar_bg.corner_radius_bottom_left = 8
		hp_bar_bg.corner_radius_bottom_right = 8
		hp_bar.add_theme_stylebox_override("background", hp_bar_bg)

		var hp_bar_fill = StyleBoxFlat.new()
		hp_bar_fill.bg_color = COLOR_BUBBLE_MAGENTA
		hp_bar_fill.corner_radius_top_left = 8
		hp_bar_fill.corner_radius_top_right = 8
		hp_bar_fill.corner_radius_bottom_left = 8
		hp_bar_fill.corner_radius_bottom_right = 8
		hp_bar.add_theme_stylebox_override("fill", hp_bar_fill)

		vbox.add_child(hp_bar)

		# HP label
		var hp_label = Label.new()
		hp_label.text = "%d/%d" % [combatant.hp, combatant.hp_max]
		hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hp_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
		hp_label.add_theme_font_size_override("font_size", 8)
		vbox.add_child(hp_label)

	# Store combatant ID in metadata
	panel.set_meta("combatant_id", combatant.id)
	panel.set_meta("is_ally", is_ally)

	# Make panels clickable for targeting
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	if not is_ally:
		panel.gui_input.connect(_on_enemy_panel_input.bind(combatant))
	else:
		panel.gui_input.connect(_on_ally_panel_input.bind(combatant))

	return panel

func _update_combatant_displays() -> void:
	"""Update all combatant HP/MP displays"""
	# TODO: Update HP/MP bars without recreating everything
	_display_combatants()

func _shake_combatant_panel(combatant_id: String) -> void:
	"""Shake a combatant's panel when they take damage"""
	if not combatant_panels.has(combatant_id):
		return

	var panel = combatant_panels[combatant_id]
	var original_position = panel.position

	# Create shake animation using Tween
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)

	# Shake sequence: left, right, left, right, center
	var shake_intensity = 8.0
	var shake_duration = 0.05

	tween.tween_property(panel, "position", original_position + Vector2(-shake_intensity, 0), shake_duration)
	tween.tween_property(panel, "position", original_position + Vector2(shake_intensity, 0), shake_duration)
	tween.tween_property(panel, "position", original_position + Vector2(-shake_intensity * 0.5, 0), shake_duration)
	tween.tween_property(panel, "position", original_position + Vector2(shake_intensity * 0.5, 0), shake_duration)
	tween.tween_property(panel, "position", original_position, shake_duration)
func _get_skill_button_sequence(skill_id: String) -> Array:
	"""Generate button sequence for a skill based on its ID"""
	var element = ""
	var tier = 1
	
	if "_L" in skill_id:
		var parts = skill_id.split("_L")
		element = parts[0].to_lower()
		tier = int(parts[1]) if parts.size() > 1 else 1
	
	var length = 3
	if tier == 2: length = 5
	elif tier >= 3: length = 8
	
	var sequence = []
	match element:
		"fire":
			var pattern = ["A", "X", "A", "Y", "A", "B", "A", "X"]
			for i in range(length): sequence.append(pattern[i])
		"water":
			var pattern = ["B", "A", "B", "X", "B", "Y", "B", "A"]
			for i in range(length): sequence.append(pattern[i])
		"earth":
			var pattern = ["X", "Y", "X", "A", "X", "B", "X", "Y"]
			for i in range(length): sequence.append(pattern[i])
		"air":
			var pattern = ["Y", "B", "Y", "A", "Y", "X", "Y", "B"]
			for i in range(length): sequence.append(pattern[i])
		"void":
			var pattern = ["A", "B", "A", "B", "X", "Y", "A", "B"]
			for i in range(length): sequence.append(pattern[i])
		_:
			var pattern = ["A", "B", "X", "Y", "A", "B", "X", "Y"]
			for i in range(length): sequence.append(pattern[i])
	
	return sequence



func _show_status_details(combatant: Dictionary) -> void:
	"""Show detailed status information popup for a combatant"""
	# Create modal background (blocks clicks)
	status_details_modal = ColorRect.new()
	status_details_modal.color = Color(0, 0, 0, 0.5)  # Semi-transparent black overlay
	status_details_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	status_details_modal.z_index = 99
	status_details_modal.mouse_filter = Control.MOUSE_FILTER_STOP  # Block all clicks
	add_child(status_details_modal)

	# Create popup panel - fully opaque, no transparency
	status_details_popup = PanelContainer.new()
	status_details_popup.custom_minimum_size = Vector2(400, 300)
	status_details_popup.modulate.a = 1.0  # 100% solid, no transparency

	# Add Core vibe styling
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = COLOR_INK_CHARCOAL  # Dark background
	panel_style.border_width_left = 3
	panel_style.border_width_right = 3
	panel_style.border_width_top = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = COLOR_SKY_CYAN  # Cyan neon border
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.shadow_size = 6
	panel_style.shadow_color = Color(COLOR_SKY_CYAN.r, COLOR_SKY_CYAN.g, COLOR_SKY_CYAN.b, 0.4)  # Cyan glow
	status_details_popup.add_theme_stylebox_override("panel", panel_style)

	# Center it on screen
	status_details_popup.position = get_viewport_rect().size / 2 - status_details_popup.custom_minimum_size / 2
	status_details_popup.z_index = 100
	status_details_popup.mouse_filter = Control.MOUSE_FILTER_STOP  # Prevent clicking through

	var vbox = VBoxContainer.new()
	status_details_popup.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "=== %s Status ===" % combatant.display_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", COLOR_BUBBLE_MAGENTA)  # Pink magenta title
	vbox.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(380, 220)
	vbox.add_child(scroll)

	var content = VBoxContainer.new()
	scroll.add_child(content)

	# Ailment
	var ailment = str(combatant.get("ailment", ""))
	if ailment != "" and ailment != "null":
		var ailment_label = Label.new()
		ailment_label.text = "❌ Ailment: %s" % ailment.capitalize()
		ailment_label.add_theme_color_override("font_color", COLOR_CITRUS_YELLOW)  # Yellow for ailments
		content.add_child(ailment_label)

	# Buffs/Debuffs
	if combatant.has("buffs"):
		var buffs = combatant.get("buffs", [])
		if buffs.size() > 0:
			var buff_title = Label.new()
			buff_title.text = "\n--- Active Effects (%d) ---" % buffs.size()
			buff_title.add_theme_font_size_override("font_size", 14)
			buff_title.add_theme_color_override("font_color", COLOR_SKY_CYAN)  # Cyan section header
			content.add_child(buff_title)

			for buff in buffs:
				if typeof(buff) == TYPE_DICTIONARY:
					var buff_type = str(buff.get("type", ""))
					var value = float(buff.get("value", 0.0))
					var duration = int(buff.get("duration", 0))

					var buff_text = _format_buff_description(buff_type, value, duration)
					var buff_label = Label.new()
					buff_label.text = buff_text

					# Color based on positive/negative
					if value > 0:
						buff_label.add_theme_color_override("font_color", COLOR_ELECTRIC_LIME)  # Lime green for buffs
					else:
						buff_label.add_theme_color_override("font_color", COLOR_CITRUS_YELLOW)  # Yellow for debuffs

					content.add_child(buff_label)

	# If no effects
	if ailment == "" or ailment == "null":
		if not combatant.has("buffs") or combatant.buffs.size() == 0:
			var none_label = Label.new()
			none_label.text = "\n✓ No status effects"
			none_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)  # White text
			content.add_child(none_label)

	# Close button
	var close_btn = Button.new()
	close_btn.text = "Close (B)"
	close_btn.pressed.connect(_close_status_details)
	vbox.add_child(close_btn)

	add_child(status_details_popup)

	# Pause the status picker panel while status details are open
	if status_picker_panel:
		# Block all input to status picker
		status_picker_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		status_picker_panel.process_mode = Node.PROCESS_MODE_DISABLED
		# Release focus from any buttons
		for btn in status_picker_buttons:
			if btn.has_focus():
				btn.release_focus()

func _format_buff_description(buff_type: String, value: float, duration: int) -> String:
	"""Format buff/debuff into readable description"""
	var type_name = ""
	var symbol = "↑" if value > 0 else "↓"

	match buff_type.to_lower():
		"atk_up", "atk_down", "atk":
			type_name = "Attack"
		"skl_up", "skl_down", "skl", "mnd_up", "mnd_down", "mnd":
			type_name = "Skill/Mind"
		"def_up", "def_down", "def":
			type_name = "Defense"
		"spd_up", "spd_down", "spd", "speed":
			type_name = "Speed"
		"phys_acc", "acc_up", "acc_down", "acc":
			type_name = "Physical Accuracy"
		"mind_acc", "skill_acc":
			type_name = "Skill Accuracy"
		"evasion", "evade", "eva_up", "eva_down":
			type_name = "Evasion"
		"regen":
			return "● Regen (%d%% per round, %d rounds left)" % [int(value * 100), duration]
		"reflect":
			var element = ""
			return "◆ Reflect (%d rounds left)" % duration
		_:
			type_name = buff_type.replace("_", " ").capitalize()

	var percent = int(abs(value) * 100)
	return "%s %s %s%d%% (%d rounds left)" % [symbol, type_name, "+" if value > 0 else "-", percent, duration]

## ═══════════════════════════════════════════════════════════════
## ACTION MENU
## ═══════════════════════════════════════════════════════════════

func _show_action_menu() -> void:
	"""Show the action menu for player's turn"""
	# Ensure input is enabled (in case animation was skipped)
	if is_in_round_transition:
		_enable_all_input()

	_enable_action_menu()

	# Disable Run button if already attempted this round
	var run_button = action_menu.get_node_or_null("RunButton")
	if run_button and run_button is Button:
		run_button.disabled = battle_mgr.run_attempted_this_round
		if battle_mgr.run_attempted_this_round:
			run_button.text = "Run (Used)"
		else:
			run_button.text = "Run"

	# TODO: Enable/disable actions based on state
	# e.g., disable skills if no MP, disable burst if gauge too low

func _disable_action_menu() -> void:
	"""Disable and dim action menu buttons (but keep visible)"""
	if not action_menu:
		return

	# Dim the entire action menu
	action_menu.modulate.a = 0.3

	# Disable all buttons
	for child in action_menu.get_children():
		if child is Button:
			child.disabled = true

func _enable_action_menu() -> void:
	"""Enable and restore action menu buttons"""
	if not action_menu:
		return

	# Restore full opacity
	action_menu.modulate.a = 1.0

	# Enable all buttons
	for child in action_menu.get_children():
		if child is Button:
			child.disabled = false

func _disable_all_input() -> void:
	"""Disable all input during round transitions to prevent glitches"""
	is_in_round_transition = true

	# Disable and dim action menu
	_disable_action_menu()

	# Disable ally slots (prevent clicking on characters)
	if ally_slots:
		ally_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Disable enemy slots (prevent clicking on enemies)
	if enemy_slots:
		enemy_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE

	print("[Battle] Input disabled during round transition")

func _enable_all_input() -> void:
	"""Re-enable all input after round transition completes"""
	is_in_round_transition = false

	# Re-enable action menu
	if action_menu:
		action_menu.mouse_filter = Control.MOUSE_FILTER_STOP

	# Re-enable ally slots
	if ally_slots:
		ally_slots.mouse_filter = Control.MOUSE_FILTER_STOP

	# Re-enable enemy slots
	if enemy_slots:
		enemy_slots.mouse_filter = Control.MOUSE_FILTER_STOP

	print("[Battle] Input re-enabled after round transition")

func _on_attack_pressed() -> void:
	"""Handle Attack action - prompt user to select target"""
	# Block input during round transitions
	if is_in_round_transition:
		return

	_show_instruction("Select an enemy.")

	# Get alive enemies
	var enemies = battle_mgr.get_enemy_combatants()
	target_candidates = enemies.filter(func(e): return not e.is_ko)

	if target_candidates.is_empty():
		_hide_instruction()
		log_message("No valid targets!")
		return

	# Enable target selection mode
	awaiting_target_selection = true
	selected_target_index = 0  # Start with first target
	_highlight_target_candidates()

	# Show currently selected target
	if not target_candidates.is_empty():
		log_message("→ %s" % target_candidates[0].display_name)

func _execute_attack(target: Dictionary) -> void:
	"""Execute attack on selected target"""
	_hide_instruction()
	awaiting_target_selection = false
	_clear_target_highlights()

	# Check if frozen combatant can act
	if not _check_freeze_action_allowed():
		return

	# Clear defending status when attacking
	current_combatant.is_defending = false

	# Start building turn message
	start_turn_message()
	add_turn_line("%s attacked %s!" % [current_combatant.display_name, target.display_name])

	if target:
		# First, check if the attack hits
		var hit_check = combat_resolver.check_physical_hit(current_combatant, target)

		if not hit_check.hit:
			# Miss!
			_show_miss_feedback()  # Show big MISS text
			add_turn_line("But it missed!")
			add_turn_line("(Hit chance: %d%%, rolled %d)" % [int(hit_check.hit_chance), hit_check.roll])
			queue_turn_message()  # Queue the full turn message
			print("[Battle] Miss! Hit chance: %.1f%%, Roll: %d" % [hit_check.hit_chance, hit_check.roll])
		else:
			# Hit! Launch attack minigame
			var tpo = current_combatant.stats.get("TPO", 1)
			var brw = current_combatant.stats.get("BRW", 1)
			var status_effects = []
			var ailment = str(current_combatant.get("ailment", ""))
			if ailment != "":
				status_effects.append(ailment)

			_show_instruction("FIGHT!")
			var minigame_result = await minigame_mgr.launch_attack_minigame(tpo, brw, status_effects)
			_hide_instruction()

			# Apply minigame result modifiers
			var damage_modifier = minigame_result.get("damage_modifier", 1.0)
			var minigame_crit = minigame_result.get("is_crit", false)

			# Now roll for critical (or use minigame crit)
			var crit_check = combat_resolver.check_critical_hit(current_combatant, {"defender": target})
			var is_crit = crit_check.crit or minigame_crit

			# Calculate mind type effectiveness
			var type_bonus = combat_resolver.get_mind_type_bonus(current_combatant, target)

			# Check weapon type weakness (check now, record later after damage)
			var weapon_weakness_hit = combat_resolver.check_weapon_weakness(current_combatant, target)

			# Critical hits also count as weakness hits for stumbling
			var crit_weakness_hit = is_crit

			# Calculate damage
			var damage_result = combat_resolver.calculate_physical_damage(
				current_combatant,
				target,
				{
					"potency": 100,
					"is_crit": is_crit,
					"type_bonus": type_bonus
				}
			)

			var damage = damage_result.damage
			var is_stumble = damage_result.is_stumble

			
			# Apply minigame damage modifier
			damage = int(round(damage * damage_modifier))
			print("[Battle] Minigame modifier: %.2fx | Final damage: %d" % [damage_modifier, damage])
			# Apply damage
			target.hp -= damage

			# Wake up if asleep
			_wake_if_asleep(target)

			if target.hp <= 0:
				target.hp = 0
				_set_fainted(target)

				# Record kill for morality system (if enemy)
				if not target.get("is_ally", false):
					battle_mgr.record_enemy_defeat(target, false)  # false = kill

			# Record weakness hits AFTER damage (only if target still alive)
			var weakness_line = ""
			if not target.is_ko and (weapon_weakness_hit or crit_weakness_hit):
				var became_fallen = await battle_mgr.record_weapon_weakness_hit(target)
				if weapon_weakness_hit:
					weakness_line = "%s receives a WEAPON WEAKNESS!" % target.display_name
				elif crit_weakness_hit:
					weakness_line = "%s receives a CRITICAL STUMBLE!" % target.display_name
				if became_fallen:
					weakness_line += " %s fell!" % target.display_name

			# Add weakness line if present
			if weakness_line != "":
				add_turn_line(weakness_line)

			# Build hit message line
			var hit_msg = "%s is hit for %d damage!" % [target.display_name, damage]

			# Add special effects to message
			var effect_parts = []
			if is_crit:
				effect_parts.append("CRITICAL")
			if type_bonus > 0.0:
				effect_parts.append("Super Effective")
			elif type_bonus < 0.0:
				effect_parts.append("Not Very Effective")
			if target.get("is_defending", false):
				effect_parts.append("Guarded")

			if not effect_parts.is_empty():
				hit_msg = "%s (%s)" % [hit_msg, ", ".join(effect_parts)]

			add_turn_line(hit_msg)

			# Add KO or status line
			if target.is_ko:
				add_turn_line("%s fainted!" % target.display_name)
			elif weakness_line == "":  # Only show HP if no weakness
				add_turn_line("%s has %d HP left." % [target.display_name, target.hp])

			# Queue the full turn message
			queue_turn_message()

			# Debug: show hit, crit, and damage breakdown
			var hit_breakdown = hit_check.breakdown
			var crit_breakdown = crit_check.breakdown
			var dmg_breakdown = damage_result.breakdown
			print("[Battle] Hit! Chance: %.1f%% (ACC %.1f - EVA %.1f), Roll: %d" % [
				hit_check.hit_chance, hit_breakdown.hit_percent, hit_breakdown.eva_percent, hit_check.roll
			])
			print("[Battle] Crit: %s | Chance: %.1f%% (Base %.1f + BRW %.1f + Weapon %d), Roll: %d, Mult: %.2fx" % [
				"YES" if is_crit else "NO", crit_check.crit_chance, crit_breakdown.base,
				crit_breakdown.brw_bonus, crit_breakdown.weapon_bonus, crit_check.roll, crit_breakdown.crit_mult
			])
			print("[Battle] Type: %s vs %s = %.2fx (%s)" % [
				current_combatant.get("mind_type", "none"),
				target.get("mind_type", "none"),
				1.0 + type_bonus,
				"SUPER EFFECTIVE" if type_bonus > 0 else ("NOT VERY EFFECTIVE" if type_bonus < 0 else "neutral")
			])
			print("[Battle] Damage: PreMit=%.1f, AtkPower=%.1f, Raw=%.1f, Final=%d (Min=%d)" % [
				dmg_breakdown.pre_mit, dmg_breakdown.atk_power, dmg_breakdown.raw, damage, dmg_breakdown.min_damage
			])

			# Add burst gauge
			battle_mgr.add_burst(10)  # +10 for basic attack hit
			if is_crit:
				battle_mgr.add_burst(4)  # +4 for crit
			if is_stumble:
				battle_mgr.add_burst(8)  # +8 for weakness

			_update_combatant_displays()
			_update_burst_gauge()

			# Refresh turn order if combatant was KO'd
			if target.is_ko:
				# Animate falling and then re-sort turn order
				if turn_order_display:
					await turn_order_display.animate_ko_fall(target.id)
				await battle_mgr.refresh_turn_order()
			elif turn_order_display:
				turn_order_display.update_combatant_hp(target.id)

	# Check if battle is over (all enemies defeated/captured)
	var battle_ended = await battle_mgr._check_battle_end()
	if battle_ended:
		print("[Battle] Battle ended after attack - skipping end turn")
		return  # Battle ended

	# End turn
	battle_mgr.end_turn()

func _on_skill_pressed() -> void:
	"""Handle Skill action - show sigil/skill menu"""
	# Block input during round transitions
	if is_in_round_transition:
		return

	var sigils = current_combatant.get("sigils", [])
	var skills = current_combatant.get("skills", [])

	if skills.is_empty():
		log_message("No skills available!")
		return

	# Get SigilSystem for display names
	var sigil_sys = get_node_or_null("/root/aSigilSystem")
	if not sigil_sys:
		log_message("Sigil system not available!")
		return

	# Build skill menu with sigil info
	var skill_menu = []
	for i in range(min(sigils.size(), skills.size())):
		var sigil_inst = sigils[i]
		var skill_id = skills[i]

		if skill_definitions.has(skill_id):
			var skill_data = skill_definitions[skill_id]
			var mp_cost = int(skill_data.get("cost_mp", 0))
			var can_afford = current_combatant.mp >= mp_cost

			# Get sigil display name
			var sigil_name = sigil_sys.get_display_name_for(sigil_inst) if sigil_sys.has_method("get_display_name_for") else "Sigil"

			skill_menu.append({
				"sigil_name": sigil_name,
				"sigil_inst_id": sigil_inst,  # Track which sigil this skill comes from
				"skill_id": skill_id,
				"skill_data": skill_data,
				"can_afford": can_afford
			})

	if skill_menu.is_empty():
		log_message("No skills available!")
		return

	_show_instruction("Choose a skill.")

	# Show skill selection menu
	_show_skill_menu(skill_menu)

func _categorize_battle_item(item_id: String, item_name: String, item_def: Dictionary) -> String:
	"""Categorize an item into Restore, Cure, Tactical, or Combat"""
	var effect = str(item_def.get("battle_status_effect", ""))

	# Check for Cure items (status ailment cures)
	if item_id.begins_with("CURE_") or "Cure" in effect:
		return "Cure"

	# Check for Restore items (HP/MP healing, revival, elixirs)
	if item_id.begins_with("HP_") or item_id.begins_with("MP_") or item_id.begins_with("REV_") or \
	   item_id.begins_with("HEAL_") or item_id.begins_with("ELX_") or \
	   "Heal" in effect or "Revive" in effect:
		return "Restore"

	# Check for Combat items (bombs, AOE damage)
	if "Bomb" in item_name or "AOE dmg" in effect:
		return "Combat"

	# Check for Tactical items (buffs, mirrors, speed/defense boosts, escape items)
	if item_id.begins_with("BUFF_") or item_id.begins_with("TOOL_") or "Reflect" in effect or \
	   "Up" in effect or "Shield" in effect or "Regen" in effect or \
	   "Speed" in effect or "Hit%" in effect or "Evasion%" in effect or "SkillHit%" in effect or \
	   "escape" in effect or "Run%" in effect:
		return "Tactical"

	# Default to Tactical if we can't determine
	return "Tactical"

func _on_item_pressed() -> void:
	"""Handle Item action - show usable items menu"""
	# Block input during round transitions
	if is_in_round_transition:
		return

	var inventory = get_node_or_null("/root/aInventorySystem")
	if not inventory:
		log_message("Inventory system not available!")
		return

	# Get all consumable items player has
	var item_counts = inventory.get_counts_dict()
	var item_defs = inventory.get_item_defs()
	var usable_items: Array = []

	for item_id in item_counts:
		var count = item_counts[item_id]
		if count <= 0:
			continue

		# Skip if item_id is invalid
		if item_id == null:
			continue

		var item_id_str = str(item_id)  # Use str() which is safer than String()
		if item_id_str == "":
			continue

		var item_def = item_defs.get(item_id, {})
		var use_type = item_def.get("use_type", "")
		if use_type == null:
			use_type = ""
		use_type = str(use_type)

		var category = item_def.get("category", "")
		if category == null:
			category = ""
		category = str(category)

		# Debug: Print use_type for all items to see what we're getting
		print("[Battle] Item %s: use_type='%s', category='%s', count=%d" % [item_id_str, use_type, category, count])

		# Include items that can be used in battle (use_type = "battle" or "both")
		# Exclude bind items (those are for Capture button) - BIND_ items
		# Exclude Sigils (those are equipment, not consumables)
		if use_type in ["battle", "both"] and category != "Battle Items" and category != "Sigils" and not item_id_str.begins_with("BIND_"):
			var desc = item_def.get("short_description", "")
			if desc == null:
				desc = ""
			else:
				desc = str(desc)
				if desc == "null":
					desc = ""

			# Debug: Check what description we're getting
			if item_id_str.begins_with("BUFF_") or item_id_str.begins_with("BAT_"):
				print("[Battle] Item %s description: '%s'" % [item_id_str, desc])

			var item_name = item_def.get("name", "")
			if item_name == null or item_name == "":
				item_name = item_id_str
			item_name = str(item_name)

			var targeting = item_def.get("targeting", "Ally")
			if targeting == null:
				targeting = "Ally"
			targeting = str(targeting)

			# Categorize the item
			var item_category = _categorize_battle_item(item_id_str, item_name, item_def)

			usable_items.append({
				"id": item_id_str,
				"name": item_name,
				"display_name": item_name,
				"description": desc,
				"count": count,
				"targeting": targeting,
				"item_def": item_def,
				"battle_category": item_category
			})

	print("[Battle] Found %d usable items for battle" % usable_items.size())
	if usable_items.is_empty():
		log_message("No usable items!")
		return

	_show_instruction("Choose an item.")

	# Show item selection menu
	_show_item_menu(usable_items)

func _on_capture_pressed() -> void:
	"""Handle Capture action - show bind item selection menu"""
	# Block input during round transitions
	if is_in_round_transition:
		return

	var inventory = get_node_or_null("/root/aInventorySystem")
	if not inventory:
		log_message("Inventory system not available!")
		return

	# Find available bind items
	var bind_items: Array = []
	var bind_ids = ["BIND_001", "BIND_002", "BIND_003", "BIND_004", "BIND_005"]

	for bind_id in bind_ids:
		var count = inventory.get_count(bind_id)
		if count > 0:
			var item_def = inventory.get_item_def(bind_id)

			# Debug: Check what fields are available in item_def
			print("[Battle] Bind item %s fields: %s" % [bind_id, item_def.keys()])

			var desc = item_def.get("short_description", "")
			if desc == null:
				desc = ""
			desc = str(desc)

			var bind_name = item_def.get("name", "")
			if bind_name == null or bind_name == "":
				bind_name = bind_id
			bind_name = str(bind_name)

			# Read capture modifier from stat_boost field (since capture_mod doesn't exist in CSV)
			var capture_mod_raw = item_def.get("stat_boost", 0)
			var capture_mod_val = int(capture_mod_raw) if capture_mod_raw != null else 0
			print("[Battle] Bind item %s (%s) capture modifier: %d%%" % [bind_id, bind_name, capture_mod_val])

			bind_items.append({
				"id": str(bind_id),
				"name": bind_name,
				"display_name": bind_name,
				"description": desc,
				"capture_mod": capture_mod_val,
				"count": count,
				"item_def": item_def
			})

	if bind_items.is_empty():
		log_message("No bind items available!")
		return

	_show_instruction("Choose a bind.")

	# Show bind selection menu
	_show_capture_menu(bind_items)

func _execute_capture(target: Dictionary) -> void:
	"""Execute capture attempt on selected target"""
	awaiting_target_selection = false
	awaiting_capture_target = false
	_clear_target_highlights()

	# Get the bind item that was selected
	var bind_data = get_meta("pending_capture_bind", {})
	if bind_data.is_empty():
		log_message("Capture failed - no bind selected!")
		return

	print("[Battle] bind_data contents: %s" % bind_data)
	var bind_id: String = bind_data.id
	var bind_name: String = bind_data.name
	var capture_mod: int = bind_data.capture_mod
	print("[Battle] Extracted capture_mod value: %d" % capture_mod)

	# Calculate capture chance
	var capture_result = combat_resolver.calculate_capture_chance(target, {"item_mod": capture_mod})
	var capture_chance: float = capture_result.chance
	print("[Battle] Capture calculation result: %s" % capture_result)

	log_message("%s uses %s on %s!" % [current_combatant.display_name, bind_name, target.display_name])
	log_message("  Capture chance: %.1f%%" % capture_chance)

	# ═══════ CAPTURE MINIGAME ═══════
	# Initialize or get persistent break rating
	if not target.has("break_rating"):
		# First capture attempt - calculate initial break rating
		var base_rating = target.get("level", 1)
		var enemy_hp = target.hp
		var enemy_hp_max = target.hp_max
		var enemy_hp_percent = float(enemy_hp) / float(enemy_hp_max)
		var party_hp = current_combatant.hp

		# Start with base rating
		var calculated_rating = float(base_rating)

		# Apply modifiers based on HP comparison
		if enemy_hp_percent >= 1.0:
			# Enemy at 100% HP: +50%
			calculated_rating *= 1.5
			log_message("  → Enemy at full health! (+50% break rating)")
		elif enemy_hp > party_hp:
			# Enemy has more HP than party member: +25%
			calculated_rating *= 1.25
			log_message("  → Enemy stronger than you! (+25% break rating)")
		elif enemy_hp_percent <= 0.1:
			# Enemy below 10% HP: -50%
			calculated_rating *= 0.5
			log_message("  → Enemy critically weak! (-50% break rating)")
		elif enemy_hp < party_hp:
			# Enemy has less HP than party member: -25%
			calculated_rating *= 0.75
			log_message("  → Enemy weaker than you! (-25% break rating)")

		target.break_rating = max(1, int(calculated_rating))
		log_message("  → First capture attempt! Break rating: %d" % target.break_rating)
	else:
		log_message("  → Continued capture! Break rating: %d" % target.break_rating)

	# Map bind item to bind type
	var bind_type = "basic"
	match bind_id:
		"BIND_001": bind_type = "basic"
		"BIND_002": bind_type = "standard"
		"BIND_003": bind_type = "advanced"
		"BIND_004": bind_type = "advanced"  # Superior uses advanced mechanics

	# Build enemy data for minigame
	var enemy_data = {
		"hp": target.hp,
		"hp_max": target.hp_max,
		"level": target.get("level", 1),
		"TPO": target.stats.get("TPO", 1),
		"actor_id": target.get("actor_id", ""),
		"display_name": target.get("display_name", "Enemy"),
		"break_rating": target.break_rating,
		"ailment": target.get("ailment", "")  # Add enemy ailment
	}

	# Build party member data for minigame
	var party_member_data = {
		"FOC": current_combatant.stats.get("FCS", 1)
	}

	# Get status effects
	var status_effects = []
	var ailment = str(current_combatant.get("ailment", ""))
	if ailment != "":
		status_effects.append(ailment)

	# Launch capture minigame
	log_message("  → Starting capture minigame...")
	var minigame_result = await minigame_mgr.launch_capture_minigame([bind_type], enemy_data, party_member_data, status_effects)

	# Update break rating based on minigame result
	var break_rating_reduced = minigame_result.get("break_rating_reduced", 0)
	var wraps_completed = minigame_result.get("wraps_completed", 0)

	target.break_rating -= break_rating_reduced
	if target.break_rating < 0:
		target.break_rating = 0

	log_message("  → Completed %d wraps! Break rating: %d → %d" % [wraps_completed, target.break_rating + break_rating_reduced, target.break_rating])

	# Consume the bind item
	var inventory = get_node("/root/aInventorySystem")
	inventory.remove_item(bind_id, 1)

	# Check if break rating hit 0 (capture success)
	var success = target.break_rating <= 0

	if success:
		# Capture successful!
		_set_captured(target)  # Remove from battle and mark as captured
		log_message("  → SUCCESS! %s was captured!" % target.display_name)

		# Record capture for morality system
		battle_mgr.record_enemy_defeat(target, true)  # true = capture

		# Add captured enemy to collection
		_add_captured_enemy(target)

		# Animate turn cell - turn it green
		if turn_order_display and turn_order_display.has_method("animate_capture"):
			turn_order_display.animate_capture(target.id)

		# Update display
		_update_combatant_displays()

		# Check if battle is over (after capture)
		print("[Battle] Checking if battle ended after capture...")
		var battle_ended = await battle_mgr._check_battle_end()
		print("[Battle] Battle end check result: %s" % battle_ended)
		if battle_ended:
			print("[Battle] Battle ended - skipping end turn")
			return  # Battle ended
	else:
		# Capture failed but progress made
		if break_rating_reduced > 0:
			log_message("  → Progress made! %s resists but is weakening..." % target.display_name)
		else:
			log_message("  → FAILED! %s broke free with no progress!" % target.display_name)

	# End turn
	battle_mgr.end_turn()

func _execute_item_usage(target: Dictionary) -> void:
	"""Execute item usage on selected target"""
	awaiting_target_selection = false
	awaiting_item_target = false
	_clear_target_highlights()

	# Check if frozen combatant can act
	if not _check_freeze_action_allowed():
		return

	# Get the item that was selected
	if selected_item.is_empty():
		log_message("Item usage failed - no item selected!")
		return

	var item_id: String = selected_item.id
	var item_name: String = selected_item.name
	var item_def: Dictionary = selected_item.item_def

	# Get item properties
	var effect: String = String(item_def.get("battle_status_effect", ""))
	var duration: int = int(item_def.get("round_duration", 1))
	var mind_type_tag: String = String(item_def.get("mind_type_tag", "none")).to_lower()
	var targeting: String = String(item_def.get("targeting", "Ally"))

	# ═══════ MIRROR ITEMS (Reflect) ═══════
	if "Reflect" in effect:
		# Log item usage with target
		log_message("%s uses %s on %s!" % [current_combatant.display_name, item_name, target.display_name])

		# Extract element type from effect (e.g., "Reflect: Fire (1 hit)")
		var reflect_type = mind_type_tag  # Use mind_type_tag from item
		if reflect_type == "none" or reflect_type == "":
			# Try to extract from effect string
			var lower_effect = effect.to_lower()
			if "fire" in lower_effect:
				reflect_type = "fire"
			elif "water" in lower_effect:
				reflect_type = "water"
			elif "earth" in lower_effect:
				reflect_type = "earth"
			elif "air" in lower_effect:
				reflect_type = "air"
			elif "data" in lower_effect:
				reflect_type = "data"
			elif "void" in lower_effect:
				reflect_type = "void"
			elif "any" in lower_effect or "mind" in lower_effect:
				reflect_type = "any"

		# Add reflect buff
		if not target.has("buffs"):
			target.buffs = []

		target.buffs.append({
			"type": "reflect",
			"element": reflect_type,
			"duration": duration,
			"source": item_name
		})

		log_message("  → %s is protected by a %s Mirror! (Duration: %d rounds)" % [target.display_name, reflect_type.capitalize(), duration])

	# ═══════ BOMB ITEMS (AOE Damage) ═══════
	elif "AOE" in effect or "Bomb" in item_name:
		# Get bomb element from mind_type_tag
		var bomb_element = mind_type_tag

		# Calculate bomb damage (fixed potency for now, can be adjusted)
		var base_damage = 50  # Base bomb damage (50 direct AOE damage)
		var bomb_targets = battle_mgr.get_enemy_combatants()

		log_message("  → %s explodes, hitting all enemies!" % item_name)

		var ko_list = []  # Track defeated enemies for animation

		for enemy in bomb_targets:
			if enemy.is_ko:
				continue

			# Apply type effectiveness
			var type_bonus = 0.0
			if bomb_element != "none" and combat_resolver:
				# Create a temp attacker dict with the bomb's element
				var temp_attacker = {"mind_type": bomb_element}
				type_bonus = combat_resolver.get_mind_type_bonus(temp_attacker, enemy)

			var damage = int(base_damage * (1.0 + type_bonus))
			enemy.hp = max(0, enemy.hp - damage)

			var type_msg = ""
			if type_bonus > 0:
				type_msg = " (Weakness!)"
			elif type_bonus < 0:
				type_msg = " (Resisted)"

			log_message("    %s takes %d damage%s!" % [enemy.display_name, damage, type_msg])

			# Check for KO
			if enemy.hp <= 0:
				_set_fainted(enemy)
				log_message("    %s was defeated!" % enemy.display_name)
				battle_mgr.record_enemy_defeat(enemy, false)
				ko_list.append(enemy)

		_update_combatant_displays()

		# Animate KO fall for each defeated enemy (refresh after each one)
		if ko_list.size() > 0:
			for ko_enemy in ko_list:
				if turn_order_display:
					await turn_order_display.animate_ko_fall(ko_enemy.id)
				battle_mgr.refresh_turn_order()

	# ═══════ FLASH POP (Evasion + Run Boost) ═══════
	elif "Run%" in effect:
		# Log item usage with target
		log_message("%s uses %s on %s!" % [current_combatant.display_name, item_name, target.display_name])

		if not target.has("buffs"):
			target.buffs = []

		# Extract run% bonus from effect (e.g., "Run% +20%")
		var run_bonus = 20.0  # Default bonus
		var regex = RegEx.new()
		regex.compile("Run%\\s*\\+?(\\d+)%?")
		var result = regex.search(effect)
		if result:
			run_bonus = float(result.get_string(1))

		# Add run boost buff
		target.buffs.append({
			"type": "run_boost",
			"value": run_bonus,
			"duration": duration,
			"source": item_name
		})

		log_message("  → %s's escape chance increased by %d%%!" % [target.display_name, int(run_bonus)])

		# Also apply evasion buff if present
		if "Evasion Up" in effect:
			var evasion_value = 10  # Default +10% evasion
			var evasion_regex = RegEx.new()
			evasion_regex.compile("Evasion Up \\+?(\\d+)%")
			var evasion_result = evasion_regex.search(effect)
			if evasion_result:
				evasion_value = int(evasion_result.get_string(1))

			target.buffs.append({
				"type": "evasion",
				"value": evasion_value,
				"duration": duration,
				"source": item_name
			})
			log_message("  → %s's evasion increased by %d%% for %d round(s)!" % [target.display_name, evasion_value, duration])

	# ═══════ BUFF ITEMS (ATK Up, MND Up, Shield, etc.) ═══════
	elif "Up" in effect or "Shield" in effect or "Regen" in effect or "Speed" in effect or "Hit%" in effect or "Evasion%" in effect or "SkillHit%" in effect:
		# Log item usage with target
		log_message("%s uses %s on %s!" % [current_combatant.display_name, item_name, target.display_name])

		# Determine buff type and magnitude
		var buff_type = ""
		var buff_value = 0.0

		if "ATK Up" in effect or "Attack Up" in effect:
			buff_type = "atk_up"
			buff_value = 0.15  # +15% ATK
		elif "SKL Up" in effect or "Skill Up" in effect or "MND Up" in effect:
			buff_type = "skl_up"
			buff_value = 0.15  # +15% SKL
		elif "DEF Up" in effect or "Defense Up" in effect or "Shield" in effect or "-20% dmg" in effect:
			buff_type = "def_up"
			buff_value = 0.20  # -20% damage taken
		elif "Regen" in effect or "Health Up" in effect:
			buff_type = "regen"
			buff_value = 0.10  # 10% HP per round
		elif "+10 Speed" in effect or "Speed Up" in effect:
			buff_type = "spd_up"
			buff_value = 10.0  # +10 Speed (flat bonus)
		elif "+10 Hit%" in effect or "Hit% Up" in effect:
			buff_type = "phys_acc"
			buff_value = 0.10  # +10% physical Hit%
		elif "+10 Evasion%" in effect or "Evasion% Up" in effect:
			buff_type = "evasion"
			buff_value = 0.10  # +10% Eva%
		elif "+10 SkillHit%" in effect or "SkillHit% Up" in effect:
			buff_type = "mind_acc"
			buff_value = 0.10  # +10% Skill Hit%

		if buff_type != "":
			battle_mgr.apply_buff(target, buff_type, buff_value, duration)
			log_message("  → %s gained %s for %d turns!" % [target.display_name, buff_type.replace("_", " ").capitalize(), duration])
			# Refresh turn order to show buff immediately
			if battle_mgr:
				battle_mgr.refresh_turn_order()

	# ═══════ CURE ITEMS (Remove ailments) ═══════
	elif "Cure" in effect:
		# Log item usage with target
		log_message("%s uses %s on %s!" % [current_combatant.display_name, item_name, target.display_name])

		var cured_ailment = ""
		if "Poison" in effect:
			cured_ailment = "poison"
		elif "Burn" in effect:
			cured_ailment = "burn"
		elif "Sleep" in effect:
			cured_ailment = "sleep"
		elif "Freeze" in effect:
			cured_ailment = "freeze"
		elif "Confuse" in effect:
			cured_ailment = "confused"
		elif "Charm" in effect:
			cured_ailment = "charm"
		elif "Berserk" in effect:
			cured_ailment = "berserk"
		elif "Malaise" in effect:
			cured_ailment = "malaise"
		elif "Attack Down" in effect:
			# Remove attack down debuff
			if target.has("debuffs"):
				target.debuffs = target.debuffs.filter(func(d): return d.get("type", "") != "attack_down")
			log_message("  → Cured Attack Down!")
		elif "Defense Down" in effect:
			if target.has("debuffs"):
				target.debuffs = target.debuffs.filter(func(d): return d.get("type", "") != "defense_down")
			log_message("  → Cured Defense Down!")
		elif "Mind Down" in effect:
			if target.has("debuffs"):
				target.debuffs = target.debuffs.filter(func(d): return d.get("type", "") != "mind_down")
			log_message("  → Cured Mind Down!")

		if cured_ailment != "":
			var current_ailment = str(target.get("ailment", ""))
			if current_ailment == cured_ailment:
				target.ailment = ""
				target.ailment_turn_count = 0
				log_message("  → Cured %s!" % cured_ailment.capitalize())
				# Refresh turn order to remove status indicator
				if battle_mgr:
					battle_mgr.refresh_turn_order()
			else:
				log_message("  → %s doesn't have %s!" % [target.display_name, cured_ailment.capitalize()])

	# ═══════ HEAL ITEMS ═══════
	elif "Heal" in effect:
		# Log item usage with target
		log_message("%s uses %s on %s!" % [current_combatant.display_name, item_name, target.display_name])

		# Parse heal amount from effect string (e.g., "Heal 50 HP")
		var hp_heal = 0
		var mp_heal = 0

		if "HP" in effect:
			# Extract number or percentage before "HP"
			var regex = RegEx.new()
			regex.compile("(\\d+)\\s*%?\\s*[HM]")  # Match "50 HP" or "25% HP" or "50% MaxHP"
			var result = regex.search(effect)
			if result:
				var value_str = result.get_string(1)
				var heal_value = int(value_str)

				# Check if it's a percentage heal
				if "%" in effect:
					hp_heal = int(target.hp_max * heal_value / 100.0)
				else:
					hp_heal = heal_value

		if "MP" in effect:
			# Extract number or percentage before "MP"
			var regex = RegEx.new()
			regex.compile("(\\d+)\\s*%?\\s*[HM]")
			var result = regex.search(effect)
			if result:
				var value_str = result.get_string(1)
				var heal_value = int(value_str)

				# Check if it's a percentage heal
				if "%" in effect:
					mp_heal = int(target.mp_max * heal_value / 100.0)
				else:
					mp_heal = heal_value

		# Apply healing
		if hp_heal > 0:
			var old_hp = target.hp
			target.hp = min(target.hp + hp_heal, target.hp_max)
			var actual_heal = target.hp - old_hp
			log_message("  → Restored %d HP!" % actual_heal)

		if mp_heal > 0:
			var old_mp = target.mp
			target.mp = min(target.mp + mp_heal, target.mp_max)
			var actual_heal = target.mp - old_mp
			log_message("  → Restored %d MP!" % actual_heal)

		# Update displays
		_update_combatant_displays()

	# ═══════ REVIVE ITEMS ═══════
	elif "Revive" in effect:
		# Log item usage with target
		log_message("%s uses %s on %s!" % [current_combatant.display_name, item_name, target.display_name])

		if target.is_ko:
			# Extract revive percentage
			var revive_percent = 25  # Default 25%
			var regex = RegEx.new()
			regex.compile("(\\d+)\\s*%")
			var result = regex.search(effect)
			if result:
				revive_percent = int(result.get_string(1))

			target.is_ko = false
			target.ailment = "Revived"  # Set Revived status (prevents action this turn)
			target.ailment_turn_count = 1  # Lasts 1 turn
			target.hp = max(1, int(target.hp_max * revive_percent / 100.0))
			log_message("  → %s was revived with %d HP! (Can't act this turn)" % [target.display_name, target.hp])
			# Refresh turn order to show revive
			if battle_mgr:
				battle_mgr.refresh_turn_order()
			_update_combatant_displays()
		else:
			log_message("  → %s is not KO'd!" % target.display_name)

	# ═══════ AILMENT/DEBUFF ITEMS (Inflict Status) ═══════
	# Check if this item inflicts an ailment or debuff
	var ailment_to_apply = ""
	var debuff_to_apply = ""

	# Match ailments
	if "Poison" in effect and "Cure" not in effect:
		ailment_to_apply = "poison"
	elif "Burn" in effect and "Cure" not in effect:
		ailment_to_apply = "burn"
	elif "Sleep" in effect and "Cure" not in effect:
		ailment_to_apply = "sleep"
	elif "Freeze" in effect and "Cure" not in effect:
		ailment_to_apply = "freeze"
	elif "Confuse" in effect and "Cure" not in effect:
		ailment_to_apply = "confuse"
	elif "Charm" in effect and "Cure" not in effect:
		ailment_to_apply = "charm"
	elif "Berserk" in effect and "Cure" not in effect:
		ailment_to_apply = "berserk"
	elif "Malaise" in effect and "Cure" not in effect:
		ailment_to_apply = "malaise"
	elif "Mind Block" in effect and "Cure" not in effect:
		ailment_to_apply = "mind_block"

	# Match debuffs
	if "Attack Down" in effect and "Cure" not in effect:
		debuff_to_apply = "atk_down"
	elif "Defense Down" in effect and "Cure" not in effect:
		debuff_to_apply = "def_down"
	elif "Skill Down" in effect and "Cure" not in effect:
		debuff_to_apply = "skl_down"
	elif "Mind Down" in effect and "Cure" not in effect:
		debuff_to_apply = "skl_down"  # Mind Down same as Skill Down

	# Apply ailment if found
	if ailment_to_apply != "":
		# Check if target already has an ailment (only one independent ailment allowed)
		var current_ailment = str(target.get("ailment", ""))
		if current_ailment != "" and current_ailment != "null":
			log_message("%s uses %s on %s!" % [current_combatant.display_name, item_name, target.display_name])
			log_message("  → But %s already has %s! (Ailment blocked)" % [target.display_name, current_ailment.capitalize()])
		else:
			log_message("%s uses %s on %s!" % [current_combatant.display_name, item_name, target.display_name])
			target.ailment = ailment_to_apply
			target.ailment_turn_count = 0  # Track how many turns they've had this ailment
			log_message("  → %s is now %s!" % [target.display_name, ailment_to_apply.capitalize()])
			# Refresh turn order to show status
			if battle_mgr:
				battle_mgr.refresh_turn_order()

	# Apply debuff if found
	if debuff_to_apply != "":
		if ailment_to_apply == "":  # Only log if we didn't already log for ailment
			log_message("%s uses %s on %s!" % [current_combatant.display_name, item_name, target.display_name])

		# Debuffs are negative buffs (-15% for stat debuffs)
		battle_mgr.apply_buff(target, debuff_to_apply, -0.15, duration)

		var debuff_name = debuff_to_apply.replace("_", " ").capitalize()
		log_message("  → %s's %s reduced by 15%% for %d turns!" % [target.display_name, debuff_name, duration])
		# Refresh turn order to show debuff
		if battle_mgr:
			battle_mgr.refresh_turn_order()

	# Consume the item
	var inventory = get_node("/root/aInventorySystem")
	inventory.remove_item(item_id, 1)

	# End turn
	battle_mgr.end_turn()

func _on_defend_pressed() -> void:
	"""Handle Defend action"""
	# Block input during round transitions
	if is_in_round_transition:
		return

	# Check if frozen combatant can act
	if not _check_freeze_action_allowed():
		return

	# Show confirmation dialog
	_show_confirmation_dialog("Do you want to guard?", Callable(self, "_execute_defend"))

func _execute_defend() -> void:
	"""Execute defend action after confirmation"""
	print("[Battle] _execute_defend called!")
	log_message("%s moved into a defensive stance." % current_combatant.display_name)
	current_combatant.is_defending = true

	# End turn
	print("[Battle] Calling battle_mgr.end_turn()")
	battle_mgr.end_turn()

func _on_burst_pressed() -> void:
	"""Handle Burst action - show burst abilities menu"""
	# Block input during round transitions
	if is_in_round_transition:
		return

	# Check if frozen combatant can act
	if not _check_freeze_action_allowed():
		return

	# Only hero can use burst abilities
	if current_combatant.get("id", "") != "hero":
		log_message("Only %s can use Burst abilities!" % _get_hero_display_name())
		return

	if not burst_system:
		log_message("Burst system not available!")
		return

	if not battle_mgr:
		log_message("Battle manager not available!")
		return

	# Get current party IDs (all allies in battle)
	var party_ids: Array = []
	var allies = battle_mgr.get_ally_combatants()
	if allies:
		for combatant in allies:
			if combatant and not combatant.get("is_ko", false):
				var id = combatant.get("id", "")
				if id != "":
					party_ids.append(id)

	if party_ids.is_empty():
		log_message("No active party members!")
		return

	# Get available burst abilities
	var available_bursts = burst_system.get_available_bursts(party_ids)

	if available_bursts.is_empty():
		_show_instruction("No Bursts available.")
		return

	_show_instruction("Choose Burst Ability")

	# Show burst selection menu
	_show_burst_menu(available_bursts)

func _on_run_pressed() -> void:
	"""Handle Run action"""
	# Block input during round transitions
	if is_in_round_transition:
		return

	# Check if frozen combatant can act
	if not _check_freeze_action_allowed():
		return

	# Check if run was already attempted this round
	if battle_mgr.run_attempted_this_round:
		log_message("Already tried to run this round!")
		return

	# Show confirmation dialog
	_show_confirmation_dialog("Do you want to run?", Callable(self, "_execute_run"))

func _execute_run() -> void:
	"""Execute run action after confirmation"""
	# Mark that run was attempted
	battle_mgr.run_attempted_this_round = true

	# Calculate run chance based on enemy HP and level difference
	var run_chance = _calculate_run_chance()

	log_message("%s attempts to escape... (%d%% base chance)" % [current_combatant.display_name, int(run_chance)])

	# ═══════ RUN MINIGAME ═══════
	# Calculate tempo difference (party TPO - enemy TPO)
	var party_tpo = current_combatant.stats.get("TPO", 1)
	var enemies = battle_mgr.get_enemy_combatants()
	var avg_enemy_tpo = 0
	for enemy in enemies:
		avg_enemy_tpo += enemy.stats.get("TPO", 1)
	if enemies.size() > 0:
		avg_enemy_tpo = int(avg_enemy_tpo / enemies.size())
	var tempo_diff = party_tpo - avg_enemy_tpo

	# Get focus stat
	var focus_stat = current_combatant.stats.get("FCS", 1)

	# Get status effects
	var status_effects = []
	var ailment = str(current_combatant.get("ailment", ""))
	if ailment != "":
		status_effects.append(ailment)

	# Launch run minigame
	log_message("  → Navigate through the gaps to escape!")
	var minigame_result = await minigame_mgr.launch_run_minigame(run_chance, tempo_diff, focus_stat, status_effects)

	# Get success from minigame
	var success = minigame_result.get("success", false)

	if success:
		log_message("Escaped successfully!")
		await get_tree().create_timer(1.0).timeout
		battle_mgr.current_state = battle_mgr.BattleState.ESCAPED
		battle_mgr.return_to_overworld()
	else:
		log_message("Couldn't escape!")
		battle_mgr.end_turn()

func _on_status_pressed() -> void:
	"""Handle Status action - view party/enemy information"""
	# Block input during round transitions
	if is_in_round_transition:
		return

	_show_instruction("Choose a character.")

	# Show character picker for status viewing
	_show_status_character_picker()

func _on_switch_panel_pressed() -> void:
	"""Handle switching between action menu panels"""
	_toggle_action_panel()

func _toggle_action_panel() -> void:
	"""Toggle between the two action menu panels with spin animations"""
	# Set animation flag to block further input
	is_panel_switching = true

	is_panel_1_active = not is_panel_1_active

	# Get button references
	var skill_btn = action_menu.get_node_or_null("SkillButton")
	var defend_btn = action_menu.get_node_or_null("DefendButton")
	var attack_btn = action_menu.get_node_or_null("AttackButton")
	var capture_btn = action_menu.get_node_or_null("CaptureButton")
	var burst_btn = action_menu.get_node_or_null("BurstButton")
	var run_btn = action_menu.get_node_or_null("RunButton")
	var status_btn = action_menu.get_node_or_null("StatusButton")
	var item_btn = action_menu.get_node_or_null("ItemButton")

	var anim_duration = 0.3
	var spin_rotation = deg_to_rad(360)  # Full rotation

	if is_panel_1_active:
		# Hide Panel 2 with spin inward animation
		var buttons_to_hide = [burst_btn, run_btn, status_btn, item_btn]
		for btn in buttons_to_hide:
			if btn:
				_animate_button_hide(btn, anim_duration, spin_rotation)

		# Wait a moment before showing new buttons
		await get_tree().create_timer(anim_duration * 0.5).timeout

		# Show Panel 1 with spin outward animation
		var buttons_to_show = [skill_btn, defend_btn, attack_btn, capture_btn]
		for btn in buttons_to_show:
			if btn:
				btn.visible = true
				btn.modulate.a = 0.0
				btn.scale = Vector2(0.5, 0.5)
				btn.rotation = -spin_rotation
				_animate_button_show(btn, anim_duration, spin_rotation)
	else:
		# Hide Panel 1 with spin inward animation
		var buttons_to_hide = [skill_btn, defend_btn, attack_btn, capture_btn]
		for btn in buttons_to_hide:
			if btn:
				_animate_button_hide(btn, anim_duration, spin_rotation)

		# Wait a moment before showing new buttons
		await get_tree().create_timer(anim_duration * 0.5).timeout

		# Show Panel 2 with spin outward animation
		var buttons_to_show = [burst_btn, run_btn, status_btn, item_btn]
		for btn in buttons_to_show:
			if btn:
				btn.visible = true
				btn.modulate.a = 0.0
				btn.scale = Vector2(0.5, 0.5)
				btn.rotation = -spin_rotation
				_animate_button_show(btn, anim_duration, spin_rotation)

	# Wait for all animations to complete, then clear animation flag
	await get_tree().create_timer(anim_duration).timeout
	is_panel_switching = false

func _animate_button_hide(btn: Button, duration: float, rotation: float) -> void:
	"""Animate button spinning inward and fading out"""
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_BACK)

	# Spin and scale down
	tween.tween_property(btn, "rotation", rotation, duration)
	tween.tween_property(btn, "scale", Vector2(0.1, 0.1), duration)
	tween.tween_property(btn, "modulate:a", 0.0, duration * 0.7)

	await tween.finished
	btn.visible = false
	# Reset for next time
	btn.rotation = 0.0
	btn.scale = Vector2(1.0, 1.0)
	btn.modulate.a = 1.0

func _animate_button_show(btn: Button, duration: float, rotation: float) -> void:
	"""Animate button spinning outward and fading in"""
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)

	# Spin and scale up
	tween.tween_property(btn, "rotation", 0.0, duration)
	tween.tween_property(btn, "scale", Vector2(1.0, 1.0), duration)
	tween.tween_property(btn, "modulate:a", 1.0, duration * 0.7)

func _show_status_character_picker() -> void:
	"""Show a character picker to select whose status to view"""
	# Initialize arrays
	status_picker_buttons = []
	status_picker_data = []
	selected_status_index = 0

	# Create modal background
	status_picker_modal = ColorRect.new()
	status_picker_modal.color = Color(0, 0, 0, 0.7)
	status_picker_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	status_picker_modal.z_index = 99
	status_picker_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(status_picker_modal)

	# Create picker panel
	status_picker_panel = PanelContainer.new()
	status_picker_panel.custom_minimum_size = Vector2(500, 400)

	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = COLOR_INK_CHARCOAL  # Dark background
	panel_style.border_width_left = 3
	panel_style.border_width_right = 3
	panel_style.border_width_top = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = COLOR_SKY_CYAN  # Cyan neon border
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.shadow_size = 6
	panel_style.shadow_color = Color(COLOR_SKY_CYAN.r, COLOR_SKY_CYAN.g, COLOR_SKY_CYAN.b, 0.4)  # Cyan glow
	status_picker_panel.add_theme_stylebox_override("panel", panel_style)

	status_picker_panel.position = get_viewport_rect().size / 2 - status_picker_panel.custom_minimum_size / 2
	status_picker_panel.position.y -= 60  # Move up 60px
	status_picker_panel.z_index = 100
	status_picker_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox = VBoxContainer.new()
	status_picker_panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "=== View Character Status ==="
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", COLOR_BUBBLE_MAGENTA)  # Pink magenta title
	vbox.add_child(title)

	# Instructions
	var instructions = Label.new()
	instructions.text = "Use ↑↓ to navigate, A to select, B to cancel"
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.add_theme_font_size_override("font_size", 12)
	instructions.add_theme_color_override("font_color", COLOR_MILK_WHITE)  # White text
	vbox.add_child(instructions)

	# Scroll container for character list
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 280)
	vbox.add_child(scroll)

	var character_list = VBoxContainer.new()
	scroll.add_child(character_list)

	# Add allies
	var allies = battle_mgr.get_ally_combatants()
	if allies.size() > 0:
		var ally_header = Label.new()
		ally_header.text = "\n--- Party Members ---"
		ally_header.add_theme_font_size_override("font_size", 14)
		ally_header.add_theme_color_override("font_color", COLOR_ELECTRIC_LIME)  # Lime green for allies
		character_list.add_child(ally_header)

		for ally in allies:
			var btn = Button.new()
			var hp_text = "%d/%d HP" % [ally.hp, ally.hp_max]
			var mp_text = "%d/%d MP" % [ally.mp, ally.mp_max]
			var status_text = ""
			if ally.is_ko:
				status_text = " [KO]"
			elif ally.get("ailment", "") != "":
				status_text = " [%s]" % String(ally.ailment).capitalize()

			btn.text = "%s - %s | %s%s" % [ally.display_name, hp_text, mp_text, status_text]
			btn.custom_minimum_size = Vector2(460, 30)
			btn.pressed.connect(_confirm_status_selection)
			character_list.add_child(btn)
			status_picker_buttons.append(btn)
			status_picker_data.append(ally)

	# Add enemies
	var enemies = battle_mgr.get_enemy_combatants()
	if enemies.size() > 0:
		var enemy_header = Label.new()
		enemy_header.text = "\n--- Enemies ---"
		enemy_header.add_theme_font_size_override("font_size", 14)
		enemy_header.add_theme_color_override("font_color", COLOR_CITRUS_YELLOW)  # Yellow for enemies
		character_list.add_child(enemy_header)

		for enemy in enemies:
			var btn = Button.new()
			var hp_text = "%d/%d HP" % [enemy.hp, enemy.hp_max]
			var status_text = ""
			if enemy.is_ko:
				status_text = " [KO]"
			elif enemy.get("ailment", "") != "":
				status_text = " [%s]" % String(enemy.ailment).capitalize()

			btn.text = "%s - %s%s" % [enemy.display_name, hp_text, status_text]
			btn.custom_minimum_size = Vector2(460, 30)
			btn.pressed.connect(_confirm_status_selection)
			character_list.add_child(btn)
			status_picker_buttons.append(btn)
			status_picker_data.append(enemy)

	# Close button
	var close_btn = Button.new()
	close_btn.text = "Close (B)"
	close_btn.custom_minimum_size = Vector2(120, 30)
	close_btn.pressed.connect(_close_status_picker)
	vbox.add_child(close_btn)

	# Highlight first character
	if status_picker_buttons.size() > 0:
		_highlight_status_button(0)

	add_child(status_picker_panel)

	# Set cooldown to prevent immediate button press
	input_cooldown = input_cooldown_duration

func _calculate_run_chance() -> float:
	"""Calculate run chance based on enemy HP percentage and level difference"""
	const BASE_RUN_CHANCE: float = 5.0  # Base 5% escape chance (18° gap)
	const MAX_HP_BONUS: float = 40.0
	const _MAX_LEVEL_BONUS: float = 20.0  # Reserved for future level-based calculations
	const LEVEL_BONUS_PER_LEVEL: float = 2.0

	# Calculate enemy HP percentage bonus (0-40%)
	var enemies = battle_mgr.get_enemy_combatants()
	var total_enemy_hp_current: float = 0.0
	var total_enemy_hp_max: float = 0.0

	for enemy in enemies:
		total_enemy_hp_current += enemy.hp
		total_enemy_hp_max += enemy.hp_max

	var hp_loss_percent: float = 0.0
	if total_enemy_hp_max > 0:
		hp_loss_percent = 1.0 - (total_enemy_hp_current / total_enemy_hp_max)

	var hp_bonus: float = hp_loss_percent * MAX_HP_BONUS

	# Calculate level difference bonus (0-20%, 2% per level up to 10 levels)
	var allies = battle_mgr.get_ally_combatants()
	var total_ally_level: int = 0
	var total_enemy_level: int = 0

	for ally in allies:
		total_ally_level += ally.level

	for enemy in enemies:
		total_enemy_level += enemy.level

	var level_difference: int = total_ally_level - total_enemy_level
	var level_bonus: float = 0.0
	if level_difference > 0:
		level_bonus = min(level_difference, 10) * LEVEL_BONUS_PER_LEVEL

	# Check for run chance bonus from items (Flash Pop buff on current combatant)
	var item_bonus: float = 0.0
	if current_combatant and current_combatant.has("buffs"):
		for buff in current_combatant.buffs:
			if buff.get("type", "") == "run_boost":
				item_bonus = buff.get("value", 0.0)
				break

	# Calculate final run chance
	var final_chance: float = BASE_RUN_CHANCE + hp_bonus + level_bonus + item_bonus

	# Log breakdown for debugging
	if item_bonus > 0:
		log_message("  Base: %d%% | HP Bonus: +%d%% | Level Bonus: +%d%% | Item Bonus: +%d%%" % [
			int(BASE_RUN_CHANCE),
			int(hp_bonus),
			int(level_bonus),
			int(item_bonus)
		])
	else:
		log_message("  Base: %d%% | HP Bonus: +%d%% | Level Bonus: +%d%%" % [
			int(BASE_RUN_CHANCE),
			int(hp_bonus),
			int(level_bonus)
		])

	return final_chance

## ═══════════════════════════════════════════════════════════════
## TARGET SELECTION
## ═══════════════════════════════════════════════════════════════

func _on_enemy_panel_input(event: InputEvent, target: Dictionary) -> void:
	"""Handle clicks on enemy panels"""
	if event is InputEventMouseButton:
		var mb_event = event as InputEventMouseButton
		if mb_event.pressed and mb_event.button_index == MOUSE_BUTTON_LEFT:
			if awaiting_target_selection:
				# Check if this target is valid
				if target in target_candidates:
					if awaiting_capture_target:
						# Attempting capture
						await _execute_capture(target)
					elif awaiting_item_target:
						# Using an item
						_execute_item_usage(target)
					elif awaiting_skill_selection:
						# Using a skill
						_clear_target_highlights()
						awaiting_target_selection = false
						awaiting_skill_selection = false
						await _execute_skill_single(target)

						# Check if battle is over
						var battle_ended = await battle_mgr._check_battle_end()
						if not battle_ended:
							battle_mgr.end_turn()
					elif not selected_burst.is_empty():
						# Using a burst ability (single target)
						_clear_target_highlights()
						awaiting_target_selection = false
						await _execute_burst_on_target(target)

						# Check if battle is over
						var battle_ended = await battle_mgr._check_battle_end()
						if not battle_ended:
							battle_mgr.end_turn()
					else:
						# Regular attack
						_execute_attack(target)

func _on_ally_panel_input(event: InputEvent, target: Dictionary) -> void:
	"""Handle clicks on ally panels (for item targeting)"""
	if event is InputEventMouseButton:
		var mb_event = event as InputEventMouseButton
		if mb_event.pressed and mb_event.button_index == MOUSE_BUTTON_LEFT:
			if awaiting_target_selection and awaiting_item_target:
				# Check if this target is valid
				if target in target_candidates:
					_execute_item_usage(target)

func _highlight_target_candidates() -> void:
	"""Highlight valid targets with a visual indicator"""
	# Get currently selected target ID
	var selected_target_id = ""
	if selected_target_index >= 0 and selected_target_index < target_candidates.size():
		selected_target_id = target_candidates[selected_target_index].id

	# Highlight enemies
	for child in enemy_slots.get_children():
		var combatant_id = child.get_meta("combatant_id", "")
		var is_candidate = target_candidates.any(func(c): return c.id == combatant_id)

		if is_candidate:
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.3, 0.2, 0.2, 0.9)
			style.border_width_left = 4
			style.border_width_right = 4
			style.border_width_top = 4
			style.border_width_bottom = 4

			# Red border for currently selected, yellow for others
			if combatant_id == selected_target_id:
				style.border_color = Color(1.0, 0.2, 0.2, 1.0)  # Red - currently selected
			else:
				style.border_color = Color(1.0, 1.0, 0.0, 1.0)  # Yellow - targetable

			child.add_theme_stylebox_override("panel", style)

	# Highlight allies (for items)
	for child in ally_slots.get_children():
		var combatant_id = child.get_meta("combatant_id", "")
		var is_candidate = target_candidates.any(func(c): return c.id == combatant_id)

		if is_candidate:
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.2, 0.3, 0.2, 0.9)
			style.border_width_left = 4
			style.border_width_right = 4
			style.border_width_top = 4
			style.border_width_bottom = 4

			# Red border for currently selected, green for others
			if combatant_id == selected_target_id:
				style.border_color = Color(1.0, 0.2, 0.2, 1.0)  # Red - currently selected
			else:
				style.border_color = Color(0.0, 1.0, 0.0, 1.0)  # Green - targetable

			child.add_theme_stylebox_override("panel", style)

func _clear_target_highlights() -> void:
	"""Remove targeting highlights from all panels"""
	for child in enemy_slots.get_children():
		# Reset to default panel style
		child.remove_theme_stylebox_override("panel")
	for child in ally_slots.get_children():
		# Reset to default panel style
		child.remove_theme_stylebox_override("panel")

## ═══════════════════════════════════════════════════════════════
## ENEMY AI
## ═══════════════════════════════════════════════════════════════

func _execute_enemy_ai() -> void:
	"""Execute AI for enemy turn"""
	await get_tree().create_timer(0.5).timeout  # Brief delay

	# Clear defending status when attacking
	current_combatant.is_defending = false

	# Simple AI: attack random ally
	var allies = battle_mgr.get_ally_combatants()
	var alive_allies = allies.filter(func(a): return not a.is_ko)

	if alive_allies.size() > 0:
		var target = alive_allies[randi() % alive_allies.size()]

		# Start building turn message
		start_turn_message()
		add_turn_line("%s attacked %s!" % [current_combatant.display_name, target.display_name])

		# First, check if the attack hits
		var hit_check = combat_resolver.check_physical_hit(current_combatant, target)

		if not hit_check.hit:
			# Miss!
			_show_miss_feedback()  # Show big MISS text
			add_turn_line("But it missed!")
			add_turn_line("(Hit chance: %d%%, rolled %d)" % [int(hit_check.hit_chance), hit_check.roll])
			queue_turn_message()  # Queue the full turn message
			print("[Battle] Enemy Miss! Hit chance: %.1f%%, Roll: %d" % [hit_check.hit_chance, hit_check.roll])
		else:
			# Hit! Now roll for critical
			var crit_check = combat_resolver.check_critical_hit(current_combatant, {"defender": target})
			var is_crit = crit_check.crit

			# Calculate mind type effectiveness
			var type_bonus = combat_resolver.get_mind_type_bonus(current_combatant, target)

			# Check weapon type weakness (check now, record later after damage)
			var weapon_weakness_hit = combat_resolver.check_weapon_weakness(current_combatant, target)

			# Critical hits also count as weakness hits for stumbling
			var crit_weakness_hit = is_crit

			# Calculate damage
			var damage_result = combat_resolver.calculate_physical_damage(
				current_combatant,
				target,
				{
					"potency": 100,
					"is_crit": is_crit,
					"type_bonus": type_bonus
				}
			)

			var damage = damage_result.damage
			var is_stumble = damage_result.is_stumble

			# Apply damage
			target.hp -= damage

			# Wake up if asleep
			_wake_if_asleep(target)

			if target.hp <= 0:
				target.hp = 0
				_set_fainted(target)

				# Record kill for morality system (if enemy)
				if not target.get("is_ally", false):
					battle_mgr.record_enemy_defeat(target, false)  # false = kill

			# Record weakness hits AFTER damage (only if target still alive)
			var weakness_line = ""
			if not target.is_ko and (weapon_weakness_hit or crit_weakness_hit):
				var became_fallen = await battle_mgr.record_weapon_weakness_hit(target)
				if weapon_weakness_hit:
					weakness_line = "%s receives a WEAPON WEAKNESS!" % target.display_name
				elif crit_weakness_hit:
					weakness_line = "%s receives a CRITICAL STUMBLE!" % target.display_name
				if became_fallen:
					weakness_line += " %s fell!" % target.display_name

			# Add weakness line if present
			if weakness_line != "":
				add_turn_line(weakness_line)

			# Build hit message line
			var hit_msg = "%s is hit for %d damage!" % [target.display_name, damage]

			# Add special effects to message
			var effect_parts = []
			if is_crit:
				effect_parts.append("CRITICAL")
			if type_bonus > 0.0:
				effect_parts.append("Super Effective")
			elif type_bonus < 0.0:
				effect_parts.append("Not Very Effective")
			if target.get("is_defending", false):
				effect_parts.append("Guarded")

			if not effect_parts.is_empty():
				hit_msg = "%s (%s)" % [hit_msg, ", ".join(effect_parts)]

			add_turn_line(hit_msg)

			# Add KO or status line
			if target.is_ko:
				add_turn_line("%s fainted!" % target.display_name)
			elif weakness_line == "":  # Only show HP if no weakness
				add_turn_line("%s has %d HP left." % [target.display_name, target.hp])

			# Queue the full turn message
			queue_turn_message()

			# Debug: show hit, crit, and damage breakdown
			var hit_breakdown = hit_check.breakdown
			var crit_breakdown = crit_check.breakdown
			var dmg_breakdown = damage_result.breakdown
			print("[Battle] Enemy Hit! Chance: %.1f%% (ACC %.1f - EVA %.1f), Roll: %d" % [
				hit_check.hit_chance, hit_breakdown.hit_percent, hit_breakdown.eva_percent, hit_check.roll
			])
			print("[Battle] Enemy Crit: %s | Chance: %.1f%% (Base %.1f + BRW %.1f + Weapon %d), Roll: %d, Mult: %.2fx" % [
				"YES" if is_crit else "NO", crit_check.crit_chance, crit_breakdown.base,
				crit_breakdown.brw_bonus, crit_breakdown.weapon_bonus, crit_check.roll, crit_breakdown.crit_mult
			])
			print("[Battle] Enemy Damage: PreMit=%.1f, AtkPower=%.1f, Raw=%.1f, Final=%d (Min=%d)" % [
				dmg_breakdown.pre_mit, dmg_breakdown.atk_power, dmg_breakdown.raw, damage, dmg_breakdown.min_damage
			])

			# Add burst gauge (player gains burst when taking damage)
			battle_mgr.add_burst(6)  # +6 for taking damage
			if is_crit:
				battle_mgr.add_burst(4)  # +4 for enemy crit (player gains burst)
			if is_stumble:
				battle_mgr.add_burst(8)  # +8 for weakness

			_update_combatant_displays()
			_update_burst_gauge()

			# Refresh turn order if combatant was KO'd
			if target.is_ko:
				# Animate falling and then re-sort turn order
				if turn_order_display:
					await turn_order_display.animate_ko_fall(target.id)
				await battle_mgr.refresh_turn_order()
			elif turn_order_display:
				turn_order_display.update_combatant_hp(target.id)

	await get_tree().create_timer(1.0).timeout

	# End turn
	battle_mgr.end_turn()

func _execute_berserk_action() -> void:
	"""Execute berserk behavior - attack random target including allies"""
	await get_tree().create_timer(0.5).timeout

	# Clear defending status
	current_combatant.is_defending = false

	# Get all alive combatants (allies and enemies)
	var all_targets = []
	for c in battle_mgr.combatants:
		if not c.is_ko and c.id != current_combatant.id:  # Don't target self
			all_targets.append(c)

	if all_targets.size() > 0:
		var target = all_targets[randi() % all_targets.size()]
		log_message("  → %s attacks %s in a berserk rage!" % [current_combatant.display_name, target.display_name])

		# Execute attack (same as normal attack)
		await _execute_attack(target)
	else:
		log_message("  → No one to attack!")
		await get_tree().create_timer(1.0).timeout

	battle_mgr.end_turn()

func _execute_charm_action() -> void:
	"""Execute charm behavior - use heal/buff items on enemies"""
	await get_tree().create_timer(0.5).timeout

	# Get inventory system
	var inventory = get_node("/root/aInventorySystem")
	var item_counts = inventory.get_counts_dict()
	var item_defs = inventory.get_item_defs()

	# Get heal/buff items from inventory
	var heal_buff_items = []
	for item_id in item_counts.keys():
		var quantity = item_counts[item_id]
		if quantity > 0:
			var item_def = item_defs.get(item_id, {})
			var category = _categorize_battle_item(item_id, item_def.get("name", ""), item_def)
			if category in ["Healing", "Buffs"]:
				heal_buff_items.append({"id": item_id, "def": item_def})

	if heal_buff_items.size() > 0:
		# Pick random item
		var item_data = heal_buff_items[randi() % heal_buff_items.size()]
		var item_id = item_data.id
		var item_def = item_data.def

		# Pick random alive enemy as target
		var enemies = battle_mgr.get_enemy_combatants()
		var alive_enemies = enemies.filter(func(e): return not e.is_ko)

		if alive_enemies.size() > 0:
			var target = alive_enemies[randi() % alive_enemies.size()]
			log_message("  → %s uses %s on %s!" % [
				current_combatant.display_name,
				item_def.get("name", item_id),
				target.display_name
			])

			# Use the item
			inventory.remove_item(item_id, 1)
			await _execute_item_usage(target)
		else:
			log_message("  → No enemies to help!")
	else:
		log_message("  → No healing or buff items to use!")

	await get_tree().create_timer(1.0).timeout
	battle_mgr.end_turn()

## ═══════════════════════════════════════════════════════════════
## UI UPDATES
## ═══════════════════════════════════════════════════════════════

func _update_burst_gauge() -> void:
	"""Update burst gauge display with smooth animation"""
	if burst_gauge_bar:
		burst_gauge_bar.max_value = battle_mgr.BURST_GAUGE_MAX
		# Animate the burst gauge fill smoothly
		var tween = create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(burst_gauge_bar, "value", battle_mgr.burst_gauge, 0.8)

func start_turn_message() -> void:
	"""Start building a new turn message"""
	turn_message_lines.clear()

func add_turn_line(line: String) -> void:
	"""Add a line to the current turn message"""
	turn_message_lines.append(line)

func queue_turn_message() -> void:
	"""Queue the accumulated turn message as a single message"""
	if turn_message_lines.is_empty():
		return

	# Join all lines with newlines
	var full_message = "\n".join(turn_message_lines)
	log_message(full_message)
	turn_message_lines.clear()

func log_message(message: String) -> void:
	"""Add a message to the message queue for Pokemon-style display"""
	message_queue.append(message)
	print("[Battle] Queued: " + message)

	# Start processing queue if not already displaying
	if not is_displaying_message:
		_display_next_message()

func _display_next_message() -> void:
	"""Display the next message in the queue with typewriter effect"""
	if message_queue.is_empty():
		is_displaying_message = false
		_hide_continue_indicator()
		return

	is_displaying_message = true
	is_typewriter_active = true

	# Get next message
	var message = message_queue.pop_front()
	current_message_full = message

	# Clear battle log
	if battle_log:
		battle_log.clear()

	# Start typewriter effect
	_start_typewriter_effect(message)

func _continue_to_next_message() -> void:
	"""Continue to next message when player presses accept"""
	if not is_displaying_message:
		return

	# If typewriter is still active, skip to full message
	if is_typewriter_active:
		_skip_typewriter_effect()
		return

	# Display next message
	_display_next_message()

func _start_typewriter_effect(message: String) -> void:
	"""Start character-by-character reveal of message"""
	if not battle_log:
		return

	# Kill any existing typewriter tween
	if typewriter_tween:
		typewriter_tween.kill()
		typewriter_tween = null

	# Calculate duration based on message length (faster than typical for battle pacing)
	var chars_per_second = 60.0  # 60 characters per second
	var duration = float(message.length()) / chars_per_second

	# Use a custom method to reveal text character by character
	var char_index = 0
	var reveal_interval = 1.0 / chars_per_second

	# Create a timer-based typewriter effect
	_typewriter_reveal_next_char(message, 0, reveal_interval)

func _typewriter_reveal_next_char(message: String, char_index: int, interval: float) -> void:
	"""Reveal one character at a time"""
	if not battle_log or not is_typewriter_active:
		return

	if char_index >= message.length():
		# Finished revealing all characters
		is_typewriter_active = false
		_show_continue_indicator()
		return

	# Append next character
	battle_log.clear()
	battle_log.append_text(message.substr(0, char_index + 1))

	# Schedule next character
	await get_tree().create_timer(interval).timeout
	_typewriter_reveal_next_char(message, char_index + 1, interval)

func _skip_typewriter_effect() -> void:
	"""Skip to showing the full message immediately"""
	if not battle_log:
		return

	# Stop typewriter
	is_typewriter_active = false

	# Show full message
	battle_log.clear()
	battle_log.append_text(current_message_full)

	# Show continue indicator
	_show_continue_indicator()

func _wait_for_message_queue() -> void:
	"""Wait until all messages in queue have been displayed and player has continued"""
	# Wait until message queue is empty and no message is displaying
	while not message_queue.is_empty() or is_displaying_message:
		await get_tree().process_frame

	# Brief pause after messages clear for smooth flow
	await get_tree().create_timer(0.1).timeout

func _create_instruction_popup() -> void:
	"""Create the instruction message popup that appears above battle log"""
	instruction_popup = PanelContainer.new()
	instruction_popup.custom_minimum_size = Vector2(560, 50)  # Same width as BattleLogPanel

	# Style with cyan neon border to match Core vibe
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_INK_CHARCOAL
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = COLOR_SKY_CYAN  # Cyan neon border
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_size = 6
	style.shadow_color = Color(COLOR_SKY_CYAN.r, COLOR_SKY_CYAN.g, COLOR_SKY_CYAN.b, 0.4)  # Cyan glow
	style.content_margin_left = 15
	style.content_margin_right = 15
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	instruction_popup.add_theme_stylebox_override("panel", style)

	# Create label
	instruction_label = Label.new()
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	instruction_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
	instruction_label.add_theme_font_size_override("font_size", 16)
	instruction_popup.add_child(instruction_label)

	# Position above BattleLogPanel (starts hidden below)
	# BattleLogPanel: offset_left=360, offset_top=-200, offset_right=920, offset_bottom=-50
	instruction_popup.position = Vector2(360, get_viewport().get_visible_rect().size.y - 200)  # Start at battle log top
	instruction_popup.modulate.a = 0.0  # Start invisible

	add_child(instruction_popup)

func _show_instruction(message: String) -> void:
	"""Show instruction popup with animation sliding up from battle log"""
	if not instruction_popup or not instruction_label:
		return

	instruction_label.text = message

	# Starting position (at battle log top)
	var start_y = get_viewport().get_visible_rect().size.y - 200
	# End position (60 pixels above battle log)
	var end_y = start_y - 60

	instruction_popup.position.y = start_y
	instruction_popup.modulate.a = 0.0

	# Animate up and fade in
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(instruction_popup, "position:y", end_y, 0.3)
	tween.tween_property(instruction_popup, "modulate:a", 1.0, 0.2)

func _hide_instruction() -> void:
	"""Hide instruction popup with animation sliding back down"""
	if not instruction_popup:
		return

	# Animate down and fade out
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(instruction_popup, "position:y", get_viewport().get_visible_rect().size.y - 200, 0.2)
	tween.tween_property(instruction_popup, "modulate:a", 0.0, 0.15)

func _create_continue_indicator() -> void:
	"""Create the 'Press A to continue' indicator"""
	continue_indicator = Label.new()
	continue_indicator.text = "▼"  # Down arrow
	continue_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	continue_indicator.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	continue_indicator.add_theme_color_override("font_color", COLOR_ELECTRIC_LIME)
	continue_indicator.add_theme_font_size_override("font_size", 20)

	# Position in bottom-right corner of battle log panel
	# BattleLogPanel: offset_left=360, offset_top=-200, offset_right=920, offset_bottom=-50
	continue_indicator.position = Vector2(880, get_viewport().get_visible_rect().size.y - 70)
	continue_indicator.size = Vector2(30, 20)
	continue_indicator.modulate.a = 0.0  # Start invisible

	add_child(continue_indicator)

func _show_continue_indicator() -> void:
	"""Show the continue indicator with blinking animation"""
	if not continue_indicator:
		return

	# Kill any existing tween
	if continue_indicator_tween:
		continue_indicator_tween.kill()

	# Create blinking animation
	continue_indicator_tween = create_tween()
	continue_indicator_tween.set_loops()
	continue_indicator_tween.tween_property(continue_indicator, "modulate:a", 1.0, 0.5).set_ease(Tween.EASE_IN_OUT)
	continue_indicator_tween.tween_property(continue_indicator, "modulate:a", 0.3, 0.5).set_ease(Tween.EASE_IN_OUT)

func _hide_continue_indicator() -> void:
	"""Hide the continue indicator"""
	if not continue_indicator:
		return

	# Kill any existing tween
	if continue_indicator_tween:
		continue_indicator_tween.kill()
		continue_indicator_tween = null

	continue_indicator.modulate.a = 0.0

func _show_miss_feedback() -> void:
	"""Show big MISS text in center of screen that fades away in 0.5 seconds"""
	# Create miss label
	var miss_label = Label.new()
	miss_label.text = "MISS!"
	miss_label.add_theme_font_size_override("font_size", 80)  # Big font
	miss_label.add_theme_color_override("font_color", COLOR_CITRUS_YELLOW)  # Yellow color
	miss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	miss_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Center it on screen
	miss_label.set_anchors_preset(Control.PRESET_CENTER)
	miss_label.custom_minimum_size = Vector2(400, 100)
	miss_label.position = Vector2(
		get_viewport_rect().size.x / 2 - 200,
		get_viewport_rect().size.y / 2 - 50
	)
	miss_label.z_index = 200  # High z-index to appear above everything

	add_child(miss_label)

	# Fade out and remove after 0.5 seconds
	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(miss_label, "modulate:a", 0.0, 0.5)

	# Remove label after fade completes
	await tween.finished
	miss_label.queue_free()

## ═══════════════════════════════════════════════════════════════
## CONFIRMATION DIALOG (YES/NO)
## ═══════════════════════════════════════════════════════════════

func _show_confirmation_dialog(message: String, on_confirm: Callable) -> void:
	"""Show a Yes/No confirmation dialog"""
	_show_instruction(message)

	awaiting_confirmation = true
	confirmation_callback = on_confirm

	# Disable action menu while showing confirmation
	_disable_action_menu()

	# Create confirmation panel
	confirmation_panel = PanelContainer.new()
	confirmation_panel.custom_minimum_size = Vector2(300, 120)

	# Style the panel with cyan neon border
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_INK_CHARCOAL
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = COLOR_SKY_CYAN  # Cyan neon border
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_size = 6
	style.shadow_color = Color(COLOR_SKY_CYAN.r, COLOR_SKY_CYAN.g, COLOR_SKY_CYAN.b, 0.4)  # Cyan glow
	confirmation_panel.add_theme_stylebox_override("panel", style)

	# Create VBox layout
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	confirmation_panel.add_child(vbox)

	# Add message label
	var label = Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
	vbox.add_child(label)

	# Add button container
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(hbox)

	# Create Yes button
	confirmation_yes_button = Button.new()
	confirmation_yes_button.text = "Yes"
	confirmation_yes_button.custom_minimum_size = Vector2(100, 40)
	confirmation_yes_button.pressed.connect(_on_confirmation_yes)
	hbox.add_child(confirmation_yes_button)

	# Create No button
	confirmation_no_button = Button.new()
	confirmation_no_button.text = "No"
	confirmation_no_button.custom_minimum_size = Vector2(100, 40)
	confirmation_no_button.pressed.connect(_on_confirmation_no)
	hbox.add_child(confirmation_no_button)

	# Position in center of screen
	confirmation_panel.position = Vector2(
		(get_viewport().get_visible_rect().size.x - 300) / 2,
		(get_viewport().get_visible_rect().size.y - 120) / 2
	)

	add_child(confirmation_panel)

	# Focus Yes button by default
	confirmation_yes_button.grab_focus()

func _on_confirmation_yes() -> void:
	"""Handle Yes button press"""
	print("[Battle] Confirmation Yes pressed")

	# Save callback before closing dialog (which clears it)
	var callback = confirmation_callback
	print("[Battle] Saved callback, is_valid: ", callback.is_valid())

	_close_confirmation_dialog()
	_hide_instruction()

	# Call the confirmation callback
	if callback.is_valid():
		print("[Battle] Executing callback...")
		callback.call()
		print("[Battle] Callback executed")
	else:
		print("[Battle] ERROR: Callback is not valid!")

func _on_confirmation_no() -> void:
	"""Handle No button press"""
	_close_confirmation_dialog()
	_hide_instruction()

	# Re-enable action menu
	_enable_action_menu()

func _close_confirmation_dialog() -> void:
	"""Close the confirmation dialog"""
	awaiting_confirmation = false
	confirmation_callback = Callable()

	if confirmation_panel:
		confirmation_panel.queue_free()
		confirmation_panel = null

	confirmation_yes_button = null
	confirmation_no_button = null

## ═══════════════════════════════════════════════════════════════
## SKILL MENU & EXECUTION
## ═══════════════════════════════════════════════════════════════

func _show_skill_menu(skill_menu: Array) -> void:
	"""Show skill selection menu with sigils"""
	# Disable and dim action menu
	_disable_action_menu()

	# Store current menu
	current_skill_menu = skill_menu
	skill_menu_buttons = []
	selected_skill_index = 0

	# Create skill menu panel
	skill_menu_panel = PanelContainer.new()
	skill_menu_panel.custom_minimum_size = Vector2(400, 0)

	# Style the panel with cyan neon Core vibe
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_INK_CHARCOAL
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = COLOR_SKY_CYAN  # Cyan neon border
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_size = 6
	style.shadow_color = Color(COLOR_SKY_CYAN.r, COLOR_SKY_CYAN.g, COLOR_SKY_CYAN.b, 0.4)  # Cyan glow
	skill_menu_panel.add_theme_stylebox_override("panel", style)

	# Create VBox for menu items
	var vbox = VBoxContainer.new()
	skill_menu_panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Select a Skill"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", COLOR_MILK_WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Show current mind type
	var current_type = String(current_combatant.get("mind_type", "omega")).capitalize()
	var type_label = Label.new()
	type_label.text = "Current Type: %s" % current_type
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.add_theme_font_size_override("font_size", 14)
	type_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
	vbox.add_child(type_label)

	# Add "Change Type" button (only for player)
	if current_combatant.get("is_ally", false) and current_combatant.get("id") == "hero":
		var changed_this_round = current_combatant.get("changed_type_this_round", false)
		var change_type_btn = Button.new()
		change_type_btn.text = "⚡ CHANGE MIND TYPE ⚡" if not changed_this_round else "Change Mind Type (Used)"
		change_type_btn.custom_minimum_size = Vector2(380, 50)
		change_type_btn.disabled = changed_this_round
		change_type_btn.pressed.connect(_on_change_type_button_pressed)

		# Style the button to make it stand out
		if not changed_this_round:
			var btn_style = StyleBoxFlat.new()
			btn_style.bg_color = COLOR_BUBBLE_MAGENTA.darkened(0.3)  # Pink/magenta background
			btn_style.border_width_left = 2
			btn_style.border_width_right = 2
			btn_style.border_width_top = 2
			btn_style.border_width_bottom = 2
			btn_style.border_color = COLOR_BUBBLE_MAGENTA  # Bright magenta border
			btn_style.corner_radius_top_left = 8
			btn_style.corner_radius_top_right = 8
			btn_style.corner_radius_bottom_left = 8
			btn_style.corner_radius_bottom_right = 8
			change_type_btn.add_theme_stylebox_override("normal", btn_style)

			var btn_style_hover = StyleBoxFlat.new()
			btn_style_hover.bg_color = COLOR_BUBBLE_MAGENTA.darkened(0.1)  # Brighter on hover
			btn_style_hover.border_width_left = 3
			btn_style_hover.border_width_right = 3
			btn_style_hover.border_width_top = 3
			btn_style_hover.border_width_bottom = 3
			btn_style_hover.border_color = COLOR_BUBBLE_MAGENTA.lightened(0.2)
			btn_style_hover.corner_radius_top_left = 8
			btn_style_hover.corner_radius_top_right = 8
			btn_style_hover.corner_radius_bottom_left = 8
			btn_style_hover.corner_radius_bottom_right = 8
			change_type_btn.add_theme_stylebox_override("hover", btn_style_hover)
			change_type_btn.add_theme_stylebox_override("focus", btn_style_hover)

			change_type_btn.add_theme_color_override("font_color", COLOR_MILK_WHITE)
			change_type_btn.add_theme_font_size_override("font_size", 18)

			# Add to navigation array so it's selectable
			skill_menu_buttons.append(change_type_btn)

		vbox.add_child(change_type_btn)

	# Add separator
	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	# Add skill buttons
	for i in range(skill_menu.size()):
		var menu_entry = skill_menu[i]
		var sigil_name = menu_entry.sigil_name
		var skill_data = menu_entry.skill_data
		var skill_name = String(skill_data.get("name", "Unknown"))
		var skill_element = String(skill_data.get("element", "none"))
		var skill_element_cap = skill_element.capitalize()
		var mp_cost = int(skill_data.get("cost_mp", 0))
		var can_afford = menu_entry.can_afford

		# Check if skill element matches current mind type
		var current_mind_type = String(current_combatant.get("mind_type", "omega")).to_lower()
		var type_matches = (skill_element.to_lower() == current_mind_type)

		var button = Button.new()
		button.text = "[%s] %s\n(%s, MP: %d)" % [sigil_name, skill_name, skill_element_cap, mp_cost]
		button.custom_minimum_size = Vector2(380, 50)

		# Disable if can't afford OR type doesn't match
		if not can_afford:
			button.disabled = true
			button.text += "\n[Not enough MP]"
		elif not type_matches:
			button.disabled = true
			button.text += "\n[Wrong Type - Need %s]" % skill_element_cap
		else:
			button.pressed.connect(_on_skill_button_pressed.bind(i))
			# Only add enabled buttons to navigation list
			skill_menu_buttons.append(button)

		vbox.add_child(button)

	# Add cancel button
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(380, 40)
	cancel_btn.pressed.connect(_close_skill_menu)
	vbox.add_child(cancel_btn)

	# Add cancel to navigation array so it's selectable
	skill_menu_buttons.append(cancel_btn)

	# Add to scene
	add_child(skill_menu_panel)

	# Center it
	skill_menu_panel.position = Vector2(
		(get_viewport_rect().size.x - skill_menu_panel.custom_minimum_size.x) / 2,
		100
	)

	# Highlight first button if available (Change Mind Type will be first if it exists)
	if not skill_menu_buttons.is_empty():
		_highlight_skill_button(0)
		# Ensure first button grabs focus
		skill_menu_buttons[0].grab_focus()

	# Set cooldown to prevent immediate button press
	input_cooldown = input_cooldown_duration

func _on_skill_button_pressed(index: int) -> void:
	"""Handle skill button press"""
	if index >= 0 and index < current_skill_menu.size():
		var menu_entry = current_skill_menu[index]
		_close_skill_menu()
		_on_skill_selected(menu_entry)

func _on_change_type_button_pressed() -> void:
	"""Handle change type button press - show type selection menu"""
	# Close current skill menu
	_close_skill_menu()

	# Reset type menu state
	type_menu_buttons = []
	selected_type_index = 0

	# Create type selection panel
	type_menu_panel = PanelContainer.new()
	type_menu_panel.custom_minimum_size = Vector2(300, 0)

	# Style the panel with cyan neon Core vibe
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_INK_CHARCOAL
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = COLOR_SKY_CYAN  # Cyan neon border
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_size = 6
	style.shadow_color = Color(COLOR_SKY_CYAN.r, COLOR_SKY_CYAN.g, COLOR_SKY_CYAN.b, 0.4)  # Cyan glow
	type_menu_panel.add_theme_stylebox_override("panel", style)

	var vbox = VBoxContainer.new()
	type_menu_panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Change Mind Type"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", COLOR_MILK_WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var current_type = String(current_combatant.get("mind_type", "omega")).capitalize()
	var current_label = Label.new()
	current_label.text = "Current: %s" % current_type
	current_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	current_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
	vbox.add_child(current_label)

	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	# Add type buttons
	var available_types = ["Fire", "Water", "Earth", "Air", "Void", "Data", "Omega"]
	for type_name in available_types:
		if type_name.to_lower() != current_type.to_lower():
			var btn = Button.new()
			btn.text = type_name
			btn.custom_minimum_size = Vector2(280, 40)
			btn.pressed.connect(_on_type_selected.bind(type_name))
			type_menu_buttons.append(btn)  # Add to navigation array
			vbox.add_child(btn)

	# Cancel button
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(280, 40)
	cancel_btn.pressed.connect(_on_type_menu_cancel)
	type_menu_buttons.append(cancel_btn)  # Add to navigation array
	vbox.add_child(cancel_btn)

	# Add to scene and center
	add_child(type_menu_panel)
	type_menu_panel.position = Vector2(
		(get_viewport_rect().size.x - type_menu_panel.custom_minimum_size.x) / 2,
		100  # Moved up 50px from 150
	)

	# Highlight first button and grab focus
	if not type_menu_buttons.is_empty():
		_highlight_type_button(0)
		type_menu_buttons[0].grab_focus()

	# Set cooldown to prevent immediate button press
	input_cooldown = input_cooldown_duration

func _on_type_selected(new_type: String) -> void:
	"""Handle type selection"""
	# Close type menu
	_close_type_menu()

	# Switch type (don't end turn)
	_switch_mind_type(new_type, false)

	# Reopen skill menu with new type
	_on_skill_pressed()

func _on_type_menu_cancel() -> void:
	"""Cancel type selection and return to skill menu"""
	# Close type menu
	_close_type_menu()

	# Reopen skill menu
	_on_skill_pressed()

func _close_type_menu() -> void:
	"""Close the type selection menu"""
	if type_menu_panel:
		type_menu_panel.queue_free()
		type_menu_panel = null
	type_menu_buttons = []
	selected_type_index = 0

func _close_skill_menu() -> void:
	"""Close the skill menu"""
	_hide_instruction()

	if skill_menu_panel:
		skill_menu_panel.queue_free()
		skill_menu_panel = null
	current_skill_menu = []
	skill_menu_buttons = []
	selected_skill_index = 0

	# Enable action menu again
	_enable_action_menu()

func _navigate_skill_menu(direction: int) -> void:
	"""Navigate skill menu with controller (direction: -1 for up, 1 for down)"""
	if skill_menu_buttons.is_empty():
		return

	# Remove highlight from current button
	_unhighlight_skill_button(selected_skill_index)

	# Move selection
	selected_skill_index += direction

	# Wrap around
	if selected_skill_index < 0:
		selected_skill_index = skill_menu_buttons.size() - 1
	elif selected_skill_index >= skill_menu_buttons.size():
		selected_skill_index = 0

	# Highlight new button
	_highlight_skill_button(selected_skill_index)

func _confirm_skill_selection() -> void:
	"""Confirm skill selection with A button"""
	if selected_skill_index >= 0 and selected_skill_index < skill_menu_buttons.size():
		# Get the selected button and trigger its pressed signal
		var button = skill_menu_buttons[selected_skill_index]

		# For special buttons (Change Mind Type, Cancel), just press them directly
		if button.text.contains("CHANGE MIND TYPE") or button.text == "Cancel":
			button.emit_signal("pressed")
			return

		# Find the actual skill index in current_skill_menu
		for i in range(current_skill_menu.size()):
			var menu_entry = current_skill_menu[i]
			var skill_data = menu_entry.skill_data
			var skill_name = String(skill_data.get("name", "Unknown"))
			var sigil_name = menu_entry.sigil_name

			# Check if this matches the selected button text
			if button.text.contains(skill_name) and button.text.contains(sigil_name):
				_on_skill_button_pressed(i)
				return

func _highlight_skill_button(index: int) -> void:
	"""Highlight a skill button for controller navigation"""
	if index >= 0 and index < skill_menu_buttons.size():
		var button = skill_menu_buttons[index]
		button.modulate = Color(1.2, 1.2, 0.8, 1.0)  # Yellowish tint

func _unhighlight_skill_button(index: int) -> void:
	"""Remove highlight from a skill button"""
	if index >= 0 and index < skill_menu_buttons.size():
		var button = skill_menu_buttons[index]
		button.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal color

## ═══════════════════════════════════════════════════════════════
## TYPE MENU NAVIGATION
## ═══════════════════════════════════════════════════════════════

func _navigate_type_menu(direction: int) -> void:
	"""Navigate type menu with controller (direction: -1 for up, 1 for down)"""
	if type_menu_buttons.is_empty():
		return

	# Remove highlight from current button
	_unhighlight_type_button(selected_type_index)

	# Move selection
	selected_type_index += direction

	# Wrap around
	if selected_type_index < 0:
		selected_type_index = type_menu_buttons.size() - 1
	elif selected_type_index >= type_menu_buttons.size():
		selected_type_index = 0

	# Highlight new button
	_highlight_type_button(selected_type_index)

func _confirm_type_selection() -> void:
	"""Confirm type selection with A button"""
	if selected_type_index >= 0 and selected_type_index < type_menu_buttons.size():
		# Get the selected button and trigger its pressed signal
		var button = type_menu_buttons[selected_type_index]
		button.emit_signal("pressed")

func _highlight_type_button(index: int) -> void:
	"""Highlight a type button for controller navigation"""
	if index >= 0 and index < type_menu_buttons.size():
		var button = type_menu_buttons[index]
		button.modulate = Color(1.2, 1.2, 1.4, 1.0)  # Light blue highlight
		button.grab_focus()

func _unhighlight_type_button(index: int) -> void:
	"""Remove highlight from a type button"""
	if index >= 0 and index < type_menu_buttons.size():
		var button = type_menu_buttons[index]
		button.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal color

## ═══════════════════════════════════════════════════════════════
## STATUS PICKER NAVIGATION
## ═══════════════════════════════════════════════════════════════

func _navigate_status_picker(direction: int) -> void:
	"""Navigate status picker with controller (direction: -1 for up, 1 for down)"""
	if status_picker_buttons.is_empty():
		return

	# Remove highlight from current button
	_unhighlight_status_button(selected_status_index)

	# Move selection
	selected_status_index += direction

	# Wrap around
	if selected_status_index < 0:
		selected_status_index = status_picker_buttons.size() - 1
	elif selected_status_index >= status_picker_buttons.size():
		selected_status_index = 0

	# Highlight new button
	_highlight_status_button(selected_status_index)

func _confirm_status_selection() -> void:
	"""Confirm status selection with A button"""
	if selected_status_index >= 0 and selected_status_index < status_picker_data.size():
		# Show status details for selected character
		_show_status_details(status_picker_data[selected_status_index])

func _close_status_picker() -> void:
	"""Close the status picker"""
	if status_picker_panel:
		status_picker_panel.queue_free()
		status_picker_panel = null
	if status_picker_modal:
		status_picker_modal.queue_free()
		status_picker_modal = null
	status_picker_buttons = []
	status_picker_data = []
	selected_status_index = 0

func _highlight_status_button(index: int) -> void:
	"""Highlight a status picker button"""
	if index >= 0 and index < status_picker_buttons.size():
		var button = status_picker_buttons[index]
		button.modulate = Color(1.2, 1.2, 0.8, 1.0)  # Yellow tint
		button.grab_focus()

func _unhighlight_status_button(index: int) -> void:
	"""Remove highlight from a status picker button"""
	if index >= 0 and index < status_picker_buttons.size():
		var button = status_picker_buttons[index]
		button.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal color

func _close_status_details() -> void:
	"""Close the status details popup"""
	if status_details_popup:
		status_details_popup.queue_free()
		status_details_popup = null
	if status_details_modal:
		status_details_modal.queue_free()
		status_details_modal = null

	# Resume the status picker panel
	if status_picker_panel:
		status_picker_panel.process_mode = Node.PROCESS_MODE_INHERIT
		status_picker_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		# Re-highlight the selected button
		if selected_status_index >= 0 and selected_status_index < status_picker_buttons.size():
			_highlight_status_button(selected_status_index)

## ═══════════════════════════════════════════════════════════════
## ITEM MENU
## ═══════════════════════════════════════════════════════════════

func _show_item_menu(items: Array) -> void:
	"""Show item selection menu with categorized tabs"""
	# Disable and dim action menu
	_disable_action_menu()

	# Reset navigation
	item_menu_buttons = []
	selected_item_index = 0

	# Categorize items
	var restore_items = []
	var cure_items = []
	var tactical_items = []
	var combat_items = []

	for item in items:
		var category = item.get("battle_category", "Tactical")
		if category == "Restore":
			restore_items.append(item)
		elif category == "Cure":
			cure_items.append(item)
		elif category == "Tactical":
			tactical_items.append(item)
		elif category == "Combat":
			combat_items.append(item)

	# Create item menu panel
	item_menu_panel = PanelContainer.new()
	item_menu_panel.custom_minimum_size = Vector2(440, 0)  # Reduced width by 110px total

	# Style the panel with Core vibe
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_INK_CHARCOAL
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = COLOR_SKY_CYAN  # Cyan neon border
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_size = 6
	style.shadow_color = Color(COLOR_SKY_CYAN.r, COLOR_SKY_CYAN.g, COLOR_SKY_CYAN.b, 0.4)  # Cyan glow
	item_menu_panel.add_theme_stylebox_override("panel", style)

	# Create VBox for menu items
	var vbox = VBoxContainer.new()
	item_menu_panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Select an Item"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", COLOR_MILK_WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Add separator
	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	# Create tab container
	var tab_container = TabContainer.new()
	tab_container.custom_minimum_size = Vector2(420, 230)  # Reduced width by 110px total, height by 70px
	vbox.add_child(tab_container)

	# Store reference for controller navigation
	item_tab_container = tab_container

	# Add category tabs (Restore, Cure, Tactical, Combat)
	_add_category_tab(tab_container, "Restore", restore_items)
	_add_category_tab(tab_container, "Cure", cure_items)
	_add_category_tab(tab_container, "Tactical", tactical_items)
	_add_category_tab(tab_container, "Combat", combat_items)

	# Add separator
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	# Add description label
	item_description_label = Label.new()
	item_description_label.text = "Hover over an item to see its description"
	item_description_label.add_theme_font_size_override("font_size", 14)
	item_description_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
	item_description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_description_label.custom_minimum_size = Vector2(420, 60)  # Reduced width by 110px total
	item_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(item_description_label)

	# Add separator
	var sep3 = HSeparator.new()
	vbox.add_child(sep3)

	# Add cancel button
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(420, 40)  # Reduced width by 110px total
	cancel_btn.pressed.connect(_close_item_menu)
	vbox.add_child(cancel_btn)

	# Add to scene and center (moved up 130px total)
	add_child(item_menu_panel)
	item_menu_panel.position = Vector2(
		(get_viewport_rect().size.x - 440) / 2,  # Adjusted for new width (440px)
		(get_viewport_rect().size.y - 400) / 2 - 130  # Moved up 130px total (30px more)
	)

	# Rebuild button list for first tab and highlight first item
	_rebuild_item_button_list()

	# Set cooldown to prevent immediate button press
	input_cooldown = input_cooldown_duration

func _add_category_tab(tab_container: TabContainer, category_name: String, category_items: Array) -> void:
	"""Add a tab for a specific item category with two-column layout"""
	# Create scroll container for items
	var scroll = ScrollContainer.new()
	scroll.name = category_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	tab_container.add_child(scroll)

	# Create GridContainer for two-column layout
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 5)
	scroll.add_child(grid)

	# Show message if no items in this category
	if category_items.is_empty():
		var empty_label = Label.new()
		empty_label.text = "No items in this category"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 14)
		empty_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
		grid.add_child(empty_label)
		return

	# Add item buttons in two columns
	for item_data in category_items:
		var item_name = str(item_data.get("name", "Unknown"))
		var item_count = int(item_data.get("count", 0))
		var item_desc = str(item_data.get("description", ""))

		# Debug: Check what description we have in item_data
		var item_id = str(item_data.get("id", ""))
		if item_id.begins_with("BUFF_") or item_id.begins_with("BAT_") or item_id.begins_with("HP_"):
			print("[Battle] Creating button for %s: description in item_data = '%s'" % [item_id, item_desc])

		var button = Button.new()
		button.text = "%s (x%d)" % [item_name, item_count]
		button.custom_minimum_size = Vector2(250, 40)
		button.pressed.connect(_on_item_selected.bind(item_data))
		button.mouse_entered.connect(_on_item_hover.bind(item_name, item_desc))
		button.mouse_exited.connect(_on_item_unhover)

		# Store item data on button for controller navigation
		button.set_meta("item_data", item_data)
		button.set_meta("item_name", item_name)
		button.set_meta("item_desc", item_desc)

		grid.add_child(button)

func _close_item_menu() -> void:
	"""Close the item menu"""
	_hide_instruction()

	if item_menu_panel:
		item_menu_panel.queue_free()
		item_menu_panel = null

	item_description_label = null
	item_tab_container = null
	item_scroll_container = null
	item_menu_buttons = []
	selected_item_index = 0

	# Enable action menu again
	_enable_action_menu()

func _rebuild_item_button_list() -> void:
	"""Rebuild the button list for the current tab"""
	if not item_tab_container:
		return

	item_menu_buttons = []
	selected_item_index = 0

	# Get current tab
	var current_tab = item_tab_container.get_current_tab_control()
	if not current_tab:
		return

	# Find all buttons in the current tab
	var scroll = current_tab as ScrollContainer
	if not scroll:
		return

	# Store reference to scroll container for auto-scrolling
	item_scroll_container = scroll

	# Reset scroll to top when switching tabs
	scroll.scroll_vertical = 0

	var grid = scroll.get_child(0) as GridContainer
	if not grid:
		return

	# Collect all buttons
	for child in grid.get_children():
		if child is Button:
			item_menu_buttons.append(child)

	# Highlight first item if available
	if not item_menu_buttons.is_empty():
		_highlight_item_button(0)
		# Show description for first item
		var first_button = item_menu_buttons[0]
		if first_button.has_meta("item_name") and first_button.has_meta("item_desc"):
			_on_item_hover(first_button.get_meta("item_name"), first_button.get_meta("item_desc"))

func _navigate_item_menu(direction: int) -> void:
	"""Navigate item menu vertically (direction: -1 for up, 1 for down)"""
	if item_menu_buttons.is_empty():
		return

	# Remove highlight from current button
	_unhighlight_item_button(selected_item_index)

	# Move selection by 2 (one row in 2-column grid)
	selected_item_index += direction * 2

	# Wrap around
	if selected_item_index < 0:
		# Wrapped past top - go to last row
		selected_item_index = item_menu_buttons.size() - 1
	elif selected_item_index >= item_menu_buttons.size():
		# Wrapped past bottom - go to first row, same column
		# Check if we were on left or right column
		var was_right_column = (selected_item_index - direction * 2) % 2 == 1
		selected_item_index = 1 if was_right_column else 0

	# Highlight new button
	_highlight_item_button(selected_item_index)

	# Update description
	var button = item_menu_buttons[selected_item_index]
	if button.has_meta("item_name") and button.has_meta("item_desc"):
		_on_item_hover(button.get_meta("item_name"), button.get_meta("item_desc"))

func _navigate_item_menu_horizontal(direction: int) -> void:
	"""Navigate item menu horizontally (direction: -1 for left, 1 for right)"""
	if item_menu_buttons.is_empty():
		return

	# Remove highlight from current button
	_unhighlight_item_button(selected_item_index)

	# Move selection by 1 (left/right within same row)
	selected_item_index += direction

	# Wrap around
	if selected_item_index < 0:
		selected_item_index = item_menu_buttons.size() - 1
	elif selected_item_index >= item_menu_buttons.size():
		selected_item_index = 0

	# Highlight new button
	_highlight_item_button(selected_item_index)

	# Update description
	var button = item_menu_buttons[selected_item_index]
	if button.has_meta("item_name") and button.has_meta("item_desc"):
		_on_item_hover(button.get_meta("item_name"), button.get_meta("item_desc"))

func _switch_item_tab(direction: int) -> void:
	"""Switch item tabs with left/right (direction: -1 for left, 1 for right)"""
	if not item_tab_container:
		return

	var current_tab = item_tab_container.get_current_tab()
	var tab_count = item_tab_container.get_tab_count()

	var new_tab = current_tab + direction

	# Wrap around
	if new_tab < 0:
		new_tab = tab_count - 1
	elif new_tab >= tab_count:
		new_tab = 0

	item_tab_container.set_current_tab(new_tab)

	# Rebuild button list for new tab
	_rebuild_item_button_list()

func _confirm_item_selection() -> void:
	"""Confirm item selection with A button"""
	if selected_item_index >= 0 and selected_item_index < item_menu_buttons.size():
		var button = item_menu_buttons[selected_item_index]
		# Trigger the button press
		button.emit_signal("pressed")

func _highlight_item_button(index: int) -> void:
	"""Highlight an item button for controller navigation"""
	if index >= 0 and index < item_menu_buttons.size():
		var button = item_menu_buttons[index]
		button.modulate = Color(1.2, 1.2, 0.8, 1.0)  # Yellowish tint

		# Auto-scroll to ensure button is visible
		if item_scroll_container:
			# Scroll to make button visible
			_scroll_to_item_button(button)

func _unhighlight_item_button(index: int) -> void:
	"""Remove highlight from an item button"""
	if index >= 0 and index < item_menu_buttons.size():
		var button = item_menu_buttons[index]
		button.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal color

func _scroll_to_item_button(button: Button) -> void:
	"""Scroll the item menu to make the button visible"""
	if not item_scroll_container or not button:
		return

	# Find the button's index in our button list
	var button_index = item_menu_buttons.find(button)
	if button_index < 0:
		return

	# Calculate the button's Y position based on its index in a 2-column grid
	# Grid layout: 2 columns, buttons are 40px tall, 5px vertical separation
	var button_height = 40.0
	var v_separation = 5.0
	var row_height = button_height + v_separation

	# Calculate which row this button is in (2 columns = divide index by 2)
	var row_index = button_index / 2  # Integer division

	# Calculate the Y position of this row
	var button_y = row_index * row_height
	var button_bottom = button_y + button_height

	# Get scroll container dimensions
	var scroll_height = item_scroll_container.size.y
	var current_scroll = item_scroll_container.scroll_vertical

	# Add padding for better visibility
	var padding = 20.0

	# Check if button is above visible area (need to scroll up)
	if button_y < current_scroll + padding:
		item_scroll_container.scroll_vertical = max(0, button_y - padding)
	# Check if button is below visible area (need to scroll down)
	elif button_bottom > current_scroll + scroll_height - padding:
		item_scroll_container.scroll_vertical = button_bottom - scroll_height + padding

func _on_item_hover(item_name: String, item_desc: String) -> void:
	"""Show item description when hovering over button"""
	if item_description_label:
		if item_desc != "":
			item_description_label.text = "%s: %s" % [item_name, item_desc]
		else:
			item_description_label.text = "%s" % item_name

func _on_item_unhover() -> void:
	"""Reset item description when mouse leaves button"""
	if item_description_label:
		item_description_label.text = "Hover over an item to see its description"

func _execute_auto_escape_item(item_data: Dictionary) -> void:
	"""Execute auto-escape item (Smoke Grenade only)"""
	var item_id: String = item_data.get("id", "")
	var item_name: String = item_data.get("name", "Unknown")

	log_message("%s uses %s!" % [current_combatant.display_name, item_name])

	# Consume the item
	var inventory = get_node_or_null("/root/aInventorySystem")
	if inventory:
		inventory.remove_item(item_id, 1)
	else:
		push_error("Inventory system not available!")

	# Auto-escape effect
	log_message("  → Smoke fills the battlefield!")
	await get_tree().create_timer(1.0).timeout
	log_message("The party escapes successfully!")
	await get_tree().create_timer(1.0).timeout
	battle_mgr.current_state = battle_mgr.BattleState.ESCAPED
	battle_mgr.return_to_overworld()

func _on_item_selected(item_data: Dictionary) -> void:
	"""Handle item selection from menu"""
	_close_item_menu()

	# Store selected item
	selected_item = item_data

	var targeting = str(item_data.get("targeting", "Ally"))
	var item_def = item_data.get("item_def", {})
	var effect = str(item_def.get("battle_status_effect", ""))

	# Special handling for auto-escape items (Smoke Grenade only)
	if "Auto-escape" in effect:
		# Execute auto-escape immediately without target selection
		_execute_auto_escape_item(item_data)
		return

	# Special handling for AllEnemies targeting (Bombs)
	if targeting == "AllEnemies":
		# Bombs hit all enemies, no target selection needed
		log_message("%s uses %s!" % [current_combatant.display_name, str(item_data.get("name", "item"))])
		_execute_item_usage({})  # Pass empty dict since bombs hit all enemies
		return

	log_message("Using %s - select target..." % str(item_data.get("name", "item")))

	# Determine target candidates
	if targeting == "Ally":
		var allies = battle_mgr.get_ally_combatants()
		# Check if this is a revive item - if so, allow targeting KO'd allies
		var item_id = str(item_data.get("item_id", ""))
		var is_revive_item = "Revive" in effect or item_id.begins_with("REV_")

		if is_revive_item:
			# Revive items can only target KO'd (fainted) allies
			target_candidates = allies.filter(func(a): return a.is_ko)
		else:
			# Other items can only target alive allies
			target_candidates = allies.filter(func(a): return not a.is_ko)
	elif targeting == "Any":
		# "Any" targeting allows selecting from all combatants (allies and enemies)
		var all_combatants = []
		all_combatants.append_array(battle_mgr.get_ally_combatants())
		all_combatants.append_array(battle_mgr.get_enemy_combatants())
		# Allow targeting any non-KO'd character
		target_candidates = all_combatants.filter(func(c): return not c.is_ko)
	else:  # Enemy (single target)
		var enemies = battle_mgr.get_enemy_combatants()
		target_candidates = enemies.filter(func(e): return not e.is_ko)

	if target_candidates.is_empty():
		log_message("No valid targets!")
		return

	# Enable target selection mode
	awaiting_target_selection = true
	awaiting_item_target = true
	selected_target_index = 0  # Start with first target
	_highlight_target_candidates()

	# Show currently selected target
	if not target_candidates.is_empty():
		log_message("→ %s" % target_candidates[0].display_name)

## ═══════════════════════════════════════════════════════════════
## CAPTURE/BIND MENU
## ═══════════════════════════════════════════════════════════════

func _show_capture_menu(bind_items: Array) -> void:
	"""Show bind item selection menu for capture"""
	# Disable and dim action menu
	_disable_action_menu()

	# Reset navigation
	capture_menu_buttons = []
	selected_capture_index = 0

	# Create capture menu panel (wider for 2 columns)
	capture_menu_panel = PanelContainer.new()
	capture_menu_panel.custom_minimum_size = Vector2(800, 0)

	# Style the panel with Core vibe
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_INK_CHARCOAL
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = COLOR_SKY_CYAN  # Cyan neon border
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_size = 6
	style.shadow_color = Color(COLOR_SKY_CYAN.r, COLOR_SKY_CYAN.g, COLOR_SKY_CYAN.b, 0.4)  # Cyan glow
	capture_menu_panel.add_theme_stylebox_override("panel", style)

	# Create VBox for menu items
	var vbox = VBoxContainer.new()
	capture_menu_panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Select a Bind Device"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", COLOR_MILK_WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Add separator
	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	# Create scroll container for bind items (2 columns, show max 3 rows at a time)
	var scroll = ScrollContainer.new()
	var rows_to_show = min(ceili(bind_items.size() / 2.0), 3)  # Show up to 3 rows (6 items)
	scroll.custom_minimum_size = Vector2(780, rows_to_show * 55)  # 55px per row (50px button + 5px spacing)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(scroll)

	# Create GridContainer for scrollable bind item buttons (2 columns)
	var items_grid = GridContainer.new()
	items_grid.columns = 2
	items_grid.add_theme_constant_override("h_separation", 10)
	items_grid.add_theme_constant_override("v_separation", 5)
	scroll.add_child(items_grid)

	# Add bind item buttons (2 columns)
	for i in range(bind_items.size()):
		var bind_data = bind_items[i]
		var bind_name = str(bind_data.get("name", "Unknown"))
		var bind_desc = str(bind_data.get("description", ""))
		var bind_count = int(bind_data.get("count", 0))
		var capture_mod = int(bind_data.get("capture_mod", 0))

		var button = Button.new()
		button.text = "%s (x%d) [+%d%%]\n%s" % [bind_name, bind_count, capture_mod, bind_desc]
		button.custom_minimum_size = Vector2(375, 50)  # Width for 2 columns (780 - 10 spacing) / 2
		button.pressed.connect(_on_bind_selected.bind(bind_data))
		items_grid.add_child(button)

		# Add to navigation list
		capture_menu_buttons.append(button)

	# Add cancel button
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(780, 40)
	cancel_btn.pressed.connect(_close_capture_menu)
	vbox.add_child(cancel_btn)

	# Add to scene and center
	add_child(capture_menu_panel)
	capture_menu_panel.position = Vector2(
		(get_viewport_rect().size.x - 800) / 2,
		(get_viewport_rect().size.y - vbox.size.y) / 2
	)

	# Highlight first item if available
	if not capture_menu_buttons.is_empty():
		_highlight_capture_button(0)

	# Set cooldown to prevent immediate button press
	input_cooldown = input_cooldown_duration

func _close_capture_menu() -> void:
	"""Close the capture menu"""
	_hide_instruction()

	if capture_menu_panel:
		capture_menu_panel.queue_free()
		capture_menu_panel = null
	capture_menu_buttons = []
	selected_capture_index = 0

	# Enable action menu again
	_enable_action_menu()

func _navigate_capture_menu_vertical(direction: int) -> void:
	"""Navigate capture menu vertically (direction: -2 for up, 2 for down in 2-column grid)"""
	if capture_menu_buttons.is_empty():
		return

	# Remove highlight from current button
	_unhighlight_capture_button(selected_capture_index)

	# Move selection vertically
	var new_index = selected_capture_index + direction

	# Wrap around vertically
	if new_index < 0:
		# If going up from top row, wrap to bottom
		# Find last item in same column
		var column = selected_capture_index % 2
		var last_row = (capture_menu_buttons.size() - 1) / 2
		new_index = last_row * 2 + column
		# Make sure it doesn't exceed array size
		if new_index >= capture_menu_buttons.size():
			new_index = capture_menu_buttons.size() - 1
	elif new_index >= capture_menu_buttons.size():
		# If going down from bottom row, wrap to top
		var column = selected_capture_index % 2
		new_index = column

	selected_capture_index = new_index

	# Highlight new button
	_highlight_capture_button(selected_capture_index)

func _navigate_capture_menu_horizontal(direction: int) -> void:
	"""Navigate capture menu horizontally (direction: -1 for left, 1 for right in 2-column grid)"""
	if capture_menu_buttons.is_empty():
		return

	# Remove highlight from current button
	_unhighlight_capture_button(selected_capture_index)

	# Move selection horizontally
	var new_index = selected_capture_index + direction

	# Wrap around horizontally
	if new_index < 0:
		new_index = capture_menu_buttons.size() - 1
	elif new_index >= capture_menu_buttons.size():
		new_index = 0

	selected_capture_index = new_index

	# Highlight new button
	_highlight_capture_button(selected_capture_index)

func _confirm_capture_selection() -> void:
	"""Confirm capture item selection with A button"""
	if selected_capture_index >= 0 and selected_capture_index < capture_menu_buttons.size():
		var button = capture_menu_buttons[selected_capture_index]
		# Trigger the button press
		button.emit_signal("pressed")

func _highlight_capture_button(index: int) -> void:
	"""Highlight a capture button for controller navigation"""
	if index >= 0 and index < capture_menu_buttons.size():
		var button = capture_menu_buttons[index]
		button.modulate = Color(1.2, 1.2, 0.8, 1.0)  # Yellowish tint

func _unhighlight_capture_button(index: int) -> void:
	"""Remove highlight from a capture button"""
	if index >= 0 and index < capture_menu_buttons.size():
		var button = capture_menu_buttons[index]
		button.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal color

func _on_bind_selected(bind_data: Dictionary) -> void:
	"""Handle bind item selection from capture menu"""
	_close_capture_menu()

	log_message("Using %s (x%d) - select target..." % [bind_data.name, bind_data.count])

	# Get alive enemies
	var enemies = battle_mgr.get_enemy_combatants()
	target_candidates = enemies.filter(func(e): return not e.is_ko and not e.get("is_captured", false))

	if target_candidates.is_empty():
		log_message("No valid targets to capture!")
		return

	# Store selected bind for use after target selection
	set_meta("pending_capture_bind", bind_data)

	# Show instruction to select enemy
	_show_instruction("Select an enemy.")

	# Enable capture target selection mode
	awaiting_target_selection = true
	awaiting_capture_target = true
	selected_target_index = 0  # Start with first target
	_highlight_target_candidates()

	# Show currently selected target
	if not target_candidates.is_empty():
		log_message("→ %s" % target_candidates[0].display_name)

## ═══════════════════════════════════════════════════════════════
## BURST MENU & EXECUTION
## ═══════════════════════════════════════════════════════════════

func _show_burst_menu(burst_abilities: Array) -> void:
	"""Show burst ability selection menu"""
	# Disable and dim action menu
	_disable_action_menu()

	# Reset navigation
	burst_menu_buttons = []
	selected_burst_index = 0

	# Debug: print burst abilities
	print("[Battle] Showing burst menu with %d abilities" % burst_abilities.size())
	for i in range(burst_abilities.size()):
		print("[Battle] Burst %d: %s" % [i, burst_abilities[i]])

	# Create burst menu panel
	burst_menu_panel = PanelContainer.new()
	burst_menu_panel.custom_minimum_size = Vector2(450, 0)

	# Style the panel with Core vibe
	var style = StyleBoxFlat.new()
	style.bg_color = COLOR_INK_CHARCOAL  # Dark background
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.border_color = COLOR_SKY_CYAN  # Cyan neon border
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.shadow_size = 6
	style.shadow_color = Color(COLOR_SKY_CYAN.r, COLOR_SKY_CYAN.g, COLOR_SKY_CYAN.b, 0.4)  # Cyan glow
	burst_menu_panel.add_theme_stylebox_override("panel", style)

	# Create VBox for menu items
	var vbox = VBoxContainer.new()
	burst_menu_panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "Select Burst Ability"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", COLOR_BUBBLE_MAGENTA)  # Pink magenta title
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Show current burst gauge
	var gauge_label = Label.new()
	gauge_label.text = "Burst Gauge: %d / %d" % [battle_mgr.burst_gauge, battle_mgr.BURST_GAUGE_MAX]
	gauge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gauge_label.add_theme_font_size_override("font_size", 14)
	gauge_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)  # White text
	vbox.add_child(gauge_label)

	# Add separator
	var sep1 = HSeparator.new()
	vbox.add_child(sep1)

	# Add burst ability buttons
	for i in range(burst_abilities.size()):
		var burst_data = burst_abilities[i]

		# Validate burst_data
		if typeof(burst_data) != TYPE_DICTIONARY:
			print("[Battle] ERROR: Burst data %d is not a dictionary: %s" % [i, burst_data])
			continue

		var burst_name_raw = burst_data.get("name", "Unknown")
		var burst_name = String(burst_name_raw) if burst_name_raw != null else "Unknown"

		var burst_cost_raw = burst_data.get("burst_cost", 50)
		var burst_cost = int(burst_cost_raw) if burst_cost_raw != null else 50

		var description_raw = burst_data.get("description", "")
		var description = ""
		if description_raw != null:
			if typeof(description_raw) == TYPE_FLOAT or typeof(description_raw) == TYPE_INT:
				description = str(description_raw)  # Use str() for numbers
			else:
				description = String(description_raw)
		print("[Battle] Description for burst: '%s' (type: %d)" % [description, typeof(description_raw)])

		var participants_raw = burst_data.get("participants", "")
		var participants_str = String(participants_raw) if participants_raw != null else ""
		var participants = participants_str.split(";", false) if participants_str != "" else []

		# Build participants text safely with display names
		var participants_text = "Solo"
		if participants.size() > 0:
			var participant_names: PackedStringArray = PackedStringArray()
			for p in participants:
				var participant_id = String(p).strip_edges()
				var display_name = _get_member_display_name(participant_id)
				participant_names.append(display_name)
			participants_text = ", ".join(participant_names)

		var can_afford = battle_mgr.burst_gauge >= burst_cost

		# Build button text safely
		var button_text = ""
		button_text += str(burst_name) + " [Cost: " + str(burst_cost) + "]\n"
		button_text += str(description) + "\n"
		button_text += "With: " + str(participants_text)

		print("[Battle] Creating button with text: %s" % button_text)

		var button = Button.new()
		button.text = button_text
		button.custom_minimum_size = Vector2(430, 70)

		# Disable if can't afford
		if not can_afford:
			button.disabled = true
			button.text += "\n[Not enough Burst Gauge]"
		else:
			button.pressed.connect(_on_burst_selected.bind(burst_data))
			# Only add enabled buttons to navigation list
			burst_menu_buttons.append(button)

		vbox.add_child(button)

	# Add cancel button
	var sep2 = HSeparator.new()
	vbox.add_child(sep2)

	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(430, 40)
	cancel_btn.pressed.connect(_close_burst_menu)
	vbox.add_child(cancel_btn)

	# Add to scene and center
	add_child(burst_menu_panel)
	burst_menu_panel.position = Vector2(
		(get_viewport_rect().size.x - 450) / 2,
		100
	)

	# Highlight first burst if available
	if not burst_menu_buttons.is_empty():
		_highlight_burst_button(0)

	# Set cooldown to prevent immediate button press
	input_cooldown = input_cooldown_duration

func _close_burst_menu() -> void:
	"""Close the burst menu"""
	_hide_instruction()

	if burst_menu_panel:
		burst_menu_panel.queue_free()
		burst_menu_panel = null
	burst_menu_buttons = []
	selected_burst_index = 0

	# Enable action menu again
	_enable_action_menu()

func _navigate_burst_menu(direction: int) -> void:
	"""Navigate burst menu with controller (direction: -1 for up, 1 for down)"""
	if burst_menu_buttons.is_empty():
		return

	# Remove highlight from current button
	_unhighlight_burst_button(selected_burst_index)

	# Move selection
	selected_burst_index += direction

	# Wrap around
	if selected_burst_index < 0:
		selected_burst_index = burst_menu_buttons.size() - 1
	elif selected_burst_index >= burst_menu_buttons.size():
		selected_burst_index = 0

	# Highlight new button
	_highlight_burst_button(selected_burst_index)

func _confirm_burst_selection() -> void:
	"""Confirm burst ability selection with A button"""
	if selected_burst_index >= 0 and selected_burst_index < burst_menu_buttons.size():
		var button = burst_menu_buttons[selected_burst_index]
		# Trigger the button press
		button.emit_signal("pressed")

func _highlight_burst_button(index: int) -> void:
	"""Highlight a burst button for controller navigation"""
	if index >= 0 and index < burst_menu_buttons.size():
		var button = burst_menu_buttons[index]
		button.modulate = Color(1.2, 1.2, 0.8, 1.0)  # Yellowish tint

func _unhighlight_burst_button(index: int) -> void:
	"""Remove highlight from a burst button"""
	if index >= 0 and index < burst_menu_buttons.size():
		var button = burst_menu_buttons[index]
		button.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Normal color

func _on_burst_selected(burst_data: Dictionary) -> void:
	"""Handle burst ability selection"""
	_close_burst_menu()

	selected_burst = burst_data
	var burst_name = String(burst_data.get("name", "Unknown"))
	var target_type = String(burst_data.get("target", "Enemies")).to_lower()

	log_message("Selected: %s" % burst_name)

	# Determine targeting
	if "enemies" in target_type or "all enemies" in target_type:
		# AoE burst - hit all enemies
		_execute_burst_aoe()
	elif "enemy" in target_type:
		# Single target - need to select
		var enemies = battle_mgr.get_enemy_combatants()
		target_candidates = enemies.filter(func(e): return not e.is_ko)

		if target_candidates.is_empty():
			log_message("No valid targets!")
			selected_burst = {}
			return

		log_message("Select a target...")
		awaiting_target_selection = true
		selected_target_index = 0  # Start with first target
		_highlight_target_candidates()

		# Show currently selected target
		if not target_candidates.is_empty():
			log_message("→ %s" % target_candidates[0].display_name)
	else:
		# Self/Ally targeting not implemented yet
		log_message("This burst targeting not yet implemented")
		selected_burst = {}

func _execute_burst_aoe() -> void:
	"""Execute an AoE burst ability on all enemies"""
	var burst_name = String(selected_burst.get("name", "Unknown"))
	var burst_cost = int(selected_burst.get("burst_cost", 50))
	var power = int(selected_burst.get("power", 120))
	var element = String(selected_burst.get("element", "none")).to_lower()

	# Check and spend burst gauge
	if not battle_mgr.burst_gauge >= burst_cost:
		log_message("Not enough Burst Gauge!")
		selected_burst = {}
		return

	battle_mgr.burst_gauge -= burst_cost
	_update_burst_gauge()

	var hero_name = _get_hero_display_name()
	log_message("%s unleashes %s!" % [hero_name, burst_name])
	log_message("  (Spent %d Burst Gauge)" % burst_cost)

	# Hit all enemies
	var enemies = battle_mgr.get_enemy_combatants()
	var alive_enemies = enemies.filter(func(e): return not e.is_ko)

	for target in alive_enemies:
		await get_tree().create_timer(0.3).timeout
		await _execute_burst_on_target(target)

	# Check if battle is over
	var battle_ended = await battle_mgr._check_battle_end()
	if not battle_ended:
		# End turn after burst
		battle_mgr.end_turn()

func _execute_burst_on_target(target: Dictionary) -> void:
	"""Execute burst ability on a single target"""
	var power = int(selected_burst.get("power", 120))
	var acc = int(selected_burst.get("acc", 95))
	var element = String(selected_burst.get("element", "none")).to_lower()
	var crit_bonus = int(selected_burst.get("crit_bonus_pct", 20))
	var scaling_brw = float(selected_burst.get("scaling_brw", 0.5))
	var scaling_mnd = float(selected_burst.get("scaling_mnd", 1.0))
	var scaling_fcs = float(selected_burst.get("scaling_fcs", 0.5))

	# Check if hit (bursts have high accuracy)
	var hit_check = combat_resolver.check_sigil_hit(current_combatant, target, {"skill_acc": acc})

	if not hit_check.hit:
		_show_miss_feedback()  # Show big MISS text
		log_message("  → Missed %s! (%d%% chance)" % [target.display_name, int(hit_check.hit_chance)])
		return

	# ═══════ BURST MINIGAME ═══════
	var affinity = current_combatant.stats.get("affinity", 1)
	var status_effects = []
	var ailment = str(current_combatant.get("ailment", ""))
	if ailment != "":
		status_effects.append(ailment)

	log_message("  → Syncing burst energy...")
	var minigame_result = await minigame_mgr.launch_burst_minigame(affinity, status_effects)

	var damage_modifier = minigame_result.get("damage_modifier", 1.0)
	var minigame_crit = minigame_result.get("is_crit", false)

	# Roll for crit (or use minigame crit)
	var crit_check = combat_resolver.check_critical_hit(current_combatant, {"skill_crit_bonus": crit_bonus, "defender": target})
	var is_crit = crit_check.crit or minigame_crit

	# Calculate type effectiveness
	var type_bonus = 0.0
	if element != "none" and element != "":
		type_bonus = combat_resolver.get_mind_type_bonus(
			{"mind_type": element},
			target,
			element
		)

	# Calculate burst damage (higher than regular skills)
	var damage_result = combat_resolver.calculate_sigil_damage(
		current_combatant,
		target,
		{
			"potency": 150,  # Bursts are more powerful
			"is_crit": is_crit,
			"type_bonus": type_bonus,
			"base_sig": power,
			"mnd_scale": scaling_mnd,
			"brw_scale": scaling_brw,
			"fcs_scale": scaling_fcs
		}
	)

	var damage = damage_result.damage

	# Apply minigame damage modifier
	damage = int(damage * damage_modifier)

	# Apply damage
	target.hp -= damage

	# Shake the target's panel for visual feedback
	_shake_combatant_panel(target.id)

	# Wake up if asleep
	_wake_if_asleep(target)

	if target.hp <= 0:
		target.hp = 0
		_set_fainted(target)

		# Record kill
		if not target.get("is_ally", false):
			battle_mgr.record_enemy_defeat(target, false)

	# Log the hit
	var hit_msg = "  → BURST HIT %s for %d damage!" % [target.display_name, damage]
	if is_crit:
		hit_msg += " (CRITICAL!)"
	if type_bonus > 0.0:
		hit_msg += " (Super Effective!)"
	elif type_bonus < 0.0:
		hit_msg += " (Not Very Effective...)"
	log_message(hit_msg)

	# Update displays
	_update_combatant_displays()
	if target.is_ko:
		if turn_order_display:
			await turn_order_display.animate_ko_fall(target.id)
		battle_mgr.refresh_turn_order()
	elif turn_order_display:
		turn_order_display.update_combatant_hp(target.id)

func _on_skill_selected(skill_entry: Dictionary) -> void:
	"""Handle skill selection"""
	skill_to_use = skill_entry.skill_data.duplicate()
	skill_to_use["_sigil_inst_id"] = skill_entry.get("sigil_inst_id", "")  # Store sigil ID for tracking
	var skill_name = String(skill_to_use.get("name", "Unknown"))
	var target_type = String(skill_to_use.get("target", "Enemy")).to_lower()

	log_message("Selected: %s" % skill_name)

	# Determine targeting
	if target_type == "enemy" or target_type == "enemies":
		# Get alive enemies
		var enemies = battle_mgr.get_enemy_combatants()
		target_candidates = enemies.filter(func(e): return not e.is_ko)

		if target_candidates.is_empty():
			log_message("No valid targets!")
			skill_to_use = {}
			return

		# Check if AoE
		var is_aoe = int(skill_to_use.get("aoe", 0)) > 0

		if is_aoe:
			# AoE skill - hit all enemies
			_execute_skill_aoe()
		else:
			# Single target - need to select
			log_message("Select a target...")
			_show_instruction("Select an enemy.")
			awaiting_target_selection = true
			awaiting_skill_selection = true
			selected_target_index = 0  # Start with first target
			_highlight_target_candidates()

			# Show currently selected target
			if not target_candidates.is_empty():
				log_message("→ %s" % target_candidates[0].display_name)
	elif target_type == "ally" or target_type == "allies":
		# TODO: Implement ally targeting
		log_message("Ally targeting not yet implemented")
		skill_to_use = {}
	else:
		# Self-target or other
		log_message("Self-targeting not yet implemented")
		skill_to_use = {}

func _execute_skill_single(target: Dictionary) -> void:
	"""Execute a single-target skill"""
	# Check if frozen combatant can act
	if not _check_freeze_action_allowed():
		return

	# Get skill info
	var skill_id = String(skill_to_use.get("skill_id", ""))
	var skill_name = String(skill_to_use.get("name", "Unknown"))
	var mp_cost = int(skill_to_use.get("cost_mp", 0))
	var element = String(skill_to_use.get("element", "none")).to_lower()
	var power = int(skill_to_use.get("power", 30))
	var acc = int(skill_to_use.get("acc", 90))
	var crit_bonus = int(skill_to_use.get("crit_bonus_pct", 0))
	var mnd_scaling = int(skill_to_use.get("scaling_mnd", 1))

	# ═══════ HIT CHECK FIRST ═══════
	log_message("%s uses %s!" % [current_combatant.display_name, skill_name])
	var hit_check = combat_resolver.check_sigil_hit(current_combatant, target, {"skill_acc": acc})

	if not hit_check.hit:
		_show_miss_feedback()  # Show big MISS text
		log_message("  → Missed! (%d%% chance, rolled %d)" % [int(hit_check.hit_chance), hit_check.roll])
		# Still deduct MP even on miss
		current_combatant.mp -= mp_cost
		if current_combatant.mp < 0:
			current_combatant.mp = 0
		return

	# ═══════ SKILL MINIGAME ═══════
	# Get skill tier for minigame
	var skill_tier = 1
	if "_L" in skill_id:
		var parts = skill_id.split("_L")
		skill_tier = int(parts[1]) if parts.size() > 1 else 1

	# Launch skill minigame
	var focus_stat = current_combatant.stats.get("FCS", 1)
	var skill_sequence = _get_skill_button_sequence(skill_id)
	var mind_type = element  # Use the element as the mind type
	var status_effects = []
	var ailment = str(current_combatant.get("ailment", ""))
	if ailment != "":
		status_effects.append(ailment)

	log_message("  → %s prepares the skill..." % [current_combatant.display_name])
	_show_instruction("SKILL!")
	var minigame_result = await minigame_mgr.launch_skill_minigame(focus_stat, skill_sequence, skill_tier, mind_type, status_effects)
	_hide_instruction()

	# Apply minigame modifiers
	var damage_modifier = minigame_result.get("damage_modifier", 1.0)
	var mp_modifier = minigame_result.get("mp_modifier", 1.0)
	var tier_downgrade = minigame_result.get("tier_downgrade", 0)

	print("[Battle] Skill minigame - Damage: %.2fx, MP: %.2fx, Downgrade: %d" % [damage_modifier, mp_modifier, tier_downgrade])

	# Clear defending status when using skill
	current_combatant.is_defending = false

	# Deduct MP (with minigame modifier)
	var final_mp_cost = int(mp_cost * mp_modifier)
	current_combatant.mp -= final_mp_cost
	if current_combatant.mp < 0:
		current_combatant.mp = 0

	# Log MP savings if applicable
	if mp_modifier < 1.0:
		var saved_mp = mp_cost - final_mp_cost
		log_message("  → High Focus! Saved %d MP (%d → %d)" % [saved_mp, mp_cost, final_mp_cost])

	# Track sigil usage for bonus GXP
	var sigil_inst_id = skill_to_use.get("_sigil_inst_id", "")
	if sigil_inst_id != "":
		battle_mgr.sigils_used_in_battle[sigil_inst_id] = true

	# ═══════ CHECK FOR REFLECT (MIRROR) ═══════
	if target.has("buffs") and element != "none" and element != "":
		for i in range(target.buffs.size()):
			var buff = target.buffs[i]
			if buff.get("type", "") == "reflect":
				var reflect_element = buff.get("element", "")

				# Check if this mirror reflects this element
				var should_reflect = false
				if reflect_element == "any":
					should_reflect = true  # Mind Mirror reflects any element
				elif reflect_element == element:
					should_reflect = true  # Element-specific mirror

				if should_reflect:
					# REFLECT! The skill bounces back to the attacker
					log_message("  → %s's Mirror reflects the attack!" % target.display_name)

					# Remove the reflect buff (it's consumed)
					target.buffs.remove_at(i)

					# Redirect the skill to the attacker
					var original_attacker = current_combatant
					var new_target = current_combatant  # The attacker becomes the target

					# Calculate damage for reflected skill
					var reflect_type_bonus = 0.0
					if element != "none" and element != "":
						reflect_type_bonus = combat_resolver.get_mind_type_bonus(
							{"mind_type": element},
							new_target,
							element
						)

					# Calculate reflected damage (no crit on reflect)
					var reflect_damage_result = combat_resolver.calculate_sigil_damage(
						original_attacker,  # Still uses attacker's stats
						new_target,
						{
							"potency": 100,
							"is_crit": false,  # Reflected attacks don't crit
							"type_bonus": reflect_type_bonus,
							"base_sig": power,
							"mnd_scale": mnd_scaling
						}
					)

					var reflect_damage = reflect_damage_result.damage

					# Apply reflected damage
					new_target.hp -= reflect_damage
					if new_target.hp <= 0:
						new_target.hp = 0
						_set_fainted(new_target)
						log_message("  → %s was defeated by the reflection!" % new_target.display_name)
					else:
						log_message("  → %s takes %d reflected damage!" % [new_target.display_name, reflect_damage])

					# Update displays and end skill
					_update_combatant_displays()
					return  # Skill ends here, original target takes no damage

	# Roll for crit
	var crit_check = combat_resolver.check_critical_hit(current_combatant, {"skill_crit_bonus": crit_bonus, "defender": target})
	var is_crit = crit_check.crit

	# Calculate type effectiveness (use skill's element vs defender's mind type)
	# Skills ONLY use elemental weakness, NOT weapon triangle
	var type_bonus = 0.0
	if element != "none" and element != "":
		type_bonus = combat_resolver.get_mind_type_bonus(
			{"mind_type": element},
			target,
			element
		)

		# Show type matchup explanation
		if type_bonus > 0.0:
			log_message("  → TYPE ADVANTAGE! %s vs %s" % [element.capitalize(), target.mind_type.capitalize()])
		elif type_bonus < 0.0:
			log_message("  → TYPE DISADVANTAGE! %s vs %s" % [element.capitalize(), target.mind_type.capitalize()])

	# Both crits and type advantages count as stumbles for skills
	var crit_weakness_hit = is_crit
	var type_advantage_hit = type_bonus > 0.0

	# Calculate skill damage
	var damage_result = combat_resolver.calculate_sigil_damage(
		current_combatant,
		target,
		{
			"potency": 100,
			"is_crit": is_crit,
			"type_bonus": type_bonus,
			"base_sig": power,
			"mnd_scale": mnd_scaling
		}
	)

	var damage = damage_result.damage
	var _is_stumble = damage_result.is_stumble  # Reserved for future stumble mechanics

	# Apply minigame damage modifier
	var base_damage = damage
	damage = int(damage * damage_modifier)

	# Log damage modification if applicable
	if damage_modifier != 1.0:
		if damage_modifier > 1.0:
			log_message("  → Button sequence bonus! Damage: %d → %d (%.0f%%)" % [base_damage, damage, damage_modifier * 100])
		else:
			log_message("  → Missed buttons! Damage: %d → %d (%.0f%%)" % [base_damage, damage, damage_modifier * 100])

	# Apply damage
	target.hp -= damage

	# Shake the target's panel for visual feedback
	_shake_combatant_panel(target.id)

	# Wake up if asleep
	_wake_if_asleep(target)

	if target.hp <= 0:
		target.hp = 0
		target.is_ko = true

		# Record kill for morality system (if enemy)
		if not target.get("is_ally", false):
			battle_mgr.record_enemy_defeat(target, false)  # false = kill

	# Record weakness hits AFTER damage (only if target still alive)
	# Skills count crits and type advantages as weakness hits
	if not target.is_ko and (crit_weakness_hit or type_advantage_hit):
		var became_fallen = await battle_mgr.record_weapon_weakness_hit(target)
		if crit_weakness_hit:
			log_message("  → CRITICAL STUMBLE!")
		elif type_advantage_hit:
			log_message("  → ELEMENTAL STUMBLE!")
		if became_fallen:
			log_message("  → %s is FALLEN! (will skip next turn)" % target.display_name)

	# Apply status effect if skill has one (only if target still alive)
	if not target.is_ko:
		var status_to_apply = str(skill_to_use.get("status_apply", "")).to_lower()
		var status_chance_pct = int(skill_to_use.get("status_chance", 0))

		if status_to_apply != "" and status_to_apply != "null" and status_chance_pct > 0:
			var roll = randi() % 100
			if roll < status_chance_pct:
				# List of independent ailments (only one can exist at a time)
				var independent_ailments = ["burn", "burned", "freeze", "frozen", "sleep", "asleep", "poison", "poisoned", "malaise", "berserk", "charm", "charmed", "confuse", "confused"]

				if status_to_apply in independent_ailments:
					# Check if target already has an ailment
					var current_ailment = str(target.get("ailment", ""))
					if current_ailment != "" and current_ailment != "null":
						log_message("  → Failed to inflict %s! (%s already has %s)" % [status_to_apply.capitalize(), target.display_name, current_ailment.capitalize()])
					else:
						# Apply the ailment
						target.ailment = status_to_apply
						target.ailment_turn_count = 0
						log_message("  → %s is now %s! (%d%% chance, rolled %d)" % [target.display_name, status_to_apply.capitalize(), status_chance_pct, roll])
						battle_mgr.refresh_turn_order()
				else:
					# It's a debuff (not an independent ailment)
					var duration = int(skill_to_use.get("duration", 3))
					# Map status names to debuff types
					var debuff_type = ""
					if "attack down" in status_to_apply or "atk down" in status_to_apply:
						debuff_type = "attack_down"
					elif "defense down" in status_to_apply or "def down" in status_to_apply:
						debuff_type = "defense_down"
					elif "skill down" in status_to_apply or "mind down" in status_to_apply:
						debuff_type = "skill_down"
					elif "speed down" in status_to_apply or "slow" in status_to_apply:
						debuff_type = "speed_down"

					if debuff_type != "":
						battle_mgr.apply_buff(target, debuff_type, -0.15, duration)
						log_message("  → %s's %s reduced! (%d%% chance, rolled %d)" % [target.display_name, status_to_apply.replace("_", " ").capitalize(), status_chance_pct, roll])
						battle_mgr.refresh_turn_order()

	# Log the hit
	var hit_msg = "  → Hit %s for %d damage! (%d%% chance)" % [target.display_name, damage, int(hit_check.hit_chance)]
	if is_crit:
		hit_msg += " (CRITICAL! %d%% chance)" % int(crit_check.crit_chance)
	if type_bonus > 0.0:
		hit_msg += " (Super Effective!)"
	elif type_bonus < 0.0:
		hit_msg += " (Not Very Effective...)"
	if target.get("is_defending", false):
		var damage_without_defense = int(round(damage / 0.7))
		var damage_reduced = damage_without_defense - damage
		hit_msg += " (Defensive: -%d)" % damage_reduced
	log_message(hit_msg)

	# Update displays
	_update_combatant_displays()
	if target.is_ko:
		# Animate falling and then re-sort turn order
		if turn_order_display:
			await turn_order_display.animate_ko_fall(target.id)
		battle_mgr.refresh_turn_order()
	elif turn_order_display:
		turn_order_display.update_combatant_hp(target.id)

func _execute_skill_aoe() -> void:
	"""Execute an AoE skill on all valid targets"""
	# Check if frozen combatant can act
	if not _check_freeze_action_allowed():
		return

	var skill_name = String(skill_to_use.get("name", "Unknown"))
	var mp_cost = int(skill_to_use.get("cost_mp", 0))

	# Clear defending status
	current_combatant.is_defending = false

	# Deduct MP
	current_combatant.mp -= mp_cost
	if current_combatant.mp < 0:
		current_combatant.mp = 0

	log_message("%s uses %s on all enemies!" % [current_combatant.display_name, skill_name])

	# Hit each target
	for target in target_candidates:
		if not target.is_ko:
			await get_tree().create_timer(0.3).timeout
			await _execute_skill_single(target)

	# Check if battle is over
	var battle_ended = await battle_mgr._check_battle_end()
	if not battle_ended:
		# End turn after AoE
		battle_mgr.end_turn()

## ═══════════════════════════════════════════════════════════════
## MIND TYPE SWITCHING (HERO ONLY)
## ═══════════════════════════════════════════════════════════════

func _show_mind_type_menu() -> void:
	"""Show mind type switching menu for hero"""
	var available_types = ["Fire", "Water", "Earth", "Air", "Void", "Data", "Omega"]
	var current_type = String(gs.get_meta("hero_active_type", "Omega"))

	log_message("--- Switch Mind Type ---")
	log_message("Current: %s" % current_type)

	for i in range(available_types.size()):
		var type_name = available_types[i]
		var marker = " [Current]" if type_name == current_type else ""
		log_message("%d. %s%s" % [i + 1, type_name, marker])

	# For now, auto-select first type that's different from current
	for type_name in available_types:
		if type_name != current_type:
			_switch_mind_type(type_name)
			return

func _switch_mind_type(new_type: String, end_turn: bool = true) -> void:
	"""Switch hero's mind type and reload skills"""
	var old_type = String(gs.get_meta("hero_active_type", "Omega"))

	# Update mind type in GameState
	gs.set_meta("hero_active_type", new_type)

	# Update combatant's mind_type
	current_combatant.mind_type = new_type.to_lower()

	# Mark that type was changed this round
	current_combatant.changed_type_this_round = true

	# Reload sigils and skills for new type
	if has_node("/root/aSigilSystem"):
		var sigil_sys = get_node("/root/aSigilSystem")
		var loadout = sigil_sys.get_loadout("hero")

		var new_skills = []
		for sigil_inst in loadout:
			if sigil_inst != "":
				var skill_id = sigil_sys.get_active_skill_id_for_instance(sigil_inst)
				if skill_id != "":
					new_skills.append(skill_id)

		current_combatant.skills = new_skills
		log_message("%s switched from %s to %s!" % [current_combatant.display_name, old_type, new_type])

	# End turn if requested (for Item button usage)
	if end_turn:
		battle_mgr.end_turn()

## ═══════════════════════════════════════════════════════════════
## CAPTURE COLLECTION
## ═══════════════════════════════════════════════════════════════

func _add_captured_enemy(enemy: Dictionary) -> void:
	"""Add a captured enemy to the player's collection"""
	if not gs:
		return

	# Get enemy actor_id (the base enemy type, not the battle instance id)
	var actor_id = String(enemy.get("actor_id", ""))
	if actor_id == "":
		print("[Battle] Warning: Captured enemy has no actor_id!")
		return

	# Get current captured enemies list from GameState
	var captured: Array = []
	if gs.has_meta("captured_enemies"):
		var meta = gs.get_meta("captured_enemies")
		if typeof(meta) == TYPE_ARRAY:
			captured = meta.duplicate()

	# Add this enemy to the list (allows duplicates for counting)
	captured.append({
		"actor_id": actor_id,
		"display_name": enemy.get("display_name", actor_id),
		"captured_at": Time.get_datetime_string_from_system(),
		"mind_type": enemy.get("mind_type", "none"),
		"env_tag": enemy.get("env_tag", "Regular")
	})

	# Save back to GameState
	gs.set_meta("captured_enemies", captured)

	print("[Battle] Captured enemy added to collection: %s (Total captures: %d)" % [actor_id, captured.size()])
