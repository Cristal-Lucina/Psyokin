extends BaseMinigame
class_name SkillMinigame

## SkillMinigame - Focus charging + button sequence for skills
## Phase 1: Hold button to charge focus (faster with higher Focus stat)
## Phase 2: Input button sequence correctly

## Configuration
var focus_stat: int = 1  # Focus stat value (affects charge speed)
var skill_sequence: Array = []  # Button sequence ["A", "B", "X", "Y"]
var skill_tier: int = 1  # Skill tier (1-3)
var mind_type: String = "none"  # Mind type for color (fire, water, earth, air, data, void, omega)

## Internal state
enum Phase { CHARGING, INPUTTING, COMPLETE }
var current_phase: Phase = Phase.CHARGING
var focus_level: int = 0  # 0-3
var charge_time: float = 0.0
var sequence_index: int = 0
var input_timeout: float = 5.0  # Time limit for sequence input
var input_timer: float = 0.0
var misclick_count: int = 0
var has_started_charging: bool = false  # Track if player has pressed Space yet
var overall_timer: float = 0.0  # Overall countdown timer
var max_overall_time: float = 3.0  # Total time for entire minigame (reduced to 3 seconds)
var last_input_button: String = ""  # Track last button to prevent double-input
var minigame_complete: bool = false  # Lock out all input when complete

## Visual elements
var title_label: Label
var instruction_label: Label
var focus_bar: ProgressBar
var focus_level_label: Label
var party_icon: Control  # Changed to Control for custom drawing
var focus_number_label: Label  # Focus number in center of circle
var sequence_display: HBoxContainer
var timer_bar: ProgressBar  # For input phase
var overall_timer_bar: ProgressBar  # For entire minigame

## Number drop animation
var is_number_dropping: bool = false
var drop_offset: float = 0.0
var drop_velocity: float = 0.0
var drop_gravity: float = 800.0  # Pixels per second squared

## Button mapping (InputManager action strings to button labels)
## Using InputManager action strings for proper controller support
## These match the face buttons on Xbox/PlayStation controllers
const BUTTON_MAP = {
	"menu_accept": "A",      # A button (Xbox A / PS Cross)
	"battle_defend": "X",    # X button (Xbox X / PS Square)
	"battle_attack": "B",    # B button (Xbox B / PS Circle)
	"battle_skill": "Y"      # Y button (Xbox Y / PS Triangle)
}

## Focus charge speeds (seconds per level)
const BASE_CHARGE_TIME_PER_LEVEL: float = 0.8
var charge_time_per_level: float = 0.8

## Status effect charge halt (for poison/burned)
var has_halt_status: bool = false
var is_charge_halted: bool = false
var halt_timer: float = 0.0
var next_halt_time: float = 0.0
var was_space_pressed: bool = false  # Track key state for halt recovery

## Mind type colors
func _get_mind_type_color(type: String) -> Color:
	"""Get color for mind type"""
	match type.to_lower():
		"fire":
			return Color(1.0, 0.3, 0.1, 1.0)  # Bright orange-red
		"water":
			return Color(0.2, 0.5, 1.0, 1.0)  # Blue
		"earth":
			return Color(0.6, 0.4, 0.2, 1.0)  # Brown/tan
		"air":
			return Color(0.8, 1.0, 0.9, 1.0)  # Light cyan/white
		"data":
			return Color(0.3, 1.0, 0.3, 1.0)  # Bright green
		"void":
			return Color(0.5, 0.2, 0.6, 1.0)  # Purple
		"omega":
			return Color(1.0, 0.9, 0.2, 1.0)  # Golden yellow
		_:
			return Color(0.5, 0.5, 0.5, 1.0)  # Gray for unknown

func _draw_party_icon() -> void:
	"""Draw the party icon as a circle with mind type color"""
	var center = Vector2(60, 60)  # Center of 120x120 control
	var base_radius = 50.0

	# Increase size based on focus level
	var radius = base_radius + (focus_level * 5.0)

	# Get color based on mind type
	var base_color = _get_mind_type_color(mind_type)

	# Draw outer glow (increases with focus level)
	if focus_level > 0:
		var glow_alpha = 0.2 + (focus_level * 0.15)
		var glow_radius = radius + 10.0 + (focus_level * 3.0)
		party_icon.draw_circle(center, glow_radius, Color(base_color.r, base_color.g, base_color.b, glow_alpha))

	# Draw main circle
	party_icon.draw_circle(center, radius, base_color)

	# Draw highlight (gives it dimension)
	var highlight_offset = Vector2(-radius * 0.3, -radius * 0.3)
	var highlight_radius = radius * 0.4
	var highlight_color = Color(1, 1, 1, 0.3)
	party_icon.draw_circle(center + highlight_offset, highlight_radius, highlight_color)

