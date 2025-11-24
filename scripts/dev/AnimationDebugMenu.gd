## ═══════════════════════════════════════════════════════════════════════════
## AnimationDebugMenu - Debug UI for Character Animations
## ═══════════════════════════════════════════════════════════════════════════
##
## PURPOSE:
##   Displays real-time animation information for the player character
##   Shows current animation state, frame data, and available animations from CSV
##
## CONTROLS:
##   Press Y to toggle this menu
##
## ═══════════════════════════════════════════════════════════════════════════

extends PanelContainer

const AnimationDataLoaderScript = preload("res://scripts/player/AnimationDataLoader.gd")

# UI Elements
var _info_label: Label
var _animations_list: Label
var _player: Node = null

func _init():
	# Create UI structure
	name = "AnimationDebugMenu"

	# Position in top-right corner
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -450
	offset_top = 10
	offset_right = -10
	offset_bottom = 500

	# Style panel
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	panel_style.border_color = Color(0.3, 0.91, 1.0, 1.0)  # Cyan
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 12
	panel_style.content_margin_bottom = 12
	add_theme_stylebox_override("panel", panel_style)

	# Create content container
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "ANIMATION DEBUG"
	title.add_theme_color_override("font_color", Color(0.3, 0.91, 1.0))
	title.add_theme_font_size_override("font_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Separator
	var separator1 = HSeparator.new()
	separator1.add_theme_constant_override("separation", 4)
	vbox.add_child(separator1)

	# Info section
	var info_title = Label.new()
	info_title.text = "Current Animation:"
	info_title.add_theme_color_override("font_color", Color(1.0, 0.91, 0.3))
	info_title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(info_title)

	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 12)
	_info_label.add_theme_color_override("font_color", Color(0.96, 0.97, 0.98))
	vbox.add_child(_info_label)

	# Separator
	var separator2 = HSeparator.new()
	separator2.add_theme_constant_override("separation", 4)
	vbox.add_child(separator2)

	# Available animations section
	var list_title = Label.new()
	list_title.text = "Available Animations:"
	list_title.add_theme_color_override("font_color", Color(1.0, 0.91, 0.3))
	list_title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(list_title)

	# Scrollable animations list
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 200)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_animations_list = Label.new()
	_animations_list.add_theme_font_size_override("font_size", 11)
	_animations_list.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	scroll.add_child(_animations_list)

	# Instructions
	var instructions = Label.new()
	instructions.text = "Press Y to close"
	instructions.add_theme_font_size_override("font_size", 10)
	instructions.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(instructions)

func _ready():
	# Find player
	_player = get_tree().get_first_node_in_group("player")

	# Populate animations list
	_update_animations_list()

	# Enable processing for real-time updates
	set_process(true)

func _process(_delta):
	if not _player or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if not _player:
			_info_label.text = "Player not found"
			return

	_update_info()

func _update_info():
	"""Update real-time animation info"""
	if not _player:
		return

	var info_lines = []

	# Get player state
	var state = _player.get("_current_state")
	var direction = _player.get("_current_direction")
	var frame_index = _player.get("_anim_frame_index")
	var frame_timer = _player.get("_anim_frame_timer")
	var current_seq = _player.get("_current_sequence")

	# State name
	var state_name = "UNKNOWN"
	if state != null:
		match state:
			0: state_name = "IDLE"
			1: state_name = "WALK"
			2: state_name = "RUN"
			3: state_name = "JUMP"
			4: state_name = "PUSH"
			5: state_name = "PULL"

	# Direction name
	var dir_name = "UNKNOWN"
	if direction != null:
		match direction:
			0: dir_name = "DOWN"
			1: dir_name = "UP"
			2: dir_name = "RIGHT"
			3: dir_name = "LEFT"

	info_lines.append("State: %s" % state_name)
	info_lines.append("Direction: %s" % dir_name)
	info_lines.append("")

	# Current sequence info
	if current_seq != null and current_seq is AnimationDataLoaderScript.AnimationSequence:
		info_lines.append("Animation: %s_%s" % [current_seq.animation_name, current_seq.direction])
		info_lines.append("Total Frames: %d" % current_seq.frames.size())
		info_lines.append("Current Frame Index: %d" % frame_index)
		info_lines.append("Frame Timer: %.3f s" % frame_timer)
		info_lines.append("")

		# Current frame details
		if frame_index < current_seq.frames.size():
			var frame_data = current_seq.frames[frame_index]
			info_lines.append("Frame Data:")
			info_lines.append("  Frame #: %d" % frame_data.frame)
			info_lines.append("  Time: %d ms" % frame_data.time_ms)
			info_lines.append("  Flip H: %s" % ("Yes" if frame_data.flip_h else "No"))
			info_lines.append("  Hold: %s" % ("Yes" if frame_data.hold else "No"))

		# Frame sequence preview
		if current_seq.frames.size() > 0:
			info_lines.append("")
			info_lines.append("Frame Sequence:")
			var seq_preview = "  "
			for i in range(current_seq.frames.size()):
				var f = current_seq.frames[i]
				var frame_str = str(f.frame)
				if f.flip_h:
					frame_str += "f"
				if i == frame_index:
					seq_preview += "[%s] " % frame_str
				else:
					seq_preview += "%s " % frame_str
			info_lines.append(seq_preview)
	else:
		info_lines.append("No animation sequence loaded")

	_info_label.text = "\n".join(info_lines)

func _update_animations_list():
	"""Update the list of available animations"""
	var all_anims = AnimationDataLoaderScript.get_all_animations()

	if all_anims.is_empty():
		_animations_list.text = "No animations loaded"
		return

	var lines = []
	var keys = all_anims.keys()
	keys.sort()

	# Group by animation name
	var groups = {}
	for key in keys:
		var seq = all_anims[key]
		if not groups.has(seq.animation_name):
			groups[seq.animation_name] = []
		groups[seq.animation_name].append(seq)

	var group_names = groups.keys()
	group_names.sort()

	for anim_name in group_names:
		lines.append("• %s:" % anim_name)
		var sequences = groups[anim_name]
		for seq in sequences:
			var frame_count = seq.frames.size()
			lines.append("  %s (%d frames)" % [seq.direction, frame_count])

	lines.append("")
	lines.append("Total: %d animations" % all_anims.size())

	_animations_list.text = "\n".join(lines)

## Static factory method
static func create() -> AnimationDebugMenu:
	return AnimationDebugMenu.new()
