extends Node
class_name BattleSpriteAnimator

## BattleSpriteAnimator - Manages sprite animations for party members in battle
## Loads animation data from CSV and provides methods to play animations

# Mana Seed sprite system paths
const SPRITE_PATH = "res://assets/graphics/characters/New Character System/SpriteSystem/base_sheets/"
const PALETTE_PATH = "res://assets/graphics/characters/New Character System/SpriteSystem/_supporting files/palettes/"

# Mana Seed layer configuration (matching Player.gd)
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

# Palette images for color mapping (loaded at runtime)
var palette_images = {}

# Animation frame data structure
class AnimationFrame:
	var cell: int
	var timing: float  # in seconds
	var flip_h: bool
	var is_hold: bool  # true if timing is "hold"

	func _init(c: int, t: float, f: bool = false, h: bool = false):
		cell = c
		timing = t
		flip_h = f
		is_hold = h

# Animation definitions loaded from CSV
var animations = {}

# Sprite instances for each party member
# Key: combatant_id (e.g., "douglas", "kai")
# Value: {sprite: Sprite2D, current_anim: String, frame_index: int, timer: float, is_playing: bool, hold_until_clear: bool}
var sprite_instances = {}

# Character sprite sheet paths
var character_sprites = {
	"douglas": "res://assets/graphics/characters/New Character System/PartySpriteSheets/Douglas.png",
	"kai": "res://assets/graphics/characters/New Character System/PartySpriteSheets/Kai.png",
	"matcha": "res://assets/graphics/characters/New Character System/PartySpriteSheets/Matcha.png",
	"risa": "res://assets/graphics/characters/New Character System/PartySpriteSheets/Risa.png",
	"sev": "res://assets/graphics/characters/New Character System/PartySpriteSheets/Sev.png",
	"skye": "res://assets/graphics/characters/New Character System/PartySpriteSheets/Skye.png",
	"tessa": "res://assets/graphics/characters/New Character System/PartySpriteSheets/Tessa.png",
	"hero": "res://assets/graphics/characters/New Character System/PartySpriteSheets/Douglas.png",  # Default for hero
	# Enemy sprites
	"slime": "res://assets/graphics/characters/New Character System/EnemySpriteSheets/Slime.png",
	"goblin": "res://assets/graphics/characters/New Character System/EnemySpriteSheets/Goblin.png"
}

func _ready():
	_load_palettes()
	load_animations_from_csv()
	print("[BattleSpriteAnimator] Loaded %d animations from CSV" % animations.size())

func _load_palettes() -> void:
	"""Load palette images for color mapping"""
	print("[BattleSpriteAnimator] Loading palette images...")
	palette_images["3color"] = load(PALETTE_PATH + "mana seed 3-color ramps.png").get_image()
	palette_images["4color"] = load(PALETTE_PATH + "mana seed 4-color ramps.png").get_image()
	palette_images["hair"] = load(PALETTE_PATH + "mana seed hair ramps.png").get_image()
	palette_images["skin"] = load(PALETTE_PATH + "mana seed skin ramps.png").get_image()
	print("[BattleSpriteAnimator] Palette images loaded")

func _apply_color_mapping(original_texture: Texture2D, part: Dictionary, ramp_type: String, color_index: int) -> ImageTexture:
	"""Apply color mapping to a texture using palette ramps (matching Player.gd)"""
	var original_image = original_texture.get_image()
	var result_image = Image.create(original_image.get_width(), original_image.get_height(), false, Image.FORMAT_RGBA8)

	var palette_image = palette_images.get(ramp_type)
	if not palette_image:
		print("[BattleSpriteAnimator] ERROR: No palette for ramp_type: ", ramp_type)
		return ImageTexture.create_from_image(original_image)

	var palette_code = part.get("palette_code", "00")
	var source_row = int(palette_code)
	var target_row = color_index

	if source_row < 0 or source_row >= palette_image.get_height():
		print("[BattleSpriteAnimator] ERROR: Invalid source row: ", source_row)
		return ImageTexture.create_from_image(original_image)

	if target_row < 0 or target_row >= palette_image.get_height():
		print("[BattleSpriteAnimator] ERROR: Invalid target row: ", target_row)
		return ImageTexture.create_from_image(original_image)

	# Build color mapping dictionary
	var color_map = {}
	var palette_width = palette_image.get_width()

	for x in range(palette_width):
		var source_color = palette_image.get_pixel(x, source_row)
		var target_color = palette_image.get_pixel(x, target_row)
		if source_color.a > 0.1:
			color_map[source_color.to_html(false)] = target_color

	# Apply color mapping
	for y in range(original_image.get_height()):
		for x in range(original_image.get_width()):
			var pixel = original_image.get_pixel(x, y)
			if pixel.a > 0.1:
				var pixel_key = pixel.to_html(false)
				if color_map.has(pixel_key):
					result_image.set_pixel(x, y, color_map[pixel_key])
				else:
					result_image.set_pixel(x, y, pixel)
			else:
				result_image.set_pixel(x, y, pixel)

	return ImageTexture.create_from_image(result_image)

