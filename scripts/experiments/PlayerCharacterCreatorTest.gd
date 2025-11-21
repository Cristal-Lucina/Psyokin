extends Control

## Player Character Creator Test
## Simplified, controller-friendly character creator for players

# Paths
const SPRITE_PATH = "res://assets/graphics/characters/New Character System/SpriteSystem/base_sheets/"
const PALETTE_PATH = "res://assets/graphics/characters/New Character System/SpriteSystem/_supporting files/palettes/"
const ANIM_DATA_PATH = "res://scenes/test/sprite_animations_data.csv"

# Layer configuration
const LAYERS = [
	{"code": "01body", "label": "Skin Tone", "ramp_type": "skin", "max_colors": 18, "has_parts": false},
	{"code": "02sock", "label": "Legwear", "ramp_type": "3color", "max_colors": 48, "has_parts": true},
	{"code": "footwear", "label": "Footwear", "ramp_type": "3color", "max_colors": 48, "has_parts": true, "sprite_layers": ["03fot1", "07fot2"]},
	{"code": "bottomwear", "label": "Bottomwear", "ramp_type": "3color", "max_colors": 48, "has_parts": true, "sprite_layers": ["04lwr1", "06lwr2", "08lwr3"]},
	{"code": "05shrt", "label": "Topwear", "ramp_type": "3color", "max_colors": 48, "has_parts": true},
	{"code": "09hand", "label": "Handwear", "ramp_type": "3color", "max_colors": 48, "has_parts": true},
	{"code": "10outr", "label": "Overwear", "ramp_type": "3color", "max_colors": 48, "has_parts": true},
	{"code": "11neck", "label": "Neckwear", "ramp_type": "4color", "max_colors": 59, "has_parts": true, "auto_match_layer": "00undr"},
	{"code": "12face", "label": "Eyewear", "ramp_type": "3color", "max_colors": 48, "has_parts": true},
	{"code": "13hair", "label": "Hairstyle", "ramp_type": "hair", "max_colors": 58, "has_parts": true},
	{"code": "14head", "label": "Headwear", "ramp_type": "4color", "max_colors": 59, "has_parts": true}
]

# Animation options
const ANIMATIONS = ["Idle", "Walk", "Run", "Jump"]
const DIRECTIONS = ["DOWN", "LEFT", "RIGHT", "UP"]

# UI References
@onready var character_preview = $MarginContainer/MainContainer/RightPanel/PreviewContainer/CharacterLayers
@onready var animation_buttons_container = $MarginContainer/MainContainer/RightPanel/AnimationButtons
@onready var direction_buttons_container = $MarginContainer/MainContainer/RightPanel/DirectionButtons
@onready var customization_container = $MarginContainer/MainContainer/LeftPanel/PaddingContainer/ScrollContainer/ScrollPadding/CustomizationList
@onready var left_column = $MarginContainer/MainContainer/LeftPanel/PaddingContainer/ScrollContainer/ScrollPadding/CustomizationList/LeftColumn
@onready var right_column = $MarginContainer/MainContainer/LeftPanel/PaddingContainer/ScrollContainer/ScrollPadding/CustomizationList/RightColumn
@onready var scroll_container = $MarginContainer/MainContainer/LeftPanel/PaddingContainer/ScrollContainer

# State
var animations = {}  # Loaded from CSV
var available_parts = {}  # Scanned sprite parts
var palette_images = {}  # Cached palette images
var texture_cache = {}  # Cached recolored textures for performance
var current_selections = {}  # Current part selections {layer_code: part}
var current_part_indices = {}  # Current part index for each layer {layer_code: index}
var current_colors = {}  # Current color selections
var current_animation = "Idle"
var current_direction = "DOWN"
var current_frame_index = 0
var animation_timer = 0.0
var sections = []  # Array to track section nodes by layer index
var accept_button = null  # Reference to the Accept button
var accept_button_normal_style = null  # Normal style for Accept button
var accept_button_active_style = null  # Active style for Accept button

# Navigation state
var active_toggle_layer = -1  # Which layer's toggle is active (-1 = none, LAYERS.size() = Accept button)
var active_toggle_type = ""  # "part", "color", or "accept" - which toggle is active

# Trigger debouncing
var l2_was_pressed = false
var r2_was_pressed = false

func _ready():
	print("=== PLAYER CHARACTER CREATOR TEST ===")
	load_palette_images()
	load_animation_data()
	scan_character_assets()
	build_ui()
	set_default_character()
	update_preview()
	update_focus_visual()

func _unhandled_input(event):
	"""Handle controller/keyboard input"""
	# Accept/Confirm button (A button, Enter, Space)
	if event.is_action_pressed("ui_accept"):
		handle_accept()
		get_viewport().set_input_as_handled()

	# Back/Cancel button (B button, Escape, Backspace)
	elif event.is_action_pressed("ui_cancel"):
		handle_back()
		get_viewport().set_input_as_handled()

	# Navigate up
	elif event.is_action_pressed("ui_up"):
		handle_up()
		get_viewport().set_input_as_handled()

	# Navigate down
	elif event.is_action_pressed("ui_down"):
		handle_down()
		get_viewport().set_input_as_handled()

	# Navigate left
	elif event.is_action_pressed("ui_left"):
		handle_left()
		get_viewport().set_input_as_handled()

	# Navigate right
	elif event.is_action_pressed("ui_right"):
		handle_right()
		get_viewport().set_input_as_handled()

	# L1 button (Joybutton 9) - Previous animation
	elif event is InputEventJoypadButton and event.button_index == 9 and event.pressed:
		_on_animation_previous()
		get_viewport().set_input_as_handled()

	# R1 button (Joybutton 10) - Next animation
	elif event is InputEventJoypadButton and event.button_index == 10 and event.pressed:
		_on_animation_next()
		get_viewport().set_input_as_handled()

	# L2 trigger (Joypad Axis 4+) - Previous direction
	elif event is InputEventJoypadMotion and event.axis == 4:
		if event.axis_value > 0.5 and not l2_was_pressed:
			_on_direction_previous()
			l2_was_pressed = true
			get_viewport().set_input_as_handled()
		elif event.axis_value < 0.3:
			l2_was_pressed = false

	# R2 trigger (Joypad Axis 5+) - Next direction
	elif event is InputEventJoypadMotion and event.axis == 5:
		if event.axis_value > 0.5 and not r2_was_pressed:
			_on_direction_next()
			r2_was_pressed = true
			get_viewport().set_input_as_handled()
		elif event.axis_value < 0.3:
			r2_was_pressed = false

