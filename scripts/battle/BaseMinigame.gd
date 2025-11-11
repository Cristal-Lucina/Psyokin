extends Control
class_name BaseMinigame

## BaseMinigame - Base class for all battle minigames
## Provides common overlay functionality and completion signaling

## Emitted when the minigame completes
signal completed(result: Dictionary)

## Status effects affecting this minigame
var status_effects: Array = []

## Minigame duration (can be modified by status effects)
var base_duration: float = 5.0
var current_duration: float = 5.0

## Visual elements
var overlay_panel: PanelContainer
var background_dim: ColorRect
var content_container: VBoxContainer

## Status effect animation
var status_anim_time: float = 0.0
var status_effect_overlay: Control  # For drawing status effects

func _ready() -> void:
	# Set up as overlay
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_STOP

	_setup_visuals()
	_apply_status_effects()
	_setup_minigame()

	# Start the minigame
	await get_tree().process_frame
	_start_minigame()

func _setup_visuals() -> void:
	"""Create the dimmed background and central panel"""
	# Neon-kawaii color palette
	const COLOR_INK_CHARCOAL = Color(0.07, 0.09, 0.15)
	const COLOR_MILK_WHITE = Color(0.96, 0.97, 0.98)
	const COLOR_SKY_CYAN = Color(0.30, 0.91, 1.0)

	# Dimmed background
	background_dim = ColorRect.new()
	background_dim.color = Color(0, 0, 0, 0.7)
	background_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	background_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background_dim)

	# Central panel (35% of screen - smaller for better visibility)
	overlay_panel = PanelContainer.new()
	overlay_panel.custom_minimum_size = get_viewport_rect().size * 0.35
	overlay_panel.position = get_viewport_rect().size * 0.325
	overlay_panel.position.y -= 160  # Move up 160px
	overlay_panel.z_index = 101

	# Start below screen for slide-up animation
	overlay_panel.modulate.a = 0.0
	var start_y = overlay_panel.position.y
	overlay_panel.position.y = get_viewport_rect().size.y

	# Neon-kawaii panel style
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = COLOR_INK_CHARCOAL
	panel_style.border_width_left = 3
	panel_style.border_width_right = 3
	panel_style.border_width_top = 3
	panel_style.border_width_bottom = 3
	panel_style.border_color = COLOR_SKY_CYAN  # Cyan neon border
	panel_style.corner_radius_top_left = 15
	panel_style.corner_radius_top_right = 15
	panel_style.corner_radius_bottom_left = 15
	panel_style.corner_radius_bottom_right = 15
	panel_style.shadow_size = 6
	panel_style.shadow_color = Color(COLOR_SKY_CYAN.r, COLOR_SKY_CYAN.g, COLOR_SKY_CYAN.b, 0.4)
	overlay_panel.add_theme_stylebox_override("panel", panel_style)

	add_child(overlay_panel)

	# Animate slide up from bottom
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(overlay_panel, "position:y", start_y, 0.5)
	tween.tween_property(overlay_panel, "modulate:a", 1.0, 0.3)

	# Content container
	content_container = VBoxContainer.new()
	content_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_container.add_theme_constant_override("separation", 10)
	overlay_panel.add_child(content_container)

	# Status effect overlay (for animated border effects)
	status_effect_overlay = Control.new()
	status_effect_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	status_effect_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_effect_overlay.z_index = 102
	add_child(status_effect_overlay)

func _apply_status_effects() -> void:
	"""Apply status effect modifiers to the minigame"""
	for effect in status_effects:
		match effect:
			"malaise":
				# 10% faster
				current_duration = base_duration * 0.9
				print("[BaseMinigame] Malaise: Duration %.2fs -> %.2fs" % [base_duration, current_duration])
				_apply_malaise_border()
				# Connect drawing for animated effect
				status_effect_overlay.draw.connect(_draw_malaise_effect)

			"frozen":
				# Visual effect handled by subclasses
				_apply_frozen_border()
				# Connect drawing for animated effect
				status_effect_overlay.draw.connect(_draw_freeze_effect)

			"burn":
				_apply_burned_border()
				# Connect drawing for animated effect
				status_effect_overlay.draw.connect(_draw_burned_effect)

			"poison":
				_apply_poison_border()
				# Connect drawing for animated effect
				status_effect_overlay.draw.connect(_draw_poison_effect)

			"sleep":
				_apply_sleep_border()
				# Connect drawing for animated effect
				status_effect_overlay.draw.connect(_draw_sleep_effect)

