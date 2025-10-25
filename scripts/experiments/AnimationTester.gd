extends Control

## Animation Tester
## Tests all animations with selected character variants
## Auto-connects matching variants across animation pages (p1, p2, p3, p4)

# Character directories
const CHAR_BASE_PATH = "res://assets/graphics/characters/"

# Layer configuration (same as CharacterCreator)
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

# Direction mapping
const DIRECTIONS = {
	0: "South",
	1: "North",
	2: "East",
	3: "West"
}

# Animation configurations
const ANIMATIONS = {
	"walk": {"page": "p1", "rows": [4, 5, 6, 7], "frames": 6, "speed": 0.135},
	"run": {"page": "p1", "rows": [4, 5, 6, 7], "frames": 6, "speed": 0.080, "custom_frames": [0, 1, 6, 3, 4, 7]},
	"jump": {"page": "p1", "rows": [0, 1, 2, 3], "frames": 4, "speed": 0.200, "custom_frames": [5, 6, 7, 5]},
	"push": {"page": "p1", "rows": [0, 1, 2, 3], "frames": 2, "frame_offset": 1, "speed": 0.300},
	"pull": {"page": "p1", "rows": [0, 1, 2, 3], "frames": 2, "frame_offset": 3, "speed": 0.400}
}

# References
@onready var character_layers = $MainContainer/PreviewPanel/PreviewContainer/CenterContainer/CharacterLayers
@onready var anim_label = $MainContainer/PreviewPanel/PreviewContainer/AnimationInfo/AnimLabel
@onready var frame_label = $MainContainer/PreviewPanel/PreviewContainer/AnimationInfo/FrameLabel
@onready var direction_label = $MainContainer/PreviewPanel/PreviewContainer/AnimationInfo/DirectionLabel
@onready var variants_label = $MainContainer/ControlsPanel/ControlsContainer/CharacterInfo/VariantsLabel

# State
var selected_variants = {}  # Variant codes from character creator
var current_animation = "walk"
var current_direction = 0
var current_frame = 0
var animation_timer = 0.0

func _ready():
	print("Animation Tester starting...")
	# Load character data from global
	if aCharacterData.has_character():
		selected_variants = aCharacterData.get_variants()
		print("Loaded character variants: ", selected_variants)
	else:
		# Use test data if no character was created
		selected_variants = {
			"base": "humn_v00",
			"hair": "bob1_v00"
		}
		print("No character data found, using test data")

	update_variants_display()
	load_character_for_animation(current_animation)
	update_display()

func update_variants_display():
	"""Display the selected character variants"""
	var text = ""
	for layer_key in selected_variants:
		text += layer_key.capitalize() + ": " + selected_variants[layer_key] + "\n"
	variants_label.text = text if text != "" else "No character loaded"

func load_character_for_animation(anim_name: String):
	"""Load character parts for the specified animation
	Auto-connects matching variants across pages"""

	if anim_name not in ANIMATIONS:
		print("ERROR: Unknown animation: ", anim_name)
		return

	var anim_config = ANIMATIONS[anim_name]
	var page = anim_config.page

	print("Loading character for animation: ", anim_name, " (page: ", page, ")")

	# Load each layer with matching variant
	for layer_key in LAYERS:
		var layer = LAYERS[layer_key]
		var sprite = character_layers.get_node(layer.node_name)

		# Check if this layer was selected
		if layer_key not in selected_variants:
			sprite.texture = null
			sprite.visible = false
			continue

		var variant_code = selected_variants[layer_key]

		# Build the filename for this page and variant
		var filename = build_filename(page, layer.code, variant_code)
		var file_path = find_character_file(page, layer, variant_code)

		if file_path != "":
			print("  Loading ", layer_key, ": ", file_path)
			var texture = load(file_path)
			sprite.texture = texture
			sprite.visible = true
		else:
			print("  WARNING: Could not find file for ", layer_key, " variant ", variant_code, " on page ", page)
			sprite.visible = false

func build_filename(page: String, layer_code: String, variant_code: String) -> String:
	"""Build filename from components
	Example: 'p1', '0bas', 'humn_v06' -> 'char_a_p1_0bas_humn_v06.png'
	"""
	return "char_a_" + page + "_" + layer_code + "_" + variant_code + ".png"

func find_character_file(page: String, layer: Dictionary, variant_code: String) -> String:
	"""Find the character file for the given page, layer, and variant"""
	var variant_path = CHAR_BASE_PATH + "char_a_" + page + "/"
	var filename = build_filename(page, layer.code, variant_code)

	# Check if file exists
	var full_path = ""
	if layer.path == "":
		# Base layer - file is in root of variant folder
		full_path = variant_path + filename
	else:
		# Other layers - file is in subdirectory
		full_path = variant_path + layer.path + "/" + filename

	# Verify file exists
	if FileAccess.file_exists(full_path):
		return full_path
	else:
		return ""

func _process(delta):
	"""Animate the character"""
	var anim_config = ANIMATIONS[current_animation]
	var speed = anim_config.speed

	animation_timer += delta
	if animation_timer >= speed:
		animation_timer = 0.0

		# Advance frame
		var max_frames = anim_config.frames
		current_frame = (current_frame + 1) % max_frames

		update_display()

func update_display():
	"""Update the character sprite frames and labels"""
	var anim_config = ANIMATIONS[current_animation]

	# Get the row for current direction
	var direction_row = anim_config.rows[current_direction]

	# Calculate frame offset
	var frame_offset = anim_config.get("frame_offset", 0)
	var frame_to_show = current_frame + frame_offset

	# Handle custom frame sequences (like run animation)
	if "custom_frames" in anim_config:
		frame_to_show = anim_config.custom_frames[current_frame]

	# Update all visible sprites
	for layer_key in LAYERS:
		var layer = LAYERS[layer_key]
		var sprite = character_layers.get_node(layer.node_name)
		if sprite.visible and sprite.texture:
			sprite.frame = direction_row * 8 + frame_to_show

	# Update labels
	anim_label.text = "Animation: " + current_animation.capitalize()
	frame_label.text = "Frame: " + str(current_frame + 1) + "/" + str(anim_config.frames)
	direction_label.text = "Direction: " + DIRECTIONS[current_direction]

func _on_animation_selected(anim_name: String):
	"""Handle animation selection"""
	print("Selected animation: ", anim_name)
	current_animation = anim_name
	current_frame = 0
	animation_timer = 0.0
	load_character_for_animation(anim_name)
	update_display()

func _on_direction_changed(direction: int):
	"""Handle direction change"""
	current_direction = direction
	update_display()

func _on_back_pressed():
	"""Go back to character creator"""
	get_tree().change_scene_to_file("res://scenes/experiments/CharacterCreator.tscn")