func load_palette_images():
	"""Load all palette images for color swapping"""
	palette_images["3color"] = load(PALETTE_PATH + "mana seed 3-color ramps.png").get_image()
	palette_images["4color"] = load(PALETTE_PATH + "mana seed 4-color ramps.png").get_image()
	palette_images["hair"] = load(PALETTE_PATH + "mana seed hair ramps.png").get_image()
	palette_images["skin"] = load(PALETTE_PATH + "mana seed skin ramps.png").get_image()
	print("Loaded palette images")

func load_animation_data():
	"""Parse the CSV file to load animation data"""
	print("Loading animation data from CSV...")
	var file = FileAccess.open(ANIM_DATA_PATH, FileAccess.READ)
	if file == null:
		print("ERROR: Could not open animation CSV file")
		return

	# Skip header
	file.get_csv_line()

	while not file.eof_reached():
		var line = file.get_csv_line()
		if line.size() < 3:
			continue

		var anim_name = line[0].strip_edges()
		var direction = line[1].strip_edges().to_upper()
		var frame_count = int(line[2].strip_edges())

		if anim_name == "" or direction == "":
			continue

		# Parse frames and times
		var frames = []
		var times = []

		for i in range(frame_count):
			var cell_idx = 3 + (i * 2)
			var time_idx = 4 + (i * 2)

			if cell_idx >= line.size() or time_idx >= line.size():
				break

			var cell_str = line[cell_idx].strip_edges()
			var time_str = line[time_idx].strip_edges()

			if cell_str == "":
				break

			# Parse cell
			var frame_data = parse_cell(cell_str)
			frames.append(frame_data)

			# Parse time
			var time_ms = 0
			if time_str.to_lower() == "hold":
				time_ms = -1
			else:
				time_ms = int(time_str)
			times.append(time_ms)

		# Store animation data
		if anim_name not in animations:
			animations[anim_name] = {}

		animations[anim_name][direction] = {
			"frames": frames,
			"times": times,
			"total_frames": frames.size()
		}

	file.close()
	print("Loaded ", animations.size(), " animations")

func parse_cell(cell_str: String) -> Dictionary:
	"""Parse cell string like '48f' into {cell: int, flip: bool}"""
	var flip = false
	var cell_num = 0

	if cell_str.to_lower().ends_with("f"):
		flip = true
		cell_str = cell_str.substr(0, cell_str.length() - 1)

	cell_num = int(cell_str)
	return {"cell": cell_num, "flip": flip}

func scan_character_assets():
	"""Scan sprite system folders for available parts"""
	print("Scanning character assets...")

	for layer in LAYERS:
		var layer_code = layer.code

		# Check if this layer uses multiple sprite layers (like footwear)
		var sprite_codes = []
		if "sprite_layers" in layer:
			sprite_codes = layer.sprite_layers
		else:
			sprite_codes = [layer_code]

		if layer_code not in available_parts:
			available_parts[layer_code] = []

		# Scan all sprite layer directories
		for sprite_code in sprite_codes:
			var layer_path = SPRITE_PATH + sprite_code + "/"
			var dir = DirAccess.open(layer_path)

			if dir == null:
				print("  Sprite layer ", sprite_code, ": not found")
				continue

			dir.list_dir_begin()
			var file_name = dir.get_next()
			while file_name != "":
				if file_name.ends_with(".png") and file_name.begins_with("fbas_"):
					var full_path = layer_path + file_name
					var part_info = parse_filename(file_name, sprite_code)
					part_info["path"] = full_path
					part_info["sprite_code"] = sprite_code  # Track which sprite layer this belongs to
					available_parts[layer_code].append(part_info)
				file_name = dir.get_next()
			dir.list_dir_end()

		# Also scan auto-match layer if defined (like 00undr for neckwear)
		if "auto_match_layer" in layer:
			var auto_layer_code = layer.auto_match_layer
			var auto_layer_path = SPRITE_PATH + auto_layer_code + "/"
			var auto_dir = DirAccess.open(auto_layer_path)

			if auto_layer_code not in available_parts:
				available_parts[auto_layer_code] = []

			if auto_dir != null:
				auto_dir.list_dir_begin()
				var file_name = auto_dir.get_next()
				while file_name != "":
					if file_name.ends_with(".png") and file_name.begins_with("fbas_"):
						var full_path = auto_layer_path + file_name
						var part_info = parse_filename(file_name, auto_layer_code)
						part_info["path"] = full_path
						part_info["sprite_code"] = auto_layer_code
						available_parts[auto_layer_code].append(part_info)
					file_name = auto_dir.get_next()
				auto_dir.list_dir_end()
				print("  Auto-match layer ", auto_layer_code, ": found ", available_parts[auto_layer_code].size(), " parts")

		print("  Layer ", layer_code, ": found ", available_parts[layer_code].size(), " parts")

	print("Asset scan complete")

func parse_filename(filename: String, layer_code: String) -> Dictionary:
	"""Parse Mana Seed filename format"""
	var parts = filename.get_basename().split("_")
	var result = {
		"name": filename.get_basename(),
		"base_name": "",
		"palette_code": "",
		"display_name": filename.get_basename()
	}

	if parts.size() >= 4:
		result["base_name"] = parts[2]
		result["palette_code"] = parts[3]
		result["display_name"] = parts[2].capitalize()

	return result

func build_ui():
	"""Build the UI dynamically"""
	print("Building UI...")

	# Build right panel (character preview + controls)
	build_animation_controls()

	# Build left panel (customization options)
	build_customization_options()

