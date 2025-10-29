extends BaseMinigame
class_name CaptureMinigame

## CaptureMinigame - Two-phase capture system (Toss + Bind)
## Phase 1: Roll to see which binds land
## Phase 2: Rotate to make knots before enemy breaks

## Configuration
var binds: Array = []  # ["basic", "standard", "advanced"]
var enemy_data: Dictionary = {}
var party_member_data: Dictionary = {}

## Internal state
enum Phase { TOSS, BIND, COMPLETE }
var current_phase: Phase = Phase.TOSS
var landed_binds: Array = []
var knots_made: int = 0
var knots_needed: int = 0
var break_rating: int = 6
var break_timer: float = 0.0  # Time until enemy breaks free

# Bind point system
enum BindDirection { UP, DOWN, LEFT, RIGHT }
var current_bind_direction: BindDirection = BindDirection.UP
var bind_point_grabbed: bool = false
var drag_start_angle: float = 0.0
var drag_current_angle: float = 0.0
var wrap_progress: float = 0.0  # 0.0 to TAU (full circle)
var wrap_trails: Array = []  # Visual trails showing wraps

## Visual elements
var title_label: Label
var phase_label: Label
var enemy_icon: ColorRect
var bind_result_label: Label
var knot_progress_bar: ProgressBar
var break_bar: ProgressBar
var instruction_label: Label

# Bind phase visuals
var bind_arena: Control  # Container for dragging mechanic
var bind_point: ColorRect  # The point to grab and drag
var bind_trail: Line2D  # Trail showing wrap around enemy

func _setup_minigame() -> void:
	base_duration = 10.0
	current_duration = base_duration

	# Calculate break rating from enemy data
	_calculate_break_rating()

	# Title
	title_label = Label.new()
	title_label.text = "CAPTURE!"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32)
	content_container.add_child(title_label)

	# Phase label
	phase_label = Label.new()
	phase_label.text = "Phase: TOSS"
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.add_theme_font_size_override("font_size", 20)
	content_container.add_child(phase_label)

	# Enemy icon
	enemy_icon = ColorRect.new()
	enemy_icon.custom_minimum_size = Vector2(100, 100)
	enemy_icon.color = Color(0.8, 0.3, 0.3, 1.0)
	var icon_container = CenterContainer.new()
	icon_container.add_child(enemy_icon)
	content_container.add_child(icon_container)

	# Bind result label
	bind_result_label = Label.new()
	bind_result_label.text = "Rolling binds..."
	bind_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bind_result_label.add_theme_font_size_override("font_size", 18)
	content_container.add_child(bind_result_label)

	# Knot progress bar
	knot_progress_bar = ProgressBar.new()
	knot_progress_bar.max_value = 1.0
	knot_progress_bar.value = 0.0
	knot_progress_bar.show_percentage = false
	knot_progress_bar.custom_minimum_size = Vector2(300, 30)
	knot_progress_bar.visible = false
	var knot_container = CenterContainer.new()
	knot_container.add_child(knot_progress_bar)
	content_container.add_child(knot_container)

	# Break bar
	break_bar = ProgressBar.new()
	break_bar.max_value = float(break_rating)
	break_bar.value = float(break_rating)
	break_bar.show_percentage = false
	break_bar.custom_minimum_size = Vector2(300, 30)
	break_bar.visible = false
	var break_container = CenterContainer.new()
	break_container.add_child(break_bar)
	content_container.add_child(break_container)

	# Instructions
	instruction_label = Label.new()
	instruction_label.text = "Rolling binds..."
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.add_theme_font_size_override("font_size", 16)
	content_container.add_child(instruction_label)

func _calculate_break_rating() -> void:
	"""Calculate enemy break rating from HP and stats"""
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

	print("[CaptureMinigame] Break rating: %d (HP: %.1f%%)" % [break_rating, enemy_hp_percent * 100])

func _calculate_wraps_needed() -> int:
	"""Calculate wraps needed based on enemy type"""
	var actor_id = enemy_data.get("actor_id", "").to_lower()
	var display_name = enemy_data.get("display_name", "").to_lower()

	# Check for slime (3 wraps)
	if "slime" in actor_id or "slime" in display_name:
		return 3

	# Check for goblin (6 wraps)
	if "goblin" in actor_id or "goblin" in display_name:
		return 6

	# Default based on bind quality as fallback
	var wraps = 0
	for bind in landed_binds:
		match bind:
			"basic": wraps += 3
			"standard": wraps += 2
			"advanced": wraps += 1

	return max(1, wraps)

