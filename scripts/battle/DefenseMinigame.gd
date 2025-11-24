extends BaseMinigame
class_name DefenseMinigame

## DefenseMinigame - Parry-based defense with closing circle and parry battles
## Press the shown button when circle is in parry zone (40-60%) to parry
## Successful parry can lead to parry battles with the enemy

## Emitted when the minigame completes
signal minigame_completed

## Configuration
var defense_stat: int = 1  # Defense stat (currently unused)
var attacker_damage: float = 10.0  # Base damage from attacker

## Internal state
enum Phase { FADE_IN, ACTIVE, PARRY_BATTLE, SHOWING_RESULT, COMPLETE }
var current_phase: Phase = Phase.FADE_IN

## Circle animation
var circle_progress: float = 0.0  # 0.0 = fully open, 1.0 = fully closed
var circle_speed: float = 1.0  # Slower for testing (1.0 second to close)
var circle_max_radius: float = 75.0  # Maximum circle radius
var circle_min_radius: float = 37.5  # Minimum circle radius

## Parry battle tracking
var parry_round: int = 0  # 0 = initial, 1+= counter-parry rounds
var player_parry_min: float = 0.4  # Parry zone minimum (starts at 40%)
var player_parry_max: float = 0.6  # Parry zone maximum (starts at 60%)
var enemy_parry_chance: float = 0.5  # Enemy's chance to counter-parry (starts at 50%)
var is_player_turn: bool = true  # Whose turn is it in parry battle
var waiting_for_enemy: bool = false  # Waiting for enemy to attempt parry
var enemy_wait_timer: float = 0.0  # Timer for enemy decision

## Random button for parry
var parry_button: String = "A"  # Random: A, B, X, or Y
const PARRY_BUTTONS = ["A", "B", "X", "Y"]
const BUTTON_ACTIONS = {
	"A": "accept",
	"B": "back",
	"X": "special_1",
	"Y": "special_2"
}

## Result tracking
var player_attempted_parry: bool = false  # Did player press the parry button?
var final_damage_modifier: float = 1.0  # 0.0 = no damage (parried), 1.0 = normal, 1.3 = penalty for missing
var counter_attack_damage: float = 0.0  # Damage dealt back to enemy (30% of attack damage)
var initiative_bonus: int = 0  # Initiative bonus for next round (10 for successful parry)
var result_text: String = "HIT!"

## Visual elements
var button_icon: TextureRect  # The random button icon
var circle_canvas: Control  # For drawing the circle
var result_label: Label
var battle_label: Label  # Shows "PARRY!" / "COUNTER!" during battles
var fade_timer: float = 0.0
var fade_duration: float = 1.0

## Button icon modulation based on circle progress
var current_button_modulation: Color = Color.WHITE

## Input locked during fade in/out
var input_locked: bool = true

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
	"""Create transparent background - only button and circle visible"""
	# NO dimmed background - completely transparent
	background_dim = ColorRect.new()
	background_dim.color = Color(0, 0, 0, 0.0)  # Fully transparent
	background_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	background_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background_dim)

	# Central panel - also transparent
	overlay_panel = PanelContainer.new()
	overlay_panel.custom_minimum_size = get_viewport_rect().size * 0.1875
	var viewport_size = get_viewport_rect().size
	overlay_panel.position = Vector2(viewport_size.x * 0.40625, viewport_size.y * 0.25 - 100)
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
	overlay_panel.add_child(content_container)