func _process(delta):
	# Update all active sprite animations
	for combatant_id in sprite_instances:
		_update_sprite_animation(combatant_id, delta)

func load_animations_from_csv():
	"""Load all animation definitions from CSV file"""
	var file_path = "res://scenes/test/sprite_animations_data.csv"
	var file = FileAccess.open(file_path, FileAccess.READ)

	if file == null:
		push_error("[BattleSpriteAnimator] Could not open CSV file: " + file_path)
		return

	# Skip header
	file.get_csv_line()

	# Read each line
	while !file.eof_reached():
		var line = file.get_csv_line()
		if line.size() < 4:
			continue

		var anim_name = line[0].strip_edges()
		var direction = line[1].strip_edges()
		var frame_count_str = line[2].strip_edges()

		if anim_name.is_empty() or direction.is_empty():
			continue

		# Create animation key: "AnimName_DIRECTION"
		var anim_key = anim_name + "_" + direction

		# Parse frames
		var frames = []
		var col_idx = 3

		# Read up to 6 frames (Cell + Time pairs)
		for i in range(6):
			var cell_col = col_idx + (i * 2)
			var time_col = cell_col + 1

			if cell_col >= line.size() or time_col >= line.size():
				break

			var cell_str = line[cell_col].strip_edges()
			var time_str = line[time_col].strip_edges()

			if cell_str.is_empty() or time_str.is_empty():
				break

			# Parse cell number and flip flag
			var cell_num = 0
			var flip = false

			# Check for 'f' or 'F' suffix
			if cell_str.to_lower().ends_with("f"):
				flip = true
				cell_str = cell_str.substr(0, cell_str.length() - 1)

			cell_num = int(cell_str)

			# Parse timing (could be number or "hold"/"Hold")
			var timing = 0.0
			var is_hold = false

			if time_str.to_lower() == "hold":
				is_hold = true
				timing = 999999.0  # Very long time for hold frames
			else:
				# Convert milliseconds to seconds
				timing = float(time_str) / 1000.0

			frames.append(AnimationFrame.new(cell_num, timing, flip, is_hold))

		if frames.size() > 0:
			animations[anim_key] = frames

	file.close()
	print("[BattleSpriteAnimator] Loaded animation keys: %d" % animations.size())

func create_sprite_for_combatant(combatant_id: String, parent: Node, display_name: String = "", is_ally: bool = true) -> Node:
	"""Create a sprite node for a combatant (ally or enemy)

	Args:
		combatant_id: The unique ID of the combatant (e.g., "best_friend", "green_friend", "slime_0")
		parent: The node to add the sprite to
		display_name: The display name of the character (e.g., "Kai", "Matcha", "Slime")
		is_ally: True for allies (face RIGHT), False for enemies (face LEFT)
	"""
	# Use display_name for sprite lookup if provided, otherwise fall back to ID
	var lookup_name = display_name.to_lower() if not display_name.is_empty() else combatant_id.to_lower()

	# Remove number suffix from enemy IDs (e.g., "slime_0" -> "slime")
	if "_" in lookup_name and lookup_name.split("_")[-1].is_valid_int():
		lookup_name = "_".join(lookup_name.split("_").slice(0, -1))

	# Remove letter suffix from duplicate enemy names (e.g., "goblin a" -> "goblin", "slime b" -> "slime")
	var suffix_pattern = RegEx.new()
	suffix_pattern.compile("\\s+[a-h]$")  # Match space + single letter A-H at end
	lookup_name = suffix_pattern.sub(lookup_name, "", true)

	print("[BattleSpriteAnimator] Creating sprite for combatant ID: %s, Display Name: %s, Lookup: %s, is_ally: %s" % [combatant_id, display_name, lookup_name, is_ally])
	print("[BattleSpriteAnimator] Available character sprites: %s" % str(character_sprites.keys()))
	print("[BattleSpriteAnimator] Parent node: %s" % str(parent))

	# For hero, use layered system (body + hair)
	if combatant_id.to_lower() == "hero":
		return _create_layered_sprite_for_hero(combatant_id, parent, is_ally)

	if not character_sprites.has(lookup_name):
		push_error("[BattleSpriteAnimator] No sprite sheet found for: %s (display_name: %s, id: %s)" % [lookup_name, display_name, combatant_id])
		return null

	var sprite = Sprite2D.new()
	sprite.name = "BattleSprite_" + combatant_id
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # Pixel-perfect rendering

	# Load texture using the lookup name
	var texture_path = character_sprites[lookup_name]
	var texture = load(texture_path)
	if texture:
		sprite.texture = texture
		sprite.hframes = 16
		sprite.vframes = 16
		sprite.frame = 0  # Start with idle frame
		print("[BattleSpriteAnimator] Created sprite for %s from %s" % [combatant_id, texture_path])
	else:
		push_error("[BattleSpriteAnimator] Failed to load texture: " + texture_path)
		return null

	# Add to parent
	if parent:
		parent.add_child(sprite)
		print("[BattleSpriteAnimator] Sprite added to parent successfully")
	else:
		print("[BattleSpriteAnimator] ERROR: No parent provided!")

	# Determine default direction based on ally/enemy
	var default_direction = "RIGHT" if is_ally else "LEFT"

	# Track sprite instance
	sprite_instances[combatant_id] = {
		"sprite": sprite,
		"current_anim": "Idle_" + default_direction,
		"frame_index": 0,
		"timer": 0.0,
		"is_playing": false,
		"hold_until_clear": false,  # For animations that hold until manually cleared
		"play_once": false,  # For animations that play once then return to idle
		"default_direction": default_direction  # Default facing direction for idle
	}

	# Play idle animation by default
	play_animation(combatant_id, "Idle", default_direction)

	return sprite

