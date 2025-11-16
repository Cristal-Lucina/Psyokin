extends Control
class_name SaveMenu

## SaveMenu — resilient, centered modal (3 fixed slots).
## - Finds nodes via multiple paths or builds a fallback layout.
## - Preferred save path: aGameState.save_to_slot(slot)
## - Fallback: aSaveLoad.save_game(slot, payload)
## - Esc closes.

const SAVE_DIR: String = "user://saves"

# Core Vibe styling (neon-kawaii aesthetic)
# Note: Uses aCoreVibeTheme autoload for consistent styling

# Candidate paths (we'll probe these in order)
const PATH_SLOTS  : PackedStringArray = [
	"Center/Window/Margin/Root/Scroll/SlotsGrid",
	"Center/Window/Margin/Root/Scroll/Slots",
	"Center/Window/Root/Slots",
	"Center/Panel/Root/Slots",
	"MarginContainer/Panel/Root/Slots",
	"Panel/Root/Slots",
	"Root/Slots",
	"Slots"
]

var _slots_grid : GridContainer
var _backdrop   : ColorRect
var _window     : Panel
var _scroll     : ScrollContainer

# Controller navigation - 2D grid (rows = slots, columns = save/delete)
var _save_buttons: Array[Button] = []
var _delete_buttons: Array[Button] = []
var _current_row: int = 0
var _current_column: int = 0  # 0 = Save, 1 = Delete
var _input_cooldown: float = 0.0
var _input_cooldown_duration: float = 0.2

# --- helpers -------------------------------------------------------------------

func _find_node_any(paths: PackedStringArray) -> Node:
	# Try exact paths
	for p in paths:
		var n: Node = get_node_or_null(p)
		if n: return n
	# Try by last-segment name, deep search
	for p in paths:
		var name_only := p.get_file()
		var f := find_child(name_only, true, false)
		if f: return f
	return null

func _style_panel(panel: Panel) -> void:
	"""Apply Core Vibe neon-kawaii styling to a panel"""
	var style = aCoreVibeTheme.create_panel_style(
		aCoreVibeTheme.COLOR_MILK_WHITE,          # White border
		aCoreVibeTheme.COLOR_NIGHT_NAVY,          # Black background
		1.0,                                       # Full opacity
		aCoreVibeTheme.CORNER_RADIUS_MEDIUM,      # 16px rounded corners
		aCoreVibeTheme.BORDER_WIDTH_THIN,         # 2px border
		aCoreVibeTheme.SHADOW_SIZE_LARGE          # 12px glow
	)
	panel.add_theme_stylebox_override("panel", style)

func _add_button_padding(button: Button) -> void:
	"""Add padding to button text so it doesn't touch edges"""
	# Get the current styleboxes and add content margins
	for state in ["normal", "hover", "pressed", "focus"]:
		var stylebox = button.get_theme_stylebox(state)
		if stylebox and stylebox is StyleBoxFlat:
			var style = stylebox as StyleBoxFlat
			style.content_margin_left = 12
			style.content_margin_right = 12
			style.content_margin_top = 8
			style.content_margin_bottom = 8

func _ensure_fallback_layout() -> void:
	# Build a compact center window if required
	if _slots_grid != null:
		return

	# Root centerer
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Window frame with LoadoutPanel styling
	_window = Panel.new()
	_window.name = "Window"
	_window.custom_minimum_size = Vector2(700, 500)
	_style_panel(_window)
	center.add_child(_window)

	# Add margin container for padding (matching LoadoutPanel)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	margin.anchor_left = 0.0
	margin.anchor_right = 1.0
	margin.anchor_top = 0.0
	margin.anchor_bottom = 1.0
	_window.add_child(margin)

	# Root VBox
	var root := VBoxContainer.new()
	root.name = "Root"
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	# Title label with Core Vibe styling
	var title := Label.new()
	title.name = "Title"
	title.text = "Save Game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Core Vibe: White title to match border
	aCoreVibeTheme.style_label(title, aCoreVibeTheme.COLOR_MILK_WHITE, 20)
	root.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER  # Center content
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_slots_grid = GridContainer.new()
	_slots_grid.name = "SlotsGrid"
	_slots_grid.columns = 2
	_slots_grid.add_theme_constant_override("h_separation", 12)
	_slots_grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(_slots_grid)

