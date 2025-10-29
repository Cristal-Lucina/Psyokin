extends BaseMinigame
class_name RunMinigame

## RunMinigame - Circle escape minigame for running from battle
## Player must exit through gaps before circle closes

## Configuration
var run_chance: float = 50.0  # Base run percentage
var tempo_diff: int = 0  # Party tempo - enemy tempo (affects speed)
var focus: int = 1  # Focus stat (adds magnet effect)

## Internal state
var circle_radius: float = 100.0  # Current circle radius
var max_radius: float = 100.0  # Maximum radius (outer boundary)
var circle_close_speed: float = 25.0  # pixels per second
var circle_rotation_speed: float = 1.0  # radians per second
var player_pos: Vector2 = Vector2.ZERO
var circle_angle: float = 0.0
var gaps: Array = []  # Array of {start_angle, end_angle}
var arena_center: Vector2 = Vector2(100, 100)  # Center of arena
var is_caught: bool = false  # Flag to freeze movement when caught
var minigame_complete: bool = false  # Flag to stop all processing

## Visual elements
var arena: Control  # Custom control for drawing circles
var instruction_label: Label

func _setup_minigame() -> void:
	base_duration = 8.0
	current_duration = base_duration

	# Calculate circle properties based on run chance
	var gap_count = _calculate_gap_count(run_chance)
	var has_spin = _should_spin(run_chance)

	# Adjust speed based on tempo difference
	circle_close_speed = 50.0 * (1.0 - (tempo_diff * 0.02))
	if tempo_diff < 0:
		circle_close_speed *= 1.2  # Enemy faster = circle closes faster

	if has_spin:
		circle_rotation_speed = 1.0 * (1.0 - (tempo_diff * 0.02))
	else:
		circle_rotation_speed = 0.0

	print("[RunMinigame] Gaps: %d, Spin: %s, Speed: %.1f" % [gap_count, has_spin, circle_close_speed])

	# Generate random gaps
	_generate_gaps(gap_count)

	# Title
	var title_label = Label.new()
	title_label.set_name("TitleLabel")
	title_label.text = "RUN!"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32)
	content_container.add_child(title_label)

	# Arena for drawing circles
	arena = Control.new()
	arena.custom_minimum_size = Vector2(200, 200)
	arena.draw.connect(_draw_arena)
	var arena_container = CenterContainer.new()
	arena_container.add_child(arena)
	content_container.add_child(arena_container)

	# Instructions
	instruction_label = Label.new()
	instruction_label.text = "Use WASD to escape through the gaps!"
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.add_theme_font_size_override("font_size", 16)
	content_container.add_child(instruction_label)

func _calculate_gap_count(chance: float) -> int:
	"""Calculate number of gaps based on run chance"""
	if chance <= 10: return 1
	elif chance <= 30: return 2
	elif chance <= 50: return 4
	elif chance <= 70: return 8
	else: return 10

func _should_spin(chance: float) -> bool:
	"""Determine if circle should spin"""
	return chance < 50

func _generate_gaps(count: int) -> void:
	"""Generate random gap positions"""
	gaps.clear()
	var gap_size = TAU / (count * 2)  # Each gap takes up some angle

	for i in range(count):
		var base_angle = (TAU / count) * i + randf_range(-0.3, 0.3)
		gaps.append({
			"start_angle": base_angle - gap_size / 2,
			"end_angle": base_angle + gap_size / 2
		})

	print("[RunMinigame] Generated %d gaps" % gaps.size())

func _start_minigame() -> void:
	print("[RunMinigame] Starting escape")
	player_pos = Vector2.ZERO
	circle_radius = max_radius

func _draw_arena() -> void:
	"""Draw the circles and player"""
	# Draw outer boundary circle (light gray)
	arena.draw_circle(arena_center, max_radius, Color(0.3, 0.3, 0.3, 0.3))

	# Draw closing circle with gaps (red)
	# We'll draw the circle in segments, skipping the gaps
	var segment_count = 360
	var prev_point = Vector2.ZERO
	var is_first = true

	for i in range(segment_count + 1):
		var angle = (float(i) / segment_count) * TAU + circle_angle
		var normalized_angle = fmod(angle, TAU)

		# Check if this angle is in a gap
		var in_gap = false
		for gap in gaps:
			var gap_start = fmod(gap.start_angle, TAU)
			var gap_end = fmod(gap.end_angle, TAU)
			if normalized_angle >= gap_start and normalized_angle <= gap_end:
				in_gap = true
				break

		var point = arena_center + Vector2(cos(angle), sin(angle)) * circle_radius

		if not in_gap and not is_first:
			# Draw line segment (makes a circle)
			arena.draw_line(prev_point, point, Color(0.8, 0.2, 0.2, 0.8), 3.0)

		prev_point = point
		is_first = in_gap

	# Draw player dot (green)
	var player_screen_pos = arena_center + player_pos
	arena.draw_circle(player_screen_pos, 5.0, Color(0.2, 1.0, 0.2, 1.0))