func build_animation_controls():
	"""Build animation selection buttons"""
	# Get the parent containers
	var anim_label_parent = $MarginContainer/MainContainer/RightPanel/AnimationLabel.get_parent()
	var dir_label_parent = $MarginContainer/MainContainer/RightPanel/DirectionLabel.get_parent()

	# Remove the default labels
	var anim_label = $MarginContainer/MainContainer/RightPanel/AnimationLabel
	var dir_label = $MarginContainer/MainContainer/RightPanel/DirectionLabel
	var anim_label_idx = anim_label.get_index()
	var dir_label_idx = dir_label.get_index()
	anim_label.queue_free()
	dir_label.queue_free()

	# Create Animation label with L1/R1 buttons
	var anim_label_container = HBoxContainer.new()
	anim_label_container.name = "AnimationLabelContainer"
	anim_label_container.alignment = BoxContainer.ALIGNMENT_CENTER
	anim_label_parent.add_child(anim_label_container)
	anim_label_parent.move_child(anim_label_container, anim_label_idx)

	var l1_btn = Button.new()
	l1_btn.name = "L1Button"
	l1_btn.text = "L1"
	l1_btn.custom_minimum_size = Vector2(60, 40)
	l1_btn.focus_mode = Control.FOCUS_NONE  # Not controller-selectable, only for display
	l1_btn.pressed.connect(_on_animation_previous)
	anim_label_container.add_child(l1_btn)

	var anim_label_new = Label.new()
	anim_label_new.name = "AnimationLabel"
	anim_label_new.text = "Animation: " + current_animation
	anim_label_new.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	anim_label_new.custom_minimum_size = Vector2(200, 0)
	anim_label_container.add_child(anim_label_new)

	var r1_btn = Button.new()
	r1_btn.name = "R1Button"
	r1_btn.text = "R1"
	r1_btn.custom_minimum_size = Vector2(60, 40)
	r1_btn.focus_mode = Control.FOCUS_NONE  # Not controller-selectable, only for display
	r1_btn.pressed.connect(_on_animation_next)
	anim_label_container.add_child(r1_btn)

	# Animation buttons (Walk/Run/Jump)
	for anim in ANIMATIONS:
		var btn = Button.new()
		btn.text = anim
		btn.focus_mode = Control.FOCUS_NONE  # Not controller-selectable
		btn.pressed.connect(_on_animation_selected.bind(anim))
		animation_buttons_container.add_child(btn)

	# Create Direction label with L2/R2 buttons
	var dir_label_container = HBoxContainer.new()
	dir_label_container.name = "DirectionLabelContainer"
	dir_label_container.alignment = BoxContainer.ALIGNMENT_CENTER
	dir_label_parent.add_child(dir_label_container)
	dir_label_parent.move_child(dir_label_container, dir_label_idx)

	var l2_btn = Button.new()
	l2_btn.name = "L2Button"
	l2_btn.text = "L2"
	l2_btn.custom_minimum_size = Vector2(60, 40)
	l2_btn.focus_mode = Control.FOCUS_NONE  # Not controller-selectable, only for display
	l2_btn.pressed.connect(_on_direction_previous)
	dir_label_container.add_child(l2_btn)

	var dir_label_new = Label.new()
	dir_label_new.name = "DirectionLabel"
	dir_label_new.text = "Direction: " + current_direction
	dir_label_new.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dir_label_new.custom_minimum_size = Vector2(200, 0)
	dir_label_container.add_child(dir_label_new)

	var r2_btn = Button.new()
	r2_btn.name = "R2Button"
	r2_btn.text = "R2"
	r2_btn.custom_minimum_size = Vector2(60, 40)
	r2_btn.focus_mode = Control.FOCUS_NONE  # Not controller-selectable, only for display
	r2_btn.pressed.connect(_on_direction_next)
	dir_label_container.add_child(r2_btn)

	# Direction arrows
	for dir in DIRECTIONS:
		var btn = Button.new()
		match dir:
			"UP": btn.text = "↑"
			"DOWN": btn.text = "↓"
			"LEFT": btn.text = "←"
			"RIGHT": btn.text = "→"
		btn.focus_mode = Control.FOCUS_NONE  # Not controller-selectable
		btn.pressed.connect(_on_direction_selected.bind(dir))
		direction_buttons_container.add_child(btn)

func build_customization_options():
	"""Build the customization list on the left panel"""
	sections.clear()
	for i in range(LAYERS.size()):
		var layer = LAYERS[i]
		var section = create_layer_section(layer, i)

		# Add to appropriate column
		# Layers 0-5 (Skin Tone to Handwear) go to left column
		# Layers 6-10 (Overwear to Headwear) go to right column
		if i <= 5:
			left_column.add_child(section)
		else:
			right_column.add_child(section)

		# Track section by index for navigation
		sections.append(section)

	# Add Accept button at the end of right column
	add_accept_button()

