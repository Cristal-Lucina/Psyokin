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
var circle_speed: float = 2.0  # Speed of closing (2.0 = 0.5 seconds to close)
var circle_max_radius: float = 60.0  # Maximum circle radius (30% of 200)
var circle_min_radius: float = 30.0  # Minimum circle radius (30% of 100)

## Result tracking
var final_damage_modifier: float = 1.0
var final_grade: String = "good"
var result_text: String = "Good"

## Visual elements
var button_icon: TextureRect  # The A button icon
var circle_canvas: Control  # For drawing the circle
var result_label: Label
var fade_timer: float = 0.0
var fade_duration: float = 1.0

## Button icon modulation based on circle progress
var current_button_modulation: Color = Color.WHITE

## Input locked during fade in/out
var input_locked: bool = true

func _ready() -> void:
	# Override parent to customize background
	# Set up as overlay
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
	"""Create transparent background - only button and circle visible"""
	# NO dimmed background - completely transparent
	background_dim = ColorRect.new()
	background_dim.color = Color(0, 0, 0, 0.0)  # Fully transparent
	background_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	background_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background_dim)

	# Central panel - also transparent
	overlay_panel = PanelContainer.new()
	overlay_panel.custom_minimum_size = get_viewport_rect().size * 0.15  # 30% of original 0.5
	var viewport_size = get_viewport_rect().size
	overlay_panel.position = Vector2(viewport_size.x * 0.425, viewport_size.y * 0.25 - 200)  # Centered horizontally, moved up 200px
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

	# Get the controller icon layout
	var icon_layout = get_node_or_null("/root/aControllerIconLayout")
	if not icon_layout:
		print("[AttackMinigame] ERROR: aControllerIconLayout not found!")
		return

	# Create a centered container for the button and circle
	var center_container = CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_container.add_child(center_container)

	# Create canvas for drawing circle and button
	circle_canvas = Control.new()
	circle_canvas.custom_minimum_size = Vector2(150, 150)  # 30% of 500
	circle_canvas.draw.connect(_draw_circle_and_button)
	center_container.add_child(circle_canvas)

	# Load the Accept button icon (A button)
	var icon_texture = icon_layout.get_button_icon("accept")
	if icon_texture:
		# Store the texture for drawing
		button_icon = TextureRect.new()
		button_icon.texture = icon_texture
		button_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		button_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		button_icon.custom_minimum_size = Vector2(60, 60)  # 30% of 200
		# We'll draw this manually in _draw_circle_and_button
		print("[AttackMinigame] Loaded accept button icon")
	else:
		print("[AttackMinigame] ERROR: Could not load accept button icon")

	# Result label (placed above the minigame)
	result_label = Label.new()
	result_label.text = ""
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 14)  # 30% of 48
	result_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
	result_label.modulate.a = 0.0  # Hidden initially

	# Position result label at the top center
	var result_container = CenterContainer.new()
	result_container.add_child(result_label)
	content_container.add_child(result_container)
	content_container.move_child(result_container, 0)  # Move to top

	print("[AttackMinigame] Setup complete - simple circle timing with transparent background")

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

	# Update button modulation during fade in (starts white)
	current_button_modulation = Color.WHITE
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

	# Update button modulation based on circle progress
	_update_button_modulation()

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

func _update_button_modulation() -> void:
	"""Update button icon modulation based on circle progress percentage"""
	var percent = circle_progress * 100.0

	if percent < 10.0:
		# 0-10%: White
		current_button_modulation = Color.WHITE
	elif percent < 30.0:
		# 10-30%: Yellow
		current_button_modulation = Color(1.0, 1.0, 0.0)  # Yellow
	elif percent < 80.0:
		# 30-80%: Green
		current_button_modulation = Color(0.0, 1.0, 0.0)  # Green
	elif percent < 90.0:
		# 80-90%: Blue
		current_button_modulation = Color(0.3, 0.6, 1.0)  # Blue
	elif percent < 100.0:
		# 90-100%: Yellow
		current_button_modulation = Color(1.0, 1.0, 0.0)  # Yellow
	else:
		# 100%: Red
		current_button_modulation = Color(1.0, 0.0, 0.0)  # Red

