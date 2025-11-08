extends Control
class_name SaveMenu

## SaveMenu — resilient, centered modal (3 fixed slots).
## - Finds nodes via multiple paths or builds a fallback layout.
## - Preferred save path: aGameState.save_to_slot(slot)
## - Fallback: aSaveLoad.save_game(slot, payload)
## - Esc closes.

const SAVE_DIR: String = "user://saves"

# Candidate paths (we’ll probe these in order)
const PATH_SLOTS  : PackedStringArray = [
	"Center/Window/Root/Slots",
	"Center/Panel/Root/Slots",
	"MarginContainer/Panel/Root/Slots",
	"Panel/Root/Slots",
	"Root/Slots",
	"Slots"
]
const PATH_TITLE  : PackedStringArray = [
	"Center/Window/Root/Header/Title",
	"Center/Panel/Root/Header/Title",
	"Panel/Root/Header/Title",
	"Root/Header/Title",
	"Title"
]
const PATH_CLOSE  : PackedStringArray = [
	"Center/Window/Root/Header/CloseBtn",
	"Center/Panel/Root/Header/CloseBtn",
	"Panel/Root/Header/CloseBtn",
	"Root/Header/CloseBtn",
	"CloseBtn"
]
const PATH_HINT   : PackedStringArray = [
	"Center/Window/Root/Hint",
	"Center/Panel/Root/Hint",
	"Panel/Root/Hint",
	"Root/Hint",
	"Hint"
]

var _slots     : VBoxContainer
var _btn_close : Button
var _title     : Label
var _hint      : Label
var _backdrop  : ColorRect

# Controller navigation
var _all_buttons: Array[Button] = []
var _selected_button_index: int = 0
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

func _btn_any(paths: PackedStringArray) -> Button:
	return _find_node_any(paths) as Button

func _lbl_any(paths: PackedStringArray) -> Label:
	return _find_node_any(paths) as Label