func create_layer_section(layer: Dictionary, layer_index: int) -> VBoxContainer:
	"""Create a customization section for a layer"""
	var section = VBoxContainer.new()
	section.name = layer.code + "_Section"

	# Layer label
	var label = Label.new()
	label.text = layer.label
	label.add_theme_font_size_override("font_size", 14)  # Reduced from 18
	label.add_theme_color_override("font_color", Color("#8A3FFC"))  # Grape Violet
	section.add_child(label)

	# Part selector with Change button (if layer has parts)
	if layer.has_parts:
		var part_container = HBoxContainer.new()
		part_container.name = "PartContainer"

		# Change button
		var change_btn = Button.new()
		change_btn.name = "PartChangeButton"
		change_btn.text = "Change"
		change_btn.custom_minimum_size = Vector2(80, 15)  # Only 15px tall
		change_btn.add_theme_font_size_override("font_size", 8)  # 8pt font
		change_btn.focus_mode = Control.FOCUS_ALL
		change_btn.pressed.connect(_on_toggle_activated.bind(layer_index, "part"))
		part_container.add_child(change_btn)

		# Left arrow
		var left_arrow = Button.new()
		left_arrow.name = "LeftArrow"
		left_arrow.text = "◀"
		left_arrow.custom_minimum_size = Vector2(20, 0)  # Even smaller
		left_arrow.pressed.connect(_on_part_previous.bind(layer_index))
		part_container.add_child(left_arrow)

		# Current selection label
		var selection_label = Label.new()
		selection_label.name = "PartLabel"
		selection_label.text = "None"
		selection_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		selection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		selection_label.custom_minimum_size = Vector2(200, 0)
		selection_label.add_theme_font_size_override("font_size", 12)  # Reduced from 16
		selection_label.add_theme_color_override("font_color", Color("#4DE9FF"))  # Sky Cyan
		part_container.add_child(selection_label)

		# Right arrow
		var right_arrow = Button.new()
		right_arrow.name = "RightArrow"
		right_arrow.text = "▶"
		right_arrow.custom_minimum_size = Vector2(20, 0)  # Even smaller
		right_arrow.pressed.connect(_on_part_next.bind(layer_index))
		part_container.add_child(right_arrow)

		section.add_child(part_container)

	# Color selector with Change button to the left
	var color_container = HBoxContainer.new()
	color_container.name = "ColorContainer"

	# Change button
	var color_change_btn = Button.new()
	color_change_btn.name = "ColorChangeButton"
	color_change_btn.text = "Change"
	color_change_btn.custom_minimum_size = Vector2(80, 15)  # Only 15px tall
	color_change_btn.add_theme_font_size_override("font_size", 8)  # 8pt font
	color_change_btn.focus_mode = Control.FOCUS_ALL
	color_change_btn.pressed.connect(_on_toggle_activated.bind(layer_index, "color"))
	color_container.add_child(color_change_btn)

	# Color bar container with arrows
	var color_bar_container = VBoxContainer.new()
	color_bar_container.name = "ColorBarContainer"

	# Color strip with left/right arrows
	var color_strip_row = HBoxContainer.new()
	color_strip_row.name = "ColorStripRow"

	# Left arrow
	var left_arrow = Button.new()
	left_arrow.name = "LeftArrow"
	left_arrow.text = "◀"
	left_arrow.custom_minimum_size = Vector2(20, 0)
	left_arrow.focus_mode = Control.FOCUS_NONE
	left_arrow.pressed.connect(_on_color_previous.bind(layer_index))
	color_strip_row.add_child(left_arrow)

	# Color slider with gradient background
	var palette_image = get_palette_image(layer.ramp_type)
	var num_colors = min(layer.max_colors, palette_image.get_height() / 2 if palette_image else 0)

	# Container to layer gradient and slider
	var slider_container = Control.new()
	slider_container.name = "SliderContainer"
	slider_container.custom_minimum_size = Vector2(200, 20)
	slider_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Create gradient background
	if palette_image and num_colors > 0:
		var gradient = Gradient.new()

		# Sample colors from palette and add to gradient
		for i in range(num_colors):
			var color = palette_image.get_pixel(4, i * 2)  # 3rd color from palette
			var offset = float(i) / float(num_colors - 1) if num_colors > 1 else 0.0
			gradient.add_point(offset, color)

		# Create gradient texture
		var gradient_texture = GradientTexture2D.new()
		gradient_texture.gradient = gradient
		gradient_texture.width = 200
		gradient_texture.height = 20
		gradient_texture.fill_from = Vector2(0, 0.5)
		gradient_texture.fill_to = Vector2(1, 0.5)

		# Create TextureRect to display gradient
		var gradient_rect = TextureRect.new()
		gradient_rect.texture = gradient_texture
		gradient_rect.custom_minimum_size = Vector2(200, 20)
		gradient_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gradient_rect.stretch_mode = TextureRect.STRETCH_SCALE
		slider_container.add_child(gradient_rect)

	# Create slider on top of gradient
	var color_slider = HSlider.new()
	color_slider.name = "ColorSlider"
	color_slider.custom_minimum_size = Vector2(200, 20)
	color_slider.min_value = 0
	color_slider.max_value = num_colors - 1 if num_colors > 0 else 0
	color_slider.step = 1
	color_slider.value = current_colors.get(layer.code, 0)
	color_slider.focus_mode = Control.FOCUS_NONE
	color_slider.value_changed.connect(_on_color_slider_changed.bind(layer_index))
	slider_container.add_child(color_slider)

	color_strip_row.add_child(slider_container)

	# Right arrow
	var right_arrow = Button.new()
	right_arrow.name = "RightArrow"
	right_arrow.text = "▶"
	right_arrow.custom_minimum_size = Vector2(20, 0)
	right_arrow.focus_mode = Control.FOCUS_NONE
	right_arrow.pressed.connect(_on_color_next.bind(layer_index))
	color_strip_row.add_child(right_arrow)

	color_bar_container.add_child(color_strip_row)
	color_container.add_child(color_bar_container)
	section.add_child(color_container)

	# Separator
	var separator = HSeparator.new()
	section.add_child(separator)

	return section

func add_accept_button():
	"""Add the Accept button at the end of the right column"""
	# Create a centered container for the button
	var button_container = CenterContainer.new()
	button_container.name = "AcceptButtonContainer"

	# Create the Accept button
	var accept_btn = Button.new()
	accept_btn.name = "AcceptButton"
	accept_btn.text = "Accept"
	accept_btn.custom_minimum_size = Vector2(150, 40)
	accept_btn.focus_mode = Control.FOCUS_NONE  # Not controller-focusable, handled via navigation
	accept_btn.pressed.connect(_on_accept_pressed)

	# Create rounded style with Electric Lime border
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.8)  # Dark semi-transparent background
	style.border_color = Color("#C8FF3D")  # Electric Lime
	style.set_border_width_all(3)
	style.set_corner_radius_all(10)  # Rounded corners

	# Create focus style with Electric Lime background
	var focus_style = StyleBoxFlat.new()
	focus_style.bg_color = Color("#C8FF3D")  # Electric Lime background
	focus_style.border_color = Color("#C8FF3D")  # Electric Lime
	focus_style.set_border_width_all(3)
	focus_style.set_corner_radius_all(10)  # Rounded corners

	accept_btn.add_theme_stylebox_override("normal", style)
	accept_btn.add_theme_stylebox_override("hover", style)
	accept_btn.add_theme_stylebox_override("pressed", style)
	accept_btn.add_theme_color_override("font_color", Color("#C8FF3D"))  # Electric Lime text
	accept_btn.add_theme_font_size_override("font_size", 16)

	button_container.add_child(accept_btn)
	right_column.add_child(button_container)

	# Store references for navigation
	accept_button = accept_btn
	accept_button_normal_style = style
	accept_button_active_style = focus_style