func _apply_frozen_border() -> void:
	"""Apply frozen visual effect to border"""
	if overlay_panel:
		var style = overlay_panel.get_theme_stylebox("panel")
		if style is StyleBoxFlat:
			style.border_color = Color(0.6, 0.8, 1.0, 1.0)  # Light blue

func _apply_burned_border() -> void:
	"""Apply burned visual effect to border"""
	if overlay_panel:
		var style = overlay_panel.get_theme_stylebox("panel")
		if style is StyleBoxFlat:
			style.border_color = Color(1.0, 0.4, 0.0, 1.0)  # Fire orange/red

func _apply_poison_border() -> void:
	"""Apply poison visual effect to border"""
	if overlay_panel:
		var style = overlay_panel.get_theme_stylebox("panel")
		if style is StyleBoxFlat:
			style.border_color = Color(0.6, 0.3, 0.8, 1.0)  # Pale purple

func _apply_malaise_border() -> void:
	"""Apply malaise visual effect to border"""
	if overlay_panel:
		var style = overlay_panel.get_theme_stylebox("panel")
		if style is StyleBoxFlat:
			style.border_color = Color(0.1, 0.2, 0.5, 1.0)  # Dark blue

func _apply_sleep_border() -> void:
	"""Apply sleep visual effect to border"""
	if overlay_panel:
		var style = overlay_panel.get_theme_stylebox("panel")
		if style is StyleBoxFlat:
			style.border_color = Color(1.0, 1.0, 1.0, 1.0)  # White

func _process(delta: float) -> void:
	"""Update status effect animations"""
	if status_effects.has("burn") or status_effects.has("poison") or status_effects.has("sleep") or status_effects.has("malaise") or status_effects.has("frozen"):
		status_anim_time += delta
		if status_effect_overlay:
			status_effect_overlay.queue_redraw()

func _draw_burned_effect() -> void:
	"""Draw animated wavy fiery orange lines around the panel"""
	if not overlay_panel:
		return

	var panel_pos = overlay_panel.position
	var panel_size = overlay_panel.size
	var wave_segments = 20
	var line_thickness = 3.0

	# Draw smooth wavy lines along each edge (fiery orange)
	# Top edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var x1 = panel_pos.x + panel_size.x * progress
		var x2 = panel_pos.x + panel_size.x * next_progress
		var y1 = panel_pos.y + sin((status_anim_time * 2.0) + (progress * TAU * 2)) * 6.0
		var y2 = panel_pos.y + sin((status_anim_time * 2.0) + (next_progress * TAU * 2)) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(1.0, 0.4, 0.0, intensity)  # Fiery orange

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Bottom edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var x1 = panel_pos.x + panel_size.x * progress
		var x2 = panel_pos.x + panel_size.x * next_progress
		var y1 = panel_pos.y + panel_size.y + sin((status_anim_time * 2.0) + (progress * TAU * 2) + PI) * 6.0
		var y2 = panel_pos.y + panel_size.y + sin((status_anim_time * 2.0) + (next_progress * TAU * 2) + PI) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(1.0, 0.4, 0.0, intensity)

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Left edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var y1 = panel_pos.y + panel_size.y * progress
		var y2 = panel_pos.y + panel_size.y * next_progress
		var x1 = panel_pos.x + sin((status_anim_time * 2.0) + (progress * TAU * 2)) * 6.0
		var x2 = panel_pos.x + sin((status_anim_time * 2.0) + (next_progress * TAU * 2)) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(1.0, 0.4, 0.0, intensity)

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Right edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var y1 = panel_pos.y + panel_size.y * progress
		var y2 = panel_pos.y + panel_size.y * next_progress
		var x1 = panel_pos.x + panel_size.x + sin((status_anim_time * 2.0) + (progress * TAU * 2) + PI) * 6.0
		var x2 = panel_pos.x + panel_size.x + sin((status_anim_time * 2.0) + (next_progress * TAU * 2) + PI) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(1.0, 0.4, 0.0, intensity)

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

