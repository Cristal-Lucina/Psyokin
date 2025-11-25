## ═══════════════════════════════════════════════════════════════════════════
## Player - Playable Character Controller
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Controls the player character in the game world with JRPG-style movement.
##   Loads character appearance from GameState and animates based on direction.
##
## RESPONSIBILITIES:
##   • Load character sprites from GameState character_variants
##   • Handle WASD and arrow key input for movement
##   • Animate character based on movement direction
##   • Cycle walk animation frames (6 frames at 135ms per frame)
##   • Camera follows player smoothly
##
## SPRITE SYSTEM:
##   • 8 layers: base, outfit, cloak, face, hair, hat, tool_a, tool_b
##   • Sprite sheets: 512x512, 8x8 grid (64x64 per frame)
##   • Sprite layout (1-indexed sprite numbers):
##     Row 1 (1-8):   Idle S(1), Push S(2-3), Pull S(4-5), Jump S(6-8)
##     Row 2 (9-16):  Idle N(9), Push N(10-11), Pull N(12-13), Jump N(14-16)
##     Row 3 (17-24): Idle E(17), Push E(18-19), Pull E(20-21), Jump E(22-24)
##     Row 4 (25-32): Idle W(25), Push W(26-27), Pull W(28-29), Jump W(30-32)
##     Row 5 (33-40): Walk S(33-38), Run components S(39-40)
##     Row 6 (41-48): Walk N(41-46), Run components N(47-48)
##     Row 7 (49-56): Walk E(49-54), Run components E(55-56)
##     Row 8 (57-64): Walk W(57-62), Run components W(63-64)
##   • Direction mapping: 0=South, 1=North, 2=East, 3=West
##   • Run uses custom sequence: walk frames 1,2,7,4,5,8 (replaces 3rd and 6th with run frames)
##
## ═══════════════════════════════════════════════════════════════════════════

extends CharacterBody2D
class_name Player

# Import animation loader
const AnimationDataLoaderScript = preload("res://scripts/player/AnimationDataLoader.gd")

# Constants
const GS_PATH = "/root/aGameState"
const SPRITE_PATH = "res://assets/graphics/characters/New Character System/SpriteSystem/base_sheets/"
const PALETTE_PATH = "res://assets/graphics/characters/New Character System/SpriteSystem/_supporting files/palettes/"

# Mana Seed layer configuration (matching character creator)
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

# Movement settings
@export var move_speed: float = 120.0

# Movement states
enum MovementState {
	IDLE,
	WALK,
	RUN,
	JUMP,
	PUSH,
	PULL
}

# Jump phases
enum JumpPhase {
	NONE,        # Not jumping
	CHARGING,    # Holding first frame (crouch)
	AIRBORNE,    # In air (frames 2-3)
	LANDING      # Landing hold (first frame for 2 frames)
}

# Speed multipliers
const RUN_SPEED_MULT: float = 1.75
const PUSH_PULL_SPEED_MULT: float = 0.5

# Animation constants
const WALK_FRAME_TIME: float = 0.135  # 135ms per frame for walk
const RUN_FRAME_TIME: float = 0.100  # 100ms per frame for run (faster)
const PUSH_PULL_FRAME_TIME: float = 0.200  # 200ms per frame for push/pull (slower)
const WALK_FRAMES: int = 6  # 6 frames per walk cycle
const RUN_FRAMES: int = 6  # 6 frames per run cycle (custom sequence)
const PUSH_FRAMES: int = 2  # 2 frames per push animation
const PULL_FRAMES: int = 2  # 2 frames per pull animation

# Jump animation constants
const JUMP_AIRBORNE_FRAMES: int = 2  # 2 frames while in air (frames 2-3)
const JUMP_LANDING_HOLD_FRAMES: int = 2  # Hold landing frame for 2 frames
const JUMP_ARC_DISTANCE: float = 80.0  # Distance to travel during jump
const JUMP_ARC_DURATION: float = 0.27  # Duration of airborne phase (2 frames)
const JUMP_ARC_HEIGHT: float = 40.0  # Height of vertical arc for East/West jumps

# Run animation uses custom frame sequence: columns 0,1,6,3,4,7
# This replaces the 3rd walk frame with 7th (first run frame)
# and 6th walk frame with 8th (second run frame)
const RUN_FRAME_SEQUENCE: Array[int] = [0, 1, 6, 3, 4, 7]