# --- lifecycle ----------------------------------------------------------------

func _ready() -> void:
	print("[SaveMenu] _ready() called - initializing save menu")
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Stop input from passing through
	mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop = get_node_or_null("Backdrop") as ColorRect
	if _backdrop:
		_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP

	# Apply LoadoutPanel styling to window if it exists
	_window = get_node_or_null("Center/Window") as Panel
	if _window:
		_style_panel(_window)

	# Resolve existing nodes first
	_slots_grid = _find_node_any(PATH_SLOTS) as GridContainer

	print("[SaveMenu] Found nodes - slots_grid: %s" % ["yes" if _slots_grid else "no"])

	# If anything is missing, build a fallback (safe & centered)
	_ensure_fallback_layout()

	# Ensure we're visible
	show()
	visible = true

	print("[SaveMenu] Rebuilding slot UI")
	_rebuild()
	print("[SaveMenu] Ready complete - save menu visible: %s" % visible)

func _process(delta: float) -> void:
	"""Handle input cooldown"""
	if _input_cooldown > 0:
		_input_cooldown -= delta

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

		# 2D grid navigation through save slots
		if _input_cooldown <= 0 and _save_buttons.size() > 0:
			if e.is_action_pressed("move_up"):
				_navigate_grid_vertical(-1)
				_input_cooldown = _input_cooldown_duration
				viewport.set_input_as_handled()
				return
			elif e.is_action_pressed("move_down"):
				_navigate_grid_vertical(1)
				_input_cooldown = _input_cooldown_duration
				viewport.set_input_as_handled()
				return
			elif e.is_action_pressed("move_left"):
				_navigate_grid_horizontal(-1)
				_input_cooldown = _input_cooldown_duration
				viewport.set_input_as_handled()
				return
			elif e.is_action_pressed("move_right"):
				_navigate_grid_horizontal(1)
				_input_cooldown = _input_cooldown_duration
				viewport.set_input_as_handled()
				return
			elif e.is_action_pressed("menu_accept"):
				_activate_current_button()
				viewport.set_input_as_handled()
				return

		# Mark ALL other controller/keyboard input as handled to prevent passthrough
		viewport.set_input_as_handled()

# --- UI build -----------------------------------------------------------------