func _setup_minigame() -> void:
	base_duration = 10.0  # Maximum time allowed
	current_duration = base_duration

	# Pick random parry button
	parry_button = PARRY_BUTTONS[randi() % PARRY_BUTTONS.size()]
	print("[DefenseMinigame] Random parry button: %s" % parry_button)

	# Neon-kawaii colors
	const COLOR_MILK_WHITE = Color(0.96, 0.97, 0.98)

	# Clear the default content container
	for child in content_container.get_children():
		child.queue_free()

	# Get the controller icon layout
	var icon_layout = get_node_or_null("/root/aControllerIconLayout")
	if not icon_layout:
		push_error("[DefenseMinigame] aControllerIconLayout not found!")
		return

	# Result label (placed at top, hidden initially)
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

	# Battle label (shows "PARRY!" / "COUNTER!" during battles)
	battle_label = Label.new()
	battle_label.text = ""
	battle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	battle_label.add_theme_font_size_override("font_size", 40)
	battle_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))  # Gold color
	battle_label.add_theme_constant_override("outline_size", 6)
	battle_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	battle_label.modulate.a = 0.0  # Hidden initially

	var battle_container = CenterContainer.new()
	battle_container.add_child(battle_label)
	content_container.add_child(battle_container)

	# Create a centered container for the button and circle
	var center_container = CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_container.add_child(center_container)

	# Create canvas for drawing circle
	circle_canvas = Control.new()
	circle_canvas.custom_minimum_size = Vector2(188, 188)
	circle_canvas.draw.connect(_draw_circle)
	center_container.add_child(circle_canvas)

	# Get random button icon texture
	var button_action = BUTTON_ACTIONS.get(parry_button, "accept")
	var button_texture = icon_layout.get_button_icon(button_action)

	if button_texture:
		# Create button icon (75x75, centered)
		button_icon = TextureRect.new()
		button_icon.texture = button_texture
		button_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		button_icon.custom_minimum_size = Vector2(75, 75)
		button_icon.position = Vector2(56.5, 56.5)  # Center in 188x188 canvas
		button_icon.z_index = 102
		circle_canvas.add_child(button_icon)
		print("[DefenseMinigame] Created button icon for %s" % parry_button)
	else:
		push_error("[DefenseMinigame] Failed to load button icon for %s" % parry_button)

	print("[DefenseMinigame] Setup complete - defense minigame")

func _start_minigame() -> void:
	print("[DefenseMinigame] Starting defense minigame - PARRY!")
	print("[DefenseMinigame] Parry button: %s" % parry_button)
	print("[DefenseMinigame] Parry zone: %.0f%% - %.0f%%" % [player_parry_min * 100, player_parry_max * 100])
	current_phase = Phase.FADE_IN
	circle_progress = 0.0
	fade_timer = 0.0
	input_locked = true

	# Fade in the overlay
	overlay_panel.modulate.a = 0.0

func _process(delta: float) -> void:
	match current_phase:
		Phase.FADE_IN:
			_process_fade_in(delta)
		Phase.ACTIVE:
			_process_active(delta)
		Phase.PARRY_BATTLE:
			_process_parry_battle(delta)
		Phase.SHOWING_RESULT:
			_process_showing_result(delta)
		Phase.COMPLETE:
			pass  # Nothing to do

func _process_fade_in(delta: float) -> void:
	"""Fade in the minigame UI"""
	fade_timer += delta
	var alpha = min(fade_timer / fade_duration, 1.0)
	overlay_panel.modulate.a = alpha

	# After 1 second, start the active phase
	if fade_timer >= fade_duration:
		current_phase = Phase.ACTIVE
		input_locked = false
		print("[DefenseMinigame] Defense active - press %s to parry!" % parry_button)

func _process_active(delta: float) -> void:
	"""Player attempting to parry"""
	# Update circle animation
	circle_progress += circle_speed * delta
	circle_canvas.queue_redraw()

	# Update button color based on zone
	_update_button_color()

	# Check for parry input
	if not input_locked:
		_check_parry_input()

	# Circle fully closed - missed parry
	if circle_progress >= 1.0:
		_miss_parry()

func _process_parry_battle(delta: float) -> void:
	"""Parry battle - waiting for player or enemy to respond"""
	if waiting_for_enemy:
		enemy_wait_timer += delta
		if enemy_wait_timer >= 0.5:  # Enemy decides after 0.5s
			_enemy_parry_attempt()
	else:
		# Player's turn - update circle animation
		circle_progress += circle_speed * delta
		circle_canvas.queue_redraw()
		_update_button_color()

		if not input_locked:
			_check_parry_input()

		# Circle fully closed - player failed to counter
		if circle_progress >= 1.0:
			_lose_parry_battle()

func _check_parry_input() -> void:
	"""Check if player pressed the correct parry button"""
	var action_to_check = ""
	match parry_button:
		"A": action_to_check = aInputManager.ACTION_ACCEPT
		"B": action_to_check = aInputManager.ACTION_BACK
		"X": action_to_check = aInputManager.ACTION_DEFEND
		"Y": action_to_check = aInputManager.ACTION_SKILL

	if action_to_check != "" and aInputManager.is_action_just_pressed(action_to_check):
		# Player attempted the parry!
		player_attempted_parry = true

		# Check if in parry zone
		if circle_progress >= player_parry_min and circle_progress <= player_parry_max:
			_successful_parry()
		else:
			_miss_parry()

