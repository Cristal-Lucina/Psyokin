extends Control

## Title (Main Menu)
## Resilient wiring for New, Continue, Load, Options, Quit.
## Finds buttons by common paths, then by name, then by label text.
## Hides Continue/Load when no saves exist.

const SAVE_DIR               : String = "user://saves"
const MAIN_SCENE             : String = "res://scenes/main/Main.tscn"
const OPTIONS_SCENE          : String = "res://scenes/main_menu/Options.tscn"
const LOAD_MENU_SCENE        : String = "res://scenes/ui/save/LoadMenu.tscn"
const CHARACTER_CREATION_SCENE: String = "res://scenes/creation/CharacterCreation.tscn"

# Common candidate paths for buttons (probe in this order)
const NEW_PATHS      : PackedStringArray = [
	"MarginContainer/VBoxContainer/NewGameButton",
	"NewGameButton"
]
const CONTINUE_PATHS : PackedStringArray = [
	"MarginContainer/VBoxContainer/ContinueButton",
	"ContinueButton"
]
const LOAD_PATHS     : PackedStringArray = [
	"MarginContainer/VBoxContainer/LoadButton",
	"LoadButton"
]
const OPTIONS_PATHS  : PackedStringArray = [
	"MarginContainer/VBoxContainer/OptionsButton",
	"OptionsButton"
]
const QUIT_PATHS     : PackedStringArray = [
	"MarginContainer/VBoxContainer/QuitButton",
	"QuitButton"
]

# Controller navigation
var navigable_buttons: Array[Button] = []
var selected_button_index: int = 0
var input_cooldown: float = 0.0
var input_cooldown_duration: float = 0.15  # 150ms between inputs

# ------------------------------------------------------------------------------

func _ready() -> void:
	"""Wire buttons defensively and decorate Continue."""
	var sl: Node = get_node_or_null("/root/aSaveLoad")
	var has_save: bool = _has_any_save(sl)

	var new_btn     : Button = _find_button(NEW_PATHS,  ["NewGameButton", "New Game"])
	var continue_btn: Button = _find_button(CONTINUE_PATHS, ["ContinueButton", "Continue"])
	var load_btn    : Button = _find_button(LOAD_PATHS, ["LoadButton", "Load"])
	var options_btn : Button = _find_button(OPTIONS_PATHS, ["OptionsButton", "Options"])
	var quit_btn    : Button = _find_button(QUIT_PATHS, ["QuitButton", "Quit"])

	# Connect once
	if new_btn and not new_btn.pressed.is_connected(_on_new_game_pressed):
		new_btn.pressed.connect(_on_new_game_pressed)

	if continue_btn:
		continue_btn.visible = has_save
		if not continue_btn.pressed.is_connected(_on_continue_pressed):
			continue_btn.pressed.connect(_on_continue_pressed)

	if load_btn:
		load_btn.visible = has_save
		if not load_btn.pressed.is_connected(_on_load_pressed):
			load_btn.pressed.connect(_on_load_pressed)

	if options_btn and not options_btn.pressed.is_connected(_on_options_pressed):
		options_btn.pressed.connect(_on_options_pressed)

	if quit_btn and not quit_btn.pressed.is_connected(_on_quit_pressed):
		quit_btn.pressed.connect(_on_quit_pressed)

	# Decorate Continue with latest save summary (nice UX)
	if continue_btn and has_save:
		var latest_slot: int = _find_latest_slot(sl)
		if latest_slot >= 0:
			var meta: Dictionary = _safe_get_slot_meta(sl, latest_slot)
			if not meta.is_empty():
				var label: String = String(meta.get("summary", String(meta.get("label", ""))))
				if label != "":
					continue_btn.text = "Continue - %s" % label

	# Setup controller navigation
	_setup_controller_navigation(new_btn, continue_btn, load_btn, options_btn, quit_btn, has_save)

# ------------------------------------------------------------------------------
# Button handlers
# ------------------------------------------------------------------------------

func _on_new_game_pressed() -> void:
	"""Start a new game and go to Character Creation."""
	if has_node("/root/aGameState"):
		aGameState.new_game()

	# Prefer router if it exposes a creation jump
	if has_node("/root/aSceneRouter") and aSceneRouter.has_method("goto_creation"):
		aSceneRouter.goto_creation()
		return

	# Direct load of the creation scene, with fallback to Main
	if ResourceLoader.exists(CHARACTER_CREATION_SCENE):
		get_tree().change_scene_to_file(CHARACTER_CREATION_SCENE)
	else:
		push_error("[Title] Missing CharacterCreation scene: %s" % CHARACTER_CREATION_SCENE)
		get_tree().change_scene_to_file(MAIN_SCENE)