func _draw_poison_effect() -> void:
	"""Draw animated wavy purple lines around the panel"""
	if not overlay_panel:
		return

	var panel_pos = overlay_panel.position
	var panel_size = overlay_panel.size
	var wave_segments = 20
	var line_thickness = 3.0

	# Draw smooth wavy lines along each edge
	# Top edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var x1 = panel_pos.x + panel_size.x * progress
		var x2 = panel_pos.x + panel_size.x * next_progress
		var y1 = panel_pos.y + sin((status_anim_time * 2.0) + (progress * TAU * 2)) * 6.0
		var y2 = panel_pos.y + sin((status_anim_time * 2.0) + (next_progress * TAU * 2)) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(0.6, 0.3, 0.8, intensity)

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Bottom edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var x1 = panel_pos.x + panel_size.x * progress
		var x2 = panel_pos.x + panel_size.x * next_progress
		var y1 = panel_pos.y + panel_size.y + sin((status_anim_time * 2.0) + (progress * TAU * 2) + PI) * 6.0
		var y2 = panel_pos.y + panel_size.y + sin((status_anim_time * 2.0) + (next_progress * TAU * 2) + PI) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(0.6, 0.3, 0.8, intensity)

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Left edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var y1 = panel_pos.y + panel_size.y * progress
		var y2 = panel_pos.y + panel_size.y * next_progress
		var x1 = panel_pos.x + sin((status_anim_time * 2.0) + (progress * TAU * 2)) * 6.0
		var x2 = panel_pos.x + sin((status_anim_time * 2.0) + (next_progress * TAU * 2)) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(0.6, 0.3, 0.8, intensity)

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Right edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var y1 = panel_pos.y + panel_size.y * progress
		var y2 = panel_pos.y + panel_size.y * next_progress
		var x1 = panel_pos.x + panel_size.x + sin((status_anim_time * 2.0) + (progress * TAU * 2) + PI) * 6.0
		var x2 = panel_pos.x + panel_size.x + sin((status_anim_time * 2.0) + (next_progress * TAU * 2) + PI) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(0.6, 0.3, 0.8, intensity)

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

func _draw_sleep_effect() -> void:
	"""Draw animated wavy white lines around the panel"""
	if not overlay_panel:
		return

	var panel_pos = overlay_panel.position
	var panel_size = overlay_panel.size
	var wave_segments = 20
	var line_thickness = 3.0

	# Draw smooth wavy lines along each edge (white, matches charm animation)
	# Top edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var x1 = panel_pos.x + panel_size.x * progress
		var x2 = panel_pos.x + panel_size.x * next_progress
		var y1 = panel_pos.y + sin((status_anim_time * 2.0) + (progress * TAU * 2)) * 6.0
		var y2 = panel_pos.y + sin((status_anim_time * 2.0) + (next_progress * TAU * 2)) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(1.0, 1.0, 1.0, intensity)

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Bottom edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var x1 = panel_pos.x + panel_size.x * progress
		var x2 = panel_pos.x + panel_size.x * next_progress
		var y1 = panel_pos.y + panel_size.y + sin((status_anim_time * 2.0) + (progress * TAU * 2) + PI) * 6.0
		var y2 = panel_pos.y + panel_size.y + sin((status_anim_time * 2.0) + (next_progress * TAU * 2) + PI) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(1.0, 1.0, 1.0, intensity)

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Left edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var y1 = panel_pos.y + panel_size.y * progress
		var y2 = panel_pos.y + panel_size.y * next_progress
		var x1 = panel_pos.x + sin((status_anim_time * 2.0) + (progress * TAU * 2)) * 6.0
		var x2 = panel_pos.x + sin((status_anim_time * 2.0) + (next_progress * TAU * 2)) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(1.0, 1.0, 1.0, intensity)

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Right edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var y1 = panel_pos.y + panel_size.y * progress
		var y2 = panel_pos.y + panel_size.y * next_progress
		var x1 = panel_pos.x + panel_size.x + sin((status_anim_time * 2.0) + (progress * TAU * 2) + PI) * 6.0
		var x2 = panel_pos.x + panel_size.x + sin((status_anim_time * 2.0) + (next_progress * TAU * 2) + PI) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(1.0, 1.0, 1.0, intensity)

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