func _successful_parry() -> void:
	"""Player successfully parried!"""
	input_locked = true

	if parry_round == 0:
		# Initial parry - enemy might counter
		print("[DefenseMinigame] PARRY SUCCESS! Enemy counter chance: %.0f%%" % (enemy_parry_chance * 100))
		battle_label.text = "PARRY!"
		battle_label.modulate.a = 1.0

		# Check if enemy counters
		waiting_for_enemy = true
		enemy_wait_timer = 0.0
		current_phase = Phase.PARRY_BATTLE
	else:
		# Counter-parry success - enemy might counter again
		print("[DefenseMinigame] COUNTER SUCCESS! Round %d - Enemy counter chance: %.0f%%" % [parry_round, enemy_parry_chance * 100])
		battle_label.text = "COUNTER!"
		battle_label.modulate.a = 1.0

		waiting_for_enemy = true
		enemy_wait_timer = 0.0

func _enemy_parry_attempt() -> void:
	"""Enemy attempts to counter-parry"""
	waiting_for_enemy = false
	var roll = randf()

	print("[DefenseMinigame] Enemy parry attempt - Roll: %.2f, Chance: %.2f" % [roll, enemy_parry_chance])

	if roll < enemy_parry_chance:
		# Enemy successfully parried back!
		print("[DefenseMinigame] Enemy PARRIED BACK! Round %d" % (parry_round + 1))
		parry_round += 1

		# Update parry windows
		_update_parry_windows()

		# Change the button to make it harder!
		_change_parry_button()

		# Player's turn to counter
		circle_progress = 0.0
		input_locked = false
		battle_label.text = "COUNTER!"

		print("[DefenseMinigame] Player counter window: %.0f%% - %.0f%%, New button: %s" % [player_parry_min * 100, player_parry_max * 100, parry_button])
	else:
		# Enemy failed to parry - player wins!
		print("[DefenseMinigame] Enemy FAILED to parry - Player wins battle!")
		_win_parry_battle()

func _update_parry_windows() -> void:
	"""Update parry windows based on round"""
	if parry_round == 1:
		# Round 1: Player gets easier window (35-65%)
		player_parry_min = 0.35
		player_parry_max = 0.65
		enemy_parry_chance = 0.4  # Enemy 40% chance
	elif parry_round == 2:
		# Round 2: Player gets even easier (30-70%)
		player_parry_min = 0.30
		player_parry_max = 0.70
		enemy_parry_chance = 0.3  # Enemy 30% chance
	else:
		# Round 3+: Locked at 30-70% for player, 30% for enemy
		player_parry_min = 0.30
		player_parry_max = 0.70
		enemy_parry_chance = 0.3

func _change_parry_button() -> void:
	"""Change the parry button to a different one (makes counter harder)"""
	var old_button = parry_button

	# Pick a different button
	var available_buttons = []
	for btn in PARRY_BUTTONS:
		if btn != old_button:
			available_buttons.append(btn)

	parry_button = available_buttons[randi() % available_buttons.size()]

	print("[DefenseMinigame] Button changed: %s -> %s" % [old_button, parry_button])

	# Update the button icon
	var icon_layout = get_node_or_null("/root/aControllerIconLayout")
	if icon_layout and button_icon:
		var button_action = BUTTON_ACTIONS.get(parry_button, "accept")
		var button_texture = icon_layout.get_button_icon(button_action)

		if button_texture:
			button_icon.texture = button_texture
			print("[DefenseMinigame] Updated button icon to %s" % parry_button)
		else:
			push_error("[DefenseMinigame] Failed to load new button icon for %s" % parry_button)

func _miss_parry() -> void:
	"""Player missed the parry (or didn't attempt)"""
	input_locked = true

	if player_attempted_parry:
		# Player pressed the button but missed the timing - PENALTY
		print("[DefenseMinigame] PARRY ATTEMPTED BUT FAILED! Taking increased damage (130%)")
		final_damage_modifier = 1.3
		result_text = "MISS"
	else:
		# Player didn't press anything - circle closed naturally - SAFE
		print("[DefenseMinigame] No parry attempted - taking normal damage (100%)")
		final_damage_modifier = 1.0
		result_text = "HIT!"

	counter_attack_damage = 0.0
	_finish_minigame()

