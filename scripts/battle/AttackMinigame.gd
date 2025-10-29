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
var final_grade: String = "red"
var final_damage_modifier: float = 0.9
var is_crit: bool = false
var has_started: bool = false
var timer: float = 0.0
var time_limit: float = 4.0
var minigame_complete: bool = false  # Lock out all input when complete

## Weak spot movement
var weak_spot_pos: Vector2 = Vector2.ZERO  # Current position
var weak_spot_target: Vector2 = Vector2.ZERO  # Target position
var weak_spot_speed: float = 80.0  # Pixels per second
var weak_spot_is_visible: bool = false
var weak_spot_change_timer: float = 0.0
var weak_spot_change_interval: float = 1.5  # Change direction every 1.5s

## View circle
var view_radius: float = 60.0  # Size of visible area (scales with BRW)
var view_pos: Vector2 = Vector2.ZERO  # View center offset from arena center
var red_dot_radius: float = 12.0  # Red aiming reticle size
var weak_spot_in_red_dot: bool = false  # True if weak spot overlaps red dot

## Charging phase
var charge_progress: float = 0.0
var charge_speed: float = 1.5  # Takes 0.67 seconds to go from red to blue (even faster!)
var is_charging: bool = false
var charge_zone: String = "red"

## Visual elements
var arena: Control  # For custom drawing
var arena_size: float = 200.0  # Smaller arena
var arena_center: Vector2 = Vector2(100, 100)  # Center point for 200x200 arena
var arena_radius: float = 90.0  # Arena bounds
var charge_bar: ProgressBar
var charge_label: Label
var instruction_label: Label
var timer_label: Label

func _setup_minigame() -> void:
	base_duration = time_limit + 3.0  # Shorter overall duration
	current_duration = base_duration

	# Calculate view size from BRW (higher BRW = bigger view window)
	view_radius = 40.0 + (brawn * 5.0)
	print("[AttackMinigame] View radius: %.1f (BRW: %d)" % [view_radius, brawn])

	# Randomize starting position for weak spot
	_randomize_weak_spot_target()
	weak_spot_pos = _get_random_position_in_arena()

	# Title
	var title_label = Label.new()
	title_label.text = "ATTACK!"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 28)
	content_container.add_child(title_label)

	# Arena (200x200 - circular view)
	arena = Control.new()
	arena.custom_minimum_size = Vector2(arena_size, arena_size)
	arena.draw.connect(_draw_arena)
	var arena_center_container = CenterContainer.new()
	arena_center_container.add_child(arena)
	content_container.add_child(arena_center_container)

	# Charge bar
	charge_bar = ProgressBar.new()
	charge_bar.max_value = 1.2  # Allow overcharge to show
	charge_bar.value = 0.0
	charge_bar.show_percentage = false
	charge_bar.custom_minimum_size = Vector2(200, 25)
	var bar_container = CenterContainer.new()
	bar_container.add_child(charge_bar)
	content_container.add_child(bar_container)

	# Charge label
	charge_label = Label.new()
	charge_label.text = "Find weak spot, then HOLD SPACE to charge!"
	charge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	charge_label.add_theme_font_size_override("font_size", 14)
	content_container.add_child(charge_label)

	# Timer label
	timer_label = Label.new()
	timer_label.text = "Move to start!"
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 16)
	content_container.add_child(timer_label)

	# Instructions
	instruction_label = Label.new()
	instruction_label.text = "WASD: Move view | HOLD SPACE: Charge when visible!"
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.add_theme_font_size_override("font_size", 11)
	content_container.add_child(instruction_label)

func _draw_arena() -> void:
	"""Draw the circular arena with moving weak spot"""
	# Draw outer dark circle (full arena)
	arena.draw_circle(arena_center, arena_radius, Color(0.2, 0.2, 0.2, 0.5))

	# Calculate view center position (arena center + view offset)
	var view_center = arena_center + view_pos

	# Draw visible view circle (lighter)
	arena.draw_circle(view_center, view_radius, Color(0.3, 0.3, 0.4, 0.8))

	# Calculate weak spot screen position
	var weak_spot_screen_pos = arena_center + weak_spot_pos

	# Check if weak spot is visible (inside view circle)
	var distance_from_view_center = (weak_spot_screen_pos - view_center).length()
	weak_spot_is_visible = distance_from_view_center <= view_radius

	# Check if weak spot overlaps with red aiming dot
	var distance_from_red_dot = (weak_spot_screen_pos - view_center).length()
	weak_spot_in_red_dot = distance_from_red_dot <= red_dot_radius

	# Draw view circle border
	_draw_circle_outline(view_center, view_radius, Color(0.5, 0.7, 1.0, 0.8), 2.0)

	# Draw red aiming reticle in center of view
	arena.draw_circle(view_center, red_dot_radius, Color(1.0, 0.2, 0.2, 0.6))
	_draw_circle_outline(view_center, red_dot_radius, Color(1.0, 0.3, 0.3, 1.0), 2.0)

	# ONLY draw weak spot if it's visible in the view
	if weak_spot_is_visible:
		arena.draw_circle(weak_spot_screen_pos, 8.0, Color(1.0, 1.0, 0.0, 1.0))

