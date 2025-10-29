extends BaseMinigame
class_name AttackMinigame

## AttackMinigame - Timing-based weak spot attack
## The weak spot moves around a circular path
## Player must time their charge when the weak spot is visible in the circular view
## Missing the timing = automatic red hit

## Configuration
var tempo: int = 1  # Number of attempts (based on TPO)
var brawn: int = 1  # Brawn stat (affects view radius)

## Internal state
enum Phase { WATCHING, CHARGING, COMPLETE }
var current_phase: Phase = Phase.WATCHING
var current_attempt: int = 0
var best_grade: String = "red"
var best_damage_modifier: float = 0.9
var is_crit: bool = false
var has_started: bool = false
var watch_timer: float = 0.0
var watch_time_limit: float = 8.0
var minigame_complete: bool = false  # Lock out all input when complete

## Weak spot movement
var weak_spot_angle: float = 0.0  # Angle around the circle
var weak_spot_orbit_radius: float = 100.0  # How far from center it orbits
var weak_spot_speed: float = 2.0  # Radians per second
var weak_spot_is_visible: bool = false

## View circle
var view_radius: float = 80.0  # Size of visible area (scales with BRW)

## Charging phase
var charge_progress: float = 0.0
var charge_speed: float = 0.5  # Takes 2 seconds to go from red to blue
var is_charging: bool = false
var charge_zone: String = "red"

## Visual elements
var arena: Control  # For custom drawing
var arena_center: Vector2 = Vector2(140, 140)  # Center point for 280x280 arena
var charge_bar: ProgressBar
var charge_label: Label
var instruction_label: Label
var timer_label: Label
var attempt_label: Label

func _setup_minigame() -> void:
	base_duration = watch_time_limit + 5.0
	current_duration = base_duration

	# Calculate view size from BRW (higher BRW = bigger view window)
	view_radius = 60.0 + (brawn * 8.0)
	print("[AttackMinigame] View radius: %.1f (BRW: %d)" % [view_radius, brawn])

	# Randomize starting angle for weak spot
	weak_spot_angle = randf() * TAU

	# Title
	var title_label = Label.new()
	title_label.text = "ATTACK!"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 28)
	content_container.add_child(title_label)

	# Arena (280x280 - circular view)
	arena = Control.new()
	arena.custom_minimum_size = Vector2(280, 280)
	arena.draw.connect(_draw_arena)
	var arena_center_container = CenterContainer.new()
	arena_center_container.add_child(arena)
	content_container.add_child(arena_center_container)

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
	instruction_label.text = "HOLD SPACE when weak spot is visible!"
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.add_theme_font_size_override("font_size", 11)
	content_container.add_child(instruction_label)

func _draw_arena() -> void:
	"""Draw the circular arena with moving weak spot"""
	# Draw outer dark circle (full arena)
	arena.draw_circle(arena_center, 130.0, Color(0.2, 0.2, 0.2, 0.5))

	# Draw visible view circle (lighter)
	arena.draw_circle(arena_center, view_radius, Color(0.3, 0.3, 0.4, 0.8))

	# Draw enemy icon in center
	arena.draw_circle(arena_center, 25.0, Color(0.8, 0.3, 0.3, 1.0))

	# Calculate weak spot position based on angle
	var weak_spot_pos = arena_center + Vector2(
		cos(weak_spot_angle) * weak_spot_orbit_radius,
		sin(weak_spot_angle) * weak_spot_orbit_radius
	)

	# Check if weak spot is visible (inside view circle)
	var distance_from_center = (weak_spot_pos - arena_center).length()
	weak_spot_is_visible = distance_from_center <= view_radius

	# Draw weak spot (bright yellow if visible, dim if not)
	var weak_spot_color = Color(1.0, 1.0, 0.0, 1.0) if weak_spot_is_visible else Color(0.5, 0.5, 0.0, 0.3)
	arena.draw_circle(weak_spot_pos, 10.0, weak_spot_color)

	# Draw view circle border
	_draw_circle_outline(arena_center, view_radius, Color(0.5, 0.7, 1.0, 0.8), 2.0)

func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	"""Helper to draw a circle outline"""
	var points = 64
	for i in range(points + 1):
		var angle_from = (float(i) / points) * TAU
		var angle_to = (float(i + 1) / points) * TAU
		var point_from = center + Vector2(cos(angle_from), sin(angle_from)) * radius
		var point_to = center + Vector2(cos(angle_to), sin(angle_to)) * radius
		arena.draw_line(point_from, point_to, color, width)

