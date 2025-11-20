extends Control

## Psyokin Test Character Creator
## Uses sprite_animations_data.csv for accurate animation data
## Sprites numbered 0-255 in 16x16 grid (left to right, top to bottom)

# Paths
const SPRITE_PATH = "res://assets/graphics/characters/New Character System/SpriteSystem/base_sheets/"
const PALETTE_PATH = "res://assets/graphics/characters/New Character System/SpriteSystem/_supporting files/palettes/"
const ANIM_DATA_PATH = "res://scenes/test/sprite_animations_data.csv"

# Shader for palette swapping
var palette_shader = preload("res://assets/shaders/palette_swap.gdshader")

# Layer configuration (Mana Seed system)
const LAYERS = [
	{"code": "00undr", "label": "Under Layer", "ramp_type": null, "hidden": true, "allow_none": true, "max_color_schemes": 0},
	{"code": "01body", "label": "BODY", "ramp_type": "skin", "hidden": false, "allow_none": false, "max_color_schemes": 18},
	{"code": "02sock", "label": "Legwear", "ramp_type": "3color", "hidden": false, "allow_none": true, "max_color_schemes": 48},
	{"code": "03fot1", "label": "Footwear", "ramp_type": "3color", "hidden": false, "allow_none": true, "max_color_schemes": 48, "combine_with": "07fot2"},
	{"code": "04lwr1", "label": "Bottomwear", "ramp_type": "3color", "hidden": false, "allow_none": true, "max_color_schemes": 48},
	{"code": "05shrt", "label": "Topwear", "ramp_type": "3color", "hidden": false, "allow_none": true, "max_color_schemes": 48},
	{"code": "06lwr2", "label": "Bottomwear", "ramp_type": "3color", "hidden": false, "allow_none": true, "max_color_schemes": 48},
	{"code": "07fot2", "label": "Footwear", "ramp_type": "3color", "hidden": true, "allow_none": true, "max_color_schemes": 48},  # Combined into 03fot1
	{"code": "08lwr3", "label": "Bottomwear", "ramp_type": "3color", "hidden": false, "allow_none": true, "max_color_schemes": 48},
	{"code": "09hand", "label": "Handwear", "ramp_type": "3color", "hidden": false, "allow_none": true, "max_color_schemes": 48},
	{"code": "10outr", "label": "Overwear", "ramp_type": "3color", "hidden": false, "allow_none": true, "max_color_schemes": 48},
	{"code": "11neck", "label": "Neckwear", "ramp_type": "4color", "hidden": false, "allow_none": true, "max_color_schemes": 60},
	{"code": "12face", "label": "Eyewear", "ramp_type": "3color", "hidden": false, "allow_none": true, "max_color_schemes": 48},
	{"code": "13hair", "label": "Hairstyle", "ramp_type": "hair", "hidden": false, "allow_none": true, "max_color_schemes": 58},
	{"code": "14head", "label": "Headwear", "ramp_type": "4color", "hidden": false, "allow_none": true, "max_color_schemes": 60}
]

# Animation data parsed from CSV
var animations = {}  # {anim_name: {direction: {frames:[], times:[], total_frames:int}}}

# References
@onready var character_layers = $MainContainer/PreviewPanel/PreviewContainer/CenterContainer/CharacterLayers
@onready var parts_container = $MainContainer/ControlsPanel/ControlsContainer/ScrollContainer/PartsContainer
@onready var animation_list = $MainContainer/AnimationPanel/AnimationContainer/ScrollContainer/AnimationList
@onready var anim_label = $MainContainer/PreviewPanel/PreviewContainer/AnimationInfo/AnimLabel
@onready var direction_label = $MainContainer/PreviewPanel/PreviewContainer/AnimationInfo/DirectionLabel
@onready var frame_label = $MainContainer/PreviewPanel/PreviewContainer/AnimationInfo/FrameLabel

# State
var current_animation = "Idle"
var current_direction = "DOWN"
var current_frame_index = 0
var animation_timer = 0.0
var available_parts = {}
var current_selections = {}
var current_color_ramps = {}

# Cached palette images
var palette_images = {}

