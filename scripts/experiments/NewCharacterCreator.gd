extends Control

## New Character Creator Experiment
## A standalone scene for the new Mana Seed character system with shader-based palette swapping
##
## Layer Order (bottom to top) - from Mana Seed documentation:
## - 00undr: Under everything (back wing, cloak back)
## - 01body: Base body (required) - SKIN RAMP
## - 02sock: Legwear (socks, stockings) - 3-COLOR
## - 03fot1: Footwear (small, under pants) - 3-COLOR
## - 04lwr1: Bottomwear (pants, shorts) - 3-COLOR [MUTUALLY EXCLUSIVE with 06lwr2, 08lwr3]
## - 05shrt: Topwear (shirts, blouses) - 3-COLOR
## - 06lwr2: Bottomwear (overalls) - 3-COLOR [MUTUALLY EXCLUSIVE with 04lwr1, 08lwr3]
## - 07fot2: Footwear (big, over pants) - 3-COLOR
## - 08lwr3: Bottomwear (skirts, dresses) - 3-COLOR [MUTUALLY EXCLUSIVE with 04lwr1, 06lwr2]
## - 09hand: Handwear (gloves, bracers) - 3-COLOR
## - 10outr: Overwear (coats, vests) - 3-COLOR
## - 11neck: Neckwear (cloak, scarf) - 4-COLOR
## - 12face: Eyewear (glasses, masks) - 3-COLOR
## - 13hair: Hair - HAIR RAMP (5-color)
## - 14head: Headwear (hats, hoods) - 4-COLOR

# Path to new character system
const CHAR_BASE_PATH = "res://assets/graphics/characters/New Character System/SpriteSystem/base_sheets/"
const PALETTE_PATH = "res://assets/graphics/characters/New Character System/SpriteSystem/_supporting files/palettes/"

# Shader for palette swapping
var palette_shader = preload("res://assets/shaders/palette_swap.gdshader")

# Layer configuration matching the new system
const LAYERS = {
	"00undr": {"node_name": "UnderSprite", "label": "Under Layer", "ramp_type": null, "z_index": 0},
	"01body": {"node_name": "BodySprite", "label": "Body", "ramp_type": "skin", "z_index": 1},
	"02sock": {"node_name": "LegwearSprite", "label": "Legwear", "ramp_type": "3color", "z_index": 2},
	"03fot1": {"node_name": "Footwear1Sprite", "label": "Footwear (Small)", "ramp_type": "3color", "z_index": 3},
	"04lwr1": {"node_name": "BottomwearSprite", "label": "Bottomwear", "ramp_type": "3color", "z_index": 4, "exclusive_group": "bottomwear"},
	"05shrt": {"node_name": "TopwearSprite", "label": "Topwear", "ramp_type": "3color", "z_index": 5},
	"06lwr2": {"node_name": "BottomwearSprite", "label": "Bottomwear (Overalls)", "ramp_type": "3color", "z_index": 6, "exclusive_group": "bottomwear"},
	"07fot2": {"node_name": "Footwear2Sprite", "label": "Footwear (Large)", "ramp_type": "3color", "z_index": 7},
	"08lwr3": {"node_name": "BottomwearSprite", "label": "Bottomwear (Dress/Skirt)", "ramp_type": "3color", "z_index": 8, "exclusive_group": "bottomwear"},
	"09hand": {"node_name": "HandwearSprite", "label": "Handwear", "ramp_type": "3color", "z_index": 9},
	"10outr": {"node_name": "OverwearSprite", "label": "Overwear", "ramp_type": "3color", "z_index": 10},
	"11neck": {"node_name": "NeckwearSprite", "label": "Neckwear", "ramp_type": "4color", "z_index": 11},
	"12face": {"node_name": "EyewearSprite", "label": "Eyewear", "ramp_type": "3color", "z_index": 12},
	"13hair": {"node_name": "HairSprite", "label": "Hairstyle", "ramp_type": "hair", "z_index": 13},
	"14head": {"node_name": "HeadwearSprite", "label": "Headwear", "ramp_type": "4color", "z_index": 14}
}

# Direction mapping (simplified for initial testing)
const DIRECTIONS = {
	0: "South",
	1: "North",
	2: "East",
	3: "West"
}

