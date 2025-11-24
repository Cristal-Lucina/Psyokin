extends BaseMinigame
class_name CaptureMinigame

## CaptureMinigame - Hold button and spin joystick to capture
## Random button (A, B, X, Y) + random direction (clockwise/counter-clockwise)
## Fill progress bar by holding button and spinning in correct direction
## Periodically changes button OR direction
## Multiple fill cycles based on difficulty

signal minigame_completed

## Configuration
var binds: Array = []  # ["basic", "standard", "advanced"]
var enemy_data: Dictionary = {}
var party_member_data: Dictionary = {}

## Internal state
enum Phase { FADE_IN, ACTIVE, SHOWING_RESULT, COMPLETE }
var current_phase: Phase = Phase.FADE_IN

## Difficulty (determines number of fill cycles)
var break_rating: int = 6
var fills_needed: int = 3  # How many times player must fill the bar
var fills_completed: int = 0

## Progress tracking
var fill_progress: float = 0.0  # 0.0 to 1.0 (one complete fill)
var fill_speed: float = 0.5  # How fast the bar fills per second (doubled from 0.25)
var decay_speed: float = 0.1  # How fast the bar drains when not inputting (reduced from 0.15)

## Button and direction requirements
const CAPTURE_BUTTONS = ["A", "B", "X", "Y"]
const BUTTON_ACTIONS = {
	"A": "accept",
	"B": "back",
	"X": "defend",
	"Y": "skill"
}
var current_button: String = "A"  # Random button
var current_button_action: String = ""  # Will be set to InputManager constant
var current_direction: int = 1  # 1 = clockwise, -1 = counter-clockwise

## Joystick rotation tracking
var last_input_angle: float = 0.0
var accumulated_rotation: float = 0.0  # Track total rotation
var rotation_threshold: float = 0.05  # Very low threshold (was 0.1)
var has_initial_angle: bool = false  # Track if we've set the initial angle

## Change tracking (periodic button/direction changes)
var change_progress: float = 0.0  # When this hits 1.0, trigger a change
var change_interval: float = 0.33  # Change happens at 33% and 66% of each fill

## Visual elements
var button_icon: TextureRect  # The current button icon
var direction_arrow: Control  # Arrow indicating spin direction
var circle_canvas: Control  # For drawing the progress circle
var progress_bar: ProgressBar  # Shows fill progress
var fills_label: Label  # Shows "Fill 1/3"
var button_prompt_label: Label  # Shows "HOLD A" or "HOLD B" etc
var result_label: Label
var fade_timer: float = 0.0
var fade_duration: float = 0.5

## Input locked during fade in/out
var input_locked: bool = true

## Result tracking
var capture_success: bool = false
var result_text: String = "FAILED"

# Core vibe color constants
const COLOR_MILK_WHITE = Color(0.96, 0.97, 0.98)
const COLOR_BUBBLE_MAGENTA = Color(1.0, 0.29, 0.85)

func _ready() -> void:
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
	"""Create transparent background - only button, arrow, and circle visible"""
	# Fully transparent background
	background_dim = ColorRect.new()
	background_dim.color = Color(0, 0, 0, 0.0)  # Fully transparent
	background_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	background_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background_dim)

	# Central panel - also transparent
	overlay_panel = PanelContainer.new()
	overlay_panel.custom_minimum_size = get_viewport_rect().size * 0.25
	var viewport_size = get_viewport_rect().size
	overlay_panel.position = Vector2(viewport_size.x * 0.375, viewport_size.y * 0.25 - 100)  # Centered, moved up 100px
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
	base_duration = 2.0  # 2 seconds per fill (will be multiplied by fills_needed)

	# Calculate difficulty from enemy data
	_calculate_difficulty()

	# Set total duration based on fills needed
	current_duration = base_duration * fills_needed

	# Clear the default content container
	for child in content_container.get_children():
		child.queue_free()

	# Get the controller icon layout
	var icon_layout = get_node_or_null("/root/aControllerIconLayout")
	if not icon_layout:
		print("[CaptureMinigame] ERROR: aControllerIconLayout not found!")
		return

	# Fills label at top
	fills_label = Label.new()
	fills_label.text = "Fill 1/%d" % fills_needed
	fills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fills_label.add_theme_font_size_override("font_size", 32)
	fills_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
	fills_label.add_theme_constant_override("outline_size", 4)
	fills_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	content_container.add_child(fills_label)

	# Button prompt label (shows "HOLD A" or "HOLD B" etc)
	button_prompt_label = Label.new()
	button_prompt_label.text = "HOLD A"  # Will be updated by _randomize_button()
	button_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button_prompt_label.add_theme_font_size_override("font_size", 40)
	button_prompt_label.add_theme_color_override("font_color", COLOR_BUBBLE_MAGENTA)
	button_prompt_label.add_theme_constant_override("outline_size", 6)
	button_prompt_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	content_container.add_child(button_prompt_label)

	# Create a centered container for the button, arrow, and circle
	var center_container = CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_container.add_child(center_container)

	# Create canvas for drawing circle, button, and arrow
	circle_canvas = Control.new()
	circle_canvas.custom_minimum_size = Vector2(250, 250)
	circle_canvas.draw.connect(_draw_capture_visual)
	center_container.add_child(circle_canvas)

	# Pick random starting button
	_randomize_button()

	# Pick random starting direction
	_randomize_direction()

	# Result label (placed above the minigame)
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
	content_container.move_child(result_container, 0)  # Move to top

	print("[CaptureMinigame] Setup complete - hold button and spin mechanic")