func _setup_minigame() -> void:
	base_duration = 10.0
	current_duration = base_duration

	# Calculate charge speed based on Focus stat
	# Each focus level gives 15% speed increase (scales well for 10 levels)
	var speed_multiplier = 1.0 + (focus_stat * 0.15)
	charge_time_per_level = BASE_CHARGE_TIME_PER_LEVEL / speed_multiplier
	print("[SkillMinigame] Charge time per level: %.2fs (Focus: %d, Speed: %.0f%%)" % [charge_time_per_level, focus_stat, speed_multiplier * 100])

	# Check for halt-inducing status effects
	has_halt_status = status_effects.has("burn") or status_effects.has("poison") or status_effects.has("sleep")
	if has_halt_status:
		print("[SkillMinigame] Halt status detected: %s" % str(status_effects))
		# Schedule first halt at a random time (0.5 to 1.5 seconds)
		next_halt_time = randf_range(0.5, 1.5)

	# Title (show focus stat for debugging)
	title_label = Label.new()
	title_label.text = "SKILL! (Focus: %d - %d%% Speed)" % [focus_stat, int(speed_multiplier * 100)]
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 28)
	content_container.add_child(title_label)

	# Overall timer bar (starts when Space is first pressed)
	overall_timer_bar = ProgressBar.new()
	overall_timer_bar.max_value = max_overall_time
	overall_timer_bar.value = max_overall_time
	overall_timer_bar.show_percentage = false
	overall_timer_bar.custom_minimum_size = Vector2(300, 15)
	var overall_timer_container = CenterContainer.new()
	overall_timer_container.add_child(overall_timer_bar)
	content_container.add_child(overall_timer_container)

	# Party icon (circle) with focus number
	var icon_container = CenterContainer.new()
	content_container.add_child(icon_container)

	party_icon = Control.new()
	party_icon.custom_minimum_size = Vector2(120, 120)
	party_icon.draw.connect(_draw_party_icon)
	icon_container.add_child(party_icon)

	# Focus number label in center of circle
	focus_number_label = Label.new()
	focus_number_label.text = "0"
	focus_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	focus_number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	focus_number_label.add_theme_font_size_override("font_size", 48)
	focus_number_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	focus_number_label.position = Vector2(0, 0)
	focus_number_label.size = Vector2(120, 120)
	party_icon.add_child(focus_number_label)

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
	focus_level_label.text = "Focus Level: 0 | Hold A (Accept) to charge!"
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
	instruction_label.text = "Release A (Accept) to start casting!"
	instruction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instruction_label.add_theme_font_size_override("font_size", 16)
	content_container.add_child(instruction_label)

func _start_minigame() -> void:
	print("[SkillMinigame] Starting - Focus: %d, Tier: %d, Sequence: %s" % [focus_stat, skill_tier, str(skill_sequence)])
	current_phase = Phase.CHARGING
	overall_timer = max_overall_time  # Initialize timer (will start counting when Space is pressed)
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
	# Call parent to update status effect animations
	super._process(delta)

	# Stop all processing if minigame is complete
	if minigame_complete:
		return

	# Update number drop animation
	if is_number_dropping:
		drop_velocity += drop_gravity * delta
		drop_offset += drop_velocity * delta

		# Update label position
		if focus_number_label:
			focus_number_label.position.y = drop_offset

		# Stop dropping after falling off screen
		if drop_offset > 200:
			is_number_dropping = false
			drop_offset = 0.0
			drop_velocity = 0.0
			if focus_number_label:
				focus_number_label.position.y = 0

	match current_phase:
		Phase.CHARGING:
			_process_charging(delta)
		Phase.INPUTTING:
			_process_inputting(delta)

