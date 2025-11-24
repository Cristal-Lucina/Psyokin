extends BaseMinigame
class_name SkillMinigame

## SkillMinigame - Button sequence timing minigame for skills
## Press the correct button sequence within the time limit
## Correct sequence = 100% damage (Tier 1)
## Extended sequences unlock higher tiers: Tier 2 (110%), Tier 3 (130%)

## Configuration
var focus_stat: int = 1  # Focus stat (currently unused)
var skill_sequence: Array = []  # Tier 1 button sequence ["A", "B", "X", "Y"]
var tier_2_sequence: Array = ["Y", "Y", "Y"]  # Tier 2 hidden sequence (for testing)
var tier_3_sequence: Array = ["Y", "Y", "Y"]  # Tier 3 hidden sequence (for testing)
var skill_tier: int = 1  # Skill tier (1-3)
var mind_type: String = "fire"  # Mind type for color

## Internal state
enum Phase { FADE_IN, ACTIVE, SHOWING_RESULT, COMPLETE }
var current_phase: Phase = Phase.FADE_IN

## Sequence tracking
var sequence_index: int = 0  # Current position in full sequence
var tier_1_length: int = 0  # Length of tier 1 sequence
var tier_2_length: int = 0  # Length of tier 2 sequence (tier_1 + tier_2)
var tier_3_length: int = 0  # Length of tier 3 sequence (tier_1 + tier_2 + tier_3)
var full_sequence: Array = []  # Complete sequence with all tiers
var time_limit: float = 4.0  # Extended time for potential tier 2/3
var timer: float = 0.0
var failed: bool = false

## Result tracking
var final_damage_modifier: float = 1.0
var final_tier: int = 1
var result_text: String = "GOOD"

## Visual elements
var circle_canvas: Control  # For drawing the filling circle
var sequence_container: HBoxContainer  # Shows button sequence
var timer_bar: ProgressBar  # Horizontal timer bar
var result_label: Label
var fade_timer: float = 0.0
var fade_duration: float = 1.0

## Circle fill animation
var fill_progress: float = 0.0  # 0.0 = empty, 1.0 = full
var circle_radius: float = 37.5  # Same size as AttackMinigame button

## Input locked during fade in/out
var input_locked: bool = true

## Button mapping for display
const BUTTON_ICONS = {
	"A": "accept",
	"B": "back",
	"X": "special_1",
	"Y": "special_2"
}

func _ready() -> void:
	# Override parent to customize background
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_STOP

	_setup_transparent_visuals()
	_apply_status_effects()
	_setup_minigame()

	# Start the minigame
	await get_tree().process_frame
	_start_minigame()

func _setup_transparent_visuals() -> void:
	"""Create transparent background - only UI elements visible"""
	# NO dimmed background - completely transparent
	background_dim = ColorRect.new()
	background_dim.color = Color(0, 0, 0, 0.0)  # Fully transparent
	background_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	background_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background_dim)

	# Central panel - also transparent
	overlay_panel = PanelContainer.new()
	overlay_panel.custom_minimum_size = get_viewport_rect().size * 0.1875  # Same as attack minigame
	var viewport_size = get_viewport_rect().size
	overlay_panel.position = Vector2(viewport_size.x * 0.40625, viewport_size.y * 0.25 - 100)  # Same position
	overlay_panel.z_index = 101

	# Make panel transparent
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0, 0, 0, 0.0)  # Fully transparent
	panel_style.border_width_left = 0
	panel_style.border_width_right = 0
	panel_style.border_width_top = 0
	panel_style.border_width_bottom = 0
	overlay_panel.add_theme_stylebox_override("panel", panel_style)

	add_child(overlay_panel)

	# Content container
	content_container = VBoxContainer.new()
	content_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_container.add_theme_constant_override("separation", 10)
	content_container.z_index = 102  # Above overlay_panel
	overlay_panel.add_child(content_container)