func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	"""Helper to draw a circle outline"""
	var points = 64
	for i in range(points + 1):
		var angle_from = (float(i) / points) * TAU
		var angle_to = (float(i + 1) / points) * TAU
		var point_from = center + Vector2(cos(angle_from), sin(angle_from)) * radius
		var point_to = center + Vector2(cos(angle_to), sin(angle_to)) * radius
		arena.draw_line(point_from, point_to, color, width)

func _get_random_position_in_arena() -> Vector2:
	"""Get a random position within the arena bounds, not too close to center"""
	var angle = randf() * TAU
	var distance = randf_range(30.0, arena_radius - 15.0)
	return Vector2(cos(angle), sin(angle)) * distance

func _randomize_weak_spot_target() -> void:
	"""Pick a new random target for the weak spot"""
	weak_spot_target = _get_random_position_in_arena()
	weak_spot_change_timer = 0.0

func _start_minigame() -> void:
	print("[AttackMinigame] Starting timing attack (BRW: %d)" % brawn)
	current_phase = Phase.WATCHING
	has_started = false
	timer = 0.0
	weak_spot_is_visible = false
	charge_progress = 0.0
	is_charging = false

	# Reset view position to center
	view_pos = Vector2.ZERO

	# Randomize weak spot starting position and target (already done in _setup_minigame)
	# But randomize again for good measure
	weak_spot_pos = _get_random_position_in_arena()
	_randomize_weak_spot_target()

	# Reset visuals
	charge_bar.value = 0.0
	arena.queue_redraw()

	timer_label.text = "Move view to find weak spot..."
	charge_label.text = "HOLD SPACE when it's visible!"
	instruction_label.text = "WASD: Move view | HOLD SPACE: Charge when visible!"

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
	# Handle WASD view movement
	var move_dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W): move_dir.y -= 1
	if Input.is_key_pressed(KEY_S): move_dir.y += 1
	if Input.is_key_pressed(KEY_A): move_dir.x -= 1
	if Input.is_key_pressed(KEY_D): move_dir.x += 1

	if move_dir.length() > 0:
		if not has_started:
			has_started = true
			print("[AttackMinigame] Timer started!")

		move_dir = move_dir.normalized()
		view_pos += move_dir * 80.0 * delta

		# Clamp view position to stay within reasonable bounds
		view_pos.x = clampf(view_pos.x, -60.0, 60.0)
		view_pos.y = clampf(view_pos.y, -60.0, 60.0)

	# Move weak spot towards target randomly
	var direction_to_target = (weak_spot_target - weak_spot_pos).normalized()
	weak_spot_pos += direction_to_target * weak_spot_speed * delta

	# Check if reached target
	if weak_spot_pos.distance_to(weak_spot_target) < 5.0:
		_randomize_weak_spot_target()

	# Also change target periodically
	weak_spot_change_timer += delta
	if weak_spot_change_timer >= weak_spot_change_interval:
		_randomize_weak_spot_target()

	# Redraw arena to update positions
	arena.queue_redraw()

	# Update timer (always, even before started)
	if has_started:
		timer += delta
		timer_label.text = "Time: %.1fs" % (time_limit - timer)

		if timer >= time_limit:
			# Time's up! Force attack
			print("[AttackMinigame] Time's up! Auto-attacking")
			_force_attack()
			return
	else:
		timer_label.text = "Move to start timer..."

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
	print("[AttackMinigame] Started charging (weak spot visible: %s, in red dot: %s)" % [weak_spot_is_visible, weak_spot_in_red_dot])

	if weak_spot_in_red_dot:
		charge_label.text = "Charging... Release for: OK → GOOD → GREAT → CRIT"
	elif weak_spot_is_visible:
		charge_label.text = "Not in red dot! Max tier: GREAT"
	else:
		charge_label.text = "Weak spot not visible! Automatic RED hit!"