func _process_charging(delta: float) -> void:
	# Update halt timer if status effect is active
	if has_halt_status and not is_charge_halted:
		halt_timer += delta
		if halt_timer >= next_halt_time:
			# Trigger halt!
			is_charge_halted = true
			focus_level_label.text = "INTERRUPTED! Click again to continue!"
			focus_level_label.modulate = Color(1.0, 0.3, 0.3, 1.0)
			print("[SkillMinigame] Charge halted at %.2fs" % halt_timer)

	# Track Accept button state (A button / Space)
	var space_is_pressed = aInputManager.is_action_pressed(aInputManager.ACTION_ACCEPT)

	# Check if button is held
	if space_is_pressed:
		# Start the timer on first press
		if not has_started_charging:
			has_started_charging = true
			print("[SkillMinigame] Timer started!")

		# If halted, don't charge until player releases and presses again
		if is_charge_halted:
			# Check if this is a new press (was released before)
			if not was_space_pressed:
				# Player pressed again! Resume charging
				is_charge_halted = false
				focus_level_label.text = "Focus Level: %d" % focus_level
				focus_level_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
				# Schedule next halt
				halt_timer = 0.0
				next_halt_time = randf_range(0.8, 2.0)
				print("[SkillMinigame] Charging resumed!")
		else:
			# Normal charging
			charge_time += delta

			# Calculate focus level
			var new_level = min(3, int(charge_time / charge_time_per_level))
			if new_level != focus_level:
				focus_level = new_level
				_update_focus_visuals()
				print("[SkillMinigame] Focus level %d reached at %.2fs (charge_time_per_level: %.2fs)" % [focus_level, charge_time, charge_time_per_level])

			focus_bar.value = charge_time / charge_time_per_level

	was_space_pressed = space_is_pressed

	# Update overall timer (only if charging has started)
	if has_started_charging:
		overall_timer -= delta
		overall_timer_bar.value = overall_timer

		# Check for timeout
		if overall_timer <= 0:
			print("[SkillMinigame] Overall timeout during charging!")
			_finish_minigame_incomplete()
			return

	# Check if button was released
	if aInputManager.is_action_just_released(aInputManager.ACTION_ACCEPT) and charge_time > 0:
		_start_input_phase()

func _update_focus_visuals() -> void:
	"""Update focus number and redraw circle"""
	focus_level_label.text = "Focus Level: %d" % focus_level
	focus_number_label.text = str(focus_level)

	# Reset drop animation when focus increases
	drop_offset = 0.0
	drop_velocity = 0.0
	is_number_dropping = false

	# Redraw the circle with new focus level (affects size/glow)
	if party_icon:
		party_icon.queue_redraw()

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
	# Update overall timer
	overall_timer -= delta
	overall_timer_bar.value = overall_timer

	# Update input phase timer
	input_timer -= delta
	timer_bar.value = input_timer

	# Check for overall timeout
	if overall_timer <= 0:
		print("[SkillMinigame] Overall timeout during input!")
		_finish_minigame_incomplete()
		return

	if input_timer <= 0:
		# Phase timeout!
		_finish_minigame_incomplete()
		return

	# Check for button input (single press detection)
	var current_button = ""
	for action in BUTTON_MAP.keys():
		if aInputManager.is_action_pressed(action):
			current_button = BUTTON_MAP[action]
			break

	# Only process if a button is pressed AND it's different from last frame
	if current_button != "" and current_button != last_input_button:
		_on_button_input(current_button)

	# Update last button state
	last_input_button = current_button

func _on_button_input(button: String) -> void:
	"""Handle button press during input phase"""
	# Safety check: don't process if complete or out of bounds
	if minigame_complete or sequence_index >= skill_sequence.size():
		return

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

		# Trigger number drop animation
		is_number_dropping = true
		drop_offset = 0.0
		drop_velocity = 0.0

		_update_focus_visuals()
		_update_sequence_display()

		instruction_label.text = "Misclick! Restarting sequence... Focus: %d" % focus_level

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

	# Lock out all input immediately
	minigame_complete = true
	current_phase = Phase.COMPLETE

	instruction_label.text = "Great! Focus Level: %d" % focus_level
	title_label.text = "GREAT!"

	await get_tree().create_timer(1.0).timeout

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

	# Lock out all input immediately
	minigame_complete = true
	current_phase = Phase.COMPLETE

	instruction_label.text = "Skill cast anyway..."
	title_label.text = "OK"

	await get_tree().create_timer(1.0).timeout

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