func _process(delta: float) -> void:
	# Stop all processing if minigame is complete
	if minigame_complete:
		return

	# Handle player movement (only if not caught)
	if not is_caught:
		var move_dir = Vector2.ZERO
		if Input.is_key_pressed(KEY_W): move_dir.y -= 1
		if Input.is_key_pressed(KEY_S): move_dir.y += 1
		if Input.is_key_pressed(KEY_A): move_dir.x -= 1
		if Input.is_key_pressed(KEY_D): move_dir.x += 1

		if move_dir.length() > 0:
			move_dir = move_dir.normalized()
			player_pos += move_dir * 75.0 * delta  # Reduced speed for smaller arena

			# Focus magnet effect (pulls slightly toward nearest gap)
			if focus > 0:
				var nearest_gap = _find_nearest_gap()
				if nearest_gap:
					var gap_angle = (nearest_gap.start_angle + nearest_gap.end_angle) / 2.0
					var gap_dir = Vector2(cos(gap_angle + circle_angle), sin(gap_angle + circle_angle))
					player_pos += gap_dir * (focus * 2.5) * delta  # Reduced magnet effect

	# Close circle (even when caught, for visual feedback)
	circle_radius -= circle_close_speed * delta

	# Rotate circle
	circle_angle += circle_rotation_speed * delta

	# Redraw arena
	arena.queue_redraw()

	# Check win/lose conditions (only if not already caught and not complete)
	if not is_caught and not minigame_complete:
		var distance_from_center = player_pos.length()

		if distance_from_center > max_radius:
			# Player escaped outer boundary!
			_check_escape()
		elif distance_from_center > circle_radius - 5.0:  # 5 pixel buffer for player radius
			# Player is touching or outside the closing circle
			# Check if they're in a gap
			if not _is_in_gap(player_pos):
				# Hit the circle! Freeze and then fail
				_on_caught()

		if circle_radius <= 5:
			# Circle fully closed - caught!
			_on_caught()

func _find_nearest_gap() -> Dictionary:
	"""Find the nearest gap to player's current angle"""
	if gaps.is_empty():
		return {}

	var player_angle = atan2(player_pos.y, player_pos.x)
	var nearest_gap = gaps[0]
	var nearest_dist = 999.0

	for gap in gaps:
		var gap_center = (gap.start_angle + gap.end_angle) / 2.0 + circle_angle
		var dist = abs(angle_difference(player_angle, gap_center))
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_gap = gap

	return nearest_gap

func _is_in_gap(pos: Vector2) -> bool:
	"""Check if position is within a gap"""
	var angle = atan2(pos.y, pos.x) - circle_angle

	for gap in gaps:
		if angle >= gap.start_angle and angle <= gap.end_angle:
			return true

	return false

func _check_escape() -> void:
	"""Check if player successfully escaped"""
	if minigame_complete:
		return  # Already complete, don't check again

	if _is_in_gap(player_pos):
		_finish_success()
	else:
		_on_caught()

func _on_caught() -> void:
	"""Called when player is caught by the circle"""
	if is_caught or minigame_complete:
		return  # Already caught or complete, don't trigger again

	is_caught = true
	minigame_complete = true  # Stop all processing
	print("[RunMinigame] Player caught! Freezing movement...")
	instruction_label.text = "Caught!"

	# Wait a moment while frozen, then finish
	await get_tree().create_timer(0.8).timeout
	_finish_failed()

func _finish_success() -> void:
	print("[RunMinigame] Escaped!")

	minigame_complete = true  # Stop all processing immediately

	# Update title and instruction
	var title_label = content_container.get_node_or_null("TitleLabel")
	if title_label:
		title_label.text = "GREAT!"
	instruction_label.text = "Successfully escaped!"

	await get_tree().create_timer(1.5).timeout

	var result = {
		"success": true,
		"grade": "escape",
		"damage_modifier": 1.0,
		"is_crit": false,
		"mp_modifier": 1.0,
		"tier_downgrade": 0,
		"focus_level": 0
	}

	_complete_minigame(result)

func _finish_failed() -> void:
	print("[RunMinigame] Failed to escape!")

	# Update title and instruction
	var title_label = content_container.get_node_or_null("TitleLabel")
	if title_label:
		title_label.text = "OK"
	instruction_label.text = "Enemy caught you!"

	await get_tree().create_timer(1.5).timeout

	var result = {
		"success": false,
		"grade": "caught",
		"damage_modifier": 1.0,
		"is_crit": false,
		"mp_modifier": 1.0,
		"tier_downgrade": 0,
		"focus_level": 0
	}

	_complete_minigame(result)
