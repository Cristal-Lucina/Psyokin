extends BaseMinigame
class_name AttackMinigame

## AttackMinigame - Weak spot hunting with WASD movement + timing
## Phase 1: Move reticle with WASD to find enemy weak spot
## Phase 2: Press Space to lock in and do timing challenge
## Phase 3: If hit Green/Blue, press Space again for crit attempt

## Configuration
var tempo: int = 1  # Number of attempts (based on TPO)
var brawn: int = 1  # Brawn stat (affects reticle size)

## Internal state
enum Phase { HUNTING, TIMING, CRIT_ATTEMPT, COMPLETE }
var current_phase: Phase = Phase.HUNTING
var current_attempt: int = 0
var best_grade: String = "red"
var best_damage_modifier: float = 0.9
var is_crit: bool = false
var has_moved: bool = false
var hunt_timer: float = 0.0
var hunt_time_limit: float = 8.0

## Weak spot
var weak_spot_pos: Vector2 = Vector2.ZERO
var weak_spot_found: bool = false
var locked_on_weak_spot: bool = false

## Reticle
var reticle_pos: Vector2 = Vector2.ZERO
var reticle_radius: float = 50.0  # Base size, scales with BRW

## Timing phase
var timing_progress: float = 0.0
var timing_cycle_duration: float = 1.0
var waiting_for_input: bool = false
var first_hit_grade: String = ""

## Visual elements
var enemy_container: Control
var enemy_icon: ColorRect
var weak_spot_indicator: ColorRect
var reticle_outer: ColorRect
var reticle_crosshair: ColorRect
var timing_display: Control
var timing_bar: ColorRect
var instruction_label: Label
var timer_label: Label
var attempt_label: Label

## Zone thresholds
const ZONE_RED_1: float = 0.0
const ZONE_YELLOW: float = 0.3
const ZONE_GREEN: float = 0.55
const ZONE_BLUE: float = 0.7
const ZONE_RED_2: float = 0.85

func _setup_minigame() -> void:
	base_duration = hunt_time_limit + 5.0
	current_duration = base_duration

	# Calculate reticle size from BRW (higher BRW = bigger reticle)
	reticle_radius = 40.0 + (brawn * 5.0)
	print("[AttackMinigame] Reticle radius: %.1f (BRW: %d)" % [reticle_radius, brawn])

	# Generate random weak spot position (not in center) - scaled for smaller arena
	weak_spot_pos = Vector2(
		randf_range(-100.0, 100.0),
		randf_range(-100.0, 100.0)
	)
	if weak_spot_pos.length() < 35.0:
		weak_spot_pos = weak_spot_pos.normalized() * 70.0  # Push away from center

	# Title
	var title_label = Label.new()
	title_label.text = "ATTACK!"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32)
	content_container.add_child(title_label)

	# Enemy area (280x280 - smaller to fit in 35% panel)
	enemy_container = Control.new()
	enemy_container.custom_minimum_size = Vector2(280, 280)
	var enemy_center = CenterContainer.new()
	enemy_center.add_child(enemy_container)
	content_container.add_child(enemy_center)

	# Enemy icon (center)
	enemy_icon = ColorRect.new()
	enemy_icon.custom_minimum_size = Vector2(60, 60)
	enemy_icon.color = Color(0.8, 0.3, 0.3, 1.0)
	enemy_icon.position = Vector2(110, 110)
	enemy_container.add_child(enemy_icon)

	# Weak spot indicator (hidden at start, shows when found)
	weak_spot_indicator = ColorRect.new()
	weak_spot_indicator.custom_minimum_size = Vector2(16, 16)
	weak_spot_indicator.color = Color(1.0, 1.0, 0.0, 0.0)  # Transparent yellow
	weak_spot_indicator.position = Vector2(140, 140) + weak_spot_pos - Vector2(8, 8)
	enemy_container.add_child(weak_spot_indicator)

	# Player reticle (starts at center)
	reticle_outer = ColorRect.new()
	var reticle_size = reticle_radius * 2
	reticle_outer.custom_minimum_size = Vector2(reticle_size, reticle_size)
	reticle_outer.color = Color(0.3, 0.8, 0.3, 0.3)
	reticle_outer.position = Vector2(140, 140) - Vector2(reticle_radius, reticle_radius)
	enemy_container.add_child(reticle_outer)

	# Crosshair in center of reticle
	reticle_crosshair = ColorRect.new()
	reticle_crosshair.custom_minimum_size = Vector2(4, 4)
	reticle_crosshair.color = Color(0.0, 1.0, 0.0, 1.0)
	reticle_crosshair.position = Vector2(reticle_radius - 2, reticle_radius - 2)
	reticle_outer.add_child(reticle_crosshair)

	# Timing display (hidden until locked in)
	timing_display = Control.new()
	timing_display.visible = false
	content_container.add_child(timing_display)

	var timing_container = CenterContainer.new()
	timing_display.add_child(timing_container)

	timing_bar = ColorRect.new()
	timing_bar.custom_minimum_size = Vector2(300, 40)
	timing_bar.color = Color(1.0, 0.0, 0.0, 0.8)
	timing_container.add_child(timing_bar)

	# Labels
	var label_container = HBoxContainer.new()
	label_container.alignment = BoxContainer.ALIGNMENT_CENTER
	content_container.add_child(label_container)

	timer_label = Label.new()
	timer_label.text = "Move to start!"
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 18)
	label_container.add_child(timer_label)

	label_container.add_child(Control.new())  # Spacer

	attempt_label = Label.new()
	attempt_label.text = "Attempt: 1/%d" % tempo
	attempt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	attempt_label.add_theme_font_size_override("font_size", 18)
	label_container.add_child(attempt_label)

	# Instructions
	instruction_label = Label.new()
	instruction_label.text = "WASD: Find weak spot | SPACE: Attack!"
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.add_theme_font_size_override("font_size", 12)
	content_container.add_child(instruction_label)

