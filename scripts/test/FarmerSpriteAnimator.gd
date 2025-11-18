extends Node2D

# Animation frame data structure
# Each frame has: [cell_number, timing_ms, flip_horizontal]
class AnimationFrame:
	var cell: int
	var timing: float  # in seconds
	var flip_h: bool

	func _init(c: int, t: float, f: bool = false):
		cell = c
		timing = t
		flip_h = f

# Animation definitions based on the farmer base animation guide
var animations = {
	"walk_down": [
		AnimationFrame.new(48, 0.138),
		AnimationFrame.new(49, 0.138),
		AnimationFrame.new(50, 0.138),
		AnimationFrame.new(51, 0.138),
		AnimationFrame.new(48, 0.138, true),
		AnimationFrame.new(49, 0.138, true),
	],
	"walk_up": [
		AnimationFrame.new(52, 0.138),
		AnimationFrame.new(53, 0.138),
		AnimationFrame.new(54, 0.138),
		AnimationFrame.new(55, 0.138),
		AnimationFrame.new(54, 0.138, true),
		AnimationFrame.new(53, 0.138, true),
	],
	"walk_right": [
		AnimationFrame.new(64, 0.138),
		AnimationFrame.new(65, 0.138),
		AnimationFrame.new(66, 0.138),
		AnimationFrame.new(67, 0.138),
		AnimationFrame.new(68, 0.138),
		AnimationFrame.new(69, 0.138),
	],
	"walk_left": [
		AnimationFrame.new(64, 0.138, true),
		AnimationFrame.new(65, 0.138, true),
		AnimationFrame.new(66, 0.138, true),
		AnimationFrame.new(67, 0.138, true),
		AnimationFrame.new(68, 0.138, true),
		AnimationFrame.new(69, 0.138, true),
	],
	"idle_down": [
		AnimationFrame.new(0, 1.0),
	],
	"idle_up": [
		AnimationFrame.new(16, 1.0),
	],
	"idle_right": [
		AnimationFrame.new(32, 1.0),
	],
	"idle_left": [
		AnimationFrame.new(32, 1.0, true),
	],
	"run_down": [
		AnimationFrame.new(56, 0.092),
		AnimationFrame.new(57, 0.092),
		AnimationFrame.new(58, 0.092),
		AnimationFrame.new(59, 0.092),
		AnimationFrame.new(56, 0.092, true),
		AnimationFrame.new(57, 0.092, true),
	],
	"run_up": [
		AnimationFrame.new(60, 0.092),
		AnimationFrame.new(61, 0.092),
		AnimationFrame.new(62, 0.092),
		AnimationFrame.new(63, 0.092),
		AnimationFrame.new(62, 0.092, true),
		AnimationFrame.new(61, 0.092, true),
	],
	"run_right": [
		AnimationFrame.new(72, 0.092),
		AnimationFrame.new(73, 0.092),
		AnimationFrame.new(74, 0.092),
		AnimationFrame.new(75, 0.092),
		AnimationFrame.new(76, 0.092),
		AnimationFrame.new(77, 0.092),
	],
	"run_left": [
		AnimationFrame.new(72, 0.092, true),
		AnimationFrame.new(73, 0.092, true),
		AnimationFrame.new(74, 0.092, true),
		AnimationFrame.new(75, 0.092, true),
		AnimationFrame.new(76, 0.092, true),
		AnimationFrame.new(77, 0.092, true),
	],
}

# Current animation state
var current_animation: String = "idle_down"
var current_frame_index: int = 0
var frame_timer: float = 0.0
var is_playing: bool = true

# References to sprite layers
@onready var body_layer = $FarmerSprite/BodyLayer
@onready var hair_layer = $FarmerSprite/HairLayer

# Movement for testing
var move_speed: float = 100.0
var velocity: Vector2 = Vector2.ZERO

func _ready():
	print("FarmerSpriteAnimator ready!")
	print("Use arrow keys to test walk animations")
	print("Hold Shift for run animations")
	play_animation("idle_down")

func _process(delta):
	handle_input()
	update_animation(delta)

	# Move the sprite for testing
	if velocity != Vector2.ZERO:
		$FarmerSprite.position += velocity * move_speed * delta

func handle_input():
	# Get input direction
	var input_dir = Vector2.ZERO
	var is_running = Input.is_key_pressed(KEY_SHIFT)

	if Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1
	if Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_DOWN):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_UP):
		input_dir.y -= 1

	velocity = input_dir.normalized()

	# Determine animation based on input
	if input_dir != Vector2.ZERO:
		var anim_prefix = "run" if is_running else "walk"

		# Prioritize horizontal movement for animation
		if abs(input_dir.x) > abs(input_dir.y):
			if input_dir.x > 0:
				play_animation(anim_prefix + "_right")
			else:
				play_animation(anim_prefix + "_left")
		else:
			if input_dir.y > 0:
				play_animation(anim_prefix + "_down")
			else:
				play_animation(anim_prefix + "_up")
	else:
		# Idle animation - keep current direction
		if current_animation.contains("right"):
			play_animation("idle_right")
		elif current_animation.contains("left"):
			play_animation("idle_left")
		elif current_animation.contains("up"):
			play_animation("idle_up")
		else:
			play_animation("idle_down")

func play_animation(anim_name: String):
	if current_animation == anim_name and is_playing:
		return  # Already playing this animation

	if not animations.has(anim_name):
		print("Animation not found: " + anim_name)
		return

	current_animation = anim_name
	current_frame_index = 0
	frame_timer = 0.0
	is_playing = true

	# Apply first frame immediately
	apply_frame(0)

func update_animation(delta):
	if not is_playing:
		return

	var anim_data = animations[current_animation]
	if anim_data.size() == 0:
		return

	# Update frame timer
	frame_timer += delta

	# Check if we need to advance to next frame
	var current_frame_data = anim_data[current_frame_index]
	if frame_timer >= current_frame_data.timing:
		frame_timer = 0.0
		current_frame_index = (current_frame_index + 1) % anim_data.size()
		apply_frame(current_frame_index)

func apply_frame(frame_index: int):
	var anim_data = animations[current_animation]
	if frame_index >= anim_data.size():
		return

	var frame_data = anim_data[frame_index]

	# Apply to all layers
	apply_to_layer(body_layer, frame_data)
	apply_to_layer(hair_layer, frame_data)

func apply_to_layer(layer: Sprite2D, frame_data: AnimationFrame):
	if layer == null:
		return

	layer.frame = frame_data.cell
	layer.flip_h = frame_data.flip_h

func _input(event):
	# Test specific animations with number keys
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				play_animation("walk_down")
				print("Testing: walk_down")
			KEY_2:
				play_animation("walk_up")
				print("Testing: walk_up")
			KEY_3:
				play_animation("walk_right")
				print("Testing: walk_right")
			KEY_4:
				play_animation("walk_left")
				print("Testing: walk_left")
			KEY_5:
				play_animation("run_down")
				print("Testing: run_down")
			KEY_6:
				play_animation("run_up")
				print("Testing: run_up")
			KEY_7:
				play_animation("run_right")
				print("Testing: run_right")
			KEY_8:
				play_animation("run_left")
				print("Testing: run_left")