func _on_continue_pressed() -> void:
	"""Load the most recent slot, or fall back to Load menu."""
	var sl: Node = get_node_or_null("/root/aSaveLoad")
	var slot: int = _find_latest_slot(sl)
	if slot >= 0:
		var ok: bool = false
		if has_node("/root/aGameState") and aGameState.has_method("load_from_slot"):
			ok = aGameState.load_from_slot(slot)
		if not ok and sl != null and sl.has_method("load_game"):
			var payload_v: Variant = sl.call("load_game", slot)
			var payload: Dictionary = {}
			if typeof(payload_v) == TYPE_DICTIONARY:
				payload = payload_v as Dictionary
			if not payload.is_empty() and has_node("/root/aGameState") and aGameState.has_method("apply_loaded_save"):
				aGameState.apply_loaded_save(payload)
				ok = true
		if ok:
			get_tree().change_scene_to_file(MAIN_SCENE)
			return
		push_warning("[Title] Continue failed for slot %d; opening Load menu." % [slot])

	_on_load_pressed()

func _on_load_pressed() -> void:
	"""Open the Load menu as a viewport-sized overlay."""
	_open_popup_overlay(LOAD_MENU_SCENE)

func _on_options_pressed() -> void:
	"""Open Options as overlay."""
	_open_popup_overlay(OPTIONS_SCENE)

func _on_quit_pressed() -> void:
	"""Quit the game/app."""
	get_tree().quit()

# ------------------------------------------------------------------------------
# Overlay helper
# ------------------------------------------------------------------------------

func _open_popup_overlay(scene_path: String) -> void:
	"""Spawn scene_path as a viewport-sized overlay on the highest CanvasLayer."""
	if not ResourceLoader.exists(scene_path):
		push_error("[Title] Missing scene: %s" % scene_path)
		return

	# Router preferred if present
	if has_node("/root/aSceneRouter") and aSceneRouter.has_method("open_popup"):
		aSceneRouter.open_popup(scene_path, get_tree().current_scene)
		return

	var ps: PackedScene = load(scene_path) as PackedScene
	if ps == null:
		push_error("[Title] Could not load scene: %s" % scene_path)
		return

	var inst: Node = ps.instantiate()
	var layer: CanvasLayer = _find_or_make_overlay_layer()
	layer.add_child(inst)

	if inst is Control:
		var c: Control = inst
		c.top_level = true
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.z_index = 2000

func _find_or_make_overlay_layer() -> CanvasLayer:
	"""Return the highest CanvasLayer in the current scene, or create one."""
	var scene: Node = get_tree().current_scene
	var best: CanvasLayer = null
	for child in scene.get_children():
		if child is CanvasLayer:
			var cl: CanvasLayer = child
			if best == null or cl.layer > best.layer:
				best = cl
	if best == null:
		best = CanvasLayer.new()
		best.name = "Overlays"
		best.layer = 100
		scene.add_child(best)
	return best

# ------------------------------------------------------------------------------
# SaveLoad safe helpers
# ------------------------------------------------------------------------------

func _safe_list_slots(sl: Node) -> Array:
	"""Call sl.list_slots() safely and return an Array (or [])."""
	var out: Array = []
	if sl != null and sl.has_method("list_slots"):
		var v: Variant = sl.call("list_slots")
		if typeof(v) == TYPE_ARRAY:
			out = v as Array
	return out

func _safe_get_slot_meta(sl: Node, idx: int) -> Dictionary:
	"""Call sl.get_slot_meta(idx) safely and return a Dictionary (or {})."""
	var meta: Dictionary = {}
	if sl != null and sl.has_method("get_slot_meta"):
		var v: Variant = sl.call("get_slot_meta", idx)
		if typeof(v) == TYPE_DICTIONARY:
			meta = v as Dictionary
	return meta

# ------------------------------------------------------------------------------
# Save queries
# ------------------------------------------------------------------------------

func _has_any_save(sl: Node) -> bool:
	"""True if any saves exist (SaveLoad preferred, dir scan fallback)."""
	var slots: Array = _safe_list_slots(sl)
	if slots.size() > 0:
		return true

	var d: DirAccess = DirAccess.open(SAVE_DIR)
	if d == null:
		return false
	for file_name in d.get_files():
		if file_name.begins_with("slot_") and file_name.ends_with(".json"):
			return true
	return false

func _find_latest_slot(sl: Node) -> int:
	"""Most recent save by timestamp; -1 if none."""
	var latest_slot: int = -1
	var latest_ts: int = -1

	var slots: Array = _safe_list_slots(sl)
	if slots.size() > 0:
		for s in slots:
			var idx: int = int(s)
			var meta: Dictionary = _safe_get_slot_meta(sl, idx)
			if not meta.is_empty() and bool(meta.get("exists", false)):
				var ts: int = int(meta.get("ts", 0))
				if ts > latest_ts:
					latest_ts = ts
					latest_slot = idx
		return latest_slot

	# Fallback: scan files and read "ts"
	var d2: DirAccess = DirAccess.open(SAVE_DIR)
	if d2 == null:
		return -1
	for fn in d2.get_files():
		if fn.begins_with("slot_") and fn.ends_with(".json"):
			var idx2: int = int(fn.substr(5, fn.length() - 10))
			var ts2: int = _read_ts_from_file("%s/%s" % [SAVE_DIR, fn])
			if ts2 > latest_ts:
				latest_ts = ts2
				latest_slot = idx2
	return latest_slot