func _start_minigame() -> void:
	print("[AttackMinigame] Starting weak spot hunt (attempts: %d, BRW: %d)" % [tempo, brawn])
	current_phase = Phase.HUNTING
	current_attempt = 0
	_start_next_attempt()

func _start_next_attempt() -> void:
	current_attempt += 1
	attempt_label.text = "Attempt: %d/%d" % [current_attempt, tempo]

	if current_attempt > tempo:
		_finish_minigame()
		return

	# Reset for new attempt
	current_phase = Phase.HUNTING
	has_moved = false
	hunt_timer = 0.0
	weak_spot_found = false
	locked_on_weak_spot = false
	reticle_pos = Vector2.ZERO

	# Reset visuals
	reticle_outer.position = Vector2(140, 140) - Vector2(reticle_radius, reticle_radius)
	reticle_outer.color = Color(0.3, 0.8, 0.3, 0.3)
	reticle_outer.visible = true
	weak_spot_indicator.color = Color(1.0, 1.0, 0.0, 0.0)
	weak_spot_indicator.visible = true
	timing_display.visible = false

	timer_label.text = "Move to start!"
	instruction_label.text = "WASD: Find weak spot | SPACE: Attack!"

func _process(delta: float) -> void:
	match current_phase:
		Phase.HUNTING:
			_process_hunting(delta)
		Phase.TIMING:
			_process_timing(delta)
		Phase.CRIT_ATTEMPT:
			_process_crit_attempt(delta)

