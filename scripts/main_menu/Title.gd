extends Control

## Title (Main Menu)
## Resilient wiring for New, Continue, Load, Options, Quit.
## Finds buttons by common paths, then by name, then by label text.
## Hides Continue/Load when no saves exist.

## Neon Orchard Color Palette
const COLOR_ELECTRIC_LIME = Color(0.78, 1.0, 0.24)      # #C8FF3D
const COLOR_BUBBLE_MAGENTA = Color(1.0, 0.29, 0.85)     # #FF4AD9
const COLOR_SKY_CYAN = Color(0.30, 0.91, 1.0)           # #4DE9FF
const COLOR_CITRUS_YELLOW = Color(1.0, 0.91, 0.30)      # #FFE84D
const COLOR_PLASMA_TEAL = Color(0.13, 0.89, 0.70)       # #20E3B2
const COLOR_GRAPE_VIOLET = Color(0.54, 0.25, 0.99)      # #8A3FFC
const COLOR_NIGHT_NAVY = Color(0.04, 0.06, 0.10)        # #0A0F1A
const COLOR_INK_CHARCOAL = Color(0.07, 0.09, 0.15)      # #111827
const COLOR_MILK_WHITE = Color(0.96, 0.97, 0.98)        # #F4F7FB

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
var button_colors: Dictionary = {}  # Maps Button -> Color for highlight
var active_pulse_tween: Tween = null  # Track the pulsing animation
var selection_arrow: Label = null  # Arrow indicator for selected button
var fade_in_complete: bool = false  # Track if initial fade in is done

# Dynamic background elements
var diagonal_bands: ColorRect = null
var grid_overlay: ColorRect = null
var particle_layer: Node2D = null

# ------------------------------------------------------------------------------

func _ready() -> void:
	"""Wire buttons defensively and decorate Continue."""

	# Create neon-kawaii background
	_create_diagonal_background()
	_spawn_ambient_particles()

	# Create black overlay for fade in
	var black_overlay = ColorRect.new()
	black_overlay.color = Color(0.0, 0.0, 0.0, 1.0)
	black_overlay.z_index = 1000
	add_child(black_overlay)
	black_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Fade in the title screen from black over 0.5 seconds
	var fade_tween = create_tween()
	fade_tween.set_ease(Tween.EASE_OUT)
	fade_tween.set_trans(Tween.TRANS_CUBIC)
	fade_tween.tween_property(black_overlay, "color", Color(0.0, 0.0, 0.0, 0.0), 0.5)
	await fade_tween.finished
	black_overlay.queue_free()  # Remove overlay when done
	fade_in_complete = true

	# Create black square at top Z layer that fades out over 3 seconds
	var black_square = ColorRect.new()
	black_square.color = Color(0.0, 0.0, 0.0, 1.0)
	black_square.z_index = 2000
	add_child(black_square)
	black_square.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Fade out the black square over 3 seconds
	var square_tween = create_tween()
	square_tween.set_ease(Tween.EASE_OUT)
	square_tween.set_trans(Tween.TRANS_CUBIC)
	square_tween.tween_property(black_square, "color", Color(0.0, 0.0, 0.0, 0.0), 3.0)
	await square_tween.finished
	black_square.visible = false  # Make invisible after fade

	# Check if we're auto-loading from in-game (two-step loading process)
	if has_node("/root/aGameState"):
		if aGameState.has_meta("pending_load_from_ingame") and aGameState.get_meta("pending_load_from_ingame"):
			print("[Title] Detected pending load from in-game, auto-transitioning to main scene...")

			# Clear the metadata immediately
			aGameState.remove_meta("pending_load_from_ingame")
			aGameState.remove_meta("pending_load_payload")

			# Don't create a new loading screen - LoadMenu already created one that will handle
			# the entire transition from LoadMenu → Title → Main
			# Just transition immediately to Main scene
			get_tree().change_scene_to_file(MAIN_SCENE)
			return

	var sl: Node = get_node_or_null("/root/aSaveLoad")
	var has_save: bool = _has_any_save(sl)

	var new_btn     : Button = _find_button(NEW_PATHS,  ["NewGameButton", "New Game"])
	var continue_btn: Button = _find_button(CONTINUE_PATHS, ["ContinueButton", "Continue"])
	var load_btn    : Button = _find_button(LOAD_PATHS, ["LoadButton", "Load"])
	var options_btn : Button = _find_button(OPTIONS_PATHS, ["OptionsButton", "Options"])
	var quit_btn    : Button = _find_button(QUIT_PATHS, ["QuitButton", "Quit"])

	# Connect once with fade out wrappers
	if new_btn and not new_btn.pressed.is_connected(_on_new_game_button_pressed):
		new_btn.pressed.connect(_on_new_game_button_pressed)

	if continue_btn:
		continue_btn.visible = has_save
		if not continue_btn.pressed.is_connected(_on_continue_button_pressed):
			continue_btn.pressed.connect(_on_continue_button_pressed)

	if load_btn:
		load_btn.visible = has_save
		if not load_btn.pressed.is_connected(_on_load_button_pressed):
			load_btn.pressed.connect(_on_load_button_pressed)

	if options_btn and not options_btn.pressed.is_connected(_on_options_button_pressed):
		options_btn.pressed.connect(_on_options_button_pressed)

	if quit_btn and not quit_btn.pressed.is_connected(_on_quit_button_pressed):
		quit_btn.pressed.connect(_on_quit_button_pressed)

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

	# Apply Core Vibe styling
	_style_panel()
	_style_title()
	_style_buttons(new_btn, continue_btn, load_btn, options_btn, quit_btn)