func _process_charging(delta: float) -> void:
	# Handle WASD view movement WHILE charging (allows slide-to-crit!)
	var move_dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_W): move_dir.y -= 1
	if Input.is_key_pressed(KEY_S): move_dir.y += 1
	if Input.is_key_pressed(KEY_A): move_dir.x -= 1
	if Input.is_key_pressed(KEY_D): move_dir.x += 1

	if move_dir.length() > 0:
		move_dir = move_dir.normalized()
		view_pos += move_dir * 80.0 * delta

		# Clamp view position to stay within reasonable bounds
		view_pos.x = clampf(view_pos.x, -60.0, 60.0)
		view_pos.y = clampf(view_pos.y, -60.0, 60.0)

	# Continue moving weak spot towards target
	var direction_to_target = (weak_spot_target - weak_spot_pos).normalized()
	weak_spot_pos += direction_to_target * weak_spot_speed * delta

	# Check if reached target
	if weak_spot_pos.distance_to(weak_spot_target) < 5.0:
		_randomize_weak_spot_target()

	# Also change target periodically
	weak_spot_change_timer += delta
	if weak_spot_change_timer >= weak_spot_change_interval:
		_randomize_weak_spot_target()

	# Redraw arena to update positions
	arena.queue_redraw()

	# Update timer (continues during charging!)
	timer += delta
	timer_label.text = "Time: %.1fs" % (time_limit - timer)

	if timer >= time_limit:
		# Time's up! Force release at current charge
		print("[AttackMinigame] Time's up during charging!")
		_release_attack()
		return

	# Increase charge while Space is held
	if Input.is_key_pressed(KEY_SPACE):
		# Always charge, regardless of visibility
		charge_progress += delta * charge_speed
		charge_progress = min(charge_progress, 1.2)  # Cap at 1.2 (past blue, into red)

		# Update charge bar (allow it to show overcharge)
		charge_bar.value = charge_progress

		# Determine current zone based on visibility
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
	elif not weak_spot_in_red_dot:
		# Weak spot visible but not in red dot - cap at green
		if progress < 0.25:
			return "red"
		elif progress < 0.5:
			return "yellow"
		else:
			return "green"  # Cap at green
	else:
		# Weak spot in red dot - full charge available: Red → Yellow → Green → Blue → Red (stays)
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
	print("[AttackMinigame] Released attack at zone: %s (progress: %.2f, visible: %s, in red dot: %s)" % [charge_zone, charge_progress, weak_spot_is_visible, weak_spot_in_red_dot])

	# Reset charging state immediately
	is_charging = false
	current_phase = Phase.COMPLETE  # Stop input processing

	# Determine damage modifier
	var damage_modifier: float = 0.9
	var grade: String = charge_zone
	var got_crit: bool = false

	# Crit (blue) ONLY possible if weak spot is in the red aiming dot
	if charge_zone == "blue" and not weak_spot_in_red_dot:
		grade = "green"
		print("[AttackMinigame] Blue capped to green - weak spot not in red dot")

	# If weak spot not even visible, cap at red
	if not weak_spot_is_visible:
		grade = "red"
		print("[AttackMinigame] Capped to red - weak spot not visible")

	match grade:
		"red":
			damage_modifier = 0.9
		"yellow":
			damage_modifier = 1.0
		"green":
			damage_modifier = 1.1
		"blue":
			damage_modifier = 1.1
			got_crit = true

	# Set final results
	final_grade = grade
	final_damage_modifier = damage_modifier
	is_crit = got_crit

	# Show result feedback
	var result_text = ""

	if weak_spot_in_red_dot:
		result_text = "✓ PERFECT AIM! "
	elif weak_spot_is_visible:
		result_text = "✓ In view... "
	else:
		result_text = "✗ Weak spot not visible! "

	match grade:
		"red": result_text += "OK (-10% damage)"
		"yellow": result_text += "GOOD (Normal damage)"
		"green":
			if charge_zone == "blue" and not weak_spot_in_red_dot:
				result_text += "GREAT (+10% damage) [Not in red dot]"
			else:
				result_text += "GREAT (+10% damage)"
		"blue": result_text += "CRIT! (+10% damage + CRITICAL)"

	charge_label.text = result_text

	# Wait then finish minigame
	await get_tree().create_timer(1.5).timeout
	_finish_minigame()

func _force_attack() -> void:
	"""Time ran out, attack at current position"""
	# Auto-attack at red zone (worst)
	charge_zone = "red"
	final_grade = "red"
	final_damage_modifier = 0.9
	is_crit = false

	# Reset charging state
	is_charging = false
	current_phase = Phase.COMPLETE  # Stop input processing

	charge_label.text = "Time's up! OK (-10% damage)"

	await get_tree().create_timer(1.5).timeout
	_finish_minigame()

func _finish_minigame() -> void:
	print("[AttackMinigame] Finishing - Grade: %s, Modifier: %.2f, Crit: %s" % [final_grade, final_damage_modifier, is_crit])

	# Lock out all input immediately
	minigame_complete = true
	current_phase = Phase.COMPLETE

	var result = {
		"success": true,
		"grade": final_grade,
		"damage_modifier": final_damage_modifier,
		"is_crit": is_crit,
		"mp_modifier": 1.0,
		"tier_downgrade": 0,
		"focus_level": 0
	}

	_complete_minigame(result)
