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
	{"code": "03fot1", "label": "Footwear", "ramp_type": "3color", "max_colors": 48, "has_parts": true},
	{"code": "04lwr1", "label": "Bottomwear", "ramp_type": "3color", "max_colors": 48, "has_parts": true},
	{"code": "05shrt", "label": "Topwear", "ramp_type": "3color", "max_colors": 48, "has_parts": true},
	{"code": "09hand", "label": "Handwear", "ramp_type": "3color", "max_colors": 48, "has_parts": true},
	{"code": "10outr", "label": "Overwear", "ramp_type": "3color", "max_colors": 48, "has_parts": true},
	{"code": "11neck", "label": "Neckwear", "ramp_type": "4color", "max_colors": 59, "has_parts": true},
	{"code": "12face", "label": "Eyewear", "ramp_type": "3color", "max_colors": 48, "has_parts": true},
	{"code": "13hair", "label": "Hairstyle", "ramp_type": "hair", "max_colors": 58, "has_parts": true},
	{"code": "14head", "label": "Headwear", "ramp_type": "4color", "max_colors": 59, "has_parts": true}
]

# Animation options
const ANIMATIONS = ["Idle", "Walk", "Run", "Jump"]
const DIRECTIONS = ["DOWN", "UP", "LEFT", "RIGHT"]

# UI References
@onready var character_preview = $MarginContainer/MainContainer/RightPanel/PreviewContainer/CharacterLayers
@onready var animation_buttons_container = $MarginContainer/MainContainer/RightPanel/AnimationButtons
@onready var direction_buttons_container = $MarginContainer/MainContainer/RightPanel/DirectionButtons
@onready var customization_container = $MarginContainer/MainContainer/LeftPanel/PaddingContainer/ScrollContainer/CustomizationList
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

# Navigation state
var current_layer_index = 0  # Which layer section is focused
var navigation_mode = "normal"  # "normal", "part_selection", "color_selection"
var focused_element = "part"  # "part" or "color" - which Change button is focused

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
		var layer_path = SPRITE_PATH + layer_code + "/"
		var dir = DirAccess.open(layer_path)

		if dir == null:
			print("  Layer ", layer_code, ": not found")
			continue

		if layer_code not in available_parts:
			available_parts[layer_code] = []

		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if file_name.ends_with(".png") and file_name.begins_with("fbas_"):
				var full_path = layer_path + file_name
				var part_info = parse_filename(file_name, layer_code)
				part_info["path"] = full_path
				available_parts[layer_code].append(part_info)
			file_name = dir.get_next()
		dir.list_dir_end()

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
	# Animation buttons (Walk/Run/Jump)
	for anim in ANIMATIONS:
		var btn = Button.new()
		btn.text = anim
		btn.focus_mode = Control.FOCUS_ALL  # Make controller-selectable
		btn.pressed.connect(_on_animation_selected.bind(anim))
		animation_buttons_container.add_child(btn)

	# Direction arrows
	for dir in DIRECTIONS:
		var btn = Button.new()
		match dir:
			"UP": btn.text = "↑"
			"DOWN": btn.text = "↓"
			"LEFT": btn.text = "←"
			"RIGHT": btn.text = "→"
		btn.focus_mode = Control.FOCUS_ALL  # Make controller-selectable
		btn.pressed.connect(_on_direction_selected.bind(dir))
		direction_buttons_container.add_child(btn)

func build_customization_options():
	"""Build the customization list on the left panel"""
	for i in range(LAYERS.size()):
		var layer = LAYERS[i]
		var section = create_layer_section(layer, i)
		customization_container.add_child(section)