func _lose_parry_battle() -> void:
	"""Player lost the parry battle"""
	input_locked = true
	print("[DefenseMinigame] Lost parry battle at round %d" % parry_round)

	# Take normal damage (no counter-attack)
	final_damage_modifier = 1.0
	counter_attack_damage = 0.0
	result_text = "HIT!"

	_finish_minigame()

func _win_parry_battle() -> void:
	"""Player won the parry battle!"""
	input_locked = true
	print("[DefenseMinigame] WON PARRY BATTLE! Dealing 30%% counter damage + Initiative bonus!")

	# No damage taken, deal 30% counter damage
	final_damage_modifier = 0.0
	counter_attack_damage = attacker_damage * 0.3
	initiative_bonus = 10  # Grant +10 initiative for next round
	result_text = "PARRY!"

	_finish_minigame()

func _finish_minigame() -> void:
	"""Show result and fade out"""
	current_phase = Phase.SHOWING_RESULT

	# Hide battle label
	battle_label.modulate.a = 0.0

	# Show result text
	result_label.text = result_text
	result_label.modulate.a = 1.0

	# Start fade out timer
	fade_timer = 0.0

	print("[DefenseMinigame] Result: %s | Damage modifier: %.1f%% | Counter damage: %.1f" % [result_text, final_damage_modifier * 100, counter_attack_damage])

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
			current_phase = Phase.COMPLETE
			minigame_completed.emit()
			print("[DefenseMinigame] Minigame complete")

func _draw_circle() -> void:
	"""Draw the closing circle with parry zone"""
	var canvas_size = circle_canvas.size
	var center = canvas_size / 2.0

	# Calculate current circle radius
	var current_radius = lerp(circle_max_radius, circle_min_radius, circle_progress)

	# Draw parry zone (40-60% by default, gets easier in battle)
	var parry_radius_min = lerp(circle_max_radius, circle_min_radius, player_parry_min)
	var parry_radius_max = lerp(circle_max_radius, circle_min_radius, player_parry_max)

	# Fill parry zone with green
	_draw_zone_fill(center, parry_radius_max, parry_radius_min, Color(0.0, 1.0, 0.0, 0.25))

	# Draw parry zone outlines
	_draw_circle_outline(center, parry_radius_max, Color(0.0, 1.0, 0.0, 0.8), 3.0)
	_draw_circle_outline(center, parry_radius_min, Color(0.0, 1.0, 0.0, 0.8), 3.0)

	# Draw closing red circle
	_draw_circle_outline(center, current_radius, Color(1.0, 0.0, 0.0, 0.9), 4.0)

func _draw_zone_fill(center: Vector2, radius_outer: float, radius_inner: float, color: Color) -> void:
	"""Fill the area between two circles"""
	var points = 64
	for i in range(points):
		var angle_from = (float(i) / points) * TAU
		var angle_to = (float(i + 1) / points) * TAU

		var outer_from = center + Vector2(cos(angle_from), sin(angle_from)) * radius_outer
		var outer_to = center + Vector2(cos(angle_to), sin(angle_to)) * radius_outer
		var inner_from = center + Vector2(cos(angle_from), sin(angle_from)) * radius_inner
		var inner_to = center + Vector2(cos(angle_to), sin(angle_to)) * radius_inner

		var polygon = PackedVector2Array([outer_from, outer_to, inner_to, inner_from])
		circle_canvas.draw_colored_polygon(polygon, color)

func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	"""Helper to draw a circle outline"""
	var points = 64
	for i in range(points):
		var angle_from = (float(i) / points) * TAU
		var angle_to = (float(i + 1) / points) * TAU
		var from = center + Vector2(cos(angle_from), sin(angle_from)) * radius
		var to = center + Vector2(cos(angle_to), sin(angle_to)) * radius
		circle_canvas.draw_line(from, to, color, width)

func _update_button_color() -> void:
	"""Update button icon color based on which zone the circle is in"""
	if not button_icon:
		return

	# In parry zone - green
	if circle_progress >= player_parry_min and circle_progress <= player_parry_max:
		current_button_modulation = Color(0.3, 1.0, 0.3, 1.0)  # Green
	else:
		# Outside parry zone - white
		current_button_modulation = Color(1.0, 1.0, 1.0, 1.0)  # White

	button_icon.modulate = current_button_modulation