func _start_minigame() -> void:
	print("[CaptureMinigame] Starting - Binds: %s" % str(binds))
	current_phase = Phase.TOSS
	_execute_toss_phase()

func _execute_toss_phase() -> void:
	"""Phase 1: Roll each bind to see if it lands"""
	await get_tree().create_timer(0.5).timeout

	landed_binds.clear()

	for bind_type in binds:
		var land_chance = _calculate_bind_chance(bind_type)
		var roll = randf() * 100.0

		if roll <= land_chance:
			landed_binds.append(bind_type)
			bind_result_label.text += "\n%s LANDED! (%.1f%%)" % [bind_type.to_upper(), land_chance]
		else:
			bind_result_label.text += "\n%s bounced (%.1f%%)" % [bind_type, land_chance]

		await get_tree().create_timer(0.3).timeout

	if landed_binds.is_empty():
		# All bounced!
		instruction_label.text = "All binds bounced! Capture failed."
		await get_tree().create_timer(1.0).timeout
		_finish_capture_failed()
	else:
		# Move to bind phase
		await get_tree().create_timer(0.5).timeout
		_start_bind_phase()

func _calculate_bind_chance(bind_type: String) -> float:
	"""Calculate chance for bind to land"""
	var base_chance = 50.0
	match bind_type:
		"basic": base_chance = 50.0
		"standard": base_chance = 60.0
		"advanced": base_chance = 70.0

	# Modifiers
	var focus_diff = party_member_data.get("FOC", 1) - enemy_data.get("TPO", 1)
	base_chance += focus_diff * 10.0

	# HP modifier
	var enemy_hp_percent = float(enemy_data.get("hp", 1)) / float(enemy_data.get("hp_max", 1))
	if enemy_hp_percent <= 0.1:
		base_chance += 30.0

	# Clamp
	base_chance = clampf(base_chance, 5.0, 95.0)

	return base_chance

func _start_bind_phase() -> void:
	"""Phase 2: Grab and drag bind points to wrap enemy"""
	current_phase = Phase.BIND
	phase_label.text = "Phase: BIND"
	bind_result_label.text = "%d binds landed!" % landed_binds.size()

	# Calculate knots needed based on enemy type
	knots_needed = _calculate_wraps_needed()

	print("[CaptureMinigame] Enemy: %s requires %d wraps" % [enemy_data.get("display_name", ""), knots_needed])

	# Set break timer based on break rating (seconds)
	break_timer = float(break_rating) * 2.0  # 2 seconds per break rating point

	instruction_label.text = "Grab bind points and drag in circles! (%d wraps needed)" % knots_needed

	knot_progress_bar.visible = true
	knot_progress_bar.max_value = knots_needed
	break_bar.visible = true
	break_bar.max_value = break_timer
	break_bar.value = break_timer

	# Hide toss phase elements
	bind_result_label.visible = false

	# Create bind arena
	_setup_bind_arena()

	# Spawn first bind point
	_spawn_bind_point()

func _setup_bind_arena() -> void:
	"""Create the visual arena for bind dragging"""
	bind_arena = Control.new()
	bind_arena.custom_minimum_size = Vector2(200, 200)
	bind_arena.position = Vector2.ZERO
	var arena_container = CenterContainer.new()
	arena_container.add_child(bind_arena)
	content_container.add_child(arena_container)

	# Move enemy icon into arena
	if enemy_icon.get_parent():
		enemy_icon.get_parent().remove_child(enemy_icon)
	bind_arena.add_child(enemy_icon)
	enemy_icon.position = Vector2(50, 50)

	# Add bind trail (Line2D to show wrapping)
	bind_trail = Line2D.new()
	bind_trail.width = 3.0
	bind_trail.default_color = Color(0.2, 0.8, 1.0, 0.8)
	bind_arena.add_child(bind_trail)

func _spawn_bind_point() -> void:
	"""Spawn a new bind point at a random direction"""
	# Pick random direction
	current_bind_direction = randi() % 4 as BindDirection

	# Create or reposition bind point
	if bind_point == null:
		bind_point = ColorRect.new()
		bind_point.custom_minimum_size = Vector2(20, 20)
		bind_point.color = Color(1.0, 1.0, 0.0, 1.0)  # Yellow
		bind_arena.add_child(bind_point)

	# Position based on direction (around 100x100 center)
	var arena_center = Vector2(100, 100)
	var offset_distance = 80.0

	match current_bind_direction:
		BindDirection.UP:
			bind_point.position = arena_center + Vector2(-10, -offset_distance)
		BindDirection.DOWN:
			bind_point.position = arena_center + Vector2(-10, offset_distance - 20)
		BindDirection.LEFT:
			bind_point.position = arena_center + Vector2(-offset_distance, -10)
		BindDirection.RIGHT:
			bind_point.position = arena_center + Vector2(offset_distance - 20, -10)

	bind_point.visible = true
	bind_point_grabbed = false
	wrap_progress = 0.0

	print("[CaptureMinigame] Bind point spawned at: %s" % BindDirection.keys()[current_bind_direction])