# Animation configurations based on Mana Seed animation guide
# Format: {start_cell, frame_count, speed, direction_order}
const ANIMATIONS = {
	# Basic Movement
	"walk": {"cells": [0, 16, 32, 48], "frames": 8, "speed": 0.135, "label": "Walk"},
	"run": {"cells": [8, 24, 40, 56], "frames": 8, "speed": 0.080, "label": "Run"},
	"jump": {"cells": [64, 80, 96, 112], "frames": 4, "speed": 0.150, "label": "Jump"},
	"push": {"cells": [68, 84, 100, 116], "frames": 2, "speed": 0.200, "label": "Push"},
	"pull": {"cells": [70, 86, 102, 118], "frames": 2, "speed": 0.200, "label": "Pull"},

	# Farming - Planting
	"plant_seeds": {"cells": [72, 88, 104, 120], "frames": 4, "speed": 0.150, "label": "Plant Seeds"},

	# Farming - Watering
	"water_long": {"cells": [128, 144, 160, 176], "frames": 8, "speed": 0.150, "label": "Water (Long 2-4)"},

	# Farming - Carrying
	"walk_carry": {"cells": [0, 16, 32, 48], "frames": 8, "speed": 0.135, "label": "Walk While Carrying"},
	"run_carry": {"cells": [8, 24, 40, 56], "frames": 8, "speed": 0.080, "label": "Run While Carrying"},
	"jump_carry": {"cells": [64, 80, 96, 112], "frames": 4, "speed": 0.150, "label": "Jump While Carrying"},

	# Farming - Tools
	"pickaxe": {"cells": [192, 193, 194, 195], "frames": 1, "speed": 0.200, "label": "Pick Up/Carry"},
	"throw": {"cells": [196, 197, 198, 199], "frames": 1, "speed": 0.200, "label": "Throw Cropped"},

	# Fishing
	"cast_fishing": {"cells": [128, 144, 160, 176], "frames": 4, "speed": 0.200, "label": "Cast Fishing Line"},
	"got_bite": {"cells": [132, 148, 164, 180], "frames": 1, "speed": 0.100, "label": "Got A Bite!"},
	"got_it": {"cells": [133, 149, 165, 181], "frames": 1, "speed": 0.100, "label": "Got It!"},

	# Combat/Tools
	"overhead_strike": {"cells": [144, 145, 146, 147], "frames": 4, "speed": 0.100, "label": "Overhead Strike (1h/2h)"},
	"forging_strike": {"cells": [148, 149, 150, 151], "frames": 4, "speed": 0.120, "label": "Forging Strike"},
	"backhand_strike": {"cells": [152, 153, 154, 155], "frames": 1, "speed": 0.100, "label": "Backhand Strike"},

	# Expressions/Actions
	"wave": {"cells": [72, 89, 106, 123], "frames": 1, "speed": 0.200, "label": "Wave"},
	"hug": {"cells": [104, 105], "frames": 2, "speed": 0.300, "label": "Hug (south, scramble)"},
	"flute": {"cells": [76, 92, 108, 124], "frames": 1, "speed": 0.200, "label": "Flute/Horn/Lute"},

	# Utility
	"sit_throne": {"cells": [116], "frames": 1, "speed": 0.100, "label": "Sit Throne"},
	"sit_chair": {"cells": [117], "frames": 1, "speed": 0.100, "label": "Sit, Chair"},
	"meditate": {"cells": [118], "frames": 1, "speed": 0.100, "label": "Meditate"},
	"sleep": {"cells": [119], "frames": 1, "speed": 0.100, "label": "Sleep"},

	# Death/Hit
	"hurt": {"cells": [177, 178, 179, 180], "frames": 1, "speed": 0.150, "label": "Hurt (down/right/left)"},
	"kia_shot": {"cells": [120, 136, 152, 168], "frames": 4, "speed": 0.120, "label": "KIA Shot"},

	# Climbing
	"climb": {"cells": [4, 5, 6, 7], "frames": 4, "speed": 0.150, "label": "Climb (going up)"},

	# Misc
	"pet_dog": {"cells": [76, 77], "frames": 2, "speed": 0.200, "label": "Pet Dog/Cat"},
	"look_around": {"cells": [240, 241, 242], "frames": 3, "speed": 0.300, "label": "Look Around"}
}

# Color ramp data (will be loaded from palette images)
var color_ramps = {
	"3color": [],
	"4color": [],
	"hair": [],
	"skin": []
}

