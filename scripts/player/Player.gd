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

# Constants
const GS_PATH = "/root/aGameState"
const CHAR_BASE_PATH = "res://assets/graphics/characters/"
const CHAR_VARIANTS = ["char_a_p1"]

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
const ANIM_FRAME_TIME: float = 0.135  # 135ms per frame for walk/run
const WALK_FRAMES: int = 6  # 6 frames per walk cycle
const RUN_FRAMES: int = 6  # 6 frames per run cycle (custom sequence)
const PUSH_FRAMES: int = 2  # 2 frames per push animation
const PULL_FRAMES: int = 2  # 2 frames per pull animation

# Jump animation constants
const JUMP_AIRBORNE_FRAMES: int = 2  # 2 frames while in air (frames 2-3)
const JUMP_LANDING_HOLD_FRAMES: int = 2  # Hold landing frame for 2 frames
const JUMP_ARC_DISTANCE: float = 80.0  # Distance to travel during jump
const JUMP_ARC_DURATION: float = 0.27  # Duration of airborne phase (2 frames * 0.135)
const JUMP_ARC_HEIGHT: float = 40.0  # Height of vertical arc for East/West jumps

# Run animation uses custom frame sequence: columns 0,1,6,3,4,7
# This replaces the 3rd walk frame with 7th (first run frame)
# and 6th walk frame with 8th (second run frame)
const RUN_FRAME_SEQUENCE: Array[int] = [0, 1, 6, 3, 4, 7]

# Frame layout (0-indexed, rows 0-3 for actions, rows 4-7 for walk/run):
# Idle: column 0 (frames 0, 8, 16, 24)
# Push: columns 1-2 (frames 1-2, 9-10, 17-18, 25-26)
# Pull: columns 3-4 (frames 3-4, 11-12, 19-20, 27-28)
# Jump: columns 5-7 (frames 5-7, 13-15, 21-23, 29-31)
# Walk: row 4-7, columns 0-5 (frames 32-37, 40-45, 48-53, 56-61)
# Run: row 4-7, custom sequence using columns 0,1,6,3,4,7

# State
var _current_state: MovementState = MovementState.IDLE
var _current_direction: int = 0  # 0=South, 1=North, 2=East, 3=West
var _anim_frame_index: int = 0
var _anim_frame_timer: float = 0.0

# Jump state
var _jump_phase: JumpPhase = JumpPhase.NONE
var _jump_arc_timer: float = 0.0
var _jump_landing_hold_count: int = 0
var _jump_start_pos: Vector2 = Vector2.ZERO
var _jump_target_pos: Vector2 = Vector2.ZERO

# Nodes
@onready var character_layers: Node2D = $CharacterLayers
var _gs: Node = null

func _ready() -> void:
	print("[Player] Initializing player character...")
	_gs = get_node_or_null(GS_PATH)
	_load_character_appearance()