func _ensure_fallback_layout() -> void:
	# Build a compact center window if required
	if _slots != null and _title != null and _btn_close != null and _hint != null:
		return

	# Root centerer
	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	# Window frame
	var window := Panel.new()
	window.name = "Window"
	window.custom_minimum_size = Vector2(640, 360)
	center.add_child(window)

	# Root VBox
	var root := VBoxContainer.new()
	root.name = "Root"
	root.anchor_left = 0.0
	root.anchor_right = 1.0
	root.anchor_top = 0.0
	root.anchor_bottom = 1.0
	root.offset_left = 16
	root.offset_right = -16
	root.offset_top = 16
	root.offset_bottom = -16
	window.add_child(root)

	# Header
	var header := HBoxContainer.new()
	header.name = "Header"
	root.add_child(header)

	_title = Label.new()
	_title.name = "Title"
	_title.text = "Save Game"
	header.add_child(_title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_btn_close = Button.new()
	_btn_close.name = "CloseBtn"
	_btn_close.text = "Close"
	header.add_child(_btn_close)

	_hint = Label.new()
	_hint.name = "Hint"
	_hint.text = "Choose a slot. Press Esc to close."
	root.add_child(_hint)

	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_slots = VBoxContainer.new()
	_slots.name = "Slots"
	_slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slots.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.add_child(_slots)

# --- lifecycle ----------------------------------------------------------------

func _ready() -> void:
	print("[SaveMenu] _ready() called - initializing save menu")
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Stop input from passing through
	mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop = get_node_or_null("Backdrop") as ColorRect
	if _backdrop:
		_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP

	# Resolve existing nodes first
	_slots     = _find_node_any(PATH_SLOTS)  as VBoxContainer
	_title     = _lbl_any(PATH_TITLE)
	_btn_close = _btn_any(PATH_CLOSE)
	_hint      = _lbl_any(PATH_HINT)

	print("[SaveMenu] Found nodes - slots: %s, title: %s, close: %s, hint: %s" % [
		"yes" if _slots else "no",
		"yes" if _title else "no",
		"yes" if _btn_close else "no",
		"yes" if _hint else "no"
	])

	# If anything is missing, build a fallback (safe & centered)
	_ensure_fallback_layout()

	# Final safety: default texts
	if _title: _title.text = "Save Game"
	if _hint:  _hint.text  = "Choose a slot. Press Esc to close."

	# Wire close
	if _btn_close and not _btn_close.pressed.is_connected(_on_close):
		_btn_close.pressed.connect(_on_close)

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
	# Capture ALL input to prevent it from reaching panels behind this menu
	if e is InputEventKey or e is InputEventJoypadButton or e is InputEventJoypadMotion:
		# Back button closes menu
		if e.is_action_pressed("ui_cancel") or e.is_action_pressed("menu_back"):
			_on_close()
			get_viewport().set_input_as_handled()
			return

		# Controller navigation through save slots
		if _input_cooldown <= 0 and _all_buttons.size() > 0:
			if e.is_action_pressed("move_up"):
				_navigate_buttons(-1)
				_input_cooldown = _input_cooldown_duration
				get_viewport().set_input_as_handled()
				return
			elif e.is_action_pressed("move_down"):
				_navigate_buttons(1)
				_input_cooldown = _input_cooldown_duration
				get_viewport().set_input_as_handled()
				return
			elif e.is_action_pressed("menu_accept"):
				# Activate selected button (save to slot or close)
				if _selected_button_index >= 0 and _selected_button_index < _all_buttons.size():
					_all_buttons[_selected_button_index].emit_signal("pressed")
				get_viewport().set_input_as_handled()
				return

		# Mark ALL other controller/keyboard input as handled to prevent passthrough
		get_viewport().set_input_as_handled()

# --- UI build -----------------------------------------------------------------

func _rebuild() -> void:
	for c in _slots.get_children():
		c.queue_free()

	for i in range(1, 4):
		var idx := i  # capture per-iteration
		var row: HBoxContainer = HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size.y = 36

		var lbl: Label = Label.new()
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.text = _label_for_slot(idx)
		row.add_child(lbl)

		var btn_save: Button = Button.new()
		btn_save.text = "Save"
		btn_save.custom_minimum_size.y = 28
		btn_save.focus_mode = Control.FOCUS_ALL
		btn_save.pressed.connect(func() -> void: _do_save(idx))
		row.add_child(btn_save)

		var btn_del: Button = Button.new()
		btn_del.text = "Delete"
		btn_del.custom_minimum_size.y = 28
		btn_del.focus_mode = Control.FOCUS_ALL
		btn_del.pressed.connect(func() -> void: _do_delete(idx))
		row.add_child(btn_del)

		_slots.add_child(row)

	# Setup controller navigation after slots are created
	await get_tree().process_frame
	_setup_controller_navigation()

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

	if _hint:
		_hint.text = "Saved to slot %d." % slot
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

	if _hint:
		_hint.text = ("Deleted slot %d." % slot) if ok else ("Could not delete slot %d." % slot)

	_rebuild()

func _on_close() -> void:
	print("[SaveMenu] Closing save menu")
	queue_free()

# ------------------------------------------------------------------------------
# Controller Navigation Helpers
# ------------------------------------------------------------------------------

func _setup_controller_navigation() -> void:
	"""Setup controller navigation for all save slot buttons"""
	_all_buttons.clear()

	# Collect all buttons from each slot row (Save and Delete buttons)
	for row in _slots.get_children():
		if row is HBoxContainer:
			for child in row.get_children():
				if child is Button:
					_all_buttons.append(child)

	# Add close button
	if _btn_close:
		_all_buttons.append(_btn_close)

	# Start with first button selected
	if _all_buttons.size() > 0:
		_selected_button_index = 0
		_highlight_button(_selected_button_index)

	print("[SaveMenu] Navigation setup complete. ", _all_buttons.size(), " buttons")

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
