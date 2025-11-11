extends CanvasLayer
class_name LoadingScreen

## Full-screen loading overlay with fade in/out and spinning indicator
##
## USAGE:
##   var loading = LoadingScreen.create()
##   await loading.fade_in()
##   # ... do loading work ...
##   await loading.fade_out()
##   loading.queue_free()

## Neon Orchard Color Palette
const COLOR_ELECTRIC_LIME = Color(0.78, 1.0, 0.24)      # #C8FF3D
const COLOR_BUBBLE_MAGENTA = Color(1.0, 0.29, 0.85)     # #FF4AD9
const COLOR_SKY_CYAN = Color(0.30, 0.91, 1.0)           # #4DE9FF
const COLOR_CITRUS_YELLOW = Color(1.0, 0.91, 0.30)      # #FFE84D
const COLOR_PLASMA_TEAL = Color(0.13, 0.89, 0.70)       # #20E3B2
const COLOR_GRAPE_VIOLET = Color(0.54, 0.25, 0.99)      # #8A3FFC
const COLOR_NIGHT_NAVY = Color(0.04, 0.06, 0.10)        # #0A0F1A
const COLOR_INK_CHARCOAL = Color(0.07, 0.09, 0.15)      # #111827
const COLOR_MILK_WHITE = Color(0.96, 0.97, 0.98)        # #F4F7FB

const FADE_DURATION := 0.3
const SPIN_SPEED := 3.0  # Rotations per second
const MIN_DISPLAY_TIME := 3.0  # Minimum seconds to display loading screen

var _background: ColorRect
var _label: Label
var _spinner: Polygon2D
var _tween: Tween
var _display_start_time: float = 0.0
var _particle_layer: Node2D = null

static func create() -> LoadingScreen:
	"""Create a new loading screen instance"""
	var scene := load("res://scenes/ui/LoadingScreen.tscn") as PackedScene
	if scene:
		return scene.instantiate() as LoadingScreen

	# Fallback: create programmatically if scene doesn't exist
	var loading := LoadingScreen.new()
	loading._build_ui()
	return loading

func _ready() -> void:
	# Ensure this processes even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 1000  # Very high layer to be on top of everything

	# Get nodes from scene or build UI
	if _background == null:
		_background = get_node_or_null("Background") as ColorRect
	if _label == null:
		_label = get_node_or_null("Background/CenterContainer/LoadingPanel/LoadingContainer/LoadingText") as Label
	if _spinner == null:
		_spinner = get_node_or_null("Background/CenterContainer/LoadingPanel/LoadingContainer/Spinner") as Polygon2D

	# Build UI if background doesn't exist
	if _background == null:
		_build_ui()
	else:
		# Apply Core Vibe styling to existing panel
		_apply_panel_style()

	# Add ambient particles
	_spawn_ambient_particles()

	# Start invisible
	if _background:
		_background.modulate = Color(1, 1, 1, 0)

func _build_ui() -> void:
	"""Build the loading screen UI programmatically with Core Vibe styling"""
	# Full-screen dark background (fully opaque)
	_background = ColorRect.new()
	_background.name = "Background"
	_background.color = COLOR_NIGHT_NAVY  # Fully opaque
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_background)

	# Container for loading text and spinner (centered)
	var center := CenterContainer.new()
	center.name = "CenterContainer"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.add_child(center)

	# Create pill capsule panel
	var panel := PanelContainer.new()
	panel.name = "LoadingPanel"

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_INK_CHARCOAL  # Fully opaque
	panel_style.border_color = COLOR_SKY_CYAN
	panel_style.border_width_left = 3
	panel_style.border_width_right = 3
	panel_style.border_width_top = 3
	panel_style.border_width_bottom = 3
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.shadow_color = Color(COLOR_SKY_CYAN.r, COLOR_SKY_CYAN.g, COLOR_SKY_CYAN.b, 0.5)
	panel_style.shadow_size = 8
	panel_style.content_margin_left = 32
	panel_style.content_margin_right = 32
	panel_style.content_margin_top = 20
	panel_style.content_margin_bottom = 20

	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var container := HBoxContainer.new()
	container.name = "LoadingContainer"
	container.add_theme_constant_override("separation", 16)
	panel.add_child(container)

	# "LOADING" text with Core Vibe styling
	_label = Label.new()
	_label.name = "LoadingText"
	_label.text = "LOADING"
	_label.add_theme_font_size_override("font_size", 36)
	_label.add_theme_color_override("font_color", COLOR_SKY_CYAN)
	container.add_child(_label)

	# Spinning shape (diamond) with neon colors
	_spinner = Polygon2D.new()
	_spinner.name = "Spinner"
	_spinner.color = COLOR_BUBBLE_MAGENTA
	_spinner.polygon = _create_diamond(16.0)
	_spinner.position = Vector2(-30, 24)  # Positioned left and down from center
	container.add_child(_spinner)