func _load_character_appearance() -> void:
	"""Load character appearance from GameState"""
	print("[Player] Loading character appearance...")

	if not character_layers:
		print("[Player] ERROR: character_layers is null!")
		return

	# Get character variants from GameState
	var variants: Dictionary = {}
	if _gs and _gs.has_meta("hero_identity"):
		var id_v: Variant = _gs.get_meta("hero_identity")
		if typeof(id_v) == TYPE_DICTIONARY:
			var id: Dictionary = id_v
			print("[Player] hero_identity found: ", id.keys())
			if id.has("character_variants"):
				var cv: Variant = id.get("character_variants")
				if typeof(cv) == TYPE_DICTIONARY:
					variants = cv
					print("[Player] Loaded variants from GameState: ", variants)
			else:
				print("[Player] No character_variants in hero_identity")
		else:
			print("[Player] hero_identity is not a dictionary")
	else:
		print("[Player] No hero_identity meta found in GameState")

	# If no variants saved, try to load from CharacterData autoload
	if variants.is_empty():
		print("[Player] Trying CharacterData autoload...")
		var char_data = get_node_or_null("/root/aCharacterData")
		if char_data:
			print("[Player] CharacterData found")
			if char_data.has_method("get"):
				var sv: Variant = char_data.get("selected_variants")
				print("[Player] selected_variants type: ", typeof(sv))
				if typeof(sv) == TYPE_DICTIONARY:
					variants = sv
					print("[Player] Loaded variants from CharacterData: ", variants)
			elif char_data.get("selected_variants"):
				var sv2 = char_data.get("selected_variants")
				if typeof(sv2) == TYPE_DICTIONARY:
					variants = sv2
					print("[Player] Loaded variants from CharacterData (property): ", variants)
		else:
			print("[Player] CharacterData autoload not found")

	if variants.is_empty():
		print("[Player] WARNING: No character variants found!")
		return

	# Update each layer sprite
	for layer_key in LAYERS:
		var layer = LAYERS[layer_key]
		var sprite = character_layers.get_node(layer.node_name)

		if layer_key in variants and variants[layer_key] != "":
			var variant_code = variants[layer_key]
			print("[Player] Loading ", layer_key, " with variant: ", variant_code)
			var texture_path = _find_character_file(layer_key, variant_code)
			print("[Player]   -> Path: ", texture_path)
			if texture_path != "" and FileAccess.file_exists(texture_path):
				var texture = load(texture_path)
				sprite.texture = texture
				sprite.visible = true
				# Set to idle pose: rows 0-3, column 0
				# Frame = direction * 8 (South=0, North=8, East=16, West=24)
				sprite.frame = _current_direction * 8
				print("[Player]   -> Loaded successfully, frame set to ", sprite.frame)
			else:
				print("[Player]   -> ERROR: File not found!")
				sprite.texture = null
				sprite.visible = false
		else:
			sprite.texture = null
			sprite.visible = false

func _find_character_file(layer_key: String, variant_code: String) -> String:
	"""Find the character file for a given layer and variant code"""
	if not LAYERS.has(layer_key):
		print("[Player]     Layer key not found: ", layer_key)
		return ""

	var layer = LAYERS[layer_key]
	for variant in CHAR_VARIANTS:
		var base_path = CHAR_BASE_PATH + variant + "/"
		var layer_path = base_path + (layer.path + "/" if layer.path != "" else "")
		var filename = "%s_%s_%s.png" % [variant, layer.code, variant_code]
		var full_path = layer_path + filename

		print("[Player]     Trying: ", full_path)
		if FileAccess.file_exists(full_path):
			print("[Player]     FOUND!")
			return full_path

	print("[Player]     Not found in any variant")
	return ""

func _physics_process(delta: float) -> void:
	_handle_jump(delta)
	if _jump_phase == JumpPhase.NONE:
		_handle_movement(delta)
	_update_animation(delta)