func _ready():
	print("=== PSYOKIN TEST CHARACTER CREATOR ===")
	load_palette_images()
	load_animation_data()
	scan_character_assets()
	populate_animation_list()
	populate_ui()
	set_default_character()
	update_preview()

func _process(delta):
	# Animate based on current animation
	if current_animation not in animations:
		return
	if current_direction not in animations[current_animation]:
		return

	var anim_data = animations[current_animation][current_direction]
	var times = anim_data.times

	if current_frame_index >= times.size():
		return

	var current_time = times[current_frame_index]

	# Check if this is a "hold" frame (don't advance)
	if current_time < 0:  # We'll use negative for hold
		return

	animation_timer += delta * 1000.0  # Convert to milliseconds

	if animation_timer >= current_time:
		animation_timer = 0.0
		current_frame_index = (current_frame_index + 1) % anim_data.total_frames
		update_frame_display()

func load_palette_images():
	"""Load and cache palette images for color extraction"""
	print("Loading palette images...")

	var palette_paths = {
		"3color": PALETTE_PATH + "mana seed 3-color ramps.png",
		"4color": PALETTE_PATH + "mana seed 4-color ramps.png",
		"hair": PALETTE_PATH + "mana seed hair ramps.png",
		"skin": PALETTE_PATH + "mana seed skin ramps.png"
	}

	for ramp_type in palette_paths:
		var path = palette_paths[ramp_type]
		if FileAccess.file_exists(path):
			var texture = load(path)
			if texture:
				# Get the image data from the texture
				var image = texture.get_image()
				palette_images[ramp_type] = image
				print("  Loaded ", ramp_type, " palette: ", image.get_width(), "x", image.get_height())
			else:
				print("  ERROR: Failed to load texture: ", path)
		else:
			print("  WARNING: Palette not found: ", path)

	# Also load base ramps (these are the colors in the sprite that will be replaced)
	var base_ramp_paths = {
		"3color": PALETTE_PATH + "base ramps/3-color base ramp (00a).png",
		"4color": PALETTE_PATH + "base ramps/4-color base ramp (00b).png",
		"hair": PALETTE_PATH + "base ramps/hair color base ramp.png",
		"skin": PALETTE_PATH + "base ramps/skin color base ramp.png"
	}

	for ramp_type in base_ramp_paths:
		var path = base_ramp_paths[ramp_type]
		if FileAccess.file_exists(path):
			var texture = load(path)
			if texture:
				var image = texture.get_image()
				palette_images[ramp_type + "_base"] = image
				print("  Loaded ", ramp_type, " base ramp: ", image.get_width(), "x", image.get_height())
			else:
				print("  ERROR: Failed to load base ramp texture: ", path)
		else:
			print("  WARNING: Base ramp not found: ", path)

func extract_colors_from_palette(ramp_type: String, row_index: int) -> Array:
	"""Extract colors from a specific row of a palette image
	Returns array of Color objects"""
	if ramp_type not in palette_images:
		print("ERROR: Palette type not loaded: ", ramp_type)
		return []

	var image = palette_images[ramp_type]
	var colors = []

	# Determine how many colors per row based on ramp type
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

	# Read pixels from the specified row
	# Each color is a 2x2 pixel block in the palette image
	# Each row in the palette image represents one color scheme
	for i in range(colors_per_row):
		# Calculate position in 2x2 blocks
		var x = i * 2  # Each color block is 2 pixels wide
		var y = row_index * 2  # Each row of colors is 2 pixels tall
		var pixel_color = image.get_pixel(x, y)
		colors.append(pixel_color)

	return colors