func _rebuild() -> void:
	for c in _slots_grid.get_children():
		c.queue_free()

	_save_buttons.clear()
	_delete_buttons.clear()

	# Create grid with 2 columns (Save, Delete)
	for i in range(1, 4):
		var idx := i  # capture per-iteration

		# Save button with slot label (Core Vibe: Plasma Teal)
		var btn_save: Button = Button.new()
		btn_save.text = _label_for_slot(idx)
		btn_save.custom_minimum_size = Vector2(430, 40)  # Match LoadMenu width
		btn_save.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn_save.focus_mode = Control.FOCUS_ALL
		btn_save.pressed.connect(func() -> void: _do_save(idx))
		aCoreVibeTheme.style_button_with_focus_invert(btn_save, aCoreVibeTheme.COLOR_PLASMA_TEAL, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
		# Add text padding
		_add_button_padding(btn_save)
		_slots_grid.add_child(btn_save)
		_save_buttons.append(btn_save)

		# Delete button (Core Vibe: Bubble Magenta)
		var btn_del: Button = Button.new()
		btn_del.text = "Delete"
		btn_del.custom_minimum_size = Vector2(80, 40)  # Match LoadMenu width
		btn_del.focus_mode = Control.FOCUS_ALL
		btn_del.pressed.connect(func() -> void: _do_delete(idx))
		aCoreVibeTheme.style_button_with_focus_invert(btn_del, aCoreVibeTheme.COLOR_BUBBLE_MAGENTA, aCoreVibeTheme.CORNER_RADIUS_MEDIUM)
		# Add text padding
		_add_button_padding(btn_del)
		_slots_grid.add_child(btn_del)
		_delete_buttons.append(btn_del)

	# Setup controller navigation after slots are created
	await get_tree().process_frame
	_setup_grid_navigation()

# --- labels & actions ----------------------------------------------------------

func _label_for_slot(slot: int) -> String:
	if has_node("/root/aSaveLoad"):
		var meta: Dictionary = aSaveLoad.get_slot_meta(slot)
		if bool(meta.get("exists", false)):
			var ts: int = int(meta.get("ts", 0))
			var when: String = (Time.get_datetime_string_from_unix_time(ts, true) if ts > 0 else "")
			var summary: String = String(meta.get("summary", String(meta.get("scene", ""))))
			var parts: Array[String] = ["Slot %d" % slot]
			if when   != "": parts.append(when)
			if summary != "": parts.append(summary)
			return "  —  ".join(parts)
	return "Slot %d (empty)" % slot

func _do_save(slot: int) -> void:
	# Save player position to GameState before saving
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("save_position"):
		player.save_position()

	# Preferred: ask GameState to serialize and save itself.
	if has_node("/root/aGameState") and aGameState.has_method("save_to_slot"):
		aGameState.save_to_slot(slot)
	elif has_node("/root/aSaveLoad"):
		# Fallback: pass a payload if your GameState exposes one (optional)
		var payload: Dictionary = {}
		if has_node("/root/aGameState") and aGameState.has_method("get_save_payload"):
			payload = aGameState.get_save_payload()
		aSaveLoad.save_game(slot, payload)
	else:
		push_warning("[SaveMenu] No save path available.")

	print("[SaveMenu] Saved to slot %d" % slot)
	_rebuild()

func _do_delete(slot: int) -> void:
	var ok := false
	if has_node("/root/aSaveLoad"):
		ok = aSaveLoad.delete_slot(slot)
	else:
		var path := "%s/slot_%d.json" % [SAVE_DIR, slot]
		if FileAccess.file_exists(path):
			ok = (DirAccess.remove_absolute(path) == OK)

	if not ok:
		push_warning("[SaveMenu] Could not delete slot %d" % slot)
	else:
		print("[SaveMenu] Deleted slot %d" % slot)

	_rebuild()

func _on_close() -> void:
	print("[SaveMenu] Closing save menu")
	queue_free()

# ------------------------------------------------------------------------------
# 2D Grid Navigation Helpers
# ------------------------------------------------------------------------------

func _setup_grid_navigation() -> void:
	"""Setup 2D grid navigation for save/delete buttons"""
	# Start at first save button
	_current_row = 0
	_current_column = 0
	_highlight_current_button()

	print("[SaveMenu] Grid navigation setup complete. %d save buttons, %d delete buttons" % [_save_buttons.size(), _delete_buttons.size()])

func _navigate_grid_vertical(direction: int) -> void:
	"""Navigate up/down through rows in current column"""
	if _save_buttons.is_empty():
		return

	_unhighlight_current_button()

	_current_row += direction

	# Wrap around within current column
	var max_rows = _save_buttons.size()
	if _current_row < 0:
		_current_row = max_rows - 1
	elif _current_row >= max_rows:
		_current_row = 0

	_highlight_current_button()

func _navigate_grid_horizontal(direction: int) -> void:
	"""Navigate left/right between columns (Save/Delete)"""
	if _save_buttons.is_empty():
		return

	_unhighlight_current_button()

	_current_column += direction

	# Clamp to 2 columns (0 = Save, 1 = Delete)
	if _current_column < 0:
		_current_column = 1
	elif _current_column > 1:
		_current_column = 0

	_highlight_current_button()

func _activate_current_button() -> void:
	"""Activate the currently selected button"""
	var button: Button = _get_current_button()
	if button:
		print("[SaveMenu] Activating button: %s" % button.text)
		button.emit_signal("pressed")

func _get_current_button() -> Button:
	"""Get the button at current grid position"""
	if _current_row < 0:
		return null

	if _current_column == 0:
		if _current_row < _save_buttons.size():
			return _save_buttons[_current_row]
	elif _current_column == 1:
		if _current_row < _delete_buttons.size():
			return _delete_buttons[_current_row]

	return null

func _highlight_current_button() -> void:
	"""Highlight the button at current grid position"""
	var button: Button = _get_current_button()
	if button:
		button.modulate = Color(1.2, 1.2, 0.8, 1.0)
		button.grab_focus()

func _unhighlight_current_button() -> void:
	"""Remove highlight from the button at current grid position"""
	var button: Button = _get_current_button()
	if button:
		button.modulate = Color(1.0, 1.0, 1.0, 1.0)