func _calculate_difficulty() -> void:
	"""Calculate difficulty from enemy data"""
	var enemy_hp_percent = float(enemy_data.get("hp", 1)) / float(enemy_data.get("hp_max", 1))
	var base_rating = enemy_data.get("level", 1)

	if enemy_hp_percent <= 0.1:
		break_rating = max(1, int(base_rating / 2))
	elif enemy_hp_percent >= 1.0:
		break_rating = base_rating * 2
	elif enemy_hp_percent > 0.5:
		break_rating = int(base_rating * 1.25)
	else:
		break_rating = int(base_rating * 0.75)

	# Check for charm bonus (easier capture)
	var enemy_ailment = str(enemy_data.get("ailment", "")).to_lower()
	if enemy_ailment == "charm" or enemy_ailment == "charmed":
		break_rating = max(1, int(break_rating / 2))
		print("[CaptureMinigame] Enemy is CHARMED - halving difficulty!")

	# Determine fills needed based on break rating
	# Easy: 1-3 = 2 fills, Medium: 4-6 = 3 fills, Hard: 7+ = 4 fills
	if break_rating <= 3:
		fills_needed = 2
	elif break_rating <= 6:
		fills_needed = 3
	else:
		fills_needed = 4

	print("[CaptureMinigame] Break rating: %d, fills needed: %d (HP: %.1f%%)" % [break_rating, fills_needed, enemy_hp_percent * 100])

func _randomize_button() -> void:
	"""Pick a random button"""
	current_button = CAPTURE_BUTTONS[randi() % CAPTURE_BUTTONS.size()]

	# Map to InputManager action constant (like DefenseMinigame does)
	match current_button:
		"A": current_button_action = aInputManager.ACTION_ACCEPT
		"B": current_button_action = aInputManager.ACTION_BACK
		"X": current_button_action = aInputManager.ACTION_DEFEND
		"Y": current_button_action = aInputManager.ACTION_SKILL

	# Update button prompt label
	if button_prompt_label:
		button_prompt_label.text = "HOLD %s" % current_button

	print("[CaptureMinigame] Button changed to: %s (action: %s)" % [current_button, current_button_action])

func _randomize_direction() -> void:
	"""Pick a random direction"""
	current_direction = 1 if randf() > 0.5 else -1
	var direction_text = "CLOCKWISE" if current_direction == 1 else "COUNTER-CLOCKWISE"
	print("[CaptureMinigame] Direction changed to: %s" % direction_text)

func _start_minigame() -> void:
	print("[CaptureMinigame] Starting capture minigame")
	current_phase = Phase.FADE_IN
	fill_progress = 0.0
	fills_completed = 0
	change_progress = 0.0
	fade_timer = 0.0
	input_locked = true
	has_initial_angle = false  # Reset rotation tracking

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
	"""Fade in the visuals before starting"""
	fade_timer += delta
	var alpha = min(fade_timer / fade_duration, 1.0)
	overlay_panel.modulate.a = alpha

	circle_canvas.queue_redraw()

	# After fade duration, start the active phase
	if fade_timer >= fade_duration:
		current_phase = Phase.ACTIVE
		input_locked = false
		print("[CaptureMinigame] Input unlocked - start spinning!")