# ------------------------------------------------------------------------------
# Button wrapper handlers (with fade out)
# ------------------------------------------------------------------------------

func _on_new_game_button_pressed() -> void:
	"""Wrapper for New Game button - fades out then activates"""
	await _fade_out_scene()
	_on_new_game_pressed()

func _on_continue_button_pressed() -> void:
	"""Wrapper for Continue button - fades out then activates"""
	await _fade_out_scene()
	_on_continue_pressed()

func _on_load_button_pressed() -> void:
	"""Wrapper for Load button - fades out then activates"""
	await _fade_out_scene()
	_on_load_pressed()

func _on_options_button_pressed() -> void:
	"""Wrapper for Options button - fades out then activates"""
	await _fade_out_scene()
	_on_options_pressed()

func _on_quit_button_pressed() -> void:
	"""Wrapper for Quit button - fades out then activates"""
	await _fade_out_scene()
	_on_quit_pressed()

func _fade_out_scene() -> void:
	"""Fade out the entire scene"""
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "modulate", Color(1.0, 1.0, 1.0, 0.0), 0.3)
	await tween.finished

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
		# Create and show loading screen
		var loading = LoadingScreen.create()
		if loading:
			get_tree().root.add_child(loading)
			loading.set_text("Loading...")
			await loading.fade_in()

		# Small delay to ensure loading screen is visible
		await get_tree().create_timer(0.1).timeout

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
			# Schedule loading screen fade-out to happen after scene change
			if loading:
				loading.call_deferred("_fade_out_and_cleanup")

			# Change scene (this will free the Title scene, so no code after this runs)
			get_tree().change_scene_to_file(MAIN_SCENE)
			return

		# Failed - restore title screen visibility and clean up loading screen
		if loading:
			# Restore title screen before fading out loading screen
			modulate = Color(1, 1, 1, 1)
			await loading.fade_out()
			loading.queue_free()

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

func _on_overlay_closed() -> void:
	"""Resume title screen when overlay closes."""
	print("[Title] Overlay closed, resuming title screen")
	process_mode = Node.PROCESS_MODE_INHERIT
	mouse_filter = Control.MOUSE_FILTER_STOP

# ------------------------------------------------------------------------------
# Overlay helper
# ------------------------------------------------------------------------------