# Frame layout (0-indexed, 16x16 grid, matching sprite_animations_data.csv):
# Idle: column 0 (frames 0, 16, 32, 32+flip for South/North/East/West)
# Push: columns 8-9 (frames 8-9, 24-25, 40-41, 40-41+flip)
# Pull: columns 10-11 (frames 10-11, 26-27, 42-43, 42-43+flip)
# Jump: columns 1-2 (frames 1-2, 17-18, 33-34, 33-34+flip)
# Walk: (frames 48-53, 52-57, 64-69, 64-69+flip for South/North/East/West)
# Run: custom sequence using walk frames + special run frames
# Note: West/LEFT direction uses same frames as East/RIGHT but with flip_h = true

# State
var _current_state: MovementState = MovementState.IDLE
var _current_direction: int = 0  # 0=South, 1=North, 2=East, 3=West
var _anim_frame_index: int = 0
var _anim_frame_timer: float = 0.0
var _current_sequence: AnimationDataLoaderScript.AnimationSequence = null
var _force_flip: bool = false  # Force flip for current frame (from CSV)

# Jump state
var _jump_phase: JumpPhase = JumpPhase.NONE
var _jump_arc_timer: float = 0.0
var _jump_landing_hold_count: int = 0
var _jump_start_pos: Vector2 = Vector2.ZERO
var _jump_target_pos: Vector2 = Vector2.ZERO

# Nodes
@onready var character_layers: Node2D = $CharacterLayers
var _gs: Node = null

# Random encounters
var _encounter_steps: float = 0.0
var _steps_per_tile: float = 32.0  # Tile size
const ENCOUNTER_MIN_STEPS: int = 5  # Minimum tiles before encounter can trigger
const ENCOUNTER_MAX_STEPS: int = 15  # Maximum tiles before guaranteed encounter
const ENCOUNTER_CHANCE: float = 0.15  # 15% chance per tile after minimum
var _can_encounter: bool = true  # Can be disabled for safe zones

func _ready() -> void:
	print("[Player] Initializing player character...")
	add_to_group("player")  # Add to group for easy finding
	_gs = get_node_or_null(GS_PATH)
	_load_palettes()
	_load_character_appearance()
	# Initialize animation data loader
	AnimationDataLoaderScript.get_instance()

func _load_palettes() -> void:
	"""Load palette images for color mapping"""
	print("[Player] Loading palette images...")
	palette_images["3color"] = load(PALETTE_PATH + "mana seed 3-color ramps.png").get_image()
	palette_images["4color"] = load(PALETTE_PATH + "mana seed 4-color ramps.png").get_image()
	palette_images["hair"] = load(PALETTE_PATH + "mana seed hair ramps.png").get_image()
	palette_images["skin"] = load(PALETTE_PATH + "mana seed skin ramps.png").get_image()
	print("[Player] Palette images loaded")

