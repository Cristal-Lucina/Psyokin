extends BaseMinigame
class_name RunMinigame

## RunMinigame - Circle escape minigame for running from battle
## Player must exit through gaps before circle closes

## Configuration
var run_chance: float = 50.0  # Base run percentage
var tempo_diff: int = 0  # Party tempo - enemy tempo (affects speed)
var focus: int = 1  # Focus stat (adds magnet effect)

## Internal state
var circle_radius: float = 100.0  # Current catch circle radius (closes in, rotating)
var max_radius: float = 100.0  # Maximum radius (outer escape boundary)
var circle_close_speed: float = 20.0  # pixels per second
var circle_rotation_speed: float = 0.3  # radians per second (slow rotation)
var player_pos: Vector2 = Vector2.ZERO
var circle_angle: float = 0.0  # Current rotation of catch circle
var escape_gap_start: float = 0.0  # Start angle of the ONE continuous gap
var escape_gap_end: float = 0.0  # End angle of the ONE continuous gap
var arena_center: Vector2 = Vector2(100, 100)  # Center of arena
var is_caught: bool = false  # Flag to freeze movement when caught
var minigame_complete: bool = false  # Flag to stop all processing

## Visual elements
var arena: Control  # Custom control for drawing circles
var instruction_label: Label

func _setup_minigame() -> void:
	base_duration = 8.0
	current_duration = base_duration

	# Adjust speed based on tempo difference
	circle_close_speed = 20.0 * (1.0 - (tempo_diff * 0.02))
	if tempo_diff < 0:
		circle_close_speed *= 1.15  # Enemy faster = circle closes slightly faster

	# Always rotate slowly
	circle_rotation_speed = 0.3 * (1.0 - (tempo_diff * 0.02))

	# Generate ONE continuous gap based on escape percentage
	_generate_escape_gap()

	print("[RunMinigame] Escape chance: %.1f%%, Gap size: %.1f°, Speed: %.1f px/s, Rotation: %.2f rad/s" %
		[run_chance, rad_to_deg(escape_gap_end - escape_gap_start), circle_close_speed, circle_rotation_speed])

	# Title
	var title_label = Label.new()
	title_label.set_name("TitleLabel")
	title_label.text = "RUN! (%.0f%% Escape Chance)" % run_chance
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
	instruction_label.text = "Use WASD to escape through the GREEN gap!"
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.add_theme_font_size_override("font_size", 16)
	content_container.add_child(instruction_label)

func _generate_escape_gap() -> void:
	"""Generate ONE continuous escape gap based on run_chance percentage"""
	# Gap size = run_chance percentage of the full circle
	# E.g., 10% escape = 10% of circle is gap (0.1 * TAU radians)
	var gap_size_radians = (run_chance / 100.0) * TAU
	var gap_size_degrees = rad_to_deg(gap_size_radians)

	# Random starting position for the gap (0 to TAU)
	var random_start = randf() * TAU

	escape_gap_start = random_start
	escape_gap_end = random_start + gap_size_radians

	var wraps = escape_gap_end > TAU

	print("[RunMinigame] ===== GAP GENERATION =====")
	print("[RunMinigame] Run chance: %.1f%%" % run_chance)
	print("[RunMinigame] Gap size: %.2f radians = %.1f degrees (%.1f%% of 360°)" %
		[gap_size_radians, gap_size_degrees, (gap_size_degrees / 360.0) * 100.0])
	print("[RunMinigame] Gap range: %.1f° to %.1f° (wraps=%s)" %
		[rad_to_deg(escape_gap_start), rad_to_deg(escape_gap_end), wraps])

	if wraps:
		var wrapped_end = escape_gap_end - TAU
		print("[RunMinigame]   Wrapped: [%.1f° to 360°] + [0° to %.1f°]" %
			[rad_to_deg(escape_gap_start), rad_to_deg(wrapped_end)])
	print("[RunMinigame] ==========================")

func _start_minigame() -> void:
	print("[RunMinigame] Starting escape")
	player_pos = Vector2.ZERO
	circle_radius = max_radius

	# Randomize starting rotation position for catch circle
	circle_angle = randf() * TAU

	print("[RunMinigame] Catch circle starting rotation: %.1f°" % rad_to_deg(circle_angle))