func load_animation_data():
	"""Parse the CSV file to load animation data"""
	print("Loading animation data from CSV...")

	var file = FileAccess.open(ANIM_DATA_PATH, FileAccess.READ)
	if file == null:
		print("ERROR: Could not open animation data file!")
		return

	# Skip header line
	file.get_csv_line()

	while not file.eof_reached():
		var line = file.get_csv_line()
		if line.size() < 4:
			continue

		var anim_name = line[0].strip_edges()
		var direction = line[1].strip_edges()
		var frame_count = int(line[2])

		if anim_name == "":
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

			# Parse cell (handle flip flag and convert to frame number)
			var frame_data = parse_cell(cell_str)
			frames.append(frame_data)

			# Parse time (handle "hold")
			var time_ms = 0
			if time_str.to_lower() == "hold":
				time_ms = -1  # Negative means hold forever
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
	"""Parse cell string like '48f' or '064F' into {cell: int, flip: bool}"""
	var flip = false
	var cell_num = 0

	# Check for flip flag
	if cell_str.to_lower().ends_with("f"):
		flip = true
		cell_str = cell_str.substr(0, cell_str.length() - 1)

	# Parse cell number
	cell_num = int(cell_str)

	return {"cell": cell_num, "flip": flip}

func scan_character_assets():
	"""Scan the sprite system folders"""
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

	print("Asset scan complete")

func parse_filename(filename: String, layer_code: String) -> Dictionary:
	"""Parse Mana Seed filename format"""
	var parts = filename.get_basename().split("_")
	var result = {
		"name": filename.get_basename(),
		"base_name": "",
		"palette_code": "",
		"has_e_flag": false,
		"display_name": filename.get_basename()
	}

	if parts.size() >= 4:
		result["base_name"] = parts[2]
		result["palette_code"] = parts[3]
		if parts.size() >= 5 and parts[4] == "e":
			result["has_e_flag"] = true

		result["display_name"] = parts[2].capitalize() + " (" + parts[3] + ")"
		if result["has_e_flag"]:
			result["display_name"] += " [E]"

	return result

func populate_animation_list():
	"""Populate the animation selector"""
	print("Populating animation list...")

	# Get unique animation names and sort them
	var anim_names = animations.keys()
	anim_names.sort()

	# Group by category (simplified - you can enhance this)
	var categories = {
		"Idle & Movement": ["Idle", "Walk", "Walk While Carrying", "Run", "Run While Carrying", "Jump", "Jump While Carrying"],
		"Actions": ["Push", "Pull", "Pick up, Carry", "Throw Carried", "Work at Desk", "Work at Station"],
		"Social": ["Wave", "Hugs", "Sing", "Guitar", "Drums", "Flute"],
		"Combat": ["Hammer Strike", "Spear Strike", "Sword Strike", "Wand Strike", "Bow Shot", "Guard", "Fight Pose", "Evade", "Hurt", "Take Damage"],
		"Farming": ["Water Plants", "Climb", "Smith", "Pet Small", "Pet Large", "Milk"],
		"Fishing": ["Fishing Cast", "Fishing BITE", "Fishing GOT IT"],
		"Sitting": ["Throne Sit", "Sit on Ledge", "Sit on Chair", "Sit on Floor", "Sit on Floor Cute", "Sleep in Chair"],
		"Resting": ["Meditate", "Sleep"],
		"Emotions": ["Look Around (Left then Right)", "Sad", "Thumbs Up", "Shocked", "Mad Stomp", "Laugh"],
		"Drinking": ["Drink Standing", "Drink Sitting"],
		"Riding": ["Mount Up", "Ride Mount", "Soothe Mount"],
		"Misc": ["Top of Climb", "Impatient"]
	}

	var added_anims = {}

	for category in categories:
		var category_label = Label.new()
		category_label.text = "─── " + category + " ───"
		category_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		category_label.add_theme_font_size_override("font_size", 12)
		animation_list.add_child(category_label)

		for anim_name in categories[category]:
			if anim_name in animations:
				var btn = Button.new()
				btn.text = anim_name
				btn.pressed.connect(_on_animation_selected.bind(anim_name))
				animation_list.add_child(btn)
				added_anims[anim_name] = true

		var separator = HSeparator.new()
		animation_list.add_child(separator)

	# Add any remaining uncategorized animations
	var uncategorized = []
	for anim_name in anim_names:
		if anim_name not in added_anims:
			uncategorized.append(anim_name)

	if uncategorized.size() > 0:
		var category_label = Label.new()
		category_label.text = "─── Other ───"
		category_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		animation_list.add_child(category_label)

		for anim_name in uncategorized:
			var btn = Button.new()
			btn.text = anim_name
			btn.pressed.connect(_on_animation_selected.bind(anim_name))
			animation_list.add_child(btn)

