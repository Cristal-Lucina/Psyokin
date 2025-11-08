extends Control
class_name LoadMenu

const SAVE_DIR   : String = "user://saves"
const MAIN_SCENE : String = "res://scenes/main/Main.tscn"
const TITLE_SCENE: String = "res://scenes/main_menu/Title.tscn"

# Styling constants (matching LoadoutPanel)
const PANEL_BG_COLOR := Color(0.15, 0.15, 0.15, 1.0)  # Dark gray, fully opaque
const PANEL_BORDER_COLOR := Color(1.0, 0.7, 0.75, 1.0)  # Pink border
const PANEL_BORDER_WIDTH := 2
const PANEL_CORNER_RADIUS := 8

@onready var _scroll    : ScrollContainer = get_node("Center/Window/Margin/Root/Scroll") as ScrollContainer
@onready var _backdrop  : ColorRect       = $Backdrop
@onready var _window    : Panel           = get_node("Center/Window") as Panel

var _slots : VBoxContainer = null

# Controller navigation
var _all_buttons: Array[Button] = []
var _selected_button_index: int = 0
var _input_cooldown: float = 0.0
var _input_cooldown_duration: float = 0.2

func _style_panel(panel: Panel) -> void:
	"""Apply LoadoutPanel-style styling to a panel"""
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG_COLOR
	style.border_color = PANEL_BORDER_COLOR
	style.set_border_width_all(PANEL_BORDER_WIDTH)
	style.corner_radius_top_left = PANEL_CORNER_RADIUS
	style.corner_radius_top_right = PANEL_CORNER_RADIUS
	style.corner_radius_bottom_left = PANEL_CORNER_RADIUS
	style.corner_radius_bottom_right = PANEL_CORNER_RADIUS
	panel.add_theme_stylebox_override("panel", style)

func _ready() -> void:
	# Ensure this overlay continues to process even when title is "paused"
	process_mode = Node.PROCESS_MODE_ALWAYS

	mouse_filter = Control.MOUSE_FILTER_STOP
	if _backdrop:
		_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP

	# Apply LoadoutPanel styling to window if it exists
	if _window:
		_style_panel(_window)

	_slots = _scroll.get_node_or_null("Slots") as VBoxContainer
	if _slots == null:
		_slots = VBoxContainer.new()
		_slots.name = "Slots"
		_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_slots.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		_slots.add_theme_constant_override("separation", 8)
		_scroll.add_child(_slots)

	_rebuild()

func _process(delta: float) -> void:
	"""Handle input cooldown and right stick scrolling"""
	if _input_cooldown > 0:
		_input_cooldown -= delta

	# Right stick controls scroll wheel
	if _scroll:
		var right_stick_y = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
		if abs(right_stick_y) > 0.2:  # Deadzone
			var scroll_speed = 500.0  # Pixels per second
			_scroll.scroll_vertical += int(right_stick_y * scroll_speed * delta)

func _input(e: InputEvent) -> void:
	# Safety check - don't process if not in tree
	if not is_inside_tree():
		return

	var viewport := get_viewport()
	if viewport == null:
		return

	# Capture ALL input to prevent it from reaching panels behind this menu
	if e is InputEventKey or e is InputEventJoypadButton or e is InputEventJoypadMotion:
		# Back button closes menu
		if e.is_action_pressed("ui_cancel") or e.is_action_pressed("menu_back"):
			_on_close()
			viewport.set_input_as_handled()
			return

		# Controller navigation through save slots
		if _input_cooldown <= 0 and _all_buttons.size() > 0:
			if e.is_action_pressed("move_up"):
				_navigate_buttons(-1)
				_input_cooldown = _input_cooldown_duration
				viewport.set_input_as_handled()
				return
			elif e.is_action_pressed("move_down"):
				_navigate_buttons(1)
				_input_cooldown = _input_cooldown_duration
				viewport.set_input_as_handled()
				return
			elif e.is_action_pressed("menu_accept"):
				# Activate selected button (load the save)
				if _selected_button_index >= 0 and _selected_button_index < _all_buttons.size():
					_all_buttons[_selected_button_index].emit_signal("pressed")
				viewport.set_input_as_handled()
				return

		# Mark ALL other controller/keyboard input as handled to prevent passthrough
		viewport.set_input_as_handled()

func _rebuild() -> void:
	for c in _slots.get_children():
		c.queue_free()

	var slots: Array[int] = _collect_slots()
	print("[LoadMenu] Found %d save(s)" % [slots.size()])
	if slots.is_empty():
		return

	for slot in slots:
		_slots.add_child(_make_row(slot))

	await get_tree().process_frame
	_slots.queue_sort()

	# Setup controller navigation after slots are created
	_setup_controller_navigation()

func _collect_slots() -> Array[int]:
	var out: Array[int] = []
	var sl: Node = get_node_or_null("/root/aSaveLoad")
	if sl != null and sl.has_method("list_slots"):
		var arr_v: Variant = sl.call("list_slots")
		if typeof(arr_v) == TYPE_ARRAY:
			for s in (arr_v as Array):
				var idx := int(s)
				if not out.has(idx):
					out.append(idx)

	var d := DirAccess.open(SAVE_DIR)
	if d != null:
		for f in d.get_files():
			if f.begins_with("slot_") and f.ends_with(".json"):
				var idx2 := int(f.substr(5, f.length() - 10))
				if not out.has(idx2):
					out.append(idx2)
	out.sort()
	return out