func _on_accept_pressed():
	"""Handle Accept button press"""
	print("Character accepted!")
	# TODO: Save character data or transition to next scene

func get_palette_image(ramp_type: String) -> Image:
	"""Get the palette image for a ramp type"""
	return palette_images.get(ramp_type, null)

func set_default_character():
	"""Set up default character - naked with just body"""
	# Set default body color
	current_colors["01body"] = 0

	# Initialize all part indices to -1 (None) so character starts naked
	for layer in LAYERS:
		if layer.has_parts:
			current_part_indices[layer.code] = -1

	# Activate the first toggle (Skin Tone color) by default so left/right works immediately
	active_toggle_layer = 0  # First layer (Skin Tone)
	active_toggle_type = "color"  # Color toggle

func _on_animation_selected(anim_name: String):
	"""Handle animation selection"""
	current_animation = anim_name
	current_frame_index = 0
	animation_timer = 0.0
	update_animation_label()

func _on_direction_selected(direction: String):
	"""Handle direction selection"""
	current_direction = direction
	current_frame_index = 0
	animation_timer = 0.0
	update_direction_label()

func _on_animation_previous():
	"""Cycle to previous animation"""
	var current_idx = ANIMATIONS.find(current_animation)
	if current_idx == -1:
		current_idx = 0
	else:
		current_idx -= 1
		if current_idx < 0:
			current_idx = ANIMATIONS.size() - 1

	current_animation = ANIMATIONS[current_idx]
	current_frame_index = 0
	animation_timer = 0.0
	update_animation_label()
	flash_button("L1")

func _on_animation_next():
	"""Cycle to next animation"""
	var current_idx = ANIMATIONS.find(current_animation)
	if current_idx == -1:
		current_idx = 0
	else:
		current_idx += 1
		if current_idx >= ANIMATIONS.size():
			current_idx = 0

	current_animation = ANIMATIONS[current_idx]
	current_frame_index = 0
	animation_timer = 0.0
	update_animation_label()
	flash_button("R1")

func _on_direction_previous():
	"""Cycle to previous direction"""
	var current_idx = DIRECTIONS.find(current_direction)
	if current_idx == -1:
		current_idx = 0
	else:
		current_idx -= 1
		if current_idx < 0:
			current_idx = DIRECTIONS.size() - 1

	current_direction = DIRECTIONS[current_idx]
	current_frame_index = 0
	animation_timer = 0.0
	update_direction_label()
	flash_button("L2")

func _on_direction_next():
	"""Cycle to next direction"""
	var current_idx = DIRECTIONS.find(current_direction)
	if current_idx == -1:
		current_idx = 0
	else:
		current_idx += 1
		if current_idx >= DIRECTIONS.size():
			current_idx = 0

	current_direction = DIRECTIONS[current_idx]
	current_frame_index = 0
	animation_timer = 0.0
	update_direction_label()
	flash_button("R2")

func update_animation_label():
	"""Update the animation label text"""
	var label_container = $MarginContainer/MainContainer/RightPanel.get_node_or_null("AnimationLabelContainer")
	if label_container:
		var label = label_container.get_node_or_null("AnimationLabel")
		if label:
			label.text = "Animation: " + current_animation

func update_direction_label():
	"""Update the direction label text"""
	var label_container = $MarginContainer/MainContainer/RightPanel.get_node_or_null("DirectionLabelContainer")
	if label_container:
		var label = label_container.get_node_or_null("DirectionLabel")
		if label:
			label.text = "Direction: " + current_direction

func flash_button(button_name: String):
	"""Flash a button with Bubble Magenta highlight"""
	var button = null

	match button_name:
		"L1":
			button = $MarginContainer/MainContainer/RightPanel/AnimationLabelContainer/L1Button
		"R1":
			button = $MarginContainer/MainContainer/RightPanel/AnimationLabelContainer/R1Button
		"L2":
			button = $MarginContainer/MainContainer/RightPanel/DirectionLabelContainer/L2Button
		"R2":
			button = $MarginContainer/MainContainer/RightPanel/DirectionLabelContainer/R2Button

	if button:
		# Flash with Bubble Magenta
		button.modulate = Color("#FF4AD9")  # Bubble Magenta
		# Create a tween to fade back to white
		var tween = create_tween()
		tween.tween_property(button, "modulate", Color.WHITE, 0.3)

func _on_part_previous(layer_index: int):
	"""Cycle to previous part"""
	var layer = LAYERS[layer_index]
	if layer.code not in available_parts:
		return

	var parts = available_parts[layer.code]
	if parts.size() == 0:
		return

	# Get current index (default to -1 for "None")
	var current_index = current_part_indices.get(layer.code, -1)

	# Cycle backwards (None -> Last -> ... -> First -> None)
	current_index -= 1
	if current_index < -1:
		current_index = parts.size() - 1

	# Update selection
	current_part_indices[layer.code] = current_index
	if current_index == -1:
		current_selections.erase(layer.code)
	else:
		current_selections[layer.code] = parts[current_index]

	# Update label
	update_part_label(layer_index)
	update_preview()

func _on_part_next(layer_index: int):
	"""Cycle to next part"""
	var layer = LAYERS[layer_index]
	if layer.code not in available_parts:
		return

	var parts = available_parts[layer.code]
	if parts.size() == 0:
		return

	# Get current index (default to -1 for "None")
	var current_index = current_part_indices.get(layer.code, -1)

	# Cycle forwards (None -> First -> ... -> Last -> None)
	current_index += 1
	if current_index >= parts.size():
		current_index = -1

	# Update selection
	current_part_indices[layer.code] = current_index
	if current_index == -1:
		current_selections.erase(layer.code)
	else:
		current_selections[layer.code] = parts[current_index]

	# Update label
	update_part_label(layer_index)
	update_preview()