func _start_minigame() -> void:
	print("[AttackMinigame] Starting timing attack (attempts: %d, BRW: %d)" % [tempo, brawn])
	current_phase = Phase.WATCHING
	current_attempt = 0
	_start_next_attempt()

func _start_next_attempt() -> void:
	current_attempt += 1
	attempt_label.text = "Attempt: %d/%d" % [current_attempt, tempo]

	if current_attempt > tempo:
		_finish_minigame()
		return

	# Reset for new attempt
	current_phase = Phase.WATCHING
	has_started = false
	watch_timer = 0.0
	weak_spot_is_visible = false
	charge_progress = 0.0
	is_charging = false

	# Randomize weak spot starting position
	weak_spot_angle = randf() * TAU

	# Reset visuals
	charge_bar.value = 0.0
	arena.queue_redraw()

	timer_label.text = "Watch for the weak spot..."
	charge_label.text = "HOLD SPACE when it's visible!"
	instruction_label.text = "HOLD SPACE when weak spot is visible!"

func _process(delta: float) -> void:
	# Stop all processing if minigame is complete
	if minigame_complete:
		return

	match current_phase:
		Phase.WATCHING:
			_process_watching(delta)
		Phase.CHARGING:
			_process_charging(delta)

func _process_watching(delta: float) -> void:
	# Move weak spot around the orbit
	weak_spot_angle += weak_spot_speed * delta
	if weak_spot_angle > TAU:
		weak_spot_angle -= TAU

	# Redraw arena to update weak spot position
	arena.queue_redraw()

	# Update timer
	if not has_started:
		timer_label.text = "Watch for the weak spot..."
	else:
		watch_timer += delta
		timer_label.text = "Time: %.1fs" % (watch_time_limit - watch_timer)

		if watch_timer >= watch_time_limit:
			# Time's up! Force attack
			print("[AttackMinigame] Time's up! Auto-attacking")
			_force_attack()
			return

	# Check for Space HELD to start charging
	if Input.is_key_pressed(KEY_SPACE):
		if not is_charging:
			if not has_started:
				has_started = true
				print("[AttackMinigame] Timer started!")
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
	print("[AttackMinigame] Started charging (weak spot visible: %s)" % weak_spot_is_visible)

	if weak_spot_is_visible:
		charge_label.text = "Charging... Release for: OK → GOOD → GREAT → CRIT"
	else:
		charge_label.text = "Weak spot not visible! Automatic RED hit!"

func _process_charging(delta: float) -> void:
	# Continue moving weak spot and redrawing
	weak_spot_angle += weak_spot_speed * delta
	if weak_spot_angle > TAU:
		weak_spot_angle -= TAU
	arena.queue_redraw()

	# Increase charge while Space is held
	if Input.is_key_pressed(KEY_SPACE):
		if weak_spot_is_visible:
			# Full charge available: Red → Yellow → Green → Blue → stays at Red
			charge_progress += delta * charge_speed
			charge_progress = min(charge_progress, 1.2)  # Cap at 1.2 (past blue, into red)
		else:
			# No charge - locked at red
			charge_progress = 0.0

		# Update charge bar
		charge_bar.value = min(charge_progress, 1.0)

		# Determine current zone
		charge_zone = _get_charge_zone(charge_progress, weak_spot_is_visible)
		_update_charge_visuals(charge_zone)
	else:
		# Released!
		_release_attack()

func _get_charge_zone(progress: float, is_weak_spot_visible: bool) -> String:
	"""Get current charge zone"""
	if not is_weak_spot_visible:
		# Weak spot not visible - always red
		return "red"
	else:
		# Full charge available: Red → Yellow → Green → Blue → Red (stays)
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
	print("[AttackMinigame] Released attack at zone: %s (progress: %.2f, visible: %s)" % [charge_zone, charge_progress, weak_spot_is_visible])

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

	if weak_spot_is_visible:
		result_text = "✓ Good timing! "
	else:
		result_text = "✗ Weak spot not visible! "

	match charge_zone:
		"red": result_text += "OK (-10% damage)"
		"yellow": result_text += "GOOD (Normal damage)"
		"green": result_text += "GREAT (+10% damage)"
		"blue": result_text += "CRIT! (+10% damage + CRITICAL)"

	charge_label.text = result_text

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