func _format_slot_meta(slot: int) -> String:
	var label := "Slot %d" % slot
	var sl: Node = get_node_or_null("/root/aSaveLoad")
	if sl != null and sl.has_method("get_slot_meta"):
		var meta_v: Variant = sl.call("get_slot_meta", slot)
		if typeof(meta_v) == TYPE_DICTIONARY:
			var meta: Dictionary = meta_v
			if bool(meta.get("exists", false)):
				var when := ""
				var ts := int(meta.get("ts", 0))
				var scene := String(meta.get("scene", ""))
				var summary := String(meta.get("summary", scene))
				if ts > 0:
					when = Time.get_datetime_string_from_unix_time(ts, true)
				var parts: Array[String] = ["Slot %d" % slot]
				if when    != "": parts.append(when)
				if summary != "": parts.append(summary)
				return "  —  ".join(parts)
	return label

func _make_row(slot: int) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.y = 40
	row.add_theme_constant_override("separation", 8)

	var row_btn := Button.new()
	row_btn.text = _format_slot_meta(slot)
	row_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_btn.focus_mode = Control.FOCUS_ALL
	row_btn.flat = false
	row_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row_btn.pressed.connect(_on_load_pressed.bind(slot))
	row.add_child(row_btn)

	var load_b := Button.new()
	load_b.text = "Load"
	load_b.custom_minimum_size.y = 28
	load_b.pressed.connect(_on_load_pressed.bind(slot))
	row.add_child(load_b)

	var del_b := Button.new()
	del_b.text = "Delete"
	del_b.custom_minimum_size.y = 28
	del_b.pressed.connect(_on_delete_pressed.bind(slot))
	row.add_child(del_b)

	return row

func _on_load_pressed(slot: int) -> void:
	var sl: Node = get_node_or_null("/root/aSaveLoad")
	var payload: Dictionary = {}
	if sl != null and sl.has_method("load_game"):
		var v: Variant = sl.call("load_game", slot)
		if typeof(v) == TYPE_DICTIONARY:
			payload = v

	# 1) Let GameState restore everything (modules + equip snapshot etc.)
	if has_node("/root/aGameState") and not payload.is_empty() and aGameState.has_method("apply_loaded_save"):
		aGameState.apply_loaded_save(payload)

	# 2) Safety net: if this save has a top-level "sigils" blob, apply it too.
	if not payload.is_empty() and payload.has("sigils"):
		var sb_v: Variant = payload.get("sigils", {})
		if typeof(sb_v) == TYPE_DICTIONARY:
			var sig := get_node_or_null("/root/aSigilSystem")
			if sig != null and sig.has_method("apply_save_blob"):
				sig.call("apply_save_blob", (sb_v as Dictionary))

	if has_node("/root/aSceneRouter"):
		aSceneRouter.goto_main()
	elif ResourceLoader.exists(MAIN_SCENE):
		get_tree().change_scene_to_file(MAIN_SCENE)

	queue_free()

func _on_delete_pressed(slot: int) -> void:
	var ok := false
	var sl: Node = get_node_or_null("/root/aSaveLoad")
	if sl != null and sl.has_method("delete_slot"):
		ok = bool(sl.call("delete_slot", slot))
	else:
		var path := "%s/slot_%d.json" % [SAVE_DIR, slot]
		if FileAccess.file_exists(path):
			ok = (DirAccess.remove_absolute(path) == OK)

	if not ok:
		push_warning("[LoadMenu] Could not delete slot %d" % slot)
	_rebuild()

func _on_close() -> void:
	print("[LoadMenu] Closing load menu")
	queue_free()

# ------------------------------------------------------------------------------
# Controller Navigation Helpers
# ------------------------------------------------------------------------------

func _setup_controller_navigation() -> void:
	"""Setup controller navigation for all save slot buttons"""
	_all_buttons.clear()

	# Collect all load buttons from each slot row
	for row in _slots.get_children():
		if row is HBoxContainer:
			for child in row.get_children():
				if child is Button:
					_all_buttons.append(child)

	# Start with first button selected
	if _all_buttons.size() > 0:
		_selected_button_index = 0
		_highlight_button(_selected_button_index)

	print("[LoadMenu] Navigation setup complete. ", _all_buttons.size(), " buttons")

func _navigate_buttons(direction: int) -> void:
	"""Navigate through buttons with controller"""
	if _all_buttons.is_empty():
		return

	_unhighlight_button(_selected_button_index)

	_selected_button_index += direction
	if _selected_button_index < 0:
		_selected_button_index = _all_buttons.size() - 1
	elif _selected_button_index >= _all_buttons.size():
		_selected_button_index = 0

	_highlight_button(_selected_button_index)

func _highlight_button(index: int) -> void:
	"""Highlight a button"""
	if index >= 0 and index < _all_buttons.size():
		var button = _all_buttons[index]
		button.modulate = Color(1.2, 1.2, 0.8, 1.0)
		button.grab_focus()

func _unhighlight_button(index: int) -> void:
	"""Remove highlight from a button"""
	if index >= 0 and index < _all_buttons.size():
		var button = _all_buttons[index]
		button.modulate = Color(1.0, 1.0, 1.0, 1.0)