func create_layer_section(layer: Dictionary, layer_index: int) -> VBoxContainer:
	"""Create a customization section for a layer"""
	var section = VBoxContainer.new()
	section.name = layer.code + "_Section"

	# Layer label
	var label = Label.new()
	label.text = layer.label
	label.add_theme_font_size_override("font_size", 18)
	section.add_child(label)

	# Part selector with Change button (if layer has parts)
	if layer.has_parts:
		var part_container = HBoxContainer.new()
		part_container.name = "PartContainer"

		# Change button
		var change_btn = Button.new()
		change_btn.name = "PartChangeButton"
		change_btn.text = "Change"
		change_btn.custom_minimum_size = Vector2(80, 40)
		change_btn.focus_mode = Control.FOCUS_ALL
		part_container.add_child(change_btn)

		# Current selection label
		var selection_label = Label.new()
		selection_label.name = "PartLabel"
		selection_label.text = "None"
		selection_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		selection_label.add_theme_font_size_override("font_size", 16)
		part_container.add_child(selection_label)

		section.add_child(part_container)

	# Color selector with Change button and slider
	var color_container = VBoxContainer.new()
	color_container.name = "ColorContainer"

	# Change button row
	var color_change_row = HBoxContainer.new()
	color_change_row.name = "ColorChangeRow"

	var color_change_btn = Button.new()
	color_change_btn.name = "ColorChangeButton"
	color_change_btn.text = "Change"
	color_change_btn.custom_minimum_size = Vector2(80, 40)
	color_change_btn.focus_mode = Control.FOCUS_ALL
	color_change_row.add_child(color_change_btn)

	var color_label = Label.new()
	color_label.name = "ColorLabel"
	color_label.text = layer.label + " Color"
	color_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	color_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_change_row.add_child(color_label)

	color_container.add_child(color_change_row)

	# Color bar container with arrows
	var color_bar_container = VBoxContainer.new()
	color_bar_container.name = "ColorBarContainer"

	# Position indicator (small arrow pointing down)
	var indicator_row = HBoxContainer.new()
	indicator_row.name = "IndicatorRow"
	indicator_row.custom_minimum_size = Vector2(0, 20)

	var indicator_left_spacer = Control.new()
	indicator_left_spacer.name = "IndicatorLeftSpacer"
	indicator_left_spacer.custom_minimum_size = Vector2(40, 20)  # Match left arrow width
	indicator_row.add_child(indicator_left_spacer)

	var indicator_position_spacer = Control.new()
	indicator_position_spacer.name = "IndicatorPositionSpacer"
	indicator_position_spacer.custom_minimum_size = Vector2(0, 20)
	indicator_row.add_child(indicator_position_spacer)

	var indicator_label = Label.new()
	indicator_label.name = "IndicatorLabel"
	indicator_label.text = "▼"
	indicator_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	indicator_row.add_child(indicator_label)

	color_bar_container.add_child(indicator_row)

	# Color strip with left/right arrows
	var color_strip_row = HBoxContainer.new()
	color_strip_row.name = "ColorStripRow"

	# Left arrow
	var left_arrow = Button.new()
	left_arrow.name = "LeftArrow"
	left_arrow.text = "◀"
	left_arrow.custom_minimum_size = Vector2(40, 40)
	color_strip_row.add_child(left_arrow)

	# Color strip (fixed 300px width)
	var color_strip = HBoxContainer.new()
	color_strip.name = "ColorStrip"
	color_strip.custom_minimum_size = Vector2(300, 40)

	var palette_image = get_palette_image(layer.ramp_type)
	var num_colors = min(layer.max_colors, palette_image.get_height() / 2 if palette_image else 0)
	var block_width = 300.0 / num_colors if num_colors > 0 else 20.0

	for i in range(num_colors):
		var color_block = Panel.new()
		color_block.name = "ColorBlock_" + str(i)
		color_block.custom_minimum_size = Vector2(block_width, 40)
		color_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Add color preview
		if palette_image:
			var preview_color = palette_image.get_pixel(4, i * 2)  # 3rd color
			var style = StyleBoxFlat.new()
			style.bg_color = preview_color
			style.border_color = Color.BLACK
			style.border_width_left = 1
			style.border_width_right = 1
			style.border_width_top = 1
			style.border_width_bottom = 1
			color_block.add_theme_stylebox_override("panel", style)

		color_strip.add_child(color_block)

	color_strip_row.add_child(color_strip)

	# Right arrow
	var right_arrow = Button.new()
	right_arrow.name = "RightArrow"
	right_arrow.text = "▶"
	right_arrow.custom_minimum_size = Vector2(40, 40)
	color_strip_row.add_child(right_arrow)

	color_bar_container.add_child(color_strip_row)
	color_container.add_child(color_bar_container)
	section.add_child(color_container)

	# Separator
	var separator = HSeparator.new()
	section.add_child(separator)

	return section

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

	# Initialize focused element based on first layer
	var first_layer = LAYERS[0]
	focused_element = "part" if first_layer.has_parts else "color"

