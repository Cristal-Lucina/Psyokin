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
	overlay_panel.z_index = 101

	# Panel style
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.15, 0.15, 0.2, 1.0)
	panel_style.border_width_left = 4
	panel_style.border_width_right = 4
	panel_style.border_width_top = 4
	panel_style.border_width_bottom = 4
	panel_style.border_color = Color(0.4, 0.6, 0.8, 1.0)
	overlay_panel.add_theme_stylebox_override("panel", panel_style)

	add_child(overlay_panel)

	# Content container
	content_container = VBoxContainer.new()
	content_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_container.add_theme_constant_override("separation", 10)
	overlay_panel.add_child(content_container)

func _apply_status_effects() -> void:
	"""Apply status effect modifiers to the minigame"""
	for effect in status_effects:
		match effect:
			"malaise":
				# 10% faster
				current_duration = base_duration * 0.9
				print("[BaseMinigame] Malaise: Duration %.2fs -> %.2fs" % [base_duration, current_duration])

			"frozen":
				# Visual effect handled by subclasses
				_apply_frozen_border()

			"burned", "poison":
				# Screen shake handled by subclasses
				pass

func _apply_frozen_border() -> void:
	"""Apply frozen visual effect to border"""
	if overlay_panel:
		var style = overlay_panel.get_theme_stylebox("panel")
		if style is StyleBoxFlat:
			style.border_color = Color(0.6, 0.8, 1.0, 1.0)  # Pale blue

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
			style.border_color = Color(0.7, 0.7, 0.7, 1.0)  # Cloudy gray

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