func _draw_circle_and_button() -> void:
	"""Draw the closing red circle and button icon in center"""
	var canvas_size = circle_canvas.size
	var center = canvas_size / 2.0

	# Draw zone marker rings (static guides showing where each zone is)
	# These show the player where to aim for
	var radius_30 = lerp(circle_max_radius, circle_min_radius, 0.30)  # Start of green zone
	var radius_80 = lerp(circle_max_radius, circle_min_radius, 0.80)  # Start of blue zone (OPTIMAL)
	var radius_90 = lerp(circle_max_radius, circle_min_radius, 0.90)  # End of blue zone

	# Draw green zone ring (30% - normal damage starts here)
	_draw_circle_outline(center, radius_30, Color(0.0, 1.0, 0.0, 0.3), 1.0)

	# Draw blue zone rings (80-90% - BEST zone, +30% damage!)
	_draw_circle_outline(center, radius_80, Color(0.3, 0.6, 1.0, 0.6), 2.0)  # Outer blue ring
	_draw_circle_outline(center, radius_90, Color(0.3, 0.6, 1.0, 0.6), 2.0)  # Inner blue ring

	# Fill the blue zone area with a semi-transparent blue
	_draw_zone_fill(center, radius_80, radius_90, Color(0.3, 0.6, 1.0, 0.15))

	# Calculate current circle radius based on progress
	# Progress 0.0 = max radius, Progress 1.0 = min radius (stops at button edge)
	var current_radius = lerp(circle_max_radius, circle_min_radius, circle_progress)

	# Draw red circle border (closing in)
	_draw_circle_outline(center, current_radius, Color(1.0, 0.0, 0.0), 2.0)  # 30% of 6

	# Draw the button icon in the center (60x60)
	if button_icon and button_icon.texture:
		var icon_size = Vector2(60, 60)  # 30% of 200
		var icon_pos = center - icon_size / 2.0
		var icon_rect = Rect2(icon_pos, icon_size)

		# Draw with current modulation color
		circle_canvas.draw_texture_rect(button_icon.texture, icon_rect, false, current_button_modulation)

func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	"""Helper to draw a circle outline"""
	var points = 64
	for i in range(points):
		var angle_from = (float(i) / points) * TAU
		var angle_to = (float(i + 1) / points) * TAU
		var point_from = center + Vector2(cos(angle_from), sin(angle_from)) * radius
		var point_to = center + Vector2(cos(angle_to), sin(angle_to)) * radius
		circle_canvas.draw_line(point_from, point_to, color, width)

func _draw_zone_fill(center: Vector2, outer_radius: float, inner_radius: float, color: Color) -> void:
	"""Helper to fill the area between two circles (for zone highlighting)"""
	var points = 64
	for i in range(points):
		var angle_from = (float(i) / points) * TAU
		var angle_to = (float(i + 1) / points) * TAU

		# Create a quad between the two circles
		var outer_from = center + Vector2(cos(angle_from), sin(angle_from)) * outer_radius
		var outer_to = center + Vector2(cos(angle_to), sin(angle_to)) * outer_radius
		var inner_from = center + Vector2(cos(angle_from), sin(angle_from)) * inner_radius
		var inner_to = center + Vector2(cos(angle_to), sin(angle_to)) * inner_radius

		# Draw two triangles to fill the quad
		var points_array1 = PackedVector2Array([outer_from, outer_to, inner_from])
		var points_array2 = PackedVector2Array([outer_to, inner_to, inner_from])
		circle_canvas.draw_colored_polygon(points_array1, color)
		circle_canvas.draw_colored_polygon(points_array2, color)

func _stop_circle() -> void:
	"""Player pressed A or circle reached 100% - calculate result"""
	input_locked = true
	current_phase = Phase.SHOWING_RESULT

	var percent = circle_progress * 100.0

	# Determine damage modifier and result text based on final percentage
	if percent < 10.0:
		# White zone (0-10%) - too early
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