func update_part_label(layer_index: int):
	"""Update the part selection label text"""
	var layer = LAYERS[layer_index]
	var section = sections[layer_index]
	var part_container = section.get_node_or_null("PartContainer")
	if not part_container:
		return

	var part_label = part_container.get_node("PartLabel")
	var current_index = current_part_indices.get(layer.code, -1)

	if current_index == -1:
		part_label.text = "None"
	else:
		var parts = available_parts[layer.code]
		if current_index < parts.size():
			part_label.text = parts[current_index].display_name
		else:
			part_label.text = "None"

func _on_color_slider_changed(value: float, layer_index: int):
	"""Handle color slider value change"""
	var layer = LAYERS[layer_index]
	current_colors[layer.code] = int(value)
	update_preview()

func _on_color_previous(layer_index: int):
	"""Cycle to previous color"""
	var layer = LAYERS[layer_index]
	var color_index = current_colors.get(layer.code, 0)
	color_index -= 1
	if color_index < 0:
		color_index = layer.max_colors - 1
	current_colors[layer.code] = color_index

	# Update slider
	var section = sections[layer_index]
	var color_container = section.get_node("ColorContainer")
	var color_bar_container = color_container.get_node("ColorBarContainer")
	var color_strip_row = color_bar_container.get_node("ColorStripRow")
	var slider_container = color_strip_row.get_node("SliderContainer")
	var slider = slider_container.get_node("ColorSlider")
	slider.value = color_index

	update_preview()
	update_focus_visual()

func _on_color_next(layer_index: int):
	"""Cycle to next color"""
	var layer = LAYERS[layer_index]
	var color_index = current_colors.get(layer.code, 0)
	color_index += 1
	if color_index >= layer.max_colors:
		color_index = 0
	current_colors[layer.code] = color_index

	# Update slider
	var section = sections[layer_index]
	var color_container = section.get_node("ColorContainer")
	var color_bar_container = color_container.get_node("ColorBarContainer")
	var color_strip_row = color_bar_container.get_node("ColorStripRow")
	var slider_container = color_strip_row.get_node("SliderContainer")
	var slider = slider_container.get_node("ColorSlider")
	slider.value = color_index

	update_preview()
	update_focus_visual()

func _on_toggle_activated(layer_index: int, toggle_type: String):
	"""Handle Change button toggle - only one can be active at a time"""
	# If clicking the same toggle, deactivate it
	if active_toggle_layer == layer_index and active_toggle_type == toggle_type:
		active_toggle_layer = -1
		active_toggle_type = ""
	else:
		# Activate this toggle, deactivate all others
		active_toggle_layer = layer_index
		active_toggle_type = toggle_type

	update_focus_visual()


func update_preview():
	"""Update character preview"""
	for layer in LAYERS:
		var layer_code = layer.code

		# Get sprite codes (single or multiple for combined layers)
		var sprite_codes = []
		if "sprite_layers" in layer:
			sprite_codes = layer.sprite_layers
		else:
			sprite_codes = [layer_code]

		# Get selected part (or body for body layer)
		var part = null
		if layer.has_parts:
			part = current_selections.get(layer_code, null)
		else:
			# Body layer - load default body sprite
			if layer_code == "01body":
				var body_parts = available_parts.get(layer_code, [])
				if body_parts.size() > 0:
					part = body_parts[0]

		# Apply to all sprite nodes for this layer
		for sprite_code in sprite_codes:
			var sprite = character_preview.get_node_or_null(sprite_code)
			if not sprite:
				continue

			# If no part selected, clear the sprite
			if part == null:
				sprite.texture = null
				continue

			# For combined layers (like footwear), only apply if the part belongs to this sprite layer
			if "sprite_layers" in layer:
				if part.sprite_code != sprite_code:
					sprite.texture = null
					continue

			# Load texture
			var original_texture = load(part.path)

			# Apply color mapping if color is selected
			if layer_code in current_colors:
				var color_index = current_colors[layer_code]
				var recolored_texture = apply_color_mapping(original_texture, part, layer.ramp_type, color_index)
				sprite.texture = recolored_texture
			else:
				sprite.texture = original_texture

		# Auto-match layer (e.g., apply matching underwear for neckwear)
		if "auto_match_layer" in layer and part != null:
			var auto_layer_code = layer.auto_match_layer
			var auto_sprite = character_preview.get_node_or_null(auto_layer_code)

			if auto_sprite:
				# Find matching part by base_name in the auto-match layer
				var matching_part = null
				if auto_layer_code in available_parts:
					for auto_part in available_parts[auto_layer_code]:
						if auto_part.base_name == part.base_name:
							matching_part = auto_part
							break

				if matching_part != null:
					# Load and apply matching texture with same color
					var auto_texture = load(matching_part.path)
					if layer_code in current_colors:
						var color_index = current_colors[layer_code]
						var recolored_texture = apply_color_mapping(auto_texture, matching_part, layer.ramp_type, color_index)
						auto_sprite.texture = recolored_texture
					else:
						auto_sprite.texture = auto_texture
				else:
					# No matching part, clear the auto-match sprite
					auto_sprite.texture = null
		# Clear auto-match layer if main layer has no selection
		elif "auto_match_layer" in layer and part == null:
			var auto_layer_code = layer.auto_match_layer
			var auto_sprite = character_preview.get_node_or_null(auto_layer_code)
			if auto_sprite:
				auto_sprite.texture = null

func apply_color_mapping(original_texture: Texture2D, part: Dictionary, ramp_type: String, color_index: int) -> ImageTexture:
	"""Apply color mapping to a texture (with caching for performance)"""
	# Create cache key from part path and color index
	var cache_key = part.path + ":" + str(color_index)

	# Check if already cached
	if cache_key in texture_cache:
		return texture_cache[cache_key]

	# Not cached - create the recolored texture
	var original_image = original_texture.get_image()
	var recolored_image = Image.create(original_image.get_width(), original_image.get_height(), false, original_image.get_format())
	recolored_image.copy_from(original_image)

	var palette_code = part.palette_code
	var base_colors = get_base_colors_for_palette_code(palette_code, ramp_type)
	var target_colors = get_target_colors_for_palette_code(palette_code, ramp_type, color_index)

	if base_colors.size() == 0 or target_colors.size() == 0:
		var result = ImageTexture.create_from_image(recolored_image)
		texture_cache[cache_key] = result
		return result

	# Pixel-by-pixel color replacement (CPU-based)
	for y in range(recolored_image.get_height()):
		for x in range(recolored_image.get_width()):
			var pixel = recolored_image.get_pixel(x, y)
			if pixel.a < 0.01:
				continue

			# Check against each base color
			for i in range(min(base_colors.size(), target_colors.size())):
				if colors_match(pixel, base_colors[i]):
					recolored_image.set_pixel(x, y, Color(target_colors[i].r, target_colors[i].g, target_colors[i].b, pixel.a))
					break

	# Cache the result before returning
	var result = ImageTexture.create_from_image(recolored_image)
	texture_cache[cache_key] = result
	return result

