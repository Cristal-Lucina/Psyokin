## ═══════════════════════════════════════════════════════════════════════════
## AnimationDataLoader - CSV Animation Data Parser
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Loads and parses sprite animation data from sprite_animations_data.csv
##   Provides animation frame sequences and timing for character sprites.
##
## CSV FORMAT:
##   Animation,Direction,Frames,Cell1,Time1,Cell2,Time2,...,Special
##   Example: Walk,DOWN,6,48,135,49,135,50,135,48f,135,49f,135,50f,135,
##
## FRAME FORMAT:
##   - Numbers: frame index (e.g., "48")
##   - Numbers with 'f': frame index with horizontal flip (e.g., "48f")
##   - "Hold": hold frame indefinitely
##
## ═══════════════════════════════════════════════════════════════════════════

class_name AnimationDataLoader

const CSV_PATH = "res://assets/graphics/characters/New Character System/sprite_animations_data.csv"

## Animation frame data structure
class AnimationFrame:
	var frame: int = 0
	var time_ms: int = 135
	var flip_h: bool = false
	var hold: bool = false

	func _init(f: int = 0, t: int = 135, flip: bool = false, is_hold: bool = false):
		frame = f
		time_ms = t
		flip_h = flip
		hold = is_hold

## Animation sequence data
class AnimationSequence:
	var animation_name: String = ""
	var direction: String = ""
	var frames: Array[AnimationFrame] = []
	var total_frames: int = 0

	func get_frame_at_index(index: int) -> AnimationFrame:
		if frames.is_empty():
			return AnimationFrame.new()
		return frames[index % frames.size()]

## Singleton instance
static var _instance: AnimationDataLoader = null
static var _animations: Dictionary = {}  # Key: "AnimationName_DIRECTION", Value: AnimationSequence

## Get singleton instance
static func get_instance() -> AnimationDataLoader:
	if _instance == null:
		_instance = AnimationDataLoader.new()
		_instance.load_animations()
	return _instance

## Load all animations from CSV
func load_animations() -> void:
	_animations.clear()

	var file = FileAccess.open(CSV_PATH, FileAccess.READ)
	if not file:
		push_error("[AnimationDataLoader] Failed to open CSV: " + CSV_PATH)
		return

	# Skip header line
	var header = file.get_csv_line()

	var line_num = 2
	while not file.eof_reached():
		var line = file.get_csv_line()
		if line.size() < 3:
			continue

		var anim_name = line[0].strip_edges()
		var direction = line[1].strip_edges().to_upper()
		var frame_count_str = line[2].strip_edges()

		if anim_name.is_empty() or direction.is_empty():
			continue

		var frame_count = int(frame_count_str)
		if frame_count == 0:
			continue

		var sequence = AnimationSequence.new()
		sequence.animation_name = anim_name
		sequence.direction = direction
		sequence.total_frames = frame_count

		# Parse frame data (Cell1, Time1, Cell2, Time2, ...)
		var col_index = 3
		for i in range(frame_count):
			if col_index >= line.size():
				break

			var cell_str = line[col_index].strip_edges()
			var time_str = line[col_index + 1].strip_edges() if col_index + 1 < line.size() else "135"

			if cell_str.is_empty():
				break

			var frame_data = _parse_frame(cell_str, time_str)
			sequence.frames.append(frame_data)

			col_index += 2

		# Store with key: "AnimationName_DIRECTION"
		var key = anim_name + "_" + direction
		_animations[key] = sequence

		line_num += 1

	file.close()
	print("[AnimationDataLoader] Loaded %d animation sequences" % _animations.size())

## Parse a single frame cell (e.g., "48f" -> frame 48, flipped)
func _parse_frame(cell: String, time: String) -> AnimationFrame:
	var flip_h = false
	var hold = false
	var frame_num = 0

	# Check for "Hold" special value
	if time.to_lower() == "hold":
		hold = true

	# Check for flip suffix
	if cell.ends_with("f") or cell.ends_with("F"):
		flip_h = true
		cell = cell.substr(0, cell.length() - 1)

	# Parse frame number
	frame_num = int(cell)

	# Parse time (milliseconds)
	var time_ms = int(time) if not hold else 9999999

	return AnimationFrame.new(frame_num, time_ms, flip_h, hold)

## Get animation sequence by name and direction
static func get_animation(anim_name: String, direction: String) -> AnimationSequence:
	var instance = get_instance()
	var key = anim_name + "_" + direction.to_upper()
	if instance._animations.has(key):
		return instance._animations[key]

	# Return empty sequence if not found
	var empty = AnimationSequence.new()
	empty.animation_name = anim_name
	empty.direction = direction
	return empty

## Get all available animations
static func get_all_animations() -> Dictionary:
	return get_instance()._animations

## Check if animation exists
static func has_animation(anim_name: String, direction: String) -> bool:
	var instance = get_instance()
	var key = anim_name + "_" + direction.to_upper()
	return instance._animations.has(key)
