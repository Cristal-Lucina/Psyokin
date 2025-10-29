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
var breaks_completed: int = 0  # Number of breaks achieved
var breaks_needed: int = 0  # Total breaks needed (= break rating)
var break_rating: int = 6
var break_timer: float = 0.0  # Time until enemy breaks free
var minigame_complete: bool = false  # Lock out all input when complete

# Bind point system
enum BindDirection { UP, DOWN, LEFT, RIGHT }
enum WrapDirection { CLOCKWISE, COUNTERCLOCKWISE }
var current_bind_direction: BindDirection = BindDirection.UP
var current_wrap_direction: WrapDirection = WrapDirection.CLOCKWISE
var bind_point_grabbed: bool = false
var drag_start_angle: float = 0.0
var drag_current_angle: float = 0.0
var wrap_progress: float = 0.0  # 0.0 to TAU (full circle)
var wraps_in_current_break: int = 0  # Wraps completed for current break
var wraps_per_point: int = 3  # How many wraps needed per break rating point

## Visual elements
var title_label: Label
var phase_label: Label
var enemy_icon: Control  # Changed to Control for circular drawing
var bind_result_label: Label
var break_progress_bar: ProgressBar  # Shows breaks completed
var break_timer_bar: ProgressBar  # Shows time remaining
var instruction_label: Label
var charm_effect_overlay: Control  # For pink wavy border when enemy is charmed
var charm_anim_time: float = 0.0
var sleep_effect_overlay: Control  # For white wavy border when enemy is asleep
var sleep_anim_time: float = 0.0

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

	# Enemy icon (circular)
	enemy_icon = Control.new()
	enemy_icon.custom_minimum_size = Vector2(100, 100)
	enemy_icon.draw.connect(_draw_enemy_circle)
	var icon_container = CenterContainer.new()
	icon_container.add_child(enemy_icon)
	content_container.add_child(icon_container)

	# Need to defer queue_redraw until after the node is in the tree
	enemy_icon.ready.connect(func(): enemy_icon.queue_redraw())

	# Bind result label
	bind_result_label = Label.new()
	bind_result_label.text = "Rolling binds..."
	bind_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bind_result_label.add_theme_font_size_override("font_size", 18)
	content_container.add_child(bind_result_label)

	# Break progress bar (shows breaks completed)
	break_progress_bar = ProgressBar.new()
	break_progress_bar.max_value = 1.0
	break_progress_bar.value = 0.0
	break_progress_bar.show_percentage = false
	break_progress_bar.custom_minimum_size = Vector2(300, 30)
	break_progress_bar.visible = false
	var progress_container = CenterContainer.new()
	progress_container.add_child(break_progress_bar)
	content_container.add_child(progress_container)

	# Break timer bar (shows time remaining)
	break_timer_bar = ProgressBar.new()
	break_timer_bar.max_value = float(break_rating)
	break_timer_bar.value = float(break_rating)
	break_timer_bar.show_percentage = false
	break_timer_bar.custom_minimum_size = Vector2(300, 30)
	break_timer_bar.visible = false
	var timer_container = CenterContainer.new()
	timer_container.add_child(break_timer_bar)
	content_container.add_child(timer_container)

	# Instructions
	instruction_label = Label.new()
	instruction_label.text = "Rolling binds..."
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.add_theme_font_size_override("font_size", 16)
	content_container.add_child(instruction_label)

	# Charm effect overlay (pink wavy border when enemy is charmed)
	var enemy_ailment = str(enemy_data.get("ailment", "")).to_lower()
	if enemy_ailment == "charm" or enemy_ailment == "charmed":
		charm_effect_overlay = Control.new()
		charm_effect_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		charm_effect_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		charm_effect_overlay.z_index = 102
		charm_effect_overlay.draw.connect(_draw_charm_effect)
		add_child(charm_effect_overlay)
		print("[CaptureMinigame] Enemy is charmed - adding pink wavy border!")

	# Sleep effect overlay (white wavy border when enemy is asleep)
	if enemy_ailment == "sleep" or enemy_ailment == "asleep":
		sleep_effect_overlay = Control.new()
		sleep_effect_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		sleep_effect_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sleep_effect_overlay.z_index = 102
		sleep_effect_overlay.draw.connect(_draw_sleep_effect)
		add_child(sleep_effect_overlay)
		print("[CaptureMinigame] Enemy is asleep - adding white wavy border!")