func get_base_colors_for_palette_code(palette_code: String, ramp_type: String) -> Array:
	"""Get base colors based on palette code"""
	var base_ramp_filename = ""

	match palette_code:
		"00a":
			base_ramp_filename = "3-color base ramp (00a).png"
		"00b":
			base_ramp_filename = "4-color base ramp (00b).png"
		"00c":
			base_ramp_filename = "2x 3-color base ramps (00c).png"
		"00d":
			base_ramp_filename = "4-color + 3-color base ramps (00d).png"
		"00f":
			base_ramp_filename = "4-color base ramp (00b).png"
		"00":
			if ramp_type == "skin":
				base_ramp_filename = "skin color base ramp.png"
			elif ramp_type == "hair":
				base_ramp_filename = "hair color base ramp.png"
		_:
			if ramp_type == "skin":
				base_ramp_filename = "skin color base ramp.png"
			elif ramp_type == "hair":
				base_ramp_filename = "hair color base ramp.png"
			elif ramp_type == "3color":
				base_ramp_filename = "3-color base ramp (00a).png"
			elif ramp_type == "4color":
				base_ramp_filename = "4-color base ramp (00b).png"

	if base_ramp_filename == "":
		return []

	var base_ramp_path = PALETTE_PATH + "base ramps/" + base_ramp_filename
	if not FileAccess.file_exists(base_ramp_path):
		return []

	var texture = load(base_ramp_path)
	if texture == null:
		return []

	var image = texture.get_image()
	var colors = []

	# Read colors from 2x2 blocks
	var num_colors = image.get_width() / 2
	for i in range(num_colors):
		var x = i * 2
		var pixel_color = image.get_pixel(x, 0)
		colors.append(pixel_color)

	return colors

func get_target_colors_for_palette_code(palette_code: String, ramp_type: String, row_index: int) -> Array:
	"""Get target colors for a specific palette row"""
	match palette_code:
		"00a":
			return extract_colors_from_palette("3color", row_index)
		"00b":
			return extract_colors_from_palette("4color", row_index)
		"00c":
			var colors_3 = extract_colors_from_palette("3color", row_index)
			if colors_3.size() >= 3:
				return colors_3 + colors_3
			return colors_3
		"00d":
			var colors_4 = extract_colors_from_palette("4color", row_index)
			var colors_3 = extract_colors_from_palette("3color", row_index)
			return colors_4 + colors_3
		"00f":
			var colors_4 = extract_colors_from_palette("4color", row_index)
			var colors_hair = extract_colors_from_palette("hair", row_index)
			return colors_4 + colors_hair
		"00":
			return extract_colors_from_palette(ramp_type, row_index)
		_:
			return extract_colors_from_palette(ramp_type, row_index)

func extract_colors_from_palette(ramp_type: String, row_index: int) -> Array:
	"""Extract colors from a specific row of a palette image"""
	if ramp_type not in palette_images:
		return []

	var image = palette_images[ramp_type]
	var colors = []

	var colors_per_row = 3
	match ramp_type:
		"3color":
			colors_per_row = 3
		"4color":
			colors_per_row = 4
		"hair":
			colors_per_row = 5
		"skin":
			colors_per_row = 4

	# Read colors from 2x2 blocks
	for i in range(colors_per_row):
		var x = i * 2
		var y = row_index * 2
		var pixel_color = image.get_pixel(x, y)
		colors.append(pixel_color)

	return colors

func colors_match(c1: Color, c2: Color, tolerance: float = 0.01) -> bool:
	"""Check if two colors match within tolerance"""
	return abs(c1.r - c2.r) < tolerance and abs(c1.g - c2.g) < tolerance and abs(c1.b - c2.b) < tolerance

# ========== CONTROLLER NAVIGATION ==========

func handle_accept():
	"""Handle accept/confirm button - trigger Accept button if active"""
	if active_toggle_type == "accept" and accept_button:
		accept_button.pressed.emit()

func handle_back():
	"""Handle back/cancel button - deactivate current toggle"""
	if active_toggle_layer != -1:
		active_toggle_layer = -1
		active_toggle_type = ""
		update_focus_visual()

func handle_up():
	"""Handle up navigation - activate previous toggle"""
	# Build list of all toggles in order
	var toggles = []
	for i in range(LAYERS.size()):
		var layer = LAYERS[i]
		if layer.has_parts:
			toggles.append({"layer": i, "type": "part"})
		toggles.append({"layer": i, "type": "color"})

	# Add Accept button at the end
	toggles.append({"layer": LAYERS.size(), "type": "accept"})

	# Find current toggle index
	var current_idx = -1
	for i in range(toggles.size()):
		if toggles[i].layer == active_toggle_layer and toggles[i].type == active_toggle_type:
			current_idx = i
			break

	# Move to previous (wrap around)
	var new_idx = current_idx - 1
	if new_idx < 0:
		new_idx = toggles.size() - 1

	active_toggle_layer = toggles[new_idx].layer
	active_toggle_type = toggles[new_idx].type

	update_focus_visual()
	ensure_section_visible()

