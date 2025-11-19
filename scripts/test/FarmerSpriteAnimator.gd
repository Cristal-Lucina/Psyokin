extends Node2D

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
var animation_list = []  # List of animation names for dropdown

# Current animation state
var current_animation: String = "Idle_DOWN"
var current_frame_index: int = 0
var frame_timer: float = 0.0
var is_playing: bool = true
var manual_mode: bool = false  # Set to true when using UI controls

# Character sprite definitions
var characters = {
	"Layered (Body+Hair)": {
		"body": "res://assets/graphics/characters/New Character System/SpriteSystem/farmer_base_sheets/01body/fbas_01body_human_00.png",
		"hair": "res://assets/graphics/characters/New Character System/SpriteSystem/farmer_base_sheets/13hair/fbas_13hair_twintail_00.png",
		"layered": true
	},
	"Douglas": {
		"sprite": "res://assets/graphics/characters/New Character System/PartySpriteSheets/Douglas.png",
		"layered": false
	},
	"Kai": {
		"sprite": "res://assets/graphics/characters/New Character System/PartySpriteSheets/Kai.png",
		"layered": false
	},
	"Matcha": {
		"sprite": "res://assets/graphics/characters/New Character System/PartySpriteSheets/Matcha.png",
		"layered": false
	},
	"Risa": {
		"sprite": "res://assets/graphics/characters/New Character System/PartySpriteSheets/Risa.png",
		"layered": false
	},
	"Sev": {
		"sprite": "res://assets/graphics/characters/New Character System/PartySpriteSheets/Sev.png",
		"layered": false
	},
	"Skye": {
		"sprite": "res://assets/graphics/characters/New Character System/PartySpriteSheets/Skye.png",
		"layered": false
	},
	"Tessa": {
		"sprite": "res://assets/graphics/characters/New Character System/PartySpriteSheets/Tessa.png",
		"layered": false
	}
}

var current_character: String = "Layered (Body+Hair)"

# References to sprite layers
@onready var body_layer = $FarmerSprite/BodyLayer
@onready var hair_layer = $FarmerSprite/HairLayer

# UI References
@onready var animation_dropdown = $UI/AnimationDropdown
@onready var btn_up = $UI/DirectionButtons/BtnUp
@onready var btn_down = $UI/DirectionButtons/BtnDown
@onready var btn_left = $UI/DirectionButtons/BtnLeft
@onready var btn_right = $UI/DirectionButtons/BtnRight
@onready var status_label = $UI/StatusLabel
@onready var character_list = $UI/CharacterPanel/CharacterList

func _ready():
	load_animations_from_csv()
	setup_ui()

	# Only play animation if it was loaded successfully
	if animations.has("Idle_DOWN"):
		play_animation("Idle_DOWN")

	print("FarmerSpriteAnimator ready!")
	print("Loaded " + str(animations.size()) + " animations from CSV")

func load_animations_from_csv():
	var file_path = "res://scenes/test/sprite_animations_data.csv"
	var file = FileAccess.open(file_path, FileAccess.READ)

	if file == null:
		print("ERROR: Could not open CSV file: " + file_path)
		return

	# Skip header
	file.get_csv_line()

	# Track unique animation names for dropdown
	var unique_anims = {}

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

		# Track for dropdown (just the base name)
		unique_anims[anim_name] = true

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

	# Build sorted animation list for dropdown
	animation_list = unique_anims.keys()
	animation_list.sort()

	print("Loaded animations: " + str(animations.keys()))

func setup_ui():
	# Populate dropdown
	if animation_dropdown:
		animation_dropdown.clear()
		for i in range(animation_list.size()):
			animation_dropdown.add_item(animation_list[i], i)

		# Connect signals
		animation_dropdown.item_selected.connect(_on_animation_selected)

		# Set initial selection
		var idle_idx = animation_list.find("Idle")
		if idle_idx >= 0:
			animation_dropdown.select(idle_idx)
	else:
		print("WARNING: AnimationDropdown UI element not found!")

	# Connect direction buttons
	if btn_up:
		btn_up.pressed.connect(_on_direction_pressed.bind("UP"))
	if btn_down:
		btn_down.pressed.connect(_on_direction_pressed.bind("DOWN"))
	if btn_left:
		btn_left.pressed.connect(_on_direction_pressed.bind("LEFT"))
	if btn_right:
		btn_right.pressed.connect(_on_direction_pressed.bind("RIGHT"))

	# Populate character list
	if character_list:
		character_list.clear()
		var char_names = characters.keys()
		char_names.sort()
		for char_name in char_names:
			character_list.add_item(char_name)

		# Connect character selection
		character_list.item_selected.connect(_on_character_selected)

		# Set initial character selection
		var layered_idx = char_names.find("Layered (Body+Hair)")
		if layered_idx >= 0:
			character_list.select(layered_idx)
	else:
		print("WARNING: CharacterList UI element not found!")