func _on_animation_selected(anim_name: String):
	"""Handle animation selection"""
	current_animation = anim_name
	current_frame_index = 0
	animation_timer = 0.0

func _on_direction_selected(direction: String):
	"""Handle direction selection"""
	current_direction = direction
	current_frame_index = 0
	animation_timer = 0.0

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
	var section = customization_container.get_child(layer_index)
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


func update_preview():
	"""Update character preview"""
	for layer in LAYERS:
		var layer_code = layer.code
		var sprite = character_preview.get_node_or_null(layer_code)
		if not sprite:
			continue

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

		if part == null:
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
	"""Handle accept/confirm button"""
	var layer = LAYERS[current_layer_index]

	if navigation_mode == "normal":
		# Entering selection mode based on focused element
		if focused_element == "part" and layer.has_parts:
			navigation_mode = "part_selection"
			print("Entered part selection mode")
		elif focused_element == "color":
			navigation_mode = "color_selection"
			print("Entered color selection mode")
	elif navigation_mode == "part_selection":
		# Exit part selection mode
		navigation_mode = "normal"
		print("Exited part selection mode")
	elif navigation_mode == "color_selection":
		# Exit color selection mode and apply selection
		navigation_mode = "normal"
		print("Exited color selection mode")

	update_focus_visual()

func handle_back():
	"""Handle back/cancel button"""
	if navigation_mode == "part_selection" or navigation_mode == "color_selection":
		# Exit selection mode without applying
		navigation_mode = "normal"
		print("Cancelled selection mode")
		update_focus_visual()

func handle_up():
	"""Handle up navigation"""
	if navigation_mode == "normal":
		# Move to previous layer
		current_layer_index -= 1
		if current_layer_index < 0:
			current_layer_index = LAYERS.size() - 1  # Wrap to last layer

		# Default to part button if available, otherwise color button
		var layer = LAYERS[current_layer_index]
		focused_element = "part" if layer.has_parts else "color"

		update_focus_visual()
		ensure_section_visible()

func handle_down():
	"""Handle down navigation"""
	if navigation_mode == "normal":
		# Move to next layer
		current_layer_index += 1
		if current_layer_index >= LAYERS.size():
			current_layer_index = 0  # Wrap to first layer

		# Default to part button if available, otherwise color button
		var layer = LAYERS[current_layer_index]
		focused_element = "part" if layer.has_parts else "color"

		update_focus_visual()
		ensure_section_visible()

func handle_left():
	"""Handle left navigation"""
	var layer = LAYERS[current_layer_index]

	if navigation_mode == "normal":
		# Toggle between part and color Change buttons
		if focused_element == "color" and layer.has_parts:
			focused_element = "part"
			update_focus_visual()
	elif navigation_mode == "part_selection":
		# Cycle to previous part
		_on_part_previous(current_layer_index)
	elif navigation_mode == "color_selection":
		# Slide to previous color
		var color_index = current_colors.get(layer.code, 0)
		color_index -= 1
		if color_index < 0:
			color_index = layer.max_colors - 1
		current_colors[layer.code] = color_index
		update_preview()
		update_focus_visual()

func handle_right():
	"""Handle right navigation"""
	var layer = LAYERS[current_layer_index]

	if navigation_mode == "normal":
		# Toggle between part and color Change buttons
		if focused_element == "part":
			focused_element = "color"
			update_focus_visual()
	elif navigation_mode == "part_selection":
		# Cycle to next part
		_on_part_next(current_layer_index)
	elif navigation_mode == "color_selection":
		# Slide to next color
		var color_index = current_colors.get(layer.code, 0)
		color_index += 1
		if color_index >= layer.max_colors:
			color_index = 0
		current_colors[layer.code] = color_index
		update_preview()
		update_focus_visual()

