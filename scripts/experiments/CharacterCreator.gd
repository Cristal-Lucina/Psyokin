extends Control

## Character Creator Experiment
## A standalone scene to experiment with the Mana Seed character layering system
##
## Layer Order (bottom to top):
## - 0bas: Base body (required)
## - 1out: Outfit
## - 2clo: Cloak/Cape
## - 3fac: Face items (glasses, masks)
## - 4har: Hair
## - 5hat: Hats
## - 6tla: Tool A (weapons)
## - 7tlb: Tool B (shields, off-hand)

# Character directories
const CHAR_BASE_PATH = "res://assets/graphics/characters/"
# Only use p1 (page 1: walk/run animations)
const CHAR_VARIANTS = ["char_a_p1"]

# Layer configuration
const LAYERS = {
	"base": {"code": "0bas", "node_name": "BaseSprite", "path": ""},
	"outfit": {"code": "1out", "node_name": "OutfitSprite", "path": "1out"},
	"cloak": {"code": "2clo", "node_name": "CloakSprite", "path": "2clo"},
	"face": {"code": "3fac", "node_name": "FaceSprite", "path": "3fac"},
	"hair": {"code": "4har", "node_name": "HairSprite", "path": "4har"},
	"hat": {"code": "5hat", "node_name": "HatSprite", "path": "5hat"},
	"tool_a": {"code": "6tla", "node_name": "ToolASprite", "path": "6tla"},
	"tool_b": {"code": "7tlb", "node_name": "ToolBSprite", "path": "7tlb"}
}

# Direction mapping (row in sprite sheet)
const DIRECTIONS = {
	0: "South",
	1: "North",
	2: "East",
	3: "West"
}

# References
@onready var character_layers = $MainContainer/PreviewPanel/PreviewContainer/CenterContainer/CharacterLayers
@onready var parts_container = $MainContainer/ControlsPanel/ControlsContainer/ScrollContainer/PartsContainer
@onready var frame_label = $MainContainer/PreviewPanel/PreviewContainer/AnimationControls/FrameLabel
@onready var direction_label = $MainContainer/PreviewPanel/PreviewContainer/AnimationControls/DirectionLabel

# State
var current_direction = 0  # South
var current_frame = 0
var available_parts = {}
var current_selections = {}
# Walk animation (6 frames, rows 5-8)
var animation_timer = 0.0
var animation_speed = 0.135  # 135ms per frame for walk

func _ready():
	print("Character Creator starting...")
	scan_character_assets()
	populate_ui()
	set_default_character()
	update_preview()

func _process(delta):
	# Walk animation cycling (6 frames)
	animation_timer += delta
	if animation_timer >= animation_speed:
		animation_timer = 0.0
		current_frame = (current_frame + 1) % 6  # Walk has 6 frames (0-5)
		update_frame_display()

func scan_character_assets():
	"""Scan the character assets folder to find all available parts"""
	print("Scanning character assets...")

	for variant in CHAR_VARIANTS:
		var variant_path = CHAR_BASE_PATH + variant + "/"
		var dir = DirAccess.open(variant_path)

		if dir == null:
			print("Could not open directory: ", variant_path)
			continue

		# Scan each layer
		for layer_key in LAYERS:
			var layer = LAYERS[layer_key]
			var layer_path = variant_path + layer.path

			if layer_key not in available_parts:
				available_parts[layer_key] = []

			# For base layer, files are directly in variant folder
			if layer.path == "":
				dir.list_dir_begin()
				var file_name = dir.get_next()
				while file_name != "":
					if file_name.ends_with(".png") and layer.code in file_name:
						var full_path = variant_path + file_name
						available_parts[layer_key].append({
							"name": file_name.get_basename(),
							"path": full_path
						})
					file_name = dir.get_next()
				dir.list_dir_end()
			else:
				# For other layers, check subdirectory
				var subdir = DirAccess.open(layer_path)
				if subdir:
					subdir.list_dir_begin()
					var file_name = subdir.get_next()
					while file_name != "":
						if file_name.ends_with(".png"):
							var full_path = layer_path + "/" + file_name
							available_parts[layer_key].append({
								"name": file_name.get_basename(),
								"path": full_path
							})
						file_name = subdir.get_next()
					subdir.list_dir_end()

	print("Asset scan complete. Found:")
	for layer_key in available_parts:
		print("  ", layer_key, ": ", available_parts[layer_key].size(), " items")

func populate_ui():
	"""Create UI controls for each available part"""

	# Base options
	var base_container = parts_container.get_node("BaseSection/BaseOptions")
	populate_layer_options(base_container, "base")

	# Outfit options
	var outfit_container = parts_container.get_node("OutfitSection/OutfitOptions")
	populate_layer_options(outfit_container, "outfit")

	# Hair options
	var hair_container = parts_container.get_node("HairSection/HairOptions")
	populate_layer_options(hair_container, "hair")

	# Hat options
	var hat_container = parts_container.get_node("HatSection")
	if hat_container.has_node("HatOptions"):
		# Node exists in HatSection
		populate_layer_options(hat_container.get_node("HatOptions"), "hat")
	else:
		# Check if it's at the wrong level
		var hat_options = parts_container.get_node("HatOptions")
		if hat_options:
			populate_layer_options(hat_options, "hat")

func populate_layer_options(container: Node, layer_key: String):
	"""Populate a container with buttons for each part option"""
	if layer_key not in available_parts:
		return

	# Add "None" option
	var none_btn = Button.new()
	none_btn.text = "None"
	none_btn.pressed.connect(_on_part_selected.bind(layer_key, null))
	container.add_child(none_btn)

	# Add button for each available part
	for part in available_parts[layer_key]:
		var btn = Button.new()
		btn.text = part.name
		btn.pressed.connect(_on_part_selected.bind(layer_key, part))
		container.add_child(btn)

func set_default_character():
	"""Set up a default character with base body"""
	if "base" in available_parts and available_parts["base"].size() > 0:
		_on_part_selected("base", available_parts["base"][0])

func _on_part_selected(layer_key: String, part):
	"""Handle part selection"""
	current_selections[layer_key] = part
	update_preview()

func update_preview():
	"""Update the character preview with current selections"""
	for layer_key in LAYERS:
		var layer = LAYERS[layer_key]
		var sprite = character_layers.get_node(layer.node_name)

		if layer_key in current_selections and current_selections[layer_key] != null:
			var part = current_selections[layer_key]
			var texture = load(part.path)
			sprite.texture = texture
			sprite.visible = true
		else:
			sprite.texture = null
			sprite.visible = false

	update_frame_display()

func update_frame_display():
	"""Update the frame and direction display"""
	for layer_key in LAYERS:
		var layer = LAYERS[layer_key]
		var sprite = character_layers.get_node(layer.node_name)
		if sprite.visible and sprite.texture:
			# Walk animation is on rows 5-8 (direction + 4)
			# Rows 1-4 have idle/push/pull/jump
			# Rows 5-8 have walk animation (6 frames: 0-5)
			var walk_row = current_direction + 4
			sprite.frame = walk_row * 8 + current_frame

	frame_label.text = "Walk Frame: " + str(current_frame + 1) + "/6"
	direction_label.text = "Direction: " + DIRECTIONS[current_direction]

func _on_direction_changed(direction: int):
	"""Handle direction button press"""
	current_direction = direction
	update_frame_display()