func _create_layered_sprite_for_hero(combatant_id: String, parent: Node, is_ally: bool = true) -> Node2D:
	"""Create a full Mana Seed layered sprite system for the hero"""
	print("[BattleSpriteAnimator] Creating Mana Seed layered sprite for hero...")

	# Create a container for layers
	var container = Node2D.new()
	container.name = "HeroSpriteContainer_" + combatant_id

	# Create all sprite layer nodes
	var layer_sprites = {}
	for layer in LAYERS:
		var sprite_codes = []
		if "sprite_layers" in layer:
			sprite_codes = layer.sprite_layers
		else:
			sprite_codes = [layer.code]

		for sprite_code in sprite_codes:
			var sprite = Sprite2D.new()
			sprite.name = sprite_code
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.hframes = 16
			sprite.vframes = 16
			sprite.frame = 0
			sprite.visible = true
			container.add_child(sprite)
			layer_sprites[sprite_code] = sprite

	# Add underwear layer (00undr) for auto-matching
	var undr_sprite = Sprite2D.new()
	undr_sprite.name = "00undr"
	undr_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	undr_sprite.hframes = 16
	undr_sprite.vframes = 16
	undr_sprite.frame = 0
	undr_sprite.visible = true
	container.add_child_at_index(undr_sprite, 0)  # Add at beginning
	layer_sprites["00undr"] = undr_sprite

	# Get hero appearance from GameState
	var gs = get_node_or_null("/root/aGameState")
	var character_selections: Dictionary = {}
	var character_colors: Dictionary = {}

	if gs and gs.has_meta("hero_identity"):
		var hero_id = gs.get_meta("hero_identity")
		if typeof(hero_id) == TYPE_DICTIONARY:
			print("[BattleSpriteAnimator] hero_identity found: ", hero_id.keys())
			if hero_id.has("character_selections"):
				character_selections = hero_id.get("character_selections", {})
			if hero_id.has("character_colors"):
				character_colors = hero_id.get("character_colors", {})
			print("[BattleSpriteAnimator] Loaded ", character_selections.size(), " parts and ", character_colors.size(), " colors")
	else:
		print("[BattleSpriteAnimator] WARNING: No hero_identity meta found in GameState!")
		# Create default naked character with just body
		character_colors["01body"] = 0

	# Load sprites for each layer (matching Player.gd logic)
	for layer in LAYERS:
		var layer_code = layer.code
		var sprite_codes = []
		if "sprite_layers" in layer:
			sprite_codes = layer.sprite_layers
		else:
			sprite_codes = [layer_code]

		# Get selected part
		var part = null
		if layer.has_parts:
			part = character_selections.get(layer_code, null)
		else:
			# Body layer - load default body sprite
			if layer_code == "01body":
				var body_dir = SPRITE_PATH + "01body/"
				var dir = DirAccess.open(body_dir)
				if dir:
					dir.list_dir_begin()
					var file_name = dir.get_next()
					while file_name != "":
						if file_name.ends_with(".png") and file_name.begins_with("fbas_"):
							part = {
								"name": file_name.get_basename(),
								"path": body_dir + file_name,
								"base_name": "",
								"palette_code": "00",
								"display_name": "Body"
							}
							var parts_arr = file_name.get_basename().split("_")
							if parts_arr.size() >= 4:
								part["palette_code"] = parts_arr[3]
							break
						file_name = dir.get_next()
					dir.list_dir_end()

		# Apply to all sprite nodes for this layer
		for sprite_code in sprite_codes:
			var sprite = layer_sprites.get(sprite_code)
			if not sprite:
				continue

			if part == null:
				sprite.texture = null
				continue

			# For combined layers, only apply if the part belongs to this sprite layer
			if "sprite_layers" in layer:
				if part.get("sprite_code", "") != sprite_code:
					sprite.texture = null
					continue

			# Load texture
			var texture_path = part.get("path", "")
			if texture_path == "" or not FileAccess.file_exists(texture_path):
				print("[BattleSpriteAnimator] ERROR: Texture not found: ", texture_path)
				sprite.texture = null
				continue

			var original_texture = load(texture_path)

			# Apply color mapping if color is selected
			if layer_code in character_colors:
				var color_index = character_colors[layer_code]
				var recolored_texture = _apply_color_mapping(original_texture, part, layer.ramp_type, color_index)
				sprite.texture = recolored_texture
			else:
				sprite.texture = original_texture

		# Auto-match layer (e.g., underwear for neckwear)
		if "auto_match_layer" in layer and part != null:
			var auto_layer_code = layer.auto_match_layer
			var auto_sprite = layer_sprites.get(auto_layer_code)

			if auto_sprite:
				var matching_part = null
				var auto_dir_path = SPRITE_PATH + auto_layer_code + "/"
				var auto_dir = DirAccess.open(auto_dir_path)

				if auto_dir:
					auto_dir.list_dir_begin()
					var file_name = auto_dir.get_next()
					while file_name != "":
						if file_name.ends_with(".png") and file_name.begins_with("fbas_"):
							var file_parts = file_name.get_basename().split("_")
							if file_parts.size() >= 4 and file_parts[2] == part.get("base_name", ""):
								matching_part = {
									"name": file_name.get_basename(),
									"path": auto_dir_path + file_name,
									"base_name": file_parts[2],
									"palette_code": file_parts[3],
									"display_name": file_parts[2].capitalize()
								}
								break
						file_name = auto_dir.get_next()
					auto_dir.list_dir_end()

				if matching_part != null:
					var auto_texture = load(matching_part.path)
					if layer_code in character_colors:
						var color_index = character_colors[layer_code]
						var recolored_texture = _apply_color_mapping(auto_texture, matching_part, layer.ramp_type, color_index)
						auto_sprite.texture = recolored_texture
					else:
						auto_sprite.texture = auto_texture
				else:
					auto_sprite.texture = null
		elif "auto_match_layer" in layer and part == null:
			var auto_layer_code = layer.auto_match_layer
			var auto_sprite = layer_sprites.get(auto_layer_code)
			if auto_sprite:
				auto_sprite.texture = null

	# Add container to parent
	if parent:
		parent.add_child(container)

	# Determine default direction based on ally/enemy
	var default_direction = "RIGHT" if is_ally else "LEFT"

	# Track all layers for animation updates
	sprite_instances[combatant_id] = {
		"sprite": container,
		"layer_sprites": layer_sprites,  # All layer sprites
		"current_anim": "Idle_" + default_direction,
		"frame_index": 0,
		"timer": 0.0,
		"is_playing": false,
		"hold_until_clear": false,
		"play_once": false,
		"default_direction": default_direction,
		"is_layered": true
	}

	# Play idle animation by default
	play_animation(combatant_id, "Idle", default_direction)

	print("[BattleSpriteAnimator] Created Mana Seed layered sprite for hero with %d layers" % layer_sprites.size())
	return container

