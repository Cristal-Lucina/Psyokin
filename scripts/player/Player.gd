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
##     Row 1 (1-8):   Idle S(1), Push S(2-3), Pull S(4-5), Crouch S(6), Jump S(7-8)
##     Row 2 (9-16):  Idle N(9), Push N(10-11), Pull N(12-13), Crouch N(14), Jump N(15-16)
##     Row 3 (17-24): Idle E(17), Push E(18-19), Pull E(20-21), Crouch E(22), Jump E(23-24)
##     Row 4 (25-32): Idle W(25), Push W(26-27), Pull W(28-29), Crouch W(30), Jump W(31-32)
##     Row 5 (33-40): Walk S(33-38), Run S(39-40)
##     Row 6 (41-48): Walk N(41-46), Run N(47-48)
##     Row 7 (49-56): Walk E(49-54), Run E(55-56)
##     Row 8 (57-64): Walk W(57-62), Run W(63-64)
##   • Direction mapping: 0=South, 1=North, 2=East, 3=West
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
	CROUCH,
	PUSH,
	PULL
}

# Speed multipliers
const RUN_SPEED_MULT: float = 1.75
const PUSH_PULL_SPEED_MULT: float = 0.5

# Animation constants
const ANIM_FRAME_TIME: float = 0.135  # 135ms per frame for walk/run
const WALK_FRAMES: int = 6  # 6 frames per walk cycle
const RUN_FRAMES: int = 2  # 2 frames per run cycle
const PUSH_FRAMES: int = 2  # 2 frames per push animation
const PULL_FRAMES: int = 2  # 2 frames per pull animation

# Frame layout (0-indexed, rows 0-3 for actions, rows 4-7 for walk/run):
# Idle: column 0 (frames 0, 8, 16, 24)
# Push: columns 1-2 (frames 1-2, 9-10, 17-18, 25-26)
# Pull: columns 3-4 (frames 3-4, 11-12, 19-20, 27-28)
# Crouch: column 5 (frames 5, 13, 21, 29)
# Jump: columns 6-7 (frames 6-7, 14-15, 22-23, 30-31)
# Walk: row 4-7, columns 0-5 (frames 32-37, 40-45, 48-53, 56-61)
# Run: row 4-7, columns 6-7 (frames 38-39, 46-47, 54-55, 62-63)

# State
var _current_state: MovementState = MovementState.IDLE
var _current_direction: int = 0  # 0=South, 1=North, 2=East, 3=West
var _anim_frame_index: int = 0
var _anim_frame_timer: float = 0.0

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
	_handle_movement(delta)
	_update_animation(delta)

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

	# Update direction based on input (even if not moving, for crouch)
	if input_vector.length() > 0:
		# Prioritize horizontal movement for 4-directional sprites
		if abs(input_vector.x) > abs(input_vector.y):
			# Moving horizontally
			if input_vector.x > 0:
				_current_direction = 2  # East
			else:
				_current_direction = 3  # West
		else:
			# Moving vertically
			if input_vector.y > 0:
				_current_direction = 0  # South
			else:
				_current_direction = 1  # North

	# Determine movement state based on modifier keys
	var speed_mult: float = 1.0
	var can_move: bool = true

	if Input.is_key_pressed(KEY_C):
		# Crouch - can't move, only change direction
		_current_state = MovementState.CROUCH
		can_move = false
	elif Input.is_key_pressed(KEY_COMMA):
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
			# Run: rows 4-7, columns 6-7
			# South: 38-39, North: 46-47, East: 54-55, West: 62-63
			_anim_frame_timer += delta
			if _anim_frame_timer >= ANIM_FRAME_TIME:
				_anim_frame_timer -= ANIM_FRAME_TIME
				_anim_frame_index = (_anim_frame_index + 1) % RUN_FRAMES
			frame = (4 + _current_direction) * 8 + 6 + _anim_frame_index

		MovementState.CROUCH:
			# Crouch: column 5 (frames 5, 13, 21, 29)
			frame = _current_direction * 8 + 5
			_anim_frame_index = 0
			_anim_frame_timer = 0.0

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
