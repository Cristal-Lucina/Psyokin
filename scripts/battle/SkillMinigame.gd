extends BaseMinigame
class_name SkillMinigame

## SkillMinigame - Button sequence timing minigame for skills
## Press the correct button sequence within the time limit
## Correct sequence = 100% damage (Tier 1)
## Extended sequences unlock higher tiers: Tier 2 (110%), Tier 3 (130%)

## Configuration
var focus_stat: int = 1  # Focus stat (currently unused)
var skill_sequence: Array = []  # Button sequence ["A", "B", "X", "Y"]
var skill_tier: int = 1  # Skill tier (1-3)
var mind_type: String = "fire"  # Mind type for color

## Internal state
enum Phase { FADE_IN, ACTIVE, SHOWING_RESULT, COMPLETE }
var current_phase: Phase = Phase.FADE_IN

## Sequence tracking
var sequence_index: int = 0  # Current position in sequence
var time_limit: float = 2.0  # 2 seconds to complete sequence
var timer: float = 0.0
var failed: bool = false

## Result tracking
var final_damage_modifier: float = 1.0
var final_tier: int = 1
var result_text: String = "GOOD"

## Visual elements
var circle_canvas: Control  # For drawing the filling circle
var sequence_container: HBoxContainer  # Shows button sequence
var timer_bar: ProgressBar  # Horizontal timer bar
var result_label: Label
var fade_timer: float = 0.0
var fade_duration: float = 1.0

## Circle fill animation
var fill_progress: float = 0.0  # 0.0 = empty, 1.0 = full
var circle_radius: float = 37.5  # Same size as AttackMinigame button

## Input locked during fade in/out
var input_locked: bool = true

## Button mapping for display
const BUTTON_ICONS = {
	"A": "Accept",
	"B": "Back",
	"X": "Special_1",
	"Y": "Special_2"
}

func _ready() -> void:
	# Override parent to customize background
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_STOP

	_setup_transparent_visuals()
	_apply_status_effects()
	_setup_minigame()

	# Start the minigame
	await get_tree().process_frame
	_start_minigame()

func _setup_transparent_visuals() -> void:
	"""Create transparent background - only UI elements visible"""
	# NO dimmed background - completely transparent
	background_dim = ColorRect.new()
	background_dim.color = Color(0, 0, 0, 0.0)  # Fully transparent
	background_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	background_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background_dim)

	# Central panel - also transparent
	overlay_panel = PanelContainer.new()
	overlay_panel.custom_minimum_size = get_viewport_rect().size * 0.1875  # Same as attack minigame
	var viewport_size = get_viewport_rect().size
	overlay_panel.position = Vector2(viewport_size.x * 0.40625, viewport_size.y * 0.25 - 100)  # Same position
	overlay_panel.z_index = 101

	# Make panel transparent
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0.0)  # Fully transparent
	panel_style.border_width_left = 0
	panel_style.border_width_right = 0
	panel_style.border_width_top = 0
	panel_style.border_width_bottom = 0
	overlay_panel.add_theme_stylebox_override("panel", panel_style)

	add_child(overlay_panel)

	# Content container
	content_container = VBoxContainer.new()
	content_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_container.add_theme_constant_override("separation", 10)
	overlay_panel.add_child(content_container)