func populate_ui():
	"""Create UI controls for each layer"""
	print("Populating UI...")

	# Group bottomwear layers
	var bottomwear_parts = []
	for layer in LAYERS:
		if layer.code in ["04lwr1", "06lwr2", "08lwr3"]:
			if layer.code in available_parts:
				bottomwear_parts.append_array(available_parts[layer.code])

	# Group footwear layers (Small + Large)
	var footwear_parts = []
	for layer in LAYERS:
		if layer.code in ["03fot1", "07fot2"]:
			if layer.code in available_parts:
				footwear_parts.append_array(available_parts[layer.code])

	for layer in LAYERS:
		var layer_code = layer.code

		# Skip hidden layers
		if layer.get("hidden", false):
			continue

		# Skip bottomwear sub-layers (handled as group)
		if layer_code in ["06lwr2", "08lwr3"]:
			continue

		var section = create_layer_section(layer_code, layer.label)
		parts_container.add_child(section)

		# Special handling for bottomwear group
		if layer_code == "04lwr1":
			populate_layer_options(section, layer_code, bottomwear_parts, layer)
		# Special handling for footwear group (combine 03fot1 and 07fot2)
		elif layer_code == "03fot1":
			populate_layer_options(section, layer_code, footwear_parts, layer)
		else:
			var parts = available_parts.get(layer_code, [])
			populate_layer_options(section, layer_code, parts, layer)

		var separator = HSeparator.new()
		parts_container.add_child(separator)

func create_layer_section(layer_code: String, label: String) -> VBoxContainer:
	"""Create a section container for a layer"""
	var section = VBoxContainer.new()
	section.name = layer_code + "_Section"

	var section_label = Label.new()
	section_label.text = label
	section_label.add_theme_font_size_override("font_size", 16)
	section.add_child(section_label)

	var options_container = VBoxContainer.new()
	options_container.name = "Options"
	section.add_child(options_container)

	return section

func populate_layer_options(section: Node, layer_code: String, parts: Array, layer):
	"""Populate a section with part and color options"""
	var options_container = section.get_node("Options")
	var ramp_type = layer.get("ramp_type", null)
	var allow_none = layer.get("allow_none", true)
	var max_color_schemes = layer.get("max_color_schemes", 999)

	# Add "None" option (only if allowed)
	if allow_none:
		var none_btn = Button.new()
		none_btn.text = "None"
		none_btn.pressed.connect(_on_part_selected.bind(layer_code, null))
		options_container.add_child(none_btn)

	# Add button for each part
	for part in parts:
		var btn = Button.new()
		# Clean up display name - remove parentheses content
		var display_name = part.display_name
		var paren_pos = display_name.find("(")
		if paren_pos > 0:
			display_name = display_name.substr(0, paren_pos).strip_edges()
		btn.text = display_name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_part_selected.bind(layer_code, part))
		options_container.add_child(btn)

	# Add color ramp selector if supported
	if ramp_type != null:
		var color_section = VBoxContainer.new()
		var color_label = Label.new()
		color_label.text = "  Color Ramp:"
		color_section.add_child(color_label)

		# Load and display palette image
		var palette_image_path = get_palette_image_path(ramp_type)
		var num_color_schemes = 20  # Default fallback
		var palette_image = null

		if FileAccess.file_exists(palette_image_path):
			var palette_texture = load(palette_image_path)
			if palette_texture:
				var palette_display = TextureRect.new()
				palette_display.texture = palette_texture
				palette_display.expand_mode = TextureRect.EXPAND_FIT_WIDTH
				palette_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
				palette_display.custom_minimum_size = Vector2(0, 150)
				color_section.add_child(palette_display)

				# Calculate number of color schemes from image height
				# Each color scheme is 2 pixels tall (2x2 blocks per color)
				palette_image = palette_texture.get_image()
				num_color_schemes = palette_image.get_height() / 2
				print("  Found ", num_color_schemes, " color schemes for ", ramp_type)

		# Limit to max_color_schemes specified in layer config
		num_color_schemes = min(num_color_schemes, max_color_schemes)

		# Add color ramp buttons (limited to max_color_schemes)
		var ramp_grid = GridContainer.new()
		ramp_grid.columns = 5
		for i in range(num_color_schemes):
			var btn = Button.new()
			btn.text = str(i + 1)
			btn.custom_minimum_size = Vector2(40, 30)
			btn.pressed.connect(_on_color_ramp_selected.bind(i, layer_code, ramp_type))

			# Add color preview from 3rd color in the palette row
			if palette_image != null:
				# Get the 3rd color (index 2) from this row
				# Each color is a 2x2 block, so 3rd color is at x = 2 * 2 = 4
				var preview_color = palette_image.get_pixel(4, i * 2)

				# Create a StyleBoxFlat for the button background
				var style = StyleBoxFlat.new()
				style.bg_color = preview_color
				style.border_color = Color.BLACK
				style.border_width_left = 1
				style.border_width_right = 1
				style.border_width_top = 1
				style.border_width_bottom = 1
				btn.add_theme_stylebox_override("normal", style)

				# Make text more visible with a contrasting color
				var text_color = Color.WHITE if preview_color.get_luminance() < 0.5 else Color.BLACK
				btn.add_theme_color_override("font_color", text_color)

			ramp_grid.add_child(btn)

		color_section.add_child(ramp_grid)
		options_container.add_child(color_section)