func _apply_panel_style() -> void:
	"""Apply Core Vibe styling to the loading panel from scene"""
	var panel = get_node_or_null("Background/CenterContainer/LoadingPanel") as PanelContainer
	if panel:
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = COLOR_INK_CHARCOAL  # Fully opaque
		panel_style.border_color = COLOR_SKY_CYAN
		panel_style.border_width_left = 3
		panel_style.border_width_right = 3
		panel_style.border_width_top = 3
		panel_style.border_width_bottom = 3
		panel_style.corner_radius_top_left = 12
		panel_style.corner_radius_top_right = 12
		panel_style.corner_radius_bottom_left = 12
		panel_style.corner_radius_bottom_right = 12
		panel_style.shadow_color = Color(COLOR_SKY_CYAN.r, COLOR_SKY_CYAN.g, COLOR_SKY_CYAN.b, 0.5)
		panel_style.shadow_size = 8
		panel_style.content_margin_left = 32
		panel_style.content_margin_right = 32
		panel_style.content_margin_top = 20
		panel_style.content_margin_bottom = 20

		panel.add_theme_stylebox_override("panel", panel_style)

func _spawn_ambient_particles() -> void:
	"""Spawn pulsing neon squares for ambient atmosphere"""
	# Remove old particle layer if it exists
	if _particle_layer and is_instance_valid(_particle_layer):
		_particle_layer.queue_free()

	_particle_layer = Node2D.new()
	_particle_layer.name = "AmbientParticles"
	_particle_layer.z_index = 10  # Bring to front, above UI elements
	_particle_layer.modulate = Color(1, 1, 1, 0)  # Start invisible
	add_child(_particle_layer)

	var viewport_size = get_viewport().get_visible_rect().size if get_viewport() else Vector2(1152, 648)

	# Create 50 ambient particles (more than title screen)
	for i in range(50):
		var particle = ColorRect.new()
		var size = randi_range(6, 12)  # Bigger than title screen (was 2-6)
		particle.custom_minimum_size = Vector2(size, size)
		particle.size = Vector2(size, size)

		# Random neon color
		var colors = [COLOR_SKY_CYAN, COLOR_BUBBLE_MAGENTA, COLOR_ELECTRIC_LIME, COLOR_CITRUS_YELLOW]
		particle.color = colors[randi() % colors.size()]

		# Random position
		particle.position = Vector2(
			randf_range(0, viewport_size.x),
			randf_range(0, viewport_size.y)
		)

		# Set pivot to center for scaling
		particle.pivot_offset = Vector2(size / 2.0, size / 2.0)

		_particle_layer.add_child(particle)

		# Animate slow drift
		var drift_tween = create_tween()
		drift_tween.set_loops()
		var drift_x = randf_range(-100, 100)
		var drift_y = randf_range(-60, 60)
		var drift_duration = randf_range(10, 18)
		drift_tween.tween_property(particle, "position", particle.position + Vector2(drift_x, drift_y), drift_duration)
		drift_tween.tween_property(particle, "position", particle.position, drift_duration)

		# Animate pulsing scale
		var pulse_tween = create_tween()
		pulse_tween.set_loops()
		var pulse_duration = randf_range(1.5, 3.0)
		var scale_min = randf_range(0.8, 0.9)
		var scale_max = randf_range(1.1, 1.3)
		pulse_tween.set_trans(Tween.TRANS_SINE)
		pulse_tween.set_ease(Tween.EASE_IN_OUT)
		pulse_tween.tween_property(particle, "scale", Vector2(scale_max, scale_max), pulse_duration / 2.0)
		pulse_tween.tween_property(particle, "scale", Vector2(scale_min, scale_min), pulse_duration / 2.0)

		# Animate pulsing opacity
		var opacity_tween = create_tween()
		opacity_tween.set_loops()
		var opacity_duration = randf_range(2.0, 4.0)
		var opacity_min = randf_range(0.3, 0.5)
		var opacity_max = randf_range(0.8, 1.0)
		opacity_tween.set_trans(Tween.TRANS_SINE)
		opacity_tween.set_ease(Tween.EASE_IN_OUT)
		opacity_tween.tween_property(particle, "modulate:a", opacity_max, opacity_duration / 2.0)
		opacity_tween.tween_property(particle, "modulate:a", opacity_min, opacity_duration / 2.0)

