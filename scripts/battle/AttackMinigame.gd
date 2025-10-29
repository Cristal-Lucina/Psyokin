extends BaseMinigame
class_name AttackMinigame

## AttackMinigame - Timing-based reticle minigame for physical attacks
## Player must press button when reticle is in green/blue zone

## Configuration
var tempo: int = 1  # Number of reticles (1-4)

## Internal state
var current_reticle: int = 0
var best_grade: String = "red"
var best_damage_modifier: float = 0.9
var is_crit: bool = false

## Visual elements
var enemy_icon: TextureRect
var reticle_container: CenterContainer
var reticle_outer: ColorRect
var reticle_inner: ColorRect
var instruction_label: Label
var result_label: Label

## Timing
var reticle_time: float = 0.0
var reticle_cycle_duration: float = 1.0  # One full Red->Yellow->Green->Blue->Red cycle

## Reticle zones (percentage of cycle)
const ZONE_RED_1: float = 0.0
const ZONE_YELLOW: float = 0.3
const ZONE_GREEN: float = 0.5
const ZONE_BLUE: float = 0.65
const ZONE_RED_2: float = 0.75

func _setup_minigame() -> void:
	base_duration = 10.0  # 10 seconds max per attack minigame
	current_duration = base_duration

	# Apply status effect speed
	for effect in status_effects:
		if effect == "malaise":
			reticle_cycle_duration *= 0.9  # 10% faster

	# Title
	var title_label = Label.new()
	title_label.text = "ATTACK!"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32)
	content_container.add_child(title_label)

	# Enemy icon placeholder
	enemy_icon = TextureRect.new()
	enemy_icon.custom_minimum_size = Vector2(100, 100)
	enemy_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	enemy_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	var icon_container = CenterContainer.new()
	icon_container.add_child(enemy_icon)
	content_container.add_child(icon_container)

	# Create placeholder enemy icon (colored square)
	var placeholder = ColorRect.new()
	placeholder.color = Color(0.8, 0.3, 0.3, 1.0)
	placeholder.custom_minimum_size = Vector2(100, 100)
	enemy_icon.add_child(placeholder)

	# Reticle display
	reticle_container = CenterContainer.new()
	content_container.add_child(reticle_container)

	# Outer reticle (fixed size)
	reticle_outer = ColorRect.new()
	reticle_outer.custom_minimum_size = Vector2(200, 200)
	reticle_outer.color = Color(0.3, 0.3, 0.3, 0.5)
	reticle_container.add_child(reticle_outer)

	# Inner reticle (shrinking)
	reticle_inner = ColorRect.new()
	reticle_inner.custom_minimum_size = Vector2(200, 200)
	reticle_inner.color = Color(1.0, 0.0, 0.0, 0.8)  # Start red
	reticle_inner.position = Vector2.ZERO
	reticle_outer.add_child(reticle_inner)

	# Instructions
	instruction_label = Label.new()
	instruction_label.text = "Press SPACE when the reticle is GREEN or BLUE!"
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.add_theme_font_size_override("font_size", 16)
	content_container.add_child(instruction_label)

	# Result display
	result_label = Label.new()
	result_label.text = "Reticle %d/%d" % [current_reticle + 1, tempo]
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 20)
	content_container.add_child(result_label)

func _start_minigame() -> void:
	print("[AttackMinigame] Starting with %d reticles" % tempo)
	_start_next_reticle()

func _start_next_reticle() -> void:
	if current_reticle >= tempo:
		_finish_minigame()
		return

	reticle_time = 0.0
	result_label.text = "Reticle %d/%d - Best: %s" % [current_reticle + 1, tempo, best_grade.to_upper()]

func _process(delta: float) -> void:
	if current_reticle >= tempo:
		return

	# Update reticle animation
	reticle_time += delta
	var cycle_progress = fmod(reticle_time, reticle_cycle_duration) / reticle_cycle_duration

	# Determine current zone and color
	var current_zone = _get_zone(cycle_progress)
	_update_reticle_visuals(cycle_progress, current_zone)

	# Check for input
	if Input.is_action_just_pressed("ui_accept") or Input.is_key_pressed(KEY_SPACE):
		_on_button_pressed(current_zone)

func _get_zone(progress: float) -> String:
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

func _update_reticle_visuals(progress: float, zone: String) -> void:
	# Update color based on zone
	match zone:
		"red":
			reticle_inner.color = Color(1.0, 0.0, 0.0, 0.8)
		"yellow":
			reticle_inner.color = Color(1.0, 1.0, 0.0, 0.8)
		"green":
			reticle_inner.color = Color(0.0, 1.0, 0.0, 0.8)
		"blue":
			reticle_inner.color = Color(0.0, 0.5, 1.0, 0.8)

	# Shrink reticle (oscillates 200 -> 50 -> 200)
	var shrink_progress = abs(sin(progress * PI * 2))
	var size = lerp(50.0, 200.0, shrink_progress)
	reticle_inner.custom_minimum_size = Vector2(size, size)
	reticle_inner.size = Vector2(size, size)

	# Center the inner reticle
	var offset = (200.0 - size) / 2.0
	reticle_inner.position = Vector2(offset, offset)

func _on_button_pressed(zone: String) -> void:
	print("[AttackMinigame] Button pressed on zone: %s" % zone)

	# Determine damage modifier and grade
	var damage_modifier: float = 0.9
	var grade: String = zone
	var force_crit: bool = false

	match zone:
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
			force_crit = true

	# Update best grade
	if _is_better_grade(grade, best_grade):
		best_grade = grade
		best_damage_modifier = damage_modifier
		if force_crit:
			is_crit = true

	# Show feedback
	result_label.text = "Hit: %s! Best: %s" % [grade.to_upper(), best_grade.to_upper()]

	# Move to next reticle
	current_reticle += 1

	# Auto-end on blue
	if force_crit:
		print("[AttackMinigame] Blue hit! Auto-ending.")
		_finish_minigame()
	else:
		await get_tree().create_timer(0.3).timeout
		_start_next_reticle()

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
