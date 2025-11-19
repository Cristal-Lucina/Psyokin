extends Node
class_name BattleSpriteAnimator

## BattleSpriteAnimator - Manages sprite animations for party members in battle
## Loads animation data from CSV and provides methods to play animations

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
	load_animations_from_csv()
	print("[BattleSpriteAnimator] Loaded %d animations from CSV" % animations.size())

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
	"""Create a layered sprite system for the hero (body + hair)"""
	# Create a container for layers
	var container = Node2D.new()
	container.name = "HeroSpriteContainer_" + combatant_id

	# Create body layer
	var body_sprite = Sprite2D.new()
	body_sprite.name = "BodyLayer"
	body_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	body_sprite.hframes = 16
	body_sprite.vframes = 16
	body_sprite.frame = 0

	# Create hair layer
	var hair_sprite = Sprite2D.new()
	hair_sprite.name = "HairLayer"
	hair_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hair_sprite.hframes = 16
	hair_sprite.vframes = 16
	hair_sprite.frame = 0

	# Get hero appearance from GameState
	var gs = get_node_or_null("/root/aGameState")
	var body_variant = "human_00"  # Default
	var hair_variant = "twintail_00"  # Default

	if gs and gs.has_meta("hero_identity"):
		var hero_identity = gs.get_meta("hero_identity")
		if typeof(hero_identity) == TYPE_DICTIONARY and hero_identity.has("character_variants"):
			var variants = hero_identity["character_variants"]
			if variants.has("body"):
				body_variant = variants["body"]
			if variants.has("hair"):
				hair_variant = variants["hair"]

	# Load body texture with fallback
	var body_path = "res://assets/graphics/characters/New Character System/SpriteSystem/farmer_base_sheets/01body/fbas_01body_" + body_variant + ".png"
	var body_texture = null
	if FileAccess.file_exists(body_path):
		body_texture = load(body_path)

	if body_texture:
		body_sprite.texture = body_texture
		print("[BattleSpriteAnimator] Loaded hero body: %s" % body_path)
	else:
		print("[BattleSpriteAnimator] Failed to load hero body: %s, using default" % body_path)
		# Fallback to default
		var default_body_path = "res://assets/graphics/characters/New Character System/SpriteSystem/farmer_base_sheets/01body/fbas_01body_human_00.png"
		body_texture = load(default_body_path)
		if body_texture:
			body_sprite.texture = body_texture

	# Load hair texture with fallback
	var hair_path = "res://assets/graphics/characters/New Character System/SpriteSystem/farmer_base_sheets/13hair/fbas_13hair_" + hair_variant + ".png"
	var hair_texture = null
	if FileAccess.file_exists(hair_path):
		hair_texture = load(hair_path)

	if hair_texture:
		hair_sprite.texture = hair_texture
		print("[BattleSpriteAnimator] Loaded hero hair: %s" % hair_path)
	else:
		print("[BattleSpriteAnimator] Failed to load hero hair: %s, using default" % hair_path)
		# Fallback to default
		var default_hair_path = "res://assets/graphics/characters/New Character System/SpriteSystem/farmer_base_sheets/13hair/fbas_13hair_twintail_00.png"
		hair_texture = load(default_hair_path)
		if hair_texture:
			hair_sprite.texture = hair_texture

	# Add layers to container
	container.add_child(body_sprite)
	container.add_child(hair_sprite)

	# Add container to parent
	if parent:
		parent.add_child(container)

	# Determine default direction based on ally/enemy
	var default_direction = "RIGHT" if is_ally else "LEFT"

	# Track both layers for animation updates
	sprite_instances[combatant_id] = {
		"sprite": container,  # Use container as the main sprite reference
		"body_layer": body_sprite,
		"hair_layer": hair_sprite,
		"current_anim": "Idle_" + default_direction,
		"frame_index": 0,
		"timer": 0.0,
		"is_playing": false,
		"hold_until_clear": false,
		"play_once": false,
		"default_direction": default_direction,
		"is_layered": true  # Flag to indicate this is a layered sprite
	}

	# Play idle animation by default
	play_animation(combatant_id, "Idle", default_direction)

	print("[BattleSpriteAnimator] Created layered sprite for hero")
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

	# Handle layered sprites (hero)
	if instance.get("is_layered", false):
		var body_layer = instance.get("body_layer")
		var hair_layer = instance.get("hair_layer")
		if body_layer:
			body_layer.frame = frame_data.cell
			body_layer.flip_h = frame_data.flip_h
		if hair_layer:
			hair_layer.frame = frame_data.cell
			hair_layer.flip_h = frame_data.flip_h
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
