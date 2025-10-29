extends BaseMinigame
class_name AttackMinigame

## AttackMinigame - Weak spot hunting with hold-to-charge attack
## Phase 1: Move reticle with WASD to find enemy weak spot
## Phase 2: HOLD Space when on weak spot, gauge charges through colors
## Phase 3: RELEASE Space at desired color to attack

## Configuration
var tempo: int = 1  # Number of attempts (based on TPO)
var brawn: int = 1  # Brawn stat (affects reticle size)

## Internal state
enum Phase { HUNTING, CHARGING, COMPLETE }
var current_phase: Phase = Phase.HUNTING
var current_attempt: int = 0
var best_grade: String = "red"
var best_damage_modifier: float = 0.9
var is_crit: bool = false
var has_moved: bool = false
var hunt_timer: float = 0.0
var hunt_time_limit: float = 8.0
var minigame_complete: bool = false  # Lock out all input when complete

## Weak spot
var weak_spot_pos: Vector2 = Vector2.ZERO
var weak_spot_found: bool = false

## Reticle
var reticle_pos: Vector2 = Vector2.ZERO
var reticle_radius: float = 50.0  # Base size, scales with BRW

## Charging phase
var charge_progress: float = 0.0
var charge_speed: float = 0.5  # Takes 2 seconds to go from red to blue
var is_charging: bool = false
var charge_zone: String = "red"

## Visual elements
var enemy_container: Control
var enemy_icon: ColorRect
var weak_spot_indicator: ColorRect
var reticle_outer: ColorRect
var reticle_crosshair: ColorRect
var charge_bar: ProgressBar
var charge_label: Label
var instruction_label: Label
var timer_label: Label
var attempt_label: Label

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
	title_label.add_theme_font_size_override("font_size", 28)
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

	# Charge bar
	charge_bar = ProgressBar.new()
	charge_bar.max_value = 1.0
	charge_bar.value = 0.0
	charge_bar.show_percentage = false
	charge_bar.custom_minimum_size = Vector2(280, 30)
	var bar_container = CenterContainer.new()
	bar_container.add_child(charge_bar)
	content_container.add_child(bar_container)

	# Charge label
	charge_label = Label.new()
	charge_label.text = "Find weak spot, then HOLD SPACE to charge!"
	charge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	charge_label.add_theme_font_size_override("font_size", 14)
	content_container.add_child(charge_label)

	# Labels
	var label_container = HBoxContainer.new()
	label_container.alignment = BoxContainer.ALIGNMENT_CENTER
	content_container.add_child(label_container)

	timer_label = Label.new()
	timer_label.text = "Move to start!"
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 16)
	label_container.add_child(timer_label)

	label_container.add_child(Control.new())  # Spacer

	attempt_label = Label.new()
	attempt_label.text = "Attempt: 1/%d" % tempo
	attempt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	attempt_label.add_theme_font_size_override("font_size", 16)
	label_container.add_child(attempt_label)

	# Instructions
	instruction_label = Label.new()
	instruction_label.text = "WASD: Find weak spot | HOLD SPACE: Charge attack!"
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.add_theme_font_size_override("font_size", 11)
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
	reticle_pos = Vector2.ZERO
	charge_progress = 0.0
	is_charging = false

	# Reset visuals
	reticle_outer.position = Vector2(140, 140) - Vector2(reticle_radius, reticle_radius)
	reticle_outer.color = Color(0.3, 0.8, 0.3, 0.3)
	reticle_outer.visible = true
	weak_spot_indicator.color = Color(1.0, 1.0, 0.0, 0.0)
	weak_spot_indicator.visible = true
	charge_bar.value = 0.0

	timer_label.text = "Move to start!"
	charge_label.text = "Find weak spot, then HOLD SPACE to charge!"
	instruction_label.text = "WASD: Find weak spot | HOLD SPACE: Charge attack!"

func _process(delta: float) -> void:
	# Stop all processing if minigame is complete
	if minigame_complete:
		return

	match current_phase:
		Phase.HUNTING:
			_process_hunting(delta)
		Phase.CHARGING:
			_process_charging(delta)

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
			# Time's up! Force attack at current position
			print("[AttackMinigame] Time's up! Auto-attacking")
			_force_attack()

	# Check for Space HELD to start charging
	if Input.is_key_pressed(KEY_SPACE):
		if not is_charging:
			_start_charging()
			is_charging = true
	else:
		if is_charging:
			# Released! Attack at current charge
			_release_attack()
			is_charging = false

func _start_charging() -> void:
	"""Start charging the attack gauge"""
	current_phase = Phase.CHARGING
	charge_progress = 0.0
	print("[AttackMinigame] Started charging (weak spot: %s)" % weak_spot_found)

	if weak_spot_found:
		charge_label.text = "Charging... Release for: OK → GOOD → GREAT → CRIT"
	else:
		charge_label.text = "No weak spot! Limited charge: OK → GOOD"