func _setup_minigame() -> void:
	base_duration = 10.0  # Maximum time allowed
	current_duration = base_duration

	# Neon-kawaii colors
	const COLOR_MILK_WHITE = Color(0.96, 0.97, 0.98)

	# Clear the default content container
	for child in content_container.get_children():
		child.queue_free()

	# Result label (placed at top)
	result_label = Label.new()
	result_label.text = ""
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 60)
	result_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
	result_label.add_theme_constant_override("outline_size", 8)
	result_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	result_label.modulate.a = 0.0  # Hidden initially

	var result_container = CenterContainer.new()
	result_container.add_child(result_label)
	content_container.add_child(result_container)

	# Create a centered container for the circle
	var center_container = CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_container.add_child(center_container)

	# Create canvas for drawing filling circle
	circle_canvas = Control.new()
	circle_canvas.custom_minimum_size = Vector2(188, 188)  # Same as attack minigame
	circle_canvas.draw.connect(_draw_filling_circle)
	center_container.add_child(circle_canvas)

	# Button sequence display (centered above timer bar)
	sequence_container = HBoxContainer.new()
	sequence_container.add_theme_constant_override("separation", 5)
	var sequence_center = CenterContainer.new()
	sequence_center.add_child(sequence_container)
	content_container.add_child(sequence_center)

	# Create button icons for sequence
	# Button mappings: A = Xbox A/PS Cross/Nintendo B, B = Xbox B/PS Circle/Nintendo A,
	#                  X = Xbox X/PS Square/Nintendo Y, Y = Xbox Y/PS Triangle/Nintendo X
	var icon_layout = get_node_or_null("/root/aControllerIconLayout")
	if icon_layout:
		for i in range(skill_sequence.size()):
			var button_name = skill_sequence[i]
			var icon_action = BUTTON_ICONS.get(button_name, "accept")
			var icon_texture = icon_layout.get_button_icon(icon_action)

			if icon_texture:
				var icon_rect = TextureRect.new()
				icon_rect.texture = icon_texture
				icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
				icon_rect.custom_minimum_size = Vector2(20, 20)  # Small and compact
				icon_rect.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Start grayed out
				sequence_container.add_child(icon_rect)

	# Timer bar (horizontal, below sequence)
	timer_bar = ProgressBar.new()
	timer_bar.max_value = 1.0
	timer_bar.value = 1.0
	timer_bar.show_percentage = false
	timer_bar.custom_minimum_size = Vector2(200, 10)

	# Style the timer bar
	var timer_style = StyleBoxFlat.new()
	timer_style.bg_color = Color(1.0, 1.0, 1.0, 0.8)  # White fill
	timer_bar.add_theme_stylebox_override("fill", timer_style)

	var timer_bg_style = StyleBoxFlat.new()
	timer_bg_style.bg_color = Color(0.2, 0.2, 0.2, 0.5)  # Dark background
	timer_bar.add_theme_stylebox_override("background", timer_bg_style)

	var timer_center = CenterContainer.new()
	timer_center.add_child(timer_bar)
	content_container.add_child(timer_center)

	print("[SkillMinigame] Setup complete - button sequence minigame")

func _start_minigame() -> void:
	print("[SkillMinigame] Starting button sequence minigame")
	print("[SkillMinigame] Sequence: %s" % str(skill_sequence))
	current_phase = Phase.FADE_IN
	sequence_index = 0
	fill_progress = 0.0
	timer = 0.0
	failed = false
	fade_timer = 0.0
	input_locked = true

	# Fade in the overlay
	overlay_panel.modulate.a = 0.0

func _process(delta: float) -> void:
	super._process(delta)

	match current_phase:
		Phase.FADE_IN:
			_process_fade_in(delta)
		Phase.ACTIVE:
			_process_active(delta)
		Phase.SHOWING_RESULT:
			_process_showing_result(delta)

func _process_fade_in(delta: float) -> void:
	"""Fade in before starting"""
	fade_timer += delta
	var alpha = min(fade_timer / fade_duration, 1.0)
	overlay_panel.modulate.a = alpha

	circle_canvas.queue_redraw()

	# After 1 second, start the active phase
	if fade_timer >= fade_duration:
		current_phase = Phase.ACTIVE
		input_locked = false
		timer = 0.0
		print("[SkillMinigame] Sequence input active - press buttons!")

func _process_active(delta: float) -> void:
	"""Player inputting button sequence"""
	# Update timer
	timer += delta
	var time_remaining = time_limit - timer
	timer_bar.value = time_remaining / time_limit

	# Redraw circle
	circle_canvas.queue_redraw()

	# Check for button inputs
	if not input_locked and not failed:
		_check_button_input()

	# Time's up!
	if timer >= time_limit:
		if sequence_index < skill_sequence.size():
			# Didn't finish in time - 50% damage
			failed = true
			_finish_sequence(false)
		# If already complete, this won't trigger

func _check_button_input() -> void:
	"""Check if correct button was pressed"""
	var expected_button = skill_sequence[sequence_index]
	var pressed = false
	var correct = false

	# Map expected button to action
	var action_to_check = ""
	match expected_button:
		"A":
			action_to_check = aInputManager.ACTION_ACCEPT
		"B":
			action_to_check = aInputManager.ACTION_BACK
		"X":
			action_to_check = aInputManager.ACTION_DEFEND
		"Y":
			action_to_check = aInputManager.ACTION_SKILL

	# Check if the correct button was pressed
	if action_to_check != "" and aInputManager.is_action_just_pressed(action_to_check):
		pressed = true
		correct = true
		print("[SkillMinigame] Correct button %s pressed! (%d/%d)" % [expected_button, sequence_index + 1, skill_sequence.size()])

		# Highlight the current button icon
		if sequence_index < sequence_container.get_child_count():
			var icon = sequence_container.get_child(sequence_index)
			if icon is TextureRect:
				icon.modulate = _get_mind_type_color()  # Light up with mind type color

		sequence_index += 1
		fill_progress = float(sequence_index) / float(skill_sequence.size())

		# Check if sequence complete
		if sequence_index >= skill_sequence.size():
			_finish_sequence(true)
			return
	else:
		# Check if any wrong button was pressed
		var wrong_pressed = false
		for action in [aInputManager.ACTION_ACCEPT, aInputManager.ACTION_BACK,
					   aInputManager.ACTION_DEFEND, aInputManager.ACTION_SKILL]:
			if action != action_to_check and aInputManager.is_action_just_pressed(action):
				wrong_pressed = true
				break

		if wrong_pressed:
			print("[SkillMinigame] Wrong button pressed! Restarting sequence...")
			_restart_sequence()