func _draw_malaise_effect() -> void:
	"""Draw animated wavy dark blue lines around the panel"""
	if not overlay_panel:
		return

	var panel_pos = overlay_panel.position
	var panel_size = overlay_panel.size
	var wave_segments = 20
	var line_thickness = 3.0

	# Draw smooth wavy lines along each edge (dark blue)
	# Top edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var x1 = panel_pos.x + panel_size.x * progress
		var x2 = panel_pos.x + panel_size.x * next_progress
		var y1 = panel_pos.y + sin((status_anim_time * 2.0) + (progress * TAU * 2)) * 6.0
		var y2 = panel_pos.y + sin((status_anim_time * 2.0) + (next_progress * TAU * 2)) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(0.1, 0.2, 0.5, intensity)  # Dark blue

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Bottom edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var x1 = panel_pos.x + panel_size.x * progress
		var x2 = panel_pos.x + panel_size.x * next_progress
		var y1 = panel_pos.y + panel_size.y + sin((status_anim_time * 2.0) + (progress * TAU * 2) + PI) * 6.0
		var y2 = panel_pos.y + panel_size.y + sin((status_anim_time * 2.0) + (next_progress * TAU * 2) + PI) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(0.1, 0.2, 0.5, intensity)  # Dark blue

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Left edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var y1 = panel_pos.y + panel_size.y * progress
		var y2 = panel_pos.y + panel_size.y * next_progress
		var x1 = panel_pos.x + sin((status_anim_time * 2.0) + (progress * TAU * 2)) * 6.0
		var x2 = panel_pos.x + sin((status_anim_time * 2.0) + (next_progress * TAU * 2)) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(0.1, 0.2, 0.5, intensity)  # Dark blue

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Right edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var y1 = panel_pos.y + panel_size.y * progress
		var y2 = panel_pos.y + panel_size.y * next_progress
		var x1 = panel_pos.x + panel_size.x + sin((status_anim_time * 2.0) + (progress * TAU * 2) + PI) * 6.0
		var x2 = panel_pos.x + panel_size.x + sin((status_anim_time * 2.0) + (next_progress * TAU * 2) + PI) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(0.1, 0.2, 0.5, intensity)  # Dark blue

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

func _draw_freeze_effect() -> void:
	"""Draw animated wavy light blue lines around the panel"""
	if not overlay_panel:
		return

	var panel_pos = overlay_panel.position
	var panel_size = overlay_panel.size
	var wave_segments = 20
	var line_thickness = 3.0

	# Draw smooth wavy lines along each edge (light blue)
	# Top edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var x1 = panel_pos.x + panel_size.x * progress
		var x2 = panel_pos.x + panel_size.x * next_progress
		var y1 = panel_pos.y + sin((status_anim_time * 2.0) + (progress * TAU * 2)) * 6.0
		var y2 = panel_pos.y + sin((status_anim_time * 2.0) + (next_progress * TAU * 2)) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(0.6, 0.8, 1.0, intensity)  # Light blue

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Bottom edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var x1 = panel_pos.x + panel_size.x * progress
		var x2 = panel_pos.x + panel_size.x * next_progress
		var y1 = panel_pos.y + panel_size.y + sin((status_anim_time * 2.0) + (progress * TAU * 2) + PI) * 6.0
		var y2 = panel_pos.y + panel_size.y + sin((status_anim_time * 2.0) + (next_progress * TAU * 2) + PI) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(0.6, 0.8, 1.0, intensity)

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Left edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var y1 = panel_pos.y + panel_size.y * progress
		var y2 = panel_pos.y + panel_size.y * next_progress
		var x1 = panel_pos.x + sin((status_anim_time * 2.0) + (progress * TAU * 2)) * 6.0
		var x2 = panel_pos.x + sin((status_anim_time * 2.0) + (next_progress * TAU * 2)) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(0.6, 0.8, 1.0, intensity)

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

	# Right edge
	for i in range(wave_segments):
		var progress = float(i) / wave_segments
		var next_progress = float(i + 1) / wave_segments

		var y1 = panel_pos.y + panel_size.y * progress
		var y2 = panel_pos.y + panel_size.y * next_progress
		var x1 = panel_pos.x + panel_size.x + sin((status_anim_time * 2.0) + (progress * TAU * 2) + PI) * 6.0
		var x2 = panel_pos.x + panel_size.x + sin((status_anim_time * 2.0) + (next_progress * TAU * 2) + PI) * 6.0

		var intensity = 0.6 + sin(status_anim_time * 3.0 + progress * TAU) * 0.4
		var color = Color(0.6, 0.8, 1.0, intensity)

		status_effect_overlay.draw_line(Vector2(x1, y1), Vector2(x2, y2), color, line_thickness)

## Override this in subclasses
func _setup_minigame() -> void:
	pass

## Override this in subclasses
func _start_minigame() -> void:
	pass

## Call this when minigame completes
func _complete_minigame(result: Dictionary) -> void:
	print("[BaseMinigame] Completing with result: %s" % str(result))
	completed.emit(result)
