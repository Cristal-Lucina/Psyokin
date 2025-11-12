extends Control
class_name LoadMenu

const SAVE_DIR   : String = "user://saves"
const MAIN_SCENE : String = "res://scenes/main/Main.tscn"
const TITLE_SCENE: String = "res://scenes/main_menu/Title.tscn"

# Core Vibe styling (neon-kawaii aesthetic)
# Note: Uses aCoreVibeTheme autoload for consistent styling

@onready var _scroll    : ScrollContainer = get_node("Center/Window/Margin/Root/Scroll") as ScrollContainer
@onready var _backdrop  : ColorRect       = $Backdrop
@onready var _window    : Panel           = get_node("Center/Window") as Panel

var _slots : VBoxContainer = null

# Controller navigation
var _all_slots: Array = []  # Array of {slot: int, slot_btn: Button, delete_btn: Button}
var _selected_slot_index: int = 0
var _selected_button_type: String = "slot"  # "slot" or "delete"
var _input_cooldown: float = 0.0
var _input_cooldown_duration: float = 0.2

func _style_panel(panel: Panel) -> void:
	"""Apply Core Vibe neon-kawaii styling to a panel"""
	var style = aCoreVibeTheme.create_panel_style(
		aCoreVibeTheme.COLOR_SKY_CYAN,            # Sky Cyan border (load action)
		aCoreVibeTheme.COLOR_INK_CHARCOAL,        # Ink charcoal background
		aCoreVibeTheme.PANEL_OPACITY_FULL,        # Fully opaque
		aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px corners
		aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
		aCoreVibeTheme.SHADOW_SIZE_LARGE          # 12px glow
	)
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
		if _input_cooldown <= 0 and _all_slots.size() > 0:
			if e.is_action_pressed("move_up"):
				_navigate_slots(-1)
				_input_cooldown = _input_cooldown_duration
				viewport.set_input_as_handled()
				return
			elif e.is_action_pressed("move_down"):
				_navigate_slots(1)
				_input_cooldown = _input_cooldown_duration
				viewport.set_input_as_handled()
				return
			elif e.is_action_pressed("move_right"):
				_navigate_to_delete()
				_input_cooldown = _input_cooldown_duration
				viewport.set_input_as_handled()
				return
			elif e.is_action_pressed("move_left"):
				_navigate_to_slot()
				_input_cooldown = _input_cooldown_duration
				viewport.set_input_as_handled()
				return
			elif e.is_action_pressed("menu_accept"):
				# Activate selected button
				if _selected_slot_index >= 0 and _selected_slot_index < _all_slots.size():
					var slot_data = _all_slots[_selected_slot_index]
					if _selected_button_type == "slot":
						slot_data["slot_btn"].emit_signal("pressed")
					elif _selected_button_type == "delete":
						slot_data["delete_btn"].emit_signal("pressed")
				viewport.set_input_as_handled()
				return

		# Mark ALL other controller/keyboard input as handled to prevent passthrough
		viewport.set_input_as_handled()

func _rebuild() -> void:
	for c in _slots.get_children():
		c.queue_free()

	_all_slots.clear()

	var slots: Array[int] = _collect_slots()
	print("[LoadMenu] Found %d save(s)" % [slots.size()])
	if slots.is_empty():
		return

	for slot in slots:
		var slot_data = _make_row(slot)
		_slots.add_child(slot_data["row"])
		_all_slots.append(slot_data)

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