# References
@onready var character_layers = $MainContainer/PreviewPanel/PreviewContainer/CenterContainer/CharacterLayers
@onready var parts_container = $MainContainer/ControlsPanel/ControlsContainer/ScrollContainer/PartsContainer
@onready var animation_list = $MainContainer/AnimationPanel/AnimationContainer/ScrollContainer/AnimationList
@onready var frame_label = $MainContainer/PreviewPanel/PreviewContainer/AnimationControls/FrameLabel
@onready var direction_label = $MainContainer/PreviewPanel/PreviewContainer/AnimationControls/DirectionLabel

# State
var current_direction = 0  # South
var current_frame = 0
var current_animation = "walk"  # Default animation
var available_parts = {}
var current_selections = {}
var current_color_ramps = {}  # Track selected color ramps per layer
var animation_timer = 0.0
var animation_speed = 0.135  # 135ms per frame for walk

func _ready():
	print("=== NEW CHARACTER CREATOR STARTING ===")
	load_color_ramps()
	scan_character_assets()
	populate_animation_list()
	populate_ui()
	set_default_character()
	update_preview()

func _process(delta):
	# Animate based on current animation
	var anim_config = ANIMATIONS[current_animation]
	animation_timer += delta
	if animation_timer >= anim_config.speed:
		animation_timer = 0.0
		current_frame = (current_frame + 1) % anim_config.frames
		update_frame_display()

func load_color_ramps():
	"""Load color ramp data from palette images"""
	# For now, we'll create placeholder color ramp entries
	# In a full implementation, you'd parse the palette images

	# 3-color ramps (from mana seed 3-color ramps.png)
	for i in range(30):  # Placeholder: assume 30 color variations
		color_ramps["3color"].append({
			"name": "3-Color Ramp %d" % (i + 1),
			"index": i
		})

	# 4-color ramps (from mana seed 4-color ramps.png)
	for i in range(30):
		color_ramps["4color"].append({
			"name": "4-Color Ramp %d" % (i + 1),
			"index": i
		})

	# Hair ramps (from mana seed hair ramps.png)
	for i in range(30):
		color_ramps["hair"].append({
			"name": "Hair Color %d" % (i + 1),
			"index": i
		})

	# Skin ramps (from mana seed skin ramps.png)
	for i in range(12):
		color_ramps["skin"].append({
			"name": "Skin Tone %d" % (i + 1),
			"index": i
		})

func populate_animation_list():
	"""Populate the animation selector with all available animations"""
	print("Populating animation list...")

	# Group animations by category
	var categories = {
		"Basic Movement": ["walk", "run", "jump", "push", "pull"],
		"Farming": ["plant_seeds", "water_long", "walk_carry", "run_carry", "jump_carry", "pickaxe", "throw"],
		"Fishing": ["cast_fishing", "got_bite", "got_it"],
		"Combat/Tools": ["overhead_strike", "forging_strike", "backhand_strike"],
		"Expressions": ["wave", "hug", "flute"],
		"Utility": ["sit_throne", "sit_chair", "meditate", "sleep", "climb"],
		"Death/Hit": ["hurt", "kia_shot"],
		"Misc": ["pet_dog", "look_around"]
	}

	for category in categories:
		# Add category label
		var category_label = Label.new()
		category_label.text = "─── " + category + " ───"
		category_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		category_label.add_theme_font_size_override("font_size", 12)
		animation_list.add_child(category_label)

		# Add animation buttons
		for anim_key in categories[category]:
			if anim_key in ANIMATIONS:
				var anim = ANIMATIONS[anim_key]
				var btn = Button.new()
				btn.text = anim.label
				btn.pressed.connect(_on_animation_selected.bind(anim_key))
				animation_list.add_child(btn)

		# Add separator
		var separator = HSeparator.new()
		animation_list.add_child(separator)

func scan_character_assets():
	"""Scan the new character system folders"""
	print("Scanning new character system assets...")

	for layer_code in LAYERS.keys():
		var layer_path = CHAR_BASE_PATH + layer_code + "/"
		var dir = DirAccess.open(layer_path)

		if dir == null:
			print("  Layer ", layer_code, ": not found (", layer_path, ")")
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

	print("Asset scan complete:")
	for layer_code in available_parts:
		print("  ", layer_code, " (", LAYERS[layer_code].label, "): ", available_parts[layer_code].size(), " items")