func _setup_minigame() -> void:
	base_duration = 10.0  # Maximum time allowed
	current_duration = base_duration

	# Build full sequence from all tiers
	full_sequence = skill_sequence.duplicate()
	tier_1_length = skill_sequence.size()
	tier_2_length = tier_1_length + tier_2_sequence.size()
	tier_3_length = tier_2_length + tier_3_sequence.size()

	full_sequence.append_array(tier_2_sequence)
	full_sequence.append_array(tier_3_sequence)

	print("[SkillMinigame] _setup_minigame called")
	print("[SkillMinigame] Tier 1 sequence (visible): %s" % str(skill_sequence))
	print("[SkillMinigame] Tier 2 sequence (hidden): %s" % str(tier_2_sequence))
	print("[SkillMinigame] Tier 3 sequence (hidden): %s" % str(tier_3_sequence))
	print("[SkillMinigame] Full sequence: %s" % str(full_sequence))
	print("[SkillMinigame] Tier lengths - T1: %d, T2: %d, T3: %d" % [tier_1_length, tier_2_length, tier_3_length])
	print("[SkillMinigame] mind_type = %s" % mind_type)

	# Neon-kawaii colors
	const COLOR_MILK_WHITE = Color(0.96, 0.97, 0.98)

	# Clear the default content container
	for child in content_container.get_children():
		child.queue_free()

	# Result label (placed at top)
	result_label = Label.new()
	result_label.text = ""
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 60)
	result_label.add_theme_color_override("font_color", COLOR_MILK_WHITE)
	result_label.add_theme_constant_override("outline_size", 8)
	result_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	result_label.modulate.a = 0.0  # Hidden initially

	var result_container = CenterContainer.new()
	result_container.add_child(result_label)
	content_container.add_child(result_container)

	# Create a centered container for the circle
	var center_container = CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_container.add_child(center_container)

	# Create canvas for drawing filling circle
	circle_canvas = Control.new()
	circle_canvas.custom_minimum_size = Vector2(188, 188)  # Same as attack minigame
	circle_canvas.draw.connect(_draw_filling_circle)
	center_container.add_child(circle_canvas)

	# Button sequence display (positioned independently, moved down 130px)
	sequence_container = HBoxContainer.new()
	sequence_container.add_theme_constant_override("separation", 10)
	var sequence_center = CenterContainer.new()
	sequence_center.add_child(sequence_container)

	# Position manually with absolute positioning - add to root (self), not overlay_panel
	sequence_center.set_anchors_preset(Control.PRESET_CENTER_TOP)
	sequence_center.position.x = -90  # Move 90px left from center (50 + 40)
	sequence_center.position.y = 350  # Move down 350px from top (230 + 120)
	sequence_center.z_index = 1000  # Ensure appears on top

	# Add directly to self (root control) to avoid any layout interference
	add_child(sequence_center)

	# Create ONLY 3 button slots that will be reused for all tiers
	# Start with Tier 1 buttons, then replace with Tier 2, then Tier 3
	var icon_layout = get_node_or_null("/root/aControllerIconLayout")
	print("[SkillMinigame] aControllerIconLayout found: %s" % str(icon_layout != null))

	# Create 3 button slots for tier 1 (initial display)
	print("[SkillMinigame] Creating 3 button slots (starting with Tier 1)")
	_create_tier_buttons(0, skill_sequence, icon_layout, false)  # Tier 1 - show actual buttons

	print("[SkillMinigame] Sequence container has %d children" % sequence_container.get_child_count())

	# Timer bar (horizontal, below sequence) - styled like CaptureMinigame
	timer_bar = ProgressBar.new()
	timer_bar.max_value = 1.0
	timer_bar.value = 1.0
	timer_bar.show_percentage = false
	timer_bar.custom_minimum_size = Vector2(200, 20)  # Taller like CaptureMinigame

	# Style the timer bar - match CaptureMinigame style
	var timer_style_bg = StyleBoxFlat.new()
	timer_style_bg.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	timer_style_bg.corner_radius_top_left = 4
	timer_style_bg.corner_radius_top_right = 4
	timer_style_bg.corner_radius_bottom_left = 4
	timer_style_bg.corner_radius_bottom_right = 4
	timer_bar.add_theme_stylebox_override("background", timer_style_bg)

	var timer_style_fill = StyleBoxFlat.new()
	timer_style_fill.bg_color = Color(1.0, 0.29, 0.85)  # Bubble magenta
	timer_style_fill.corner_radius_top_left = 4
	timer_style_fill.corner_radius_top_right = 4
	timer_style_fill.corner_radius_bottom_left = 4
	timer_style_fill.corner_radius_bottom_right = 4
	timer_bar.add_theme_stylebox_override("fill", timer_style_fill)

	var timer_center = CenterContainer.new()
	timer_center.add_child(timer_bar)
	content_container.add_child(timer_center)

	print("[SkillMinigame] Setup complete - button sequence minigame")