func _process_charging(delta: float) -> void:
	# Increase charge while Space is held
	if Input.is_key_pressed(KEY_SPACE):
		if weak_spot_found:
			# Full charge available: Red → Yellow → Green → Blue → stays at Red
			charge_progress += delta * charge_speed
			charge_progress = min(charge_progress, 1.2)  # Cap at 1.2 (past blue, into red)
		else:
			# Limited charge: Red → Yellow only
			charge_progress += delta * charge_speed
			charge_progress = min(charge_progress, 0.5)  # Cap at yellow

		# Update charge bar
		charge_bar.value = min(charge_progress, 1.0)

		# Determine current zone
		charge_zone = _get_charge_zone(charge_progress, weak_spot_found)
		_update_charge_visuals(charge_zone)
	else:
		# Released!
		_release_attack()

func _get_charge_zone(progress: float, has_weak_spot: bool) -> String:
	"""Get current charge zone"""
	if not has_weak_spot:
		# Limited: Red (0-0.25) → Yellow (0.25-0.5)
		if progress < 0.25:
			return "red"
		else:
			return "yellow"
	else:
		# Full: Red → Yellow → Green → Blue → Red (stays)
		if progress < 0.25:
			return "red"
		elif progress < 0.5:
			return "yellow"
		elif progress < 0.75:
			return "green"
		elif progress < 1.0:
			return "blue"
		else:
			return "red"  # Overcharged, back to red

func _update_charge_visuals(zone: String) -> void:
	"""Update charge bar color and label"""
	match zone:
		"red":
			charge_bar.modulate = Color(1.0, 0.3, 0.3, 1.0)
			charge_label.text = "OK"
		"yellow":
			charge_bar.modulate = Color(1.0, 1.0, 0.3, 1.0)
			charge_label.text = "GOOD"
		"green":
			charge_bar.modulate = Color(0.3, 1.0, 0.3, 1.0)
			charge_label.text = "GREAT"
		"blue":
			charge_bar.modulate = Color(0.3, 0.6, 1.0, 1.0)
			charge_label.text = "CRIT!"

func _release_attack() -> void:
	"""Release attack at current charge level"""
	print("[AttackMinigame] Released attack at zone: %s (progress: %.2f)" % [charge_zone, charge_progress])

	# Determine damage modifier
	var damage_modifier: float = 0.9
	var grade: String = charge_zone
	var got_crit: bool = false

	match charge_zone:
		"red":
			damage_modifier = 0.9
			grade = "red"
		"yellow":
			damage_modifier = 1.0
			grade = "yellow"
		"green":
			damage_modifier = 1.1
			grade = "green"
		"blue":
			damage_modifier = 1.1
			grade = "blue"
			got_crit = true

	# Update best if better
	if _is_better_grade(grade, best_grade):
		best_grade = grade
		best_damage_modifier = damage_modifier
		if got_crit:
			is_crit = true

	# Show result feedback
	var result_text = ""

	if weak_spot_found:
		result_text = "✓ WEAK SPOT! "
	else:
		result_text = "✗ Missed weak spot | "

	match charge_zone:
		"red": result_text += "OK (-10% damage)"
		"yellow": result_text += "GOOD (Normal damage)"
		"green": result_text += "GREAT (+10% damage)"
		"blue": result_text += "CRIT! (+10% damage + CRITICAL)"

	charge_label.text = result_text

	# Hide visuals
	reticle_outer.visible = false
	weak_spot_indicator.visible = false

	# Wait then move to next attempt
	await get_tree().create_timer(1.5).timeout
	_start_next_attempt()

func _force_attack() -> void:
	"""Time ran out, attack at current position"""
	# Auto-attack at red zone (worst)
	charge_zone = "red"
	best_grade = "red"
	best_damage_modifier = 0.9

	charge_label.text = "Time's up! OK (-10% damage)"
	reticle_outer.visible = false
	weak_spot_indicator.visible = false

	await get_tree().create_timer(1.5).timeout
	_start_next_attempt()

func _is_better_grade(new_grade: String, old_grade: String) -> bool:
	var grade_values = {"red": 0, "yellow": 1, "green": 2, "blue": 3}
	return grade_values.get(new_grade, 0) > grade_values.get(old_grade, 0)

func _finish_minigame() -> void:
	print("[AttackMinigame] Finishing - Best: %s, Modifier: %.2f, Crit: %s" % [best_grade, best_damage_modifier, is_crit])

	# Lock out all input immediately
	minigame_complete = true
	current_phase = Phase.COMPLETE

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