func _open_popup_overlay(scene_path: String) -> void:
	"""Spawn scene_path as a viewport-sized overlay on the highest CanvasLayer."""
	if not ResourceLoader.exists(scene_path):
		push_error("[Title] Missing scene: %s" % scene_path)
		return

	print("[Title] Opening overlay: ", scene_path)

	# Completely block all Title input - this is the KEY fix!
	# IGNORE blocks ALL mouse events from reaching Title and its children
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Release focus from any Title button so controller input doesn't reach them
	for btn in navigable_buttons:
		if btn.has_focus():
			btn.release_focus()

	# Disable processing (stops _process, _input, etc)
	process_mode = Node.PROCESS_MODE_DISABLED

	var ps: PackedScene = load(scene_path) as PackedScene
	if ps == null:
		push_error("[Title] Could not load scene: %s" % scene_path)
		process_mode = Node.PROCESS_MODE_INHERIT  # Resume on error
		mouse_filter = Control.MOUSE_FILTER_STOP  # Restore mouse filter
		return

	var inst: Node = ps.instantiate()
	var layer: CanvasLayer = _find_or_make_overlay_layer()
	layer.add_child(inst)

	# Connect to resume when overlay closes
	if inst:
		inst.tree_exited.connect(_on_overlay_closed)
		print("[Title] Connected to overlay tree_exited signal")

	if inst is Control:
		var c: Control = inst
		c.top_level = true
		c.set_anchors_preset(Control.PRESET_FULL_RECT)
		c.z_index = 2000
		# Ensure overlay processes even when title is disabled
		c.process_mode = Node.PROCESS_MODE_ALWAYS

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
	button_colors.clear()

	# Add buttons in VISUAL order (top to bottom) and map their highlight colors
	# Continue should be first if it exists
	if continue_btn and has_save:
		navigable_buttons.append(continue_btn)
		button_colors[continue_btn] = COLOR_SKY_CYAN
	if new_btn:
		navigable_buttons.append(new_btn)
		button_colors[new_btn] = COLOR_BUBBLE_MAGENTA
	if load_btn and has_save:
		navigable_buttons.append(load_btn)
		button_colors[load_btn] = COLOR_ELECTRIC_LIME
	if options_btn:
		navigable_buttons.append(options_btn)
		button_colors[options_btn] = COLOR_CITRUS_YELLOW
	if quit_btn:
		navigable_buttons.append(quit_btn)
		button_colors[quit_btn] = COLOR_GRAPE_VIOLET

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
			# Fade out the scene before transitioning
			_fade_out_and_activate(button)

func _fade_out_and_activate(button: Button) -> void:
	"""Fade out the entire scene before activating button"""
	await _fade_out_scene()
	# Trigger the button's pressed signal
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
	"""Highlight a button with color change and pulsing animation"""
	if index < 0 or index >= navigable_buttons.size():
		return

	var button = navigable_buttons[index]
	button.grab_focus()

	# Get button's highlight color
	var color = button_colors.get(button, COLOR_ELECTRIC_LIME)

	# Create highlighted style - background becomes the assigned color, font becomes dark
	var style_highlight = StyleBoxFlat.new()
	style_highlight.bg_color = color  # Background is the highlight color
	style_highlight.border_color = color
	style_highlight.border_width_left = 3
	style_highlight.border_width_right = 3
	style_highlight.border_width_top = 3
	style_highlight.border_width_bottom = 3
	style_highlight.corner_radius_top_left = 20
	style_highlight.corner_radius_top_right = 20
	style_highlight.corner_radius_bottom_left = 20
	style_highlight.corner_radius_bottom_right = 20
	style_highlight.shadow_color = Color(color.r, color.g, color.b, 0.8)
	style_highlight.shadow_size = 12
	button.add_theme_stylebox_override("normal", style_highlight)

	# Change font color to Night Navy
	button.add_theme_color_override("font_color", COLOR_NIGHT_NAVY)

	# Set pivot offset to center for centered pulsing
	button.pivot_offset = button.size / 2

	# Create or show selection arrow
	if not selection_arrow:
		selection_arrow = Label.new()
		selection_arrow.text = "◀"
		selection_arrow.add_theme_font_size_override("font_size", 32)
		selection_arrow.add_theme_color_override("font_color", color)
		selection_arrow.z_index = 100
		selection_arrow.visible = false  # Start invisible to avoid flicker
		add_child(selection_arrow)

	# Update arrow color and position BEFORE making visible
	selection_arrow.add_theme_color_override("font_color", color)
	selection_arrow.global_position = button.global_position + Vector2(button.size.x + 20, button.size.y / 2 - 21)
	# Only show arrow after fade in is complete
	if fade_in_complete:
		selection_arrow.visible = true

	# Kill any existing pulse animation
	if active_pulse_tween:
		active_pulse_tween.kill()

	# Animate with pulsing effect (only for selected button)
	active_pulse_tween = create_tween()
	active_pulse_tween.set_loops()
	active_pulse_tween.set_parallel(false)

	# Pulse scale up
	active_pulse_tween.tween_property(button, "scale", Vector2(1.05, 1.05), 0.6).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	# Pulse scale down
	active_pulse_tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.6).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func _unhighlight_button(index: int) -> void:
	"""Remove highlight from a button - restore to original styled state"""
	if index < 0 or index >= navigable_buttons.size():
		return

	var button = navigable_buttons[index]

	# Kill any active pulse animation
	if active_pulse_tween:
		active_pulse_tween.kill()
		active_pulse_tween = null

	# Restore original scale immediately
	button.scale = Vector2.ONE

	# Set pivot offset to center (keep centered for consistency)
	button.pivot_offset = button.size / 2

	# Hide selection arrow
	if selection_arrow:
		selection_arrow.visible = false

	# Get button's original border color
	var color = button_colors.get(button, COLOR_ELECTRIC_LIME)

	# Restore normal styling (dark background, colored border)
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = COLOR_NIGHT_NAVY
	style_normal.border_color = color
	style_normal.border_width_left = 2
	style_normal.border_width_right = 2
	style_normal.border_width_top = 2
	style_normal.border_width_bottom = 2
	style_normal.corner_radius_top_left = 20
	style_normal.corner_radius_top_right = 20
	style_normal.corner_radius_bottom_left = 20
	style_normal.corner_radius_bottom_right = 20
	style_normal.shadow_color = Color(color.r, color.g, color.b, 0.4)
	style_normal.shadow_size = 4
	button.add_theme_stylebox_override("normal", style_normal)

	# Restore font color to white
	button.add_theme_color_override("font_color", COLOR_MILK_WHITE)