func _on_animation_selected(index: int):
	manual_mode = true
	var anim_name = animation_list[index]

	# Try to play with DOWN direction first, or whatever direction is available
	var tried_key = anim_name + "_DOWN"
	if animations.has(tried_key):
		play_animation(tried_key)
	else:
		# Find any direction for this animation
		for key in animations.keys():
			if key.begins_with(anim_name + "_"):
				play_animation(key)
				break

func _on_direction_pressed(direction: String):
	manual_mode = true

	if not animation_dropdown:
		return

	var selected_idx = animation_dropdown.get_selected_id()
	if selected_idx < 0:
		return

	var anim_name = animation_list[selected_idx]
	var anim_key = anim_name + "_" + direction

	if animations.has(anim_key):
		play_animation(anim_key)
		update_status_label()
	else:
		print("Animation not found: " + anim_key)
		if status_label:
			status_label.text = "⚠ No " + direction + " animation for " + anim_name

func update_status_label():
	if status_label:
		var parts = current_animation.split("_")
		if parts.size() >= 2:
			status_label.text = "Playing: " + parts[0] + " [" + parts[1] + "] - Frame " + str(current_frame_index + 1) + "/" + str(animations[current_animation].size())

func _process(delta):
	if not manual_mode:
		handle_keyboard_input()

	update_animation(delta)
	update_status_label()

func handle_keyboard_input():
	# Get input direction
	var input_dir = Vector2.ZERO

	if Input.is_key_pressed(KEY_RIGHT):
		input_dir.x += 1
	if Input.is_key_pressed(KEY_LEFT):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_DOWN):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_UP):
		input_dir.y -= 1

	# Determine animation based on input
	if input_dir != Vector2.ZERO:
		var anim_name = "Walk"

		# Prioritize horizontal movement for animation
		var direction = ""
		if abs(input_dir.x) > abs(input_dir.y):
			if input_dir.x > 0:
				direction = "RIGHT"
			else:
				direction = "LEFT"
		else:
			if input_dir.y > 0:
				direction = "DOWN"
			else:
				direction = "UP"

		var anim_key = anim_name + "_" + direction
		if animations.has(anim_key):
			play_animation(anim_key)
	else:
		# Idle animation - keep current direction
		var direction = "DOWN"
		if current_animation.contains("RIGHT"):
			direction = "RIGHT"
		elif current_animation.contains("LEFT"):
			direction = "LEFT"
		elif current_animation.contains("UP"):
			direction = "UP"

		var idle_key = "Idle_" + direction
		if animations.has(idle_key):
			play_animation(idle_key)

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

	# Don't advance if it's a hold frame
	if current_frame_data.is_hold:
		return

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

func _on_character_selected(index: int):
	var char_names = characters.keys()
	char_names.sort()

	if index >= 0 and index < char_names.size():
		var char_name = char_names[index]
		load_character(char_name)

func load_character(char_name: String):
	if not characters.has(char_name):
		print("Character not found: " + char_name)
		return

	current_character = char_name
	var char_data = characters[char_name]

	if char_data.layered:
		# Layered mode: separate body and hair
		hair_layer.visible = true

		# Load body texture
		var body_texture = load(char_data.body)
		if body_texture:
			body_layer.texture = body_texture
			print("Loaded body: " + char_data.body)

		# Load hair texture
		var hair_texture = load(char_data.hair)
		if hair_texture:
			hair_layer.texture = hair_texture
			print("Loaded hair: " + char_data.hair)
	else:
		# Single sprite mode: use body layer, hide hair layer
		hair_layer.visible = false

		# Load character sprite
		var char_texture = load(char_data.sprite)
		if char_texture:
			body_layer.texture = char_texture
			print("Loaded character: " + char_data.sprite)

	# Refresh current animation frame
	if animations.has(current_animation):
		apply_frame(current_frame_index)

	print("Switched to character: " + char_name)

func _input(event):
	# Toggle between manual and keyboard mode with Space
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE:
			manual_mode = !manual_mode
			var mode_text = "UI Mode" if manual_mode else "Keyboard Mode"
			print("Switched to: " + mode_text)
			if status_label:
				status_label.text = "Mode: " + mode_text