func _load_character_appearance() -> void:
	"""Load character appearance from GameState using Mana Seed system"""
	print("[Player] Loading Mana Seed character appearance...")

	if not character_layers:
		print("[Player] ERROR: character_layers is null!")
		return

	# Get character data from GameState hero_identity meta
	var character_selections: Dictionary = {}
	var character_colors: Dictionary = {}

	if _gs and _gs.has_meta("hero_identity"):
		var hero_id = _gs.get_meta("hero_identity")
		if typeof(hero_id) == TYPE_DICTIONARY:
			print("[Player] hero_identity found: ", hero_id.keys())
			if hero_id.has("character_selections"):
				character_selections = hero_id.get("character_selections", {})
			if hero_id.has("character_colors"):
				character_colors = hero_id.get("character_colors", {})
			print("[Player] Loaded ", character_selections.size(), " parts and ", character_colors.size(), " colors")
	else:
		print("[Player] WARNING: No hero_identity meta found in GameState!")
		# Create default naked character with just body
		character_colors["01body"] = 0

	# Load sprites for each layer
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
			part = character_selections.get(layer_code, null)
		else:
			# Body layer - load default body sprite
			if layer_code == "01body":
				# Find first body sprite
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
							# Parse palette code from filename
							var parts_arr = file_name.get_basename().split("_")
							if parts_arr.size() >= 4:
								part["palette_code"] = parts_arr[3]
							break
						file_name = dir.get_next()
					dir.list_dir_end()

		# Apply to all sprite nodes for this layer
		for sprite_code in sprite_codes:
			var sprite = character_layers.get_node_or_null(sprite_code)
			if not sprite:
				continue

			# If no part selected, clear the sprite
			if part == null:
				sprite.texture = null
				continue

			# For combined layers (like footwear), only apply if the part belongs to this sprite layer
			if "sprite_layers" in layer:
				if part.get("sprite_code", "") != sprite_code:
					sprite.texture = null
					continue

			# Load texture
			var texture_path = part.get("path", "")
			if texture_path == "" or not FileAccess.file_exists(texture_path):
				print("[Player] ERROR: Texture not found: ", texture_path)
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

		# Auto-match layer (e.g., apply matching underwear for neckwear)
		if "auto_match_layer" in layer and part != null:
			var auto_layer_code = layer.auto_match_layer
			var auto_sprite = character_layers.get_node_or_null(auto_layer_code)

			if auto_sprite:
				# Find matching part by base_name in the auto-match layer
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
					# Load and apply matching texture with same color
					var auto_texture = load(matching_part.path)
					if layer_code in character_colors:
						var color_index = character_colors[layer_code]
						var recolored_texture = _apply_color_mapping(auto_texture, matching_part, layer.ramp_type, color_index)
						auto_sprite.texture = recolored_texture
					else:
						auto_sprite.texture = auto_texture
				else:
					auto_sprite.texture = null
		# Clear auto-match layer if main layer has no selection
		elif "auto_match_layer" in layer and part == null:
			var auto_layer_code = layer.auto_match_layer
			var auto_sprite = character_layers.get_node_or_null(auto_layer_code)
			if auto_sprite:
				auto_sprite.texture = null

	print("[Player] Character appearance loaded")

func _physics_process(delta: float) -> void:
	_handle_jump(delta)
	if _jump_phase == JumpPhase.NONE:
		_handle_movement(delta)
	_update_animation(delta)
	_check_random_encounter(delta)

func _handle_jump(delta: float) -> void:
	"""Handle jump state machine and movement"""
	match _jump_phase:
		JumpPhase.NONE:
			# Check for jump input (spacebar or A button pressed)
			if aInputManager.is_action_pressed(aInputManager.ACTION_JUMP):
				_start_jump()

		JumpPhase.CHARGING:
			# Hold crouch frame until jump button is released
			if not aInputManager.is_action_pressed(aInputManager.ACTION_JUMP):
				_release_jump()
			# Stay in place during charge
			velocity = Vector2.ZERO
			move_and_slide()

		JumpPhase.AIRBORNE:
			# Arc movement from start to target
			_jump_arc_timer += delta
			var progress: float = _jump_arc_timer / JUMP_ARC_DURATION

			if progress >= 1.0:
				# Finished arc, land
				position = _jump_target_pos
				_jump_phase = JumpPhase.LANDING
				_jump_landing_hold_count = 0
				_anim_frame_index = 0
				_anim_frame_timer = 0.0
				velocity = Vector2.ZERO
			else:
				# Interpolate position along arc
				var base_pos: Vector2 = _jump_start_pos.lerp(_jump_target_pos, progress)

				# Add vertical arc for East/West jumps (parabolic curve)
				if _current_direction == 2 or _current_direction == 3:  # East or West
					# Parabolic arc: peaks at progress = 0.5
					# Formula: -4 * height * (progress - 0.5)^2 + height
					var arc_offset: float = -4.0 * JUMP_ARC_HEIGHT * pow(progress - 0.5, 2) + JUMP_ARC_HEIGHT
					base_pos.y -= arc_offset

				position = base_pos
				velocity = Vector2.ZERO

			move_and_slide()

		JumpPhase.LANDING:
			# Hold landing frame
			_anim_frame_timer += delta
			if _anim_frame_timer >= WALK_FRAME_TIME:
				_anim_frame_timer -= WALK_FRAME_TIME
				_jump_landing_hold_count += 1

				if _jump_landing_hold_count >= JUMP_LANDING_HOLD_FRAMES:
					# Finished landing, return to idle
					_jump_phase = JumpPhase.NONE
					_current_state = MovementState.IDLE

			velocity = Vector2.ZERO
			move_and_slide()