func _process_hunting(delta: float) -> void:
	# Handle WASD movement
	var move_dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W): move_dir.y -= 1
	if Input.is_key_pressed(KEY_S): move_dir.y += 1
	if Input.is_key_pressed(KEY_A): move_dir.x -= 1
	if Input.is_key_pressed(KEY_D): move_dir.x += 1

	if move_dir.length() > 0:
		if not has_moved:
			has_moved = true
			print("[AttackMinigame] Timer started!")

		move_dir = move_dir.normalized()
		reticle_pos += move_dir * 150.0 * delta

		# Clamp to arena bounds (smaller arena = 280x280, center at 140)
		reticle_pos.x = clampf(reticle_pos.x, -125.0, 125.0)
		reticle_pos.y = clampf(reticle_pos.y, -125.0, 125.0)

		# Update reticle position
		reticle_outer.position = Vector2(140, 140) + reticle_pos - Vector2(reticle_radius, reticle_radius)

	# Check if reticle overlaps weak spot
	var distance = reticle_pos.distance_to(weak_spot_pos)
	if distance < reticle_radius:
		# Found weak spot!
		if not weak_spot_found:
			weak_spot_found = true
			print("[AttackMinigame] Weak spot found!")

		# Highlight reticle and weak spot
		reticle_outer.color = Color(1.0, 1.0, 0.0, 0.5)  # Yellow glow
		weak_spot_indicator.color = Color(1.0, 1.0, 0.0, 0.8)  # Show weak spot
	else:
		weak_spot_found = false
		reticle_outer.color = Color(0.3, 0.8, 0.3, 0.3)  # Normal green
		weak_spot_indicator.color = Color(1.0, 1.0, 0.0, 0.0)  # Hide weak spot

	# Update timer
	if has_moved:
		hunt_timer += delta
		timer_label.text = "Time: %.1fs" % (hunt_time_limit - hunt_timer)

		if hunt_timer >= hunt_time_limit:
			# Time's up! Auto-lock current position
			print("[AttackMinigame] Time's up! Auto-locking position")
			_lock_position()

	# Check for Space press to lock in
	if Input.is_action_just_pressed("ui_accept") or (Input.is_key_pressed(KEY_SPACE) and not waiting_for_input):
		_lock_position()
		waiting_for_input = true
		await get_tree().create_timer(0.2).timeout
		waiting_for_input = false

func _lock_position() -> void:
	"""Lock reticle position and start timing phase"""
	locked_on_weak_spot = weak_spot_found
	current_phase = Phase.TIMING
	timing_progress = 0.0
	waiting_for_input = false

	# Hide hunting UI
	reticle_outer.visible = false
	weak_spot_indicator.visible = false

	# Show timing UI
	timing_display.visible = true

	if locked_on_weak_spot:
		instruction_label.text = "WEAK SPOT! Press SPACE for Green/Blue!"
		print("[AttackMinigame] Locked on WEAK SPOT - full zones available")
	else:
		instruction_label.text = "Press SPACE for Yellow (no weak spot found)"
		print("[AttackMinigame] Locked on empty area - limited zones only")

	# Small delay before accepting input
	await get_tree().create_timer(0.3).timeout
	waiting_for_input = true

func _process_timing(delta: float) -> void:
	# Cycle timing bar
	timing_progress += delta
	var cycle_progress = fmod(timing_progress, timing_cycle_duration) / timing_cycle_duration

	# Determine current zone
	var zone = _get_zone(cycle_progress, locked_on_weak_spot)
	_update_timing_bar(cycle_progress, zone)

	# Check for Space press
	if waiting_for_input and (Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_SPACE)):
		_on_timing_press(zone)
		waiting_for_input = false

func _get_zone(progress: float, has_weak_spot: bool) -> String:
	"""Get current zone - limited zones if no weak spot"""
	if not has_weak_spot:
		# Only Red and Yellow available
		if progress < 0.5:
			return "red"
		else:
			return "yellow"
	else:
		# Full zones available
		if progress < ZONE_YELLOW:
			return "red"
		elif progress < ZONE_GREEN:
			return "yellow"
		elif progress < ZONE_BLUE:
			return "green"
		elif progress < ZONE_RED_2:
			return "blue"
		else:
			return "red"

func _update_timing_bar(progress: float, zone: String) -> void:
	"""Update timing bar color"""
	match zone:
		"red":
			timing_bar.color = Color(1.0, 0.0, 0.0, 0.8)
		"yellow":
			timing_bar.color = Color(1.0, 1.0, 0.0, 0.8)
		"green":
			timing_bar.color = Color(0.0, 1.0, 0.0, 0.8)
		"blue":
			timing_bar.color = Color(0.0, 0.5, 1.0, 0.8)

	# Shrink bar to show progress
	var shrink = abs(sin(progress * PI * 2))
	var width = lerp(100.0, 300.0, shrink)
	timing_bar.custom_minimum_size.x = width