func update_focus_visual():
	"""Update visual indicators for current focus"""
	# Clear all focus indicators first
	for i in range(LAYERS.size()):
		var section = customization_container.get_child(i)

		# Clear part button
		var part_container = section.get_node_or_null("PartContainer")
		if part_container:
			var part_btn = part_container.get_node("PartChangeButton")
			part_btn.modulate = Color.WHITE

		# Clear color button and strip
		var color_container = section.get_node_or_null("ColorContainer")
		if color_container:
			var color_change_row = color_container.get_node("ColorChangeRow")
			var color_btn = color_change_row.get_node("ColorChangeButton")
			color_btn.modulate = Color.WHITE

			# Clear color strip highlights
			var color_bar_container = color_container.get_node("ColorBarContainer")
			var color_strip_row = color_bar_container.get_node("ColorStripRow")
			var color_strip = color_strip_row.get_node("ColorStrip")
			for j in range(color_strip.get_child_count()):
				var block = color_strip.get_child(j)
				block.scale = Vector2(1, 1)

	# Highlight current focus
	var current_section = customization_container.get_child(current_layer_index)
	var layer = LAYERS[current_layer_index]

	if navigation_mode == "normal":
		# Highlight the focused Change button
		if focused_element == "part" and layer.has_parts:
			var part_container = current_section.get_node("PartContainer")
			var part_btn = part_container.get_node("PartChangeButton")
			part_btn.modulate = Color(1.5, 1.5, 0.5)  # Yellow highlight
		elif focused_element == "color":
			var color_container = current_section.get_node("ColorContainer")
			var color_change_row = color_container.get_node("ColorChangeRow")
			var color_btn = color_change_row.get_node("ColorChangeButton")
			color_btn.modulate = Color(1.5, 1.5, 0.5)  # Yellow highlight

	elif navigation_mode == "part_selection":
		# Highlight the part Change button (active selection mode)
		var part_container = current_section.get_node("PartContainer")
		var part_btn = part_container.get_node("PartChangeButton")
		part_btn.modulate = Color(0.5, 1.5, 0.5)  # Green highlight (active mode)

	elif navigation_mode == "color_selection":
		# Highlight the color Change button and current color in strip
		var color_container = current_section.get_node("ColorContainer")
		var color_change_row = color_container.get_node("ColorChangeRow")
		var color_btn = color_change_row.get_node("ColorChangeButton")
		color_btn.modulate = Color(0.5, 1.5, 0.5)  # Green highlight (active mode)

		# Highlight current color in strip
		var color_bar_container = color_container.get_node("ColorBarContainer")
		var color_strip_row = color_bar_container.get_node("ColorStripRow")
		var color_strip = color_strip_row.get_node("ColorStrip")
		var color_index = current_colors.get(layer.code, 0)
		if color_index < color_strip.get_child_count():
			var current_block = color_strip.get_child(color_index)
			current_block.scale = Vector2(1.0, 1.2)  # Scale up current color vertically

	# Update indicator arrow position for all layers (not just current)
	for i in range(LAYERS.size()):
		var section = customization_container.get_child(i)
		var layer_data = LAYERS[i]
		var color_container = section.get_node_or_null("ColorContainer")
		if color_container:
			var color_bar_container = color_container.get_node("ColorBarContainer")
			var indicator_row = color_bar_container.get_node("IndicatorRow")
			var indicator_position_spacer = indicator_row.get_node("IndicatorPositionSpacer")

			# Calculate indicator position based on current color
			var color_index = current_colors.get(layer_data.code, 0)
			var num_colors = layer_data.max_colors
			var block_width = 300.0 / num_colors if num_colors > 0 else 20.0
			var indicator_x = (color_index * block_width) + (block_width / 2.0) - 8  # Center on block

			# Update spacer width to position the arrow
			indicator_position_spacer.custom_minimum_size = Vector2(indicator_x, 20)

func ensure_section_visible():
	"""Scroll to keep the current section visible"""
	if current_layer_index < 0 or current_layer_index >= customization_container.get_child_count():
		return

	var current_section = customization_container.get_child(current_layer_index)
	var section_pos = current_section.position.y
	var section_height = current_section.size.y

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

	# Handle "hold" frames
	if current_time < 0:
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
			var sprite = character_preview.get_node_or_null(layer.code)
			if sprite:
				sprite.frame = frame_data.cell
				sprite.flip_h = frame_data.flip