func get_palette_image_path(ramp_type: String) -> String:
	"""Get the path to the palette image"""
	match ramp_type:
		"3color":
			return PALETTE_PATH + "mana seed 3-color ramps.png"
		"4color":
			return PALETTE_PATH + "mana seed 4-color ramps.png"
		"hair":
			return PALETTE_PATH + "mana seed hair ramps.png"
		"skin":
			return PALETTE_PATH + "mana seed skin ramps.png"
		_:
			return ""

func set_default_character():
	"""Set up a default character"""
	if "01body" in available_parts and available_parts["01body"].size() > 0:
		_on_part_selected("01body", available_parts["01body"][0])

func _on_part_selected(layer_code: String, part):
	"""Handle part selection"""
	current_selections[layer_code] = part

	# Auto-toggle Under Layer when cloak items are selected/deselected in Neckwear
	if layer_code == "11neck":
		if part != null and ("cloak" in part.base_name.to_lower()):
			# Auto-select matching under layer for cloak items
			# Look for matching under layer part
			if "00undr" in available_parts:
				for under_part in available_parts["00undr"]:
					# Match the cloak base name to under layer
					if under_part.base_name.to_lower().contains("cloak"):
						current_selections["00undr"] = under_part
						print("Auto-selected under layer: ", under_part.display_name)
						break
		else:
			# Deselect under layer when no cloak or None selected
			current_selections["00undr"] = null

	update_preview()

func _on_color_ramp_selected(index: int, layer_code: String, ramp_type: String):
	"""Handle color ramp selection"""
	current_color_ramps[layer_code] = {"type": ramp_type, "index": index}
	apply_color_ramp(layer_code)

func update_preview():
	"""Update the character preview"""
	for layer in LAYERS:
		var layer_code = layer.code
		var sprite = character_layers.get_node(layer_code)

		if layer_code in current_selections and current_selections[layer_code] != null:
			var part = current_selections[layer_code]

			# Load original texture
			var original_texture = load(part.path)

			# Check if we need to apply color ramp
			if layer.ramp_type != null and layer_code in current_color_ramps:
				# Apply color mapping and create new texture
				var recolored_texture = apply_color_mapping(original_texture, part, layer.ramp_type, layer_code)
				sprite.texture = recolored_texture
			else:
				sprite.texture = original_texture

			sprite.visible = true
			sprite.material = null  # No shader needed
		else:
			sprite.texture = null
			sprite.visible = false
			sprite.material = null

	update_frame_display()

func apply_color_ramp(layer_code: String):
	"""Trigger update_preview to recolor the sprite"""
	update_preview()