# ------------------------------------------------------------------------------
# Core Vibe Styling
# ------------------------------------------------------------------------------

func _create_diagonal_background() -> void:
	"""Create diagonal striped background with grid overlay"""
	# Create diagonal bands
	diagonal_bands = ColorRect.new()
	diagonal_bands.name = "DiagonalBands"
	diagonal_bands.color = COLOR_NIGHT_NAVY
	diagonal_bands.z_index = -2
	add_child(diagonal_bands)
	diagonal_bands.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Create grid overlay
	grid_overlay = ColorRect.new()
	grid_overlay.name = "GridOverlay"
	grid_overlay.color = Color(COLOR_SKY_CYAN.r, COLOR_SKY_CYAN.g, COLOR_SKY_CYAN.b, 0.06)
	grid_overlay.z_index = -1
	add_child(grid_overlay)
	grid_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

func _spawn_ambient_particles() -> void:
	"""Spawn slow-drifting neon stars and dots"""
	particle_layer = Node2D.new()
	particle_layer.name = "AmbientParticles"
	particle_layer.z_index = -1
	add_child(particle_layer)

	# Create 30 ambient particles
	for i in range(30):
		var particle = ColorRect.new()
		var size = randi_range(2, 6)
		particle.custom_minimum_size = Vector2(size, size)
		particle.size = Vector2(size, size)

		# Random neon color
		var colors = [COLOR_SKY_CYAN, COLOR_BUBBLE_MAGENTA, COLOR_ELECTRIC_LIME, COLOR_CITRUS_YELLOW]
		particle.color = colors[randi() % colors.size()]

		# Random position
		particle.position = Vector2(
			randf_range(0, get_viewport_rect().size.x),
			randf_range(0, get_viewport_rect().size.y)
		)

		particle_layer.add_child(particle)

		# Animate slow drift
		var tween = create_tween()
		tween.set_loops()
		var drift_x = randf_range(-50, 50)
		var drift_y = randf_range(-30, 30)
		var duration = randf_range(8, 15)
		tween.tween_property(particle, "position", particle.position + Vector2(drift_x, drift_y), duration)
		tween.tween_property(particle, "position", particle.position, duration)