func _make_row(slot: int) -> Dictionary:
	"""Create a save slot row and return button references for navigation"""
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size.y = 44
	row.add_theme_constant_override("separation", 8)

	# Main slot button (Core Vibe: Sky Cyan) - Press to load
	var row_btn := Button.new()
	row_btn.text = _format_slot_meta(slot)
	row_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_btn.focus_mode = Control.FOCUS_ALL
	row_btn.flat = false
	row_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row_btn.custom_minimum_size = Vector2(430, 40)  # Wider since we removed Load button
	row_btn.pressed.connect(_on_load_pressed.bind(slot))
	aCoreVibeTheme.style_button(row_btn, aCoreVibeTheme.COLOR_SKY_CYAN, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
	row.add_child(row_btn)

	# Delete button (Core Vibe: Bubble Magenta)
	var del_b := Button.new()
	del_b.text = "Delete"
	del_b.custom_minimum_size = Vector2(80, 40)
	del_b.pressed.connect(_on_delete_pressed.bind(slot))
	aCoreVibeTheme.style_button(del_b, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
	row.add_child(del_b)

	return {
		"slot": slot,
		"row": row,
		"slot_btn": row_btn,
		"delete_btn": del_b
	}

func _on_load_pressed(slot: int) -> void:
	print("[LoadMenu] Load pressed for slot %d - closing game menu first" % slot)

	# CRITICAL: Close the entire GameMenu hierarchy before loading
	# Find and close GameMenu to clean up the UI stack
	var game_menu := get_tree().current_scene.find_child("GameMenu", true, false)
	if game_menu:
		print("[LoadMenu] Found GameMenu, closing it")
		game_menu.queue_free()

	# Force reset PanelManager to clear panel stack
	if has_node("/root/aPanelManager"):
		print("[LoadMenu] Force resetting PanelManager")
		aPanelManager.force_reset()

	# CRITICAL: Unpause the game tree before changing scenes
	print("[LoadMenu] Unpausing game tree")
	get_tree().paused = false

	# Wait a frame for GameMenu to be freed
	await get_tree().process_frame

	# Create and show loading screen
	var loading = LoadingScreen.create()
	if loading:
		get_tree().root.add_child(loading)
		loading.set_text("Loading save...")
		await loading.fade_in()

	# Small delay to ensure loading screen is visible
	await get_tree().create_timer(0.1).timeout

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

	# Store the loaded payload and slot info for title screen to use
	if has_node("/root/aGameState"):
		aGameState.set_meta("pending_load_payload", payload)
		aGameState.set_meta("pending_load_from_ingame", true)

	# Schedule loading screen fade-out to happen after ALL scene changes complete
	# The loading screen will handle the entire transition: LoadMenu → Title → Main
	if loading:
		loading.call_deferred("_fade_out_and_cleanup")

	# Change to title screen (this will automatically free the current scene, including LoadMenu)
	# Title will detect pending load and immediately transition to Main
	# The loading screen persists through both scene changes and cleans itself up at the end
	get_tree().change_scene_to_file(TITLE_SCENE)

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
	"""Setup controller navigation for save slots"""
	# Start with first slot selected, on the slot button
	if _all_slots.size() > 0:
		_selected_slot_index = 0
		_selected_button_type = "slot"
		_highlight_current_button()

	print("[LoadMenu] Navigation setup complete. ", _all_slots.size(), " slots")

func _navigate_slots(direction: int) -> void:
	"""Navigate up/down through save slots"""
	if _all_slots.is_empty():
		return

	_unhighlight_current_button()

	_selected_slot_index += direction
	if _selected_slot_index < 0:
		_selected_slot_index = _all_slots.size() - 1
	elif _selected_slot_index >= _all_slots.size():
		_selected_slot_index = 0

	# When changing slots, always start on the slot button
	_selected_button_type = "slot"
	_highlight_current_button()

func _navigate_to_delete() -> void:
	"""Navigate right to the delete button"""
	if _selected_button_type == "slot":
		_unhighlight_current_button()
		_selected_button_type = "delete"
		_highlight_current_button()

func _navigate_to_slot() -> void:
	"""Navigate left to the slot button"""
	if _selected_button_type == "delete":
		_unhighlight_current_button()
		_selected_button_type = "slot"
		_highlight_current_button()

func _highlight_current_button() -> void:
	"""Highlight the currently selected button"""
	if _selected_slot_index >= 0 and _selected_slot_index < _all_slots.size():
		var slot_data = _all_slots[_selected_slot_index]
		var button: Button
		if _selected_button_type == "slot":
			button = slot_data["slot_btn"]
		else:
			button = slot_data["delete_btn"]

		button.modulate = Color(1.2, 1.2, 0.8, 1.0)
		button.grab_focus()

func _unhighlight_current_button() -> void:
	"""Remove highlight from the currently selected button"""
	if _selected_slot_index >= 0 and _selected_slot_index < _all_slots.size():
		var slot_data = _all_slots[_selected_slot_index]
		var button: Button
		if _selected_button_type == "slot":
			button = slot_data["slot_btn"]
		else:
			button = slot_data["delete_btn"]

		button.modulate = Color(1.0, 1.0, 1.0, 1.0)