func _start_jump() -> void:
	"""Initialize jump sequence"""
	_jump_phase = JumpPhase.CHARGING
	_current_state = MovementState.JUMP
	_anim_frame_index = 0
	_anim_frame_timer = 0.0

func _release_jump() -> void:
	"""Release jump and start arc movement"""
	_jump_phase = JumpPhase.AIRBORNE
	_jump_arc_timer = 0.0
	_anim_frame_index = 0
	_anim_frame_timer = 0.0

	# Calculate jump arc based on facing direction
	_jump_start_pos = position
	var jump_vector: Vector2 = Vector2.ZERO

	match _current_direction:
		0:  # South
			jump_vector = Vector2(0, JUMP_ARC_DISTANCE)
		1:  # North
			jump_vector = Vector2(0, -JUMP_ARC_DISTANCE)
		2:  # East
			jump_vector = Vector2(JUMP_ARC_DISTANCE, 0)
		3:  # West
			jump_vector = Vector2(-JUMP_ARC_DISTANCE, 0)

	_jump_target_pos = _jump_start_pos + jump_vector

func _handle_movement(_delta: float) -> void:
	"""Handle player input and movement"""
	# Use InputManager for unified keyboard/controller support
	var input_vector := aInputManager.get_movement_vector()

	# Determine movement state based on modifier keys first
	var speed_mult: float = 1.0
	var can_move: bool = true
	var is_pulling: bool = false  # Disabled automatic push/pull to prevent interference with interactions

	# Note: Push/pull animations disabled to prevent conflict with ACTION_ACCEPT (A button)
	# They can be re-enabled with context-sensitive logic when near pushable/pullable objects

	if aInputManager.is_action_pressed(aInputManager.ACTION_RUN):
		# Run - increased speed
		if input_vector.length() > 0:
			_current_state = MovementState.RUN
			speed_mult = RUN_SPEED_MULT
		else:
			_current_state = MovementState.IDLE
	else:
		# Walk or Idle
		if input_vector.length() > 0:
			_current_state = MovementState.WALK
		else:
			_current_state = MovementState.IDLE

	# Update direction based on input
	if input_vector.length() > 0:
		# Prioritize horizontal movement for 4-directional sprites
		var movement_direction: int = -1

		if abs(input_vector.x) > abs(input_vector.y):
			# Moving horizontally
			if input_vector.x > 0:
				movement_direction = 2  # East
			else:
				movement_direction = 3  # West
		else:
			# Moving vertically
			if input_vector.y > 0:
				movement_direction = 0  # South
			else:
				movement_direction = 1  # North

		# For pulling, face the opposite direction (as if pulling something toward you)
		if is_pulling:
			match movement_direction:
				0:  # Moving South, face North
					_current_direction = 1
				1:  # Moving North, face South
					_current_direction = 0
				2:  # Moving East, face West
					_current_direction = 3
				3:  # Moving West, face East
					_current_direction = 2
		else:
			_current_direction = movement_direction

	# Apply movement
	if can_move:
		velocity = input_vector * move_speed * speed_mult
	else:
		velocity = Vector2.ZERO

	move_and_slide()

func _update_animation(delta: float) -> void:
	"""Update sprite animation frames based on current state - uses CSV data"""
	if not character_layers:
		return

	# Get animation name based on state
	var anim_name = ""
	var direction_name = _get_direction_name(_current_direction)

	match _current_state:
		MovementState.IDLE:
			anim_name = "Idle"
			_anim_frame_index = 0
			_anim_frame_timer = 0.0

		MovementState.WALK:
			anim_name = "Walk"

		MovementState.RUN:
			anim_name = "Run"

		MovementState.JUMP:
			match _jump_phase:
				JumpPhase.CHARGING, JumpPhase.LANDING:
					anim_name = "Jump"
					_anim_frame_index = 0
				JumpPhase.AIRBORNE:
					anim_name = "Jump"

		MovementState.PUSH:
			anim_name = "Push"

		MovementState.PULL:
			anim_name = "Pull"

	# Get animation sequence from CSV
	_current_sequence = AnimationDataLoaderScript.get_animation(anim_name, direction_name)

	if _current_sequence.frames.is_empty():
		# Fallback to idle frame if animation not found
		var idle_seq = AnimationDataLoaderScript.get_animation("Idle", direction_name)
		if not idle_seq.frames.is_empty():
			_apply_frame(idle_seq.frames[0])
		return

	# Advance animation timer for non-idle states
	if _current_state != MovementState.IDLE:
		var current_frame_data = _current_sequence.get_frame_at_index(_anim_frame_index)
		var frame_time = current_frame_data.time_ms / 1000.0  # Convert ms to seconds

		_anim_frame_timer += delta
		if _anim_frame_timer >= frame_time and not current_frame_data.hold:
			_anim_frame_timer -= frame_time
			_anim_frame_index = (_anim_frame_index + 1) % _current_sequence.frames.size()

	# Apply current frame
	var frame_data = _current_sequence.get_frame_at_index(_anim_frame_index)
	_apply_frame(frame_data)

