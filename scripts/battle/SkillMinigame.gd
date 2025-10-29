extends BaseMinigame
class_name SkillMinigame

## SkillMinigame - Focus charging + button sequence for skills
## Phase 1: Hold button to charge focus (faster with higher Focus stat)
## Phase 2: Input button sequence correctly

## Configuration
var focus_stat: int = 1  # Focus stat value (affects charge speed)
var skill_sequence: Array = []  # Button sequence ["A", "B", "X", "Y"]
var skill_tier: int = 1  # Skill tier (1-3)

## Internal state
enum Phase { CHARGING, INPUTTING, COMPLETE }
var current_phase: Phase = Phase.CHARGING
var focus_level: int = 0  # 0-3
var charge_time: float = 0.0
var sequence_index: int = 0
var input_timeout: float = 5.0  # Time limit for sequence input
var input_timer: float = 0.0
var misclick_count: int = 0

## Visual elements
var title_label: Label
var instruction_label: Label
var focus_bar: ProgressBar
var focus_level_label: Label
var party_icon: ColorRect
var aura_effect: ColorRect
var sequence_display: HBoxContainer
var timer_bar: ProgressBar

## Button mapping
const BUTTON_MAP = {
	KEY_SPACE: "A",
	KEY_COMMA: "B",
	KEY_PERIOD: "Y",
	KEY_SLASH: "X"
}

## Focus charge speeds (seconds per level)
const BASE_CHARGE_TIME_PER_LEVEL: float = 0.8
var charge_time_per_level: float = 0.8

func _setup_minigame() -> void:
	base_duration = 10.0
	current_duration = base_duration

	# Calculate charge speed based on Focus stat
	charge_time_per_level = BASE_CHARGE_TIME_PER_LEVEL / (1.0 + (focus_stat * 0.1))
	print("[SkillMinigame] Charge time per level: %.2fs (Focus: %d)" % [charge_time_per_level, focus_stat])

	# Title
	title_label = Label.new()
	title_label.text = "SKILL!"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 32)
	content_container.add_child(title_label)

	# Party icon with aura
	var icon_container = CenterContainer.new()
	content_container.add_child(icon_container)

	party_icon = ColorRect.new()
	party_icon.custom_minimum_size = Vector2(100, 100)
	party_icon.color = Color(0.3, 0.6, 0.8, 1.0)
	icon_container.add_child(party_icon)

	# Aura effect (grows with focus level)
	aura_effect = ColorRect.new()
	aura_effect.custom_minimum_size = Vector2(100, 100)
	aura_effect.color = Color(0.8, 0.9, 1.0, 0.0)  # Start transparent
	aura_effect.position = Vector2.ZERO
	party_icon.add_child(aura_effect)

	# Focus bar
	focus_bar = ProgressBar.new()
	focus_bar.max_value = 3.0
	focus_bar.value = 0.0
	focus_bar.show_percentage = false
	focus_bar.custom_minimum_size = Vector2(300, 30)
	var bar_container = CenterContainer.new()
	bar_container.add_child(focus_bar)
	content_container.add_child(bar_container)

	# Focus level label
	focus_level_label = Label.new()
	focus_level_label.text = "Focus Level: 0 | Hold SPACE to charge!"
	focus_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	focus_level_label.add_theme_font_size_override("font_size", 20)
	content_container.add_child(focus_level_label)

	# Sequence display (hidden initially)
	sequence_display = HBoxContainer.new()
	sequence_display.alignment = BoxContainer.ALIGNMENT_CENTER
	sequence_display.visible = false
	content_container.add_child(sequence_display)

	# Timer bar (for sequence input phase)
	timer_bar = ProgressBar.new()
	timer_bar.max_value = input_timeout
	timer_bar.value = input_timeout
	timer_bar.show_percentage = false
	timer_bar.custom_minimum_size = Vector2(300, 20)
	timer_bar.visible = false
	var timer_container = CenterContainer.new()
	timer_container.add_child(timer_bar)
	content_container.add_child(timer_container)

	# Instructions
	instruction_label = Label.new()
	instruction_label.text = "Release to start casting!"
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.add_theme_font_size_override("font_size", 16)
	content_container.add_child(instruction_label)

func _start_minigame() -> void:
	print("[SkillMinigame] Starting - Focus: %d, Tier: %d, Sequence: %s" % [focus_stat, skill_tier, str(skill_sequence)])
	current_phase = Phase.CHARGING
	_setup_sequence_display()

func _setup_sequence_display() -> void:
	"""Pre-create sequence UI buttons"""
	for i in range(skill_sequence.size()):
		var btn_label = Label.new()
		btn_label.text = "?"
		btn_label.add_theme_font_size_override("font_size", 24)
		btn_label.modulate = Color(0.5, 0.5, 0.5, 1.0)  # Grayed out
		sequence_display.add_child(btn_label)

func _process(delta: float) -> void:
	match current_phase:
		Phase.CHARGING:
			_process_charging(delta)
		Phase.INPUTTING:
			_process_inputting(delta)

func _process_charging(delta: float) -> void:
	# Check if Space is held
	if Input.is_key_pressed(KEY_SPACE):
		charge_time += delta

		# Calculate focus level
		var new_level = min(3, int(charge_time / charge_time_per_level))
		if new_level != focus_level:
			focus_level = new_level
			_update_focus_visuals()

		focus_bar.value = charge_time / charge_time_per_level

	# Check if Space was released
	if Input.is_action_just_released("ui_accept") or (not Input.is_key_pressed(KEY_SPACE) and charge_time > 0):
		_start_input_phase()