func apply_color_mapping(original_texture: Texture2D, part: Dictionary, ramp_type: String, layer_code: String) -> ImageTexture:
	"""Apply color palette mapping by replacing pixels in the image
	Returns a new ImageTexture with swapped colors"""

	# Get the image from the texture
	var original_image = original_texture.get_image()
	if original_image == null:
		print("ERROR: Could not get image from texture for ", layer_code)
		return ImageTexture.create_from_image(original_image)

	# Create a copy to modify
	var recolored_image = Image.create(original_image.get_width(), original_image.get_height(), false, original_image.get_format())
	recolored_image.copy_from(original_image)

	# Get the base colors (what's in the sprite) based on the palette code
	var palette_code = part.palette_code  # e.g., "00a", "00b", "00c", "00d", "00f"
	var base_colors = get_base_colors_for_palette_code(palette_code, ramp_type)

	if base_colors.size() == 0:
		print("ERROR: No base colors loaded for ", layer_code)
		return ImageTexture.create_from_image(recolored_image)

	# Get the target colors based on palette code
	var target_colors = get_target_colors_for_palette_code(palette_code, ramp_type, layer_code)

	if target_colors.size() == 0:
		print("ERROR: No target colors loaded for ", layer_code)
		return ImageTexture.create_from_image(recolored_image)

	print("Applying color map to ", layer_code, ": ", base_colors.size(), " base → ", target_colors.size(), " target colors")

	# Replace colors pixel by pixel
	for y in range(recolored_image.get_height()):
		for x in range(recolored_image.get_width()):
			var pixel = recolored_image.get_pixel(x, y)

			# Skip transparent pixels
			if pixel.a < 0.01:
				continue

			# Check if this pixel matches any base color
			for i in range(min(base_colors.size(), target_colors.size())):
				if colors_match(pixel, base_colors[i]):
					recolored_image.set_pixel(x, y, Color(target_colors[i].r, target_colors[i].g, target_colors[i].b, pixel.a))
					break

	# Create and return new texture
	return ImageTexture.create_from_image(recolored_image)

func get_target_colors_for_palette_code(palette_code: String, ramp_type: String, layer_code: String) -> Array:
	"""Get target colors based on palette code
	For multi-ramp codes, builds the appropriate color array"""

	var ramp_info = current_color_ramps[layer_code]
	var row_index = ramp_info.index

	match palette_code:
		"00a":  # Single 3-color ramp
			return extract_colors_from_palette(ramp_type, row_index)
		"00b":  # Single 4-color ramp
			return extract_colors_from_palette(ramp_type, row_index)
		"00c":  # Two 3-color ramps (6 colors)
			# For now, use the same 3-color ramp twice
			var colors_3 = extract_colors_from_palette("3color", row_index)
			if colors_3.size() >= 3:
				return colors_3 + colors_3  # Repeat the 3 colors
			return []
		"00d":  # One 4-color + one 3-color (7 colors)
			# Use 4-color ramp + 3-color ramp
			var colors_4 = extract_colors_from_palette("4color", row_index)
			var colors_3 = extract_colors_from_palette("3color", row_index)
			if colors_4.size() >= 4 and colors_3.size() >= 3:
				return colors_4 + colors_3
			return []
		"00f":  # One 4-color + one 5-color hair (9 colors)
			# Use 4-color ramp + hair ramp
			var colors_4 = extract_colors_from_palette("4color", row_index)
			var colors_hair = extract_colors_from_palette("hair", row_index)
			if colors_4.size() >= 4 and colors_hair.size() >= 5:
				return colors_4 + colors_hair
			return []
		"00":  # Plain 00 - skin or hair
			return extract_colors_from_palette(ramp_type, row_index)
		_:
			# Fallback
			return extract_colors_from_palette(ramp_type, row_index)