func _handle_jump(delta: float) -> void:
	"""Handle jump state machine and movement"""
	match _jump_phase:
		JumpPhase.NONE:
			# Check for jump input (spacebar pressed)
			if Input.is_key_pressed(KEY_SPACE):
				_start_jump()

		JumpPhase.CHARGING:
			# Hold crouch frame until spacebar is released
			if not Input.is_key_pressed(KEY_SPACE):
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
			if _anim_frame_timer >= ANIM_FRAME_TIME:
				_anim_frame_timer -= ANIM_FRAME_TIME
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
	var input_vector := Vector2.ZERO

	# Get directional input (WASD and arrow keys)
	if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
		input_vector.x += 1
	if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
		input_vector.x -= 1
	if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
		input_vector.y += 1
	if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
		input_vector.y -= 1

	# Normalize diagonal movement
	if input_vector.length() > 0:
		input_vector = input_vector.normalized()

	# Determine movement state based on modifier keys first
	var speed_mult: float = 1.0
	var can_move: bool = true
	var is_pulling: bool = Input.is_key_pressed(KEY_COMMA)

	if is_pulling:
		# Pull - half speed
		_current_state = MovementState.PULL
		speed_mult = PUSH_PULL_SPEED_MULT
	elif Input.is_key_pressed(KEY_PERIOD):
		# Push - half speed
		_current_state = MovementState.PUSH
		speed_mult = PUSH_PULL_SPEED_MULT
	elif Input.is_key_pressed(KEY_SHIFT):
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
	"""Update sprite animation frames based on current state"""
	if not character_layers:
		return

	var frame: int = 0

	match _current_state:
		MovementState.IDLE:
			# Idle: column 0 (frames 0, 8, 16, 24)
			frame = _current_direction * 8
			_anim_frame_index = 0
			_anim_frame_timer = 0.0

		MovementState.WALK:
			# Walk: rows 4-7, columns 0-5
			# South: 32-37, North: 40-45, East: 48-53, West: 56-61
			_anim_frame_timer += delta
			if _anim_frame_timer >= ANIM_FRAME_TIME:
				_anim_frame_timer -= ANIM_FRAME_TIME
				_anim_frame_index = (_anim_frame_index + 1) % WALK_FRAMES
			frame = (4 + _current_direction) * 8 + _anim_frame_index

		MovementState.RUN:
			# Run: custom sequence using columns 0,1,6,3,4,7
			# South: 32,33,38,35,36,39 North: 40,41,46,43,44,47
			# East: 48,49,54,51,52,55 West: 56,57,62,59,60,63
			_anim_frame_timer += delta
			if _anim_frame_timer >= ANIM_FRAME_TIME:
				_anim_frame_timer -= ANIM_FRAME_TIME
				_anim_frame_index = (_anim_frame_index + 1) % RUN_FRAMES
			var run_col: int = RUN_FRAME_SEQUENCE[_anim_frame_index]
			frame = (4 + _current_direction) * 8 + run_col

		MovementState.JUMP:
			# Jump animation varies by phase
			match _jump_phase:
				JumpPhase.CHARGING:
					# Hold first frame (crouch/windup): column 5
					frame = _current_direction * 8 + 5

				JumpPhase.AIRBORNE:
					# Cycle through airborne frames (columns 6-7)
					_anim_frame_timer += delta
					if _anim_frame_timer >= ANIM_FRAME_TIME:
						_anim_frame_timer -= ANIM_FRAME_TIME
						_anim_frame_index = (_anim_frame_index + 1) % JUMP_AIRBORNE_FRAMES
					frame = _current_direction * 8 + 6 + _anim_frame_index

				JumpPhase.LANDING:
					# Hold first frame (crouch): column 5
					frame = _current_direction * 8 + 5

				_:
					# Fallback
					frame = _current_direction * 8 + 5

		MovementState.PUSH:
			# Push: columns 1-2 (frames 1-2, 9-10, 17-18, 25-26)
			_anim_frame_timer += delta
			if _anim_frame_timer >= ANIM_FRAME_TIME:
				_anim_frame_timer -= ANIM_FRAME_TIME
				_anim_frame_index = (_anim_frame_index + 1) % PUSH_FRAMES
			frame = _current_direction * 8 + 1 + _anim_frame_index

		MovementState.PULL:
			# Pull: columns 3-4 (frames 3-4, 11-12, 19-20, 27-28)
			_anim_frame_timer += delta
			if _anim_frame_timer >= ANIM_FRAME_TIME:
				_anim_frame_timer -= ANIM_FRAME_TIME
				_anim_frame_index = (_anim_frame_index + 1) % PULL_FRAMES
			frame = _current_direction * 8 + 3 + _anim_frame_index

	# Update all visible sprites
	for layer_key in LAYERS:
		var layer = LAYERS[layer_key]
		var sprite: Sprite2D = character_layers.get_node(layer.node_name)
		if sprite and sprite.visible and sprite.texture:
			sprite.frame = frame