func _draw_enemy_circle() -> void:
	"""Draw the enemy as a circular shape"""
	var center = Vector2(50, 50)  # Center of 100x100 control
	var radius = 40.0
	enemy_icon.draw_circle(center, radius, Color(0.8, 0.3, 0.3, 1.0))

func _draw_charm_effect() -> void:
	"""Draw animated pink wavy lines around the minigame panel (enemy is charmed!)"""
	if not overlay_panel:
		return

	var panel_pos = overlay_panel.position
	var panel_size = overlay_panel.size
	var wave_segments = 20
	var line_thickness = 3.0

	# Draw smooth wavy pink lines along each edge
	# Top edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var x1 = panel_pos.x + panel_size.x * progress
		var x2 = panel_pos.x + panel_size.x * next_progress
		var y1 = panel_pos.y + sin((charm_anim_time * 2.0) + (progress * TAU * 2)) * 6.0
		var y2 = panel_pos.y + sin((charm_anim_time * 2.0) + (next_progress * TAU * 2)) * 6.0

		var intensity = 0.6 + sin(charm_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(1.0, 0.4, 0.8, intensity)  # Pink!

		charm_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Bottom edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var x1 = panel_pos.x + panel_size.x * progress
		var x2 = panel_pos.x + panel_size.x * next_progress
		var y1 = panel_pos.y + panel_size.y + sin((charm_anim_time * 2.0) + (progress * TAU * 2) + PI) * 6.0
		var y2 = panel_pos.y + panel_size.y + sin((charm_anim_time * 2.0) + (next_progress * TAU * 2) + PI) * 6.0

		var intensity = 0.6 + sin(charm_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(1.0, 0.4, 0.8, intensity)

		charm_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Left edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var y1 = panel_pos.y + panel_size.y * progress
		var y2 = panel_pos.y + panel_size.y * next_progress
		var x1 = panel_pos.x + sin((charm_anim_time * 2.0) + (progress * TAU * 2)) * 6.0
		var x2 = panel_pos.x + sin((charm_anim_time * 2.0) + (next_progress * TAU * 2)) * 6.0

		var intensity = 0.6 + sin(charm_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(1.0, 0.4, 0.8, intensity)

		charm_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Right edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var y1 = panel_pos.y + panel_size.y * progress
		var y2 = panel_pos.y + panel_size.y * next_progress
		var x1 = panel_pos.x + panel_size.x + sin((charm_anim_time * 2.0) + (progress * TAU * 2) + PI) * 6.0
		var x2 = panel_pos.x + panel_size.x + sin((charm_anim_time * 2.0) + (next_progress * TAU * 2) + PI) * 6.0

		var intensity = 0.6 + sin(charm_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(1.0, 0.4, 0.8, intensity)

		charm_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

func _draw_sleep_effect() -> void:
	"""Draw animated white wavy lines around the minigame panel (enemy is asleep!)"""
	if not overlay_panel:
		return

	var panel_pos = overlay_panel.position
	var panel_size = overlay_panel.size
	var wave_segments = 20
	var line_thickness = 3.0

	# Draw smooth wavy white lines along each edge
	# Top edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var x1 = panel_pos.x + panel_size.x * progress
		var x2 = panel_pos.x + panel_size.x * next_progress
		var y1 = panel_pos.y + sin((sleep_anim_time * 2.0) + (progress * TAU * 2)) * 6.0
		var y2 = panel_pos.y + sin((sleep_anim_time * 2.0) + (next_progress * TAU * 2)) * 6.0

		var intensity = 0.6 + sin(sleep_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(1.0, 1.0, 1.0, intensity)  # White!

		sleep_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Bottom edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var x1 = panel_pos.x + panel_size.x * progress
		var x2 = panel_pos.x + panel_size.x * next_progress
		var y1 = panel_pos.y + panel_size.y + sin((sleep_anim_time * 2.0) + (progress * TAU * 2) + PI) * 6.0
		var y2 = panel_pos.y + panel_size.y + sin((sleep_anim_time * 2.0) + (next_progress * TAU * 2) + PI) * 6.0

		var intensity = 0.6 + sin(sleep_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(1.0, 1.0, 1.0, intensity)

		sleep_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Left edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var y1 = panel_pos.y + panel_size.y * progress
		var y2 = panel_pos.y + panel_size.y * next_progress
		var x1 = panel_pos.x + sin((sleep_anim_time * 2.0) + (progress * TAU * 2)) * 6.0
		var x2 = panel_pos.x + sin((sleep_anim_time * 2.0) + (next_progress * TAU * 2)) * 6.0

		var intensity = 0.6 + sin(sleep_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(1.0, 1.0, 1.0, intensity)

		sleep_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Right edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var y1 = panel_pos.y + panel_size.y * progress
		var y2 = panel_pos.y + panel_size.y * next_progress
		var x1 = panel_pos.x + panel_size.x + sin((sleep_anim_time * 2.0) + (progress * TAU * 2) + PI) * 6.0
		var x2 = panel_pos.x + panel_size.x + sin((sleep_anim_time * 2.0) + (next_progress * TAU * 2) + PI) * 6.0

		var intensity = 0.6 + sin(sleep_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(1.0, 1.0, 1.0, intensity)

		sleep_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

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

func _calculate_breaks_needed() -> void:
	"""Calculate breaks needed based on break rating"""
	breaks_needed = enemy_data.get("break_rating", 6)

	# Determine wraps per break based on bind quality
	wraps_per_point = 3  # Default to basic
	for bind in landed_binds:
		match bind:
			"basic": wraps_per_point = 3
			"standard": wraps_per_point = 2
			"advanced": wraps_per_point = 1

	print("[CaptureMinigame] Break rating: %d, wraps per break: %d" % [breaks_needed, wraps_per_point])

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
	# Check if enemy is charmed - massive bonus!
	var enemy_ailment = str(enemy_data.get("ailment", "")).to_lower()
	if enemy_ailment == "charm" or enemy_ailment == "charmed":
		print("[CaptureMinigame] Enemy is CHARMED - boosting hit chance to 90%%!")
		return 90.0  # Charmed enemies are much easier to catch

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

	# Calculate breaks needed
	_calculate_breaks_needed()

	print("[CaptureMinigame] Enemy: %s requires %d breaks" % [enemy_data.get("display_name", ""), breaks_needed])

	# Set break timer based on break rating (seconds)
	break_timer = float(break_rating) * 2.0  # 2 seconds per break rating point

	# Check if enemy is charmed - they break free 50% slower (more time for player)!
	var enemy_ailment = str(enemy_data.get("ailment", "")).to_lower()
	if enemy_ailment == "charm" or enemy_ailment == "charmed":
		var original_time = break_timer
		break_timer *= 1.5  # Charmed enemies take 50% longer to break free
		print("[CaptureMinigame] Enemy is CHARMED - 50%% slower break! (%.1fs -> %.1fs)" % [original_time, break_timer])

	# Start with clockwise direction
	current_wrap_direction = WrapDirection.CLOCKWISE
	wraps_in_current_break = 0
	breaks_completed = 0

	_update_instruction_label()

	break_progress_bar.visible = true
	break_progress_bar.max_value = breaks_needed
	break_progress_bar.value = 0
	break_timer_bar.visible = true
	break_timer_bar.max_value = break_timer
	break_timer_bar.value = break_timer

	# Hide toss phase elements
	bind_result_label.visible = false

	# Create bind arena
	_setup_bind_arena()

	# Spawn first bind point
	_spawn_bind_point()

func _update_instruction_label() -> void:
	"""Update instruction label with current direction and progress"""
	var direction_text = "CLOCKWISE →" if current_wrap_direction == WrapDirection.CLOCKWISE else "← COUNTERCLOCKWISE"
	instruction_label.text = "Wrap %s! (%d/%d breaks)" % [direction_text, breaks_completed, breaks_needed]

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
	# Call parent to update status effect animations
	super._process(delta)

	# Update charm effect animation
	if charm_effect_overlay and is_instance_valid(charm_effect_overlay):
		charm_anim_time += delta
		charm_effect_overlay.queue_redraw()

	# Update sleep effect animation
	if sleep_effect_overlay and is_instance_valid(sleep_effect_overlay):
		sleep_anim_time += delta
		sleep_effect_overlay.queue_redraw()

	# Stop all processing if minigame is complete
	if minigame_complete:
		return

	if current_phase != Phase.BIND:
		return

	# Update break timer
	break_timer -= delta
	break_timer_bar.value = break_timer

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
				# Check if wrapping in correct direction
				var is_correct_direction = false
				if current_wrap_direction == WrapDirection.CLOCKWISE and angle_diff > 0:
					is_correct_direction = true
				elif current_wrap_direction == WrapDirection.COUNTERCLOCKWISE and angle_diff < 0:
					is_correct_direction = true

				if is_correct_direction:
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
						wraps_in_current_break += 1
						wrap_progress = 0.0
						print("[CaptureMinigame] Wrap complete! (%d/%d for current break)" % [wraps_in_current_break, wraps_per_point])

						# Check if completed enough wraps for one break
						if wraps_in_current_break >= wraps_per_point:
							breaks_completed += 1
							wraps_in_current_break = 0
							break_progress_bar.value = breaks_completed
							_update_instruction_label()
							print("[CaptureMinigame] BREAK! (%d/%d)" % [breaks_completed, breaks_needed])

							if breaks_completed >= breaks_needed:
								_finish_capture_success()
								return
							else:
								# Switch direction for next break
								if current_wrap_direction == WrapDirection.CLOCKWISE:
									current_wrap_direction = WrapDirection.COUNTERCLOCKWISE
								else:
									current_wrap_direction = WrapDirection.CLOCKWISE
								_update_instruction_label()
								# Spawn next bind point
								_spawn_bind_point()
						else:
							# More wraps needed for this break
							_spawn_bind_point()
				else:
					# Wrong direction! Flash red and reset wrap progress
					bind_point.color = Color(1.0, 0.0, 0.0, 1.0)
					wrap_progress = 0.0
					bind_trail.clear_points()
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
	print("[CaptureMinigame] Capture successful! Completed all breaks.")

	# Lock out all input immediately
	minigame_complete = true
	current_phase = Phase.COMPLETE

	title_label.text = "GREAT!"
	phase_label.text = "Success!"
	instruction_label.text = "Break rating reduced to 0!"

	await get_tree().create_timer(1.5).timeout

	# Calculate how much break rating we reduced
	var current_break_rating = enemy_data.get("break_rating", 6)
	var break_rating_reduced = current_break_rating  # Reduced all of it!

	var result = {
		"success": true,
		"grade": "capture",
		"break_rating_reduced": break_rating_reduced,
		"wraps_completed": breaks_completed * wraps_per_point,  # Total wraps
		"damage_modifier": 1.0,
		"is_crit": false,
		"mp_modifier": 1.0,
		"tier_downgrade": 0,
		"focus_level": 0
	}

	_complete_minigame(result)

func _finish_capture_failed() -> void:
	print("[CaptureMinigame] Capture failed! Breaks completed: %d/%d" % [breaks_completed, breaks_needed])

	# Lock out all input immediately
	minigame_complete = true
	current_phase = Phase.COMPLETE

	# Break rating reduction is the number of breaks completed
	var break_rating_reduced = breaks_completed

	title_label.text = "OK"
	phase_label.text = "Failed"
	if break_rating_reduced > 0:
		instruction_label.text = "Made progress! -%d break rating" % break_rating_reduced
	else:
		instruction_label.text = "Enemy broke free!"

	await get_tree().create_timer(1.5).timeout

	var total_wraps = (breaks_completed * wraps_per_point) + wraps_in_current_break

	var result = {
		"success": false,
		"grade": "failed",
		"break_rating_reduced": break_rating_reduced,
		"wraps_completed": total_wraps,
		"damage_modifier": 1.0,
		"is_crit": false,
		"mp_modifier": 1.0,
		"tier_downgrade": 0,
		"focus_level": 0
	}

	_complete_minigame(result)