func get_base_colors_for_palette_code(palette_code: String, ramp_type: String) -> Array:
	"""Get base colors based on the palette code (00a, 00b, 00c, 00d, 00f)"""

	# Determine which base ramp file to use based on exact palette code
	var base_ramp_key = ""
	var base_ramp_filename = ""

	match palette_code:
		"00a":  # Single 3-color ramp
			base_ramp_filename = "3-color base ramp (00a).png"
		"00b":  # Single 4-color ramp
			base_ramp_filename = "4-color base ramp (00b).png"
		"00c":  # Two 3-color ramps (6 colors total)
			base_ramp_filename = "2x 3-color base ramps (00c).png"
		"00d":  # One 4-color + one 3-color ramp (7 colors total)
			base_ramp_filename = "4-color + 3-color base ramps (00d).png"
		"00f":  # One 4-color + one 5-color hair ramp (9 colors total)
			# This case is complex - need special handling
			base_ramp_filename = "4-color base ramp (00b).png"  # Fallback for now
		"00":  # Plain 00 - use ramp_type to determine
			if ramp_type == "skin":
				base_ramp_filename = "skin color base ramp.png"
			elif ramp_type == "hair":
				base_ramp_filename = "hair color base ramp.png"
		_:
			# Fallback - try to guess based on ramp_type
			if ramp_type == "skin":
				base_ramp_filename = "skin color base ramp.png"
			elif ramp_type == "hair":
				base_ramp_filename = "hair color base ramp.png"
			elif ramp_type == "3color":
				base_ramp_filename = "3-color base ramp (00a).png"
			elif ramp_type == "4color":
				base_ramp_filename = "4-color base ramp (00b).png"

	if base_ramp_filename == "":
		print("ERROR: Could not determine base ramp file for palette code: ", palette_code)
		return []

	# Load the base ramp image
	var base_ramp_path = PALETTE_PATH + "base ramps/" + base_ramp_filename
	if not FileAccess.file_exists(base_ramp_path):
		print("ERROR: Base ramp file not found: ", base_ramp_path)
		return []

	var texture = load(base_ramp_path)
	if texture == null:
		print("ERROR: Could not load base ramp texture: ", base_ramp_path)
		return []

	var image = texture.get_image()
	var colors = []

	# Read all colors from the base ramp (row 0, all columns)
	# The number of colors varies by palette code
	# Each color is a 2x2 pixel block
	var num_colors = image.get_width() / 2  # Divide by 2 since each color is 2 pixels wide
	for i in range(num_colors):
		var x = i * 2  # Each color block is 2 pixels wide
		var pixel_color = image.get_pixel(x, 0)
		colors.append(pixel_color)

	print("Loaded ", colors.size(), " base colors from ", base_ramp_filename)
	return colors

func colors_match(color1: Color, color2: Color, tolerance: float = 0.02) -> bool:
	"""Check if two colors match within a tolerance"""
	return abs(color1.r - color2.r) < tolerance and \
	       abs(color1.g - color2.g) < tolerance and \
	       abs(color1.b - color2.b) < tolerance

func update_frame_display():
	"""Update the character sprite frames"""
	if current_animation not in animations:
		return
	if current_direction not in animations[current_animation]:
		return

	var anim_data = animations[current_animation][current_direction]
	if current_frame_index >= anim_data.frames.size():
		current_frame_index = 0
		return

	var frame_data = anim_data.frames[current_frame_index]
	var cell = frame_data.cell
	var flip = frame_data.flip

	# Update all visible sprites
	for layer in LAYERS:
		var layer_code = layer.code
		var sprite = character_layers.get_node(layer_code)
		if sprite.visible and sprite.texture:
			sprite.frame = cell
			sprite.flip_h = flip

	# Update labels
	anim_label.text = "Animation: " + current_animation
	direction_label.text = "Direction: " + current_direction
	frame_label.text = "Frame: " + str(current_frame_index + 1) + "/" + str(anim_data.total_frames)

func _on_direction_changed(direction: String):
	"""Handle direction change"""
	current_direction = direction
	current_frame_index = 0
	animation_timer = 0.0
	update_frame_display()

func _on_animation_selected(anim_name: String):
	"""Handle animation selection"""
	print("Selected animation: ", anim_name)
	current_animation = anim_name
	current_frame_index = 0
	animation_timer = 0.0

	# If current direction doesn't exist for this animation, pick first available
	if current_direction not in animations[anim_name]:
		var available_dirs = animations[anim_name].keys()
		if available_dirs.size() > 0:
			current_direction = available_dirs[0]

	update_frame_display()