func _update_focus_visuals() -> void:
	"""Update aura effect based on focus level"""
	focus_level_label.text = "Focus Level: %d" % focus_level

	# Update aura
	match focus_level:
		0:
			aura_effect.color = Color(0.8, 0.9, 1.0, 0.0)
		1:
			aura_effect.color = Color(0.8, 0.9, 1.0, 0.3)
			aura_effect.custom_minimum_size = Vector2(110, 110)
		2:
			aura_effect.color = Color(0.7, 0.9, 1.0, 0.5)
			aura_effect.custom_minimum_size = Vector2(120, 120)
		3:
			aura_effect.color = Color(0.5, 1.0, 1.0, 0.7)
			aura_effect.custom_minimum_size = Vector2(130, 130)

	# Center aura
	var offset = (aura_effect.custom_minimum_size.x - 100) / 2.0
	aura_effect.position = Vector2(-offset, -offset)

func _start_input_phase() -> void:
	"""Transition to button sequence input phase"""
	print("[SkillMinigame] Starting input phase - Focus Level: %d" % focus_level)
	current_phase = Phase.INPUTTING
	sequence_index = 0
	input_timer = input_timeout

	# Hide charging UI
	focus_bar.visible = false
	focus_level_label.visible = false

	# Show sequence UI
	sequence_display.visible = true
	timer_bar.visible = true

	instruction_label.text = "Input the sequence!"
	_update_sequence_display()

func _process_inputting(delta: float) -> void:
	# Update timer
	input_timer -= delta
	timer_bar.value = input_timer

	if input_timer <= 0:
		# Timeout!
		_finish_minigame_incomplete()
		return

	# Check for button input
	for key in BUTTON_MAP.keys():
		if Input.is_key_pressed(key):
			_on_button_input(BUTTON_MAP[key])
			break

func _on_button_input(button: String) -> void:
	"""Handle button press during input phase"""
	var expected_button = skill_sequence[sequence_index]

	if button == expected_button:
		# Correct!
		print("[SkillMinigame] Correct input: %s" % button)
		sequence_index += 1
		_update_sequence_display()

		# Check if sequence complete
		if sequence_index >= skill_sequence.size():
			_finish_minigame_success()
	else:
		# Wrong button! Restart sequence and drop focus
		print("[SkillMinigame] Wrong input: %s (expected %s)" % [button, expected_button])
		misclick_count += 1
		focus_level = max(0, focus_level - 1)
		sequence_index = 0
		_update_focus_visuals()
		_update_sequence_display()

		instruction_label.text = "Misclick! Restarting sequence... Focus: %d" % focus_level

	# Small delay to prevent double-input
	await get_tree().create_timer(0.2).timeout

func _update_sequence_display() -> void:
	"""Update sequence display to show progress"""
	for i in range(sequence_display.get_child_count()):
		var label = sequence_display.get_child(i) as Label
		if i < sequence_index:
			# Completed
			label.text = skill_sequence[i]
			label.modulate = Color(0.0, 1.0, 0.0, 1.0)
		elif i == sequence_index:
			# Current
			label.text = skill_sequence[i]
			label.modulate = Color(1.0, 1.0, 0.0, 1.0)
		else:
			# Future
			label.text = "?"
			label.modulate = Color(0.5, 0.5, 0.5, 1.0)

func _finish_minigame_success() -> void:
	"""Complete minigame successfully"""
	print("[SkillMinigame] Success! Focus: %d, Misclicks: %d" % [focus_level, misclick_count])

	instruction_label.text = "Success! Focus Level: %d" % focus_level

	await get_tree().create_timer(0.5).timeout

	# Calculate bonuses
	var damage_modifier = 1.0
	var mp_modifier = 1.0

	match focus_level:
		0:
			damage_modifier = 1.0
			mp_modifier = 1.0
		1:
			damage_modifier = 1.05
			mp_modifier = 1.0
		2:
			damage_modifier = 1.1
			mp_modifier = 1.0
		3:
			damage_modifier = 1.1
			mp_modifier = 0.9  # Save 10 MP

	var result = {
		"success": true,
		"grade": "focus_%d" % focus_level,
		"damage_modifier": damage_modifier,
		"is_crit": false,
		"mp_modifier": mp_modifier,
		"tier_downgrade": 0,
		"focus_level": focus_level
	}

	_complete_minigame(result)

func _finish_minigame_incomplete() -> void:
	"""Complete minigame with timeout/failure"""
	print("[SkillMinigame] Incomplete! Sequence progress: %d/%d" % [sequence_index, skill_sequence.size()])

	instruction_label.text = "Time's up!"

	await get_tree().create_timer(0.5).timeout

	# Determine tier downgrade based on how much was completed
	var completion_ratio = float(sequence_index) / float(skill_sequence.size())
	var tier_downgrade = 0

	if completion_ratio < 0.33:
		# Less than 1/3 done = drop 2 tiers
		tier_downgrade = 2
	elif completion_ratio < 0.66:
		# Less than 2/3 done = drop 1 tier
		tier_downgrade = 1
	# else: completed enough for current tier

	var result = {
		"success": false,
		"grade": "incomplete",
		"damage_modifier": 0.9,  # 10% penalty
		"is_crit": false,
		"mp_modifier": 1.1,  # 10% more MP
		"tier_downgrade": tier_downgrade,
		"focus_level": 0
	}

	_complete_minigame(result)