func play_animation(combatant_id: String, anim_name: String, direction: String = "RIGHT", hold: bool = false, play_once: bool = false):
	"""Play an animation for a specific combatant

	Args:
		combatant_id: ID of the combatant ("douglas", "kai", etc.)
		anim_name: Animation name (e.g., "Walk", "Sword Strike")
		direction: Direction to face (UP, DOWN, LEFT, RIGHT)
		hold: If true, animation will hold on last frame until cleared
		play_once: If true, animation plays once then returns to idle
	"""
	if not sprite_instances.has(combatant_id):
		print("[BattleSpriteAnimator] No sprite instance for: " + combatant_id)
		return

	var anim_key = anim_name + "_" + direction

	if not animations.has(anim_key):
		print("[BattleSpriteAnimator] Animation not found: " + anim_key)
		return

	var instance = sprite_instances[combatant_id]
	instance["current_anim"] = anim_key
	instance["frame_index"] = 0
	instance["timer"] = 0.0
	instance["is_playing"] = true
	instance["hold_until_clear"] = hold
	instance["play_once"] = play_once
	instance["default_direction"] = direction  # Remember direction for returning to idle

	# Apply first frame immediately
	_apply_frame(combatant_id, 0)

	print("[BattleSpriteAnimator] Playing %s for %s (hold: %s, play_once: %s)" % [anim_key, combatant_id, hold, play_once])