func parse_filename(filename: String, layer_code: String) -> Dictionary:
	"""Parse Mana Seed filename format: fbas_XXlayer_name_00X_e
	Example: fbas_13hair_bob1_00 or fbas_14head_headscarf_00b_e
	Returns: {name, base_name, palette_code, has_e_flag}
	"""
	var parts = filename.get_basename().split("_")
	var result = {
		"name": filename.get_basename(),
		"base_name": "",
		"palette_code": "",
		"has_e_flag": false,
		"display_name": filename.get_basename()
	}

	# Format: fbas_XXlayer_itemname_versionpalette_e(optional)
	if parts.size() >= 4:
		# Item name is part 2
		result["base_name"] = parts[2]
		# Version/palette is part 3
		result["palette_code"] = parts[3]
		# Check for _e flag (part 4)
		if parts.size() >= 5 and parts[4] == "e":
			result["has_e_flag"] = true

		# Create display name
		result["display_name"] = parts[2].capitalize() + " (" + parts[3] + ")"
		if result["has_e_flag"]:
			result["display_name"] += " [E]"

	return result

func populate_ui():
	"""Create UI controls for each layer"""
	print("Populating UI...")

	# Group bottomwear layers together
	var bottomwear_parts = []
	if "04lwr1" in available_parts:
		bottomwear_parts.append_array(available_parts["04lwr1"])
	if "06lwr2" in available_parts:
		bottomwear_parts.append_array(available_parts["06lwr2"])
	if "08lwr3" in available_parts:
		bottomwear_parts.append_array(available_parts["08lwr3"])

	# Create sections for each layer/group
	for layer_code in LAYERS.keys():
		var layer = LAYERS[layer_code]

		# Skip bottomwear sub-layers (we'll handle them as a group)
		if layer_code in ["06lwr2", "08lwr3"]:
			continue

		# Create section
		var section = create_layer_section(layer_code, layer.label)
		parts_container.add_child(section)

		# Special handling for bottomwear group
		if layer_code == "04lwr1":
			populate_layer_options(section, layer_code, bottomwear_parts, layer.ramp_type)
		else:
			var parts = available_parts.get(layer_code, [])
			populate_layer_options(section, layer_code, parts, layer.ramp_type)

		# Add separator
		var separator = HSeparator.new()
		parts_container.add_child(separator)

func create_layer_section(layer_code: String, label: String) -> VBoxContainer:
	"""Create a section container for a layer"""
	var section = VBoxContainer.new()
	section.name = layer_code + "_Section"

	# Label
	var section_label = Label.new()
	section_label.text = label + " (" + layer_code + ")"
	section_label.add_theme_font_size_override("font_size", 16)
	section.add_child(section_label)

	# Options container
	var options_container = VBoxContainer.new()
	options_container.name = "Options"
	section.add_child(options_container)

	return section

func populate_layer_options(section: Node, layer_code: String, parts: Array, ramp_type):
	"""Populate a section with part and color options"""
	var options_container = section.get_node("Options")

	# Add "None" option
	var none_btn = Button.new()
	none_btn.text = "None"
	none_btn.pressed.connect(_on_part_selected.bind(layer_code, null))
	options_container.add_child(none_btn)

	# Add button for each part
	for part in parts:
		var part_container = HBoxContainer.new()

		# Part selection button
		var btn = Button.new()
		btn.text = part.display_name
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_part_selected.bind(layer_code, part))
		part_container.add_child(btn)

		options_container.add_child(part_container)

	# Add color ramp selector if this layer supports color swapping
	if ramp_type != null:
		var color_section = VBoxContainer.new()
		var color_label = Label.new()
		color_label.text = "  Color Ramp:"
		color_section.add_child(color_label)

		# Load and display the palette image
		var palette_image_path = get_palette_image_path(ramp_type)
		if FileAccess.file_exists(palette_image_path):
			var palette_texture = load(palette_image_path)
			if palette_texture:
				# Create a texture rect to show the palette
				var palette_display = TextureRect.new()
				palette_display.texture = palette_texture
				palette_display.expand_mode = TextureRect.EXPAND_FIT_WIDTH
				palette_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
				palette_display.custom_minimum_size = Vector2(0, 200)
				color_section.add_child(palette_display)

				# Add info label
				var info_label = Label.new()
				info_label.text = "  Click row to select color ramp"
				info_label.add_theme_font_size_override("font_size", 10)
				color_section.add_child(info_label)

		# Add a grid of color ramp buttons (first 10 rows)
		var ramp_grid = GridContainer.new()
		ramp_grid.columns = 5
		var ramps = color_ramps.get(ramp_type, [])
		for i in range(min(ramps.size(), 20)):  # Show first 20 ramps
			var btn = Button.new()
			btn.text = str(i + 1)
			btn.custom_minimum_size = Vector2(40, 30)
			btn.pressed.connect(_on_color_ramp_selected.bind(i, layer_code, ramp_type))
			ramp_grid.add_child(btn)

		color_section.add_child(ramp_grid)
		options_container.add_child(color_section)

