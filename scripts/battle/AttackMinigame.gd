extends BaseMinigame
class_name AttackMinigame

## AttackMinigame - Simple timing-based attack with closing circle
## Press A button when circle is in the right color zone for damage bonuses

## Configuration
var tempo: int = 1  # Number of attempts (based on TPO) - currently unused
var brawn: int = 1  # Brawn stat - currently unused

## Internal state
enum Phase { FADE_IN, ACTIVE, SHOWING_RESULT, COMPLETE }
var current_phase: Phase = Phase.FADE_IN

## Circle animation
var circle_progress: float = 0.0  # 0.0 = fully open, 1.0 = fully closed
var circle_speed: float = 0.5  # Speed of closing (0.5 = 2 seconds to close)
var circle_max_radius: float = 150.0  # Maximum circle radius
var circle_min_radius: float = 20.0  # Minimum circle radius (center)

## Result tracking
var final_damage_modifier: float = 1.0
var final_grade: String = "good"
var result_text: String = "Good"

## Visual elements
var button_sprite: Sprite2D
var circle_canvas: Control  # For drawing the circle
var result_label: Label
var fade_timer: float = 0.0
var fade_duration: float = 1.0

## Button colors based on circle progress
var current_button_color: Color = Color.WHITE

## Input locked during fade in/out
var input_locked: bool = true

func _setup_minigame() -> void:
	base_duration = 10.0  # Maximum time allowed
	current_duration = base_duration

	# Neon-kawaii colors
	const COLOR_MILK_WHITE = Color(0.96, 0.97, 0.98)

	# Clear the default content container (we'll draw custom UI)
	for child in content_container.get_children():
		child.queue_free()

	# Create canvas for drawing circle
	circle_canvas = Control.new()
	circle_canvas.custom_minimum_size = Vector2(400, 400)
	circle_canvas.draw.connect(_draw_circle)
	var canvas_center = CenterContainer.new()
	canvas_center.add_child(circle_canvas)
	content_container.add_child(canvas_center)

	# Result label (hidden initially)
	result_label = Label.new()
	result_label.text = ""
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 24)
	result_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
	result_label.modulate.a = 0.0  # Hidden initially
	content_container.add_child(result_label)

	print("[AttackMinigame] Setup complete - simple circle timing")

func _start_minigame() -> void:
	print("[AttackMinigame] Starting circle timing minigame")
	current_phase = Phase.FADE_IN
	circle_progress = 0.0
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
	"""Fade in the button and circle before starting"""
	fade_timer += delta
	var alpha = min(fade_timer / fade_duration, 1.0)
	overlay_panel.modulate.a = alpha

	# Update button color during fade in (starts white)
	current_button_color = Color.WHITE
	circle_canvas.queue_redraw()

	# After 1 second, start the active phase
	if fade_timer >= fade_duration:
		current_phase = Phase.ACTIVE
		input_locked = false
		circle_progress = 0.0
		print("[AttackMinigame] Circle starting to close - input unlocked!")

func _process_active(delta: float) -> void:
	"""Circle is closing - player can press A to stop it"""
	# Close the circle
	circle_progress += delta * circle_speed

	# Update button color based on circle progress
	_update_button_color()

	# Redraw the circle
	circle_canvas.queue_redraw()

	# Check for Accept button press (A button)
	if not input_locked and aInputManager.is_action_just_pressed(aInputManager.ACTION_ACCEPT):
		print("[AttackMinigame] A pressed at %.1f%%" % (circle_progress * 100.0))
		_stop_circle()
		return

	# Auto-stop at 100% if player doesn't press
	if circle_progress >= 1.0:
		circle_progress = 1.0
		print("[AttackMinigame] Circle reached 100% - auto-stopping at RED")
		_stop_circle()