func clear_hold(combatant_id: String):
	"""Clear a held animation and return to idle"""
	if not sprite_instances.has(combatant_id):
		return

	var instance = sprite_instances[combatant_id]
	instance["hold_until_clear"] = false

	# Return to idle
	play_animation(combatant_id, "Idle", "RIGHT")

func _update_sprite_animation(combatant_id: String, delta: float):
	"""Update animation for a specific sprite"""
	if not sprite_instances.has(combatant_id):
		return

	var instance = sprite_instances[combatant_id]
	if not instance["is_playing"]:
		return

	var anim_key = instance["current_anim"]
	if not animations.has(anim_key):
		return

	var anim_data = animations[anim_key]
	if anim_data.size() == 0:
		return

	var frame_index = instance["frame_index"]
	var frame_data = anim_data[frame_index]

	# Don't advance if it's a hold frame
	if frame_data.is_hold:
		# If hold_until_clear is true, stay on this frame indefinitely
		if instance["hold_until_clear"]:
			return
		# Otherwise, still don't advance but allow animation to loop
		return

	# Update timer
	instance["timer"] += delta

	# Check if we need to advance to next frame
	if instance["timer"] >= frame_data.timing:
		instance["timer"] = 0.0
		var next_frame = frame_index + 1

		# Check if animation completed
		if next_frame >= anim_data.size():
			# Animation completed one loop
			if instance["play_once"]:
				# Return to idle animation
				var default_dir = instance.get("default_direction", "RIGHT")
				play_animation(combatant_id, "Idle", default_dir)
				print("[BattleSpriteAnimator] Play-once animation complete for %s, returning to idle" % combatant_id)
				return
			else:
				# Loop animation
				next_frame = 0

		instance["frame_index"] = next_frame
		_apply_frame(combatant_id, instance["frame_index"])

func _apply_frame(combatant_id: String, frame_index: int):
	"""Apply a specific frame to a sprite"""
	if not sprite_instances.has(combatant_id):
		return

	var instance = sprite_instances[combatant_id]
	var anim_key = instance["current_anim"]

	if not animations.has(anim_key):
		return

	var anim_data = animations[anim_key]
	if frame_index >= anim_data.size():
		return

	var frame_data = anim_data[frame_index]

	# Handle layered sprites (hero with Mana Seed system)
	if instance.get("is_layered", false):
		var layer_sprites = instance.get("layer_sprites", {})
		# Update all visible layers
		for sprite_code in layer_sprites:
			var sprite = layer_sprites[sprite_code]
			if sprite and sprite.visible and sprite.texture:
				sprite.frame = frame_data.cell
				sprite.flip_h = frame_data.flip_h
	else:
		# Handle regular single sprite
		var sprite = instance["sprite"]
		sprite.frame = frame_data.cell
		sprite.flip_h = frame_data.flip_h

func get_sprite(combatant_id: String) -> Sprite2D:
	"""Get the sprite node for a combatant"""
	if not sprite_instances.has(combatant_id):
		return null
	return sprite_instances[combatant_id]["sprite"]

func play_animation_for_all(anim_name: String, direction: String = "RIGHT", hold: bool = false, play_once: bool = false):
	"""Play an animation for all active party members"""
	for combatant_id in sprite_instances.keys():
		play_animation(combatant_id, anim_name, direction, hold, play_once)

func remove_sprite(combatant_id: String):
	"""Remove a sprite instance"""
	if not sprite_instances.has(combatant_id):
		return

	var instance = sprite_instances[combatant_id]
	var sprite = instance["sprite"]
	if sprite:
		sprite.queue_free()

	sprite_instances.erase(combatant_id)
	print("[BattleSpriteAnimator] Removed sprite for: " + combatant_id)