func _restart_sequence() -> void:
	"""Reset sequence from beginning"""
	sequence_index = 0
	fill_progress = 0.0

	# Gray out all button icons again
	for i in range(sequence_container.get_child_count()):
		var icon = sequence_container.get_child(i)
		if icon is TextureRect:
			icon.modulate = Color(0.5, 0.5, 0.5, 1.0)

func _finish_sequence(success: bool) -> void:
	"""Sequence complete or failed"""
	input_locked = true
	current_phase = Phase.SHOWING_RESULT

	if success:
		# Successfully completed within time limit
		final_damage_modifier = 1.0  # Tier 1: 100% damage
		final_tier = 1
		result_text = "GOOD"
		print("[SkillMinigame] Sequence completed successfully! 100% damage")
	else:
		# Failed to complete in time
		final_damage_modifier = 0.5  # 50% damage penalty
		final_tier = 0
		result_text = "MISS"
		print("[SkillMinigame] Time's up! 50% damage penalty")

	# Show result text
	result_label.text = result_text
	result_label.modulate.a = 1.0

	# Start fade out timer
	fade_timer = 0.0

func _process_showing_result(delta: float) -> void:
	"""Show result for a moment, then fade out"""
	fade_timer += delta

	# Show result for 1 second
	if fade_timer >= 1.0:
		# Start fade out
		var fade_out_time = fade_timer - 1.0
		var alpha = 1.0 - (fade_out_time / fade_duration)
		overlay_panel.modulate.a = max(alpha, 0.0)

		# Complete after fade out
		if fade_out_time >= fade_duration:
			_finish_minigame()

func _draw_filling_circle() -> void:
	"""Draw the circle that fills with mind type color"""
	var canvas_size = circle_canvas.size
	var center = canvas_size / 2.0

	# Draw outer circle border
	_draw_circle_outline(center, circle_radius, Color(0.5, 0.5, 0.5, 0.8), 2.0)

	# Fill circle based on progress
	if fill_progress > 0.0:
		var fill_color = _get_mind_type_color()
		fill_color.a = 0.6  # Semi-transparent
		_draw_filled_circle(center, circle_radius * fill_progress, fill_color)

func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	"""Helper to draw a circle outline"""
	var points = 64
	for i in range(points):
		var angle_from = (float(i) / points) * TAU
		var angle_to = (float(i + 1) / points) * TAU
		var point_from = center + Vector2(cos(angle_from), sin(angle_from)) * radius
		var point_to = center + Vector2(cos(angle_to), sin(angle_to)) * radius
		circle_canvas.draw_line(point_from, point_to, color, width)

func _draw_filled_circle(center: Vector2, radius: float, color: Color) -> void:
	"""Helper to draw a filled circle"""
	var points = 64
	var points_array = PackedVector2Array()
	points_array.append(center)

	for i in range(points + 1):
		var angle = (float(i) / points) * TAU
		var point = center + Vector2(cos(angle), sin(angle)) * radius
		points_array.append(point)

	circle_canvas.draw_colored_polygon(points_array, color)

func _get_mind_type_color() -> Color:
	"""Get color for mind type"""
	match mind_type.to_lower():
		"fire":
			return Color(1.0, 0.3, 0.1, 1.0)  # Bright orange-red
		"water":
			return Color(0.2, 0.5, 1.0, 1.0)  # Blue
		"earth":
			return Color(0.6, 0.4, 0.2, 1.0)  # Brown/tan
		"air":
			return Color(0.8, 1.0, 0.9, 1.0)  # Light cyan/white
		"data":
			return Color(0.3, 1.0, 0.3, 1.0)  # Bright green
		"void":
			return Color(0.5, 0.2, 0.6, 1.0)  # Purple
		"omega":
			return Color(1.0, 0.9, 0.2, 1.0)  # Golden yellow
		_:
			return Color(0.5, 0.5, 0.5, 1.0)  # Gray for unknown

func _finish_minigame() -> void:
	print("[SkillMinigame] Finishing - Tier: %d, Modifier: %.2f" % [final_tier, final_damage_modifier])

	current_phase = Phase.COMPLETE

	var result = {
		"success": true,
		"grade": result_text.to_lower(),
		"damage_modifier": final_damage_modifier,
		"is_crit": false,
		"mp_modifier": 1.0,
		"tier_downgrade": 0,
		"focus_level": final_tier
	}

	_complete_minigame(result)