func _update_button_color() -> void:
	"""Update button color based on circle progress percentage"""
	var percent = circle_progress * 100.0

	if percent < 10.0:
		# 0-10%: White
		current_button_color = Color.WHITE
	elif percent < 30.0:
		# 10-30%: Yellow
		current_button_color = Color(1.0, 1.0, 0.0)  # Yellow
	elif percent < 80.0:
		# 30-80%: Green
		current_button_color = Color(0.0, 1.0, 0.0)  # Green
	elif percent < 90.0:
		# 80-90%: Blue
		current_button_color = Color(0.3, 0.6, 1.0)  # Blue
	elif percent < 100.0:
		# 90-100%: Yellow
		current_button_color = Color(1.0, 1.0, 0.0)  # Yellow
	else:
		# 100%: Red
		current_button_color = Color(1.0, 0.0, 0.0)  # Red

func _draw_circle() -> void:
	"""Draw the closing red circle and A button in center"""
	var canvas_size = circle_canvas.size
	var center = canvas_size / 2.0

	# Calculate current circle radius based on progress
	# Progress 0.0 = max radius, Progress 1.0 = min radius
	var current_radius = lerp(circle_max_radius, circle_min_radius, circle_progress)

	# Draw red circle border (closing in)
	_draw_circle_outline(center, current_radius, Color(1.0, 0.0, 0.0), 4.0)

	# Draw A button in center (filled circle with "A" text)
	var button_radius = 30.0
	circle_canvas.draw_circle(center, button_radius, current_button_color)

	# Draw "A" text on button
	var font = ThemeDB.fallback_font
	var font_size = 32
	var text = "A"
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos = center - text_size / 2.0
	circle_canvas.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.BLACK)

func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	"""Helper to draw a circle outline"""
	var points = 64
	for i in range(points):
		var angle_from = (float(i) / points) * TAU
		var angle_to = (float(i + 1) / points) * TAU
		var point_from = center + Vector2(cos(angle_from), sin(angle_from)) * radius
		var point_to = center + Vector2(cos(angle_to), sin(angle_to)) * radius
		circle_canvas.draw_line(point_from, point_to, color, width)

func _stop_circle() -> void:
	"""Player pressed A or circle reached 100% - calculate result"""
	input_locked = true
	current_phase = Phase.SHOWING_RESULT

	var percent = circle_progress * 100.0

	# Determine damage modifier and result text based on final percentage
	if percent < 10.0:
		# White zone (0-10%) - too early, no bonus/penalty yet
		final_damage_modifier = 1.0
		final_grade = "good"
		result_text = "Good"
	elif percent < 30.0:
		# Yellow zone (10-30%) - OK
		final_damage_modifier = 0.9
		final_grade = "ok"
		result_text = "OK"
	elif percent < 80.0:
		# Green zone (30-80%) - Good (normal damage)
		final_damage_modifier = 1.0
		final_grade = "good"
		result_text = "Good"
	elif percent < 90.0:
		# Blue zone (80-90%) - Amazing!
		final_damage_modifier = 1.3
		final_grade = "amazing"
		result_text = "Amazing!"
	elif percent < 100.0:
		# Yellow zone (90-100%) - OK
		final_damage_modifier = 0.9
		final_grade = "ok"
		result_text = "OK"
	else:
		# Red zone (100%) - Bad
		final_damage_modifier = 0.7
		final_grade = "bad"
		result_text = "Bad"

	print("[AttackMinigame] Stopped at %.1f%% - %s (%.1fx damage)" % [percent, result_text, final_damage_modifier])

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

func _finish_minigame() -> void:
	print("[AttackMinigame] Finishing - Grade: %s, Modifier: %.2f" % [final_grade, final_damage_modifier])

	current_phase = Phase.COMPLETE

	var result = {
		"success": true,
		"grade": final_grade,
		"damage_modifier": final_damage_modifier,
		"is_crit": false,  # No crits in this simple version
		"mp_modifier": 1.0,
		"tier_downgrade": 0,
		"focus_level": 0
	}

	_complete_minigame(result)