func handle_down():
	"""Handle down navigation - activate next toggle"""
	# Build list of all toggles in order
	var toggles = []
	for i in range(LAYERS.size()):
		var layer = LAYERS[i]
		if layer.has_parts:
			toggles.append({"layer": i, "type": "part"})
		toggles.append({"layer": i, "type": "color"})

	# Add Accept button at the end
	toggles.append({"layer": LAYERS.size(), "type": "accept"})

	# Find current toggle index
	var current_idx = -1
	for i in range(toggles.size()):
		if toggles[i].layer == active_toggle_layer and toggles[i].type == active_toggle_type:
			current_idx = i
			break

	# Move to next (wrap around)
	var new_idx = current_idx + 1
	if new_idx >= toggles.size():
		new_idx = 0

	active_toggle_layer = toggles[new_idx].layer
	active_toggle_type = toggles[new_idx].type

	update_focus_visual()
	ensure_section_visible()

func handle_left():
	"""Handle left navigation - control active toggle's selection"""
	if active_toggle_layer == -1:
		return

	if active_toggle_type == "part":
		_on_part_previous(active_toggle_layer)
	elif active_toggle_type == "color":
		_on_color_previous(active_toggle_layer)

func handle_right():
	"""Handle right navigation - control active toggle's selection"""
	if active_toggle_layer == -1:
		return

	if active_toggle_type == "part":
		_on_part_next(active_toggle_layer)
	elif active_toggle_type == "color":
		_on_color_next(active_toggle_layer)

func update_focus_visual():
	"""Update visual indicators for current focus"""
	# Clear all focus indicators first
	for i in range(LAYERS.size()):
		var section = sections[i]

		# Clear part button
		var part_container = section.get_node_or_null("PartContainer")
		if part_container:
			var part_btn = part_container.get_node("PartChangeButton")
			part_btn.modulate = Color.WHITE

		# Clear color button
		var color_container = section.get_node_or_null("ColorContainer")
		if color_container:
			var color_btn = color_container.get_node("ColorChangeButton")
			color_btn.modulate = Color.WHITE

	# Clear Accept button to normal state
	if accept_button and accept_button_normal_style:
		accept_button.add_theme_stylebox_override("normal", accept_button_normal_style)
		accept_button.add_theme_color_override("font_color", Color("#C8FF3D"))

	# Highlight active toggle if one is active
	if active_toggle_layer != -1:
		if active_toggle_type == "accept":
			# Apply active style to Accept button
			if accept_button and accept_button_active_style:
				accept_button.add_theme_stylebox_override("normal", accept_button_active_style)
				accept_button.add_theme_color_override("font_color", Color.BLACK)
		else:
			var active_section = sections[active_toggle_layer]

			if active_toggle_type == "part":
				var part_container = active_section.get_node("PartContainer")
				var part_btn = part_container.get_node("PartChangeButton")
				part_btn.modulate = Color(0.5, 1.5, 0.5)  # Green highlight (active)

			elif active_toggle_type == "color":
				var color_container = active_section.get_node("ColorContainer")
				var color_btn = color_container.get_node("ColorChangeButton")
				color_btn.modulate = Color(0.5, 1.5, 0.5)  # Green highlight (active)

func ensure_section_visible():
	"""Scroll to keep the active section visible"""
	if active_toggle_layer < 0 or active_toggle_layer >= sections.size():
		return

	var active_section = sections[active_toggle_layer]
	var section_pos = active_section.position.y
	var section_height = active_section.size.y

	var scroll_pos = scroll_container.scroll_vertical
	var viewport_height = scroll_container.size.y

	# Scroll down if section is below viewport
	if section_pos + section_height > scroll_pos + viewport_height:
		scroll_container.scroll_vertical = section_pos + section_height - viewport_height

	# Scroll up if section is above viewport
	elif section_pos < scroll_pos:
		scroll_container.scroll_vertical = section_pos

# ========== END CONTROLLER NAVIGATION ==========

func _process(delta):
	"""Handle animation playback"""
	if current_animation not in animations:
		return
	if current_direction not in animations[current_animation]:
		return

	var anim_data = animations[current_animation][current_direction]
	var times = anim_data.times

	if current_frame_index >= times.size():
		return

	var current_time = times[current_frame_index]

	# Handle "hold" frames - treat as 500ms hold then loop
	if current_time < 0:
		animation_timer += delta * 1000.0
		if animation_timer >= 500.0:  # Hold for 500ms then loop
			animation_timer = 0.0
			current_frame_index = 0  # Loop back to start
			var frame_data = anim_data.frames[current_frame_index]
			for layer in LAYERS:
				# Get actual sprite codes (handle sprite_layers for combined layers)
				var sprite_codes = []
				if "sprite_layers" in layer:
					sprite_codes = layer.sprite_layers
				else:
					sprite_codes = [layer.code]

				# Update all sprite nodes for this layer
				for sprite_code in sprite_codes:
					var sprite = character_preview.get_node_or_null(sprite_code)
					if sprite:
						sprite.frame = frame_data.cell
						sprite.flip_h = frame_data.flip

				# Also update auto-match layer if it exists (like 00undr for neckwear)
				if "auto_match_layer" in layer:
					var auto_sprite = character_preview.get_node_or_null(layer.auto_match_layer)
					if auto_sprite:
						auto_sprite.frame = frame_data.cell
						auto_sprite.flip_h = frame_data.flip
		return

	animation_timer += delta * 1000.0  # Convert to milliseconds

	if animation_timer >= current_time:
		animation_timer = 0.0
		current_frame_index += 1

		# Loop animation
		if current_frame_index >= anim_data.total_frames:
			current_frame_index = 0

		# Update sprite frames
		var frame_data = anim_data.frames[current_frame_index]
		for layer in LAYERS:
			# Get actual sprite codes (handle sprite_layers for combined layers)
			var sprite_codes = []
			if "sprite_layers" in layer:
				sprite_codes = layer.sprite_layers
			else:
				sprite_codes = [layer.code]

			# Update all sprite nodes for this layer
			for sprite_code in sprite_codes:
				var sprite = character_preview.get_node_or_null(sprite_code)
				if sprite:
					sprite.frame = frame_data.cell
					sprite.flip_h = frame_data.flip

			# Also update auto-match layer if it exists (like 00undr for neckwear)
			if "auto_match_layer" in layer:
				var auto_sprite = character_preview.get_node_or_null(layer.auto_match_layer)
				if auto_sprite:
					auto_sprite.frame = frame_data.cell
					auto_sprite.flip_h = frame_data.flip