func _on_timing_press(zone: String) -> void:
	"""Handle first timing press"""
	print("[AttackMinigame] First press on zone: %s (weak spot: %s)" % [zone, locked_on_weak_spot])
	first_hit_grade = zone

	# Determine damage modifier
	var damage_modifier: float = 0.9
	match zone:
		"red":
			damage_modifier = 0.9
		"yellow":
			damage_modifier = 1.0
		"green":
			damage_modifier = 1.1
		"blue":
			damage_modifier = 1.1

	# Update best if better
	if _is_better_grade(zone, best_grade):
		best_grade = zone
		best_damage_modifier = damage_modifier

	# Show result feedback
	timing_display.visible = false
	var result_text = ""

	if locked_on_weak_spot:
		result_text = "✓ WEAK SPOT FOUND!\n"
	else:
		result_text = "✗ Weak spot missed\n"

	result_text += "Hit: " + zone.to_upper() + " | "

	if damage_modifier < 1.0:
		result_text += "Damage: -10%"
	elif damage_modifier > 1.0:
		result_text += "Damage: +10%"
	else:
		result_text += "Damage: Normal"

	instruction_label.text = result_text

	# If hit Green or Blue on weak spot, offer crit attempt
	if (zone == "green" or zone == "blue") and locked_on_weak_spot:
		await get_tree().create_timer(1.0).timeout
		_start_crit_attempt()
	else:
		# No crit attempt, show result then move to next
		await get_tree().create_timer(1.5).timeout
		_start_next_attempt()

func _start_crit_attempt() -> void:
	"""Start crit timing phase (faster!)"""
	current_phase = Phase.CRIT_ATTEMPT
	timing_progress = 0.0
	waiting_for_input = false
	timing_cycle_duration = 0.6  # Faster for crit!

	instruction_label.text = "CRIT CHANCE! Press SPACE on BLUE!"
	print("[AttackMinigame] Crit attempt started (faster timing)")

	# Small delay before accepting input
	await get_tree().create_timer(0.3).timeout
	waiting_for_input = true

func _process_crit_attempt(delta: float) -> void:
	# Faster cycling
	timing_progress += delta
	var cycle_progress = fmod(timing_progress, timing_cycle_duration) / timing_cycle_duration

	# Only Blue zone matters for crit
	var zone = "red"
	if cycle_progress >= 0.4 and cycle_progress < 0.6:
		zone = "blue"

	_update_timing_bar(cycle_progress, zone)

	# Check for Space press
	if waiting_for_input and (Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_SPACE)):
		timing_display.visible = false

		if zone == "blue":
			is_crit = true
			print("[AttackMinigame] CRIT SUCCESS!")
			instruction_label.text = "★ CRITICAL HIT! ★\nDouble damage!"
		else:
			print("[AttackMinigame] Crit missed")
			instruction_label.text = "Crit missed\nStill a good hit though!"

		waiting_for_input = false
		await get_tree().create_timer(1.5).timeout
		_start_next_attempt()

func _is_better_grade(new_grade: String, old_grade: String) -> bool:
	var grade_values = {"red": 0, "yellow": 1, "green": 2, "blue": 3}
	return grade_values.get(new_grade, 0) > grade_values.get(old_grade, 0)

func _finish_minigame() -> void:
	print("[AttackMinigame] Finishing - Best: %s, Modifier: %.2f, Crit: %s" % [best_grade, best_damage_modifier, is_crit])

	var result = {
		"success": true,
		"grade": best_grade,
		"damage_modifier": best_damage_modifier,
		"is_crit": is_crit,
		"mp_modifier": 1.0,
		"tier_downgrade": 0,
		"focus_level": 0
	}

	_complete_minigame(result)