func _read_ts_from_file(path: String) -> int:
	"""Read unix ts from save file (top-level or payload.ts)."""
	if not FileAccess.file_exists(path):
		return 0
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return 0
	var d: Dictionary = parsed
	var ts: int = int(d.get("ts", 0))
	if ts == 0 and d.has("payload") and typeof(d["payload"]) == TYPE_DICTIONARY:
		ts = int((d["payload"] as Dictionary).get("ts", 0))
	return ts

# ------------------------------------------------------------------------------
# Node finders
# ------------------------------------------------------------------------------

func _find_node_any(paths: PackedStringArray) -> Node:
	"""Try exact paths first, then deep-search by last segment name."""
	for p in paths:
		var n: Node = get_node_or_null(p)
		if n:
			return n
	for p in paths:
		var name_only: String = p.get_file()
		var f := find_child(name_only, true, false)
		if f:
			return f
	return null

func _find_button(paths: PackedStringArray, name_or_text: PackedStringArray) -> Button:
	"""Find a button by path, then by node name, then by its displayed text."""
	var b: Button = _find_node_any(paths) as Button
	if b:
		return b

	# Search by node name anywhere
	for nm in name_or_text:
		var by_name := find_child(nm, true, false) as Button
		if by_name:
			return by_name

	# Search by displayed text across all child buttons
	var buttons: Array = []
	_collect_buttons(self, buttons)

	for candidate in buttons:
		var bc: Button = candidate as Button
		if bc and name_or_text.has(bc.text):
			return bc
	return null

func _collect_buttons(n: Node, out: Array) -> void:
	"""Collect all Buttons under n into out (recursive)."""
	for c in n.get_children():
		if c is Button:
			out.append(c)
		_collect_buttons(c, out)

# ------------------------------------------------------------------------------
# Controller Navigation
# ------------------------------------------------------------------------------

func _setup_controller_navigation(new_btn: Button, continue_btn: Button, load_btn: Button, options_btn: Button, quit_btn: Button, has_save: bool) -> void:
	"""Setup controller navigation for menu buttons"""
	navigable_buttons.clear()

	# Add buttons in VISUAL order (top to bottom)
	# Continue should be first if it exists
	if continue_btn and has_save:
		navigable_buttons.append(continue_btn)
	if new_btn:
		navigable_buttons.append(new_btn)
	if load_btn and has_save:
		navigable_buttons.append(load_btn)
	if options_btn:
		navigable_buttons.append(options_btn)
	if quit_btn:
		navigable_buttons.append(quit_btn)

	# Start at Continue if save exists, else New Game
	if navigable_buttons.size() > 0:
		if has_save and continue_btn:
			# Continue is now at index 0
			selected_button_index = 0
		else:
			# New Game is at index 0 (no save)
			selected_button_index = 0
		_highlight_button(selected_button_index)

func _process(delta: float) -> void:
	"""Handle input cooldown"""
	if input_cooldown > 0:
		input_cooldown -= delta

func _input(event: InputEvent) -> void:
	"""Handle controller input for menu navigation"""
	if navigable_buttons.is_empty():
		return

	if input_cooldown > 0:
		return

	# Navigate up/down
	if event.is_action_pressed(aInputManager.ACTION_MOVE_UP):
		_navigate_menu(-1)
		input_cooldown = input_cooldown_duration
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(aInputManager.ACTION_MOVE_DOWN):
		_navigate_menu(1)
		input_cooldown = input_cooldown_duration
		get_viewport().set_input_as_handled()
	# Accept button activates selected button
	elif event.is_action_pressed(aInputManager.ACTION_ACCEPT):
		if selected_button_index >= 0 and selected_button_index < navigable_buttons.size():
			var button = navigable_buttons[selected_button_index]
			# Mark input as handled BEFORE triggering button (scene may change)
			get_viewport().set_input_as_handled()
			# Trigger the button's pressed signal by emitting it
			# Note: This may destroy this node if it changes scenes, so nothing after this line will execute
			button.emit_signal("pressed")

func _navigate_menu(direction: int) -> void:
	"""Navigate menu with controller"""
	if navigable_buttons.is_empty():
		return

	_unhighlight_button(selected_button_index)

	selected_button_index += direction
	if selected_button_index < 0:
		selected_button_index = navigable_buttons.size() - 1
	elif selected_button_index >= navigable_buttons.size():
		selected_button_index = 0

	_highlight_button(selected_button_index)

func _highlight_button(index: int) -> void:
	"""Highlight a button - resets all buttons first to ensure only one is selected"""
	# First, unhighlight ALL buttons to ensure only one is highlighted
	for i in range(navigable_buttons.size()):
		navigable_buttons[i].modulate = Color(1.0, 1.0, 1.0, 1.0)

	# Now highlight the selected button
	if index >= 0 and index < navigable_buttons.size():
		var button = navigable_buttons[index]
		button.modulate = Color(1.2, 1.2, 0.8, 1.0)
		button.grab_focus()

func _unhighlight_button(index: int) -> void:
	"""Remove highlight from a button"""
	if index >= 0 and index < navigable_buttons.size():
		var button = navigable_buttons[index]
		button.modulate = Color(1.0, 1.0, 1.0, 1.0)