func _apply_frame(frame_data: AnimationDataLoaderScript.AnimationFrame) -> void:
	"""Apply a frame to all sprite layers"""
	if not character_layers:
		return

	var frame_num = frame_data.frame
	var flip_from_csv = frame_data.flip_h

	# Update all visible sprites
	for layer in LAYERS:
		# Get sprite codes (single or multiple for combined layers)
		var sprite_codes = []
		if "sprite_layers" in layer:
			sprite_codes = layer.sprite_layers
		else:
			sprite_codes = [layer.code]

		# Update each sprite node for this layer
		for sprite_code in sprite_codes:
			var sprite: Sprite2D = character_layers.get_node_or_null(sprite_code)
			if sprite and sprite.visible and sprite.texture:
				sprite.frame = frame_num
				# West/LEFT direction uses flip, OR if CSV specifies flip
				sprite.flip_h = (_current_direction == 3) or flip_from_csv

func _get_direction_name(direction: int) -> String:
	"""Convert direction index to name"""
	match direction:
		0: return "DOWN"
		1: return "UP"
		2: return "RIGHT"
		3: return "LEFT"
		_: return "DOWN"

## ═══════════════════════════════════════════════════════════════
## RANDOM ENCOUNTERS
## ═══════════════════════════════════════════════════════════════

func _check_random_encounter(delta: float) -> void:
	"""Check if a random encounter should trigger based on steps taken"""
	if not _can_encounter:
		return

	# Only count steps when walking or running (not jumping or idle)
	if _current_state != MovementState.WALK and _current_state != MovementState.RUN:
		return

	# Accumulate distance traveled
	var distance = velocity.length() * delta
	_encounter_steps += distance

	# Check if we've moved a full tile
	if _encounter_steps >= _steps_per_tile:
		_encounter_steps -= _steps_per_tile
		_check_encounter_roll()

func _check_encounter_roll() -> void:
	"""Roll for encounter chance"""
	# Get step counter from metadata or initialize it
	var steps_taken = 0
	if has_meta("encounter_step_counter"):
		steps_taken = get_meta("encounter_step_counter")

	steps_taken += 1
	set_meta("encounter_step_counter", steps_taken)

	# Guaranteed encounter after max steps
	if steps_taken >= ENCOUNTER_MAX_STEPS:
		_trigger_encounter()
		return

	# Random chance after minimum steps
	if steps_taken >= ENCOUNTER_MIN_STEPS:
		if randf() < ENCOUNTER_CHANCE:
			_trigger_encounter()

func _trigger_encounter() -> void:
	"""Trigger a random encounter"""
	print("[Player] Random encounter triggered!")

	# Reset step counter
	set_meta("encounter_step_counter", 0)

	# Disable movement and encounters during battle
	_can_encounter = false

	# Get random enemies (1-2 enemies for now)
	var enemy_count = randi() % 2 + 1  # 1 or 2 enemies
	var enemies: Array = []
	var possible_enemies = ["slime", "goblin"]

	for i in range(enemy_count):
		enemies.append(possible_enemies[randi() % possible_enemies.size()])

	# Get battle manager and start encounter
	var battle_mgr = get_node_or_null("/root/aBattleManager")
	if battle_mgr:
		# Store current scene path to return to
		var current_scene = get_tree().current_scene.scene_file_path
		battle_mgr.start_random_encounter(enemies, current_scene)
	else:
		push_error("[Player] BattleManager not found!")
		_can_encounter = true  # Re-enable if battle failed to start

func enable_encounters() -> void:
	"""Enable random encounters (call after returning from battle)"""
	_can_encounter = true