func _draw_arena() -> void:
	"""Draw the circles and player"""
	# Draw outer boundary circle background (light gray)
	arena.draw_circle(arena_center, max_radius, Color(0.3, 0.3, 0.3, 0.3))

	# Draw the OUTER ESCAPE CIRCLE boundary (static, doesn't rotate)
	# Green = escapable (run_chance %), Red = blocked (100-run_chance %)
	var segment_count = 360

	for i in range(segment_count):
		var angle = (float(i) / segment_count) * TAU
		var next_angle = (float(i + 1) / segment_count) * TAU

		# Check if this segment is in the escape gap
		var in_gap = _angle_in_gap(angle)

		var p1 = arena_center + Vector2(cos(angle), sin(angle)) * max_radius
		var p2 = arena_center + Vector2(cos(next_angle), sin(next_angle)) * max_radius

		if in_gap:
			# GREEN for escapable area
			arena.draw_line(p1, p2, Color(0.2, 1.0, 0.2, 1.0), 6.0)
		else:
			# RED for blocked area
			arena.draw_line(p1, p2, Color(0.8, 0.2, 0.2, 1.0), 6.0)

	# Draw CATCH CIRCLE (red, rotating, closing in)
	# The gap is defined in LOCAL circle coordinates and rotates WITH the circle
	for i in range(segment_count):
		var local_angle = (float(i) / segment_count) * TAU

		# Check if this LOCAL angle (relative to circle) has a gap
		var in_gap = _angle_in_gap(local_angle)

		# Only draw if NOT in gap
		if not in_gap:
			# World angle includes rotation for drawing position
			var world_angle = local_angle + circle_angle
			var p1 = arena_center + Vector2(cos(world_angle), sin(world_angle)) * circle_radius
			var next_world_angle = world_angle + (TAU / segment_count)
			var p2 = arena_center + Vector2(cos(next_world_angle), sin(next_world_angle)) * circle_radius
			arena.draw_line(p1, p2, Color(1.0, 0.3, 0.3, 1.0), 4.0)

	# Draw player dot (green with white outline)
	var player_screen_pos = arena_center + player_pos
	arena.draw_circle(player_screen_pos, 6.0, Color(1.0, 1.0, 1.0, 1.0))
	arena.draw_circle(player_screen_pos, 4.0, Color(0.2, 1.0, 0.2, 1.0))

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
			player_pos += move_dir * 100.0 * delta

	# Close catch circle (even when caught, for visual feedback)
	circle_radius -= circle_close_speed * delta

	# Rotate catch circle
	circle_angle += circle_rotation_speed * delta

	# Redraw arena
	arena.queue_redraw()

	# Check win/lose conditions (only if not already caught and not complete)
	if not is_caught and not minigame_complete:
		var distance_from_center = player_pos.length()

		# Check if player reached the outer escape boundary
		if distance_from_center > max_radius - 3.0:
			# Player at escape boundary - check if they're in the escape gap
			_check_escape()
		else:
			# Check if player hit the catch circle (rotating)
			if distance_from_center > circle_radius - 1.0:
				# Player is touching the catch circle
				# Check if they're in the gap (using local angle relative to circle rotation)
				var player_angle = atan2(player_pos.y, player_pos.x)
				var local_angle = player_angle - circle_angle
				var in_gap = _angle_in_gap(local_angle)

				print("[RunMinigame] Catch circle collision check:")
				print("  Player world angle: %.1f°" % rad_to_deg(player_angle))
				print("  Circle rotation: %.1f°" % rad_to_deg(circle_angle))
				print("  Player local angle: %.1f°" % rad_to_deg(local_angle))
				print("  Gap: %.1f° to %.1f°" % [rad_to_deg(escape_gap_start), rad_to_deg(escape_gap_end)])
				print("  In gap: %s" % in_gap)

				if not in_gap:
					# Hit the catch circle! Caught
					print("  → CAUGHT!")
					_on_caught()

		# Check if circle closed completely
		if circle_radius <= 3:
			# Circle fully closed - caught!
			_on_caught()

func _angle_in_gap(angle: float) -> bool:
	"""Check if an angle is within the escape gap"""
	# Normalize angle to 0-TAU
	var normalized_angle = fmod(angle, TAU)
	if normalized_angle < 0:
		normalized_angle += TAU

	# Check if gap wraps around TAU boundary
	# If escape_gap_end > TAU, the gap wraps
	if escape_gap_end > TAU:
		# Gap wraps around: e.g., start=5.5, end=7.0 (wraps at TAU=6.28)
		# This means angles from [5.5 to TAU] OR [0 to (7.0-TAU)] are in the gap
		var wrapped_end = escape_gap_end - TAU
		if normalized_angle >= escape_gap_start or normalized_angle <= wrapped_end:
			return true
	else:
		# Normal gap that doesn't wrap
		if normalized_angle >= escape_gap_start and normalized_angle <= escape_gap_end:
			return true

	return false

func _is_player_in_escape_gap() -> bool:
	"""Check if player position is within the escape gap"""
	var player_angle = atan2(player_pos.y, player_pos.x)
	return _angle_in_gap(player_angle)

func _check_escape() -> void:
	"""Check if player successfully escaped"""
	if minigame_complete:
		return  # Already complete, don't check again

	if _is_player_in_escape_gap():
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