func get_palette_image_path(ramp_type: String) -> String:
	"""Get the path to the palette image for a given ramp type"""
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
	"""Set up a default character with base body"""
	if "01body" in available_parts and available_parts["01body"].size() > 0:
		_on_part_selected("01body", available_parts["01body"][0])

func _on_part_selected(layer_code: String, part):
	"""Handle part selection"""
	print("Selected part for ", layer_code, ": ", part.display_name if part else "None")

	# Handle exclusive groups (bottomwear)
	var layer = LAYERS.get(layer_code)
	if layer and "exclusive_group" in layer:
		# Clear other selections in the same exclusive group
		for other_code in LAYERS.keys():
			var other_layer = LAYERS[other_code]
			if other_code != layer_code and "exclusive_group" in other_layer:
				if other_layer.exclusive_group == layer.exclusive_group:
					current_selections.erase(other_code)

	# Handle _e flag (headwear that replaces hair)
	if layer_code == "14head" and part != null and part.has_e_flag:
		# Hide hair when this headwear is equipped
		current_selections["13hair"] = null

	# Store selection
	current_selections[layer_code] = part
	update_preview()

func _on_color_ramp_selected(index: int, layer_code: String, ramp_type: String):
	"""Handle color ramp selection"""
	print("Selected color ramp for ", layer_code, ": index ", index)
	current_color_ramps[layer_code] = {
		"type": ramp_type,
		"index": index
	}
	apply_color_ramp(layer_code)

func update_preview():
	"""Update the character preview with current selections"""
	for layer_code in LAYERS.keys():
		var layer = LAYERS[layer_code]
		var sprite = character_layers.get_node(layer.node_name)
		sprite.z_index = layer.z_index

		if layer_code in current_selections and current_selections[layer_code] != null:
			var part = current_selections[layer_code]
			var texture = load(part.path)
			sprite.texture = texture
			sprite.visible = true

			# Apply shader if this layer supports color swapping
			if layer.ramp_type != null:
				var shader_material = ShaderMaterial.new()
				shader_material.shader = palette_shader
				sprite.material = shader_material
				apply_color_ramp(layer_code)
		else:
			sprite.texture = null
			sprite.visible = false
			sprite.material = null

	update_frame_display()

func apply_color_ramp(layer_code: String):
	"""Apply the selected color ramp to a layer's sprite"""
	if layer_code not in current_selections or current_selections[layer_code] == null:
		return

	var layer = LAYERS[layer_code]
	var sprite = character_layers.get_node(layer.node_name)

	if sprite.material == null or not sprite.material is ShaderMaterial:
		return

	var mat = sprite.material as ShaderMaterial

	# Set ramp type
	var ramp_type_int = 0
	if layer.ramp_type == "4color":
		ramp_type_int = 1
	elif layer.ramp_type == "hair":
		ramp_type_int = 2
	elif layer.ramp_type == "skin":
		ramp_type_int = 3

	mat.set_shader_parameter("ramp_type", ramp_type_int)

	# TODO: Set actual color values from palette images
	# For now, the shader will use its default base colors

func update_frame_display():
	"""Update the frame and direction display"""
	var anim_config = ANIMATIONS[current_animation]

	# Get the starting cell for the current direction
	var direction_cells = anim_config.cells
	var start_cell = direction_cells[current_direction]

	# Calculate the current frame cell
	var frame_cell = start_cell + current_frame

	for layer_code in LAYERS.keys():
		var layer = LAYERS[layer_code]
		var sprite = character_layers.get_node(layer.node_name)
		if sprite.visible and sprite.texture:
			sprite.frame = frame_cell

	frame_label.text = "Frame: " + str(current_frame + 1) + "/" + str(anim_config.frames)
	direction_label.text = "Direction: " + DIRECTIONS[current_direction]

func _on_direction_changed(direction: int):
	"""Handle direction button press"""
	current_direction = direction
	update_frame_display()

func _on_animation_selected(anim_key: String):
	"""Handle animation selection"""
	print("Selected animation: ", anim_key)
	current_animation = anim_key
	current_frame = 0
	animation_timer = 0.0
	update_frame_display()