func _create_diamond(size: float) -> PackedVector2Array:
	"""Create a diamond shape for the spinner"""
	var points: PackedVector2Array = []
	points.append(Vector2(0, -size))      # Top
	points.append(Vector2(size, 0))       # Right
	points.append(Vector2(0, size))       # Bottom
	points.append(Vector2(-size, 0))      # Left
	return points

func _process(delta: float) -> void:
	"""Rotate the spinner"""
	if _spinner and visible:
		_spinner.rotation += SPIN_SPEED * TAU * delta

func fade_in() -> void:
	"""Fade in the loading screen and fade out the current scene"""
	show()
	_display_start_time = Time.get_ticks_msec() / 1000.0  # Track when we started displaying

	if not _background:
		return

	if _tween:
		_tween.kill()

	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.set_parallel(true)  # Run all tweens in parallel

	# Fade in the loading screen background
	_tween.tween_property(_background, "modulate", Color(1, 1, 1, 1), FADE_DURATION)

	# Fade in the particle layer
	if _particle_layer:
		_tween.tween_property(_particle_layer, "modulate", Color(1, 1, 1, 1), FADE_DURATION)

	# Fade out the current scene
	var current_scene = get_tree().current_scene
	if current_scene and current_scene != self:
		_tween.tween_property(current_scene, "modulate", Color(1, 1, 1, 0), FADE_DURATION)

	await _tween.finished

func fade_out() -> void:
	"""Fade out the loading screen and fade in the new scene"""
	# Ensure minimum display time has passed
	var current_time := Time.get_ticks_msec() / 1000.0
	var elapsed_time := current_time - _display_start_time
	if elapsed_time < MIN_DISPLAY_TIME:
		var remaining_time := MIN_DISPLAY_TIME - elapsed_time
		await get_tree().create_timer(remaining_time).timeout

	if not _background:
		hide()
		return

	if _tween:
		_tween.kill()

	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.set_parallel(true)  # Run all tweens in parallel

	# Fade out the loading screen background
	_tween.tween_property(_background, "modulate", Color(1, 1, 1, 0), FADE_DURATION)

	# Fade out the particle layer
	if _particle_layer:
		_tween.tween_property(_particle_layer, "modulate", Color(1, 1, 1, 0), FADE_DURATION)

	# Fade in the new scene (if it exists and is different from the old one)
	var new_scene = get_tree().current_scene
	if new_scene and new_scene != self:
		# Ensure the new scene starts invisible
		if new_scene.modulate.a < 0.1:
			new_scene.modulate = Color(1, 1, 1, 0)
		_tween.tween_property(new_scene, "modulate", Color(1, 1, 1, 1), FADE_DURATION)

	await _tween.finished
	hide()

func set_text(text: String) -> void:
	"""Update the loading text"""
	if _label:
		_label.text = text

func _fade_out_and_cleanup() -> void:
	"""Deferred helper to fade out after scene change and set up new scene"""
	# Wait for new scene to be fully loaded
	await get_tree().process_frame
	await get_tree().process_frame  # Extra frame for safety

	# Ensure new scene starts invisible so we can fade it in
	if get_tree().current_scene:
		get_tree().current_scene.modulate = Color(1, 1, 1, 0)

	# Fade out loading screen (will fade in the new scene)
	await fade_out()
	queue_free()