func _process_active(delta: float) -> void:
	"""Player holds button and spins to fill the bar"""
	if input_locked:
		return

	# Check if player is holding the correct button
	var holding_button = aInputManager.is_action_pressed(current_button_action)

	# Debug button holding every 30 frames
	if Engine.get_frames_drawn() % 30 == 0:
		print("[CaptureMinigame] Button check - expecting: %s, action: %s, holding: %s" % [current_button, current_button_action, holding_button])

	# Get joystick input
	var input_vec = aInputManager.get_movement_vector()
	var is_spinning = false
	var correct_direction = false

	if input_vec.length() > 0.2:  # Lowered threshold from 0.3 to 0.2
		# Calculate angle from input
		var current_angle = atan2(input_vec.y, input_vec.x)

		# Initialize angle on first input
		if not has_initial_angle:
			last_input_angle = current_angle
			has_initial_angle = true
			print("[CaptureMinigame] Initial angle set: %.2f" % current_angle)
		else:
			# Calculate rotation delta
			var angle_diff = angle_difference(last_input_angle, current_angle)

			# Debug output every 30 frames (less spam)
			if Engine.get_frames_drawn() % 30 == 0 and abs(angle_diff) > 0.01:
				print("[CaptureMinigame] Rotation - angle_diff: %.2f, threshold: %.2f, direction: %s" % [angle_diff, rotation_threshold, "CW" if current_direction == 1 else "CCW"])

			if abs(angle_diff) > rotation_threshold:
				is_spinning = true

				# Check if spinning in correct direction
				if current_direction == 1 and angle_diff > 0:
					# Clockwise (positive rotation)
					correct_direction = true
					if Engine.get_frames_drawn() % 30 == 0:
						print("[CaptureMinigame] Clockwise spin detected!")
				elif current_direction == -1 and angle_diff < 0:
					# Counter-clockwise (negative rotation)
					correct_direction = true
					if Engine.get_frames_drawn() % 30 == 0:
						print("[CaptureMinigame] Counter-clockwise spin detected!")

			last_input_angle = current_angle

	# Fill or drain the progress bar
	if holding_button and is_spinning and correct_direction:
		# Correct input! Fill the bar
		fill_progress += fill_speed * delta
		change_progress += fill_speed * delta

		if Engine.get_frames_drawn() % 30 == 0:
			print("[CaptureMinigame] Filling! Progress: %.1f%%" % (fill_progress * 100))

		# Check for periodic changes (at 33% and 66% of each fill)
		if change_progress >= change_interval:
			change_progress = 0.0
			_trigger_random_change()

	else:
		# Wrong input or no input - drain the bar
		fill_progress -= decay_speed * delta
		fill_progress = max(0.0, fill_progress)

		# Debug why not filling
		if Engine.get_frames_drawn() % 60 == 0:
			if not holding_button:
				print("[CaptureMinigame] Not holding button %s" % current_button)
			elif not is_spinning:
				print("[CaptureMinigame] Not spinning (input_vec: %.2f)" % input_vec.length())
			elif not correct_direction:
				print("[CaptureMinigame] Wrong direction")

	# Check if filled
	if fill_progress >= 1.0:
		fills_completed += 1
		fill_progress = 0.0
		change_progress = 0.0
		has_initial_angle = false  # Reset rotation tracking for next fill

		print("[CaptureMinigame] Fill complete! (%d/%d)" % [fills_completed, fills_needed])

		# Update label
		if fills_completed < fills_needed:
			fills_label.text = "Fill %d/%d" % [fills_completed + 1, fills_needed]
			# Randomize for next fill
			_randomize_button()
			_randomize_direction()

		# Check if all fills completed
		if fills_completed >= fills_needed:
			_finish_capture_success()
			return

	# Redraw
	circle_canvas.queue_redraw()

func _trigger_random_change() -> void:
	"""Randomly change either button OR direction (not both)"""
	if randf() > 0.5:
		# Change button
		var old_button = current_button
		while current_button == old_button:
			_randomize_button()
		print("[CaptureMinigame] Button changed mid-fill!")
	else:
		# Change direction
		current_direction *= -1
		has_initial_angle = false  # Reset rotation tracking when direction changes
		var direction_text = "CLOCKWISE" if current_direction == 1 else "COUNTER-CLOCKWISE"
		print("[CaptureMinigame] Direction changed mid-fill to: %s" % direction_text)

func _draw_capture_visual() -> void:
	"""Draw the button icon, direction arrow, and progress circle"""
	var canvas_size = circle_canvas.size
	var center = canvas_size / 2.0

	# Get the controller icon layout
	var icon_layout = get_node_or_null("/root/aControllerIconLayout")
	if not icon_layout:
		return

	# Draw outer circle (empty)
	var outer_radius = 100.0
	_draw_circle_outline(center, outer_radius, Color(0.5, 0.5, 0.5, 0.5), 3.0)

	# Draw progress fill (colored arc)
	if fill_progress > 0.0:
		_draw_progress_arc(center, outer_radius, fill_progress, COLOR_BUBBLE_MAGENTA)

	# Draw background circle behind button icon for visibility
	var icon_bg_radius = 50.0
	circle_canvas.draw_circle(center, icon_bg_radius, Color(0.1, 0.1, 0.15, 0.8))
	_draw_circle_outline(center, icon_bg_radius, COLOR_MILK_WHITE, 3.0)

	# Draw the button icon in the center (larger)
	var icon_texture = icon_layout.get_button_icon(current_button_action)
	if icon_texture:
		var icon_size = Vector2(70, 70)  # Slightly smaller to fit inside background circle
		var icon_pos = center - icon_size / 2.0
		var icon_rect = Rect2(icon_pos, icon_size)
		circle_canvas.draw_texture_rect(icon_texture, icon_rect, false, Color.WHITE)

	# Draw direction arrow below button
	var arrow_y = center.y + 70
	_draw_direction_arrow(center.x, arrow_y, current_direction)