func _style_panel() -> void:
	"""Apply Core Vibe styling to main menu panel"""
	var frame = get_node_or_null("Center/Frame")
	if not frame:
		return

	if frame is Panel:
		var panel = frame as Panel
		var style = StyleBoxFlat.new()
		style.bg_color = COLOR_INK_CHARCOAL
		style.border_color = COLOR_SKY_CYAN
		style.border_width_left = 3
		style.border_width_right = 3
		style.border_width_top = 3
		style.border_width_bottom = 3
		style.corner_radius_top_left = 12
		style.corner_radius_top_right = 12
		style.corner_radius_bottom_left = 12
		style.corner_radius_bottom_right = 12
		style.shadow_color = Color(COLOR_SKY_CYAN.r, COLOR_SKY_CYAN.g, COLOR_SKY_CYAN.b, 0.5)
		style.shadow_size = 6
		panel.add_theme_stylebox_override("panel", style)

func _style_title() -> void:
	"""Apply Core Vibe styling to PSYOKIN title"""
	var title = get_node_or_null("Center/Frame/Root/TitleLabel")
	if not title or not title is Label:
		return

	var label = title as Label
	label.add_theme_color_override("font_color", COLOR_BUBBLE_MAGENTA)
	label.add_theme_font_size_override("font_size", 48)

	# Add white outline glow
	label.add_theme_color_override("font_outline_color", COLOR_MILK_WHITE)
	label.add_theme_constant_override("outline_size", 4)

func _style_buttons(new_btn: Button, continue_btn: Button, load_btn: Button, options_btn: Button, quit_btn: Button) -> void:
	"""Apply pill capsule styling to all buttons"""
	var buttons = [new_btn, continue_btn, load_btn, options_btn, quit_btn]
	var colors = [COLOR_BUBBLE_MAGENTA, COLOR_SKY_CYAN, COLOR_ELECTRIC_LIME, COLOR_CITRUS_YELLOW, COLOR_INK_CHARCOAL]

	for i in range(buttons.size()):
		var btn = buttons[i]
		if not btn:
			continue

		var color = colors[i % colors.size()]

		# Normal state - pill capsule with dark fill and neon border
		var style_normal = StyleBoxFlat.new()
		style_normal.bg_color = COLOR_NIGHT_NAVY
		style_normal.border_color = color
		style_normal.border_width_left = 2
		style_normal.border_width_right = 2
		style_normal.border_width_top = 2
		style_normal.border_width_bottom = 2
		style_normal.corner_radius_top_left = 20
		style_normal.corner_radius_top_right = 20
		style_normal.corner_radius_bottom_left = 20
		style_normal.corner_radius_bottom_right = 20
		style_normal.shadow_color = Color(color.r, color.g, color.b, 0.4)
		style_normal.shadow_size = 4
		btn.add_theme_stylebox_override("normal", style_normal)

		# Hover state - brighter glow
		var style_hover = style_normal.duplicate()
		style_hover.shadow_color = Color(color.r, color.g, color.b, 0.7)
		style_hover.shadow_size = 8
		btn.add_theme_stylebox_override("hover", style_hover)

		# Pressed state - inner glow
		var style_pressed = style_normal.duplicate()
		style_pressed.bg_color = Color(color.r, color.g, color.b, 0.2)
		btn.add_theme_stylebox_override("pressed", style_pressed)

		# Focus state (controller navigation) - thick border
		var style_focus = style_normal.duplicate()
		style_focus.border_width_left = 4
		style_focus.border_width_right = 4
		style_focus.border_width_top = 4
		style_focus.border_width_bottom = 4
		style_focus.shadow_color = Color(color.r, color.g, color.b, 0.8)
		style_focus.shadow_size = 12
		btn.add_theme_stylebox_override("focus", style_focus)

		# Text color - Milk White
		btn.add_theme_color_override("font_color", COLOR_MILK_WHITE)
		btn.add_theme_color_override("font_hover_color", COLOR_MILK_WHITE)
		btn.add_theme_color_override("font_pressed_color", COLOR_MILK_WHITE)
		btn.add_theme_color_override("font_focus_color", COLOR_MILK_WHITE)
