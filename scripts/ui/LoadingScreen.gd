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

const FADE_DURATION := 0.3
const SPIN_SPEED := 3.0  # Rotations per second
const MIN_DISPLAY_TIME := 3.0  # Minimum seconds to display loading screen

var _background: ColorRect
var _label: Label
var _spinner: Polygon2D
var _tween: Tween
var _display_start_time: float = 0.0

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
		_label = get_node_or_null("Background/CenterContainer/LoadingContainer/LoadingText") as Label
	if _spinner == null:
		_spinner = get_node_or_null("Background/CenterContainer/LoadingContainer/Spinner") as Polygon2D

	# Build UI if background doesn't exist
	if _background == null:
		_build_ui()

	# Start invisible
	if _background:
		_background.modulate = Color(1, 1, 1, 0)

func _build_ui() -> void:
	"""Build the loading screen UI programmatically"""
	# Full-screen dark background
	_background = ColorRect.new()
	_background.name = "Background"
	_background.color = Color(0.05, 0.05, 0.05, 1.0)  # Very dark gray
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_background)

	# Container for loading text and spinner (centered)
	var center := CenterContainer.new()
	center.name = "CenterContainer"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_background.add_child(center)

	var container := HBoxContainer.new()
	container.name = "LoadingContainer"
	container.add_theme_constant_override("separation", 12)
	center.add_child(container)

	# "LOADING" text
	_label = Label.new()
	_label.name = "LoadingText"
	_label.text = "LOADING"
	_label.add_theme_font_size_override("font_size", 40)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	container.add_child(_label)

	# Spinning shape (diamond)
	_spinner = Polygon2D.new()
	_spinner.name = "Spinner"
	_spinner.color = Color(0.3, 0.6, 1.0, 0.9)  # Blue
	_spinner.polygon = _create_diamond(20.0)
	_spinner.position = Vector2(-35, 30)  # Positioned left and down from center
	container.add_child(_spinner)

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
	_tween.set_parallel(true)  # Run both tweens in parallel

	# Fade in the loading screen background
	_tween.tween_property(_background, "modulate", Color(1, 1, 1, 1), FADE_DURATION)

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
	_tween.set_parallel(true)  # Run both tweens in parallel

	# Fade out the loading screen background
	_tween.tween_property(_background, "modulate", Color(1, 1, 1, 0), FADE_DURATION)

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