func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	"""Helper to draw a circle outline"""
	var points = 64
	for i in range(points):
		var angle_from = (float(i) / points) * TAU
		var angle_to = (float(i + 1) / points) * TAU
		var point_from = center + Vector2(cos(angle_from), sin(angle_from)) * radius
		var point_to = center + Vector2(cos(angle_to), sin(angle_to)) * radius
		circle_canvas.draw_line(point_from, point_to, color, width)

func _draw_progress_arc(center: Vector2, radius: float, progress: float, color: Color) -> void:
	"""Draw a filled arc showing progress (0.0 to 1.0)"""
	var points = 64
	var filled_points = int(points * progress)

	for i in range(filled_points):
		var angle_from = (float(i) / points) * TAU - (PI / 2.0)  # Start at top
		var angle_to = (float(i + 1) / points) * TAU - (PI / 2.0)

		# Draw thick line for progress arc
		var point_from = center + Vector2(cos(angle_from), sin(angle_from)) * radius
		var point_to = center + Vector2(cos(angle_to), sin(angle_to)) * radius
		circle_canvas.draw_line(point_from, point_to, color, 6.0)

func _draw_direction_arrow(x: float, y: float, direction: int) -> void:
	"""Draw an arrow pointing left (counter-clockwise) or right (clockwise)"""
	var arrow_size = 30.0
	var arrow_color = COLOR_MILK_WHITE

	if direction == 1:
		# Clockwise - arrow pointing RIGHT
		var tip = Vector2(x + arrow_size, y)
		var back_top = Vector2(x - arrow_size / 2, y - arrow_size / 2)
		var back_bottom = Vector2(x - arrow_size / 2, y + arrow_size / 2)

		var points = PackedVector2Array([tip, back_top, back_bottom])
		circle_canvas.draw_colored_polygon(points, arrow_color)
	else:
		# Counter-clockwise - arrow pointing LEFT
		var tip = Vector2(x - arrow_size, y)
		var back_top = Vector2(x + arrow_size / 2, y - arrow_size / 2)
		var back_bottom = Vector2(x + arrow_size / 2, y + arrow_size / 2)

		var points = PackedVector2Array([tip, back_top, back_bottom])
		circle_canvas.draw_colored_polygon(points, arrow_color)

func _finish_capture_success() -> void:
	print("[CaptureMinigame] Capture successful! Completed all fills.")

	input_locked = true
	current_phase = Phase.SHOWING_RESULT
	capture_success = true
	result_text = "GREAT!"

	# Show result
	result_label.text = result_text
	result_label.modulate.a = 1.0

	await get_tree().create_timer(1.5).timeout

	var result = {
		"success": true,
		"grade": "capture",
		"break_rating_reduced": break_rating,  # Reduced all of it!
		"damage_modifier": 1.0,
		"is_crit": false,
		"mp_modifier": 1.0
	}

	minigame_completed.emit()
	_complete_minigame(result)

func _finish_capture_failed() -> void:
	print("[CaptureMinigame] Capture failed!")

	input_locked = true
	current_phase = Phase.SHOWING_RESULT
	capture_success = false
	result_text = "FAILED"

	# Show result
	result_label.text = result_text
	result_label.modulate.a = 1.0

	await get_tree().create_timer(1.5).timeout

	# Calculate partial progress
	var partial_fills = fills_completed + fill_progress
	var total_fills = fills_needed
	var break_rating_reduced = int((partial_fills / total_fills) * break_rating)

	var result = {
		"success": false,
		"grade": "failed",
		"break_rating_reduced": break_rating_reduced,
		"damage_modifier": 1.0,
		"is_crit": false,
		"mp_modifier": 1.0
	}

	minigame_completed.emit()
	_complete_minigame(result)

func _process_showing_result(delta: float) -> void:
	"""Just wait for the result to be shown"""
	pass

func _timeout() -> void:
	"""Called when time runs out"""
	if current_phase == Phase.ACTIVE:
		_finish_capture_failed()
