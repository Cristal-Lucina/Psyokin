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
var rotation_progress: float = 0.0
var last_input_angle: float = 0.0

## Visual elements
var phase_label: Label
var enemy_icon: ColorRect
var bind_result_label: Label
var knot_progress_bar: ProgressBar
var break_bar: ProgressBar
var instruction_label: Label

func _setup_minigame() -> void:
	base_duration = 10.0
	current_duration = base_duration

	# Calculate break rating from enemy data
	_calculate_break_rating()

	# Title
	var title_label = Label.new()
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
	"""Phase 2: Rotate to make knots"""
	current_phase = Phase.BIND
	phase_label.text = "Phase: BIND"
	bind_result_label.text = "%d binds landed!" % landed_binds.size()

	# Calculate knots needed per bind type
	knots_needed = 0
	for bind in landed_binds:
		match bind:
			"basic": knots_needed += 5
			"standard": knots_needed += 3
			"advanced": knots_needed += 1

	instruction_label.text = "Rotate WASD to make %d knots! (Break: %d)" % [knots_needed, break_rating]

	knot_progress_bar.visible = true
	knot_progress_bar.max_value = knots_needed
	break_bar.visible = true

func _process(delta: float) -> void:
	if current_phase != Phase.BIND:
		return

	# Detect rotation input (WASD circular motion)
	var input_vec = Vector2.ZERO
	if Input.is_key_pressed(KEY_W): input_vec.y -= 1
	if Input.is_key_pressed(KEY_S): input_vec.y += 1
	if Input.is_key_pressed(KEY_A): input_vec.x -= 1
	if Input.is_key_pressed(KEY_D): input_vec.x += 1

	if input_vec.length() > 0.5:
		var current_angle = atan2(input_vec.y, input_vec.x)
		var angle_diff = angle_difference(last_input_angle, current_angle)

		if abs(angle_diff) > 0.1:
			rotation_progress += abs(angle_diff)
			last_input_angle = current_angle

			# Check if completed a full rotation
			if rotation_progress >= TAU:
				rotation_progress = 0.0
				knots_made += 1
				knot_progress_bar.value = knots_made

				print("[CaptureMinigame] Knot made! (%d/%d)" % [knots_made, knots_needed])

				if knots_made >= knots_needed:
					_finish_capture_success()

	# Enemy tries to break
	break_bar.value -= delta * 0.5
	if break_bar.value <= 0:
		_finish_capture_failed()

func _finish_capture_success() -> void:
	print("[CaptureMinigame] Capture successful!")
	instruction_label.text = "CAPTURED!"

	await get_tree().create_timer(0.5).timeout

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
	instruction_label.text = "Capture failed!"

	await get_tree().create_timer(0.5).timeout

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
