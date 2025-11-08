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

var _background: ColorRect
var _label: Label
var _spinner: Polygon2D
var _tween: Tween

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

	# Build UI if not loaded from scene
	if _background == null:
		_build_ui()

	# Start invisible
	modulate = Color(1, 1, 1, 0)

func _build_ui() -> void:
	"""Build the loading screen UI programmatically"""
	# Full-screen dark background
	_background = ColorRect.new()
	_background.name = "Background"
	_background.color = Color(0.05, 0.05, 0.05, 1.0)  # Very dark gray
	_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_background)

	# Container for loading text and spinner (bottom right)
	var container := HBoxContainer.new()
	container.name = "LoadingContainer"
	container.add_theme_constant_override("separation", 12)
	_background.add_child(container)

	# Position at bottom right with margin
	container.anchor_left = 1.0
	container.anchor_right = 1.0
	container.anchor_top = 1.0
	container.anchor_bottom = 1.0
	container.offset_left = -200
	container.offset_right = -40
	container.offset_top = -60
	container.offset_bottom = -40

	# "LOADING" text
	_label = Label.new()
	_label.name = "LoadingText"
	_label.text = "LOADING"
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	container.add_child(_label)

	# Spinning shape (octagon)
	_spinner = Polygon2D.new()
	_spinner.name = "Spinner"
	_spinner.color = Color(1.0, 0.7, 0.75, 0.9)  # Pink to match theme
	_spinner.polygon = _create_octagon(16.0)
	_spinner.position = Vector2(20, 10)
	container.add_child(_spinner)

func _create_octagon(radius: float) -> PackedVector2Array:
	"""Create an octagon shape for the spinner"""
	var points: PackedVector2Array = []
	var sides := 8
	for i in range(sides):
		var angle := (i * TAU / sides) - PI / 2  # Start at top
		var x := cos(angle) * radius
		var y := sin(angle) * radius
		points.append(Vector2(x, y))
	return points

func _process(delta: float) -> void:
	"""Rotate the spinner"""
	if _spinner and visible:
		_spinner.rotation += SPIN_SPEED * TAU * delta

func fade_in() -> void:
	"""Fade in the loading screen"""
	show()

	if _tween:
		_tween.kill()

	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "modulate", Color(1, 1, 1, 1), FADE_DURATION)

	await _tween.finished

func fade_out() -> void:
	"""Fade out the loading screen"""
	if _tween:
		_tween.kill()

	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(self, "modulate", Color(1, 1, 1, 0), FADE_DURATION)

	await _tween.finished
	hide()

func set_text(text: String) -> void:
	"""Update the loading text"""
	if _label:
		_label.text = text