func _process(delta: float) -> void:
	if current_phase != Phase.BIND:
		return

	# Update break timer
	break_timer -= delta
	break_bar.value = break_timer

	if break_timer <= 0:
		_finish_capture_failed()
		return

	# Check if player is trying to grab the bind point
	if not bind_point_grabbed:
		var grabbed = false
		match current_bind_direction:
			BindDirection.UP:
				if Input.is_key_pressed(KEY_W):
					grabbed = true
			BindDirection.DOWN:
				if Input.is_key_pressed(KEY_S):
					grabbed = true
			BindDirection.LEFT:
				if Input.is_key_pressed(KEY_A):
					grabbed = true
			BindDirection.RIGHT:
				if Input.is_key_pressed(KEY_D):
					grabbed = true

		if grabbed:
			bind_point_grabbed = true
			bind_point.color = Color(0.0, 1.0, 0.0, 1.0)  # Green when grabbed
			drag_start_angle = _get_direction_angle(current_bind_direction)
			drag_current_angle = drag_start_angle
			bind_trail.clear_points()
			print("[CaptureMinigame] Bind point grabbed!")
	else:
		# Player is dragging - track circular motion
		var input_vec = Vector2.ZERO
		if Input.is_key_pressed(KEY_W): input_vec.y -= 1
		if Input.is_key_pressed(KEY_S): input_vec.y += 1
		if Input.is_key_pressed(KEY_A): input_vec.x -= 1
		if Input.is_key_pressed(KEY_D): input_vec.x += 1

		if input_vec.length() > 0.5:
			# Calculate angle from enemy center
			var current_angle = atan2(input_vec.y, input_vec.x)
			var angle_diff = angle_difference(drag_current_angle, current_angle)

			if abs(angle_diff) > 0.1:
				wrap_progress += abs(angle_diff)
				drag_current_angle = current_angle

				# Add point to trail
				var arena_center = Vector2(100, 100)
				var radius = 60.0
				var trail_point = arena_center + Vector2(cos(current_angle), sin(current_angle)) * radius
				bind_trail.add_point(trail_point)

				# Update bind point position
				bind_point.position = trail_point - Vector2(10, 10)

				# Check if completed a full wrap (360 degrees)
				if wrap_progress >= TAU:
					knots_made += 1
					knot_progress_bar.value = knots_made
					print("[CaptureMinigame] Wrap complete! (%d/%d)" % [knots_made, knots_needed])

					if knots_made >= knots_needed:
						_finish_capture_success()
						return
					else:
						# Spawn next bind point
						_spawn_bind_point()
		else:
			# Player let go - fail this wrap attempt
			if bind_trail.get_point_count() > 5:
				print("[CaptureMinigame] Released too early!")
				_spawn_bind_point()  # Reset

func _get_direction_angle(direction: BindDirection) -> float:
	"""Get starting angle for a direction"""
	match direction:
		BindDirection.UP: return -PI / 2.0
		BindDirection.DOWN: return PI / 2.0
		BindDirection.LEFT: return PI
		BindDirection.RIGHT: return 0.0
	return 0.0

func _finish_capture_success() -> void:
	print("[CaptureMinigame] Capture successful!")
	title_label.text = "GREAT!"
	phase_label.text = "Success!"
	instruction_label.text = "Enemy captured successfully!"

	await get_tree().create_timer(1.5).timeout

	var result = {
		"success": true,
		"grade": "capture",
		"damage_modifier": 1.0,
		"is_crit": false,
		"mp_modifier": 1.0,
		"tier_downgrade": 0,
		"focus_level": 0
	}

	_complete_minigame(result)

func _finish_capture_failed() -> void:
	print("[CaptureMinigame] Capture failed!")
	title_label.text = "OK"
	phase_label.text = "Failed"
	instruction_label.text = "Enemy broke free!"

	await get_tree().create_timer(1.5).timeout

	var result = {
		"success": false,
		"grade": "failed",
		"damage_modifier": 1.0,
		"is_crit": false,
		"mp_modifier": 1.0,
		"tier_downgrade": 0,
		"focus_level": 0,
		"partial_progress": knots_made
	}

	_complete_minigame(result)