func _start_minigame() -> void:
	print("[SkillMinigame] Starting button sequence minigame")
	print("[SkillMinigame] Tier 1 (visible): %s" % str(skill_sequence))
	print("[SkillMinigame] Full sequence (T1+T2+T3): %s" % str(full_sequence))
	print("[SkillMinigame] Time limit: %.1f seconds for all tiers" % time_limit)
	current_phase = Phase.FADE_IN
	sequence_index = 0
	fill_progress = 0.0
	timer = 0.0
	failed = false
	fade_timer = 0.0
	input_locked = true

	# Fade in the overlay
	overlay_panel.modulate.a = 0.0

func _process(delta: float) -> void:
	super._process(delta)

	match current_phase:
		Phase.FADE_IN:
			_process_fade_in(delta)
		Phase.ACTIVE:
			_process_active(delta)
		Phase.SHOWING_RESULT:
			_process_showing_result(delta)

func _process_fade_in(delta: float) -> void:
	"""Fade in before starting"""
	fade_timer += delta
	var alpha = min(fade_timer / fade_duration, 1.0)
	overlay_panel.modulate.a = alpha

	circle_canvas.queue_redraw()

	# After 1 second, start the active phase
	if fade_timer >= fade_duration:
		current_phase = Phase.ACTIVE
		input_locked = false
		timer = 0.0
		print("[SkillMinigame] Sequence input active - press buttons!")

func _process_active(delta: float) -> void:
	"""Player inputting button sequence"""
	# Update timer
	timer += delta
	var time_remaining = time_limit - timer
	timer_bar.value = time_remaining / time_limit

	# Redraw circle
	circle_canvas.queue_redraw()

	# Check for button inputs
	if not input_locked and not failed:
		_check_button_input()

	# Time's up!
	if timer >= time_limit:
		# Determine what tier was achieved based on how far they got
		_finish_sequence(false)  # Timeout

func _check_button_input() -> void:
	"""Check if correct button was pressed"""
	# Check if we've completed all tiers
	if sequence_index >= full_sequence.size():
		return

	var expected_button = full_sequence[sequence_index]
	var pressed = false
	var correct = false

	# Map expected button to action
	var action_to_check = ""
	match expected_button:
		"A":
			action_to_check = aInputManager.ACTION_ACCEPT
		"B":
			action_to_check = aInputManager.ACTION_BACK
		"X":
			action_to_check = aInputManager.ACTION_DEFEND
		"Y":
			action_to_check = aInputManager.ACTION_SKILL

	# Check if the correct button was pressed
	if action_to_check != "" and aInputManager.is_action_just_pressed(action_to_check):
		pressed = true
		correct = true

		# Determine which tier we're in
		var tier_name = "Tier 1"
		if sequence_index >= tier_2_length:
			tier_name = "Tier 3"
		elif sequence_index >= tier_1_length:
			tier_name = "Tier 2"

		print("[SkillMinigame] %s - Correct button %s pressed! (%d/%d)" % [tier_name, expected_button, sequence_index + 1, full_sequence.size()])

		# Calculate which button slot to highlight (0-2, since we only have 3 slots)
		var slot_index = sequence_index % 3

		if slot_index < sequence_container.get_child_count():
			var button_slot = sequence_container.get_child(slot_index)

			# Check if this is a "?" placeholder that needs revealing
			if button_slot.has_meta("hidden_texture"):
				# Reveal the placeholder by replacing it with actual icon
				var icon_texture = button_slot.get_meta("hidden_texture")
				var button_name = button_slot.get_meta("button_name")

				# Remove the "?" placeholder
				for child in button_slot.get_children():
					child.queue_free()

				# Create the actual button icon
				var icon_rect = TextureRect.new()
				icon_rect.texture = icon_texture
				icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
				icon_rect.custom_minimum_size = Vector2(50, 50)
				icon_rect.z_index = 1001

				# Immediately highlight with mind color
				var mind_color = _get_mind_type_color()
				mind_color.a = 1.0  # Fully opaque
				icon_rect.modulate = mind_color
				button_slot.add_child(icon_rect)

				print("[SkillMinigame] Revealed and highlighted button %d: ? -> %s" % [slot_index, button_name])
			else:
				# Already revealed - just highlight it
				for child in button_slot.get_children():
					if child is TextureRect:
						var mind_color = _get_mind_type_color()
						mind_color.a = 1.0  # Fully opaque
						child.modulate = mind_color  # Light up with mind type color
						break

		sequence_index += 1
		fill_progress = float(sequence_index) / float(full_sequence.size())

		# Check for tier completions and reveal next tier icons
		if sequence_index == tier_1_length:
			# Just completed Tier 1! Reveal Tier 2 icons
			print("[SkillMinigame] TIER 1 COMPLETE! Revealing Tier 2 buttons...")
			_reveal_tier_icons(tier_1_length, tier_2_length)
		elif sequence_index == tier_2_length:
			# Just completed Tier 2! Reveal Tier 3 icons
			print("[SkillMinigame] TIER 2 COMPLETE! Revealing Tier 3 buttons...")
			_reveal_tier_icons(tier_2_length, tier_3_length)
		elif sequence_index >= tier_3_length:
			# Completed all tiers!
			print("[SkillMinigame] TIER 3 COMPLETE! Maximum damage!")
			_finish_sequence(true)
			return
	else:
		# Check if any wrong button was pressed
		var wrong_pressed = false
		for action in [aInputManager.ACTION_ACCEPT, aInputManager.ACTION_BACK,
					   aInputManager.ACTION_DEFEND, aInputManager.ACTION_SKILL]:
			if action != action_to_check and aInputManager.is_action_just_pressed(action):
				wrong_pressed = true
				break

		if wrong_pressed:
			print("[SkillMinigame] Wrong button pressed! Restarting sequence...")
			_restart_sequence()