func disable_encounters() -> void:
	"""Disable random encounters (for safe zones, cutscenes, etc)"""
	_can_encounter = false

## Save current position and direction to GameState
func save_position() -> void:
	"""Save player position and facing direction to GameState"""
	var gs = get_node_or_null(GS_PATH)
	if gs:
		gs.player_position = position
		gs.player_direction = _current_direction
		print("[Player] Saved position: %s, direction: %d" % [position, _current_direction])

## Restore position and direction from GameState
func restore_position() -> void:
	"""Restore player position and facing direction from GameState"""
	var gs = get_node_or_null(GS_PATH)
	if gs:
		position = gs.player_position
		_current_direction = gs.player_direction

		# Update sprite frames to idle frame for the restored direction
		var idle_frame = _current_direction * 8
		for layer in LAYERS:
			var sprite_codes = []
			if "sprite_layers" in layer:
				sprite_codes = layer.sprite_layers
			else:
				sprite_codes = [layer.code]

			for sprite_code in sprite_codes:
				var sprite: Sprite2D = character_layers.get_node_or_null(sprite_code)
				if sprite and sprite.visible and sprite.texture:
					sprite.frame = idle_frame

			# Also update auto-match layer if it exists
			if "auto_match_layer" in layer:
				var auto_sprite = character_layers.get_node_or_null(layer.auto_match_layer)
				if auto_sprite and auto_sprite.visible and auto_sprite.texture:
					auto_sprite.frame = idle_frame

		print("[Player] Restored position: %s, direction: %d" % [position, _current_direction])

# ========== COLOR MAPPING FUNCTIONS ==========

func _apply_color_mapping(original_texture: Texture2D, part: Dictionary, ramp_type: String, color_index: int) -> ImageTexture:
	"""Apply color mapping to a texture"""
	var original_image = original_texture.get_image()
	var recolored_image = Image.create(original_image.get_width(), original_image.get_height(), false, original_image.get_format())
	recolored_image.copy_from(original_image)

	var palette_code = part.get("palette_code", "00")
	var base_colors = _get_base_colors_for_palette_code(palette_code, ramp_type)
	var target_colors = _get_target_colors_for_palette_code(palette_code, ramp_type, color_index)

	if base_colors.size() == 0 or target_colors.size() == 0:
		return ImageTexture.create_from_image(recolored_image)

	# Pixel-by-pixel color replacement
	for y in range(recolored_image.get_height()):
		for x in range(recolored_image.get_width()):
			var pixel = recolored_image.get_pixel(x, y)
			if pixel.a < 0.01:
				continue

			# Check against each base color
			for i in range(min(base_colors.size(), target_colors.size())):
				if _colors_match(pixel, base_colors[i]):
					recolored_image.set_pixel(x, y, Color(target_colors[i].r, target_colors[i].g, target_colors[i].b, pixel.a))
					break

	return ImageTexture.create_from_image(recolored_image)

func _get_base_colors_for_palette_code(palette_code: String, ramp_type: String) -> Array:
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

func _get_target_colors_for_palette_code(palette_code: String, ramp_type: String, row_index: int) -> Array:
	"""Get target colors for a specific palette row"""
	match palette_code:
		"00a":
			return _extract_colors_from_palette("3color", row_index)
		"00b":
			return _extract_colors_from_palette("4color", row_index)
		"00c":
			var colors_3 = _extract_colors_from_palette("3color", row_index)
			if colors_3.size() >= 3:
				return colors_3 + colors_3
			return colors_3
		"00d":
			var colors_4 = _extract_colors_from_palette("4color", row_index)
			var colors_3 = _extract_colors_from_palette("3color", row_index)
			return colors_4 + colors_3
		"00f":
			var colors_4 = _extract_colors_from_palette("4color", row_index)
			var colors_hair = _extract_colors_from_palette("hair", row_index)
			return colors_4 + colors_hair
		"00":
			return _extract_colors_from_palette(ramp_type, row_index)
		_:
			return _extract_colors_from_palette(ramp_type, row_index)

func _extract_colors_from_palette(ramp_type: String, row_index: int) -> Array:
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

func _colors_match(c1: Color, c2: Color, tolerance: float = 0.01) -> bool:
	"""Check if two colors match within tolerance"""
	return abs(c1.r - c2.r) < tolerance and abs(c1.g - c2.g) < tolerance and abs(c1.b - c2.b) < tolerance
