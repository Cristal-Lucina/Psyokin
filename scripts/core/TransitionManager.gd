extends CanvasLayer
class_name TransitionManager

## TransitionManager - Scene Transition Controller
## Handles fade in/out transitions between scenes (like overworld to battle)

signal transition_finished

@onready var color_rect: ColorRect = ColorRect.new()
var is_transitioning: bool = false

func _ready() -> void:
	# Setup full-screen black rectangle for fading
	color_rect.color = Color.BLACK
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(color_rect)

	# Start fully transparent
	color_rect.modulate.a = 0.0

	# Ensure we're always on top
	layer = 100

	# Make it cover the whole screen
	_update_rect_size()
	get_tree().root.size_changed.connect(_update_rect_size)

func _update_rect_size() -> void:
	"""Update the ColorRect to cover the entire viewport"""
	var viewport_size = get_viewport().get_visible_rect().size
	color_rect.size = viewport_size
	color_rect.position = Vector2.ZERO

func fade_out(duration: float = 0.5) -> void:
	"""Fade to black"""
	if is_transitioning:
		return

	is_transitioning = true
	color_rect.mouse_filter = Control.MOUSE_FILTER_STOP

	# Animate to black
	var tween = create_tween()
	tween.tween_property(color_rect, "modulate:a", 1.0, duration)
	await tween.finished

	transition_finished.emit()

func fade_in(duration: float = 0.5) -> void:
	"""Fade from black to transparent"""
	# Animate to transparent
	var tween = create_tween()
	tween.tween_property(color_rect, "modulate:a", 0.0, duration)
	await tween.finished

	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	is_transitioning = false
	transition_finished.emit()

func fade_out_and_in(hold_duration: float = 0.3, fade_duration: float = 0.5) -> void:
	"""Fade out, hold black, then fade in"""
	await fade_out(fade_duration)
	await get_tree().create_timer(hold_duration).timeout
	await fade_in(fade_duration)

## Transition to a new scene with fade
func transition_to_scene(scene_path: String, fade_out_time: float = 0.5, hold_time: float = 0.3, fade_in_time: float = 0.5) -> void:
	"""Fade out, change scene, fade in"""
	await fade_out(fade_out_time)

	# Change scene
	var err = get_tree().change_scene_to_file(scene_path)
	if err != OK:
		push_error("[TransitionManager] Failed to load scene: %s (error %d)" % [scene_path, err])
		await fade_in(fade_in_time)
		return

	# Hold on black
	if hold_time > 0:
		await get_tree().create_timer(hold_time).timeout

	# Fade in
	await fade_in(fade_in_time)