func _create_tier_buttons(tier_start_index: int, button_sequence: Array, icon_layout, show_placeholders: bool) -> void:
	"""Create 3 button slots for a tier"""
	for i in range(3):
		var button_name = button_sequence[i]
		var icon_action = BUTTON_ICONS.get(button_name, "accept")

		# Create container for this button position
		var button_slot = Control.new()
		button_slot.custom_minimum_size = Vector2(50, 50)

		if show_placeholders:
			# Show "?" placeholder circle
			var placeholder = Control.new()
			placeholder.custom_minimum_size = Vector2(50, 50)
			placeholder.draw.connect(func():
				var center = Vector2(25, 25)
				var radius = 23.0
				# Draw filled circle background
				placeholder.draw_circle(center, radius, Color(0.2, 0.2, 0.2, 0.6))
				# Draw circle outline
				var points = 64
				for j in range(points):
					var angle_from = (float(j) / points) * TAU
					var angle_to = (float(j + 1) / points) * TAU
					var from = center + Vector2(cos(angle_from), sin(angle_from)) * radius
					var to = center + Vector2(cos(angle_to), sin(angle_to)) * radius
					placeholder.draw_line(from, to, Color(0.6, 0.6, 0.6, 0.7), 2.0)
				# Draw "?" text in center
				var font = ThemeDB.fallback_font
				var font_size = 32
				var text = "?"
				var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
				var text_pos = center - text_size / 2.0
				placeholder.draw_string(font, text_pos, text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0.8, 0.8, 0.8, 0.9))
			)
			button_slot.add_child(placeholder)

			# Store the actual icon texture for later reveal
			if icon_layout:
				var icon_texture = icon_layout.get_button_icon(icon_action)
				if icon_texture:
					button_slot.set_meta("hidden_texture", icon_texture)
					button_slot.set_meta("button_name", button_name)
		else:
			# Show actual button icon
			if icon_layout:
				var icon_texture = icon_layout.get_button_icon(icon_action)
				if icon_texture:
					var icon_rect = TextureRect.new()
					icon_rect.texture = icon_texture
					icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
					icon_rect.custom_minimum_size = Vector2(50, 50)
					icon_rect.modulate = Color(1.0, 1.0, 1.0, 0.7)  # Semi-transparent
					icon_rect.z_index = 1001
					button_slot.add_child(icon_rect)

		sequence_container.add_child(button_slot)

func _reveal_tier_icons(start_index: int, end_index: int) -> void:
	"""Replace all 3 buttons with next tier's buttons"""
	var icon_layout = get_node_or_null("/root/aControllerIconLayout")

	# Determine which tier we're revealing
	var next_tier_sequence: Array
	var tier_name: String
	if start_index == tier_1_length:
		# Revealing tier 2
		next_tier_sequence = tier_2_sequence
		tier_name = "Tier 2"
	else:
		# Revealing tier 3
		next_tier_sequence = tier_3_sequence
		tier_name = "Tier 3"

	print("[SkillMinigame] Replacing buttons with %s placeholders: %s" % [tier_name, str(next_tier_sequence)])

	# Remove all existing button slots
	for child in sequence_container.get_children():
		child.queue_free()

	# Create new button slots with "?" placeholders for the next tier
	_create_tier_buttons(start_index, next_tier_sequence, icon_layout, true)

	print("[SkillMinigame] %s buttons created as placeholders" % tier_name)

