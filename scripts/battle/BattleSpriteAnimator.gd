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
	"hero": "res://assets/graphics/characters/New Character System/PartySpriteSheets/Douglas.png"  # Default for hero
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

func create_sprite_for_combatant(combatant_id: String, parent: Node) -> Sprite2D:
	"""Create a sprite node for a party member"""
	var member_id = combatant_id.to_lower()

	if not character_sprites.has(member_id):
		push_error("[BattleSpriteAnimator] No sprite sheet found for: " + member_id)
		return null

	var sprite = Sprite2D.new()
	sprite.name = "BattleSprite_" + combatant_id
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # Pixel-perfect rendering

	# Load texture
	var texture_path = character_sprites[member_id]
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

	# Track sprite instance
	sprite_instances[combatant_id] = {
		"sprite": sprite,
		"current_anim": "Idle_RIGHT",
		"frame_index": 0,
		"timer": 0.0,
		"is_playing": false,
		"hold_until_clear": false  # For animations that hold until manually cleared
	}

	# Play idle animation by default
	play_animation(combatant_id, "Idle", "RIGHT")

	return sprite

func play_animation(combatant_id: String, anim_name: String, direction: String = "RIGHT", hold: bool = false):
	"""Play an animation for a specific combatant

	Args:
		combatant_id: ID of the combatant ("douglas", "kai", etc.)
		anim_name: Animation name (e.g., "Walk", "Sword Strike")
		direction: Direction to face (UP, DOWN, LEFT, RIGHT)
		hold: If true, animation will hold on last frame until cleared
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

	# Apply first frame immediately
	_apply_frame(combatant_id, 0)

	print("[BattleSpriteAnimator] Playing %s for %s (hold: %s)" % [anim_key, combatant_id, hold])

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
		instance["frame_index"] = (frame_index + 1) % anim_data.size()
		_apply_frame(combatant_id, instance["frame_index"])

func _apply_frame(combatant_id: String, frame_index: int):
	"""Apply a specific frame to a sprite"""
	if not sprite_instances.has(combatant_id):
		return

	var instance = sprite_instances[combatant_id]
	var sprite = instance["sprite"]
	var anim_key = instance["current_anim"]

	if not animations.has(anim_key):
		return

	var anim_data = animations[anim_key]
	if frame_index >= anim_data.size():
		return

	var frame_data = anim_data[frame_index]
	sprite.frame = frame_data.cell
	sprite.flip_h = frame_data.flip_h

func get_sprite(combatant_id: String) -> Sprite2D:
	"""Get the sprite node for a combatant"""
	if not sprite_instances.has(combatant_id):
		return null
	return sprite_instances[combatant_id]["sprite"]

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