func _restart_sequence() -> void:
	"""Reset sequence from beginning - go back to tier 1 buttons"""
	sequence_index = 0
	fill_progress = 0.0

	print("[SkillMinigame] Restarting - replacing buttons with Tier 1")

	# Remove all existing button slots
	for child in sequence_container.get_children():
		child.queue_free()

	# Recreate tier 1 buttons (actual icons, not placeholders)
	var icon_layout = get_node_or_null("/root/aControllerIconLayout")
	_create_tier_buttons(0, skill_sequence, icon_layout, false)

func _finish_sequence(success: bool) -> void:
	"""Sequence complete or failed"""
	input_locked = true
	current_phase = Phase.SHOWING_RESULT

	# Determine tier achieved based on how far the player got
	if sequence_index >= tier_3_length:
		# Completed all 3 tiers!
		final_damage_modifier = 1.3  # Tier 3: 130% damage
		final_tier = 3
		result_text = "GREAT!"
		print("[SkillMinigame] TIER 3 ACHIEVED! 130% damage")
	elif sequence_index >= tier_2_length:
		# Completed tier 1 + tier 2
		final_damage_modifier = 1.1  # Tier 2: 110% damage
		final_tier = 2
		result_text = "GOOD"
		print("[SkillMinigame] TIER 2 ACHIEVED! 110% damage")
	elif sequence_index >= tier_1_length:
		# Completed tier 1
		final_damage_modifier = 1.0  # Tier 1: 100% damage
		final_tier = 1
		result_text = "OK"
		print("[SkillMinigame] TIER 1 ACHIEVED! 100% damage")
	else:
		# Didn't complete tier 1 (timeout or wrong button)
		final_damage_modifier = 0.5  # 50% damage penalty
		final_tier = 0
		result_text = "MISS"
		print("[SkillMinigame] Failed to complete Tier 1! 50% damage")

	# Show result text
	result_label.text = result_text
	result_label.modulate.a = 1.0

	# Start fade out timer
	fade_timer = 0.0

func _process_showing_result(delta: float) -> void:
	"""Show result for a moment, then fade out"""
	fade_timer += delta

	# Show result for 1 second
	if fade_timer >= 1.0:
		# Start fade out
		var fade_out_time = fade_timer - 1.0
		var alpha = 1.0 - (fade_out_time / fade_duration)
		overlay_panel.modulate.a = max(alpha, 0.0)

		# Complete after fade out
		if fade_out_time >= fade_duration:
			_finish_minigame()

func _draw_filling_circle() -> void:
	"""Draw the circle that fills with mind type color"""
	var canvas_size = circle_canvas.size
	var center = canvas_size / 2.0

	# Draw outer circle border
	_draw_circle_outline(center, circle_radius, Color(0.5, 0.5, 0.5, 0.8), 2.0)

	# Fill circle based on progress
	if fill_progress > 0.0:
		var fill_color = _get_mind_type_color()
		fill_color.a = 0.6  # Semi-transparent
		_draw_filled_circle(center, circle_radius * fill_progress, fill_color)

func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	"""Helper to draw a circle outline"""
	var points = 64
	for i in range(points):
		var angle_from = (float(i) / points) * TAU
		var angle_to = (float(i + 1) / points) * TAU
		var point_from = center + Vector2(cos(angle_from), sin(angle_from)) * radius
		var point_to = center + Vector2(cos(angle_to), sin(angle_to)) * radius
		circle_canvas.draw_line(point_from, point_to, color, width)

func _draw_filled_circle(center: Vector2, radius: float, color: Color) -> void:
	"""Helper to draw a filled circle"""
	var points = 64
	var points_array = PackedVector2Array()
	points_array.append(center)

	for i in range(points + 1):
		var angle = (float(i) / points) * TAU
		var point = center + Vector2(cos(angle), sin(angle)) * radius
		points_array.append(point)

	circle_canvas.draw_colored_polygon(points_array, color)

func _get_mind_type_color() -> Color:
	"""Get color for mind type"""
	match mind_type.to_lower():
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

func _finish_minigame() -> void:
	print("[SkillMinigame] Finishing - Tier: %d, Modifier: %.2f" % [final_tier, final_damage_modifier])

	current_phase = Phase.COMPLETE

	var result = {
		"success": true,
		"grade": result_text.to_lower(),
		"damage_modifier": final_damage_modifier,
		"is_crit": false,
		"mp_modifier": 1.0,
		"tier_downgrade": 0,
		"focus_level": final_tier
	}

	_complete_minigame(result)
